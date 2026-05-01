// lib/providers/mesh_provider.dart
import 'package:flutter/material.dart';
import 'package:saferoute/services/mesh_service.dart';
import 'package:saferoute/services/notification_service.dart';

class MeshProvider extends ChangeNotifier {
  final MeshService _meshService = MeshService();
  bool _isMeshActive = false;
  List<Map<String, dynamic>> _meshAlerts = [];

  bool get isMeshActive => _isMeshActive;
  List<Map<String, dynamic>> get meshAlerts => _meshAlerts;

  Future<void> initMesh() async {
    if (_isMeshActive) return;

    await _meshService.startScanning(onSosDetected: (data) {
      _handleDetectedSos(data);
    });

    _isMeshActive = true;
    notifyListeners();
  }

  void _handleDetectedSos(Map<String, dynamic> data) {
    // Check if we already have this alert (by TID suffix)
    final String tid = data['tourist_id_suffix'];
    final bool alreadyExists =
        _meshAlerts.any((a) => a['tourist_id_suffix'] == tid);

    if (!alreadyExists) {
      _meshAlerts.add(data);

      // Notify the user via a local notification
      NotificationService.showNotification(
        "📡 MESH ALERT: Distress Signal",
        "Nearby tourist ($tid) is calling for help! Check map.",
      );

      notifyListeners();
    }
  }

  Future<void> stopMesh() async {
    await _meshService.stopScanning();
    _isMeshActive = false;
    notifyListeners();
  }

  Future<void> broadcastEmergency(
      String touristId, double lat, double lng) async {
    await _meshService.broadcastSos(touristId: touristId, lat: lat, lng: lng);
  }

  Future<void> cancelEmergency() async {
    await _meshService.stopBroadcasting();
  }
}
