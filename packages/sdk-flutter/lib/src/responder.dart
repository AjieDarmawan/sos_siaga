import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

/// Tipe data push FCM alarm SOS untuk satpam (`data.type`). Payload lain: report_id, reporter_name, place, lat, lng, created_at.
const responderPushType = 'siagasos_sos';

/// Id channel notifikasi Android yang dipakai server untuk push SOS. App wajib membuat channel ini
/// (importance max, suara `res/raw/sos_siren`) supaya sirene tetap bunyi saat app di latar belakang.
const responderPushChannelId = 'siagasos_sos';

/// Hasil minta OTP. [devCode] hanya terisi di kunci test / server dev saat WhatsApp tidak terkirim.
class ResponderOtp {
  const ResponderOtp({required this.sent, required this.expiresIn, this.devCode});
  final bool sent;
  final Duration expiresIn;
  final String? devCode;
}

/// Kasir / outlet yang mencantumkan nomor satpam ini di Nomor Darurat.
class GuardedReporter {
  const GuardedReporter({this.reporterName, this.sourceLabel, required this.active});
  final String? reporterName;
  final String? sourceLabel;
  final bool active;
}

class ResponderProfile {
  const ResponderProfile({required this.phone, required this.name, this.appName, this.guarding = const []});
  final String phone;
  final String name;
  final String? appName;
  final List<GuardedReporter> guarding;

  factory ResponderProfile.fromJson(Map<String, dynamic> j) => ResponderProfile(
        phone: j['phone'] as String,
        name: j['name'] as String,
        appName: j['app_name'] as String?,
        guarding: ((j['guarding'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map((g) => GuardedReporter(
                reporterName: g['reporter_name'] as String?, sourceLabel: g['source_label'] as String?, active: g['active'] as bool? ?? true))
            .toList(),
      );
}

/// Laporan SOS dari sudut pandang satpam.
class ResponderReport {
  const ResponderReport({
    required this.id,
    required this.status,
    required this.mode,
    required this.category,
    required this.createdAt,
    this.reporterName,
    this.reporterPhone,
    this.sourceLabel,
    this.message,
    this.location,
    this.acknowledgedAt,
    this.resolvedAt,
  });

  final String id;
  final SosStatus status;
  final SosMode mode;
  final String category;
  final DateTime createdAt;
  final String? reporterName;
  final String? reporterPhone;
  final String? sourceLabel;
  final String? message;
  final SosLocation? location;
  final DateTime? acknowledgedAt;
  final DateTime? resolvedAt;

  /// Link Google Maps lokasi terakhir pelapor, null bila tanpa lokasi.
  Uri? get mapsUri => location == null ? null : Uri.parse('https://www.google.com/maps?q=${location!.lat},${location!.lng}');

  factory ResponderReport.fromJson(Map<String, dynamic> j) {
    final loc = j['location'] as Map<String, dynamic>?;
    DateTime? t(String k) => j[k] == null ? null : DateTime.tryParse(j[k] as String)?.toLocal();
    return ResponderReport(
      id: j['id'] as String,
      status: sosStatusFromApi(j['status'] as String),
      mode: j['mode'] == 'test' ? SosMode.test : SosMode.live,
      category: j['category'] as String? ?? 'general',
      createdAt: t('created_at') ?? DateTime.now(),
      reporterName: j['reporter_name'] as String?,
      reporterPhone: j['reporter_phone'] as String?,
      sourceLabel: j['source_label'] as String?,
      message: j['message'] as String?,
      location: loc == null
          ? null
          : SosLocation(lat: (loc['lat'] as num).toDouble(), lng: (loc['lng'] as num).toDouble(), accuracyM: (loc['accuracy_m'] as num?)?.toDouble()),
      acknowledgedAt: t('acknowledged_at'),
      resolvedAt: t('resolved_at'),
    );
  }
}

/// Status yang boleh diberikan satpam.
enum ResponderAction { acknowledged, inProgress, resolved, falseAlarm }

/// Klien untuk app satpam / penerima darurat. Login ([login], atau OTP lewat [requestOtp] + [verify]) dengan nomor WhatsApp yang tercantum di Nomor Darurat pelapor
/// ([SiagaSOS.setEmergencyContacts]), lalu menerima push alarm FCM setiap SOS yang menyebut nomornya.
///
/// ```dart
/// final r = SiagaSOSResponder(apiKey: 'pk_live_...', bundleId: 'com.perusahaan.app');
/// final me = await r.login('0812xxxx', fcmToken: await FirebaseMessaging.instance.getToken());
/// saveSomewhereSecure(r.token);
/// ```
///
/// [token] disimpan sendiri oleh app (mis. secure storage) dan diberikan lagi saat app dibuka.
/// Error `responder_not_registered` / `responder_session_invalid` (401) = sesi berakhir → kembali ke layar login.
class SiagaSOSResponder {
  SiagaSOSResponder({
    required this.apiKey,
    required this.bundleId,
    String baseUrl = 'https://api.siagasos.id',
    this.token,
    http.Client? httpClient,
  })  : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _http = httpClient ?? http.Client();

  final String apiKey;
  final String bundleId;
  final String baseUrl;
  final http.Client _http;

  /// Token sesi `rsp_...`; null = belum login.
  String? token;
  bool get isLoggedIn => token != null;

  Future<Map<String, dynamic>> _request(String method, String path, {Object? body, bool auth = true}) async {
    final req = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers.addAll({'X-SOS-Key': apiKey, 'X-SOS-Bundle': bundleId, 'Content-Type': 'application/json'});
    if (auth) {
      if (token == null) throw const SiagaSOSError(401, 'responder_auth_required', 'Belum login');
      req.headers['X-SOS-Responder'] = token!;
    }
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

  /// Login langsung dengan nomor WhatsApp (tanpa OTP). 404 `responder_not_registered` bila nomor tidak ada di
  /// Nomor Darurat mana pun. [fcmToken] = token FCM perangkat untuk push alarm.
  Future<ResponderProfile> login(String phone, {String? fcmToken}) async {
    final d = await _request('POST', '/v1/sdk/responder/login', auth: false, body: {
      'phone': phone,
      'device': {'platform': _platform(), if (fcmToken != null && fcmToken.isNotEmpty) 'fcm_token': fcmToken},
    });
    token = d['token'] as String;
    final r = d['responder'] as Map<String, dynamic>;
    return ResponderProfile(phone: r['phone'] as String, name: r['name'] as String);
  }

  /// Kirim kode OTP ke WhatsApp [phone]. 404 `responder_not_registered` bila nomor tidak ada di Nomor Darurat mana pun.
  Future<ResponderOtp> requestOtp(String phone) async {
    final d = await _request('POST', '/v1/sdk/responder/otp', body: {'phone': phone}, auth: false);
    return ResponderOtp(
      sent: d['sent'] as bool? ?? false,
      expiresIn: Duration(seconds: (d['expires_in_s'] as num?)?.toInt() ?? 300),
      devCode: d['dev_code'] as String?,
    );
  }

  /// Tukar kode OTP dengan sesi. [fcmToken] = token FCM perangkat untuk push alarm (bisa diisi belakangan lewat [updateDevice]).
  Future<ResponderProfile> verify(String phone, String code, {String? fcmToken}) async {
    final d = await _request('POST', '/v1/sdk/responder/verify', auth: false, body: {
      'phone': phone,
      'code': code.trim(),
      'device': {'platform': _platform(), if (fcmToken != null && fcmToken.isNotEmpty) 'fcm_token': fcmToken},
    });
    token = d['token'] as String;
    final r = d['responder'] as Map<String, dynamic>;
    return ResponderProfile(phone: r['phone'] as String, name: r['name'] as String);
  }

  Future<ResponderProfile> me() async => ResponderProfile.fromJson(await _request('GET', '/v1/sdk/responder/me'));

  /// Perbarui token FCM (Firebase bisa merotasinya). null = berhenti menerima push di perangkat ini.
  Future<void> updateDevice(String? fcmToken) =>
      _request('PUT', '/v1/sdk/responder/device', body: {'fcm_token': fcmToken, 'platform': _platform()});

  /// SOS 7 hari terakhir yang mencantumkan nomor ini, terbaru dulu.
  Future<List<ResponderReport>> reports() async {
    final d = await _request('GET', '/v1/sdk/responder/reports');
    return ((d['data'] as List?) ?? const []).cast<Map<String, dynamic>>().map(ResponderReport.fromJson).toList();
  }

  Future<ResponderReport> report(String id) async => ResponderReport.fromJson(await _request('GET', '/v1/sdk/responder/reports/$id'));

  Future<ResponderReport> setStatus(String id, ResponderAction action, {String? note}) async => ResponderReport.fromJson(
        await _request('POST', '/v1/sdk/responder/reports/$id/status', body: {
          'status': switch (action) {
            ResponderAction.acknowledged => 'acknowledged',
            ResponderAction.inProgress => 'in_progress',
            ResponderAction.resolved => 'resolved',
            ResponderAction.falseAlarm => 'false_alarm',
          },
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        }),
      );

  /// Akhiri sesi di server (best-effort) dan lupakan token.
  Future<void> logout() async {
    try {
      if (token != null) await _request('POST', '/v1/sdk/responder/logout');
    } catch (_) {
    } finally {
      token = null;
    }
  }

  void dispose() => _http.close();

  static String _platform() => switch (defaultTargetPlatform) {
        TargetPlatform.android => 'android',
        TargetPlatform.iOS => 'ios',
        _ => 'other',
      };
}

/// Sesi berakhir → app sebaiknya kembali ke layar login satpam.
extension SiagaSOSErrorResponderX on SiagaSOSError {
  bool get isResponderSessionEnded =>
      status == 401 && (code == 'responder_not_registered' || code == 'responder_session_invalid' || code == 'responder_auth_required');
}
