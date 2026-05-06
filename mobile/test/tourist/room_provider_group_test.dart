import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saferoute/core/service_locator.dart';
import 'package:saferoute/services/api_service.dart';
import 'package:saferoute/services/room_service.dart';
import 'package:saferoute/services/secure_storage_service.dart';
import 'package:saferoute/tourist/models/room_member_model.dart';
import 'package:saferoute/tourist/providers/room_provider.dart';

class MockApiService implements ApiService {
  dynamic activeResponse;
  Object? getError;

  @override
  Future<dynamic> getJson(String path) async {
    if (getError != null) throw getError!;
    return activeResponse;
  }

  @override
  Future<dynamic> postJson(String path, Map<String, dynamic> body) async => {};

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class MockRoomService implements RoomService {
  final controller = StreamController<List<RoomMember>>.broadcast();
  int connectCount = 0;
  String? connectedRoomId;

  @override
  Stream<List<RoomMember>> get membersStream => controller.stream;

  @override
  bool get isConnected => connectCount > 0;

  @override
  Future<void> connect({
    required String roomId,
    required String userId,
    required String name,
    String? authToken,
  }) async {
    connectCount++;
    connectedRoomId = roomId;
  }

  @override
  void disconnect() {}

  @override
  void dispose() {
    unawaited(controller.close());
  }

  @override
  void sendLocation({
    required double lat,
    required double lng,
    double? accuracyMeters,
    double? batteryLevel,
    String? zoneStatus,
    String source = 'websocket',
    bool trusted = true,
  }) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class MockSecureStorageService implements SecureStorageService {
  @override
  Future<String?> getTouristId() async => 'T-100';

  @override
  Future<String?> getToken() async => 'token';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late MockApiService api;
  late MockRoomService roomService;

  Map<String, dynamic> member({
    String id = 'T-100',
    String name = 'Test Tourist',
    String sharingStatus = 'PAUSED',
  }) =>
      {
        'user_id': id,
        'tourist_id': id,
        'name': name,
        'display_name': name,
        'role': 'OWNER',
        'sharing_status': sharingStatus,
        'is_stale': true,
      };

  setUp(() async {
    await locator.reset();
    api = MockApiService();
    roomService = MockRoomService();
    locator.registerSingleton<ApiService>(api);
    locator.registerSingleton<RoomService>(roomService);
    locator.registerSingleton<SecureStorageService>(MockSecureStorageService());
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await locator.reset();
  });

  test('initialize keeps cached group as offline snapshot when server fails',
      () async {
    SharedPreferences.setMockInitialValues({
      'group_safety.active_group_id': 'cached-group',
      'group_safety.invite_code': 'CACHE1',
      'group_safety.group_name': 'Cached Team',
      'group_safety.sharing_enabled': false,
      'group_safety.members_snapshot': jsonEncode([member()]),
    });
    api.getError = Exception('network unavailable');

    final provider = RoomProvider();
    await provider.initialize();

    expect(provider.isInRoom, isTrue);
    expect(provider.isOfflineSnapshot, isTrue);
    expect(provider.groupId, 'cached-group');
    expect(provider.inviteCode, 'CACHE1');
    expect(provider.members, hasLength(1));
    expect(provider.canMutateMembership, isFalse);
    expect(roomService.connectCount, 0);

    provider.dispose();
  });

  test('initialize replaces cached group with server active group', () async {
    SharedPreferences.setMockInitialValues({
      'group_safety.active_group_id': 'cached-group',
      'group_safety.invite_code': 'CACHE1',
      'group_safety.group_name': 'Cached Team',
      'group_safety.sharing_enabled': false,
      'group_safety.members_snapshot': jsonEncode([member()]),
    });
    api.activeResponse = {
      'active_group': {
        'group_id': 'server-group',
        'invite_code': 'SERVER',
        'room_id': 'SERVER',
        'name': 'Server Team',
        'members': [member()],
        'current_member': member(),
      },
    };

    final provider = RoomProvider();
    await provider.initialize();

    expect(provider.isInRoom, isTrue);
    expect(provider.isOfflineSnapshot, isFalse);
    expect(provider.groupId, 'server-group');
    expect(provider.inviteCode, 'SERVER');
    expect(provider.groupName, 'Server Team');
    expect(roomService.connectedRoomId, 'SERVER');

    provider.dispose();
  });
}
