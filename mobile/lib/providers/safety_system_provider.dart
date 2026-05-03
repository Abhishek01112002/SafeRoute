// lib/providers/safety_system_provider.dart
// Removed SimulationEngine — no more fake/deterministic node generation.
// nearbyNodes is now sourced from the real BLE MeshProvider via the ProxyProvider in main.dart.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:saferoute/models/zone_model.dart';
import 'package:saferoute/services/safety_engine.dart';

export 'package:saferoute/services/safety_engine.dart' show SafetyRiskLevel;

enum SafetyEventType { zoneChanged, riskUpdated, sosTriggered, batteryLow }

class SafetyEvent {
  final SafetyEventType type;
  final String message;
  final DateTime timestamp;
  final dynamic data;

  const SafetyEvent({
    required this.type,
    required this.message,
    required this.timestamp,
    this.data,
  });
}

class SafetySystemProvider with ChangeNotifier {
  final _eventController = StreamController<SafetyEvent>.broadcast();
  final List<SafetyEvent> _activityLog = [];
  final List<SafetyEvent> _eventBuffer = [];
  Timer? _coalesceTimer;

  SafetyRiskLevel _currentRisk = SafetyRiskLevel.low;
  ZoneType _lastZone = ZoneType.safe;
  DateTime _lastRiskUpdateTime = DateTime.fromMillisecondsSinceEpoch(0);

  Stream<SafetyEvent> get eventStream => _eventController.stream;
  SafetyRiskLevel get currentRisk => _currentRisk;
  List<SafetyEvent> get activityLog => _activityLog.reversed.toList();

  void updateState({
    required LatLng? position,
    required ZoneType zone,
    required double batteryLevel,
    required double speedKmh,
    required DateTime lastMovement,
    required bool isSosActive,
  }) {
    final now = DateTime.now();

    // 1. Risk calculation — debounced at 5-second intervals
    if (now.difference(_lastRiskUpdateTime).inSeconds >= 5) {
      final newRisk = SafetyEngine.calculateRisk(
        zone: zone,
        batteryLevel: batteryLevel,
        isMeshConnected: true,
        speedKmh: speedKmh,
        lastMovementTime: lastMovement,
      );
      if (newRisk != _currentRisk) {
        _currentRisk = newRisk;
        _lastRiskUpdateTime = now;
        _addEvent(SafetyEvent(
          type: SafetyEventType.riskUpdated,
          message: 'Risk level: ${SafetyEngine.getRiskLabel(newRisk)}',
          timestamp: now,
          data: newRisk,
        ));
      }
    }

    // 2. Zone change tracking
    if (zone != _lastZone) {
      _addEvent(SafetyEvent(
        type: SafetyEventType.zoneChanged,
        message: 'Entered ${zone.displayLabel}',
        timestamp: now,
        data: zone,
      ));
      _lastZone = zone;
    }

    // 3. SOS (rate-limited to once per minute)
    if (isSosActive &&
        !_activityLog.any((e) =>
            e.type == SafetyEventType.sosTriggered &&
            now.difference(e.timestamp).inMinutes < 1)) {
      _addEvent(SafetyEvent(
        type: SafetyEventType.sosTriggered,
        message: 'CRITICAL: SOS signal broadcast initiated',
        timestamp: now,
      ));
    }

    // 4. Battery critical alert (once per 5 minutes)
    if (batteryLevel < 0.10 &&
        !_activityLog.any((e) =>
            e.type == SafetyEventType.batteryLow &&
            now.difference(e.timestamp).inMinutes < 5)) {
      _addEvent(SafetyEvent(
        type: SafetyEventType.batteryLow,
        message: 'Battery critical: ${(batteryLevel * 100).toInt()}% remaining',
        timestamp: now,
      ));
    }
  }

  void _addEvent(SafetyEvent event) {
    // SOS bypasses coalescing — always immediate
    if (event.type == SafetyEventType.sosTriggered) {
      _processEvent(event);
      return;
    }
    _eventBuffer.add(event);
    _coalesceTimer?.cancel();
    _coalesceTimer = Timer(const Duration(milliseconds: 500), () {
      for (final e in _eventBuffer) {
        _processEvent(e);
      }
      _eventBuffer.clear();
    });
  }

  void _processEvent(SafetyEvent event) {
    _activityLog.add(event);
    if (_activityLog.length > 100) _activityLog.removeAt(0);
    _eventController.add(event);
    notifyListeners();
  }

  @override
  void dispose() {
    _coalesceTimer?.cancel();
    _eventController.close();
    super.dispose();
  }
}
