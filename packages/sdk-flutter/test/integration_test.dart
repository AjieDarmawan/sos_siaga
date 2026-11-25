@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:siagasos/siagasos.dart';

/// Uji terhadap API lokal + MinIO sungguhan. Jalankan: SIAGASOS_IT=1 flutter test test/integration_test.dart
/// Butuh `pnpm dev:api` dan `pnpm seed:demo` (app "Aplikasi Kurir (Android)", bundle id.demosiaga.kurir).
void main() {
  final enabled = Platform.environment['SIAGASOS_IT'] == '1';
  const api = 'http://localhost:4000';

  test('trigger + lampiran foto & suara ke MinIO, tampil di portal', () async {
    final login = jsonDecode((await http.post(
            Uri.parse('$api/portal/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(
                {'email': 'demo@siagasos.test', 'password': 'demo12345'})))
        .body) as Map<String, dynamic>;
    final token = login['token'] as String;
    final apps = jsonDecode((await http.get(Uri.parse('$api/portal/apps'),
            headers: {'Authorization': 'Bearer $token'}))
        .body)['data'] as List;
    final android =
        apps.firstWhere((a) => (a['name'] as String).contains('Android'));
    final pk = (android['keys'] as List).firstWhere((k) =>
        k['kind'] == 'publishable' &&
        k['mode'] == 'live' &&
        k['active'] == true)['key'] as String;

    final sos = SiagaSOS(
        apiKey: pk,
        bundleId: 'id.demosiaga.kurir',
        baseUrl: api,
        queueStore: MemoryQueueStore(),
        user: const SosUser(ref: 'flutter-it', name: 'Uji Flutter SDK'),
        locationProvider: () async =>
            const SosLocation(lat: -6.1754, lng: 106.8272, accuracyM: 12));
    final cfg = await sos.getConfig();
    expect(cfg.appName, contains('Android'));

    final r =
        await sos.trigger(category: 'medis', message: 'Integrasi Flutter SDK');
    expect(r.id, isNotNull);
    expect(r.status, SosStatus.open);

    final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');
    final img = await sos.attach(r.localId, png, contentType: 'image/png');
    expect(img.ready, isTrue);
    final wav = Uint8List.fromList([
      ...ascii.encode('RIFF'),
      36,
      0,
      0,
      0,
      ...ascii.encode('WAVEfmt '),
      16,
      0,
      0,
      0,
      1,
      0,
      1,
      0,
      64,
      31,
      0,
      0,
      128,
      62,
      0,
      0,
      2,
      0,
      16,
      0,
      ...ascii.encode('data'),
      0,
      0,
      0,
      0
    ]);
    final aud =
        await sos.attach(r.id!, wav, contentType: 'audio/wav', durationS: 0);
    expect(aud.kind, MediaKind.audio);

    // bundle salah ditolak
    final bad = SiagaSOS(
        apiKey: pk,
        bundleId: 'com.penyusup.app',
        baseUrl: api,
        queueStore: MemoryQueueStore());
    await expectLater(
        bad.trigger(),
        throwsA(isA<SiagaSOSError>()
            .having((e) => e.code, 'code', 'bundle_not_allowed')));

    final detail = jsonDecode((await http.get(
            Uri.parse('$api/portal/reports/${r.id}'),
            headers: {'Authorization': 'Bearer $token'}))
        .body);
    final media = detail['media'] as List;
    expect(media.map((m) => m['kind']), containsAll(['image', 'audio']));
    expect(detail['device']['platform'], isNotNull);
    for (final m in media) {
      expect((await http.get(Uri.parse(m['url'] as String))).statusCode, 200,
          reason: 'file bisa dibaca dari MinIO');
    }
    final c = await sos.cancel(r.localId, reason: 'uji selesai');
    expect(c!.status, SosStatus.cancelled);
    sos.dispose();
    bad.dispose();
  },
      skip: enabled ? false : 'set SIAGASOS_IT=1 (butuh API lokal)',
      timeout: const Timeout(Duration(minutes: 2)));
}
