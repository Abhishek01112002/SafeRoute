// lib/core/widgets/error_boundary.dart
//
// SafeRoute Error Boundary
// -------------------------
// Catches Flutter widget render errors and shows a safe fallback UI
// instead of the red screen of death.
//
// Usage:
//   ErrorBoundary(
//     child: NavigationScreen(),
//     fallback: (error) => ErrorCard(message: 'Could not load map'),
//   )
//
// Wrap major screens in main_screen.dart for app-wide protection.

import 'package:flutter/material.dart';
import 'package:saferoute/utils/app_theme.dart';

class ErrorBoundary extends StatefulWidget {
  final Widget child;

  /// Optional: custom fallback widget. If null, shows the default safe card.
  final Widget Function(Object error, StackTrace? stack)? fallback;

  /// Optional: called when an error is caught (use for Crashlytics logging).
  final void Function(Object error, StackTrace? stack)? onError;

  const ErrorBoundary({
    super.key,
    required this.child,
    this.fallback,
    this.onError,
  });

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  Object? _error;
  StackTrace? _stack;

  @override
  void initState() {
    super.initState();
    _error = null;
  }

  void _handleError(Object error, StackTrace stack) {
    widget.onError?.call(error, stack);
    setState(() {
      _error = error;
      _stack = stack;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return widget.fallback?.call(_error!, _stack) ??
          _DefaultErrorFallback(
            error: _error!,
            onRetry: () => setState(() {
              _error = null;
              _stack = null;
            }),
          );
    }

    return _ErrorCatcher(
      onError: _handleError,
      child: widget.child,
    );
  }
}

// ---------------------------------------------------------------------------
// Internal widget that installs a FlutterError handler for its subtree
// ---------------------------------------------------------------------------

class _ErrorCatcher extends StatefulWidget {
  final Widget child;
  final void Function(Object error, StackTrace stack) onError;

  const _ErrorCatcher({required this.child, required this.onError});

  @override
  State<_ErrorCatcher> createState() => _ErrorCatcherState();
}

class _ErrorCatcherState extends State<_ErrorCatcher> {
  late final void Function(FlutterErrorDetails)? _previousHandler;

  @override
  void initState() {
    super.initState();
    // Save the previous handler so we don't break parent boundaries
    _previousHandler = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      widget.onError(details.exception, details.stack ?? StackTrace.empty);
      // Also call Flutter's default handler so errors still show in console
      _previousHandler?.call(details);
    };
  }

  @override
  void dispose() {
    FlutterError.onError = _previousHandler;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ---------------------------------------------------------------------------
// Default fallback UI — shown instead of the red error screen
// ---------------------------------------------------------------------------

class _DefaultErrorFallback extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _DefaultErrorFallback({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.l),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.danger,
                  size: 36,
                ),
              ),
              const SizedBox(height: AppSpacing.m),

              // Title
              Text(
                'Something went wrong',
                style: TextStyle(
                  color: AppColors.textPrimaryDark,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.s),

              // Subtitle
              Text(
                'The app ran into an unexpected issue.\nYour data is safe.',
                style: TextStyle(
                  color: AppColors.textSecondaryDark,
                  fontSize: 14,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.l),

              // Retry button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try Again'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusL),
                    ),
                  ),
                ),
              ),

              // Debug info (only in debug builds)
              if (const bool.fromEnvironment('dart.vm.product') == false) ...[
                const SizedBox(height: AppSpacing.m),
                GestureDetector(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Error Details'),
                        content: SingleChildScrollView(
                          child: Text(
                            error.toString(),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    );
                  },
                  child: Text(
                    'Tap to view technical details',
                    style: TextStyle(
                      color: AppColors.textSecondaryDark,
                      fontSize: 11,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
