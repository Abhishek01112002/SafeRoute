// lib/widgets/premium_components.dart
// Production-grade reusable components for SafeRoute
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:saferoute/utils/app_theme.dart';

// ════════════════════════════════════════════════════════════════════════════════
// 🎯 PREMIUM CARD (Soft shadow, clean padding, consistent radius)
// ════════════════════════════════════════════════════════════════════════════════

class PremiumCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final double? elevation;
  final Color? backgroundColor;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;

  const PremiumCard({
    super.key,
    required this.child,
    this.padding,
    this.elevation,
    this.backgroundColor,
    this.onTap,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius ?? BorderRadius.circular(AppSpacing.radiusL),
        child: Container(
          decoration: BoxDecoration(
            color: backgroundColor ?? theme.colorScheme.surface,
            borderRadius:
                borderRadius ?? BorderRadius.circular(AppSpacing.radiusL),
            boxShadow: [
              BoxShadow(
                color: theme.brightness == Brightness.dark
                    ? Colors.black.withValues(alpha: 0.2)
                    : Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          padding: padding ?? const EdgeInsets.all(AppSpacing.m),
          child: child,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// 🔘 PREMIUM BUTTON (States: default, disabled, loading + press animation)
// ════════════════════════════════════════════════════════════════════════════════

class PremiumButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final bool isLoading;
  final bool isFullWidth;
  final IconData? icon;
  final double? width;
  final double? height;
  final ButtonStyle? style;
  final Color? backgroundColor;

  const PremiumButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.isLoading = false,
    this.isFullWidth = false,
    this.icon,
    this.width,
    this.height,
    this.style,
    this.backgroundColor,
  });

  @override
  State<PremiumButton> createState() => _PremiumButtonState();
}

class _PremiumButtonState extends State<PremiumButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: AppMotion.fast,
    );
    _scale = Tween<double>(begin: 1.0, end: 0.96)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutCubic));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) => _ctrl.forward();
  void _onTapUp(TapUpDetails _) => _ctrl.reverse();
  void _onTapCancel() => _ctrl.reverse();

  @override
  Widget build(BuildContext context) {
    final isDisabled = widget.onPressed == null || widget.isLoading;

    return GestureDetector(
      onTapDown: isDisabled ? null : _onTapDown,
      onTapUp: isDisabled ? null : _onTapUp,
      onTapCancel: isDisabled ? null : _onTapCancel,
      onTap: isDisabled
          ? null
          : () {
              HapticFeedback.lightImpact().ignore();
              widget.onPressed?.call();
            },
      child: ScaleTransition(
        scale: _scale,
        child: SizedBox(
          width: widget.width ?? (widget.isFullWidth ? double.infinity : null),
          height: widget.height ?? AppSpacing.minTouchTarget,
          child: ElevatedButton(
            onPressed: widget.onPressed,
            style: (widget.style ??
                    ElevatedButton.styleFrom(
                      backgroundColor:
                          widget.backgroundColor ?? Colors.transparent,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.radiusL),
                      ),
                    ))
                .copyWith(
              foregroundColor: WidgetStateProperty.resolveWith<Color?>(
                (Set<WidgetState> states) {
                  if (widget.isLoading) return Colors.white.withValues(alpha: 0.6);
                  if (states.contains(WidgetState.disabled)) {
                    return Colors.white.withValues(alpha: 0.5);
                  }
                  return null;
                },
              ),
            ),
            child: widget.isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(widget.icon),
                        const SizedBox(width: AppSpacing.s),
                      ],
                      Flexible(child: widget.child),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// 📊 INFO SURFACE (Semi-transparent surface with subtle gradient)
// ════════════════════════════════════════════════════════════════════════════════

class InfoSurface extends StatelessWidget {
  final Widget child;
  final Color? backgroundColor;
  final EdgeInsets padding;
  final BorderRadius? borderRadius;

  const InfoSurface({
    super.key,
    required this.child,
    this.backgroundColor,
    this.padding = const EdgeInsets.all(AppSpacing.m),
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor ??
            (isDark
                ? AppColors.surfaceDark.withValues(alpha: 0.6)
                : AppColors.backgroundLight.withValues(alpha: 0.8)),
        borderRadius: borderRadius ?? BorderRadius.circular(AppSpacing.radiusM),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      padding: padding,
      child: child,
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// 🏷️ STATUS BADGE (High contrast labels for system states)
// ════════════════════════════════════════════════════════════════════════════════

enum BadgeStatus { success, warning, danger, info, neutral }

class StatusBadge extends StatelessWidget {
  final String label;
  final BadgeStatus status;
  final IconData? icon;

  const StatusBadge({
    super.key,
    required this.label,
    required this.status,
    this.icon,
  });

  Color _getColor() {
    switch (status) {
      case BadgeStatus.success:
        return AppColors.success;
      case BadgeStatus.warning:
        return AppColors.warning;
      case BadgeStatus.danger:
        return AppColors.danger;
      case BadgeStatus.info:
        return AppColors.info;
      case BadgeStatus.neutral:
        return AppColors.textSecondaryLight;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor();

    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.radiusS),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.m,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// ⏳ LOADING STATE (Skeleton placeholder)
// ════════════════════════════════════════════════════════════════════════════════

class LoadingState extends StatelessWidget {
  final double height;
  final double? width;
  final BorderRadius? borderRadius;

  const LoadingState({
    super.key,
    this.height = 20,
    this.width,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: theme.colorScheme.outline.withValues(alpha: 0.1),
        borderRadius: borderRadius ?? BorderRadius.circular(AppSpacing.radiusS),
      ),
      child: ShaderMask(
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.transparent,
            Colors.white.withValues(alpha: 0.2),
            Colors.transparent,
          ],
        ).createShader(bounds),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.outline.withValues(alpha: 0.05),
            borderRadius:
                borderRadius ?? BorderRadius.circular(AppSpacing.radiusS),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// 📭 EMPTY STATE (Meaningful message)
// ════════════════════════════════════════════════════════════════════════════════

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final VoidCallback? onAction;
  final String? actionLabel;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.onAction,
    this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: AppSpacing.l),
            Text(
              title,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.s),
              Text(
                message!,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: AppSpacing.l),
              PremiumButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// ⚠️ ERROR STATE (Clear + actionable)
// ════════════════════════════════════════════════════════════════════════════════

class ErrorState extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onRetry;
  final String? retryLabel;

  const ErrorState({
    super.key,
    required this.title,
    required this.message,
    required this.onRetry,
    this.retryLabel = 'Retry',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: AppColors.danger.withValues(alpha: 0.7),
            ),
            const SizedBox(height: AppSpacing.l),
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                color: AppColors.danger,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s),
            Text(
              message,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.l),
            PremiumButton(
              onPressed: onRetry,
              backgroundColor: AppColors.danger,
              child: Text(retryLabel!),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// 🔘 FLOATING ACTION BUTTON (Simple, consistent with design system)
// ════════════════════════════════════════════════════════════════════════════════

class PremiumFAB extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color? backgroundColor;
  final bool heroTag;
  final String? tooltipMessage;

  const PremiumFAB({
    super.key,
    required this.icon,
    required this.onPressed,
    this.backgroundColor,
    this.heroTag = true,
    this.tooltipMessage,
  });

  @override
  State<PremiumFAB> createState() => _PremiumFABState();
}

class _PremiumFABState extends State<PremiumFAB>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: AppMotion.fast,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 1, end: 0.95)
          .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut)),
      child: FloatingActionButton(
        onPressed: () {
          _ctrl.forward().then((_) => _ctrl.reverse());
          HapticFeedback.mediumImpact().ignore();
          widget.onPressed();
        },
        backgroundColor: widget.backgroundColor,
        tooltip: widget.tooltipMessage,
        elevation: 4,
        child: Icon(widget.icon),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// 📍 PULSE MARKER (Subtle animation for map/location markers)
// ════════════════════════════════════════════════════════════════════════════════

class PulseMarker extends StatefulWidget {
  final Color color;
  final double size;
  final Duration duration;

  const PulseMarker({
    super.key,
    required this.color,
    this.size = 16,
    this.duration = const Duration(milliseconds: 1500),
  });

  @override
  State<PulseMarker> createState() => _PulseMarkerState();
}

class _PulseMarkerState extends State<PulseMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        ScaleTransition(
          scale: Tween<double>(begin: 1, end: 2)
              .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut)),
          child: Opacity(
            opacity: Tween<double>(begin: 0.8, end: 0).evaluate(
                CurvedAnimation(parent: _ctrl, curve: Curves.easeOut)),
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color,
              ),
            ),
          ),
        ),
        Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// 📏 SECTION DIVIDER (Clean visual separation)
// ════════════════════════════════════════════════════════════════════════════════

class SectionDivider extends StatelessWidget {
  final String? label;
  final double height;

  const SectionDivider({
    super.key,
    this.label,
    this.height = AppSpacing.m,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (label == null) {
      return SizedBox(height: height);
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: height / 2),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: theme.colorScheme.outline.withValues(alpha: 0.3),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
            child: Text(
              label!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: theme.colorScheme.outline.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }
}
