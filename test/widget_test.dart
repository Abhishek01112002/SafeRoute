// test/widget_test.dart
// Updated from stale Flutter counter template — SafeRoute uses SafeRouteApp not MyApp
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saferoute/main.dart';
import 'package:saferoute/providers/tourist_provider.dart';
import 'package:saferoute/providers/location_provider.dart';
import 'package:saferoute/providers/room_provider.dart';
import 'package:saferoute/providers/theme_provider.dart';

void main() {
  testWidgets('SafeRoute app renders without crashing',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
              create: (_) => ThemeProvider(prefs, isLocked: true)),
          ChangeNotifierProvider(create: (_) => TouristProvider()),
          ChangeNotifierProvider(create: (_) => LocationProvider()),
          ChangeNotifierProvider(create: (_) => RoomProvider()),
        ],
        child: const SafeRouteApp(showMain: false),
      ),
    );

    await tester.pump();
    // App should render the onboarding screen without throwing
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
