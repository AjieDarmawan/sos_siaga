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
    expect(find.textContaining('Menunggu petugas'), findsOneWidget);
    expect(find.text('Batalkan (salah tekan)'), findsOneWidget);

    // Foto → unggah lewat presigned URL → complete.
    await tester.tap(find.text('Foto'));
    for (var i = 0; i < 100 && !s.requests.any((q) => q.url.path.endsWith('/complete')); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(s.requests.any((q) => q.url.path == '/v1/sdk/reports/rep-1/media/m-1/complete'), isTrue);

    // Tutup menu, geser ke kiri atas → menempel ke tepi kiri dan disimpan.
    await tester.tap(find.byKey(const ValueKey('siagasos-fab')));
    await tester.pump();
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

    // 4 aksi: Kirim SOS (tahan), Telepon 110, Telepon 112, Laporan pengaduan.
    expect(find.byKey(const ValueKey('siagasos-hold')), findsOneWidget);
    expect(find.text('Telepon 110'), findsOneWidget);
    expect(find.text('Telepon 112'), findsOneWidget);
    expect(find.text('Laporan pengaduan'), findsOneWidget);

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
    // Pengaduan tidak mengubah tombol bulat menjadi "AKTIF" (itu hanya untuk SOS).
    expect(find.text('AKTIF'), findsNothing);

    await tester.tap(find.text('Tutup'));
    await pumpFrames(tester, 4);
    expect(find.byKey(const ValueKey('siagasos-complaint-sheet')), findsNothing);

    sos.dispose();
    await tester.pumpWidget(const SizedBox());
  });
}
