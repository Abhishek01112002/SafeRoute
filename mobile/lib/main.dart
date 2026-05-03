// lib/main.dart
import 'dart:async';
import 'dart:ui' as ui;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saferoute/providers/tourist_provider.dart';
import 'package:saferoute/providers/location_provider.dart';
import 'package:saferoute/providers/room_provider.dart';
import 'package:saferoute/providers/auth_provider.dart';
import 'package:saferoute/providers/navigation_provider.dart';
import 'package:saferoute/providers/safety_system_provider.dart';
import 'package:saferoute/mesh/providers/mesh_provider.dart';
import 'package:saferoute/screens/onboarding_screen.dart';
import 'package:saferoute/screens/main_screen.dart';
import 'package:saferoute/services/background_service.dart';
import 'package:saferoute/services/notification_service.dart';
import 'package:saferoute/services/database_tile_provider.dart';
import 'package:saferoute/services/database_service.dart';
import 'package:saferoute/services/telemetry_service.dart';

import 'package:saferoute/providers/theme_provider.dart';
import 'package:saferoute/utils/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase (Safely)
  try {
    await Firebase.initializeApp();
    _configureTelemetry();
  } catch (e) {
    debugPrint("⚠️ Firebase initialization failed: $e");
    debugPrint("💡 Tip: Ensure google-services.json is present in android/app/");
  }

  // Initialize notifications
  await NotificationService.init();

  // Pre-flight check for Theme Management (FAANG Persistence)
  // Increase timeout to 500ms to allow registry on slower devices (Issue #10)
  SharedPreferences? prefs;
  bool themeLoadTimedOut = false;

  try {
    prefs = await SharedPreferences.getInstance()
        .timeout(const Duration(milliseconds: 500));
  } catch (_) {
    // Timeout occurred — lock to system theme for this session
    // to prevent a mid-session "snap" when prefs eventually loads
    themeLoadTimedOut = true;
    prefs = await SharedPreferences.getInstance();
  }


  // Pre-populate offline map tiles (Issue #3 fix)
  Future.delayed(const Duration(seconds: 2), () async {
    try {
      await DatabaseTileProvider.prePopulateOfflineTiles();
    } catch (e) {
      debugPrint('Failed to pre-populate offline tiles: $e');
    }
  });

  // Cleanup old breadcrumbs (72h retention policy)
  Future.delayed(const Duration(seconds: 5), () async {
    try {
      await DatabaseService().deleteOldSyncedPings();
    } catch (e) {
      debugPrint('Failed to prune old breadcrumbs: $e');
    }
  });

  final bool isRegistered = prefs.getBool('is_registered') ?? false;
  final bool onboardingCompleted =
      prefs.getBool('onboarding_completed') ?? false;
  final String? touristId = prefs.getString('tourist_id');

  // Initialize background service
  await BackgroundService.initializeBackgroundService();

  // Instantiate providers
  final touristProvider = TouristProvider();
  final meshProvider = MeshProvider();

  // Load tourist data
  await touristProvider.loadTourist();

  // Auto-start mesh if registered (Issue #2)
  if (isRegistered && touristId != null) {
    // Phase 7: Use cryptographic TUID prefix for Mesh Sender ID, fallback to touristId
    final meshId = touristProvider.tourist?.tuid?.substring(0, 8) ?? touristId;
    await meshProvider.init(meshId);
    await meshProvider.startMesh();
    debugPrint("✅ BLE Mesh auto-started for registered user: $meshId");
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ThemeProvider(prefs!, isLocked: themeLoadTimedOut),
        ),
        ChangeNotifierProvider(
          create: (_) => MainNavigationProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => AuthProvider()..initializeAuth(),
        ),
        ChangeNotifierProvider.value(value: touristProvider),
        ChangeNotifierProvider(create: (_) => LocationProvider()),
        ChangeNotifierProvider(create: (_) => RoomProvider()),
        ChangeNotifierProxyProvider<LocationProvider, SafetySystemProvider>(
          create: (_) => SafetySystemProvider(),
          update: (_, location, safety) {
            final pos = location.currentPosition;
            safety!.updateState(
              position:
                  pos != null ? LatLng(pos.latitude, pos.longitude) : null,
              zone: location.zoneStatus,
              batteryLevel: location.batteryLevel,
              speedKmh: (pos?.speed ?? 0) * 3.6,
              lastMovement: location.lastMovementTime,
              isSosActive: location.isSosActive,
            );
            return safety;
          },
        ),
        ChangeNotifierProvider.value(value: meshProvider),
      ],
      child: SafeRouteApp(showMain: isRegistered || onboardingCompleted),
    ),
  );
}

void _configureTelemetry() {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    if (kReleaseMode) {
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    }
    TelemetryService.logError(
      details.exception,
      details.stack,
      context: 'Flutter framework',
    );
  };

  ui.PlatformDispatcher.instance.onError = (error, stackTrace) {
    if (kReleaseMode) {
      FirebaseCrashlytics.instance.recordError(error, stackTrace, fatal: true);
    }
    TelemetryService.logFatal(
      error,
      stackTrace,
      context: 'Uncaught platform error',
    );
    return true;
  };
}

class SafeRouteApp extends StatelessWidget {
  final bool showMain;

  const SafeRouteApp({super.key, required this.showMain});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return AnimatedTheme(
          data: themeProvider.isDarkMode ? AppTheme.dark() : AppTheme.light(),
          duration: const Duration(milliseconds: 200),
          child: MaterialApp(
            title: 'SafeRoute',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: themeProvider.themeMode,
            home: showMain ? const MainScreen() : const OnboardingScreen(),
          ),
        );
      },
    );
  }
}
