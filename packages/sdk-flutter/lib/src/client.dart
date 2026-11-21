import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'models.dart';
import 'storage.dart';

const sdkVersion = '0.1.0';

/// Mengambil lokasi perangkat saat SOS ditekan dan selama laporan aktif.
/// Contoh dengan paket `geolocator`:
/// ```dart
/// locationProvider: () async {
///   final p = await Geolocator.getCurrentPosition();
///   return SosLocation(lat: p.latitude, lng: p.longitude, accuracyM: p.accuracy);
/// }
/// ```
typedef LocationProvider = Future<SosLocation?> Function();

/// Klien SiagaSOS. Satu instance per aplikasi; panggil [dispose] saat logout.
///
/// ```dart
/// final sos = SiagaSOS(apiKey: 'pk_test_...', bundleId: 'com.perusahaan.app', user: SosUser(ref: uid, name: nama));
/// final r = await sos.trigger(category: 'kriminal');
/// sos.status.listen((r) => print(r.status));
/// await sos.attach(r.localId, bytes, contentType: 'image/jpeg');
/// ```
class SiagaSOS {
  SiagaSOS({
    required this.apiKey,
    required this.bundleId,
    this.sourceKey,
    this.user,
    String baseUrl = 'https://api.siagasos.id',
    this.liveLocation = true,
    this.pollInterval = const Duration(seconds: 4),
    this.locationTimeout = const Duration(seconds: 8),
    this.locationProvider,
    http.Client? httpClient,
    QueueStore? queueStore,
  })  : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _http = httpClient ?? http.Client(),
        _queue = queueStore ?? SharedPrefsQueueStore('siagasos.queue.${apiKey.length > 16 ? apiKey.substring(0, 16) : apiKey}') {
    final m = RegExp(r'^pk_(live|test)_').firstMatch(apiKey);
    if (m == null) {
      throw const SiagaSOSError(0, 'invalid_api_key', 'apiKey harus publishable key (pk_live_... / pk_test_...)');
    }
    mode = m.group(1) == 'live' ? SosMode.live : SosMode.test;
    // kirim sisa antrian dari sesi sebelumnya
    scheduleMicrotask(flush);
  }

  final String apiKey;
  /// Package name (Android) / bundle identifier (iOS). Harus terdaftar di allowed_bundle_ids app.
  final String bundleId;
  final String? sourceKey;
  final SosUser? user;
  final String baseUrl;
  final bool liveLocation;
  final Duration pollInterval;
  final Duration locationTimeout;
  final LocationProvider? locationProvider;
  late final SosMode mode;

  final http.Client _http;
  final QueueStore _queue;
  final _reports = <String, ActiveReport>{};
  final _pollers = <String, Timer>{};
  final _locators = <String, Timer>{};
  Future<SdkConfig>? _config;
  Timer? _retry;
  Duration _retryDelay = const Duration(seconds: 2);
  bool _flushing = false;
  bool _disposed = false;

  final _statusCtl = StreamController<ActiveReport>.broadcast();
  final _queuedCtl = StreamController<ActiveReport>.broadcast();
  final _sentCtl = StreamController<ActiveReport>.broadcast();
  final _errorCtl = StreamController<SiagaSOSError>.broadcast();

  /// Setiap perubahan status laporan (termasuk `queued`).
  Stream<ActiveReport> get status => _statusCtl.stream;
  /// Laporan masuk antrian offline (tidak ada sinyal).
  Stream<ActiveReport> get queued => _queuedCtl.stream;
  /// Laporan berhasil diterima server.
  Stream<ActiveReport> get sent => _sentCtl.stream;
  /// Error permanen (kunci salah, bundle tidak terdaftar, dll.).
  Stream<SiagaSOSError> get errors => _errorCtl.stream;

  List<ActiveReport> get activeReports => _reports.values.where((r) => !r.status.isTerminal).toList();

  // ------------------------------------------------------------------ HTTP
  Map<String, String> get _headers => {'X-SOS-Key': apiKey, 'X-SOS-Bundle': bundleId, 'Content-Type': 'application/json'};

  Future<Map<String, dynamic>> _request(String method, String path, {Object? body, String? idempotencyKey}) async {
    final req = http.Request(method, Uri.parse('$baseUrl$path'))..headers.addAll(_headers);
    if (idempotencyKey != null) req.headers['Idempotency-Key'] = idempotencyKey;
    if (body != null) req.body = jsonEncode(body);
    http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 20)));
    } on TimeoutException {
      throw const SiagaSOSError(0, 'timeout', 'Server tidak merespons');
    } catch (e) {
      throw SiagaSOSError(0, 'network_error', 'Tidak ada koneksi: $e');
    }
    final Map<String, dynamic> data = res.body.isEmpty ? {} : (jsonDecode(res.body) as Map<String, dynamic>);
    if (res.statusCode >= 400) {
      final err = (data['error'] as Map<String, dynamic>?) ?? const {};
      throw SiagaSOSError(res.statusCode, err['code'] as String? ?? 'http_error', err['message'] as String? ?? 'HTTP ${res.statusCode}');
    }
    return data;
  }

  /// Konfigurasi tombol dari portal (kategori, teks, durasi tahan, nomor cadangan). Di-cache.
  Future<SdkConfig> getConfig() => _config ??= _request('GET', '/v1/sdk/config').then(SdkConfig.fromJson).catchError((Object e) {
        _config = null;
        throw e;
      });

  // ------------------------------------------------------------------ trigger + antrian
  /// Kirim SOS. Tidak pernah melempar karena jaringan: bila offline, laporan masuk antrian
  /// (status [SosStatus.queued]) dan dikirim otomatis. Error permanen dilempar sebagai [SiagaSOSError].
  Future<ActiveReport> trigger({String category = 'general', String? message, Map<String, dynamic>? metadata}) async {
    SosLocation? loc;
    try {
      loc = await locationProvider?.call().timeout(locationTimeout);
    } catch (_) {
      loc = null; // tanpa lokasi tetap terkirim
    }
    final item = <String, dynamic>{
      'localId': _uuid(),
      'idem': _uuid(),
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'body': {
        'category': category,
        if (message != null) 'message': message,
        if (sourceKey != null) 'source_key': sourceKey,
        if (loc != null) 'location': loc.toJson(),
        if (user != null) 'reporter': user!.toJson(),
        if (metadata != null) 'metadata': metadata,
        'device': {'platform': _platform(), 'sdk_version': 'flutter-$sdkVersion'},
        'client_created_at': DateTime.now().toUtc().toIso8601String(),
      },
    };
    final queued = ActiveReport(
      localId: item['localId'] as String,
      id: null,
      status: SosStatus.queued,
      statusMessage: 'Menunggu sinyal, laporan akan dikirim otomatis.',
      mode: mode,
      category: category,
      createdAt: DateTime.now(),
    );
    _reports[queued.localId] = queued;
    await _queue.save([...await _queue.load(), item]);
    try {
      return await _send(item);
    } on SiagaSOSError catch (e) {
      if (!e.isRetryable) {
        await _removeFromQueue(queued.localId);
        _reports.remove(queued.localId);
        _errorCtl.add(e);
        rethrow;
      }
      _queuedCtl.add(queued);
      _statusCtl.add(queued);
      _scheduleRetry();
      return queued;
    }
  }

  Future<ActiveReport> _send(Map<String, dynamic> item) async {
    final data = await _request('POST', '/v1/sdk/reports', body: item['body'], idempotencyKey: item['idem'] as String);
    final localId = item['localId'] as String;
    await _removeFromQueue(localId);
    final prev = _reports[localId];
    final r = ActiveReport(
      localId: localId,
      id: data['id'] as String,
      status: sosStatusFromApi(data['status'] as String),
      statusMessage: data['status_message'] as String?,
      mode: mode,
      category: (item['body'] as Map)['category'] as String,
      createdAt: prev?.createdAt ?? DateTime.now(),
    );
    _reports[localId] = r;
    _sentCtl.add(r);
    _statusCtl.add(r);
    _track(r);
    return r;
  }

  Future<void> _removeFromQueue(String localId) async =>
      _queue.save((await _queue.load()).where((i) => i['localId'] != localId).toList());

  /// Kirim ulang antrian sekarang (dipanggil otomatis dengan backoff; panggil juga saat app kembali online/foreground).
  Future<void> flush() async {
    if (_flushing || _disposed) return;
    _flushing = true;
    try {
      for (final item in await _queue.load()) {
        final localId = item['localId'] as String;
        _reports.putIfAbsent(localId, () => ActiveReport(
              localId: localId, id: null, status: SosStatus.queued, mode: mode,
              category: (item['body'] as Map)['category'] as String? ?? 'general',
              createdAt: DateTime.tryParse(item['createdAt'] as String? ?? '') ?? DateTime.now()));
        try {
          await _send(item);
          _retryDelay = const Duration(seconds: 2);
        } on SiagaSOSError catch (e) {
          if (e.isRetryable) {
            _scheduleRetry();
            return;
          }
          await _removeFromQueue(localId);
          _reports.remove(localId);
          _errorCtl.add(e);
        }
      }
    } finally {
      _flushing = false;
    }
  }

  void _scheduleRetry() {
    if (_retry?.isActive ?? false) return;
    _retry = Timer(_retryDelay, flush);
    final next = _retryDelay * 2;
    _retryDelay = next > const Duration(seconds: 60) ? const Duration(seconds: 60) : next;
  }

  // ------------------------------------------------------------------ status + lokasi live
  void _track(ActiveReport r) {
    if (r.status.isTerminal || _disposed) return;
    _pollers[r.localId] ??= Timer.periodic(pollInterval, (_) async {
      try {
        _update(r.localId, await _request('GET', '/v1/sdk/reports/${r.id}'));
      } catch (_) {/* coba lagi di tick berikutnya */}
    });
    if (liveLocation && locationProvider != null && !_locators.containsKey(r.localId)) {
      getConfig().then((cfg) {
        if (_disposed || _locators.containsKey(r.localId)) return;
        _locators[r.localId] = Timer.periodic(Duration(seconds: cfg.liveLocationIntervalS), (_) => _sendLocation(r.localId));
      }).catchError((_) {});
    }
  }

  Future<void> _sendLocation(String localId) async {
    final r = _reports[localId];
    if (r?.id == null) return;
    try {
      final loc = await locationProvider!().timeout(locationTimeout);
      if (loc == null) return;
      final res = await _request('POST', '/v1/sdk/reports/${r!.id}/locations',
          body: {...loc.toJson(), 'recorded_at': DateTime.now().toUtc().toIso8601String()});
      if (res['accepted'] == false) _locators.remove(localId)?.cancel();
    } catch (_) {}
  }

  ActiveReport _update(String localId, Map<String, dynamic> data) {
    final cur = _reports[localId]!;
    final next = cur.copyWith(
        id: data['id'] as String?, status: sosStatusFromApi(data['status'] as String), statusMessage: data['status_message'] as String?);
    _reports[localId] = next;
    if (next.status != cur.status || next.statusMessage != cur.statusMessage) _statusCtl.add(next);
    if (next.status.isTerminal) _stop(localId);
    return next;
  }

  void _stop(String localId) {
    _pollers.remove(localId)?.cancel();
    _locators.remove(localId)?.cancel();
  }

  // ------------------------------------------------------------------ cancel / getReport
  /// Batalkan laporan (salah tekan). Hanya bisa selama status masih `open`; error `cannot_cancel` bila sudah diterima petugas.
  Future<ActiveReport?> cancel(String idOrLocalId, {String? reason}) async {
    final entry = _find(idOrLocalId);
    if (entry != null && entry.id == null) {
      await _removeFromQueue(entry.localId);
      final c = entry.copyWith(status: SosStatus.cancelled, statusMessage: 'Laporan dibatalkan.');
      _reports[entry.localId] = c;
      _statusCtl.add(c);
      return c;
    }
    final id = entry?.id ?? idOrLocalId;
    final data = await _request('POST', '/v1/sdk/reports/$id/cancel', body: {if (reason != null) 'reason': reason});
    return entry == null ? null : _update(entry.localId, data);
  }

  Future<Map<String, dynamic>> getReport(String id) => _request('GET', '/v1/sdk/reports/$id');

  ActiveReport? _find(String idOrLocalId) =>
      _reports[idOrLocalId] ?? _reports.values.where((r) => r.id == idOrLocalId).firstOrNull;

  // ------------------------------------------------------------------ lampiran
  /// Lampirkan foto/video/suara. File diunggah langsung ke storage lewat URL bertanda tangan.
  /// Bila laporan masih di antrian offline, menunggu sampai terkirim (maks. [waitTimeout]).
  Future<MediaPublic> attach(
    String idOrLocalId,
    Uint8List bytes, {
    required String contentType,
    double? durationS,
    void Function(double ratio)? onProgress,
    Duration waitTimeout = const Duration(minutes: 2),
  }) async {
    final id = await _waitForServerId(idOrLocalId, waitTimeout);
    final out = await _request('POST', '/v1/sdk/reports/$id/media',
        body: {'content_type': contentType, 'size_bytes': bytes.length, if (durationS != null) 'duration_s': durationS});
    final upload = out['upload'] as Map<String, dynamic>;
    final req = http.StreamedRequest('PUT', Uri.parse(upload['url'] as String))
      ..headers.addAll((upload['headers'] as Map).cast<String, String>())
      ..contentLength = bytes.length;
    final sending = _http.send(req);
    const chunk = 64 * 1024;
    for (var i = 0; i < bytes.length; i += chunk) {
      req.sink.add(bytes.sublist(i, min(i + chunk, bytes.length)));
      onProgress?.call(min(i + chunk, bytes.length) / bytes.length);
      await Future<void>.delayed(Duration.zero);
    }
    await req.sink.close();
    final res = await sending.timeout(const Duration(minutes: 5));
    await res.stream.drain<void>();
    if (res.statusCode >= 300) throw SiagaSOSError(res.statusCode, 'upload_failed', 'Upload gagal (${res.statusCode})');
    onProgress?.call(1);
    final media = (out['media'] as Map<String, dynamic>)['id'] as String;
    return MediaPublic.fromJson(await _request('POST', '/v1/sdk/reports/$id/media/$media/complete'));
  }

  Future<String> _waitForServerId(String idOrLocalId, Duration timeout) async {
    final r = _find(idOrLocalId);
    if (r == null) return idOrLocalId; // id server dari sesi lain
    if (r.id != null) return r.id!;
    final sent = await this.sent.firstWhere((s) => s.localId == r.localId).timeout(timeout,
        onTimeout: () => throw const SiagaSOSError(0, 'not_sent', 'Laporan belum terkirim; lampiran dibatalkan'));
    return sent.id!;
  }

  /// Hentikan polling, lokasi live, dan retry. Antrian tetap tersimpan untuk sesi berikutnya.
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    for (final id in [..._pollers.keys, ..._locators.keys]) {
      _stop(id);
    }
    _statusCtl.close();
    _queuedCtl.close();
    _sentCtl.close();
    _errorCtl.close();
  }

  static final _rnd = Random.secure();
  static String _uuid() {
    final b = List<int>.generate(16, (_) => _rnd.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  static String _platform() => switch (defaultTargetPlatform) {
        TargetPlatform.android => 'android',
        TargetPlatform.iOS => 'ios',
        _ => 'other',
      };
}
