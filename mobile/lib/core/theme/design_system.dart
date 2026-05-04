import 'package:flutter/material.dart';

/// 🎨 SafeRoute Unified Design System
class DesignSystem {
  static const ColorTokens colors = ColorTokens();
  static const SpacingTokens spacing = SpacingTokens();
  static const MotionTokens motion = MotionTokens();
  static const StyleTokens style = StyleTokens();
}

class ColorTokens {
  const ColorTokens();

  final Color primary = const Color(0xFF8B5CF6);
  final Color primaryLight = const Color(0xFFA78BFA);
  final Color primaryDark = const Color(0xFF6D28D9);
  final Color primaryHighContrast = const Color(0xFF4C1D95);

  final Color accent = const Color(0xFF2DD4BF);
  final Color accentSecondary = const Color(0xFFF43F5E);
  final Color midnight = const Color(0xFF0F172A);

  final Color danger = const Color(0xFFF43F5E);
  final Color warning = const Color(0xFFF59E0B);
  final Color success = const Color(0xFF10B981);
  final Color info = const Color(0xFF3B82F6);

  final Color backgroundLight = const Color(0xFFF8FAFC);
  final Color surfaceLight = Colors.white;
  final Color textPrimaryLight = const Color(0xFF020617);
  final Color textSecondaryLight = const Color(0xFF334155);

  final Color backgroundDark = const Color(0xFF020617);
  final Color surfaceDark = const Color(0xFF0F172A);
  final Color textPrimaryDark = const Color(0xFFF8FAFC);
  final Color textSecondaryDark = const Color(0xFF94A3B8);

  final Color surfaceGlass = const Color(0x1AFFFFFF);
  final Color glowColor = const Color(0x4D8B5CF6);
  final Color overlayLight = const Color(0x1A000000);
  final Color overlayDark = const Color(0x33FFFFFF);
  final Color dividerLight = const Color(0xFFE2E8F0);
  final Color dividerDark = const Color(0xFF1E293B);
}

class SpacingTokens {
  const SpacingTokens();

  final double xs = 4.0;
  final double s = 8.0;
  final double m = 16.0;
  final double l = 24.0;
  final double xl = 32.0;
  final double xxl = 48.0;

  final double radiusS = 8.0;
  final double radiusM = 12.0;
  final double radiusL = 16.0;
  final double radiusXL = 24.0;
  final double radiusFull = 32.0;

  final double minTouchTarget = 48.0;
}

class MotionTokens {
  const MotionTokens();
  final Duration micro = const Duration(milliseconds: 100);
  final Duration fast = const Duration(milliseconds: 150);
  final Duration standard = const Duration(milliseconds: 200);
  final Duration slow = const Duration(milliseconds: 400);

  final Curve curve = Curves.easeOutQuart;
  final Curve fastCurve = Curves.easeOutCubic;
  final Curve spring = Curves.elasticOut;
  final Curve smooth = Curves.easeInOutCubic;
}

class StyleTokens {
  const StyleTokens();
}
