import 'package:flutter/material.dart';

import 'stitch_design.dart';

/// Native Flutter design system ported from the uploaded LittleNet Stitch UI.
abstract final class LittleNetTheme {
  static const Color primary = StitchTokens.blue;
  static const Color ink = StitchTokens.ink;
  static const Color divider = StitchTokens.border;
  static const Color canvas = StitchTokens.canvas;
  static const Color softCanvas = StitchTokens.softCanvas;
  static const Color success = StitchTokens.safe;
  static const Color warning = StitchTokens.review;
  static const Color danger = StitchTokens.blocked;

  static ThemeData light() {
    const radius = BorderRadius.all(Radius.circular(8));
    const inputRadius = BorderRadius.all(Radius.circular(6));

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: canvas,
      canvasColor: canvas,
      dividerColor: divider,
      colorScheme: const ColorScheme.light(
        primary: primary,
        onPrimary: Colors.white,
        surface: canvas,
        onSurface: ink,
        error: danger,
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: ink, fontSize: 14, height: 1.35),
        bodyMedium: TextStyle(color: ink, fontSize: 13, height: 1.35),
        bodySmall: TextStyle(color: StitchTokens.muted, fontSize: 11, height: 1.25),
        titleLarge: TextStyle(color: ink, fontSize: 20, fontWeight: FontWeight.w700),
        titleMedium: TextStyle(color: ink, fontSize: 15, fontWeight: FontWeight.w700),
        titleSmall: TextStyle(color: ink, fontSize: 13, fontWeight: FontWeight.w700),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: canvas,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 48,
        titleSpacing: 16,
        iconTheme: IconThemeData(color: ink, size: 24),
        titleTextStyle: TextStyle(
          color: ink,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -.35,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: canvas,
        selectedItemColor: ink,
        unselectedItemColor: ink,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 52,
        backgroundColor: canvas,
        elevation: 0,
        indicatorColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: ink,
            size: states.contains(WidgetState.selected) ? 26 : 24,
          ),
        ),
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        color: canvas,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: Color(0xFFEDEDED), width: .7),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Color(0xFFF5F5F5),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        hintStyle: TextStyle(color: StitchTokens.muted, fontSize: 13),
        labelStyle: TextStyle(color: StitchTokens.muted, fontSize: 13),
        border: OutlineInputBorder(
          borderRadius: inputRadius,
          borderSide: BorderSide(color: divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: inputRadius,
          borderSide: BorderSide(color: divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: inputRadius,
          borderSide: BorderSide(color: primary, width: 1),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: canvas,
        modalBackgroundColor: canvas,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: Color(0xFFC7C7C7),
        dragHandleSize: Size(36, 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: canvas,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 44),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(48, 40),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          side: const BorderSide(color: divider),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: softCanvas,
        side: BorderSide(color: divider),
        labelStyle: TextStyle(color: ink, fontSize: 11, fontWeight: FontWeight.w600),
        shape: StadiumBorder(),
      ),
      splashColor: Colors.black12,
      highlightColor: Colors.transparent,
    );
  }
}
