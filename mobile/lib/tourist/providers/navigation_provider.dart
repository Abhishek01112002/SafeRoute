import 'dart:math';
import 'package:flutter/material.dart';

class NavigationLeg {
  final String direction;
  final String maneuver;
  final double remainingDistanceMeters;
  final Duration eta;

  const NavigationLeg({
    required this.direction,
    required this.maneuver,
    required this.remainingDistanceMeters,
    required this.eta,
  });

  NavigationLeg copyWith({
    String? direction,
    String? maneuver,
    double? remainingDistanceMeters,
    Duration? eta,
  }) {
    return NavigationLeg(
      direction: direction ?? this.direction,
      maneuver: maneuver ?? this.maneuver,
      remainingDistanceMeters:
          remainingDistanceMeters ?? this.remainingDistanceMeters,
      eta: eta ?? this.eta,
    );
  }
}

class MainNavigationProvider extends ChangeNotifier {
  int _currentIndex = 0;
  bool _isImmersive = false;
  bool _isNavigating = false;
  NavigationLeg? _currentLeg;
  List<NavigationLeg> _routeLegs = [];
  int _routeIndex = 0;
  DateTime? _lastLocationTs;
  double? _lastLat;
  double? _lastLng;

  int get currentIndex => _currentIndex;
  bool get isImmersive => _isImmersive;
  bool get isNavigating => _isNavigating;
  NavigationLeg? get currentLeg => _currentLeg;

  void setIndex(int index) {
    if (_currentIndex != index) {
      _currentIndex = index;
      _isImmersive = false; // Reset immersive mode when switching screens
      notifyListeners();
    }
  }

  void setImmersive(bool value) {
    if (_isImmersive != value) {
      _isImmersive = value;
      notifyListeners();
    }
  }

  void startNavigation({NavigationLeg? initialLeg}) {
    _isNavigating = true;
    if (initialLeg != null) _currentLeg = initialLeg;
    notifyListeners();
  }

  void stopNavigation() {
    _isNavigating = false;
    _currentLeg = null;
    _routeLegs = [];
    _routeIndex = 0;
    _lastLocationTs = null;
    _lastLat = null;
    _lastLng = null;
    notifyListeners();
  }

  void updateCurrentLeg(NavigationLeg leg) {
    final shouldNotify = _currentLeg == null ||
        _currentLeg!.direction != leg.direction ||
        _currentLeg!.maneuver != leg.maneuver ||
        (_currentLeg!.remainingDistanceMeters - leg.remainingDistanceMeters)
                .abs() >
            5 ||
        (_currentLeg!.eta.inSeconds - leg.eta.inSeconds).abs() > 5;

    _currentLeg = leg;
    if (shouldNotify) notifyListeners();
  }

  void startNavigationRoute(List<NavigationLeg> legs) {
    if (legs.isEmpty) return;
    _routeLegs = legs;
    _routeIndex = 0;
    _currentLeg = _routeLegs.first;
    _isNavigating = true;
    _lastLocationTs = null;
    _lastLat = null;
    _lastLng = null;
    notifyListeners();
  }

  void ingestLocation({
    required double latitude,
    required double longitude,
    required double speedKmh,
    required DateTime timestamp,
    required String headingDirection,
  }) {
    if (!_isNavigating || _currentLeg == null || _routeLegs.isEmpty) return;

    if (_lastLat == null || _lastLng == null || _lastLocationTs == null) {
      _lastLat = latitude;
      _lastLng = longitude;
      _lastLocationTs = timestamp;
      _refreshEta(speedKmh: speedKmh, headingDirection: headingDirection);
      notifyListeners();
      return;
    }

    final movedMeters = _distanceMeters(
      _lastLat!,
      _lastLng!,
      latitude,
      longitude,
    );

    _lastLat = latitude;
    _lastLng = longitude;
    _lastLocationTs = timestamp;

    // Ignore micro-jitter to avoid noisy leg updates.
    if (movedMeters < 1.5) {
      _refreshEta(speedKmh: speedKmh, headingDirection: headingDirection);
      notifyListeners();
      return;
    }

    final remaining = (_currentLeg!.remainingDistanceMeters - movedMeters)
        .clamp(0.0, double.infinity);

    if (remaining <= 1.0) {
      if (_routeIndex < _routeLegs.length - 1) {
        _routeIndex += 1;
        _currentLeg = _routeLegs[_routeIndex];
      } else {
        stopNavigation();
        return;
      }
    } else {
      _currentLeg = _currentLeg!.copyWith(remainingDistanceMeters: remaining);
    }

    _refreshEta(speedKmh: speedKmh, headingDirection: headingDirection);
    notifyListeners();
  }

  void _refreshEta({
    required double speedKmh,
    required String headingDirection,
  }) {
    if (_currentLeg == null) return;
    final metersPerMin = (speedKmh.clamp(1.0, 35.0) * 1000) / 60;
    final etaMin = (_currentLeg!.remainingDistanceMeters / metersPerMin)
        .ceil()
        .clamp(1, 30);
    _currentLeg = _currentLeg!.copyWith(
      eta: Duration(minutes: etaMin),
      direction: headingDirection,
    );
  }

  double _distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = (sin(dLat / 2) * sin(dLat / 2)) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) * (sin(dLon / 2) * sin(dLon / 2));
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRad(double deg) => deg * 0.017453292519943295;
}
