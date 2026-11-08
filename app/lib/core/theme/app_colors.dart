import 'package:flutter/material.dart';

/// Brand palette from the product brief.
abstract final class AppColors {
  static const Color navy = Color(0xFF0B3C6D); // Primary
  static const Color white = Color(0xFFFFFFFF); // Secondary
  static const Color gold = Color(0xFFD4AF37); // Accent
  static const Color background = Color(0xFFF5F7FA); // Background

  // Supporting tones
  static const Color navyDeep = Color(0xFF072845);
  static const Color navyBright = Color(0xFF1D5B98);
  static const Color goldSoft = Color(0xFFF6EBC5);
  static const Color onGold = Color(0xFF2A2104);

  static const Color darkBackground = Color(0xFF07111F);
  static const Color darkSurface = Color(0xFF0E1C2F);

  static const Color success = Color(0xFF1E8E5A);
  static const Color warning = Color(0xFFB7791F);
  static const Color danger = Color(0xFFC0392B);

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [navyDeep, navy, navyBright],
  );
}
