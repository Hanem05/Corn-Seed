import 'package:flutter/material.dart';

class AppTheme {
  static const forest = Color(0xFF163F32);
  static const canvas = Color(0xFFF6F5EF);
  static const gold = Color(0xFFE9C76B);
  static ThemeData get light {
    final colors = ColorScheme.fromSeed(seedColor: forest).copyWith(
        primary: forest,
        onPrimary: Colors.white,
        surface: canvas,
        onSurface: const Color(0xFF192D25),
        onSurfaceVariant: const Color(0xFF637169),
        primaryContainer: const Color(0xFFE3ECE4),
        outlineVariant: const Color(0xFFDCE1D8));
    final base = ThemeData(useMaterial3: true, colorScheme: colors);
    return base.copyWith(
      scaffoldBackgroundColor: canvas,
      textTheme: base.textTheme.copyWith(
        headlineLarge: const TextStyle(
            fontSize: 36,
            height: 1.12,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.3,
            color: forest),
        headlineSmall: const TextStyle(
            fontSize: 26,
            height: 1.2,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.7,
            color: forest),
        titleLarge: const TextStyle(
            fontSize: 21, fontWeight: FontWeight.w700, color: forest),
        bodyLarge: const TextStyle(fontSize: 16, height: 1.5, color: forest),
        bodyMedium: const TextStyle(fontSize: 14, height: 1.45, color: forest),
      ),
      appBarTheme: const AppBarTheme(
          backgroundColor: canvas,
          foregroundColor: forest,
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0),
      cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              minimumSize: const Size(48, 56),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              textStyle:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 56),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              side: BorderSide(color: colors.outlineVariant))),
      snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: forest,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
    );
  }
}
