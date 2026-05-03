// lib/services/geofencing_engine.dart
// Dynamic geofencing — zones are always synced from the backend and cached in
// local SQLite. No coordinates are ever hardcoded here in the final version.
//
// ── DEFAULT-SAFE ARCHITECTURE ─────────────────────────────────────────────────
// When zones are loaded and no match is found → ZoneType.safe (implicit default)
// When zones are NOT loaded → ZoneType.syncing (prevents false SECURE on cold start)
//
// Only CAUTION and RESTRICTED zones are evaluated.
// Zone priority (highest wins): RESTRICTED > CAUTION > (implicit SAFE)

import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:saferoute/core/models/zone_model.dart';
import 'package:saferoute/services/api_service.dart';
import 'package:saferoute/services/database_service.dart';
import 'package:saferoute/core/service_locator.dart';

class GeofencingEngine {
  List<ZoneModel> _zones = [];
  String? _loadedDestinationId;
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;
  String? get loadedDestinationId => _loadedDestinationId;

  /// Returns only the active danger zones (caution + restricted).
  List<ZoneModel> get activeDangerZones =>
      _zones.where((z) => z.isActive && z.type.isDanger).toList();

  GeofencingEngine();

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Load zones for a destination.
  /// Priority: API (live) → local SQLite cache → operate in SAFE mode.
  Future<void> loadForDestination(String destinationId) async {
    if (_loadedDestinationId == destinationId && _isLoaded) return;

    final api = locator<ApiService>();
    final db  = locator<DatabaseService>();

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

    // 3. No data — everything is safe by default (no danger zones to worry about)
    _zones = [];
    _loadedDestinationId = destinationId;
    _isLoaded = true;
    debugPrint('✅ GeofencingEngine: No danger zones for $destinationId — default SAFE mode');
  }

  /// Evaluate zone type for a GPS point.
  /// Returns the highest-priority matching zone type.
  ///
  /// DEFAULT-SAFE: Returns [ZoneType.safe] when no danger zone matches.
  /// Returns [ZoneType.syncing] when zone data hasn't loaded yet.
  ZoneType getZoneType(LatLng point) {
    // Race condition guard: zones not loaded yet → syncing state
    if (!_isLoaded) return ZoneType.syncing;

    // No zones loaded → everything is safe (no danger zones exist for this area)
    if (_zones.isEmpty) return ZoneType.safe;

    // Priority: RESTRICTED(2) > CAUTION(1) — only danger zones matter
    const priorityMap = {ZoneType.restricted: 2, ZoneType.caution: 1};
    ZoneType result = ZoneType.safe; // Default: safe until proven dangerous
    int best = 0;

    for (final zone in _zones) {
      if (!zone.isActive) continue;
      // Skip safe zones from backend — they're redundant in default-safe model
      if (zone.type == ZoneType.safe) continue;
      if (_pointInZone(point, zone)) {
        final p = priorityMap[zone.type] ?? 0;
        if (p > best) {
          best = p;
          result = zone.type;
        }
      }
    }

    return result;
  }

  /// Alias for compatibility with older code
  ZoneType getZone(LatLng point) => getZoneType(point);

  /// Check if a specific point is inside any active danger zone.
  /// Used by backtrack boundary detection.
  bool isPointInDangerZone(LatLng point) {
    if (!_isLoaded || _zones.isEmpty) return false;
    for (final zone in _zones) {
      if (!zone.isActive) continue;
      if (zone.type == ZoneType.safe) continue;
      if (_pointInZone(point, zone)) return true;
    }
    return false;
  }

  /// Return the matching ZoneModel (for UI detail — name, type).
  ZoneModel? getZoneModel(LatLng point) {
    if (!_isLoaded || _zones.isEmpty) return null;
    const priorityMap = {ZoneType.restricted: 2, ZoneType.caution: 1};
    ZoneModel? best;
    int bestP = -1;
    for (final zone in _zones) {
      if (!zone.isActive) continue;
      if (zone.type == ZoneType.safe) continue;
      if (_pointInZone(point, zone)) {
        final p = priorityMap[zone.type] ?? 0;
        if (p > bestP) { bestP = p; best = zone; }
      }
    }
    return best;
  }

  /// Inject zones directly (e.g. from sync_service after a bulk sync).
  void setZones(List<ZoneModel> zones, [String? destinationId]) {
    _zones = zones;
    _loadedDestinationId = destinationId ?? _loadedDestinationId;
    _isLoaded = true;
    debugPrint('🛰️ GeofencingEngine: ${zones.length} zones injected for $destinationId');
  }

  /// Compatibility method for legacy dynamic zones injection
  void setDynamicZones(List<Map<String, dynamic>> legacyZones) {
    _zones = legacyZones.map((z) => ZoneModel.fromMap({
      'id': z['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      'destination_id': 'legacy',
      'name': z['name'] ?? 'Legacy Zone',
      'type': z['type']?.toString().toUpperCase() ?? 'CAUTION',
      'shape': z['points'] != null ? 'POLYGON' : 'CIRCLE',
      'center_lat': z['lat'] ?? z['center']?['lat'],
      'center_lng': z['lng'] ?? z['center']?['lng'],
      'radius_m': z['radius']?.toDouble() ?? 500.0,
      'polygon_json': z['points'] != null ? jsonEncode(z['points']) : '[]',
      'is_active': 1,
    })).toList();
    _isLoaded = true;
  }

  /// Mark engine as loaded (used when no destination is selected but we
  /// want to transition from syncing → safe).
  void markLoaded() {
    _isLoaded = true;
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
