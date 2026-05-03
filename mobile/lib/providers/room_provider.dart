import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/room_member_model.dart';
import '../services/room_service.dart';
import '../services/api_service.dart';
import '../services/secure_storage_service.dart';

class RoomProvider extends ChangeNotifier {
  final RoomService _roomService = RoomService();
  final ApiService _apiService = ApiService();

  List<RoomMember> _members = [];
  String? _roomId;
  bool _isInRoom = false;
  bool _isLoading = false;
  StreamSubscription? _membersSub;
  StreamSubscription? _locationSub;
  Timer? _heartbeatTimer;
  Position? _lastSharedPosition;
  bool _isSharingLocation = false;
  final _secureStorage = SecureStorageService();

  List<RoomMember> get members => _members;
  String? get roomId => _roomId;
  bool get isInRoom => _isInRoom;
  bool get isLoading => _isLoading;
  bool get isSharingLocation => _isSharingLocation;

  void setSharingLocation(bool value) {
    _isSharingLocation = value;
    if (!_isSharingLocation) {
      _locationSub?.cancel();
      _heartbeatTimer?.cancel();
    } else if (_isInRoom) {
      _startLocationSharing();
    }
    notifyListeners();
  }

  Future<void> createAndJoinRoom({
    required String userId,
    required String name,
  }) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _apiService.post('/rooms/create', {});
      final id = response['room_id'];
      await _joinRoom(roomId: id, userId: userId, name: name);
    } catch (e) {
      debugPrint('Error creating room: $e');
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
    notifyListeners();
    try {
      await _apiService.post('/rooms/$roomId/join', {});
      await _joinRoom(roomId: roomId, userId: userId, name: name);
    } catch (e) {
      debugPrint('Error joining room: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _joinRoom({
    required String roomId,
    required String userId,
    required String name,
  }) async {
    _roomId = roomId;
    _isInRoom = true;

    final token = await _secureStorage.getToken();

    await _roomService.connect(
      roomId: roomId,
      userId: userId,
      name: name,
      authToken: token,
    );

    // Listen for member updates
    _membersSub = _roomService.membersStream.listen((members) {
      _members = members;
      notifyListeners();
    });

    if (_isSharingLocation) {
      _startLocationSharing();
    }

    notifyListeners();
  }

  void _startLocationSharing() {
    _locationSub?.cancel();
    _heartbeatTimer?.cancel();
    _locationSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((pos) {
      if (_isSharingLocation) {
        _lastSharedPosition = pos;
        _roomService.sendLocation(lat: pos.latitude, lng: pos.longitude);
      }
    });

    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final pos = _lastSharedPosition;
      if (_isSharingLocation && pos != null) {
        _roomService.sendLocation(lat: pos.latitude, lng: pos.longitude);
      }
    });
  }

  void leaveRoom() {
    _membersSub?.cancel();
    _locationSub?.cancel();
    _heartbeatTimer?.cancel();
    _roomService.disconnect();
    _isInRoom = false;
    _roomId = null;
    _members = [];
    notifyListeners();
  }

  @override
  void dispose() {
    _membersSub?.cancel();
    _locationSub?.cancel();
    _heartbeatTimer?.cancel();
    _roomService.dispose();
    super.dispose();
  }
}
