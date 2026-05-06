import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saferoute/core/service_locator.dart';
import 'package:saferoute/services/api_service.dart';
import 'package:saferoute/services/room_service.dart';
import 'package:saferoute/services/secure_storage_service.dart';
import 'package:saferoute/tourist/models/room_member_model.dart';

class RoomProvider extends ChangeNotifier {
  final RoomService _roomService = locator<RoomService>();
  final ApiService _apiService = locator<ApiService>();
  final SecureStorageService _secureStorage = locator<SecureStorageService>();

  static const _cacheGroupId = 'group_safety.active_group_id';
  static const _cacheInviteCode = 'group_safety.invite_code';
  static const _cacheGroupName = 'group_safety.group_name';
  static const _cacheSharing = 'group_safety.sharing_enabled';
  static const _cacheMembers = 'group_safety.members_snapshot';
  static const _cacheSavedAt = 'group_safety.snapshot_saved_at';

  List<RoomMember> _members = [];
  String? _roomId;
  String? _groupId;
  String? _inviteCode;
  String? _groupName;
  String? _currentUserId;
  String? _currentName;
  bool _isInRoom = false;
  bool _isLoading = false;
  bool _isSharingLocation = false;
  bool _isOfflineSnapshot = false;
  String? _error;
  DateTime? _lastSnapshotAt;

  StreamSubscription? _membersSub;
  StreamSubscription? _locationSub;
  Timer? _heartbeatTimer;
  Position? _lastSharedPosition;

  List<RoomMember> get members => _members;
  String? get roomId => _roomId;
  String? get groupId => _groupId;
  String? get inviteCode => _inviteCode;
  String get groupName => _groupName ?? 'Travel Group';
  bool get isInRoom => _isInRoom;
  bool get isLoading => _isLoading;
  bool get isSharingLocation => _isSharingLocation;
  bool get isOfflineSnapshot => _isOfflineSnapshot;
  bool get canMutateMembership =>
      _isInRoom && !_isOfflineSnapshot && !_isLoading;
  String? get error => _error;
  DateTime? get lastSnapshotAt => _lastSnapshotAt;
  bool get isSocketConnected => _roomService.isConnected;
  int get staleMemberCount => _members.where((m) => m.isStale).length;

  RoomMember? get currentMember {
    final userId = _currentUserId;
    if (userId == null) return null;
    final matches = _members.where((member) => member.userId == userId);
    return matches.isEmpty ? null : matches.first;
  }

  Future<void> initialize() async {
    await _restoreFromCache();
    final touristId = await _resolveTouristId();
    if (touristId == null || touristId.isEmpty) {
      return;
    }
    _currentUserId = touristId;
    await _syncActiveGroup(touristId: touristId);
  }

  Future<void> refreshActiveGroup() async {
    final touristId = await _resolveTouristId();
    if (touristId == null || touristId.isEmpty) {
      _error = 'Tourist identity is not available on this device.';
      notifyListeners();
      return;
    }
    _currentUserId = touristId;
    await _syncActiveGroup(touristId: touristId);
  }

  void setSharingLocation(bool value) {
    final previous = _isSharingLocation;
    _isSharingLocation = value;
    _error = null;

    if (value) {
      if (_isInRoom && !_isOfflineSnapshot) {
        _startLocationSharing();
      }
    } else {
      _stopLocationSharing();
    }

    notifyListeners();
    unawaited(_persistSharingPreference(value));

    if (_groupId != null && !_isOfflineSnapshot) {
      unawaited(_syncSharingPreference(value, previous));
    }
  }

  Future<void> createAndJoinRoom({
    required String userId,
    required String name,
    String? groupName,
    String? tripId,
    String? destinationId,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.postJson('/v3/groups', {
        'name': (groupName == null || groupName.trim().isEmpty)
            ? 'Travel Group'
            : groupName.trim(),
        if (tripId != null) 'trip_id': tripId,
        if (destinationId != null) 'destination_id': destinationId,
      });
      await _applyGroupPayload(
        _asMap(response)!,
        userId: userId,
        name: name,
        connectSocket: true,
        persist: true,
      );
    } catch (e) {
      _error = _friendlyError(e);
      debugPrint('Error creating group: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> joinRoom({
    required String roomId,
    required String userId,
    required String name,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final inviteCode = roomId.trim().toUpperCase();
      final response = await _apiService.postJson(
        '/v3/groups/$inviteCode/join',
        {},
      );
      await _applyGroupPayload(
        _asMap(response)!,
        userId: userId,
        name: name,
        connectSocket: true,
        persist: true,
      );
    } catch (e) {
      _error = _friendlyError(e);
      debugPrint('Error joining group: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void leaveRoom() {
    unawaited(_leaveRoom());
  }

  Future<void> _syncActiveGroup({required String touristId}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.getJson('/v3/groups/active');
      final responseMap = _asMap(response);
      final active = _asMap(responseMap?['active_group']);

      if (active == null) {
        await _clearLocalState(clearCache: true);
        return;
      }

      final currentMember = _asMap(active['current_member']);
      final displayName = (currentMember?['display_name'] ??
              currentMember?['name'] ??
              _currentName ??
              'Tourist')
          .toString();
      await _applyGroupPayload(
        active,
        userId: touristId,
        name: displayName,
        connectSocket: true,
        persist: true,
      );
    } catch (e) {
      _isOfflineSnapshot = _isInRoom;
      _error = _isInRoom
          ? 'Showing offline group snapshot. Reconnect to change membership.'
          : _friendlyError(e);
      debugPrint('Active group sync failed: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _applyGroupPayload(
    Map<String, dynamic> payload, {
    required String userId,
    required String name,
    bool connectSocket = false,
    bool persist = false,
  }) async {
    final membersPayload = payload['members'];
    final members = membersPayload is List
        ? membersPayload
            .whereType<Map>()
            .map((m) => RoomMember.fromJson(Map<String, dynamic>.from(m)))
            .toList()
        : <RoomMember>[];

    final currentMember = _asMap(payload['current_member']);
    _groupId = payload['group_id']?.toString();
    _inviteCode = (payload['invite_code'] ?? payload['room_id'])?.toString();
    _roomId = _inviteCode ?? _groupId;
    _groupName = payload['name']?.toString() ?? _groupName ?? 'Travel Group';
    _currentUserId = userId;
    _currentName = name;
    _members = members;
    _isInRoom = _groupId != null && _roomId != null;
    _isOfflineSnapshot = false;
    _error = null;
    _lastSnapshotAt = DateTime.now();

    if (currentMember != null) {
      _isSharingLocation = (currentMember['sharing_status'] ?? 'SHARING')
              .toString()
              .toUpperCase() ==
          'SHARING';
    }

    if (persist) {
      await _cacheActiveGroup();
    }

    if (connectSocket && _isInRoom) {
      await _connectSocket(userId: userId, name: name);
      if (_isSharingLocation) {
        _startLocationSharing();
      }
    }
  }

  Future<void> _connectSocket({
    required String userId,
    required String name,
  }) async {
    final roomRef = _roomId ?? _inviteCode ?? _groupId;
    if (roomRef == null) return;

    await _membersSub?.cancel();
    _roomService.disconnect();

    final token = await _secureStorage.getToken();
    await _roomService.connect(
      roomId: roomRef,
      userId: userId,
      name: name,
      authToken: token,
    );

    _membersSub = _roomService.membersStream.listen((members) {
      _members = members;
      _lastSnapshotAt = DateTime.now();
      unawaited(_cacheActiveGroup());
      notifyListeners();
    });
  }

  Future<void> _syncSharingPreference(bool value, bool previous) async {
    final groupId = _groupId;
    if (groupId == null) return;

    try {
      final response =
          await _apiService.postJson('/v3/groups/$groupId/sharing', {
        'sharing': value,
        'sharing_status': value ? 'SHARING' : 'PAUSED',
      });
      final touristId = _currentUserId ?? await _resolveTouristId();
      if (touristId != null) {
        await _applyGroupPayload(
          _asMap(response)!,
          userId: touristId,
          name: _currentName ?? 'Tourist',
          connectSocket: false,
          persist: true,
        );
      }
    } catch (e) {
      _isSharingLocation = previous;
      if (previous && _isInRoom) {
        _startLocationSharing();
      } else {
        _stopLocationSharing();
      }
      _error = 'Could not update sharing preference. Please try again.';
      notifyListeners();
      debugPrint('Sharing update failed: $e');
    }
  }

  Future<void> _leaveRoom() async {
    if (_isOfflineSnapshot) {
      _error = 'Reconnect before leaving the group.';
      notifyListeners();
      return;
    }

    final groupId = _groupId;
    if (groupId != null) {
      _isLoading = true;
      _error = null;
      notifyListeners();
      try {
        await _apiService.postJson('/v3/groups/$groupId/leave', {});
      } catch (e) {
        _isLoading = false;
        _error = _friendlyError(e);
        notifyListeners();
        debugPrint('Error leaving group: $e');
        return;
      }
    }

    await _clearLocalState(clearCache: true);
    _isLoading = false;
    notifyListeners();
  }

  void _startLocationSharing() {
    if (_isOfflineSnapshot) return;
    _locationSub?.cancel();
    _heartbeatTimer?.cancel();

    _locationSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(
      (pos) {
        if (_isSharingLocation) {
          _lastSharedPosition = pos;
          _sendPosition(pos);
        }
      },
      onError: (e) {
        _error = 'Location sharing paused until GPS permission is available.';
        notifyListeners();
        debugPrint('Group location stream failed: $e');
      },
    );

    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final pos = _lastSharedPosition;
      if (_isSharingLocation && pos != null) {
        _sendPosition(pos);
      }
    });
  }

  void _sendPosition(Position pos) {
    _roomService.sendLocation(
      lat: pos.latitude,
      lng: pos.longitude,
      accuracyMeters: pos.accuracy,
      zoneStatus: 'UNKNOWN',
      source: 'websocket',
      trusted: true,
    );
  }

  void _stopLocationSharing() {
    _locationSub?.cancel();
    _locationSub = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  Future<void> _restoreFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final groupId = prefs.getString(_cacheGroupId);
    final roomCode = prefs.getString(_cacheInviteCode);
    if (groupId == null && roomCode == null) return;

    final rawMembers = prefs.getString(_cacheMembers);
    final members = <RoomMember>[];
    if (rawMembers != null) {
      try {
        final decoded = jsonDecode(rawMembers);
        if (decoded is List) {
          members.addAll(
            decoded
                .whereType<Map>()
                .map((m) => RoomMember.fromJson(Map<String, dynamic>.from(m))),
          );
        }
      } catch (e) {
        debugPrint('Group cache restore failed: $e');
      }
    }

    _groupId = groupId;
    _inviteCode = roomCode;
    _roomId = roomCode ?? groupId;
    _groupName = prefs.getString(_cacheGroupName) ?? 'Travel Group';
    _isSharingLocation = prefs.getBool(_cacheSharing) ?? false;
    _members = members;
    _isInRoom = _roomId != null;
    _isOfflineSnapshot = _isInRoom;
    final savedAt = prefs.getString(_cacheSavedAt);
    _lastSnapshotAt = savedAt == null ? null : DateTime.tryParse(savedAt);
    notifyListeners();
  }

  Future<void> _cacheActiveGroup() async {
    final prefs = await SharedPreferences.getInstance();
    if (_groupId != null) {
      await prefs.setString(_cacheGroupId, _groupId!);
    }
    if (_inviteCode != null) {
      await prefs.setString(_cacheInviteCode, _inviteCode!);
    }
    await prefs.setString(_cacheGroupName, groupName);
    await prefs.setBool(_cacheSharing, _isSharingLocation);
    await prefs.setString(
      _cacheMembers,
      jsonEncode(_members.map((m) => m.toJson()).toList()),
    );
    await prefs.setString(_cacheSavedAt, DateTime.now().toIso8601String());
  }

  Future<void> _persistSharingPreference(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_cacheSharing, value);
  }

  Future<void> _clearCachedGroup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheGroupId);
    await prefs.remove(_cacheInviteCode);
    await prefs.remove(_cacheGroupName);
    await prefs.remove(_cacheSharing);
    await prefs.remove(_cacheMembers);
    await prefs.remove(_cacheSavedAt);
  }

  Future<void> _clearLocalState({required bool clearCache}) async {
    await _membersSub?.cancel();
    _membersSub = null;
    _stopLocationSharing();
    _roomService.disconnect();
    _members = [];
    _roomId = null;
    _groupId = null;
    _inviteCode = null;
    _groupName = null;
    _isInRoom = false;
    _isSharingLocation = false;
    _isOfflineSnapshot = false;
    _lastSnapshotAt = null;
    if (clearCache) {
      await _clearCachedGroup();
    }
  }

  Future<String?> _resolveTouristId() async {
    final secureId = await _secureStorage.getTouristId();
    if (secureId != null && secureId.isNotEmpty) return secureId;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('tourist_id');
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value == null) return null;
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('409')) {
      return 'This tourist already has an active group.';
    }
    if (text.contains('429')) {
      return 'Too many join attempts. Please wait a few minutes.';
    }
    if (text.contains('404')) {
      return 'Invite code was not found or has expired.';
    }
    return 'Group network request failed. Check backend connectivity and try again.';
  }

  @override
  void dispose() {
    _membersSub?.cancel();
    _stopLocationSharing();
    _roomService.dispose();
    super.dispose();
  }
}
