import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:siagasos/siagasos.dart';

const key = 'pk_test_abcdefghijklmnop';

/// Server palsu yang mencatat request dan bisa disetel gagal.
class FakeServer {
  final requests = <http.Request>[];
  int failNext = 0; // jumlah POST /reports berikutnya yang dibuat gagal jaringan
  String status = 'open';
  String buttonText = 'SOS'; // nilai bawaan server bila "Teks tombol" portal kosong
  List<Map<String, dynamic>> serverContacts = [];
  late final client = MockClient((req) async {
    requests.add(req);
    final p = req.url.path;
    if (p == '/v1/sdk/config') {
      return http.Response(jsonEncode({'app_name': 'Demo', 'mode': 'test', 'categories': ['general'], 'button_text': buttonText, 'hold_seconds': 1,
        'recipient_text': 'Ke satpam', 'fallback_phone': '110', 'live_location_interval_s': 15}), 200);
    }
    if (p == '/v1/sdk/reports' && req.method == 'POST') {
      if (failNext > 0) {
        failNext--;
        throw http.ClientException('offline');
      }
      return http.Response(jsonEncode({'id': 'rep-1', 'status': 'open', 'mode': 'test', 'category': 'medis', 'status_message': null}), 201);
    }
    if (p == '/v1/sdk/reports/rep-1') return http.Response(jsonEncode({'id': 'rep-1', 'status': status, 'status_message': null}), 200);
    if (p == '/v1/sdk/reports/rep-1/media') {
      return http.Response(jsonEncode({'media': {'id': 'm-1'}, 'upload': {'method': 'PUT', 'url': 'https://storage.test/put?sig=1', 'headers': {'Content-Type': 'image/jpeg'}}}), 201);
    }
    if (p == '/v1/sdk/reports/rep-1/cancel') {
      status = 'cancelled';
      return http.Response(jsonEncode({'id': 'rep-1', 'status': 'cancelled', 'status_message': null}), 200);
    }
    if (p == '/v1/sdk/reports/rep-1/detail') {
      return http.Response(jsonEncode({
        'id': 'rep-1', 'kind': 'pengaduan', 'status': status, 'mode': 'test', 'category': 'parkir_liar',
        'created_at': '2026-11-23T08:00:00Z', 'acknowledged_at': '2026-11-23T08:05:00Z', 'resolved_at': '2026-11-23T09:00:00Z',
        'status_message': 'Petugas sudah menertibkan parkir', 'message': 'Parkir liar menutup gang setiap malam',
        'location': {'lat': -6.2, 'lng': 106.8, 'accuracy_m': 10},
        'timeline': [
          {'type': 'created', 'actor': 'Anda', 'to_status': 'open', 'note': null, 'created_at': '2026-11-23T08:00:00Z'},
          {'type': 'media', 'actor': 'Anda', 'to_status': null, 'note': 'Foto ditambahkan', 'created_at': '2026-11-23T08:01:00Z'},
          {'type': 'status_changed', 'actor': 'Bripka Andi', 'to_status': 'acknowledged', 'note': 'Menuju lokasi', 'created_at': '2026-11-23T08:05:00Z'},
          {'type': 'status_changed', 'actor': 'Bripka Andi', 'to_status': 'resolved', 'note': 'Sudah ditertibkan', 'created_at': '2026-11-23T09:00:00Z'},
        ],
        'media': [
          {'id': 'm-1', 'kind': 'video', 'content_type': 'video/mp4', 'duration_s': 5, 'uploaded_by': 'reporter', 'created_at': '2026-11-23T08:01:00Z', 'url': 'https://storage.test/v.mp4'},
        ],
      }), 200);
    }
    if (p == '/v1/sdk/reports/rep-1/notes') return http.Response(jsonEncode({'id': 'rep-1', 'status': status, 'status_message': null}), 201);
    if (req.url.host == 'storage.test') return http.Response('', 200);
    if (p == '/v1/sdk/reports/rep-1/media/m-1/complete') {
      return http.Response(jsonEncode({'id': 'm-1', 'kind': 'image', 'content_type': 'image/jpeg', 'size_bytes': 3, 'status': 'ready'}), 200);
    }
    if (p == '/v1/sdk/contacts' && req.method == 'PUT') {
      serverContacts = ((jsonDecode(req.body) as Map)['contacts'] as List).cast<Map<String, dynamic>>();
      return http.Response(jsonEncode({'ok': true, 'count': serverContacts.length}), 200);
    }
    if (p == '/v1/sdk/contacts') return http.Response(jsonEncode({'contacts': serverContacts}), 200);
    if (p == '/v1/sdk/reports/bad' ) return http.Response(jsonEncode({'error': {'code': 'invalid_api_key', 'message': 'x'}}), 401);
    return http.Response('{}', 404);
  });
}

SiagaSOS make(FakeServer s, {QueueStore? store, QueueStore? history, QueueStore? contacts, QueueStore? contactsSync, http.Client? c}) => SiagaSOS(
      apiKey: key, bundleId: 'com.demo.app', baseUrl: 'https://api.test', httpClient: c ?? s.client,
      queueStore: store ?? MemoryQueueStore(), historyStore: history ?? MemoryQueueStore(), contactsStore: contacts ?? MemoryQueueStore(),
      contactsSyncStore: contactsSync ?? MemoryQueueStore(), user: const SosUser(ref: 'u1', name: 'Budi'),
      locationProvider: () async => const SosLocation(lat: -6.2, lng: 106.8, accuracyM: 10),
      pollInterval: const Duration(milliseconds: 50));

void main() {
  test('menolak secret key / kunci salah', () {
    expect(() => SiagaSOS(apiKey: 'sk_test_x', bundleId: 'a.b'), throwsA(isA<SiagaSOSError>()));
  });

  test('mode dari prefix kunci', () {
    final s = FakeServer();
    expect(make(s).mode, SosMode.test);
  });

  test('trigger mengirim header mobile, idempotency, lokasi, dan pelapor', () async {
    final s = FakeServer();
    final sos = make(s);
    final r = await sos.trigger(category: 'medis', message: 'pingsan');
    expect(r.id, 'rep-1');
    expect(r.status, SosStatus.open);
    final post = s.requests.firstWhere((q) => q.url.path == '/v1/sdk/reports');
    expect(post.headers['X-SOS-Key'], key);
    expect(post.headers['X-SOS-Bundle'], 'com.demo.app');
    expect(post.headers['Idempotency-Key'], matches(RegExp(r'^[0-9a-f-]{36}$')));
    final body = jsonDecode(post.body) as Map<String, dynamic>;
    expect(body['location']['lat'], -6.2);
    expect(body['reporter']['ref'], 'u1');
    expect(body['device']['platform'], isNotNull);
    sos.dispose();
  });

  test('offline: masuk antrian, lalu terkirim ulang dengan Idempotency-Key yang sama', () async {
    final s = FakeServer()..failNext = 1;
    final store = MemoryQueueStore();
    final sos = make(s, store: store);
    final queued = <ActiveReport>[];
    sos.queued.listen(queued.add);
    final r = await sos.trigger(category: 'kriminal');
    expect(r.status, SosStatus.queued);
    expect(r.id, isNull);
    expect((await store.load()).length, 1);
    expect(queued, hasLength(1));
    final sent = await sos.sent.first.timeout(const Duration(seconds: 5));
    expect(sent.id, 'rep-1');
    expect(await store.load(), isEmpty);
    final keys = s.requests.where((q) => q.url.path == '/v1/sdk/reports').map((q) => q.headers['Idempotency-Key']).toSet();
    expect(keys, hasLength(1), reason: 'retry harus memakai idempotency key yang sama');
    sos.dispose();
  });

  test('antrian bertahan antar sesi (instance baru mengirim sisa antrian)', () async {
    final store = MemoryQueueStore();
    final s1 = FakeServer()..failNext = 99;
    final a = make(s1, store: store);
    await a.trigger();
    a.dispose();
    expect((await store.load()).length, 1);
    final s2 = FakeServer();
    final b = make(s2, store: store);
    await b.sent.first.timeout(const Duration(seconds: 2));
    expect(await store.load(), isEmpty);
    b.dispose();
  });

  test('polling status berhenti di status akhir', () async {
    final s = FakeServer();
    final sos = make(s);
    final statuses = <SosStatus>[];
    sos.status.listen((r) => statuses.add(r.status));
    await sos.trigger();
    s.status = 'acknowledged';
    await Future<void>.delayed(const Duration(milliseconds: 120));
    s.status = 'resolved';
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final n = s.requests.where((q) => q.url.path == '/v1/sdk/reports/rep-1').length;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(statuses, containsAllInOrder([SosStatus.open, SosStatus.acknowledged, SosStatus.resolved]));
    expect(s.requests.where((q) => q.url.path == '/v1/sdk/reports/rep-1').length, n, reason: 'tidak polling lagi');
    sos.dispose();
  });

  test('attach: minta URL → PUT ke storage tanpa X-SOS-Key → complete', () async {
    final s = FakeServer();
    final sos = make(s);
    final r = await sos.trigger();
    final progress = <double>[];
    final m = await sos.attach(r.localId, Uint8List.fromList([1, 2, 3]), contentType: 'image/jpeg', onProgress: progress.add);
    expect(m.ready, isTrue);
    expect(m.kind, MediaKind.image);
    expect(progress.last, 1);
    final create = s.requests.firstWhere((q) => q.url.path.endsWith('/media'));
    expect(jsonDecode(create.body)['size_bytes'], 3);
    sos.dispose();
  });

  test('batal saat masih di antrian cukup menghapus antrian', () async {
    final s = FakeServer()..failNext = 99;
    final store = MemoryQueueStore();
    final sos = make(s, store: store);
    final r = await sos.trigger();
    final c = await sos.cancel(r.localId);
    expect(c!.status, SosStatus.cancelled);
    expect(await store.load(), isEmpty);
    sos.dispose();
  });

  testWidgets('SOSButton: tahan sampai penuh → laporan terkirim; lepas lebih cepat → batal', (tester) async {
    final s = FakeServer();
    final sos = make(s);
    ActiveReport? sent;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: SOSButton(client: sos, holdSeconds: 1, onSent: (r) => sent = r)))));
    await tester.pump();

    // lepas setelah 0,4 dtk → tidak terkirim
    var g = await tester.startGesture(tester.getCenter(find.byType(SOSButton)));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await g.up();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(sent, isNull);
    expect(s.requests.where((q) => q.url.path == '/v1/sdk/reports'), isEmpty);

    // tahan penuh 1 dtk → terkirim
    g = await tester.startGesture(tester.getCenter(find.byType(SOSButton)));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50)); // per frame supaya animasi tahan berjalan
    }
    await g.up();
    await tester.pump();
    expect(sent?.id, 'rep-1');
    expect(find.textContaining('Batalkan'), findsOneWidget);
    sos.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  test('kontak darurat: jabatan & aktif disimpan, hanya yang aktif dikirim bersama SOS, maks. 5 aktif', () async {
    final s = FakeServer();
    final sos = make(s);
    await sos.setEmergencyContacts(const [
      EmergencyContact(name: 'Pak Joko', phone: '0812-1111-2222', role: 'Satpam'),
      EmergencyContact(name: 'Kakak', phone: '+62 813 3333 4444', active: false),
    ]);
    final saved = await sos.emergencyContacts();
    expect(saved.map((c) => (c.phone, c.role, c.active)), [('6281211112222', 'Satpam', true), ('6281333334444', null, false)]);

    await sos.trigger(category: 'kriminal');
    final body = jsonDecode(s.requests.firstWhere((q) => q.url.path == '/v1/sdk/reports').body) as Map;
    expect(body['emergency_contacts'], [
      {'name': 'Pak Joko (Satpam)', 'phone': '6281211112222'}
    ]);

    expect(
      () => sos.setEmergencyContacts([for (var i = 0; i < 6; i++) EmergencyContact(name: 'K$i', phone: '08120000000$i')]),
      throwsA(isA<ArgumentError>()),
    );
    expect(() => sos.setEmergencyContacts(const [EmergencyContact(name: 'X', phone: '123')]), throwsA(isA<ArgumentError>()));
    expect(
      () => sos.setEmergencyContacts(const [EmergencyContact(name: 'A', phone: '081211112222'), EmergencyContact(name: 'B', phone: '6281211112222')]),
      throwsA(isA<ArgumentError>()),
    );
    sos.dispose();
  });

  test('Nomor Darurat disinkronkan ke server dan dipulihkan di perangkat baru', () async {
    final s = FakeServer();
    final sos = make(s);
    final synced = await sos.setEmergencyContacts(const [EmergencyContact(name: 'Pak Budi', role: 'Satpam', phone: '0812 1111 2222')]);
    expect(synced, isTrue);
    final put = s.requests.lastWhere((r) => r.url.path == '/v1/sdk/contacts' && r.method == 'PUT');
    expect(jsonDecode(put.body), {
      'reporter': {'ref': 'u1', 'name': 'Budi'},
      'contacts': [{'name': 'Pak Budi', 'role': 'Satpam', 'phone': '6281211112222', 'active': true}],
    });
    sos.dispose();

    // Perangkat baru (penyimpanan kosong) → ambil dari server.
    final fresh = make(s);
    expect(await fresh.syncEmergencyContacts(), isTrue);
    final restored = await fresh.emergencyContacts();
    expect(restored.single.phone, '6281211112222');
    expect(restored.single.role, 'Satpam');
    fresh.dispose();
  });

  test('responder: OTP → verify → laporan → tanggapi → logout', () async {
    final requests = <http.Request>[];
    final c = MockClient((req) async {
      requests.add(req);
      final p = req.url.path;
      if (p == '/v1/sdk/responder/otp') return http.Response(jsonEncode({'sent': false, 'expires_in_s': 300, 'dev_code': '123456'}), 200);
      if (p == '/v1/sdk/responder/verify' || p == '/v1/sdk/responder/login') {
        return http.Response(jsonEncode({'token': 'rsp_abc', 'responder': {'phone': '6281211112222', 'name': 'Pak Budi (Satpam)'}}), 201);
      }
      final rep = {'id': 'r1', 'status': 'open', 'mode': 'live', 'category': 'kriminal', 'reporter_name': 'Kasir Satu',
        'source_label': 'Outlet A', 'location': {'lat': -6.2, 'lng': 106.8, 'accuracy_m': null}, 'created_at': '2026-11-23T08:00:00Z'};
      if (p == '/v1/sdk/responder/reports') return http.Response(jsonEncode({'data': [rep]}), 200);
      if (p == '/v1/sdk/responder/reports/r1/status') return http.Response(jsonEncode({...rep, 'status': 'acknowledged'}), 200);
      if (p == '/v1/sdk/responder/logout') return http.Response('', 204);
      return http.Response(jsonEncode({'error': {'code': 'responder_not_registered', 'message': 'x'}}), 401);
    });
    final r = SiagaSOSResponder(apiKey: key, bundleId: 'com.demo.app', baseUrl: 'https://api.test', httpClient: c);
    expect((await r.requestOtp('081211112222')).devCode, '123456');
    final me = await r.verify('081211112222', '123456', fcmToken: 'fcm-1');
    expect(me.name, 'Pak Budi (Satpam)');
    expect(r.token, 'rsp_abc');
    expect((jsonDecode(requests.last.body) as Map)['device'], containsPair('fcm_token', 'fcm-1'));
    expect(requests.first.headers.containsKey('X-SOS-Responder'), isFalse);

    final direct = SiagaSOSResponder(apiKey: key, bundleId: 'com.demo.app', baseUrl: 'https://api.test', httpClient: c);
    expect((await direct.login('081211112222')).name, 'Pak Budi (Satpam)');
    expect(direct.token, 'rsp_abc');

    final list = await r.reports();
    expect(list.single.reporterName, 'Kasir Satu');
    expect(list.single.mapsUri.toString(), 'https://www.google.com/maps?q=-6.2,106.8');
    expect(requests.last.headers['X-SOS-Responder'], 'rsp_abc');
    expect((await r.setStatus('r1', ResponderAction.acknowledged)).status, SosStatus.acknowledged);

    try {
      await r.me();
      fail('harus 401');
    } on SiagaSOSError catch (e) {
      expect(e.isResponderSessionEnded, isTrue);
    }
    await r.logout();
    expect(r.isLoggedIn, isFalse);
  });
}
