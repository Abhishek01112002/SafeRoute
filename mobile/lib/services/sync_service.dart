// lib/services/sync_service.dart
// Runs after login and when connectivity is restored.
// Syncs: location pings, SOS events, zones (per destination), trail graphs.

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:saferoute/services/api_service.dart';
import 'package:saferoute/services/database_service.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final ApiService _api = ApiService();
  final DatabaseService _db = DatabaseService();

  bool _isSyncing = false;
  static const int maxRetries = 3;
  static const Duration baseBackoff = Duration(seconds: 2);

  // ── Full sync — call on login and on connectivity restore ─────────────────

  Future<void> syncAll({
    required String touristId,
    required List<String> destinationIds,
  }) async {
    if (_isSyncing) return;
    _isSyncing = true;
    debugPrint('🔄 SyncService: Starting full sync...');

    try {
      // Run critical syncs first
      await _syncLocationPings();
      await _syncSosEvents(touristId);
      
      // Then background downloads
      await _syncZones(destinationIds);
      await _syncTrailGraphs(destinationIds);
      
    } catch (e) {
      debugPrint('❌ SyncService error: $e');
    } finally {
      _isSyncing = false;
      debugPrint('✅ SyncService: Full sync cycle complete.');
    }
  }

  // ── Lightweight offline-data-only sync (no zone/graph download) ───────────
  // Use this on periodic background ticks when full sync isn't needed.

  Future<void> syncOfflineData({String? touristId}) async {
    if (_isSyncing) return;
    _isSyncing = true;
    debugPrint("🔄 SyncService: Starting offline data synchronization...");
    
    try {
      await _syncLocationPings();
      await _syncSosEvents(touristId);
      debugPrint("✅ SyncService: Offline sync cycle completed successfully.");
    } catch (e) {
      debugPrint("❌ SyncService Error: $e");
    } finally {
      _isSyncing = false;
    }
  }

  // ── Upload queued location pings with exponential backoff ──────────────────

  Future<void> _syncLocationPings() async {
    final unsyncedPings = await _db.getUnsyncedPings();
    if (unsyncedPings.isEmpty) return;

    debugPrint("🔄 Syncing ${unsyncedPings.length} location pings...");
    int syncedCount = 0;
    int failedCount = 0;

    for (var ping in unsyncedPings) {
      bool success = false;
      
      for (int attempt = 0; attempt < maxRetries; attempt++) {
        try {
          success = await _api.sendLocationPing(ping);
          if (success && ping.id != null) {
            await _db.markPingSynced(ping.id!);
            syncedCount++;
            break;
          }
        } on RateLimitException catch (e) {
          debugPrint("⏳ Rate limited on ping sync (attempt ${attempt + 1}). Retry-After: ${e.retryAfter}");
          if (attempt < maxRetries - 1) {
            await Future.delayed(_calculateBackoff(attempt));
          }
        } catch (e) {
          debugPrint("❌ Error syncing ping (attempt ${attempt + 1}): $e");
          if (attempt < maxRetries - 1) {
            await Future.delayed(_calculateBackoff(attempt));
          }
        }
      }
      
      if (!success) failedCount++;
    }

    debugPrint("✅ Location Pings: $syncedCount/${unsyncedPings.length} synced ($failedCount pending).");
  }

  // ── Upload queued SOS events (PRIORITY) ──────────────────────────────────

  Future<void> _syncSosEvents(String? touristId) async {
    final unsyncedSos = await _db.getUnsyncedSosEvents();
    if (unsyncedSos.isEmpty) return;

    debugPrint("🔄 Syncing ${unsyncedSos.length} SOS events (PRIORITY)...");
    int syncedCount = 0;
    int failedCount = 0;

    for (var sos in unsyncedSos) {
      bool success = false;
      
      // SOS events get more aggressive retry - max 5 attempts
      for (int attempt = 0; attempt < 5; attempt++) {
        try {
          success = await _api.sendSosAlert(
            sos['latitude'], 
            sos['longitude'], 
            sos['triggerType'],
            touristId: touristId ?? sos['touristId'],
          );
          
          if (success && sos['id'] != null) {
            await _db.markSosSynced(sos['id']);
            syncedCount++;
            debugPrint("✅ SOS Event ${sos['id']} synced successfully!");
            break;
          }
        } on RateLimitException catch (e) {
          debugPrint("⏳ Rate limited on SOS sync (attempt ${attempt + 1}). Retry-After: ${e.retryAfter}");
          if (attempt < 4) {
            await Future.delayed(_calculateBackoff(attempt));
          }
        } on AuthCorruptionException catch (e) {
          debugPrint("🛑 Auth failed on SOS sync: $e. Aborting sync.");
          return; 
        } catch (e) {
          debugPrint("⚠️ Error syncing SOS (attempt ${attempt + 1}): $e");
          if (attempt < 4) {
            await Future.delayed(_calculateBackoff(attempt));
          }
        }
      }
      
      if (!success) failedCount++;
    }

    debugPrint("✅ SOS Events: $syncedCount/${unsyncedSos.length} synced ($failedCount pending).");
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
        if (graph != null) {
          await _db.saveTrailGraph(graph);
          debugPrint('🧭 Trail graph synced for $destId: ${graph.nodes.length} nodes');
        }
      } catch (e) {
        debugPrint('⚠️ Trail graph sync failed for $destId: $e');
      }
    }
  }

  /// Calculate exponential backoff with jitter
  Duration _calculateBackoff(int attemptNumber) {
    final exponentialSeconds = baseBackoff.inSeconds * pow(2, attemptNumber);
    final jitterFactor = 0.8 + (Random().nextDouble() * 0.4); 
    final totalSeconds = (exponentialSeconds * jitterFactor).toInt();
    final capped = min(totalSeconds, 30); 
    return Duration(seconds: capped);
  }
}
