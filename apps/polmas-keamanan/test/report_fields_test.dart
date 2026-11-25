import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:polmas_keamanan/core/models.dart';
import 'package:polmas_keamanan/widgets/report_table.dart';

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
  'media': {'image': 2, 'video': 1, 'audio': 0},
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
        home: Scaffold(
          body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  setUpAll(() => initializeDateFormatting('id'));

  testWidgets('kartu lengkap: 9 isian tampil tanpa luapan (huruf 130%)', (tester) async {
    await _pump(
      tester,
      ReportFieldsCard(
        report: _sample(last: {'action': 'tangani', 'officer': 'Aiptu Rahmat Hidayat (Polsek Bogor Tengah)', 'note': 'Menuju lokasi bersama Babinsa'}),
        from: (lat: -6.597, lng: 106.797),
      ),
    );
    expect(tester.takeException(), isNull);
    for (final f in ReportField.values.where((f) => f != ReportField.berita && f != ReportField.status && f != ReportField.tindakLanjut)) {
      expect(find.text(f.label), findsOneWidget, reason: f.label);
    }
    expect(find.text('Ditangani · Aiptu Rahmat Hidayat'), findsOneWidget);
    expect(find.text('0800-123-4567'), findsOneWidget);
  });

  testWidgets('kartu: nomor disamarkan & belum ditanggapi', (tester) async {
    await _pump(tester, ReportFieldsCard(report: _sample(phone: false)));
    expect(tester.takeException(), isNull);
    expect(find.text('Disamarkan'), findsOneWidget);
    expect(find.text('Belum ditanggapi'), findsOneWidget);
  });

  testWidgets('tabel: header 9 kolom + baris, tanpa luapan', (tester) async {
    await _pump(tester, ReportTable(reports: [_sample(), _sample(phone: false)]));
    expect(tester.takeException(), isNull);
    for (final f in ReportField.values) {
      expect(find.text(f.label), findsOneWidget, reason: f.label);
    }
  });
}
