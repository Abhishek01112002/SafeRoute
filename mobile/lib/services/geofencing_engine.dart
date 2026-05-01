// lib/services/geofencing_engine.dart
// Dynamic geofencing — zones are always synced from the backend and cached in
// local SQLite. No coordinates are ever hardcoded here.
//
// Zone priority (highest wins): RESTRICTED > CAUTION > SAFE > UNKNOWN

import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:saferoute/models/zone_model.dart';
import 'package:saferoute/services/api_service.dart';
import 'package:saferoute/services/database_service.dart';

class GeofencingEngine {
  List<ZoneModel> _zones = [];
  String? _loadedDestinationId;
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;
  String? get loadedDestinationId => _loadedDestinationId;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Load zones for a destination.
  /// Priority: API (live) → local SQLite cache → operate in UNKNOWN mode.
  Future<void> loadForDestination(String destinationId) async {
    if (_loadedDestinationId == destinationId && _isLoaded) return;

    final api = ApiService();
    final db  = DatabaseService();

    // 1. Try API first
    try {
      final zones = await api.getZonesForDestination(destinationId);
      if (zones.isNotEmpty) {
        _zones = zones;
        _loadedDestinationId = destinationId;
        _isLoaded = true;
        await db.saveZones(destinationId, zones);
        debugPrint('🗺️ GeofencingEngine: ${zones.length} zones loaded from API for $destinationId');
        return;
      }
    } catch (e) {
      debugPrint('⚠️ GeofencingEngine: API failed: $e — trying cache');
    }

    // 2. Fall back to local cache
    final cached = await db.getZonesForDestination(destinationId);
    if (cached.isNotEmpty) {
      _zones = cached;
      _loadedDestinationId = destinationId;
      _isLoaded = true;
      debugPrint('💾 GeofencingEngine: ${cached.length} zones loaded from cache for $destinationId');
      return;
    }

    // 3. No data — operate in unknown mode (never falsely label anything SAFE)
    _zones = [];
    _loadedDestinationId = destinationId;
    _isLoaded = true;
    debugPrint('❓ GeofencingEngine: No zone data for $destinationId — UNKNOWN mode');
  }

  /// Evaluate zone type for a GPS point.
  /// Returns the highest-priority matching zone type.
  ZoneType getZoneType(LatLng point) {
    if (!_isLoaded || _zones.isEmpty) return ZoneType.unknown;

    // Priority: RESTRICTED(3) > CAUTION(2) > SAFE(1)
    const priority = {ZoneType.restricted: 3, ZoneType.caution: 2, ZoneType.safe: 1};
    ZoneType result = ZoneType.unknown;
    int best = 0;

    for (final zone in _zones) {
      if (!zone.isActive) continue;
      if (_pointInZone(point, zone)) {
        final p = priority[zone.type] ?? 0;
        if (p > best) {
          best = p;
          result = zone.type;
        }
      }
    }

    return result;
  }

  /// Return the matching ZoneModel (for UI detail — name, type).
  ZoneModel? getZoneModel(LatLng point) {
    if (!_isLoaded || _zones.isEmpty) return null;
    const priority = {ZoneType.restricted: 3, ZoneType.caution: 2, ZoneType.safe: 1};
    ZoneModel? best;
    int bestP = -1;
    for (final zone in _zones) {
      if (!zone.isActive) continue;
      if (_pointInZone(point, zone)) {
        final p = priority[zone.type] ?? 0;
        if (p > bestP) { bestP = p; best = zone; }
      }
    }
    return best;
  }

  /// Inject zones directly (e.g. from sync_service after a bulk sync).
  void setZones(List<ZoneModel> zones, String destinationId) {
    _zones = zones;
    _loadedDestinationId = destinationId;
    _isLoaded = true;
    debugPrint('🛰️ GeofencingEngine: ${zones.length} zones injected for $destinationId');
  }

  // ── Internal geometry ──────────────────────────────────────────────────────

  bool _pointInZone(LatLng point, ZoneModel zone) {
    return zone.shape == ZoneShape.circle
        ? _pointInCircle(point, zone)
        : _pointInPolygon(point, zone.polygonPoints);
  }

  bool _pointInCircle(LatLng point, ZoneModel zone) {
    if (zone.centerLat == null || zone.centerLng == null || zone.radiusM == null) {
      return false;
    }
    final dist = _haversineM(
      point.latitude, point.longitude,
      zone.centerLat!, zone.centerLng!,
    );
    return dist <= zone.radiusM!;
  }

  bool _pointInPolygon(LatLng point, List<ZonePoint> polygon) {
    if (polygon.length < 3) return false;
    bool inside = false;
    int j = polygon.length - 1;
    for (int i = 0; i < polygon.length; i++) {
      final xi = polygon[i].lng;
      final yi = polygon[i].lat;
      final xj = polygon[j].lng;
      final yj = polygon[j].lat;
      if ((yi > point.latitude) != (yj > point.latitude) &&
          point.longitude < (xj - xi) * (point.latitude - yi) / (yj - yi) + xi) {
        inside = !inside;
      }
      j = i;
    }
    return inside;
  }

  double _haversineM(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) * math.cos(_rad(lat2)) *
            math.sin(dLng / 2) * math.sin(dLng / 2);
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _rad(double deg) => deg * math.pi / 180;
}
