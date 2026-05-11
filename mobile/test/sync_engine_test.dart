import 'package:flutter_test/flutter_test.dart';
import 'package:saferoute/services/sync_engine.dart';

void main() {
  test('SyncOperation preserves nextAttempt for retry scheduling', () {
    final nextAttempt = DateTime.fromMillisecondsSinceEpoch(123456789);
    final operation = SyncOperation(
      id: 'op-1',
      type: SyncOperationType.locationPing,
      priority: SyncPriority.normal,
      payload: {'id': 42},
      state: SyncState.retrying,
      retryCount: 2,
      nextAttempt: nextAttempt,
    );

    final restored = SyncOperation.fromMap(operation.toMap());

    expect(restored.state, SyncState.retrying);
    expect(restored.retryCount, 2);
    expect(restored.nextAttempt, nextAttempt);
  });

  test('SyncOperation accepts legacy rows without nextAttempt', () {
    final createdAt = DateTime.fromMillisecondsSinceEpoch(1000);
    final restored = SyncOperation.fromMap({
      'id': 'legacy-op',
      'type': SyncOperationType.sosEvent.name,
      'priority': SyncPriority.critical.name,
      'payload': '{"localId":1}',
      'state': SyncState.pending.name,
      'retry_count': 0,
      'last_attempt': null,
      'error_message': null,
      'created_at': createdAt.millisecondsSinceEpoch,
    });

    expect(restored.id, 'legacy-op');
    expect(restored.nextAttempt, isNull);
  });
}
