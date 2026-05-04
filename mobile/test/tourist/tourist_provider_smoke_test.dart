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
import 'package:saferoute/services/api_service.dart';
import 'package:saferoute/services/database_service.dart';

import 'package:saferoute/tourist/providers/tourist_provider.dart';
import 'package:saferoute/tourist/models/tourist_model.dart';
import 'package:saferoute/utils/app_theme.dart';
import 'package:saferoute/core/providers/theme_provider.dart';
import 'package:saferoute/core/service_locator.dart';

// Mock classes for testing
class MockApiService implements ApiService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class MockDatabaseService implements DatabaseService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
  
  @override
  Future<Tourist?> getTourist() async => null;
}

void main() {
  setUp(() async {
    // Reset GetIt before each test to avoid state leakage
    await locator.reset();
    
    // Register stubs to prevent 'GetIt not found' errors during TouristProvider construction
    locator.registerSingleton<ApiService>(MockApiService());
    locator.registerSingleton<DatabaseService>(MockDatabaseService());
    
    SharedPreferences.setMockInitialValues({});
  });

  group('TouristProvider — initial state', () {
    test('starts in GUEST user state', () {
      final provider = TouristProvider();
      expect(provider.userState, UserState.guest);
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

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => TouristProvider(),
          child: MaterialApp(
            home: Scaffold(
              body: Builder(builder: (context) {
                final tourist = Provider.of<TouristProvider>(context);
                return Text(tourist.userState.toString());
              }),
            ),
          ),
        ),
      );
      
      await tester.pump();
      // Provider should render the state text without crashing
      expect(find.text(UserState.guest.toString()), findsOneWidget);
    });
  });
}
