import 'dart:async';
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
  
  Future<void> syncOfflineData() async {
    if (_isSyncing) return;
    _isSyncing = true;
    
    debugPrint("🔄 SyncService: Starting offline data synchronization...");
    
    try {
      // 1. Sync Location Pings
      final unsyncedPings = await _dbService.getUnsyncedPings();
      if (unsyncedPings.isNotEmpty) {
        debugPrint("🔄 Syncing ${unsyncedPings.length} location pings...");
        int syncedCount = 0;
        for (var ping in unsyncedPings) {
          bool success = await _apiService.sendLocationPing(ping);
          if (success && ping.id != null) {
            await _dbService.markPingSynced(ping.id!);
            syncedCount++;
          }
        }
        debugPrint("✅ Synced $syncedCount/${unsyncedPings.length} pings.");
      }

      // 2. Sync SOS Events
      final unsyncedSos = await _dbService.getUnsyncedSosEvents();
      if (unsyncedSos.isNotEmpty) {
        debugPrint("🔄 Syncing ${unsyncedSos.length} SOS events...");
        int syncedSosCount = 0;
        for (var sos in unsyncedSos) {
          bool success = await _apiService.sendSosAlert(
            sos['latitude'], 
            sos['longitude'], 
            sos['triggerType'],
            touristId: sos['touristId'],
          );
          if (success && sos['id'] != null) {
            await _dbService.markSosSynced(sos['id']);
            syncedSosCount++;
          }
        }
        debugPrint("✅ Synced $syncedSosCount/${unsyncedSos.length} SOS events.");
      }
      
    } catch (e) {
      debugPrint("❌ SyncService Error: $e");
    } finally {
      _isSyncing = false;
      debugPrint("🔄 SyncService: Idle.");
    }
  }
}
