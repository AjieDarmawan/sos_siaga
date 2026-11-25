import 'package:flutter/material.dart';

/// Design token Polmas Keamanan (PRD §7.1). Merah dipakai terutama untuk SOS & status darurat.
abstract final class PK {
  static const red = Color(0xFFD71920);
  static const redDark = Color(0xFFA80F15);
  static const white = Color(0xFFFFFFFF);
  static const navy = Color(0xFF0B2A6B);
  static const gold = Color(0xFFE3A82B);
  static const green = Color(0xFF16A34A);
  static const bg = Color(0xFFF4F6FA);
  static const text = Color(0xFF0F172A);
  static const text2 = Color(0xFF475569);
  static const line = Color(0xFFE2E8F0);
  static const grey = Color(0xFF64748B);

  // Mode gelap: navy sangat tua, merah dilembutkan.
  static const darkBg = Color(0xFF060F24);
  static const darkSurface = Color(0xFF0E1A36);
  static const darkLine = Color(0xFF1E2C4D);
  static const redSoft = Color(0xFFE5484D);

  // Jarak (kelipatan 4) & radius.
  static const s4 = 4.0, s8 = 8.0, s12 = 12.0, s16 = 16.0, s24 = 24.0, s32 = 32.0;
  static const rCard = 16.0, rButton = 14.0, rField = 12.0;

  static const cardShadow = [BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 4))];
  static const sosGlow = [BoxShadow(color: Color(0x59D71920), blurRadius: 24, offset: Offset(0, 8))];

  // Durasi animasi (PRD §7.4).
  static const splashOut = Duration(milliseconds: 400);
  static const step = Duration(milliseconds: 280);
  static const shake = Duration(milliseconds: 320);
  static const mapZoom = Duration(milliseconds: 900);
  static const fieldFill = Duration(milliseconds: 150);
  static const sosPulse = Duration(milliseconds: 1200);
  static const countUp = Duration(milliseconds: 800);
  static const cardIn = Duration(milliseconds: 300);
  static const cardStagger = Duration(milliseconds: 60);
  static const tab = Duration(milliseconds: 250);
  static const check = Duration(milliseconds: 500);
}

/// Warna yang menyesuaikan terang/gelap.
extension PKColors on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get surface => isDark ? PK.darkSurface : PK.white;
  Color get pageBg => isDark ? PK.darkBg : PK.bg;
  Color get ink => isDark ? const Color(0xFFF1F5F9) : PK.text;
  Color get ink2 => isDark ? const Color(0xFFA5B4CC) : PK.text2;
  Color get hairline => isDark ? PK.darkLine : PK.line;
  Color get danger => isDark ? PK.redSoft : PK.red;

  /// Merah untuk teks kecil: Merah Tua di mode terang supaya kontras ≥ 4,5:1.
  Color get dangerText => isDark ? const Color(0xFFFF8A8E) : PK.redDark;
  Color get brand => isDark ? const Color(0xFF8FB0FF) : PK.navy;

  /// "Kurangi gerakan" di perangkat.
  bool get reduceMotion => MediaQuery.maybeOf(this)?.disableAnimations ?? false;
}
