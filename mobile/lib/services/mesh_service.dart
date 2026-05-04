import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:saferoute/services/database_service.dart';
import 'package:saferoute/services/secure_storage_service.dart';
import 'package:saferoute/tourist/models/mesh/mesh_packet.dart';
import 'package:saferoute/tourist/models/mesh/mesh_node.dart';
import 'package:saferoute/core/service_locator.dart';

class MeshService {
  static final MeshService _instance = MeshService._internal();
  factory MeshService() => _instance;
  MeshService._internal();

  final _dbService = locator<DatabaseService>();
  final _storage = locator<SecureStorageService>();
  final _nearbyNodesController = StreamController<List<MeshNode>>.broadcast();
  final _incomingPacketController = StreamController<MeshPacket>.broadcast();

  Stream<List<MeshNode>> get nearbyNodes => _nearbyNodesController.stream;
  Stream<MeshPacket> get incomingPackets => _incomingPacketController.stream;

  final Map<String, MeshNode> _nodesMap = {};
  bool _isServiceRunning = false;
  String? _myUserId;
  String? _signingSecret;

  String? get myUserId => _myUserId;

  // Queue Structures
  bool _isQueueRunning = false;
  final List<MeshPacket> _emergencyQueue = [];
  final List<MeshPacket> _highQueue = [];
  final List<MeshPacket> _normalQueue = [];

  static const String _meshServiceUuid = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E";

  Future<void> init(String userId) async {
    _myUserId = userId;
    _signingSecret = await _storage.getToken();

    // If offline or no token, use TUID as a fallback stable secret for local mesh
    if (_signingSecret == null || _signingSecret == 'offline-token') { // pragma: allowlist secret
      _signingSecret = await _storage.getTouristId() ?? "SAFEROUTE_OFFLINE_SECRET_STUB"; // pragma: allowlist secret
    }
  }

  Future<void> start() async {
    if (_isServiceRunning) return;

    // Secure Runtime Permissions or Android 12+ silently shuts down BLE layers
    final scanPerm = await Permission.bluetoothScan.request();
    final connPerm = await Permission.bluetoothConnect.request();
    final advPerm = await Permission.bluetoothAdvertise.request();
    final locPerm = await Permission.location.request();

    if (scanPerm.isPermanentlyDenied ||
        connPerm.isPermanentlyDenied ||
        advPerm.isPermanentlyDenied ||
        locPerm.isPermanentlyDenied ||
        scanPerm.isDenied ||
        connPerm.isDenied ||
        advPerm.isDenied ||
        locPerm.isDenied) {
      debugPrint("Mesh: Fatal. Missing BLE permissions.");
      return;
    }

    _isServiceRunning = true;

    // Scan/Advertise Strategy Defaults
    // Scan Window: 80ms, Interval: 100ms
    FlutterBluePlus.onScanResults.listen((results) {
      for (ScanResult r in results) {
        if (r.advertisementData.serviceUuids.contains(Guid(_meshServiceUuid))) {
          _handleDiscoveredNode(r);
        }
      }
    });

    try {
      // Check for Bluetooth & Location permissions before starting scan
      if (await FlutterBluePlus.isSupported == false) {
        debugPrint("Mesh: Bluetooth not supported");
        return;
      }

      await FlutterBluePlus.startScan(continuousUpdates: true);
    } catch (e) {
      debugPrint("Mesh: Start scan failed (permissions?): $e");
    }

    unawaited(_startQueueExecutionLoop());
    await _startDefaultAdvertising();
  }

  Future<void> _startQueueExecutionLoop() async {
    if (_isQueueRunning) return;
    _isQueueRunning = true;

    while (_isServiceRunning) {
      MeshPacket? packet;

      // Interrupt execution logic based on strict priority
      if (_emergencyQueue.isNotEmpty) {
        packet = _emergencyQueue.removeAt(0);
      } else if (_highQueue.isNotEmpty) {
        packet = _highQueue.removeAt(0);
      } else if (_normalQueue.isNotEmpty) {
        packet = _normalQueue.removeAt(0);
      }

      if (packet != null) {
        await _executeBroadcast(packet);
        await Future.delayed(
            const Duration(milliseconds: 100)); // Advertising duty cycle
      } else {
        await Future.delayed(const Duration(milliseconds: 50)); // Idle wait
      }
    }
    _isQueueRunning = false;
  }

  bool _hasPacketInAnyQueue(String id) {
    return _emergencyQueue.any((p) => p.packetId == id) ||
        _highQueue.any((p) => p.packetId == id) ||
        _normalQueue.any((p) => p.packetId == id);
  }

  void _enqueuePacket(MeshPacket packet) {
    if (_hasPacketInAnyQueue(packet.packetId)) return;

    if (packet.type == MeshPacketType.sosAlert) {
      _emergencyQueue.add(packet);
    } else if (packet.priority > 0) {
      _highQueue.add(packet);
    } else {
      _normalQueue.add(packet);
    }
  }

  Future<void> _executeBroadcast(MeshPacket packet) async {
    debugPrint(
        "Mesh: Broadcasting packet ${packet.packetId} (Priority ${packet.priority})");
    try {
      final AdvertiseData advertiseData = AdvertiseData(
        serviceUuid: _meshServiceUuid,
        manufacturerId: 0xFFFF, // FAANG Custom Mapping
        manufacturerData: packet.toCBEPBytes(),
        includeDeviceName: false, // Save payload bytes
      );

      await FlutterBlePeripheral().stop();
      await FlutterBlePeripheral().start(advertiseData: advertiseData);
    } catch (e) {
      debugPrint("MeshService: Re-broadcast exception: $e");
    }
  }

  Future<void> _startDefaultAdvertising() async {
    final AdvertiseData advertiseData = AdvertiseData(
      serviceUuid: _meshServiceUuid,
      includeDeviceName: true,
    );
    await FlutterBlePeripheral().start(advertiseData: advertiseData);
  }

  void _handleDiscoveredNode(ScanResult result) {
    final nodeId = result.device.remoteId.str;
    final name = result.advertisementData.advName.isNotEmpty
        ? result.advertisementData.advName
        : "Unknown Node";

    _nodesMap[nodeId] = MeshNode.fromScan(nodeId, name, result.rssi);
    _nearbyNodesController.add(_nodesMap.values.toList());

    if (result.advertisementData.manufacturerData.isNotEmpty) {
      unawaited(_processIncomingCBEPData(
          result.advertisementData.manufacturerData.values.first, result.rssi));
    }
  }

  Future<void> _processIncomingCBEPData(List<int> data, int rssi) async {
    try {
      final packet = MeshPacket.fromCBEPBytes(Uint8List.fromList(data));

      // Security: Validate Signature
      // In production, we'd fetch the public key/secret for the sourceId from a local cache.
      // For this hackathon/POC, we use a shared build-time salt if the user is offline,
      // or their own JWT if they are the source.
      // Note: Full verification requires the backend to broadcast "Mesh Keys" to all users.
      if (packet.signature == 0) {
        debugPrint("Mesh: Dropping unsigned packet from ${packet.sourceId}");
        return;
      }

      // Verification logic:
      // If we are the source, we know our secret.
      // Otherwise, we check if it's signed with the 'trusted' global salt.
      const globalSalt = String.fromEnvironment('SAFEROUTE_TUID_SALT', defaultValue: "SR_IDENTITY_V1_UTTARAKHAND_2025");
      final expectedSig = packet.generateSignature(globalSalt);

      debugPrint("[MeshService] Validating packet signature...");
      if (packet.signature != expectedSig) {
         debugPrint("❌ Invalid or missing signature. Dropping packet ${packet.packetId}. Possible spoofing attempt.");
         return;
      }
      debugPrint("✅ Signature verified. Processing packet ${packet.packetId}...");

      // Strict State Dedup
      if (await _dbService.hasPacket(packet.packetId)) return;
      await _dbService.saveMeshPacket(packet);

      // Distribute to App Layer
      _incomingPacketController.add(packet);

      // Probabilistic Flooding Algorithm
      if (packet.hopCount > 0) {
        int delayMs = 0;

        // If signal is strong, others might relay it. Add Jitter.
        if (rssi > -65) {
          delayMs = 50 + Random().nextInt(150); // Jitter 50ms to 200ms
          await Future.delayed(Duration(milliseconds: delayMs));
        }

        // If duplicate detected in background during Jitter delay, cancel.
        if (await _dbService.hasPacket("${packet.packetId}_relayed")) return;

        // Mark as locally processed relay to avoid re-queueing self
        await _dbService.saveMeshPacket(
            packet.copyWith(packetId: "${packet.packetId}_relayed"));

        // TraceRoute Injection
        final myShortId = (_myUserId?.hashCode ?? 0) & 0xFFFF;
        final List<int> newPath = List.from(packet.relayPathShortIds);
        if (newPath.length < 5) newPath.add(myShortId);

        final relayedPacket =
            packet.copyWith(hopCount: packet.hopCount - 1, newPath: newPath);

        _enqueuePacket(relayedPacket);
      }
    } catch (e) {
      // Silently drop non-CBEP noise.
    }
  }

  Future<void> sendPacket(MeshPacket packet) async {
    // Cryptographically sign the packet before queuing
    const globalSalt = String.fromEnvironment('SAFEROUTE_TUID_SALT', defaultValue: "SR_IDENTITY_V1_UTTARAKHAND_2025");
    final signedPacket = packet.copyWith(
      signature: packet.generateSignature(globalSalt)
    );

    // Queue internal user packets instantly
    _enqueuePacket(signedPacket);
  }

  Future<void> stop() async {
    _isServiceRunning = false;
    await FlutterBluePlus.stopScan();
    await FlutterBlePeripheral().stop();
  }
}
