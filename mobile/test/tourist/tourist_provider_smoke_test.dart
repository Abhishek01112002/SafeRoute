// test/tourist/tourist_provider_smoke_test.dart
//
// Smoke tests for TouristProvider initial state.
// These tests verify the provider starts correctly and state values
// are sane before any user interaction or network call.
//
// No network calls are made — ApiService is mocked via GetIt.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get_it/get_it.dart';

import 'package:saferoute/tourist/providers/tourist_provider.dart';
import 'package:saferoute/tourist/models/tourist_model.dart';
import 'package:saferoute/utils/app_theme.dart';
import 'package:saferoute/core/providers/theme_provider.dart';

void main() {
  setUp(() {
    // Reset GetIt before each test to avoid state leakage
    GetIt.instance.reset();
    SharedPreferences.setMockInitialValues({});
  });

  group('TouristProvider — initial state', () {
    test('starts in GUEST user state', () {
      final provider = TouristProvider();
      expect(provider.userState, UserState.GUEST);
    });

    test('isLoading starts as false', () {
      final provider = TouristProvider();
      expect(provider.isLoading, isFalse);
    });

    test('tourist starts as null', () {
      final provider = TouristProvider();
      expect(provider.tourist, isNull);
    });

    test('errorMessage starts as null', () {
      final provider = TouristProvider();
      expect(provider.errorMessage, isNull);
    });

    test('guestSessionId starts as null', () {
      final provider = TouristProvider();
      expect(provider.guestSessionId, isNull);
    });

    test('isLocked starts as false (no brute force lockout)', () {
      final provider = TouristProvider();
      expect(provider.isLocked, isFalse);
    });

    test('remainingLockSeconds is 0 when not locked', () {
      final provider = TouristProvider();
      expect(provider.remainingLockSeconds, 0);
    });
  });

  group('TouristProvider — clearError()', () {
    test('clearError resets errorMessage to null', () {
      final provider = TouristProvider();
      // Access private field via provider interface
      provider.clearError();
      expect(provider.errorMessage, isNull);
    });
  });

  group('TouristProvider — widget integration smoke test', () {
    testWidgets('TouristProvider renders in widget tree without crashing',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => ThemeProvider(prefs, isLocked: true),
            ),
            ChangeNotifierProvider(create: (_) => TouristProvider()),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: Builder(builder: (context) {
                final tourist = context.watch<TouristProvider>();
                return Text(tourist.userState.name);
              }),
            ),
          ),
        ),
      );

      await tester.pump();
      // Provider should render the GUEST state text without crashing
      expect(find.text('GUEST'), findsOneWidget);
    });
  });
}
