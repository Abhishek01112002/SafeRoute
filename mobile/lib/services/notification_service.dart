import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
        const InitializationSettings(android: android, iOS: darwin));
    _initialized = true;
  }

  static Future<void> showNotification(String title, String body) async {
    await _plugin.show(
      DateTime.now().millisecond,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'saferoute_general',
          'General Alerts',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      ),
      payload: 'saferoute://alerts',
    );
  }

  static Future<void> showDistanceAlert(
      String memberName, double distKm) async {
    await _plugin.show(
      memberName.hashCode,
      '⚠️ Group Member Far Away',
      '$memberName is ${distKm.toStringAsFixed(1)} km from you',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'saferoute_group',
          'Group Alerts',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      ),
      payload: 'saferoute://group',
    );
  }
}
