import 'package:flutter/material.dart';

/// 🎨 SafeRoute Aurora Elite Color System
/// A world-class palette blending Deep Orchid, Aurora Teal, and Neon Coral.
class AppColors {
  // Brand Colors (Aurora Palette)
  static const Color primary = Color(0xFF8B5CF6); // Deep Orchid
  static const Color primaryLight = Color(0xFFA78BFA);
  static const Color primaryDark = Color(0xFF6D28D9);

  static const Color accent = Color(0xFF2DD4BF); // Aurora Teal
  static const Color accentSecondary = Color(0xFFF43F5E); // Neon Coral

  // New Strategy Token
  static const Color midnight = Color(0xFF0F172A); // Deep Navy Slate

  // Neutral Palette (field utility)
  static const Color backgroundLight = Color(0xFFF8FAFC); // Very Light Silk
  static const Color surfaceLight = Colors.white;
  static const Color backgroundDark = Color(0xFF0B1120); // Night field surface
  static const Color surfaceDark = Color(0xFF1C1C1E); // Dark card surface

  // Text Colors (High Contrast)
  static const Color textPrimaryLight = Color(0xFF020617); // Almost Black
  static const Color textSecondaryLight = Color(0xFF334155); // Dark Slate Gray
  static const Color textPrimaryDark = Color(0xFFF8FAFC);
  static const Color textSecondaryDark = Color(0xFF94A3B8);

  // High-Dynamic-Range (HDR) Tokens
  static const Color primaryHighContrast = Color(0xFFA855F7); // Neon Purple
  static const Color accentHighContrast = Color(0xFF34D399); // Emerald Glow

  static const Color surfaceGlass = Color(0x1AFFFFFF);
  static const Color glowColor = Color(0x4D8B5CF6);

  // Functional Zone Colors (Consistent - NEVER override by theme)
  static const Color danger = Color(0xFFF43F5E); // Red
  static const Color warning = Color(0xFFF59E0B); // Yellow
  static const Color success = Color(0xFF10B981); // Green
  static const Color info = Color(0xFF3B82F6); // Blue

  // Legacy zone names (kept for compatibility)
  static const Color zoneRed = danger;
  static const Color zoneYellow = warning;
  static const Color zoneGreen = success;

  // Subtle surfaces and overlays
  static const Color overlayLight = Color(0x1A000000);
  static const Color overlayDark = Color(0x33FFFFFF);
  static const Color dividerLight = Color(0xFFE2E8F0);
  static const Color dividerDark = Color(0xFF1E293B);
}

/// 📏 Elite Spacing & Glass Tokens (8dp grid)
@immutable
class SafeRouteColors extends ThemeExtension<SafeRouteColors> {
  final Color safe;
  final Color caution;
  final Color restricted;
  final Color offline;
  final Color mesh;
  final Color sync;
  final Color mapOverlay;
  final Color mapOverlayText;

  const SafeRouteColors({
    required this.safe,
    required this.caution,
    required this.restricted,
    required this.offline,
    required this.mesh,
    required this.sync,
    required this.mapOverlay,
    required this.mapOverlayText,
  });

  static const light = SafeRouteColors(
    safe: AppColors.success,
    caution: AppColors.warning,
    restricted: AppColors.danger,
    offline: Color(0xFFB91C1C),
    mesh: AppColors.info,
    sync: AppColors.accent,
    mapOverlay: Color(0xF7FFFFFF),
    mapOverlayText: AppColors.textPrimaryLight,
  );

  static const dark = SafeRouteColors(
    safe: AppColors.success,
    caution: AppColors.warning,
    restricted: AppColors.danger,
    offline: Color(0xFFFF6B6B),
    mesh: Color(0xFF60A5FA),
    sync: AppColors.accent,
    mapOverlay: Color(0xF21C1C1E),
    mapOverlayText: AppColors.textPrimaryDark,
  );

  @override
  SafeRouteColors copyWith({
    Color? safe,
    Color? caution,
    Color? restricted,
    Color? offline,
    Color? mesh,
    Color? sync,
    Color? mapOverlay,
    Color? mapOverlayText,
  }) {
    return SafeRouteColors(
      safe: safe ?? this.safe,
      caution: caution ?? this.caution,
      restricted: restricted ?? this.restricted,
      offline: offline ?? this.offline,
      mesh: mesh ?? this.mesh,
      sync: sync ?? this.sync,
      mapOverlay: mapOverlay ?? this.mapOverlay,
      mapOverlayText: mapOverlayText ?? this.mapOverlayText,
    );
  }

  @override
  SafeRouteColors lerp(ThemeExtension<SafeRouteColors>? other, double t) {
    if (other is! SafeRouteColors) return this;
    return SafeRouteColors(
      safe: Color.lerp(safe, other.safe, t)!,
      caution: Color.lerp(caution, other.caution, t)!,
      restricted: Color.lerp(restricted, other.restricted, t)!,
      offline: Color.lerp(offline, other.offline, t)!,
      mesh: Color.lerp(mesh, other.mesh, t)!,
      sync: Color.lerp(sync, other.sync, t)!,
      mapOverlay: Color.lerp(mapOverlay, other.mapOverlay, t)!,
      mapOverlayText: Color.lerp(mapOverlayText, other.mapOverlayText, t)!,
    );
  }
}

class AppSpacing {
  static const double xs = 4.0;
  static const double s = 8.0;
  static const double m = 16.0;
  static const double l = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;

  // Consistent border radius
  static const double radiusS = 8.0;
  static const double radiusM = 12.0;
  static const double radiusL = 14.0;
  static const double radiusXL = 16.0;
  static const double radiusFull = 32.0;

  // Min touch target (accessibility)
  static const double minTouchTarget = 48.0;
  static const double fieldActionTarget = 56.0;
}

/// 🎞️ Elite Motion Design (all ≤200ms for performance)
class AppMotion {
  static const Duration micro = Duration(milliseconds: 100);
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration standard = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 400);

  static const Curve curve = Curves.easeOutQuart;
  static const Curve fastCurve = Curves.easeOutCubic;
  static const Curve spring = Curves.elasticOut;
  static const Curve smooth = Curves.easeInOutCubic;
}

/// 🏔️ Elite Elevation & Depths
class AppElevation {
  static List<BoxShadow> level1 = [
    BoxShadow(
      color: AppColors.primary.withValues(alpha: 0.1),
      blurRadius: 12,
      spreadRadius: -2,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> level2 = [
    BoxShadow(
      color: AppColors.primary.withValues(alpha: 0.15),
      blurRadius: 24,
      spreadRadius: -4,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> level3 = [
    BoxShadow(
      color: AppColors.primary.withValues(alpha: 0.2),
      blurRadius: 42,
      spreadRadius: -8,
      offset: const Offset(0, 16),
    ),
  ];
}

/// 🧊 Elite Glassmorphism & Gloom System
class AppStyle {
  static BoxDecoration glass({
    required Color color,
    double blur = 20,
    double radius = 24,
    Color? borderColor,
    double borderOpacity = 0.1,
  }) {
    return BoxDecoration(
      color: color.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: (borderColor ?? Colors.white).withValues(alpha: borderOpacity),
        width: 1.5,
      ),
    );
  }

  static List<BoxShadow> aura(Color color,
          {double opacity = 0.15, double blur = 30}) =>
      [
        BoxShadow(
          color: color.withValues(alpha: opacity),
          blurRadius: blur,
          spreadRadius: 0,
          offset: const Offset(0, 8),
        ),
      ];
}

/// 👔 SafeRoute Aurora Theme (Material 3)
class AppTheme {
  static ThemeData light() {
    const colorScheme = ColorScheme.light(
      primary: AppColors.primary,
      secondary: AppColors.accent,
      surface: AppColors.surfaceLight,
      error: AppColors.danger,
      onSurface: AppColors.textPrimaryLight,
      onError: Colors.white,
      onPrimary: Colors.white,
      outline: AppColors.dividerLight,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      extensions: const [SafeRouteColors.light],
      scaffoldBackgroundColor: AppColors.backgroundLight,

      // AppBar (transparent, clean)
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimaryLight,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),

      // Enhanced Typography (Material 3 compliant)
      textTheme: const TextTheme(
        // Headlines
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: AppColors.textPrimaryLight,
          height: 1.25,
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: AppColors.textPrimaryLight,
          height: 1.3,
        ),
        displaySmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: AppColors.textPrimaryLight,
          height: 1.33,
        ),
        // Headlines
        headlineLarge: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: AppColors.textPrimaryLight,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          color: AppColors.textPrimaryLight,
        ),
        headlineSmall: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          color: AppColors.textPrimaryLight,
        ),
        // Titles
        titleLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.15,
          color: AppColors.textPrimaryLight,
        ),
        titleMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
          color: AppColors.textPrimaryLight,
        ),
        titleSmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
          color: AppColors.textPrimaryLight,
        ),
        // Body
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          color: AppColors.textPrimaryLight,
          height: 1.5,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          color: AppColors.textSecondaryLight,
          height: 1.43,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          color: AppColors.textSecondaryLight,
          height: 1.33,
        ),
        // Labels
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
          color: AppColors.textPrimaryLight,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
          color: AppColors.textPrimaryLight,
        ),
        labelSmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
          color: AppColors.textSecondaryLight,
        ),
      ),

      // Button theming
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, AppSpacing.minTouchTarget),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.l,
            vertical: AppSpacing.s,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusL),
          ),
          elevation: 0,
        ),
      ),

      // Input decoration
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.backgroundLight,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.m,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusM),
          borderSide: const BorderSide(color: AppColors.dividerLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusM),
          borderSide: const BorderSide(color: AppColors.dividerLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusM),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),

      // Card styling
      cardTheme: CardThemeData(
        color: AppColors.surfaceLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusL),
          side: const BorderSide(color: AppColors.dividerLight, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.dividerLight,
        thickness: 1,
        space: AppSpacing.m,
      ),
    );
  }

  static ThemeData dark() {
    const colorScheme = ColorScheme.dark(
      primary: AppColors.primary,
      secondary: AppColors.accent,
      surface: AppColors.surfaceDark,
      error: AppColors.danger,
      onSurface: AppColors.textPrimaryDark,
      onError: Colors.white,
      onPrimary: Colors.white,
      outline: AppColors.dividerDark,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      extensions: const [SafeRouteColors.dark],
      scaffoldBackgroundColor: AppColors.backgroundDark,

      // AppBar (transparent, clean)
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimaryDark,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),

      // Enhanced Typography (Material 3 compliant)
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: AppColors.textPrimaryDark,
          height: 1.25,
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: AppColors.textPrimaryDark,
          height: 1.3,
        ),
        displaySmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: AppColors.textPrimaryDark,
          height: 1.33,
        ),
        headlineLarge: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: AppColors.textPrimaryDark,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          color: AppColors.textPrimaryDark,
        ),
        headlineSmall: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          color: AppColors.textPrimaryDark,
        ),
        titleLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.15,
          color: AppColors.textPrimaryDark,
        ),
        titleMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
          color: AppColors.textPrimaryDark,
        ),
        titleSmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
          color: AppColors.textPrimaryDark,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          color: AppColors.textPrimaryDark,
          height: 1.5,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          color: AppColors.textSecondaryDark,
          height: 1.43,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          color: AppColors.textSecondaryDark,
          height: 1.33,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
          color: AppColors.textPrimaryDark,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
          color: AppColors.textPrimaryDark,
        ),
        labelSmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
          color: AppColors.textSecondaryDark,
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, AppSpacing.minTouchTarget),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.l,
            vertical: AppSpacing.s,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusL),
          ),
          elevation: 0,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceDark,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.m,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusM),
          borderSide: const BorderSide(color: AppColors.dividerDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusM),
          borderSide: const BorderSide(color: AppColors.dividerDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusM),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),

      cardTheme: CardThemeData(
        color: AppColors.surfaceDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusL),
          side: const BorderSide(color: AppColors.dividerDark, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.dividerDark,
        thickness: 1,
        space: AppSpacing.m,
      ),
    );
  }
}
