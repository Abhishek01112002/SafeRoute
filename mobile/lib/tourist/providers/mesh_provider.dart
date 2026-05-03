import 'dart:async';
import 'package:flutter/material.dart';
import 'package:saferoute/tourist/models/mesh/mesh_node.dart';
import 'package:saferoute/tourist/models/mesh/mesh_packet.dart';
import 'package:saferoute/services/mesh_service.dart';
import 'package:saferoute/services/analytics_service.dart';
import 'package:saferoute/core/service_locator.dart';

class MeshProvider extends ChangeNotifier {
  final MeshService _meshService = locator<MeshService>();

  List<MeshNode> _nearbyNodes = [];
  bool _isMeshActive = false;

  List<MeshNode> get nearbyNodes => _nearbyNodes;
  bool get isMeshActive => _isMeshActive;
  bool _isGuest = false;
  void setGuestMode(bool isGuest) => _isGuest = isGuest;

  StreamSubscription? _nodesSub;
  StreamSubscription? _packetSub;

  Future<void> init(String userId) async {
    await _meshService.init(userId);
  }

  Future<void> startMesh() async {
    if (_isMeshActive) return;

    await _meshService.start();
    _isMeshActive = true;

    _nodesSub = _meshService.nearbyNodes.listen((nodes) {
      _nearbyNodes = nodes;
      notifyListeners();
    });

    _packetSub = _meshService.incomingPackets.listen((packet) {
      // Handle incoming SOS or Message
      _handleIncomingPacket(packet);
    });

    notifyListeners();
  }

  final List<MeshPacket> _recentActivity = [];
  List<MeshPacket> get recentActivity => _recentActivity;

  void _handleIncomingPacket(MeshPacket packet) {
    _recentActivity.insert(0, packet);
    if (_recentActivity.length > 50) _recentActivity.removeLast(); // Keep top 50

    if (packet.type == MeshPacketType.SOS_ALERT) {
      debugPrint("MESH ALERT: SOS received from ${packet.sourceId}");
      // Analytics: Tracking mesh robustness
      locator<AnalyticsService>().logEvent(AnalyticsEvent.meshPacketRelayed, properties: {'type': 'SOS', 'source': packet.sourceId});
    }
    // Update UI
    notifyListeners();
  }

  Future<void> stopMesh() async {
    await _meshService.stop();
    _nodesSub?.cancel();
    _packetSub?.cancel();
    _isMeshActive = false;
    _nearbyNodes = [];
    notifyListeners();
  }

  Future<void> sendSosRelay(double lat, double lng) async {
    if (_isGuest) {
      debugPrint("🛡️ Mesh Safety: Guest originating SOS relay. Identity will be limited on backend.");
    }
    final packet = MeshPacket(
      sourceId: _meshService.myUserId ?? "unknown",
      type: MeshPacketType.SOS_ALERT,
      lat: lat,
      lng: lng,
      priority: 1, // High priority overrides queue
    );
    await _meshService.sendPacket(packet);
    _recentActivity.insert(0, packet);
    if (_recentActivity.length > 50) _recentActivity.removeLast();
    notifyListeners();
  }

  Future<void> broadcastLocation(double lat, double lng) async {
    if (!_isMeshActive) return;
    // Guests CAN broadcast location for safety/breadcrumb features
    final packet = MeshPacket(
      sourceId: _meshService.myUserId ?? "unknown",
      type: MeshPacketType.LOCATION_UPDATE,
      lat: lat,
      lng: lng,
      priority: 0,
    );
    await _meshService.sendPacket(packet);
    _recentActivity.insert(0, packet);
    if (_recentActivity.length > 50) _recentActivity.removeLast();
    notifyListeners();
  }

  @override
  void dispose() {
    stopMesh();
    super.dispose();
  }
}
