import 'package:flutter/material.dart';

/// Semantic design tokens for LittleNet V2.
class AppColors {
  // Brand Colors
  static const Color primary = Color(0xFF6C5CE7); // Friendly Indigo/Violet
  static const Color primaryLight = Color(0xFFA29BFE);
  static const Color primaryDark = Color(0xFF4834D4);

  // Mode Accents
  static const Color kidsAccent = Color(0xFFFF7675); // Warm Coral
  static const Color kidsGold = Color(0xFFFDCB6E); // Sunshine Yellow
  static const Color kidsMint = Color(0xFF00B894); // Educational Mint
  static const Color parentAccent = Color(0xFF0984E3); // Trust Blue
  static const Color moderatorAccent = Color(0xFF636E72); // Professional Slate

  // Neutral Backgrounds & Surfaces
  static const Color background = Color(0xFFF8F9FE);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceElevated = Color(0xFFFFFFFF);
  static const Color cardBorder = Color(0xFFE9ECEF);

  // Text Colors
  static const Color textPrimary = Color(0xFF2D3436);
  static const Color textSecondary = Color(0xFF636E72);
  static const Color textMuted = Color(0xFFB2BEC3);
  static const Color textLight = Color(0xFFFFFFFF);

  // Semantic Status Colors
  static const Color success = Color(0xFF00B894);
  static const Color warning = Color(0xFFE17055);
  static const Color error = Color(0xFFD63031);
  static const Color info = Color(0xFF0984E3);

  // Safety Gate Colors
  static const Color safeAllowed = Color(0xFF00B894);
  static const Color safeReview = Color(0xFFF39C12);
  static const Color safeBlocked = Color(0xFFE74C3C);
}
