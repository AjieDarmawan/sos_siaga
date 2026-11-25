import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:polmas_keamanan/core/models.dart';
import 'package:polmas_keamanan/core/app_state.dart';
import 'package:polmas_keamanan/screens/reports_screen.dart';
import 'package:polmas_keamanan/widgets/ui.dart';

/// Laporan contoh dengan teks panjang supaya luapan (overflow) ketahuan.
Report _sample({bool phone = true, Map? last}) => Report({
  'id': '00000000-0000-0000-0000-000000000001',
  'kind': 'sos',
  'category': 'darurat',
  'title': 'Pencurian motor di depan minimarket Jl. Kapten Muslihat yang sangat panjang',
  'message': 'Diduga terjadi pencurian motor di depan rumah warga, pelaku terekam CCTV dan kabur ke arah pasar.',
  'status': 'ditangani',
  'source': 'umkm',
  'source_label': 'Polmas UMKM',
  'app_name': 'commerceOS POS Toko Roti Sinar Jaya',
  'location_text': 'Jl. Suryakencana No. 120, depan gerbang pasar',
  'kelurahan': {'code': '32.71.03.1002', 'name': 'Paledang'},
  'location': {'lat': -6.6, 'lng': 106.8},
  'reporter': {'name': 'Siti Rahmawati Kusumaningrum', 'phone': phone ? '628001234567' : null, 'is_me': false},
  'created_at': DateTime.now().subtract(const Duration(minutes: 12)).toUtc().toIso8601String(),
  'media': {'image': 2, 'video': 1, 'audio': 1},
  'video_s': 18,
  'code': 'SOS-2511-0000',
  'last_response': last,
});

Future<void> _pump(WidgetTester tester, Widget child, {double scale = 1.3}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: const Size(390, 844), textScaler: TextScaler.linear(scale)),
      child: MaterialApp(
        home: AppScope(
          state: AppState(),
          child: Scaffold(
            body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  setUpAll(() => initializeDateFormatting('id'));
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('kartu Tindak Lanjut: semua kolom tampil tanpa luapan (huruf 130%)', (tester) async {
    final last = {'action': 'tangani', 'officer': 'Bripka Andi Saputra (Unit R2-07)', 'note': 'Unit menuju lokasi', 'created_at': DateTime.now().toUtc().toIso8601String()};
    await _pump(tester, ReportCard(r: _sample(last: last)));
    expect(tester.takeException(), isNull);
    expect(find.text('SOS'), findsOneWidget);
    expect(find.text('Diproses'), findsOneWidget);
    expect(find.textContaining('Pencurian motor'), findsOneWidget);
    expect(find.text('0800-123-4567'), findsOneWidget);
    expect(find.textContaining('Bripka Andi Saputra,', findRichText: true), findsOneWidget);
    expect(find.textContaining('Unit menuju lokasi', findRichText: true), findsOneWidget);
    expect(find.textContaining('(Unit R2-07)', findRichText: true), findsNothing);
  });

  testWidgets('kartu tanpa tanggapan: "Belum ditanggapi" + nomor disamarkan tidak tampil', (tester) async {
    final r = Report({..._sample(phone: false).raw, 'status': 'baru'});
    await _pump(tester, ReportCard(r: r));
    expect(tester.takeException(), isNull);
    expect(find.text('Darurat'), findsOneWidget);
    expect(find.textContaining('Belum ditanggapi', findRichText: true), findsOneWidget);
  });

  testWidgets('tabel: 9 kolom header seperti contoh', (tester) async {
    await _pump(tester, ReportTable(items: [_sample(), _sample(phone: false)]), scale: 1);
    expect(tester.takeException(), isNull);
    for (final h in ['Berita', 'No HP', 'Ekosistem', 'Dari Siapa', 'Foto/Video', 'Location', 'Waktu', 'Status', 'Tindak Lanjut']) {
      expect(find.text(h), findsOneWidget, reason: h);
    }
    expect(find.text('Disamarkan'), findsOneWidget);
  });
}
