// lib/services/permission_service.dart
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Centralized service for production-ready permission management.
/// Handles Android (33+) and iOS requirements with declarative status checks.
class PermissionService {
  /// Checks the current status of a given permission.
  static Future<PermissionStatus> checkPermission(Permission permission) async {
    return await permission.status;
  }

  /// Requests a single permission, handling all possible user decisions.
  /// Centralizes rationale dialogs and settings redirects.
  static Future<PermissionStatus> requestPermission({
    required Permission permission,
    required BuildContext context,
    String? rationaleTitle,
    String? rationaleMessage,
  }) async {
    // 1. Check for permanent denial first.
    if (await permission.isPermanentlyDenied) {
      if (context.mounted) {
        await _showSettingsDialog(context, permission, rationaleTitle, rationaleMessage);
      }
      return PermissionStatus.permanentlyDenied;
    }

    // 2. For iOS, check for 'limited' access (mostly for Photos).
    if (await permission.isLimited) {
      if (context.mounted) {
        await _showLimitedAccessDialog(context, permission);
      }
      return PermissionStatus.limited;
    }

    // 3. For Android, show a rationale before requesting if required by OS.
    if (await permission.shouldShowRequestRationale) {
      if (context.mounted) {
        final shouldContinue = await _showRationaleDialog(
          context,
          permission,
          rationaleTitle ?? 'Permission Required',
          rationaleMessage ?? 'This permission is necessary for SafeRoute to function properly.',
        );
        if (!shouldContinue) return PermissionStatus.denied;
      }
    }

    // 4. Finally, request the permission.
    final status = await permission.request();

    // 5. Handle the result (Granted vs Denied)
    if (status.isPermanentlyDenied && context.mounted) {
      await _showSettingsDialog(context, permission, rationaleTitle, rationaleMessage);
    }

    return status;
  }

  /// Specialized handler for Background Location (High priority for SafeRoute)
  static Future<bool> requestBackgroundLocation(BuildContext context) async {
    // First, ensure foreground location is granted.
    final foregroundStatus = await requestPermission(
      permission: Permission.locationWhenInUse,
      context: context,
      rationaleTitle: 'Location Access',
      rationaleMessage: 'SafeRoute needs your location to track your safety trail.',
    );

    if (!foregroundStatus.isGranted) return false;

    // Then, request background location.
    final backgroundStatus = await requestPermission(
      permission: Permission.locationAlways,
      context: context,
      rationaleTitle: 'Always-On Location',
      rationaleMessage: 'To protect you even when the screen is off, SafeRoute requires "Allow all the time" location access.',
    );

    return backgroundStatus.isGranted;
  }

  static Future<void> _showSettingsDialog(
    BuildContext context,
    Permission permission,
    String? title,
    String? message,
  ) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title ?? 'Permission Required'),
        content: Text(message ?? 'This permission is required for the feature. Please enable it in the app settings.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  static Future<bool> _showRationaleDialog(
    BuildContext context,
    Permission permission,
    String title,
    String message,
  ) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not Now'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    ) ?? false;
  }

  static Future<void> _showLimitedAccessDialog(BuildContext context, Permission permission) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limited Access'),
        content: const Text('SafeRoute has limited access to your resources. For the full experience, please grant full access in settings.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
