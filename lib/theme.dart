import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Design system (UI/UX Pro Max): dark fintech, gold trust accent, Inter.
class AppColors {
  static const background = Color(0xFF0F172A);
  static const card = Color(0xFF222735);
  static const muted = Color(0xFF272F42);
  static const border = Color(0xFF334155);
  static const primary = Color(0xFFF59E0B);
  static const accent = Color(0xFF8B5CF6);
  static const foreground = Color(0xFFF8FAFC);
  static const mutedForeground = Color(0xFF94A3B8);
  static const up = Color(0xFF22C55E);
  static const down = Color(0xFFEF4444);
}

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.dark,
  ).copyWith(
    surface: AppColors.background,
    onSurface: AppColors.foreground,
    primary: AppColors.primary,
    onPrimary: AppColors.background,
    secondary: AppColors.accent,
    error: AppColors.down,
    outline: AppColors.border,
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: AppColors.foreground,
      displayColor: AppColors.foreground,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.foreground,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: AppColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border, width: 0.6),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.card,
      indicatorColor: AppColors.primary.withValues(alpha: 0.18),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: AppColors.muted,
      selectedColor: AppColors.primary,
      labelStyle: const TextStyle(color: AppColors.foreground, fontSize: 12),
      side: const BorderSide(color: AppColors.border, width: 0.6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.muted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
      ),
      labelStyle: const TextStyle(color: AppColors.mutedForeground),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    dividerColor: AppColors.border,
  );
}

/// Format helpers for IDX numbers.
String fmtNum(num? v, {int dec = 0}) {
  if (v == null) return '-';
  final s = v.toStringAsFixed(dec);
  final parts = s.split('.');
  final intPart = parts[0];
  final neg = intPart.startsWith('-');
  final digits = neg ? intPart.substring(1) : intPart;
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
    buf.write(digits[i]);
  }
  return (neg ? '-' : '') + buf.toString() + (parts.length > 1 ? ',${parts[1]}' : '');
}

String fmtPct(num? v, {bool sign = true}) {
  if (v == null) return '-';
  final s = (sign && v > 0) ? '+' : '';
  return '$s${v.toStringAsFixed(2).replaceAll('.', ',')}%';
}

String fmtBig(num? v) {
  if (v == null) return '-';
  final a = v.abs();
  if (a >= 1e12) return '${fmtNum(a / 1e12, dec: 1)} T';
  if (a >= 1e9) return '${fmtNum(a / 1e9, dec: 1)} M';
  if (a >= 1e6) return '${fmtNum(a / 1e6, dec: 1)} jt';
  return fmtNum(v);
}

Color pctColor(num? v) =>
    v == null ? AppColors.mutedForeground : (v >= 0 ? AppColors.up : AppColors.down);
