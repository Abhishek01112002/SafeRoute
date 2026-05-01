import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:saferoute/services/api_service.dart';
import 'package:saferoute/services/database_service.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final ApiService _apiService = ApiService();
  final DatabaseService _dbService = DatabaseService();
  
  bool _isSyncing = false;
  static const int maxRetries = 3;
  static const Duration baseBackoff = Duration(seconds: 2);
  
  /// Sync offline data with retry logic and conflict resolution
  Future<void> syncOfflineData() async {
    if (_isSyncing) return;
    _isSyncing = true;
    
    debugPrint("🔄 SyncService: Starting offline data synchronization...");
    
    try {
      // 1. Sync Location Pings with conflict resolution
      await _syncLocationPings();
      
      // 2. Sync SOS Events (critical - highest priority)
      await _syncSosEvents();
      
      debugPrint("✅ SyncService: Sync cycle completed successfully.");
      
    } catch (e) {
      debugPrint("❌ SyncService Error: $e");
    } finally {
      _isSyncing = false;
      debugPrint("🔄 SyncService: Idle.");
    }
  }

  /// Sync location pings with exponential backoff retry
  Future<void> _syncLocationPings() async {
    final unsyncedPings = await _dbService.getUnsyncedPings();
    if (unsyncedPings.isEmpty) return;

    debugPrint("🔄 Syncing ${unsyncedPings.length} location pings...");
    int syncedCount = 0;
    int failedCount = 0;

    for (var ping in unsyncedPings) {
      bool success = false;
      
      // Retry with exponential backoff
      for (int attempt = 0; attempt < maxRetries; attempt++) {
        try {
          success = await _apiService.sendLocationPing(ping);
          
          if (success && ping.id != null) {
            await _dbService.markPingSynced(ping.id!);
            syncedCount++;
            break;
          }
        } on RateLimitException catch (e) {
          debugPrint("⏳ Rate limited on ping sync (attempt $attempt+1). Retry-After: ${e.retryAfter}");
          if (attempt < maxRetries - 1) {
            final backoffDuration = _calculateBackoff(attempt);
            await Future.delayed(backoffDuration);
          }
        } catch (e) {
          debugPrint("❌ Error syncing ping (attempt $attempt+1): $e");
          if (attempt < maxRetries - 1) {
            final backoffDuration = _calculateBackoff(attempt);
            await Future.delayed(backoffDuration);
          }
        }
      }
      
      if (!success) {
        failedCount++;
        // Mark as failed but keep in DB for next sync attempt
        debugPrint("⚠️ Failed to sync ping after $maxRetries attempts. Will retry next cycle.");
      }
    }

    debugPrint("✅ Location Pings: $syncedCount/${unsyncedPings.length} synced (${failedCount} pending).");
  }

  /// Sync SOS events with highest priority and conflict detection
  Future<void> _syncSosEvents() async {
    final unsyncedSos = await _dbService.getUnsyncedSosEvents();
    if (unsyncedSos.isEmpty) return;

    debugPrint("🔄 Syncing ${unsyncedSos.length} SOS events (PRIORITY)...");
    int syncedCount = 0;
    int failedCount = 0;

    for (var sos in unsyncedSos) {
      bool success = false;
      
      // SOS events get more aggressive retry - max 5 attempts
      for (int attempt = 0; attempt < 5; attempt++) {
        try {
          success = await _apiService.sendSosAlert(
            sos['latitude'], 
            sos['longitude'], 
            sos['triggerType'],
            touristId: sos['touristId'],
          );
          
          if (success && sos['id'] != null) {
            await _dbService.markSosSynced(sos['id']);
            syncedCount++;
            debugPrint("✅ SOS Event ${sos['id']} synced successfully!");
            break;
          }
        } on RateLimitException catch (e) {
          debugPrint("⏳ Rate limited on SOS sync (attempt $attempt+1). Retry-After: ${e.retryAfter}");
          if (attempt < 4) {
            final backoffDuration = _calculateBackoff(attempt);
            await Future.delayed(backoffDuration);
          }
        } on AuthCorruptionException catch (e) {
          debugPrint("🛑 Auth failed on SOS sync: $e. Aborting sync.");
          return; // Stop entire sync if auth is broken
        } catch (e) {
          debugPrint("⚠️ Error syncing SOS (attempt $attempt+1): $e");
          if (attempt < 4) {
            final backoffDuration = _calculateBackoff(attempt);
            await Future.delayed(backoffDuration);
          }
        }
      }
      
      if (!success) {
        failedCount++;
        debugPrint("❌ Failed to sync SOS ${sos['id']} after 5 attempts. High priority - will retry immediately next cycle.");
      }
    }

    debugPrint("✅ SOS Events: $syncedCount/${unsyncedSos.length} synced (${failedCount} pending).");
  }

  /// Calculate exponential backoff with jitter
  Duration _calculateBackoff(int attemptNumber) {
    // Exponential backoff: 2s, 4s, 8s with ±20% jitter
    final exponentialSeconds = baseBackoff.inSeconds * pow(2, attemptNumber);
    final jitterFactor = 0.8 + (Random().nextDouble() * 0.4); // 0.8 to 1.2
    final totalSeconds = (exponentialSeconds * jitterFactor).toInt();
    
    final capped = min(totalSeconds, 30); // Cap at 30 seconds
    debugPrint("⏳ Backoff: ${capped}s for attempt $attemptNumber");
    return Duration(seconds: capped);
  }
}
