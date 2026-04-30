// lib/models/zone_model.dart
// Canonical zone schema — matches backend DB and local SQLite exactly.
// Zones are always owned by the backend; the app only reads and caches them.

import 'dart:convert';

enum ZoneType { safe, caution, restricted, unknown }
enum ZoneShape { circle, polygon }

extension ZoneTypeExtension on ZoneType {
  static ZoneType fromString(String s) {
    switch (s.toUpperCase()) {
      case 'SAFE':       return ZoneType.safe;
      case 'CAUTION':    return ZoneType.caution;
      case 'RESTRICTED': return ZoneType.restricted;
      default:           return ZoneType.unknown;
    }
  }

  String toApiString() {
    switch (this) {
      case ZoneType.safe:       return 'SAFE';
      case ZoneType.caution:    return 'CAUTION';
      case ZoneType.restricted: return 'RESTRICTED';
      case ZoneType.unknown:    return 'UNKNOWN';
    }
  }

  String get displayLabel {
    switch (this) {
      case ZoneType.safe:       return 'Safe Zone';
      case ZoneType.caution:    return 'Caution Zone';
      case ZoneType.restricted: return 'Restricted Zone';
      case ZoneType.unknown:    return 'Unknown';
    }
  }
}

extension ZoneShapeExtension on ZoneShape {
  static ZoneShape fromString(String s) =>
      s.toUpperCase() == 'POLYGON' ? ZoneShape.polygon : ZoneShape.circle;

  String toApiString() => this == ZoneShape.polygon ? 'POLYGON' : 'CIRCLE';
}

class ZonePoint {
  final double lat;
  final double lng;

  const ZonePoint({required this.lat, required this.lng});

  factory ZonePoint.fromJson(Map<String, dynamic> j) =>
      ZonePoint(lat: (j['lat'] as num).toDouble(), lng: (j['lng'] as num).toDouble());

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};
}

class ZoneModel {
  final String id;
  final String destinationId;
  final String authorityId;
  final String name;
  final ZoneType type;
  final ZoneShape shape;

  // Circle fields (shape == circle)
  final double? centerLat;
  final double? centerLng;
  final double? radiusM;

  // Polygon fields (shape == polygon)
  final List<ZonePoint> polygonPoints;

  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ZoneModel({
    required this.id,
    required this.destinationId,
    required this.authorityId,
    required this.name,
    required this.type,
    required this.shape,
    this.centerLat,
    this.centerLng,
    this.radiusM,
    this.polygonPoints = const [],
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ZoneModel.fromJson(Map<String, dynamic> j) {
    final shape = ZoneShapeExtension.fromString(j['shape'] ?? 'CIRCLE');
    List<ZonePoint> points = [];
    if (j['polygon_points'] != null) {
      final raw = j['polygon_points'] is String
          ? json.decode(j['polygon_points'] as String) as List
          : j['polygon_points'] as List;
      points = raw.map((e) => ZonePoint.fromJson(e as Map<String, dynamic>)).toList();
    }

    return ZoneModel(
      id:            j['id'] as String,
      destinationId: j['destination_id'] as String,
      authorityId:   j['authority_id'] as String? ?? '',
      name:          j['name'] as String,
      type:          ZoneTypeExtension.fromString(j['type'] ?? ''),
      shape:         shape,
      centerLat:     (j['center_lat'] as num?)?.toDouble(),
      centerLng:     (j['center_lng'] as num?)?.toDouble(),
      radiusM:       (j['radius_m'] as num?)?.toDouble(),
      polygonPoints: points,
      isActive:      (j['is_active'] == true || j['is_active'] == 1),
      createdAt:     DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt:     DateTime.tryParse(j['updated_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id':              id,
    'destination_id':  destinationId,
    'authority_id':    authorityId,
    'name':            name,
    'type':            type.toApiString(),
    'shape':           shape.toApiString(),
    'center_lat':      centerLat,
    'center_lng':      centerLng,
    'radius_m':        radiusM,
    'polygon_points':  polygonPoints.map((p) => p.toJson()).toList(),
    'is_active':       isActive,
    'created_at':      createdAt.toIso8601String(),
    'updated_at':      updatedAt.toIso8601String(),
  };

  /// SQLite flat map — polygon stored as JSON string
  Map<String, dynamic> toMap() => {
    'id':              id,
    'destination_id':  destinationId,
    'authority_id':    authorityId,
    'name':            name,
    'type':            type.toApiString(),
    'shape':           shape.toApiString(),
    'center_lat':      centerLat,
    'center_lng':      centerLng,
    'radius_m':        radiusM,
    'polygon_json':    json.encode(polygonPoints.map((p) => p.toJson()).toList()),
    'is_active':       isActive ? 1 : 0,
    'created_at':      createdAt.toIso8601String(),
    'updated_at':      updatedAt.toIso8601String(),
  };

  factory ZoneModel.fromMap(Map<String, dynamic> m) =>
      ZoneModel.fromJson({
        ...m,
        'polygon_points': m['polygon_json'],
        'is_active':      m['is_active'],
      });
}
