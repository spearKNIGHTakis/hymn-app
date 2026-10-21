import 'package:flutter/material.dart';

class AppColors {
  static const blue = Color(0xFF174A8B);
  static const red = Color(0xFFC62828);
  static const green = Color(0xFF287447);
  static const cream = Color(0xFFF7F5EF);
  static const charcoal = Color(0xFF20252B);
  static const muted = Color(0xFF6B7280);
}

class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.blue,
      brightness: brightness,
      primary: AppColors.blue,
      secondary: AppColors.green,
      error: AppColors.red,
      surface: dark ? const Color(0xFF191E24) : Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? const Color(0xFF11161B) : AppColors.cream,
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? const Color(0xFF11161B) : AppColors.cream,
        foregroundColor: dark ? Colors.white : AppColors.charcoal,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: dark ? const Color(0xFF191E24) : Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF222A32) : Colors.white,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: scheme.primary, width: 1.5)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: dark ? const Color(0xFF191E24) : Colors.white,
        indicatorColor: scheme.primaryContainer,
      ),
    );
  }
}
