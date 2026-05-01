// lib/main.dart
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

import 'package:saferoute/utils/permission_helper.dart';
import 'package:saferoute/providers/theme_provider.dart';
import 'package:saferoute/utils/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  // Proactively request permissions
  Future.delayed(const Duration(seconds: 1), () {
    PermissionHelper.requestAllPermissions();
  });

  final bool isRegistered = prefs.getBool('is_registered') ?? false;
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
    await meshProvider.init(touristId);
    await meshProvider.startMesh();
    debugPrint("✅ BLE Mesh auto-started for registered user: $touristId");
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
              position: pos != null ? LatLng(pos.latitude, pos.longitude) : null,
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
      child: SafeRouteApp(isRegistered: isRegistered),
    ),
  );
}

class SafeRouteApp extends StatelessWidget {
  final bool isRegistered;

  const SafeRouteApp({super.key, required this.isRegistered});

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
            home: isRegistered ? const MainScreen() : const OnboardingScreen(),
          ),
        );
      },
    );
  }
}
