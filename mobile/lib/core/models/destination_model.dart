// lib/models/destination_model.dart
// Typed destination — replaces raw Map<String,dynamic> usage throughout the app.

import 'package:saferoute/core/models/emergency_contact_model.dart';

enum DifficultyLevel { low, moderate, high, veryHigh }
enum ConnectivityLevel { excellent, good, moderate, poor, veryPoor, none }

extension DifficultyLevelExtension on DifficultyLevel {
  static DifficultyLevel fromString(String s) {
    switch (s.toUpperCase()) {
      case 'LOW':       return DifficultyLevel.low;
      case 'MODERATE':  return DifficultyLevel.moderate;
      case 'HIGH':      return DifficultyLevel.high;
      case 'VERY_HIGH': return DifficultyLevel.veryHigh;
      default:          return DifficultyLevel.low;
    }
  }

  String toApiString() {
    switch (this) {
      case DifficultyLevel.low:      return 'LOW';
      case DifficultyLevel.moderate: return 'MODERATE';
      case DifficultyLevel.high:     return 'HIGH';
      case DifficultyLevel.veryHigh: return 'VERY_HIGH';
    }
  }

  String get displayLabel {
    switch (this) {
      case DifficultyLevel.low:      return 'Easy';
      case DifficultyLevel.moderate: return 'Moderate';
      case DifficultyLevel.high:     return 'High';
      case DifficultyLevel.veryHigh: return 'Very High';
    }
  }
}

extension ConnectivityLevelExtension on ConnectivityLevel {
  static ConnectivityLevel fromString(String s) {
    switch (s.toUpperCase()) {
      case 'EXCELLENT': return ConnectivityLevel.excellent;
      case 'GOOD':      return ConnectivityLevel.good;
      case 'MODERATE':  return ConnectivityLevel.moderate;
      case 'POOR':      return ConnectivityLevel.poor;
      case 'VERY_POOR': return ConnectivityLevel.veryPoor;
      case 'NONE':      return ConnectivityLevel.none;
      default:          return ConnectivityLevel.moderate;
    }
  }

  String toApiString() {
    switch (this) {
      case ConnectivityLevel.excellent: return 'EXCELLENT';
      case ConnectivityLevel.good:      return 'GOOD';
      case ConnectivityLevel.moderate:  return 'MODERATE';
      case ConnectivityLevel.poor:      return 'POOR';
      case ConnectivityLevel.veryPoor:  return 'VERY_POOR';
      case ConnectivityLevel.none:      return 'NONE';
    }
  }

  bool get requiresOfflineMode {
    return this == ConnectivityLevel.veryPoor || this == ConnectivityLevel.none;
  }

  String get displayLabel {
    switch (this) {
      case ConnectivityLevel.excellent: return 'Excellent';
      case ConnectivityLevel.good:      return 'Good';
      case ConnectivityLevel.moderate:  return 'Moderate';
      case ConnectivityLevel.poor:      return 'Poor';
      case ConnectivityLevel.veryPoor:  return 'Very Poor';
      case ConnectivityLevel.none:      return 'No Signal';
    }
  }
}

class DestinationCoordinates {
  final double lat;
  final double lng;

  const DestinationCoordinates({required this.lat, required this.lng});

  factory DestinationCoordinates.fromJson(Map<String, dynamic> j) =>
      DestinationCoordinates(
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};
}

class DestinationModel {
  final String id;
  final String state;
  final String name;
  final String district;
  final int altitudeM;
  final DestinationCoordinates coordinates;
  final String category;
  final DifficultyLevel difficulty;
  final ConnectivityLevel connectivity;
  final String bestSeason;
  final List<String> warnings;
  final String? authorityId;   // jurisdiction owner (district-level authority)
  final bool isActive;

  // Populated separately when fetched with contacts
  final List<EmergencyContact> emergencyContacts;

  const DestinationModel({
    required this.id,
    required this.state,
    required this.name,
    required this.district,
    required this.altitudeM,
    required this.coordinates,
    required this.category,
    required this.difficulty,
    required this.connectivity,
    required this.bestSeason,
    required this.warnings,
    this.authorityId,
    required this.isActive,
    this.emergencyContacts = const [],
  });

  factory DestinationModel.fromJson(Map<String, dynamic> j) {
    List<String> warnings = [];
    if (j['warnings'] is List) {
      warnings = (j['warnings'] as List).map((e) => e.toString()).toList();
    } else if (j['warnings_json'] is String) {
      try {
        final decoded = j['warnings_json'] as String;
        // simple parse
        warnings = decoded
            .replaceAll('[', '').replaceAll(']', '')
            .split(',')
            .map((s) => s.trim().replaceAll('"', ''))
            .where((s) => s.isNotEmpty)
            .toList();
      } catch (_) {}
    }

    DestinationCoordinates coords;
    if (j['coordinates'] is Map) {
      coords = DestinationCoordinates.fromJson(j['coordinates'] as Map<String, dynamic>);
    } else {
      coords = DestinationCoordinates(
        lat: (j['center_lat'] as num? ?? 0).toDouble(),
        lng: (j['center_lng'] as num? ?? 0).toDouble(),
      );
    }

    return DestinationModel(
      id:           j['id'] as String,
      state:        j['state'] as String? ?? '',
      name:         j['name'] as String,
      district:     j['district'] as String? ?? '',
      altitudeM:    (j['altitude_m'] as num? ?? 0).toInt(),
      coordinates:  coords,
      category:     j['category'] as String? ?? '',
      difficulty:   DifficultyLevelExtension.fromString(j['difficulty'] as String? ?? ''),
      connectivity: ConnectivityLevelExtension.fromString(j['connectivity'] as String? ?? ''),
      bestSeason:   j['best_season'] as String? ?? '',
      warnings:     warnings,
      authorityId:  j['authority_id'] as String?,
      isActive:     (j['is_active'] == true || j['is_active'] == 1),
      emergencyContacts: j['emergency_contacts'] != null
          ? (j['emergency_contacts'] as List)
              .map((e) => EmergencyContact.fromJson(e as Map<String, dynamic>))
              .toList()
          : [],
    );
  }

  Map<String, dynamic> toJson() => {
    'id':           id,
    'state':        state,
    'name':         name,
    'district':     district,
    'altitude_m':   altitudeM,
    'coordinates':  coordinates.toJson(),
    'category':     category,
    'difficulty':   difficulty.toApiString(),
    'connectivity': connectivity.toApiString(),
    'best_season':  bestSeason,
    'warnings':     warnings,
    'authority_id': authorityId,
    'is_active':    isActive,
  };
}
