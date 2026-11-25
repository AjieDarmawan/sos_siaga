import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

/// Tipografi PRD: Plus Jakarta Sans. Judul layar 24/32 bold, judul kartu 18/24 semibold, isi 16/24,
/// keterangan 13/18 medium, angka dashboard 32/36 bold. Isi teks tidak di bawah 14.
ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final ink = dark ? const Color(0xFFF1F5F9) : PK.text;
  final ink2 = dark ? const Color(0xFFA5B4CC) : PK.text2;
  final base = ThemeData(brightness: b, useMaterial3: true);
  final text = GoogleFonts.plusJakartaSansTextTheme(base.textTheme).copyWith(
    headlineSmall: GoogleFonts.plusJakartaSans(fontSize: 24, height: 32 / 24, fontWeight: FontWeight.w700, color: ink),
    titleLarge: GoogleFonts.plusJakartaSans(fontSize: 20, height: 28 / 20, fontWeight: FontWeight.w700, color: ink),
    titleMedium: GoogleFonts.plusJakartaSans(fontSize: 18, height: 24 / 18, fontWeight: FontWeight.w600, color: ink),
    titleSmall: GoogleFonts.plusJakartaSans(fontSize: 16, height: 22 / 16, fontWeight: FontWeight.w600, color: ink),
    bodyLarge: GoogleFonts.plusJakartaSans(fontSize: 16, height: 24 / 16, color: ink),
    bodyMedium: GoogleFonts.plusJakartaSans(fontSize: 14, height: 20 / 14, color: ink),
    bodySmall: GoogleFonts.plusJakartaSans(fontSize: 13, height: 18 / 13, fontWeight: FontWeight.w500, color: ink2),
    labelLarge: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600),
    labelMedium: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: ink2),
    displaySmall: GoogleFonts.plusJakartaSans(fontSize: 32, height: 36 / 32, fontWeight: FontWeight.w700, color: ink),
  );
  final scheme = ColorScheme.fromSeed(
    seedColor: PK.navy,
    brightness: b,
    primary: dark ? const Color(0xFF8FB0FF) : PK.navy,
    onPrimary: dark ? PK.darkBg : PK.white,
    secondary: PK.gold,
    error: dark ? PK.redSoft : PK.red,
    surface: dark ? PK.darkSurface : PK.white,
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? PK.darkBg : PK.bg,
    textTheme: text,
    dividerColor: dark ? PK.darkLine : PK.line,
    dividerTheme: DividerThemeData(color: dark ? PK.darkLine : PK.line, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? PK.darkBg : PK.bg,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? PK.darkSurface : PK.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PK.rField),
        borderSide: BorderSide(color: dark ? PK.darkLine : PK.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PK.rField),
        borderSide: BorderSide(color: dark ? PK.darkLine : const Color(0xFFCBD5E1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PK.rField),
        borderSide: BorderSide(color: dark ? const Color(0xFF8FB0FF) : PK.navy, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PK.rField),
        borderSide: BorderSide(color: dark ? PK.redSoft : PK.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PK.rField),
        borderSide: BorderSide(color: dark ? PK.redSoft : PK.red, width: 2),
      ),
      labelStyle: TextStyle(color: ink2),
      errorStyle: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w500, color: dark ? const Color(0xFFFF8A8E) : PK.redDark),
    ),
    chipTheme: base.chipTheme.copyWith(
      labelStyle: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: ink),
      shape: const StadiumBorder(),
      side: BorderSide(color: dark ? PK.darkLine : PK.line),
      backgroundColor: dark ? PK.darkSurface : PK.white,
      selectedColor: (dark ? const Color(0xFF8FB0FF) : PK.navy).withValues(alpha: 0.14),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? PK.darkSurface : PK.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      showDragHandle: true,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder(), TargetPlatform.iOS: CupertinoPageTransitionsBuilder()},
    ),
  );
}
