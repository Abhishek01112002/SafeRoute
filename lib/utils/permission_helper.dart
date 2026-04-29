// lib/utils/permission_helper.dart
import 'package:permission_handler/permission_handler.dart';

class PermissionHelper {
  static Future<bool> requestAllPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.locationAlways,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.notification,
      Permission.camera,
    ].request();

    // Critical permissions for SafeRoute
    bool locationGranted = statuses[Permission.location]?.isGranted ?? false;
    bool bluetoothGranted = (statuses[Permission.bluetoothScan]?.isGranted ?? false) &&
                          (statuses[Permission.bluetoothConnect]?.isGranted ?? false);
    
    return locationGranted && bluetoothGranted;
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
