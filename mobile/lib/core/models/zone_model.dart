// lib/models/zone_model.dart
// Canonical zone schema — matches backend DB and local SQLite exactly.
// Zones are always owned by the backend; the app only reads and caches them.
//
// ── DEFAULT-SAFE ARCHITECTURE ─────────────────────────────────────────────────
// Every location is SAFE by default. Authorities only define CAUTION and
// RESTRICTED zones. The app never requires explicit "safe zone" geometry.
// `safe` is the implicit default — NOT a backend-defined zone.
// `syncing` is a transient UI-only state shown while zone data is loading.

import 'dart:convert';

/// Zone classification for any GPS point.
///
/// Priority hierarchy: RESTRICTED > CAUTION > (implicit SAFE)
///
/// - [safe]: Default state. The user is not inside any danger zone.
///           This is the implicit fallback — not sent by the backend.
/// - [caution]: Authority-marked moderate-risk area (yellow zone).
/// - [restricted]: Authority-marked high-risk area (red zone).
/// - [syncing]: Transient state — zone data is still loading from
///              backend/cache. Prevents false "SECURE" during cold start.
enum ZoneType { safe, caution, restricted, syncing }

enum ZoneShape { circle, polygon }

extension ZoneTypeExtension on ZoneType {
  static ZoneType fromString(String s) {
    switch (s.toUpperCase()) {
      case 'SAFE':       return ZoneType.safe;
      case 'CAUTION':    return ZoneType.caution;
      case 'RESTRICTED': return ZoneType.restricted;
      case 'SYNCING':    return ZoneType.syncing;
      // Legacy / unknown values all collapse to safe (default-safe model)
      default:           return ZoneType.safe;
    }
  }

  String toApiString() {
    switch (this) {
      case ZoneType.safe:       return 'SAFE';
      case ZoneType.caution:    return 'CAUTION';
      case ZoneType.restricted: return 'RESTRICTED';
      case ZoneType.syncing:    return 'SYNCING';
    }
  }

  String get displayLabel {
    switch (this) {
      case ZoneType.safe:       return 'Secure';
      case ZoneType.caution:    return 'Caution Zone';
      case ZoneType.restricted: return 'Restricted Zone';
      case ZoneType.syncing:    return 'Syncing...';
    }
  }

  /// Returns true if this zone type represents a danger state.
  bool get isDanger => this == ZoneType.caution || this == ZoneType.restricted;
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
