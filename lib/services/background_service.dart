// lib/services/background_service.dart
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:saferoute/models/location_ping_model.dart';
import 'package:saferoute/services/api_service.dart';
import 'package:saferoute/services/database_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  int failedGpsCount = 0;

  // Main background loop
  Timer.periodic(const Duration(seconds: 30), (timer) async {
    if (service is AndroidServiceInstance) {
      if (!(await service.isForegroundService())) {
        return;
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final touristId = prefs.getString('tourist_id');
      if (touristId == null) return;

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 15),
        );
        failedGpsCount = 0; // Reset on success
      } catch (e) {
        failedGpsCount++;
        debugPrint("Background GPS Fail ($failedGpsCount): $e");
        
        if (failedGpsCount >= 3) {
          flutterLocalNotificationsPlugin.show(
            889,
            '🚨 GPS Signal Unavailable',
            'SafeRoute cannot acquire your location. Please move to an open area.',
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'saferoute_alerts',
                'SafeRoute Critical Alerts',
                importance: Importance.high,
                priority: Priority.high,
              ),
            ),
          );
        }
        return; // Skip this ping cycle
      }

      // 2. Create LocationPing object
      final ping = LocationPing(
        touristId: touristId,
        latitude: position.latitude,
        longitude: position.longitude,
        speedKmh: position.speed * 3.6,
        accuracyMeters: position.accuracy,
        timestamp: DateTime.now(),
        zoneStatus: ZoneType.none,
      );

      final apiService = ApiService();
      final dbService = DatabaseService();

      // 3. Try to POST to API
      bool success = await apiService.sendLocationPing(ping);

      if (!success) {
        await dbService.savePing(ping);
      } else {
        final unsynced = await dbService.getUnsyncedPings();
        for (var p in unsynced) {
          bool synced = await apiService.sendLocationPing(p);
          if (synced && p.id != null) {
            await dbService.markPingSynced(p.id!);
          }
        }
      }

      // FIX: capture now() once — two separate calls could straddle a minute boundary
      final now = DateTime.now();
      flutterLocalNotificationsPlugin.show(
        888,
        'SafeRoute Active',
        'Last sync: ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'saferoute_foreground',
            'SafeRoute Background Service',
            ongoing: true,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
    } catch (e) {
      debugPrint("Background task error: $e");
    }
  });
}

class BackgroundService {
  static const String notificationChannelId = 'saferoute_foreground';
  static const int notificationId = 888;

  static Future<void> initializeBackgroundService() async {
    final service = FlutterBackgroundService();

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      notificationChannelId,
      'SafeRoute Background Service',
      description: 'Protects you by tracking location in background',
      importance: Importance.low,
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: notificationChannelId,
        initialNotificationTitle: 'SafeRoute is protecting you',
        initialNotificationContent: 'GPS tracking active',
        foregroundServiceNotificationId: notificationId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  static Future<void> stopBackgroundService() async {
    final service = FlutterBackgroundService();
    service.invoke('stopService');
  }

  static Future<bool> isRunning() async {
    return await FlutterBackgroundService().isRunning();
  }
}
