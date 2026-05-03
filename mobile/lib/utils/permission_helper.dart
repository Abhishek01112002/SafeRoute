import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:saferoute/services/permission_service.dart';

class PermissionHelper {
  static Future<bool> requestAllPermissions(BuildContext context) async {
    // Request critical permissions individually via PermissionService for robust handling

    // 1. Location (Foreground + Background)
    final locationGranted = await PermissionService.requestBackgroundLocation(context);

    // 2. Bluetooth (Scan + Connect)
    final bluetoothStatus = await PermissionService.requestPermission(
      permission: Permission.bluetoothScan,
      context: context,
      rationaleTitle: 'Mesh Networking',
      rationaleMessage: 'SafeRoute uses Bluetooth to communicate with other users and authorities in zero-signal areas.',
    );

    if (bluetoothStatus.isGranted) {
      await PermissionService.requestPermission(
        permission: Permission.bluetoothConnect,
        context: context,
      );
      await PermissionService.requestPermission(
        permission: Permission.bluetoothAdvertise,
        context: context,
      );
    }

    // 3. Notifications
    await PermissionService.requestPermission(
      permission: Permission.notification,
      context: context,
      rationaleTitle: 'Safety Alerts',
      rationaleMessage: 'SafeRoute needs to send you critical alerts about nearby dangers.',
    );

    // 4. Camera (Optional but good to have ready)
    await PermissionService.requestPermission(
      permission: Permission.camera,
      context: context,
    );

    return locationGranted;
  }

  static bool isPermissionCritical(Permission p) {
    return p == Permission.location ||
        p == Permission.locationAlways ||
        p == Permission.bluetoothScan ||
        p == Permission.bluetoothConnect;
  }

  static Future<void> openSettings() async {
    await openAppSettings();
  }
}
