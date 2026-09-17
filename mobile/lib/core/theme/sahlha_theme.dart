import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'sahlha_colors.dart';
import 'sahlha_spacing.dart';

/// Material 3 theme for Sahlha. Nunito: rounded, readable, calm.
abstract final class SahlhaTheme {
  static ThemeData light() {
    final base = ThemeData(useMaterial3: true);
    final text = GoogleFonts.nunitoTextTheme(base.textTheme);
    final scheme = ColorScheme.fromSeed(
      seedColor: SahlhaColors.teal,
      primary: SahlhaColors.teal,
      surface: SahlhaColors.surface,
    );
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: SahlhaColors.cream,
      textTheme: text.copyWith(
        displaySmall: text.displaySmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: SahlhaColors.ink,
        ),
        headlineSmall: text.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: SahlhaColors.ink,
        ),
        titleLarge: text.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: SahlhaColors.ink,
        ),
        titleMedium: text.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: SahlhaColors.ink,
        ),
        bodyLarge: text.bodyLarge?.copyWith(
          color: SahlhaColors.ink,
          height: 1.55,
        ),
        bodyMedium: text.bodyMedium?.copyWith(
          color: SahlhaColors.ink,
          height: 1.55,
        ),
        bodySmall: text.bodySmall?.copyWith(
          color: SahlhaColors.muted,
          height: 1.5,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: SahlhaColors.cream,
        foregroundColor: SahlhaColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: const CardThemeData(
        color: SahlhaColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(SahlhaRadius.lg)),
          side: BorderSide(color: SahlhaColors.line),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: SahlhaColors.teal,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(SahlhaRadius.lg)),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: SahlhaColors.tealDark,
          minimumSize: const Size.fromHeight(54),
          side: const BorderSide(color: SahlhaColors.teal, width: 1.5),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(SahlhaRadius.lg)),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: SahlhaColors.tealDark,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: SahlhaColors.surface,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(SahlhaRadius.md)),
          borderSide: BorderSide(color: SahlhaColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(SahlhaRadius.md)),
          borderSide: BorderSide(color: SahlhaColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(SahlhaRadius.md)),
          borderSide: BorderSide(color: SahlhaColors.teal, width: 2),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: SahlhaColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(SahlhaRadius.lg),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: SahlhaColors.surface,
        indicatorColor: SahlhaColors.tealSoft,
        labelTextStyle: WidgetStatePropertyAll(
          text.labelSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      dividerColor: SahlhaColors.line,
    );
  }
}
