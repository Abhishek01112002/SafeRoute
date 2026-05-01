import 'dart:async';
import 'package:flutter/material.dart';
import '../models/mesh_node.dart';
import '../models/mesh_packet.dart';
import '../services/mesh_service.dart';

class MeshProvider extends ChangeNotifier {
  final MeshService _meshService = MeshService();
  
  List<MeshNode> _nearbyNodes = [];
  bool _isMeshActive = false;
  
  List<MeshNode> get nearbyNodes => _nearbyNodes;
  bool get isMeshActive => _isMeshActive;

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

  List<MeshPacket> _recentActivity = [];
  List<MeshPacket> get recentActivity => _recentActivity;

  void _handleIncomingPacket(MeshPacket packet) {
    _recentActivity.insert(0, packet);
    if (_recentActivity.length > 50) _recentActivity.removeLast(); // Keep top 50
    
    if (packet.type == MeshPacketType.SOS_ALERT) {
      debugPrint("MESH ALERT: SOS received from ${packet.sourceId}");
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
