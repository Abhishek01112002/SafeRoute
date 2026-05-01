// lib/models/location_ping_model.dart
// ZoneType has moved to zone_model.dart — import from there.
import 'package:flutter/material.dart';
import 'package:saferoute/models/zone_model.dart';
export 'package:saferoute/models/zone_model.dart' show ZoneType, ZoneTypeExtension;


class LocationPing {
  final int? id;
  final String touristId;
  final double latitude;
  final double longitude;
  final double speedKmh;
  final double accuracyMeters;
  final DateTime timestamp;
  final bool isSynced;
  final ZoneType zoneStatus;

  LocationPing({
    this.id,
    required this.touristId,
    required this.latitude,
    required this.longitude,
    required this.speedKmh,
    required this.accuracyMeters,
    required this.timestamp,
    this.isSynced = false,
    required this.zoneStatus,
  });

  factory LocationPing.fromJson(Map<String, dynamic> json) => LocationPing(
        id: json["id"],
        touristId: json["tourist_id"],
        latitude: json["latitude"].toDouble(),
        longitude: json["longitude"].toDouble(),
        speedKmh: (json["speed_kmh"] ?? 0.0).toDouble(),
        accuracyMeters: (json["accuracy_meters"] ?? 0.0).toDouble(),
        timestamp: DateTime.parse(json["timestamp"]),
        isSynced: json["is_synced"] == 1 || json["is_synced"] == true,
        zoneStatus: ZoneTypeExtension.fromString(json["zone_status"] ?? ""),
      );

  Map<String, dynamic> toJson() => {
        "id": id,
        "tourist_id": touristId,
        "latitude": latitude,
        "longitude": longitude,
        "speed_kmh": speedKmh,
        "accuracy_meters": accuracyMeters,
        "timestamp": timestamp.toIso8601String(),
        "is_synced": isSynced ? 1 : 0,
        "zone_status": zoneStatus.name,
      };

  factory LocationPing.fromMap(Map<String, dynamic> map) => LocationPing(
        id: map["id"],
        touristId: map["touristId"],
        latitude: map["latitude"],
        longitude: map["longitude"],
        speedKmh: map["speedKmh"],
        accuracyMeters: map["accuracyMeters"],
        timestamp: DateTime.fromMillisecondsSinceEpoch(map["timestamp"]),
        isSynced: map["isSynced"] == 1,
        zoneStatus: ZoneTypeExtension.fromString(map["zoneStatus"] ?? ""),
      );

  Map<String, dynamic> toMap() => {
        "id": id,
        "touristId": touristId,
        "latitude": latitude,
        "longitude": longitude,
        "speedKmh": speedKmh,
        "accuracyMeters": accuracyMeters,
        "timestamp": timestamp.millisecondsSinceEpoch,
        "isSynced": isSynced ? 1 : 0,
        "zoneStatus": zoneStatus.name,
      };
}
