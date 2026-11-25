import 'dart:math' as math;

import 'package:intl/intl.dart';

final _day = DateFormat('EEEE, d MMMM y', 'id');
final _short = DateFormat('d MMM y', 'id');
final _time = DateFormat('HH.mm', 'id');
final _dateTime = DateFormat('d MMM y, HH.mm', 'id');

String fmtDay(DateTime d) => _day.format(d);
String fmtShort(DateTime d) => _short.format(d);
String fmtTime(DateTime d) => _time.format(d);

/// "Sabtu".
String fmtWeekday(DateTime d) => DateFormat('EEEE', 'id').format(d);

/// "Sab".
String fmtWeekdayShort(DateTime d) => const ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'][d.weekday - 1];

/// "25 Nov".
String fmtDayMonth(DateTime d) => DateFormat('d MMM', 'id').format(d);
String fmtDateTime(DateTime d) => _dateTime.format(d);

/// "Hari ini", "Kemarin", atau tanggal lengkap: judul kelompok riwayat per hari.
String fmtDayHeader(DateTime d) {
  final now = DateTime.now();
  final a = DateTime(d.year, d.month, d.day);
  final b = DateTime(now.year, now.month, now.day);
  final diff = b.difference(a).inDays;
  if (diff == 0) return 'Hari ini';
  if (diff == 1) return 'Kemarin';
  return _day.format(d);
}

/// Waktu relatif singkat: "baru saja", "5 mnt lalu", "3 jam lalu", "2 hari lalu".
String fmtRelative(DateTime d) {
  final s = DateTime.now().difference(d);
  if (s.inSeconds < 60) return 'baru saja';
  if (s.inMinutes < 60) return '${s.inMinutes} mnt lalu';
  if (s.inHours < 24) return '${s.inHours} jam lalu';
  if (s.inDays < 7) return '${s.inDays} hari lalu';
  return _short.format(d);
}

/// Durasi dalam detik → "45 dtk", "12 mnt", "3 j 20 mnt".
String fmtDuration(num? seconds) {
  if (seconds == null) return '–';
  final s = seconds.round();
  if (s < 60) return '$s dtk';
  final m = s ~/ 60;
  if (m < 60) return '$m mnt';
  final h = m ~/ 60;
  final rm = m % 60;
  if (h < 24) return rm == 0 ? '$h j' : '$h j $rm mnt';
  return '${h ~/ 24} hr ${h % 24} j';
}

String fmtNumber(num n) => NumberFormat.decimalPattern('id').format(n);

/// Jarak lurus dua titik (meter, haversine).
double distanceM(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1), dLng = rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}

/// "± 350 m" / "± 1,2 km".
String fmtDistance(double m) {
  if (m < 1000) return '± ${(m / 10).round() * 10} m';
  return '± ${(m / 1000).toStringAsFixed(m < 10000 ? 1 : 0).replaceAll('.', ',')} km';
}

/// "Hari ini, 15.20 WIB" / "Kemarin, 20.15 WIB" / "3 Nov 2026, 08.00 WIB".
String fmtDayTime(DateTime d) {
  final head = fmtDayHeader(d);
  return '${head.contains(',') ? fmtShort(d) : head}, ${fmtTime(d)} WIB';
}

/// 628001110001 → "0800-111-0001" untuk ditampilkan.
String fmtPhone(String p) {
  var d = p.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.startsWith('62')) d = '0${d.substring(2)}';
  if (d.length < 8) return d;
  return '${d.substring(0, 4)}-${d.substring(4, d.length - 4)}-${d.substring(d.length - 4)}';
}

/// Bagian lokal nomor (tanpa 0/62) → "812-3456-7890": 3 digit, 4 digit, sisanya.
String dashLocal(String digits) {
  final d = digits.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.length <= 3) return d;
  if (d.length <= 7) return '${d.substring(0, 3)}-${d.substring(3)}';
  return '${d.substring(0, 3)}-${d.substring(3, 7)}-${d.substring(7)}';
}

/// 628123456789 → "+62 812-3456-789" (gaya tampilan profil & login).
String fmtPhoneIntl(String p) {
  var d = p.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.startsWith('62')) d = d.substring(2);
  if (d.startsWith('0')) d = d.substring(1);
  return '+62 ${dashLocal(d)}';
}

String greeting() {
  final h = DateTime.now().hour;
  if (h < 11) return 'Selamat pagi';
  if (h < 15) return 'Selamat siang';
  if (h < 18) return 'Selamat sore';
  return 'Selamat malam';
}
