import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:siagasos/siagasos.dart';

import 'client_test.dart' show FakeServer, make;

Future<void> pumpFrames(WidgetTester t, int n, [int ms = 50]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(Duration(milliseconds: ms));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('SOSFloatingButton: menu, tahan kirim, telepon, lampiran, posisi diingat', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final s = FakeServer();
    final sos = make(s);
    final calls = <String>[];
    var pageTaps = 0;
    ActiveReport? sent;

    await tester.pumpWidget(MaterialApp(
      home: const SizedBox(),
      builder: (context, child) => SOSFloatingButton(
        client: sos,
        holdSeconds: 1,
        tkpPrompt: false, // tanpa ajakan rekam TKP
        onCall: calls.add,
        onSent: (r) => sent = r,
        onCapture: (context, kind) async => CapturedMedia(bytes: Uint8List.fromList([1, 2, 3]), contentType: 'image/jpeg'),
        child: Scaffold(body: Center(child: ElevatedButton(onPressed: () => pageTaps++, child: const Text('Halaman')))),
      ),
    ));
    await tester.pump();

    // Area kosong tidak menangkap sentuhan: konten halaman tetap bisa diketuk.
    await tester.tap(find.text('Halaman'));
    expect(pageTaps, 1);

    // Posisi awal: pojok kanan bawah.
    final fab = find.byKey(const ValueKey('siagasos-fab'));
    expect(tester.getCenter(fab).dx, greaterThan(300));
    expect(tester.getCenter(fab).dy, greaterThan(650));

    await tester.tap(fab);
    await tester.pump();
    expect(find.text('Telepon 110'), findsOneWidget);
    expect(find.text('Telepon 112'), findsOneWidget);
    await tester.tap(find.text('Telepon 112'));
    expect(calls, ['112']);

    // Tahan bilah kirim sampai penuh.
    final g = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('siagasos-hold'))));
    await pumpFrames(tester, 30);
    await g.up();
    await pumpFrames(tester, 4);
    expect(sent?.id, 'rep-1');
    // Seperti tata-warga: menu tetap sama selama SOS aktif (tanpa mode "AKTIF"/panel status);
    // status di keterangan menu + titik kecil di tombol bulat.
    expect(find.byKey(const ValueKey('siagasos-hold')), findsOneWidget);
    expect(find.textContaining('SOS aktif: Terkirim. Menunggu petugas'), findsOneWidget);
    expect(find.byKey(const ValueKey('siagasos-fab-active')), findsOneWidget);
    expect(find.text('AKTIF'), findsNothing);

    // Batal salah tekan lewat Laporan → Riwayat laporan.
    await tester.tap(find.byKey(const ValueKey('siagasos-report')));
    await pumpFrames(tester, 8);
    await tester.tap(find.byKey(const ValueKey('siagasos-history')));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.tap(find.byKey(const ValueKey('siagasos-cancel-rep-1')));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    final cancel = s.requests.lastWhere((q) => q.url.path == '/v1/sdk/reports/rep-1/cancel');
    expect(jsonDecode(cancel.body), {'reason': 'Salah tekan'});
    expect(find.text('Dibatalkan'), findsOneWidget);
    expect(find.byKey(const ValueKey('siagasos-cancel-rep-1')), findsNothing);
    expect(find.byKey(const ValueKey('siagasos-fab-active')), findsNothing);
    await tester.tap(find.byTooltip('Tutup'));
    await pumpFrames(tester, 4);

    // Geser ke kiri atas → menempel ke tepi kiri dan disimpan.
    await tester.drag(find.byKey(const ValueKey('siagasos-fab')), const Offset(-300, -500));
    await pumpFrames(tester, 6);
    final c = tester.getCenter(find.byKey(const ValueKey('siagasos-fab')));
    expect(c.dx, lessThan(60));
    expect(c.dy, lessThan(400));
    final saved = (await SharedPreferences.getInstance()).getString('siagasos.fab.position');
    expect(saved, startsWith('L,'));

    sos.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('SOSFloatingButton: menu 4 aksi + laporan pengaduan dengan foto', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final s = FakeServer();
    final sos = make(s);
    ActiveReport? complaint;
    await tester.pumpWidget(MaterialApp(
      home: const SizedBox(),
      builder: (context, child) => SOSFloatingButton(
        client: sos,
        onCall: (_) {},
        onComplaintSent: (r) => complaint = r,
        onCapture: (context, kind) async => CapturedMedia(bytes: Uint8List.fromList([1, 2, 3]), contentType: 'image/jpeg'),
        child: const Scaffold(body: SizedBox()),
      ),
    ));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('siagasos-fab')));
    await pumpFrames(tester, 8);

    // 4 aksi: Kirim SOS (tahan), Telepon 110, Telepon 112, Laporan → sub-menu Pengaduan / Riwayat laporan.
    expect(find.byKey(const ValueKey('siagasos-hold')), findsOneWidget);
    expect(find.text('Telepon 110'), findsOneWidget);
    expect(find.text('Telepon 112'), findsOneWidget);
    expect(find.text('Laporan'), findsOneWidget);
    expect(find.text('Pengaduan'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('siagasos-report')));
    await pumpFrames(tester, 8);
    expect(find.text('Pengaduan'), findsOneWidget);
    expect(find.text('Riwayat laporan'), findsOneWidget);
    expect(find.byKey(const ValueKey('siagasos-hold')), findsNothing);
    // Kembali → menu utama.
    await tester.tap(find.byKey(const ValueKey('siagasos-back')));
    await pumpFrames(tester, 8);
    expect(find.byKey(const ValueKey('siagasos-hold')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('siagasos-report')));
    await pumpFrames(tester, 8);

    await tester.tap(find.byKey(const ValueKey('siagasos-complaint')));
    await pumpFrames(tester, 8);
    expect(find.byKey(const ValueKey('siagasos-complaint-sheet')), findsOneWidget);

    // Tombol kirim nonaktif sampai uraian diisi.
    FilledButton send() => tester.widget<FilledButton>(find.ancestor(of: find.text('Kirim pengaduan'), matching: find.byWidgetPredicate((w) => w is FilledButton)));
    expect(send().onPressed, isNull);
    await tester.tap(find.text('Parkir liar'));
    await tester.enterText(find.byKey(const ValueKey('siagasos-complaint-text')), 'Parkir liar menutup gang setiap malam');
    await tester.tap(find.text('Lampirkan foto (opsional)'));
    await pumpFrames(tester, 2);
    expect(find.text('Foto terlampir'), findsOneWidget);
    expect(send().onPressed, isNotNull);

    await tester.ensureVisible(find.text('Kirim pengaduan'));
    await tester.pump();
    await tester.tap(find.text('Kirim pengaduan'));
    await tester.pump();
    for (var i = 0; i < 100 && !s.requests.any((q) => q.url.path.endsWith('/complete')); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 10));
    }
    final post = s.requests.firstWhere((q) => q.url.path == '/v1/sdk/reports');
    final body = jsonDecode(post.body) as Map<String, dynamic>;
    expect(body['kind'], 'pengaduan');
    expect(body['category'], 'parkir_liar');
    expect(body['message'], 'Parkir liar menutup gang setiap malam');
    expect(complaint?.kind, ReportKind.pengaduan);
    expect(s.requests.any((q) => q.url.path == '/v1/sdk/reports/rep-1/media/m-1/complete'), isTrue);
    await pumpFrames(tester, 4);
    expect(find.text('Pengaduan terkirim'), findsOneWidget);
    // Pengaduan tidak menandai tombol bulat (penanda hanya untuk SOS aktif).
    expect(find.byKey(const ValueKey('siagasos-fab-active')), findsNothing);

    await tester.tap(find.text('Tutup'));
    await pumpFrames(tester, 4);
    expect(find.byKey(const ValueKey('siagasos-complaint-sheet')), findsNothing);

    // Riwayat: pengaduan tadi tercatat, statusnya diperbarui dari server.
    s.status = 'resolved';
    await tester.tap(find.byKey(const ValueKey('siagasos-fab')));
    await pumpFrames(tester, 8);
    await tester.tap(find.byKey(const ValueKey('siagasos-report')));
    await pumpFrames(tester, 8);
    await tester.tap(find.byKey(const ValueKey('siagasos-history')));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.byKey(const ValueKey('siagasos-history-sheet')), findsOneWidget);
    expect(find.text('Parkir liar'), findsOneWidget);
    expect(find.text('Parkir liar menutup gang setiap malam'), findsOneWidget);
    expect(find.text('Selesai'), findsOneWidget);

    sos.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('SOSFloatingButton: label & warna EWS, teks tanpa gaya darurat Flutter', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sos = make(FakeServer());
    await tester.pumpWidget(MaterialApp(
      home: const SizedBox(),
      builder: (context, child) => SOSFloatingButton(
        client: sos,
        onCall: (_) {},
        sosLabel: 'EWS Alert',
        callLabel: 'Call',
        child: child!,
      ),
    ));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('siagasos-fab')));
    await pumpFrames(tester, 8);
    expect(find.text('EWS Alert'), findsOneWidget);
    expect(find.text('Call 110'), findsOneWidget);
    expect(find.text('Call 112'), findsOneWidget);
    // Urutan atas → bawah: EWS Alert, Call 110, Call 112, Laporan, tombol bulat.
    final ys = ['EWS Alert', 'Call 110', 'Call 112', 'Laporan'].map((t) => tester.getCenter(find.text(t)).dy).toList();
    for (var i = 1; i < ys.length; i++) {
      expect(ys[i], greaterThan(ys[i - 1]));
    }
    expect(tester.getCenter(find.byKey(const ValueKey('siagasos-fab'))).dy, greaterThan(ys.last));
    // Dipasang di atas Navigator: tetap harus punya Material, bukan gaya darurat (garis bawah kuning).
    final style = DefaultTextStyle.of(tester.element(find.text('EWS Alert'))).style;
    expect(style.decoration, isNot(TextDecoration.underline));
    sos.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('SOSFloatingButton: alur EWS tata-warga — sekali ketuk, sirene/SENYAP, rekam TKP + catatan', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final s = FakeServer();
    final sos = make(s);
    final siren = _FakeSiren();
    final captured = <MediaKind>[];
    await tester.pumpWidget(MaterialApp(
      home: const SizedBox(),
      builder: (context, child) => SOSFloatingButton(
        client: sos,
        holdSeconds: 0,
        sosLabel: 'EWS Alert',
        siren: siren,
        onCall: (_) {},
        onCapture: (context, kind) async {
          captured.add(kind);
          // Seperti layar kamera sungguhan: beberapa frame berlalu selama kamera terbuka.
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return CapturedMedia(bytes: Uint8List.fromList([1, 2, 3]), contentType: 'video/mp4', durationS: 5);
        },
        child: child!,
      ),
    ));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('siagasos-fab')));
    await pumpFrames(tester, 8);
    expect(find.textContaining('tahan'), findsNothing); // tanpa tahan N detik

    // Sekali ketuk → SOS terkirim, sirene mulai, ajakan rekam TKP muncul.
    await tester.tap(find.text('EWS Alert'));
    await pumpFrames(tester, 8);
    expect(siren.starts, 1);
    expect(s.requests.where((q) => q.url.path == '/v1/sdk/reports').length, 1);
    expect(find.text('SOS terkirim'), findsOneWidget);
    expect(find.text('Rekam kondisi TKP?'), findsOneWidget);
    expect(find.text('Maks. 5 detik'), findsOneWidget);

    // Tombol bulat menjadi SENYAP selama sirene berbunyi; "Matikan sirene" di popup juga mematikan.
    expect(find.text('SENYAP'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('siagasos-tkp-mute')));
    await tester.pump();
    expect(siren.active.value, isFalse);
    expect(find.text('SENYAP'), findsNothing);

    // Rekam → catatan → kirim: video diunggah + catatan ke /notes.
    await tester.tap(find.byKey(const ValueKey('siagasos-tkp-record')));
    await tester.pump(const Duration(milliseconds: 50));
    // Selama kamera app host terbuka, tombol & popup disembunyikan (regresi: dulu Overlay lembar dibuat ulang
    // → "entry is already present in a different Overlay").
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('siagasos-fab')), findsNothing);
    expect(find.text('Rekam kondisi TKP?'), findsNothing);
    await pumpFrames(tester, 6);
    expect(tester.takeException(), isNull);
    expect(captured, [MediaKind.video]);
    expect(find.byKey(const ValueKey('siagasos-fab')), findsOneWidget);
    expect(find.text('Video 5 detik'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('siagasos-tkp-note')), 'Dua orang mencurigakan di depan toko');
    await tester.tap(find.byKey(const ValueKey('siagasos-tkp-send')));
    for (var i = 0; i < 100 && !s.requests.any((q) => q.url.path.endsWith('/notes')); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 10));
    }
    await pumpFrames(tester, 4);
    expect(s.requests.any((q) => q.url.path == '/v1/sdk/reports/rep-1/media/m-1/complete'), isTrue);
    final note = s.requests.lastWhere((q) => q.url.path == '/v1/sdk/reports/rep-1/notes');
    expect(jsonDecode(note.body), {'note': 'Dua orang mencurigakan di depan toko'});
    expect(find.text('Rekaman TKP terkirim'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('siagasos-tkp-close')));
    await pumpFrames(tester, 4);
    expect(find.byKey(const ValueKey('siagasos-tkp')), findsNothing);
    // SOS masih aktif: tombol tetap "SOS" + titik penanda; menu tetap EWS/110/112/Laporan.
    expect(find.text('AKTIF'), findsNothing);
    expect(find.byKey(const ValueKey('siagasos-fab-active')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('siagasos-fab')));
    await pumpFrames(tester, 8);
    expect(find.text('EWS Alert'), findsOneWidget);
    expect(find.text('Laporan'), findsOneWidget);

    sos.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('SOSFloatingButton: Nomor darurat disimpan di perangkat dan ikut terkirim bersama SOS', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = FakeServer();
    final sos = make(s);
    await tester.pumpWidget(MaterialApp(
      home: const SizedBox(),
      builder: (context, child) => SOSFloatingButton(client: sos, holdSeconds: 0, sosLabel: 'EWS Alert', onCall: (_) {}, child: child!),
    ));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('siagasos-fab')));
    await pumpFrames(tester, 8);
    await tester.tap(find.byKey(const ValueKey('siagasos-report')));
    await pumpFrames(tester, 8);
    expect(find.text('Nomor darurat'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('siagasos-contacts')));
    await pumpFrames(tester, 8);
    expect(find.byKey(const ValueKey('siagasos-contacts-sheet')), findsOneWidget);

    // Nomor tidak valid ditolak; nomor valid dinormalisasi ke 62xx.
    await tester.enterText(find.byKey(const ValueKey('siagasos-contact-phone')), '123');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('siagasos-contact-add')));
    await tester.pump();
    expect(find.textContaining('Nomor WhatsApp tidak valid'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('siagasos-contact-name')), 'Istri');
    await tester.enterText(find.byKey(const ValueKey('siagasos-contact-phone')), '0813-3333-4444');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('siagasos-contact-add')));
    await pumpFrames(tester, 4);
    expect(find.text('Istri'), findsOneWidget);
    expect(find.text('+6281333334444'), findsOneWidget);
    expect((await sos.emergencyContacts()).map((c) => c.phone), ['6281333334444']);
    await tester.tap(find.byTooltip('Tutup'));
    await pumpFrames(tester, 4);

    // SOS membawa kontak darurat; pengaduan tidak.
    await tester.tap(find.byKey(const ValueKey('siagasos-fab')));
    await pumpFrames(tester, 8);
    await tester.tap(find.text('EWS Alert'));
    await pumpFrames(tester, 8);
    final post = s.requests.firstWhere((q) => q.url.path == '/v1/sdk/reports');
    expect((jsonDecode(post.body) as Map)['emergency_contacts'], [
      {'name': 'Istri', 'phone': '6281333334444'}
    ]);
    await sos.complain(category: 'parkir_liar', message: 'Parkir liar di depan toko');
    final complaint = s.requests.lastWhere((q) => q.url.path == '/v1/sdk/reports');
    expect((jsonDecode(complaint.body) as Map).containsKey('emergency_contacts'), isFalse);

    sos.dispose();
    await tester.pumpWidget(const SizedBox());
  });
}

class _FakeSiren implements SosSiren {
  @override
  final ValueNotifier<bool> active = ValueNotifier(false);
  int starts = 0;
  @override
  void start() {
    starts++;
    active.value = true;
  }

  @override
  void stop() => active.value = false;
}
