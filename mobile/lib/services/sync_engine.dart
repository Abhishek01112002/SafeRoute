// lib/services/sync_engine.dart
// Production-grade sync orchestration with priority queue, conflict resolution,
// persistent state machine, and observability.

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:saferoute/services/api_service.dart';
import 'package:saferoute/services/database_service.dart';
import 'package:saferoute/core/models/location_ping_model.dart';
import 'package:saferoute/core/service_locator.dart';
import 'package:uuid/uuid.dart';

/// Sync operation priority levels
enum SyncPriority { critical, high, normal, low }

/// Sync operation state machine
enum SyncState { pending, inProgress, completed, failed, retrying }

/// Sync operation types
enum SyncOperationType {
  sosEvent,
  locationPing,
  touristIdentity,
  zoneData,
  trailGraph,
}

/// Represents a single sync operation
class SyncOperation {
  final String id;
  final SyncOperationType type;
  final SyncPriority priority;
  final Map<String, dynamic> payload;
  SyncState state;
  int retryCount;
  DateTime? lastAttempt;
  DateTime? nextAttempt;
  String? errorMessage;
  final DateTime createdAt;

  SyncOperation({
    required this.id,
    required this.type,
    required this.priority,
    required this.payload,
    this.state = SyncState.pending,
    this.retryCount = 0,
    this.lastAttempt,
    this.nextAttempt,
    this.errorMessage,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type.name,
        'priority': priority.name,
        'payload': jsonEncode(payload),
        'state': state.name,
        'retry_count': retryCount,
        'last_attempt': lastAttempt?.millisecondsSinceEpoch,
        'next_attempt': nextAttempt?.millisecondsSinceEpoch,
        'error_message': errorMessage,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  static SyncOperation fromMap(Map<String, dynamic> map) {
    return SyncOperation(
      id: map['id'],
      type: SyncOperationType.values.byName(map['type']),
      priority: SyncPriority.values.byName(map['priority']),
      payload: jsonDecode(map['payload']),
      state: SyncState.values.byName(map['state']),
      retryCount: map['retry_count'],
      lastAttempt: map['last_attempt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_attempt'])
          : null,
      nextAttempt: map['next_attempt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['next_attempt'])
          : null,
      errorMessage: map['error_message'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']),
    );
  }
}

/// Sync progress event for UI observability
class SyncProgress {
  final int totalOperations;
  final int completedOperations;
  final int failedOperations;
  final SyncOperation? currentOperation;
  final bool isRunning;
  final DateTime? startTime;
  final Duration? elapsed;

  const SyncProgress({
    required this.totalOperations,
    required this.completedOperations,
    required this.failedOperations,
    this.currentOperation,
    required this.isRunning,
    this.startTime,
    this.elapsed,
  });

  double get progressPercent =>
      totalOperations > 0 ? completedOperations / totalOperations : 0.0;
}

/// Production-grade sync engine with priority queue and persistent state
class SyncEngine {
  static final SyncEngine _instance = SyncEngine._internal();
  factory SyncEngine() => _instance;
  SyncEngine._internal();

  final ApiService _api = locator<ApiService>();
  final DatabaseService _db = locator<DatabaseService>();

  // Internal state
  bool _isRunning = false;
  bool _isInitialized = false;
  final _progressController = StreamController<SyncProgress>.broadcast();
  Timer? _periodicTimer;

  // Configuration
  static const int _maxRetries = 3;
  static const int _maxSosRetries = 50;
  static const Duration _baseBackoff = Duration(seconds: 2);
  static const Duration _maxBackoff = Duration(minutes: 5);
  static const int _batchSize = 50;

  /// Observable sync progress stream
  Stream<SyncProgress> get progressStream => _progressController.stream;

  /// Initialize the sync engine database tables
  Future<void> initialize() async {
    if (_isInitialized) return;
    final db = await _db.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_queue (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        priority TEXT NOT NULL,
        payload TEXT NOT NULL,
        state TEXT NOT NULL DEFAULT 'pending',
        retry_count INTEGER DEFAULT 0,
        last_attempt INTEGER,
        next_attempt INTEGER,
        error_message TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    try {
      await db.execute('ALTER TABLE sync_queue ADD COLUMN next_attempt INTEGER');
    } catch (_) {
      // Existing databases already have this column after the first migration.
    }
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sync_state_priority ON sync_queue(state, priority, next_attempt, created_at)');
    _isInitialized = true;
    debugPrint('✅ SyncEngine: Initialized');
  }

  /// Enqueue a sync operation
  Future<void> enqueue(SyncOperation operation) async {
    await initialize();
    final db = await _db.database;
    await db.insert(
      'sync_queue',
      operation.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    debugPrint(
        '📥 SyncEngine: Enqueued ${operation.type.name} (${operation.priority.name})');
    await _notifyProgress();
  }

  /// Ensure a locally saved SOS has a durable sync queue row.
  Future<void> enqueueSosEvent({
    required int localId,
    required String touristId,
    required double? latitude,
    required double? longitude,
    required String triggerType,
    required String idempotencyKey,
    required int timestamp,
  }) async {
    await initialize();
    final db = await _db.database;
    final operationId = 'sos_$localId';
    final existing = await db.query(
      'sync_queue',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [operationId],
      limit: 1,
    );
    if (existing.isNotEmpty) return;

    await enqueue(SyncOperation(
      id: operationId,
      type: SyncOperationType.sosEvent,
      priority: SyncPriority.critical,
      payload: {
        'localId': localId,
        'latitude': latitude,
        'longitude': longitude,
        'triggerType': triggerType,
        'touristId': touristId,
        'idempotencyKey': idempotencyKey,
        'timestamp': timestamp,
      },
    ));
  }

  /// Mark a direct-send SOS queue row as completed so it is not replayed.
  Future<void> markSosOperationCompleted(int localId) async {
    await initialize();
    final db = await _db.database;
    final operationId = 'sos_$localId';
    final updated = await db.update(
      'sync_queue',
      {
        'state': SyncState.completed.name,
        'last_attempt': DateTime.now().millisecondsSinceEpoch,
        'error_message': null,
      },
      where: 'id = ?',
      whereArgs: [operationId],
    );
    if (updated == 0) return;
    await _notifyProgress();
  }

  /// Rebuild missing SOS sync rows from local SQLite before queue processing.
  Future<void> enqueuePendingSosEvents() async {
    await initialize();
    final events = await _db.getUnsyncedSosEvents();
    for (final event in events) {
      await _enqueueSosEventFromMap(event);
    }
  }

  /// Start periodic background sync
  void startPeriodicSync(Duration interval) {
    unawaited(initialize());
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(interval, (_) => processQueue());
    debugPrint('🔄 SyncEngine: Periodic sync started ($interval)');
  }

  /// Stop periodic sync
  void stopPeriodicSync() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
    debugPrint('⏹️ SyncEngine: Periodic sync stopped');
  }

  /// Process all pending operations in priority order
  Future<void> processQueue() async {
    await initialize();
    if (_isRunning) {
      debugPrint('⏳ SyncEngine: Already running, skipping');
      return;
    }
    _isRunning = true;
    final startTime = DateTime.now();

    try {
      await enqueuePendingSosEvents();
      final operations = await _getPendingOperations();
      if (operations.isEmpty) {
        debugPrint('✅ SyncEngine: No pending operations');
        return;
      }

      debugPrint('🔄 SyncEngine: Processing ${operations.length} operations');

      for (var i = 0; i < operations.length; i++) {
        final op = operations[i];
        await _notifyProgress(
          currentOperation: op,
          completedOperations: i,
          totalOperations: operations.length,
          startTime: startTime,
        );

        await _processOperation(op);
        await _notifyProgress(
          currentOperation: op,
          completedOperations: i + 1,
          totalOperations: operations.length,
          startTime: startTime,
        );
      }

      debugPrint('✅ SyncEngine: Queue processing complete');
    } catch (e, stack) {
      debugPrint('❌ SyncEngine: Queue processing error: $e\n$stack');
    } finally {
      _isRunning = false;
      await _notifyProgress(isRunning: false);
    }
  }

  /// Get all pending operations sorted by priority
  Future<List<SyncOperation>> _getPendingOperations() async {
    final db = await _db.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final staleInProgressCutoff =
        DateTime.now().subtract(_maxBackoff).millisecondsSinceEpoch;
    final maps = await db.query(
      'sync_queue',
      where: '''
        (state IN (?, ?) AND (next_attempt IS NULL OR next_attempt <= ?))
        OR (state = ? AND (last_attempt IS NULL OR last_attempt <= ?))
      ''',
      whereArgs: [
        'pending',
        'retrying',
        now,
        'inProgress',
        staleInProgressCutoff,
      ],
      orderBy:
          "CASE priority WHEN 'critical' THEN 0 WHEN 'high' THEN 1 WHEN 'normal' THEN 2 ELSE 3 END ASC, created_at ASC",
      limit: 100,
    );
    return maps.map(SyncOperation.fromMap).toList();
  }

  /// Process a single operation with retry logic
  Future<void> _processOperation(SyncOperation op) async {
    try {
      await _updateOperationState(op, SyncState.inProgress);

      final success = await _executeOperation(op);

      if (success) {
        await _updateOperationState(op, SyncState.completed);
        debugPrint('✅ SyncEngine: ${op.type.name} completed');
      } else {
        await _handleFailure(op, 'Operation returned false');
      }
    } on RateLimitException catch (e) {
      debugPrint('⏳ SyncEngine: Rate limited, will retry: $e');
      await _handleFailure(op, 'Rate limited', retryAfter: e.retryAfter);
    } on AuthCorruptionException catch (e) {
      debugPrint('🛑 SyncEngine: Auth corruption, aborting: $e');
      await _updateOperationState(op, SyncState.failed,
          error: 'Auth corruption');
    } catch (e) {
      debugPrint('❌ SyncEngine: ${op.type.name} failed: $e');
      await _handleFailure(op, e.toString());
    }
  }

  /// Execute the actual API call based on operation type
  Future<bool> _executeOperation(SyncOperation op) async {
    switch (op.type) {
      case SyncOperationType.sosEvent:
        final result = await _api.triggerSosAlert(
          (op.payload['latitude'] as num?)?.toDouble(),
          (op.payload['longitude'] as num?)?.toDouble(),
          op.payload['triggerType'],
          touristId: op.payload['touristId'],
          idempotencyKey: op.payload['idempotencyKey'],
          timestamp: op.payload['timestamp'] != null
              ? DateTime.fromMillisecondsSinceEpoch(op.payload['timestamp'])
              : null,
        );
        if (result.accepted && op.payload['localId'] != null) {
          await _db.markSosAccepted(
            op.payload['localId'],
            serverSosId: result.sosId,
            deliveryState: result.deliveryState,
          );
        }
        return result.accepted;

      case SyncOperationType.locationPing:
        final success =
            await _api.sendLocationPing(LocationPing.fromMap(op.payload));
        if (success && op.payload['id'] != null) {
          await _db.markPingSynced(op.payload['id']);
        }
        return success;

      case SyncOperationType.touristIdentity:
        await _api.registerTouristMultipart(
          fields: Map<String, String>.from(op.payload['fields']),
          photoPath: op.payload['photoPath'],
          docPath: op.payload['docPath'],
        );
        return true;

      case SyncOperationType.zoneData:
        final zones =
            await _api.getZonesForDestination(op.payload['destinationId']);
        if (zones.isNotEmpty) {
          await _db.saveZones(op.payload['destinationId'], zones);
        }
        return true;

      case SyncOperationType.trailGraph:
        final graph = await _api.getTrailGraph(op.payload['destinationId']);
        if (graph != null) {
          await _db.saveTrailGraph(graph);
        }
        return true;
    }
  }

  /// Handle operation failure with exponential backoff
  Future<void> _handleFailure(
    SyncOperation op,
    String error, {
    Duration? retryAfter,
  }) async {
    final maxRetries =
        op.type == SyncOperationType.sosEvent ? _maxSosRetries : _maxRetries;
    if (op.retryCount >= maxRetries) {
      await _updateOperationState(op, SyncState.failed, error: error);
      debugPrint('🔴 SyncEngine: ${op.type.name} max retries exceeded');
      return;
    }

    op.retryCount++;
    final backoff = retryAfter ?? _calculateBackoff(op.retryCount - 1);
    await _updateOperationState(
      op,
      SyncState.retrying,
      error: error,
      nextAttempt: DateTime.now().add(backoff),
    );
    debugPrint(
        '🔄 SyncEngine: ${op.type.name} retry ${op.retryCount}/$maxRetries');
  }

  /// Calculate exponential backoff with jitter
  Duration _calculateBackoff(int attemptNumber) {
    final exponentialSeconds = _baseBackoff.inSeconds * pow(2, attemptNumber);
    final jitterFactor = 0.8 + (Random().nextDouble() * 0.4);
    final totalSeconds = (exponentialSeconds * jitterFactor).toInt();
    final capped = min(totalSeconds, _maxBackoff.inSeconds);
    return Duration(seconds: capped);
  }

  /// Update operation state in database
  Future<void> _updateOperationState(
    SyncOperation op,
    SyncState state, {
    String? error,
    DateTime? nextAttempt,
  }) async {
    final db = await _db.database;
    op.state = state;
    op.lastAttempt = DateTime.now();
    op.nextAttempt =
        state == SyncState.retrying || state == SyncState.failed
            ? nextAttempt
            : null;
    if (error != null) op.errorMessage = error;

    await db.update(
      'sync_queue',
      op.toMap(),
      where: 'id = ?',
      whereArgs: [op.id],
    );
  }

  /// Clean up completed operations older than 7 days
  Future<void> cleanupOldOperations() async {
    await initialize();
    final db = await _db.database;
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    final deleted = await db.delete(
      'sync_queue',
      where: 'state = ? AND last_attempt < ?',
      whereArgs: ['completed', cutoff.millisecondsSinceEpoch],
    );
    if (deleted > 0) {
      debugPrint('🧹 SyncEngine: Cleaned up $deleted old operations');
    }
  }

  /// Retry all failed operations
  Future<void> retryFailed() async {
    await initialize();
    final db = await _db.database;
    await db.update(
      'sync_queue',
      {'state': 'pending', 'retry_count': 0},
      where: 'state = ?',
      whereArgs: ['failed'],
    );
    debugPrint('🔄 SyncEngine: Reset failed operations to pending');
    await processQueue();
  }

  /// Get current queue statistics
  Future<Map<String, int>> getStats() async {
    await initialize();
    final db = await _db.database;
    final result = await db.rawQuery('''
      SELECT state, COUNT(*) as count FROM sync_queue GROUP BY state
    ''');
    return {for (var r in result) r['state'] as String: r['count'] as int};
  }

  /// Notify progress listeners
  Future<void> _notifyProgress({
    SyncOperation? currentOperation,
    int completedOperations = 0,
    int totalOperations = 0,
    bool isRunning = true,
    DateTime? startTime,
  }) async {
    final stats = await getStats();
    final progress = SyncProgress(
      totalOperations: totalOperations,
      completedOperations: completedOperations,
      failedOperations: stats['failed'] ?? 0,
      currentOperation: currentOperation,
      isRunning: isRunning,
      startTime: startTime,
      elapsed: startTime != null ? DateTime.now().difference(startTime) : null,
    );
    _progressController.add(progress);
  }

  /// Legacy compatibility: Full sync method (migrates from SyncService)
  Future<void> fullSync({
    required String touristId,
    required List<String> destinationIds,
  }) async {
    debugPrint('🔄 SyncEngine: Starting full sync for $touristId');

    // Enqueue critical operations first
    await _enqueueIdentitySync(touristId);
    await _enqueueLocationPings();
    await _enqueueSosEvents(touristId);

    // Enqueue background operations
    for (final destId in destinationIds) {
      await _enqueueZoneSync(destId);
      await _enqueueTrailGraphSync(destId);
    }

    await processQueue();
  }

  /// Enqueue identity sync if needed
  Future<void> _enqueueIdentitySync(String touristId) async {
    final tourist = await _db.getTourist();
    if (tourist != null &&
        !tourist.isSynced &&
        tourist.registrationFields != null) {
      await enqueue(SyncOperation(
        id: 'identity_${tourist.touristId}',
        type: SyncOperationType.touristIdentity,
        priority: SyncPriority.high,
        payload: {
          'fields': tourist.registrationFields,
          'photoPath': tourist.registrationFields!['local_photo_path'],
          'docPath': tourist.registrationFields!['local_doc_path'],
        },
      ));
    }
  }

  /// Enqueue pending location pings
  Future<void> _enqueueLocationPings() async {
    final pings = await _db.getUnsyncedPings();
    for (final ping in pings.take(_batchSize)) {
      await enqueue(SyncOperation(
        id: 'ping_${ping.id}',
        type: SyncOperationType.locationPing,
        priority: SyncPriority.normal,
        payload: ping.toMap(),
      ));
    }
  }

  /// Enqueue pending SOS events (CRITICAL priority)
  Future<void> _enqueueSosEvents(String touristId) async {
    final events = await _db.getUnsyncedSosEvents();
    for (final event in events) {
      await _enqueueSosEventFromMap(event, touristIdOverride: touristId);
    }
  }

  Future<void> _enqueueSosEventFromMap(
    Map<String, dynamic> event, {
    String? touristIdOverride,
  }) async {
    final localId = event['id'] is int
        ? event['id'] as int
        : int.tryParse(event['id']?.toString() ?? '');
    if (localId == null) return;

    final idempotencyKey =
        event['idempotencyKey']?.toString() ?? const Uuid().v4();
    final touristId = touristIdOverride ?? event['touristId']?.toString();
    if (touristId == null || touristId.isEmpty) return;

    final timestamp = event['timestamp'] is int
        ? event['timestamp'] as int
        : int.tryParse(event['timestamp']?.toString() ?? '');
    if (timestamp == null) return;

    await enqueueSosEvent(
      localId: localId,
      touristId: touristId,
      latitude: (event['latitude'] as num?)?.toDouble(),
      longitude: (event['longitude'] as num?)?.toDouble(),
      triggerType: event['triggerType']?.toString() ?? 'MANUAL',
      idempotencyKey: idempotencyKey,
      timestamp: timestamp,
    );
  }

  /// Enqueue zone sync (LOW priority)
  Future<void> _enqueueZoneSync(String destinationId) async {
    await enqueue(SyncOperation(
      id: 'zone_$destinationId',
      type: SyncOperationType.zoneData,
      priority: SyncPriority.low,
      payload: {'destinationId': destinationId},
    ));
  }

  /// Enqueue trail graph sync (LOW priority)
  Future<void> _enqueueTrailGraphSync(String destinationId) async {
    await enqueue(SyncOperation(
      id: 'graph_$destinationId',
      type: SyncOperationType.trailGraph,
      priority: SyncPriority.low,
      payload: {'destinationId': destinationId},
    ));
  }

  /// Dispose resources
  void dispose() {
    _periodicTimer?.cancel();
    _progressController.close();
  }
}
