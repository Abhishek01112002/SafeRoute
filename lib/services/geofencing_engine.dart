import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:saferoute/models/location_ping_model.dart';
import 'package:saferoute/services/api_service.dart';
import 'dart:math' as math;

class GeofencingEngine {
  List<LatLng> _greenOuterZone = [];
  List<LatLng> _greenInnerZone = [];
  List<LatLng> _yellowZone = [];
  List<LatLng> _redZone = [];
  List<Map<String, dynamic>> _dynamicZones = [];

  GeofencingEngine() {
    // Load defaults if empty
    _loadStaticDefaults();
  }

  void _loadStaticDefaults() {
    _greenOuterZone = const [
      LatLng(30.3369583, 77.8696472),
      LatLng(30.3367083, 77.8702083),
      LatLng(30.3364306, 77.8709528),
      LatLng(30.3356667, 77.8710083),
      LatLng(30.3345111, 77.8709083),
      LatLng(30.3350556, 77.8692028),
      LatLng(30.3355472, 77.8684444),
      LatLng(30.3361194, 77.8689889),
      LatLng(30.3365111, 77.8685583),
      LatLng(30.3364694, 77.8688333),
      LatLng(30.3362750, 77.8690833),
      LatLng(30.3366222, 77.8693694),
      LatLng(30.3369583, 77.8696472),
    ];
    _greenInnerZone = const [
      LatLng(30.3374333, 77.8687000),
      LatLng(30.3373222, 77.8689667),
      LatLng(30.3371500, 77.8692639),
      LatLng(30.3370833, 77.8684083),
      LatLng(30.3367222, 77.8681639),
      LatLng(30.3374333, 77.8687000),
    ];
    _yellowZone = const [
      LatLng(30.3371500, 77.8692639),
      LatLng(30.3369583, 77.8696472),
      LatLng(30.3366222, 77.8693694),
      LatLng(30.3362750, 77.8690833),
      LatLng(30.3364694, 77.8688333),
      LatLng(30.3365111, 77.8685583),
      LatLng(30.3371500, 77.8692639),
    ];
    _redZone = const [
      LatLng(30.3367222, 77.8681639),
      LatLng(30.3365111, 77.8685583),
      LatLng(30.3361194, 77.8689889),
      LatLng(30.3355472, 77.8684444),
      LatLng(30.3358361, 77.8679139),
      LatLng(30.3363389, 77.8678833),
      LatLng(30.3367222, 77.8681639),
    ];
  }

  Future<void> loadZonesFromApi(ApiService api) async {
    try {
      final zones = await api.getActiveTouristZones();
      _dynamicZones = zones.cast<Map<String, dynamic>>();
      debugPrint(
          "GeofencingEngine: ${_dynamicZones.length} dynamic zones loaded from API.");
    } catch (e) {
      debugPrint("⚠️ GeofencingEngine: API loading failed: $e");
    }
  }

  ZoneType getZone(LatLng point) {
    // 1. Check Dynamic Zones (Circles) first
    for (var zone in _dynamicZones) {
      final center = LatLng(zone['lat'], zone['lng']);
      final radius = zone['radius'] as num;

      final distance = _calculateDistance(point, center);
      if (distance <= radius) {
        return _parseZoneType(zone['type']?.toString());
      }
    }

    // 2. Fallback to Static Polygons
    if (_isInsidePolygon(point, _redZone)) return ZoneType.red;
    if (_isInsidePolygon(point, _yellowZone)) return ZoneType.yellow;
    if (_isInsidePolygon(point, _greenInnerZone)) return ZoneType.greenInner;
    if (_isInsidePolygon(point, _greenOuterZone)) return ZoneType.greenOuter;

    return ZoneType.none;
  }

  double _calculateDistance(LatLng p1, LatLng p2) {
    const double r = 6371e3; // Earth radius in meters
    final phi1 = p1.latitude * math.pi / 180;
    final phi2 = p2.latitude * math.pi / 180;
    final deltaPhi = (p2.latitude - p1.latitude) * math.pi / 180;
    final deltaLambda = (p2.longitude - p1.longitude) * math.pi / 180;

    final a = math.sin(deltaPhi / 2) * math.sin(deltaPhi / 2) +
        math.cos(phi1) *
            math.cos(phi2) *
            math.sin(deltaLambda / 2) *
            math.sin(deltaLambda / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return r * c;
  }

  bool _isInsidePolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.isEmpty) return false;
    int i, j = polygon.length - 1;
    bool inside = false;
    for (i = 0; i < polygon.length; i++) {
      if ((polygon[i].longitude > point.longitude) !=
              (polygon[j].longitude > point.longitude) &&
          (point.latitude <
              (polygon[j].latitude - polygon[i].latitude) *
                      (point.longitude - polygon[i].longitude) /
                      (polygon[j].longitude - polygon[i].longitude) +
                  polygon[i].latitude)) {
        inside = !inside;
      }
      j = i;
    }
    return inside;
  }

  // Method to allow dynamic injection from cached database (Issue #14)
  void setDynamicZones(List<Map<String, dynamic>> zones) {
    _dynamicZones = zones;
    debugPrint(
        "GeofencingEngine: Updated dynamic zones (${_dynamicZones.length})");
  }

  ZoneType _parseZoneType(String? type) {
    switch (type?.toUpperCase()) {
      case 'RED':
        return ZoneType.red;
      case 'YELLOW':
        return ZoneType.yellow;
      case 'GREEN':
        return ZoneType.greenInner;
      default:
        return ZoneType.greenOuter;
    }
  }
}
