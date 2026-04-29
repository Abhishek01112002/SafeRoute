// lib/services/mesh_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

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
          if (data.length >= 10) {
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
  }) async {
    if (_isAdvertising) return;
    _isAdvertising = true;

    final AdvertiseData adData = AdvertiseData(
      serviceUuid: _serviceUuid,
      manufacturerId: 0xFFFF,
      manufacturerData: _encodePacket(touristId, lat, lng),
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

  Uint8List _encodePacket(String tid, double lat, double lng) {
    // Basic encoding: First 4 chars of TID + Lat (Float32) + Lng (Float32)
    final BytesBuilder bb = BytesBuilder();
    bb.add(utf8.encode(tid.length > 4 ? tid.substring(tid.length - 4) : tid));
    
    final ByteData coords = ByteData(8);
    coords.setFloat32(0, lat.toDouble(), Endian.little);
    coords.setFloat32(4, lng.toDouble(), Endian.little);
    bb.add(coords.buffer.asUint8List());

    return bb.toBytes();
  }

  Map<String, dynamic> _decodePacket(List<int> data) {
    final Uint8List bytes = Uint8List.fromList(data);
    final String tidSuffix = utf8.decode(bytes.sublist(0, 4));
    final ByteData coords = ByteData.sublistView(bytes, 4, 12);
    
    return {
      "tourist_id_suffix": tidSuffix,
      "latitude": coords.getFloat32(0, Endian.little),
      "longitude": coords.getFloat32(4, Endian.little),
      "received_at": DateTime.now().toIso8601String(),
    };
  }
}
