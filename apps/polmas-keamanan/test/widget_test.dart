import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:polmas_keamanan/core/format.dart';
import 'package:polmas_keamanan/core/models.dart';
import 'package:polmas_keamanan/theme/tokens.dart';
import 'package:polmas_keamanan/widgets/ui.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id'));

  group('format', () {
    test('nomor 62 ditampilkan dengan awalan 0', () => expect(fmtPhone('628001110006'), '0800-111-0006'));
    test('durasi', () {
      expect(fmtDuration(45), '45 dtk');
      expect(fmtDuration(12 * 60), '12 mnt');
      expect(fmtDuration(3 * 3600 + 20 * 60), '3 j 20 mnt');
      expect(fmtDuration(null), '–');
    });
  });

  group('model', () {
    test('nomor tiket & ekosistem', () {
      final r = Report({'id': 'abcd1234-0000', 'kind': 'sos', 'code': 'SOS-2511-ABCD', 'source': 'umkm', 'source_label': 'UMKM', 'app_name': 'commerceOS (Android)', 'created_at': '2026-11-25T10:00:00Z'});
      expect(r.code, 'SOS-2511-ABCD');
      expect(r.ecosystemLabel, 'UMKM');
      expect(r.ecosystemApp, 'commerceOS');
      // App tanpa pilar Polmas (mis. POS biasa): ekosistem disembunyikan, nama app tidak tampil.
      final pos = Report({'id': 'x', 'kind': 'sos', 'source_label': 'POSTIP Kasir (Android)', 'app_name': 'POSTIP Kasir (Android)', 'created_at': '2026-11-25T10:00:00Z'});
      expect(pos.hasEcosystem, isFalse);
      expect(pos.ecosystemApp, isNull);
      expect(cleanAppName('Polmas Warga (Demo)'), 'Polmas Warga');
    });

    test('status SOS baru = Darurat merah, laporan baru = Baru navy', () {
      expect(statusStyle(PkStatus.baru, sos: true).label, 'Darurat');
      expect(statusStyle(PkStatus.baru, sos: true).color, PK.red);
      expect(statusStyle(PkStatus.baru, sos: false).label, 'Baru');
      expect(statusStyle(PkStatus.ditangani, sos: true).color, PK.gold);
      expect(statusStyle(PkStatus.selesai, sos: false).color, PK.green);
    });

    test('cek nomor: login pertama dari Nomor Darurat + baris asal nomor', () {
      final c = PhoneCheck({
        'phone': '628001110006',
        'name': 'Agus Setiawan',
        'has_password': false,
        'contacts': [
          {'role': 'Satpam', 'place': 'Toko Roti Sinar Jaya', 'app': 'Polmas UMKM (Demo)'},
          {'role': null, 'place': 'Keluarga Siti', 'app': 'tata-warga'},
        ],
      });
      expect(c.hasPassword, isFalse);
      expect(c.contactLines, ['Satpam · Toko Roti Sinar Jaya', 'Keluarga Siti']);
    });

    test('laporan: judul & lokasi singkat', () {
      final r = Report({
        'id': 'x',
        'kind': 'laporan',
        'category': 'pencurian',
        'status': 'diverifikasi',
        'kelurahan': {'code': '32.71.03.1002', 'name': 'Paledang'},
        'location_text': 'Jl. Suryakencana No. 5',
        'created_at': '2026-11-25T10:00:00Z',
      });
      expect(r.headline, 'Pencurian');
      expect(r.status, PkStatus.diverifikasi);
      expect(r.placeLine, 'Kel. Paledang · Jl. Suryakencana No. 5');
    });
  });

  testWidgets('lencana status selalu berteks (bukan warna saja)', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Column(children: [StatusPill(status: PkStatus.baru, sos: true), StatusPill(status: PkStatus.ditangani, sos: false)])),
      ),
    );
    expect(find.text('Darurat'), findsOneWidget);
    expect(find.text('Diproses'), findsOneWidget);
  });
}
