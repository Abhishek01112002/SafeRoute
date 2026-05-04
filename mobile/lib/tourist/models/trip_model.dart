// lib/tourist/models/trip_model.dart
import 'package:flutter/foundation.dart';

enum TripStatus { planned, active, completed, cancelled }

extension TripStatusX on TripStatus {
  String get label {
    switch (this) {
      case TripStatus.planned:    return 'Planned';
      case TripStatus.active:     return 'Active';
      case TripStatus.completed:  return 'Completed';
      case TripStatus.cancelled:  return 'Cancelled';
    }
  }

  bool get isActive => this == TripStatus.active;
}

class TripStop {
  final int? stopId;
  final String tripId;
  final String? destinationId;
  final String name;
  final String? destinationState;
  final DateTime visitDateFrom;
  final DateTime visitDateTo;
  final int orderIndex;
  final double? centerLat;
  final double? centerLng;

  const TripStop({
    this.stopId,
    required this.tripId,
    this.destinationId,
    required this.name,
    this.destinationState,
    required this.visitDateFrom,
    required this.visitDateTo,
    this.orderIndex = 1,
    this.centerLat,
    this.centerLng,
  });

  factory TripStop.fromJson(Map<String, dynamic> json) => TripStop(
        stopId: json['stop_id'] as int?,
        tripId: json['trip_id'] as String? ?? '',
        destinationId: json['destination_id'] as String?,
        name: json['name'] as String? ?? '',
        destinationState: json['destination_state'] as String?,
        visitDateFrom: DateTime.parse(json['visit_date_from'] as String),
        visitDateTo: DateTime.parse(json['visit_date_to'] as String),
        orderIndex: json['order_index'] as int? ?? 1,
        centerLat: (json['center_lat'] as num?)?.toDouble(),
        centerLng: (json['center_lng'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'stop_id': stopId,
        'trip_id': tripId,
        'destination_id': destinationId,
        'name': name,
        'destination_state': destinationState,
        'visit_date_from': visitDateFrom.toIso8601String(),
        'visit_date_to': visitDateTo.toIso8601String(),
        'order_index': orderIndex,
        'center_lat': centerLat,
        'center_lng': centerLng,
      };
}

@immutable
class Trip {
  final String tripId;
  final String touristId;
  final TripStatus status;
  final DateTime tripStartDate;
  final DateTime tripEndDate;
  final String? primaryState;
  final String? notes;
  final List<TripStop> stops;
  final DateTime createdAt;

  const Trip({
    required this.tripId,
    required this.touristId,
    required this.status,
    required this.tripStartDate,
    required this.tripEndDate,
    this.primaryState,
    this.notes,
    this.stops = const [],
    required this.createdAt,
  });

  bool get isActive => status == TripStatus.active;

  /// Returns the stop the tourist is currently at (first stop within today's range,
  /// or the first stop overall if none match today).
  TripStop? get currentStop {
    final now = DateTime.now();
    for (final stop in stops) {
      if (!now.isBefore(stop.visitDateFrom) && !now.isAfter(stop.visitDateTo)) {
        return stop;
      }
    }
    return stops.isNotEmpty ? stops.first : null;
  }

  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
        tripId: json['trip_id'] as String,
        touristId: json['tourist_id'] as String,
        status: TripStatus.values.firstWhere(
          (e) => e.name.toUpperCase() == (json['status'] as String? ?? 'PLANNED').toUpperCase(),
          orElse: () => TripStatus.planned,
        ),
        tripStartDate: DateTime.parse(json['trip_start_date'] as String),
        tripEndDate: DateTime.parse(json['trip_end_date'] as String),
        primaryState: json['primary_state'] as String?,
        notes: json['notes'] as String?,
        stops: (json['stops'] as List<dynamic>? ?? [])
            .map((s) => TripStop.fromJson(s as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'trip_id': tripId,
        'tourist_id': touristId,
        'status': status.name.toUpperCase(),
        'trip_start_date': tripStartDate.toIso8601String(),
        'trip_end_date': tripEndDate.toIso8601String(),
        'primary_state': primaryState,
        'notes': notes,
        'stops': stops.map((s) => s.toJson()).toList(),
        'created_at': createdAt.toIso8601String(),
      };
}
