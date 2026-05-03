// lib/core/widgets/async_state_widget.dart
//
// SafeRoute Async State Widget
// -----------------------------
// A reusable widget that handles the 3 standard async states:
//   1. Loading  → Shows shimmer skeleton (or custom loader)
//   2. Error    → Shows consistent error card with optional retry
//   3. Data     → Shows the actual content
//
// Usage:
//   AsyncStateWidget<Tourist>(
//     isLoading: provider.isLoading,
//     error: provider.appError,      // AppError? — new typed error
//     data: provider.tourist,
//     onData: (tourist) => TouristCard(tourist: tourist),
//     onRetry: provider.reload,
//   )
//
// This does NOT replace or modify any existing widget. It is additive.

import 'package:flutter/material.dart';
import 'package:saferoute/core/errors/app_error.dart';
import 'package:saferoute/utils/app_theme.dart';

// ---------------------------------------------------------------------------
// AsyncStateWidget
// ---------------------------------------------------------------------------

class AsyncStateWidget<T> extends StatelessWidget {
  final T? data;
  final bool isLoading;
  final AppError? error;
  final Widget Function(T data) onData;
  final Widget Function()? onLoading;
  final Widget Function(AppError error, VoidCallback? onRetry)? onError;
  final VoidCallback? onRetry;

  // Skeleton config (used by default loader)
  final int skeletonLineCount;
  final double skeletonLineHeight;

  const AsyncStateWidget({
    super.key,
    required this.isLoading,
    required this.onData,
    this.data,
    this.error,
    this.onLoading,
    this.onError,
    this.onRetry,
    this.skeletonLineCount = 3,
    this.skeletonLineHeight = 16,
  });

  @override
  Widget build(BuildContext context) {
    // Priority: Loading > Error > Data > Empty
    if (isLoading) {
      return onLoading?.call() ??
          SafeRouteSkeleton(
            lineCount: skeletonLineCount,
            lineHeight: skeletonLineHeight,
          );
    }

    if (error != null) {
      return onError?.call(error!, onRetry) ??
          SafeRouteErrorCard(error: error!, onRetry: onRetry);
    }

    if (data != null) {
      return onData(data as T);
    }

    // Empty state
    return const _EmptyState();
  }
}

// ---------------------------------------------------------------------------
// SafeRouteSkeleton — Shimmer loading placeholder
// ---------------------------------------------------------------------------

class SafeRouteSkeleton extends StatefulWidget {
  final int lineCount;
  final double lineHeight;
  final bool showAvatar;

  const SafeRouteSkeleton({
    super.key,
    this.lineCount = 3,
    this.lineHeight = 16,
    this.showAvatar = false,
  });

  @override
  State<SafeRouteSkeleton> createState() => _SafeRouteSkeletonState();
}

class _SafeRouteSkeletonState extends State<SafeRouteSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _shimmer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _shimmer = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    final highlight = isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9);

    return AnimatedBuilder(
      animation: _shimmer,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.showAvatar) ...[
                Row(children: [
                  _SkeletonBox(
                    width: 48,
                    height: 48,
                    borderRadius: 24,
                    base: base,
                    highlight: highlight,
                    shimmerX: _shimmer.value,
                  ),
                  const SizedBox(width: AppSpacing.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SkeletonBox(
                          width: double.infinity,
                          height: widget.lineHeight,
                          base: base,
                          highlight: highlight,
                          shimmerX: _shimmer.value,
                        ),
                        const SizedBox(height: AppSpacing.s),
                        _SkeletonBox(
                          width: 120,
                          height: widget.lineHeight * 0.75,
                          base: base,
                          highlight: highlight,
                          shimmerX: _shimmer.value,
                        ),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: AppSpacing.m),
              ],
              ...List.generate(widget.lineCount, (i) {
                // Last line is shorter to look more natural
                final width = i == widget.lineCount - 1 ? 180.0 : double.infinity;
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: i < widget.lineCount - 1 ? AppSpacing.s : 0,
                  ),
                  child: _SkeletonBox(
                    width: width,
                    height: widget.lineHeight,
                    base: base,
                    highlight: highlight,
                    shimmerX: _shimmer.value,
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;
  final Color base;
  final Color highlight;
  final double shimmerX;

  const _SkeletonBox({
    required this.width,
    required this.height,
    required this.base,
    required this.highlight,
    required this.shimmerX,
    this.borderRadius = 6,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          begin: Alignment(shimmerX, 0),
          end: const Alignment(1, 0),
          colors: [base, highlight, base],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SafeRouteErrorCard — Consistent error display
// ---------------------------------------------------------------------------

class SafeRouteErrorCard extends StatelessWidget {
  final AppError error;
  final VoidCallback? onRetry;
  final bool compact;

  const SafeRouteErrorCard({
    super.key,
    required this.error,
    this.onRetry,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (compact) {
      return Row(
        children: [
          Icon(Icons.error_outline_rounded,
              color: AppColors.danger, size: 16),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Text(
              error.userMessage,
              style: TextStyle(color: AppColors.danger, fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: const Text('Retry', style: TextStyle(fontSize: 12)),
            ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radiusL),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _iconForError(error),
            color: AppColors.danger,
            size: 36,
          ),
          const SizedBox(height: AppSpacing.s),
          Text(
            error.userMessage,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: AppSpacing.m),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Try Again'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusM),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _iconForError(AppError error) {
    return switch (error) {
      NetworkError() => Icons.wifi_off_rounded,
      OfflineError() => Icons.signal_wifi_off_rounded,
      AuthError() => Icons.lock_outline_rounded,
      RateLimitError() => Icons.timer_off_rounded,
      ValidationError() => Icons.warning_amber_rounded,
      ServerError() => Icons.cloud_off_rounded,
      NotFoundError() => Icons.search_off_rounded,
      UnknownError() => Icons.error_outline_rounded,
    };
  }
}

// ---------------------------------------------------------------------------
// Empty State
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_rounded,
              size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: AppSpacing.s),
          Text(
            'Nothing here yet.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.outline,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
