import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:saferoute/tourist/models/room_member_model.dart';
import 'package:saferoute/services/notification_service.dart';
import 'package:saferoute/core/config/env_config.dart';

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
  static const double _dangerSeparationKm = 1.0;

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
    final apiUri = Uri.parse(EnvConfig.apiBaseUrl);
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

      final type = json['type']?.toString();

      if (type == 'member_left' &&
          json['user_id'] != null &&
          json['user_id'] != _currentUserId) {
        NotificationService.showNotification(
          'Group signal lost',
          'A group member is no longer reachable.',
        );
      }

      if (type == 'rate_limited') {
        debugPrint('[WS] Location update rate-limited: ${json['reason']}');
        return;
      }

      if (type == 'error') {
        debugPrint('[WS] Server error: ${json['detail']}');
        return;
      }

      if (json['members'] is List) {
        final members = (json['members'] as List)
            .whereType<Map>()
            .map((m) => RoomMember.fromJson(Map<String, dynamic>.from(m)))
            .toList();

        if (members.isNotEmpty || type == 'sharing_paused') {
          _membersController.add(members);
          _checkDistances(members);
        }
      }
    } catch (e) {
      debugPrint('[WS] Error handling message: $e');
    }
  }

  void sendLocation({
    required double lat,
    required double lng,
    double? accuracyMeters,
    double? batteryLevel,
    String? zoneStatus,
    String source = 'websocket',
    bool trusted = true,
  }) {
    if (_channel == null) return;
    try {
      _channel!.sink.add(jsonEncode({
        'user_id': _currentUserId,
        'name': _currentName,
        'lat': lat,
        'lng': lng,
        'timestamp': DateTime.now().millisecondsSinceEpoch / 1000,
        if (accuracyMeters != null) 'accuracy_meters': accuracyMeters,
        if (batteryLevel != null) 'battery_level': batteryLevel,
        if (zoneStatus != null) 'zone_status': zoneStatus,
        'source': source,
        'trusted': trusted,
      }));
    } catch (e) {
      debugPrint('[WS] Error sending location: $e');
    }
  }

  void _checkDistances(List<RoomMember> members) {
    final matches = members.where((m) => m.userId == _currentUserId);
    final me = matches.isEmpty ? null : matches.first;
    if (me == null) return;

    for (final other in members) {
      if (other.userId == _currentUserId) continue;
      final dist = me.distanceTo(other);
      if (dist != null && dist > _dangerSeparationKm) {
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
