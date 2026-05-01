// lib/services/fall_detection_service.dart
import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';

class FallDetectionService {
  static final FallDetectionService _instance =
      FallDetectionService._internal();
  factory FallDetectionService() => _instance;
  FallDetectionService._internal();

  StreamSubscription<UserAccelerometerEvent>? _subscription;
  bool _isMonitoring = false;

  // High-G Spike Threshold (approx 3.0G = ~30 m/s2)
  static const double _spikeThreshold = 30.0;
  // Inactivity Threshold (movement < 2.0 m/s2)
  static const double _inactivityThreshold = 2.0;

  DateTime? _lastSpikeTime;
  double _lastMagnitude = 0.0;
  Function(bool)? onPotentialFall;

  void startMonitoring() {
    if (_isMonitoring) return;
    _isMonitoring = true;

    _subscription =
        userAccelerometerEvents.listen((UserAccelerometerEvent event) {
      final double magnitude =
          sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      _lastMagnitude = magnitude;

      if (magnitude > _spikeThreshold) {
        _lastSpikeTime = DateTime.now();
        // Potential impact detected, start monitoring for inactivity
        _checkInactivity();
      }
    });
  }

  void _checkInactivity() {
    // Wait for 15 seconds to check if the user is moving
    Future.delayed(const Duration(seconds: 15), () {
      if (_lastSpikeTime != null) {
        // Here we would ideally check a rolling window of recent movement
        // For this implementation, we check whether movement is still very low
        // we trigger an 'Are you okay?' callback.
        if (_lastMagnitude < _inactivityThreshold) {
          onPotentialFall?.call(true);
        }
      }
    });
  }

  void stopMonitoring() {
    _subscription?.cancel();
    _isMonitoring = false;
  }
}
