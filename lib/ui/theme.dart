import 'package:flutter/material.dart';

class C {
  static const ink = Color(0xFF111A33);
  static const paper = Color(0xFFF2F5FB);
  static const surface = Colors.white;
  static const blue = Color(0xFF3556FF);
  static const violet = Color(0xFF8C6BFF);
  static const mint = Color(0xFF14B88F);
  static const amber = Color(0xFFFFB84D);
  static const muted = Color(0xFF65708C);
  static const line = Color(0xFFDCE2F0);
  static const warn = Color(0xFFD9542C);
  static const noteBg = Color(0xFFFFF3D6);
  static const noteFg = Color(0xFF7A4B00);
}

ThemeData buildTheme() {
  final base = ThemeData(useMaterial3: true, brightness: Brightness.light);
  return base.copyWith(
    colorScheme: ColorScheme.fromSeed(seedColor: C.blue, brightness: Brightness.light)
        .copyWith(primary: C.blue, surface: C.surface),
    scaffoldBackgroundColor: C.paper,
    textTheme: base.textTheme.apply(bodyColor: C.ink, displayColor: C.ink),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: C.surface,
      indicatorColor: C.blue.withValues(alpha: .12),
      height: 68,
    ),
  );
}
