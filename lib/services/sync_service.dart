// lib/services/sync_service.dart
// Runs after login and when connectivity is restored.
// Syncs: location pings, SOS events, zones (per destination), trail graphs.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:saferoute/services/api_service.dart';
import 'package:saferoute/services/database_service.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final ApiService      _api = ApiService();
  final DatabaseService _db  = DatabaseService();

  bool _isSyncing = false;

  // ── Full sync — call on login and on connectivity restore ─────────────────

  Future<void> syncAll({
    required String touristId,
    required List<String> destinationIds,
  }) async {
    if (_isSyncing) return;
    _isSyncing = true;
    debugPrint('🔄 SyncService: Starting full sync...');

    try {
      await Future.wait([
        _syncOfflinePings(),
        _syncOfflineSos(touristId),
        _syncZones(destinationIds),
        _syncTrailGraphs(destinationIds),
      ]);
    } catch (e) {
      debugPrint('❌ SyncService error: $e');
    } finally {
      _isSyncing = false;
      debugPrint('✅ SyncService: Sync complete.');
    }
  }

  // ── Upload queued location pings ──────────────────────────────────────────

  Future<void> _syncOfflinePings() async {
    final pings = await _db.getUnsyncedPings();
    if (pings.isEmpty) return;
    debugPrint('🔄 Uploading ${pings.length} queued pings...');
    int count = 0;
    for (final ping in pings) {
      final ok = await _api.sendLocationPing(ping);
      if (ok && ping.id != null) {
        await _db.markPingSynced(ping.id!);
        count++;
      }
    }
    debugPrint('✅ Pings synced: $count/${pings.length}');
  }

  // ── Upload queued SOS events ──────────────────────────────────────────────

  Future<void> _syncOfflineSos(String touristId) async {
    final events = await _db.getUnsyncedSosEvents();
    if (events.isEmpty) return;
    debugPrint('🔄 Uploading ${events.length} queued SOS events...');
    int count = 0;
    for (final sos in events) {
      final ok = await _api.sendSosAlert(
        sos['latitude'] as double,
        sos['longitude'] as double,
        sos['triggerType'] as String,
        touristId: touristId,
      );
      if (ok && sos['id'] != null) {
        await _db.markSosSynced(sos['id'] as int);
        count++;
      }
    }
    debugPrint('✅ SOS events synced: $count/${events.length}');
  }

  // ── Download & cache zones for all tourist destinations ───────────────────

  Future<void> _syncZones(List<String> destinationIds) async {
    for (final destId in destinationIds) {
      try {
        final zones = await _api.getZonesForDestination(destId);
        if (zones.isNotEmpty) {
          await _db.saveZones(destId, zones);
          debugPrint('🗺️ Zones synced for $destId: ${zones.length}');
        }
      } catch (e) {
        debugPrint('⚠️ Zone sync failed for $destId: $e');
      }
    }
  }

  // ── Download & cache trail graphs for all tourist destinations ────────────

  Future<void> _syncTrailGraphs(List<String> destinationIds) async {
    for (final destId in destinationIds) {
      try {
        final graph = await _api.getTrailGraph(destId);
        if (graph != null && !graph.isEmpty) {
          await _db.saveTrailGraph(graph);
          debugPrint('🧭 Trail graph synced for $destId: ${graph.nodes.length} nodes');
        }
      } catch (e) {
        debugPrint('⚠️ Trail graph sync failed for $destId: $e');
      }
    }
  }

  // ── Lightweight offline-data-only sync (no zone/graph download) ───────────
  // Use this on periodic background ticks when full sync isn't needed.

  Future<void> syncOfflineData({required String touristId}) async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      await Future.wait([
        _syncOfflinePings(),
        _syncOfflineSos(touristId),
      ]);
    } catch (e) {
      debugPrint('❌ SyncService offline error: $e');
    } finally {
      _isSyncing = false;
    }
  }
}
