import 'dart:async';

import 'package:flutter/material.dart';
import 'package:saferoute/core/service_locator.dart';
import 'package:saferoute/services/analytics_service.dart';
import 'package:saferoute/services/mesh_service.dart';
import 'package:saferoute/services/secure_storage_service.dart';
import 'package:saferoute/tourist/models/mesh/mesh_node.dart';
import 'package:saferoute/tourist/models/mesh/mesh_packet.dart';

enum MeshRuntimeState {
  idle,
  checking,
  permissionNeeded,
  bluetoothOff,
  unsupported,
  starting,
  active,
  failed,
}

class MeshProvider extends ChangeNotifier {
  final MeshService _meshService = locator<MeshService>();

  List<MeshNode> _nearbyNodes = [];
  final List<MeshPacket> _recentActivity = [];
  bool _isMeshActive = false;
  bool _isGuest = false;
  MeshRuntimeState _meshState = MeshRuntimeState.idle;
  String _statusMessage =
      'Offline relay is off. Internet SOS and group sync still work.';
  String? _lastError;
  String? _activeUserId;
  bool _isDisposed = false;

  StreamSubscription? _nodesSub;
  StreamSubscription? _packetSub;

  List<MeshNode> get nearbyNodes => _nearbyNodes;
  List<MeshPacket> get recentActivity => _recentActivity;
  bool get isMeshActive => _isMeshActive;
  MeshRuntimeState get meshState => _meshState;
  String get statusMessage => _statusMessage;
  String? get lastError => _lastError;
  bool get canStart =>
      _meshState == MeshRuntimeState.idle ||
      _meshState == MeshRuntimeState.permissionNeeded ||
      _meshState == MeshRuntimeState.bluetoothOff ||
      _meshState == MeshRuntimeState.failed;
  bool get canBroadcast =>
      _isMeshActive && _meshState == MeshRuntimeState.active;

  void setGuestMode(bool isGuest) => _isGuest = isGuest;

  Future<void> init(String userId) async {
    _activeUserId = userId;
    await _meshService.init(userId);
  }

  Future<bool> startMesh() async {
    if (_isMeshActive) return true;
    if (_activeUserId == null || _activeUserId!.isEmpty) {
      _setRuntimeState(
        MeshRuntimeState.failed,
        'Mesh identity is not ready. Log in again before starting offline relay.',
        error: 'Missing mesh user id',
      );
      return false;
    }

    _setRuntimeState(
      MeshRuntimeState.checking,
      'Checking Bluetooth support and permissions...',
    );
    _setRuntimeState(
      MeshRuntimeState.starting,
      'Starting offline rescue relay...',
    );

    try {
      final result = await _meshService.start();
      switch (result) {
        case MeshServiceStartResult.success:
          _isMeshActive = true;
          _nodesSub ??= _meshService.nearbyNodes.listen((nodes) {
            if (_isDisposed) return;
            _nearbyNodes = nodes;
            notifyListeners();
          });
          _packetSub ??=
              _meshService.incomingPackets.listen(_handleIncomingPacket);
          _setRuntimeState(
            MeshRuntimeState.active,
            'Offline relay active. Nearby SafeRoute devices can receive fallback signals.',
          );
          return true;
        case MeshServiceStartResult.unsupported:
          _setRuntimeState(
            MeshRuntimeState.unsupported,
            'This phone does not support BLE mesh. Internet SOS and group sync still work.',
            error: _meshService.lastError,
          );
          return false;
        case MeshServiceStartResult.permissionDenied:
          _setRuntimeState(
            MeshRuntimeState.permissionNeeded,
            'Bluetooth permission is needed only for offline relay. Internet SOS still works.',
            error: _meshService.lastError,
          );
          return false;
        case MeshServiceStartResult.bluetoothOff:
          _setRuntimeState(
            MeshRuntimeState.bluetoothOff,
            'Bluetooth is off. Turn it on, then tap Start Mesh again.',
            error: _meshService.lastError,
          );
          return false;
        case MeshServiceStartResult.failed:
          _setRuntimeState(
            MeshRuntimeState.failed,
            'Mesh could not start on this phone. Internet SOS and group sync still work.',
            error: _meshService.lastError,
          );
          return false;
      }
    } catch (e) {
      _setRuntimeState(
        MeshRuntimeState.failed,
        'Mesh failed safely. Internet SOS and group sync still work.',
        error: e.toString(),
      );
      return false;
    }
  }

  Future<void> stopMesh() async {
    await _meshService.stop();
    unawaited(_nodesSub?.cancel());
    unawaited(_packetSub?.cancel());
    _nodesSub = null;
    _packetSub = null;
    _isMeshActive = false;
    _nearbyNodes = [];
    _setRuntimeState(
      MeshRuntimeState.idle,
      'Offline relay is off. Internet SOS and group sync still work.',
    );
  }

  Future<void> sendSosRelay(double lat, double lng) async {
    if (!canBroadcast) {
      _setRuntimeState(
        _meshState,
        'Start Mesh before sending an offline SOS relay.',
        error: _lastError,
      );
      return;
    }

    if (_isGuest) {
      debugPrint(
        'Mesh Safety: guest originating SOS relay. Identity will be limited.',
      );
    }

    final packet = MeshPacket(
      sourceId: _meshService.myUserId ?? 'unknown',
      type: MeshPacketType.sosAlert,
      lat: lat,
      lng: lng,
      priority: 1,
    );

    final jwtSecret = await locator<SecureStorageService>().getToken() ??
        await locator<SecureStorageService>().getTouristId() ??
        'SAFEROUTE_OFFLINE_SECRET';

    final signedPacket = MeshPacket(
      packetId: packet.packetId,
      sourceId: packet.sourceId,
      type: packet.type,
      lat: packet.lat,
      lng: packet.lng,
      hopCount: packet.hopCount,
      priority: packet.priority,
      signature: packet.generateSignature(jwtSecret),
    );

    await _meshService.sendPacket(signedPacket);
    _recordActivity(signedPacket);
  }

  Future<void> broadcastLocation(double lat, double lng) async {
    if (!canBroadcast) return;
    final packet = MeshPacket(
      sourceId: _meshService.myUserId ?? 'unknown',
      type: MeshPacketType.locationUpdate,
      lat: lat,
      lng: lng,
      priority: 0,
    );
    await _meshService.sendPacket(packet);
    _recordActivity(packet);
  }

  void _handleIncomingPacket(MeshPacket packet) {
    if (_isDisposed) return;
    _recordActivity(packet, notify: false);

    if (packet.type == MeshPacketType.sosAlert) {
      debugPrint('MESH ALERT: SOS received from ${packet.sourceId}');
      locator<AnalyticsService>().logEvent(
        AnalyticsEvent.meshPacketRelayed,
        properties: {'type': 'SOS', 'source': packet.sourceId},
      );
    }
    notifyListeners();
  }

  void _recordActivity(MeshPacket packet, {bool notify = true}) {
    if (_isDisposed) return;
    _recentActivity.insert(0, packet);
    if (_recentActivity.length > 50) _recentActivity.removeLast();
    if (notify) notifyListeners();
  }

  void _setRuntimeState(
    MeshRuntimeState state,
    String message, {
    String? error,
  }) {
    if (_isDisposed) return;
    _meshState = state;
    _statusMessage = message;
    _lastError = error;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    unawaited(_meshService.stop());
    unawaited(_nodesSub?.cancel());
    unawaited(_packetSub?.cancel());
    super.dispose();
  }
}
