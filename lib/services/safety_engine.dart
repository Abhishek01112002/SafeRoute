// lib/services/safety_engine.dart
import 'package:flutter/material.dart';
import 'package:saferoute/models/location_ping_model.dart';

enum SafetyRiskLevel { low, medium, high }

class SafetyEngine {
  /// Computes a real-time risk level based on environmental and device factors.
  /// Risk = f(Zone, Battery, connectivity, movement)
  static SafetyRiskLevel calculateRisk({
    required ZoneType zone,
    required double batteryLevel,
    required bool isMeshConnected,
    required double speedKmh,
    required DateTime lastMovementTime,
  }) {
    // 1. Priority Hierarchy: RED Zone is the absolute highest risk
    if (zone == ZoneType.red) return SafetyRiskLevel.high;

    // 2. Battery Critical (Lower than Red Zone, still High)
    if (batteryLevel < 0.10) return SafetyRiskLevel.high;

    // 3. Yellow Zone or Extreme Battery Warning (Medium)
    if (zone == ZoneType.yellow || batteryLevel < 0.25)
      return SafetyRiskLevel.medium;

    // 4. Connectivity Loss (Medium)
    if (!isMeshConnected) return SafetyRiskLevel.medium;

    // 5. Movement Factor (Immobility)
    final idleDuration = DateTime.now().difference(lastMovementTime).inMinutes;
    if (idleDuration > 15 && speedKmh < 0.5) {
      return SafetyRiskLevel.medium;
    }

    // Default: System Secure
    return SafetyRiskLevel.low;
  }

  static Color getRiskColor(SafetyRiskLevel level) {
    switch (level) {
      case SafetyRiskLevel.high:
        return Colors.redAccent;
      case SafetyRiskLevel.medium:
        return Colors.orangeAccent;
      case SafetyRiskLevel.low:
        return Colors.greenAccent;
    }
  }

  static String getRiskLabel(SafetyRiskLevel level) {
    switch (level) {
      case SafetyRiskLevel.high:
        return "CRITICAL RISK";
      case SafetyRiskLevel.medium:
        return "CAUTION";
      case SafetyRiskLevel.low:
        return "SECURE";
    }
  }

  static String getRiskAdvice(SafetyRiskLevel level) {
    switch (level) {
      case SafetyRiskLevel.high:
        return "Immediate action required. Deploy SOS if immobilized. Move to extraction point.";
      case SafetyRiskLevel.medium:
        return "Warning: System stress detected. Check battery levels and head to stable mesh zones.";
      case SafetyRiskLevel.low:
        return "System nominal. Perimeter secure. Continue mission as planned.";
    }
  }
}
