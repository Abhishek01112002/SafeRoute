// lib/services/safety_engine.dart
import 'package:flutter/material.dart';
import 'package:saferoute/models/zone_model.dart';
import 'package:saferoute/models/location_ping_model.dart';

enum SafetyRiskLevel { low, medium, high }

class SafetyEngine {
  /// Compute real-time risk from environmental + device state.
  /// Priority hierarchy is strict — highest matching rule wins.
  static SafetyRiskLevel calculateRisk({
    required ZoneType zone,
    required double batteryLevel,   // 0.0–1.0
    required bool isMeshConnected,
    required double speedKmh,
    required DateTime lastMovementTime,
  }) {
    // 1. RESTRICTED zone — absolute maximum risk
    if (zone == ZoneType.restricted || zone == ZoneType.red) return SafetyRiskLevel.high;

    // 2. Critical battery (< 10%) — still high
    if (batteryLevel < 0.10) return SafetyRiskLevel.high;

    // 3. CAUTION zone or low battery (< 25%)
    if (zone == ZoneType.caution || zone == ZoneType.yellow || batteryLevel < 0.25) {
      return SafetyRiskLevel.medium;
    }

    // 4. No mesh connectivity
    if (!isMeshConnected) return SafetyRiskLevel.medium;

    // 5. Prolonged stillness — possible fall or incapacitation
    final idleMinutes = DateTime.now().difference(lastMovementTime).inMinutes;
    if (idleMinutes > 15 && speedKmh < 0.5) return SafetyRiskLevel.medium;

    return SafetyRiskLevel.low;
  }

  static Color getRiskColor(SafetyRiskLevel level) {
    switch (level) {
      case SafetyRiskLevel.high:   return Colors.redAccent;
      case SafetyRiskLevel.medium: return Colors.orangeAccent;
      case SafetyRiskLevel.low:    return Colors.greenAccent;
    }
  }

  static String getRiskLabel(SafetyRiskLevel level) {
    switch (level) {
      case SafetyRiskLevel.high:   return 'CRITICAL RISK';
      case SafetyRiskLevel.medium: return 'CAUTION';
      case SafetyRiskLevel.low:    return 'SECURE';
    }
  }

  static String getRiskAdvice(SafetyRiskLevel level) {
    switch (level) {
      case SafetyRiskLevel.high:
        return 'Immediate action required. Deploy SOS if immobilized. Move to extraction point.';
      case SafetyRiskLevel.medium:
        return 'Warning: System stress detected. Check battery and move to a stable mesh zone.';
      case SafetyRiskLevel.low:
        return 'System nominal. Continue as planned.';
    }
  }
}
