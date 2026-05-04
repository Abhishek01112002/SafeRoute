// lib/screens/permission_setup_screen.dart
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:saferoute/utils/app_theme.dart';
import 'package:saferoute/widgets/premium_widgets.dart';
import 'package:saferoute/utils/permission_helper.dart';
import 'package:saferoute/screens/main_screen.dart';
import 'package:provider/provider.dart';
import 'package:saferoute/tourist/providers/tourist_provider.dart';
import 'package:saferoute/services/analytics_service.dart';
import 'package:saferoute/core/service_locator.dart';

class PermissionSetupScreen extends StatefulWidget {
  const PermissionSetupScreen({super.key});

  @override
  State<PermissionSetupScreen> createState() => _PermissionSetupScreenState();
}

class _PermissionSetupScreenState extends State<PermissionSetupScreen> {
  bool _isRequesting = false;

  Future<void> _handlePermissions() async {
    setState(() => _isRequesting = true);
    final granted = await PermissionHelper.requestAllPermissions(context);
    if (!mounted) return;
    setState(() => _isRequesting = false);

    locator<AnalyticsService>().logEvent(
      granted ? AnalyticsEvent.permissionGranted : AnalyticsEvent.permissionDenied
    );

    if (granted) {
      if (mounted) {
        final touristProv = context.read<TouristProvider>();
        final navigator = Navigator.of(context);
        await touristProv.completeOnboarding();

        unawaited(navigator.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainScreen()),
          (route) => false,
        ));
      }
    } else {
      _showLimitedModeDialog();
    }
  }

  void _showLimitedModeDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.black.withValues(alpha: 0.9),
        title: const Text("LIMITED MODE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        content: const Text(
          "Without permissions, live tracking and SOS broadcasting will be disabled. You can still view maps and sync data manually.",
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("RETRY")),
          EliteButton(
            isFullWidth: false,
            onPressed: () async {
              Navigator.pop(ctx);
              final touristProv = context.read<TouristProvider>();
              final navigator = Navigator.of(context);
              await touristProv.completeOnboarding();
              unawaited(navigator.pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const MainScreen()),
                (route) => false,
              ));
            },
            child: const Text("CONTINUE LIMITED"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: AuroraBackground()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Hero(
                    tag: 'app_logo',
                    child: Icon(Icons.security_rounded, size: 80, color: AppColors.primary),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  Text(
                    "SAFETY CLEARANCE",
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.m),
                  Text(
                    "SafeRoute requires your permission to protect you in zero-connectivity zones.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  _permissionItem(Icons.location_on_rounded, "LOCATION ACCESS", "To track your position and geofence status."),
                  const SizedBox(height: AppSpacing.m),
                  _permissionItem(Icons.bluetooth_searching_rounded, "MESH NETWORKING", "To communicate with authorities without internet."),
                  const SizedBox(height: AppSpacing.m),
                  _permissionItem(Icons.notifications_active_rounded, "CRITICAL ALERTS", "To notify you of nearby dangers."),
                  const Spacer(),
                  EliteButton(
                    onPressed: _isRequesting ? null : _handlePermissions,
                    child: Text(_isRequesting ? "REQUESTING..." : "GRANT ALL ACCESS"),
                  ),
                  const SizedBox(height: AppSpacing.m),
                  TextButton(
                    onPressed: () => _handleLimitedMode(),
                    child: Text(
                      "CONTINUE WITH LIMITED FEATURES",
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                        fontWeight: FontWeight.w900,
                        fontSize: 9,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleLimitedMode() {
    locator<AnalyticsService>().logEvent(AnalyticsEvent.permissionDenied, properties: {'mode': 'manual_skip'});
    _showLimitedModeDialog();
  }

  Widget _permissionItem(IconData icon, String title, String desc) {
    final theme = Theme.of(context);
    return EliteSurface(
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 24),
          const SizedBox(width: AppSpacing.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1)),
                Text(desc, style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
