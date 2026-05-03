// lib/services/sync_service.dart
// DEPRECATED: This file is maintained for backward compatibility.
// All sync operations are now delegated to SyncEngine.
//
// Migration: Replace calls to SyncService() with SyncEngine()
// The SyncEngine provides: priority queue, persistent state,
// conflict resolution, observability, and production-grade retry logic.

import 'package:flutter/foundation.dart';
import 'package:saferoute/services/sync_engine.dart';

/// Legacy SyncService - delegates all operations to SyncEngine
///
/// NOTE: This class is deprecated. Use SyncEngine directly for new code.
/// Example migration:
///   // OLD
///   await SyncService().syncAll(touristId: id, destinationIds: dests);
///
///   // NEW
///   await SyncEngine().fullSync(touristId: id, destinationIds: dests);
@deprecated
class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final SyncEngine _engine = SyncEngine();

  /// Full sync - delegates to SyncEngine
  Future<void> syncAll({
    required String touristId,
    required List<String> destinationIds,
  }) async {
    debugPrint('⚠️ SyncService is deprecated. Use SyncEngine.fullSync() instead.');
    return _engine.fullSync(
      touristId: touristId,
      destinationIds: destinationIds,
    );
  }

  /// Offline data sync - delegates to SyncEngine
  Future<void> syncOfflineData({String? touristId}) async {
    debugPrint('⚠️ SyncService is deprecated. Use SyncEngine.processQueue() instead.');
    return _engine.processQueue();
  }
}
