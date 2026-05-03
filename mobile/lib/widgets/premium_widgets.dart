import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'dart:async';
import 'dart:math' as math;
import 'package:saferoute/utils/app_theme.dart';

/// 🎯 Elite Button with Haptics and Micro-animations
class EliteButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final bool isPrimary;
  final bool isFullWidth;
  final IconData? icon;
  final Color? color;
  final double? width;
  final double? height;

  const EliteButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.isPrimary = true,
    this.isFullWidth = true,
    this.icon,
    this.color,
    this.width,
    this.height,
  });

  @override
  State<EliteButton> createState() => _EliteButtonState();
}

class _EliteButtonState extends State<EliteButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: AppMotion.standard);
    _scale = Tween<double>(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(parent: _ctrl, curve: AppMotion.curve),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) => _ctrl.forward();
  void _handleTapUp(TapUpDetails details) => _ctrl.reverse();
  void _handleTapCancel() => _ctrl.reverse();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPrimary = widget.isPrimary;

    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: () async {
        if (widget.onPressed != null) {
          try {
            await HapticFeedback.lightImpact();
          } catch (_) {}
          widget.onPressed!();
        }
      },
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: widget.width ?? (widget.isFullWidth ? double.infinity : null),
          height: widget.height ?? 48,
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.s,
            horizontal: AppSpacing.l,
          ),
          decoration: BoxDecoration(
            color: widget.onPressed == null
                ? theme.disabledColor.withValues(alpha: 0.12)
                : (widget.color ??
                    (isPrimary
                        ? theme.colorScheme.primary
                        : Colors.transparent)),
            borderRadius: BorderRadius.circular(AppSpacing.radiusM),
            border: !isPrimary && widget.onPressed != null
                ? Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.5))
                : null,
            boxShadow: isPrimary && widget.onPressed != null
                ? AppElevation.level1
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(
                  widget.icon,
                  size: 18,
                  color: isPrimary
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.s),
              ],
              DefaultTextStyle(
                style: TextStyle(
                  color: isPrimary
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
                child: widget.child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ✨ Glimmer Loader (Gradient Shimmer)
class GlimmerLoader extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const GlimmerLoader({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = AppSpacing.radiusS,
  });

  @override
  State<GlimmerLoader> createState() => _GlimmerLoaderState();
}

class _GlimmerLoaderState extends State<GlimmerLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _align;
  bool _shouldShow = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat();
    _align = Tween<double>(begin: -2.5, end: 2.5).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine),
    );

    _timer = Timer(const Duration(milliseconds: 100), () {
      if (mounted) setState(() => _shouldShow = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldShow) {
      return SizedBox(width: widget.width, height: widget.height);
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark
        ? const Color(0xFF334155).withValues(alpha: 0.5)
        : const Color(0xFFE2E8F0);
    final highlightColor = isDark
        ? const Color(0xFF475569).withValues(alpha: 0.5)
        : const Color(0xFFF1F5F9);

    return AnimatedBuilder(
      animation: _align,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(_align.value, 0),
              end: const Alignment(1, 0),
              colors: [baseColor, highlightColor, baseColor],
            ),
          ),
        );
      },
    );
  }
}

/// 🛡️ Elite Surface (Overlay & Card Container)
class EliteSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final bool hasGlassEffect;
  final Color? color;
  final Color? borderColor;
  final double? borderOpacity;
  final double? blur;
  final double? borderRadius;
  final VoidCallback? onTap;

  const EliteSurface({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.hasGlassEffect = true,
    this.color,
    this.borderColor,
    this.borderOpacity,
    this.blur,
    this.borderRadius,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final r = borderRadius ?? AppSpacing.radiusXL;

    Widget content = Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(r),
        boxShadow:
            hasGlassEffect ? [] : AppStyle.aura(theme.colorScheme.primary),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(r),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur ?? 25, sigmaY: blur ?? 25),
          child: Container(
            padding: padding ?? const EdgeInsets.all(AppSpacing.m),
            decoration: BoxDecoration(
              color: color ??
                  (isDark
                      ? AppColors.surfaceDark.withValues(alpha: 0.7)
                      : AppColors.surfaceLight.withValues(alpha: 0.85)),
              borderRadius: BorderRadius.circular(r),
              border: Border.all(
                color: borderColor ??
                    (isDark
                        ? Colors.white.withValues(alpha: borderOpacity ?? 0.1)
                        : Colors.black.withValues(alpha: borderOpacity ?? 0.15)),
                width: 1.5,
              ),
            ),
            child: DefaultTextStyle(
              style: theme.textTheme.bodyMedium!.copyWith(
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimaryLight,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap!();
        },
        child: content,
      );
    }
    return content;
  }
}

/// 🌅 Aurora Dynamic Background
/// High-performance organic animated gradient
class AuroraBackground extends StatefulWidget {
  const AuroraBackground({super.key});

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      ),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          return Stack(
            children: [
              // 🧪 Layer 1: Primary Drift
              Positioned(
                top: -150 + (50 * _ctrl.value),
                left: -100 + (30 * (1 - _ctrl.value)),
                child: _AuraLayer(
                  color: AppColors.primary.withValues(alpha: isDark ? 0.15 : 0.05),
                  size: 500,
                ),
              ),
              // 🧪 Layer 2: Secondary Drift
              Positioned(
                bottom: -100 + (40 * _ctrl.value),
                right: -80 + (60 * _ctrl.value),
                child: _AuraLayer(
                  color: AppColors.accent.withValues(alpha: isDark ? 0.12 : 0.04),
                  size: 450,
                ),
              ),
              // 🧪 Layer 3: Dynamic Glow
              Center(
                child: _AuraLayer(
                  color: AppColors.primaryHighContrast
                      .withValues(alpha: isDark ? 0.04 : 0.015),
                  size: 800,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AuraLayer extends StatelessWidget {
  final Color color;
  final double size;

  const _AuraLayer({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
          stops: const [0.3, 1.0],
        ),
      ),
    );
  }
}

/// 📍 Pulse Marker for Maps and HUD
class PulseMarker extends StatefulWidget {
  final Color color;
  final double size;
  final double? speed;
  final double? heading; // Added heading support for pointing direction

  const PulseMarker({
    super.key,
    required this.color,
    this.size = 20,
    this.speed,
    this.heading,
  });

  @override
  State<PulseMarker> createState() => _PulseMarkerState();
}

class _PulseMarkerState extends State<PulseMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat();
    _pulse = Tween<double>(begin: 1.0, end: 3.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutQuart),
    );
    _opacity = Tween<double>(begin: 0.6, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutQuart),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // 1. Directional Indicator (Pointing Arrow)
          if (widget.heading != null)
            Transform.rotate(
              angle: (widget.heading! * math.pi / 180),
              child: CustomPaint(
                size: Size(widget.size * 3, widget.size * 3),
                painter: _HeadingPainter(widget.color),
              ),
            ),

          // 2. Radar Pulse
          AnimatedBuilder(
            animation: _ctrl,
            builder: (context, child) {
              return Container(
                width: widget.size * _pulse.value,
                height: widget.size * _pulse.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: widget.color.withValues(alpha: _opacity.value),
                      width: 2),
                ),
              );
            },
          ),
          // 3. Core Marker (The "Blue Dot")
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                    color: widget.color.withValues(alpha: 0.5),
                    blurRadius: 10,
                    spreadRadius: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeadingPainter extends CustomPainter {
  final Color color;
  _HeadingPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.8), color.withValues(alpha: 0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path()
      ..moveTo(size.width / 2, 0) // Tip
      ..lineTo(size.width * 0.7, size.height * 0.4)
      ..quadraticBezierTo(size.width / 2, size.height * 0.3, size.width * 0.3,
          size.height * 0.4)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// ⚡ Elite Speedometer HUD
class EliteSpeedometer extends StatelessWidget {
  final double speed;
  final bool isDark;

  const EliteSpeedometer({
    super.key,
    required this.speed,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    // Convert m/s to km/h
    final floatSpeed = speed * 3.6;
    final displaySpeed = floatSpeed.toStringAsFixed(0);

    return Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(
        color: isDark ? Colors.black87 : Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.5), width: 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(35),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                displaySpeed,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : AppColors.primary,
                  fontFamily: 'monospace',
                ),
              ),
              const Text(
                'KM/H',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  color: Colors.grey,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 📦 Offline Pack Asset Card
class OfflinePackCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String regionKey;
  final double progress;
  final bool isDownloading;
  final VoidCallback onDownload;

  const OfflinePackCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.regionKey,
    required this.progress,
    required this.isDownloading,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isComplete = progress >= 1.0;

    return EliteSurface(
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.s),
                decoration: BoxDecoration(
                  color: (isComplete ? AppColors.success : AppColors.primary)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusS),
                ),
                child: Icon(
                  isComplete ? Icons.offline_pin : Icons.map_outlined,
                  color: isComplete ? AppColors.success : AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          letterSpacing: 0.5),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark ? Colors.white54 : Colors.black54,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isComplete && !isDownloading)
                IconButton(
                  onPressed: onDownload,
                  icon: const Icon(Icons.download_for_offline,
                      color: AppColors.primary),
                )
              else if (isComplete)
                const Icon(Icons.check_circle,
                    color: AppColors.success, size: 20)
            ],
          ),
          if (isDownloading) ...[
            const SizedBox(height: AppSpacing.m),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: isDark ? Colors.white10 : Colors.black12,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppColors.primary),
                      minHeight: 2,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.m),
                Text(
                  "${(progress * 100).toInt()}%",
                  style:
                      const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
