import 'package:flutter_test/flutter_test.dart';
import 'package:saferoute/tourist/providers/navigation_provider.dart';

void main() {
  group('MainNavigationProvider route progression', () {
    test('advances to next leg after sufficient movement', () {
      final provider = MainNavigationProvider();
      provider.startNavigationRoute(const [
        NavigationLeg(
          direction: 'N',
          maneuver: 'Leg 1',
          remainingDistanceMeters: 50,
          eta: Duration(minutes: 2),
        ),
        NavigationLeg(
          direction: 'N',
          maneuver: 'Leg 2',
          remainingDistanceMeters: 80,
          eta: Duration(minutes: 3),
        ),
      ]);

      final t0 = DateTime(2026, 1, 1, 10, 0, 0);

      // Baseline point initializes tracking.
      provider.ingestLocation(
        latitude: 30.0000,
        longitude: 78.0000,
        speedKmh: 5,
        timestamp: t0,
        headingDirection: 'N',
      );

      // ~67m northward shift should complete first 50m leg.
      provider.ingestLocation(
        latitude: 30.0006,
        longitude: 78.0000,
        speedKmh: 5,
        timestamp: t0.add(const Duration(seconds: 20)),
        headingDirection: 'N',
      );

      expect(provider.isNavigating, isTrue);
      expect(provider.currentLeg, isNotNull);
      expect(provider.currentLeg!.maneuver, 'Leg 2');
    });

    test('stops navigation after final leg completion', () {
      final provider = MainNavigationProvider();
      provider.startNavigationRoute(const [
        NavigationLeg(
          direction: 'E',
          maneuver: 'Final leg',
          remainingDistanceMeters: 20,
          eta: Duration(minutes: 1),
        ),
      ]);

      final t0 = DateTime(2026, 1, 1, 10, 0, 0);
      provider.ingestLocation(
        latitude: 30.0000,
        longitude: 78.0000,
        speedKmh: 4,
        timestamp: t0,
        headingDirection: 'E',
      );

      // ~55m eastward shift should finish final leg and auto-stop.
      provider.ingestLocation(
        latitude: 30.0000,
        longitude: 78.0006,
        speedKmh: 4,
        timestamp: t0.add(const Duration(seconds: 20)),
        headingDirection: 'E',
      );

      expect(provider.isNavigating, isFalse);
      expect(provider.currentLeg, isNull);
    });
  });

  group('Distance calculations (Haversine formula)', () {
    test('calculates accurate distance between two coordinates', () {
      final provider = MainNavigationProvider();
      provider.startNavigationRoute(const [
        NavigationLeg(
          direction: 'N',
          maneuver: 'Test leg',
          remainingDistanceMeters: 1000,
          eta: Duration(minutes: 10),
        ),
      ]);

      final t0 = DateTime(2026, 1, 1, 10, 0, 0);

      // Start at known location
      provider.ingestLocation(
        latitude: 30.0000,
        longitude: 78.0000,
        speedKmh: 5,
        timestamp: t0,
        headingDirection: 'N',
      );

      // Move ~111m north (1 second of arc ≈ 111m at equator, less at 30°N)
      provider.ingestLocation(
        latitude: 30.0010,  // ~111m north at 30°N latitude
        longitude: 78.0000,
        speedKmh: 5,
        timestamp: t0.add(const Duration(seconds: 30)),
        headingDirection: 'N',
      );

      // Distance should be approximately 111m (±5m for latitude approximation)
      expect(provider.currentLeg, isNotNull);
      // Remaining distance should be ~1000 - 111 = 889m
      expect(
        provider.currentLeg!.remainingDistanceMeters,
        closeTo(889, 10), // Within 10m tolerance
      );
    });

    test('handles east-west distance correctly', () {
      final provider = MainNavigationProvider();
      provider.startNavigationRoute(const [
        NavigationLeg(
          direction: 'E',
          maneuver: 'East leg',
          remainingDistanceMeters: 500,
          eta: Duration(minutes: 5),
        ),
      ]);

      final t0 = DateTime(2026, 1, 1, 10, 0, 0);

      provider.ingestLocation(
        latitude: 30.0000,
        longitude: 78.0000,
        speedKmh: 5,
        timestamp: t0,
        headingDirection: 'E',
      );

      // Move ~96m east at 30°N latitude (1 second of arc = 111m * cos(30°) ≈ 96m)
      provider.ingestLocation(
        latitude: 30.0000,
        longitude: 78.0010,
        speedKmh: 5,
        timestamp: t0.add(const Duration(seconds: 20)),
        headingDirection: 'E',
      );

      expect(provider.currentLeg, isNotNull);
      // Remaining distance should be ~500 - 96 = 404m
      expect(
        provider.currentLeg!.remainingDistanceMeters,
        closeTo(404, 10),
      );
    });
  });

  group('ETA calculations', () {
    test('calculates ETA based on speed and remaining distance', () {
      final provider = MainNavigationProvider();
      provider.startNavigationRoute(const [
        NavigationLeg(
          direction: 'N',
          maneuver: 'ETA test',
          remainingDistanceMeters: 2000,  // 2km
          eta: Duration(minutes: 30),  // Initial placeholder
        ),
      ]);

      final t0 = DateTime(2026, 1, 1, 10, 0, 0);

      // At 60 km/h, 2km should take 2 minutes
      provider.ingestLocation(
        latitude: 30.0000,
        longitude: 78.0000,
        speedKmh: 60,  // 60 km/h
        timestamp: t0,
        headingDirection: 'N',
      );

      expect(provider.currentLeg, isNotNull);
      // Speed is clamped to 35 km/h max for trekking safety.
      // ETA = ceil(2000m / (35*1000/60 m/min)) = ceil(3.43) = 4 minutes
      expect(provider.currentLeg!.eta.inMinutes, equals(4));
    });

    test('clamps ETA between 1 and 30 minutes', () {
      final provider = MainNavigationProvider();
      provider.startNavigationRoute(const [
        NavigationLeg(
          direction: 'N',
          maneuver: 'Clamp test',
          remainingDistanceMeters: 100,  // Very short
          eta: Duration(minutes: 5),
        ),
      ]);

      final t0 = DateTime(2026, 1, 1, 10, 0, 0);

      // At very high speed, ETA should still be at least 1 minute
      provider.ingestLocation(
        latitude: 30.0000,
        longitude: 78.0000,
        speedKmh: 200,  // Very fast
        timestamp: t0,
        headingDirection: 'N',
      );

      expect(provider.currentLeg!.eta.inMinutes, greaterThanOrEqualTo(1));

      // Test upper clamp with very long distance
      provider.startNavigationRoute(const [
        NavigationLeg(
          direction: 'N',
          maneuver: 'Long leg',
          remainingDistanceMeters: 50000,  // 50km
          eta: Duration(minutes: 60),
        ),
      ]);

      provider.ingestLocation(
        latitude: 30.0000,
        longitude: 78.0000,
        speedKmh: 5,  // Very slow
        timestamp: t0.add(const Duration(minutes: 1)),
        headingDirection: 'N',
      );

      expect(provider.currentLeg!.eta.inMinutes, lessThanOrEqualTo(30));
    });

    test('speed clamping prevents unrealistic ETAs', () {
      final provider = MainNavigationProvider();
      provider.startNavigationRoute(const [
        NavigationLeg(
          direction: 'N',
          maneuver: 'Speed clamp',
          remainingDistanceMeters: 1000,
          eta: Duration(minutes: 10),
        ),
      ]);

      final t0 = DateTime(2026, 1, 1, 10, 0, 0);

      // Speed is clamped between 1 and 35 km/h for ETA calculation
      // At 0 km/h, should use 1 km/h minimum
      provider.ingestLocation(
        latitude: 30.0000,
        longitude: 78.0000,
        speedKmh: 0,  // Stationary
        timestamp: t0,
        headingDirection: 'N',
      );

      // ETA = 1000m / (1*1000/60) = 60 minutes, but clamped to 30
      expect(provider.currentLeg!.eta.inMinutes, equals(30));
    });
  });
}
