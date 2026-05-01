// lib/providers/safety_system_provider.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:saferoute/models/location_ping_model.dart';
import 'package:saferoute/services/safety_engine.dart';
import 'package:saferoute/services/simulation_engine.dart';

enum SafetyEventType { zoneChanged, riskUpdated, sosTriggered, nodeDetected, batteryLow }

class SafetyEvent {
  final SafetyEventType type;
  final String message;
  final DateTime timestamp;
  final dynamic data;

  SafetyEvent({
    required this.type,
    required this.message,
    required this.timestamp,
    this.data,
  });
}

class SafetySystemProvider with ChangeNotifier {
  final _eventController = StreamController<SafetyEvent>.broadcast();
  List<SafetyEvent> _eventBuffer = [];
  Timer? _coalesceTimer;
  
  // State
  SafetyRiskLevel _currentRisk = SafetyRiskLevel.low;
  List<SimulatedNode> _nearbyNodes = [];
  final List<SafetyEvent> _activityLog = [];
  
  // Debounce/Smoothing
  DateTime _lastRiskUpdateTime = DateTime.fromMillisecondsSinceEpoch(0);
  ZoneType _lastZone = ZoneType.none;

  // Streams
  Stream<SafetyEvent> get eventStream => _eventController.stream;
  
  // Getters
  SafetyRiskLevel get currentRisk => _currentRisk;
  List<SimulatedNode> get nearbyNodes => _nearbyNodes;
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

    // 1. Debounced Risk Calculation (Every 5 seconds)
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
          message: "Risk level adjusted to ${SafetyEngine.getRiskLabel(newRisk)}",
          timestamp: now,
          data: newRisk,
        ));
      }
    }

    // 2. Zone Change Tracking
    if (zone != _lastZone) {
      _addEvent(SafetyEvent(
        type: SafetyEventType.zoneChanged,
        message: "Status: Entered ${zone.toString().split('.').last.toUpperCase()} perimeter",
        timestamp: now,
        data: zone,
      ));
      _lastZone = zone;
    }

    // 3. SOS Trigger (Event-Driven)
    if (isSosActive && !_activityLog.any((e) => e.type == SafetyEventType.sosTriggered && now.difference(e.timestamp).inMinutes < 1)) {
       _addEvent(SafetyEvent(
        type: SafetyEventType.sosTriggered,
        message: "CRITICAL: SOS signal broadcast initiated",
        timestamp: now,
      ));
    }

    // 4. Deterministic Node Generation
    if (position != null) {
      final newNodes = SimulationEngine.getNearbyNodes(position, now);
      // Only update if nodes change (simulation window)
      if (_nearbyNodes.isEmpty || newNodes.first.id != _nearbyNodes.first.id) {
        _nearbyNodes = newNodes;
        _addEvent(SafetyEvent(
          type: SafetyEventType.nodeDetected,
          message: "Mesh Sync: Found ${newNodes.length} nearby safety nodes",
          timestamp: now,
          data: newNodes,
        ));
      }
    }
    // notifyListeners() is now handled by _processEvent to minimize redundant builds
  }

  void _addEvent(SafetyEvent event) {
    // SOS events are critical and bypass coalescing
    if (event.type == SafetyEventType.sosTriggered) {
      _processEvent(event);
      return;
    }

    // Buffer other events for coalescing
    _eventBuffer.add(event);
    _coalesceTimer?.cancel();
    _coalesceTimer = Timer(const Duration(milliseconds: 500), () {
      if (_eventBuffer.isNotEmpty) {
        for (var e in _eventBuffer) {
          _processEvent(e);
        }
        _eventBuffer.clear();
      }
    });
  }

  void _processEvent(SafetyEvent event) {
    _activityLog.add(event);
    if (_activityLog.length > 50) _activityLog.removeAt(0);
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
