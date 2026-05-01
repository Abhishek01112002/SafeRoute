import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/room_member_model.dart';
import 'notification_service.dart';
import '../utils/constants.dart';

class RoomService {
  WebSocketChannel? _channel;
  final _membersController = StreamController<List<RoomMember>>.broadcast();

  Stream<List<RoomMember>> get membersStream => _membersController.stream;

  String? _currentRoomId;
  String? _currentUserId;
  String? _currentName;
  String? _authToken;

  bool _intentionallyDisconnected = false;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  static const Duration _reconnectBaseDelay = Duration(seconds: 2);

  bool get isConnected => _channel != null;

  Future<void> connect({
    required String roomId,
    required String userId,
    required String name,
    String? authToken,
  }) async {
    _currentRoomId = roomId;
    _currentUserId = userId;
    _currentName = name;
    _authToken = authToken;
    _intentionallyDisconnected = false;
    _reconnectAttempts = 0;

    _connectInternal();
  }

  void _connectInternal() {
    if (_intentionallyDisconnected) return;

    final uri = _buildWebSocketUri();

    debugPrint('[WS] Connecting to: $uri (attempt #${_reconnectAttempts + 1})');

    try {
      _channel = WebSocketChannel.connect(uri);

      _channel!.stream.listen(
        (data) {
          _reconnectAttempts = 0; // reset on successful message
          _handleMessage(data);
        },
        onError: (e) {
          debugPrint('[WS] Error: $e');
          _channel = null;
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('[WS] Connection closed');
          _channel = null;
          _scheduleReconnect(); // FIX: auto-reconnect on any drop
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('[WS] Connect failed: $e');
      _channel = null;
      _scheduleReconnect();
    }
  }

  Uri _buildWebSocketUri() {
    final apiUri = Uri.parse(kBaseUrl);
    final scheme = apiUri.scheme == 'https' ? 'wss' : 'ws';
    final basePath = apiUri.path.endsWith('/')
        ? apiUri.path.substring(0, apiUri.path.length - 1)
        : apiUri.path;
    final wsPath = '$basePath/rooms/ws/$_currentRoomId/$_currentUserId';

    return apiUri.replace(
      scheme: scheme,
      path: wsPath,
      queryParameters: _authToken == null ? null : {'token': _authToken},
    );
  }

  /// FIX: Exponential back-off reconnection — critical for mountain connectivity.
  void _scheduleReconnect() {
    if (_intentionallyDisconnected) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('[WS] Max reconnect attempts reached. Giving up.');
      return;
    }

    _reconnectTimer?.cancel();
    // Exponential back-off: 2s, 4s, 8s … capped at 60s
    final delay = Duration(
      seconds: (_reconnectBaseDelay.inSeconds * (1 << _reconnectAttempts))
          .clamp(2, 60),
    );
    _reconnectAttempts++;
    debugPrint(
        '[WS] Reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts)');

    _reconnectTimer = Timer(delay, () {
      if (!_intentionallyDisconnected) {
        _connectInternal();
      }
    });
  }

  void _handleMessage(dynamic data) {
    try {
      final json = jsonDecode(data as String);

      if (json['type'] == 'location_update' || json['type'] == 'member_left') {
        if (json['type'] == 'member_left' &&
            json['user_id'] != null &&
            json['user_id'] != _currentUserId) {
          NotificationService.showNotification(
            'Group signal lost',
            'A group member is no longer reachable.',
          );
        }

        final members = (json['members'] as List)
            .map((m) => RoomMember.fromJson(m))
            .toList();

        _membersController.add(members);
        _checkDistances(members);
      }
    } catch (e) {
      debugPrint('[WS] Error handling message: $e');
    }
  }

  void sendLocation({required double lat, required double lng}) {
    if (_channel == null) return;
    try {
      _channel!.sink.add(jsonEncode({
        'name': _currentName,
        'lat': lat,
        'lng': lng,
      }));
    } catch (e) {
      debugPrint('[WS] Error sending location: $e');
    }
  }

  void _checkDistances(List<RoomMember> members) {
    final me = members.where((m) => m.userId == _currentUserId).firstOrNull;
    if (me == null) return;

    const double alertThresholdKm = 10.0;

    for (final other in members) {
      if (other.userId == _currentUserId) continue;
      final dist = me.distanceTo(other);
      if (dist > alertThresholdKm) {
        NotificationService.showDistanceAlert(other.name, dist);
      }
    }
  }

  void disconnect() {
    _intentionallyDisconnected = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    disconnect();
    _membersController.close();
  }
}
