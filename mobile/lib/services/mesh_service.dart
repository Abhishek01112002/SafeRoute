// lib/services/mesh_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:saferoute/mesh/models/mesh_packet.dart';

class MeshService {
  static final MeshService _instance = MeshService._internal();
  factory MeshService() => _instance;
  MeshService._internal();

  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();
  bool _isScanning = false;
  bool _isAdvertising = false;

  // SafeRoute Service UUID for Mesh Discovery
  static const String _serviceUuid = "4a983300-30fd-4b4d-912f-6830720616cc";

  StreamSubscription? _scanSub;

  /// Start scanning for SOS packets from other SafeRoute devices
  Future<void> startScanning({required Function(Map<String, dynamic> data) onSosDetected}) async {
    if (_isScanning) return;
    _isScanning = true;

    debugPrint("📶 Mesh: Starting background scan for SOS packets...");

    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      for (ScanResult r in results) {
        final Map<int, List<int>> manufData = r.advertisementData.manufacturerData;

        // We look for our custom manufacturer ID (0xFFFF for hackathon)
        if (manufData.containsKey(0xFFFF)) {
          final List<int> data = manufData[0xFFFF]!;
          if (data.length >= 31) { // v2 protocol length
            try {
              final decoded = _decodePacket(data);
              onSosDetected(decoded);
            } catch (e) {
              debugPrint("❌ Mesh: Failed to decode packet: $e");
            }
          }
        }
      }
    });

    await FlutterBluePlus.startScan(
      withServices: [Guid(_serviceUuid)],
      continuousUpdates: true,
      androidUsesFineLocation: true,
    );
  }

  /// Stop scanning
  Future<void> stopScanning() async {
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    _isScanning = false;
  }

  /// Broadcast an SOS alert via BLE advertisement
  Future<void> broadcastSos({
    required String touristId,
    required double lat,
    required double lng,
    String? tuid,
  }) async {
    if (_isAdvertising) return;
    _isAdvertising = true;

    final AdvertiseData adData = AdvertiseData(
      serviceUuid: _serviceUuid,
      manufacturerId: 0xFFFF,
      manufacturerData: _encodePacket(touristId, lat, lng, tuid: tuid),
    );

    debugPrint("🆘 Mesh: Broadcasting SOS packet via BLE Peripheral...");
    await _peripheral.start(advertiseData: adData);
  }

  /// Stop broadcasting
  Future<void> stopBroadcasting() async {
    await _peripheral.stop();
    _isAdvertising = false;
  }

  // --- Helper Methods ---

  Uint8List _encodePacket(String tid, double lat, double lng, {String? tuid}) {
    // v2: Use MeshPacket for secure signing
    final packet = MeshPacket(
      sourceId: tid,
      type: MeshPacketType.SOS_ALERT,
      lat: lat,
      lng: lng,
      priority: 1, // SOS is high priority
    );

    // If we have the TUID, sign the packet. Otherwise, it's an unsigned legacy packet.
    final signedPacket = tuid != null
        ? packet.copyWith(signature: packet.generateSignature(tuid))
        : packet;

    return signedPacket.toCBEPBytes();
  }

  Map<String, dynamic> _decodePacket(List<int> data) {
    try {
      final packet = MeshPacket.fromCBEPBytes(Uint8List.fromList(data));
      return {
        "tourist_id_suffix": packet.sourceId.length > 4
            ? packet.sourceId.substring(packet.sourceId.length - 4)
            : packet.sourceId,
        "latitude": packet.lat,
        "longitude": packet.lng,
        "signature": packet.signature.toString(),
        "received_at": DateTime.now().toIso8601String(),
        "packet_id": packet.packetId,
      };
    } catch (e) {
      debugPrint("❌ Mesh: Decoding error: $e");
      rethrow;
    }
  }
}
