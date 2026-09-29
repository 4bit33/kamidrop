import 'package:flutter/material.dart';

/// Палітра в японському дусі: папір васі, туш сумі, кіновар шу для печатки-ханко.
class Kami {
  static const washi = Color(0xFFF5F1E8); // тло, теплий папір
  static const paper = Color(0xFFFFFDF8); // картки
  static const sumi = Color(0xFF1F1D1A); // основний текст
  static const stone = Color(0xFF7A746A); // другорядний текст
  static const line = Color(0xFFE2DBCD); // тонкі лінії
  static const shu = Color(0xFFC8412E); // акцент, печатка
  static const matcha = Color(0xFF5B8A5A); // «готовий»
  static const kincha = Color(0xFFC68A2C); // «зайнятий»
}

ThemeData kamiTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Kami.shu,
    brightness: Brightness.light,
  ).copyWith(
    primary: Kami.shu,
    onPrimary: Colors.white,
    surface: Kami.washi,
    onSurface: Kami.sumi,
    outline: Kami.line,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Kami.washi,
    textTheme: const TextTheme(
      headlineMedium: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: Kami.sumi),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Kami.sumi),
      bodyMedium: TextStyle(fontSize: 14, color: Kami.sumi),
      bodySmall: TextStyle(fontSize: 12, color: Kami.stone),
    ),
    cardTheme: const CardThemeData(
      color: Kami.paper,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: Kami.line),
      ),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: Kami.washi,
      side: BorderSide(color: Kami.line),
      labelStyle: TextStyle(fontSize: 12, color: Kami.sumi),
      padding: EdgeInsets.symmetric(horizontal: 4),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Kami.washi, showDragHandle: true),
  );
}
