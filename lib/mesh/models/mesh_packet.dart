import 'dart:convert';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';

enum MeshPacketType {
  LOCATION_UPDATE, // 0
  SOS_ALERT,       // 1
  ACK              // 2
}

class MeshPacket {
  final int version = 1;
  final String packetId; // We store String, but encode as 4-byte hash
  final String sourceId; // We store String, but encode as 4-byte hash
  final MeshPacketType type;
  final double lat;
  final double lng;
  final int hopCount;
  final int priority;
  final List<int> relayPathShortIds; // Max 5 items, 2-bytes each
  final int timestamp; // Local storage only, not sent over BLE (saves bytes)

  MeshPacket({
    String? packetId,
    required this.sourceId,
    required this.type,
    required this.lat,
    required this.lng,
    this.hopCount = 3,
    this.priority = 0,
    List<int>? relayPathShortIds,
    int? timestamp,
  })  : packetId = packetId ?? const Uuid().v4(),
        relayPathShortIds = relayPathShortIds ?? [],
        timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  // Convert to 31-byte CBEP Protocol (Compact Binary Encoding Protocol)
  Uint8List toCBEPBytes() {
    final buffer = ByteData(31); // Strict BLE Manufacturer Data limit
    
    buffer.setUint8(0, version);
    buffer.setUint8(1, type.index);
    buffer.setUint8(2, hopCount);
    buffer.setUint8(3, priority);
    
    // 4-byte hash for identity to save 32-byte UUID overhead
    buffer.setUint32(4, packetId.hashCode & 0xFFFFFFFF);
    buffer.setUint32(8, sourceId.hashCode & 0xFFFFFFFF);
    
    // IEEE 754 float32 takes 4 bytes each, perfect for geographic coordinates
    buffer.setFloat32(12, lat);
    buffer.setFloat32(16, lng);

    // Relay Path Tracking (up to 5 devices * 2 bytes = 10 bytes)
    for (int i = 0; i < 5; i++) {
      if (i < relayPathShortIds.length) {
        buffer.setUint16(20 + (i * 2), relayPathShortIds[i] & 0xFFFF);
      } else {
        buffer.setUint16(20 + (i * 2), 0); // Padding empty slots
      }
    }

    // Basic checksum
    int sum = 0;
    for (int i = 0; i < 30; i++) sum += buffer.getUint8(i);
    buffer.setUint8(30, sum & 0xFF);

    return buffer.buffer.asUint8List();
  }

  factory MeshPacket.fromCBEPBytes(Uint8List bytes) {
    if (bytes.length < 31) throw Exception("Invalid CBEP Payload Length");
    
    final buffer = ByteData.sublistView(bytes);
    
    // Verify Checksum
    int sum = 0;
    for (int i = 0; i < 30; i++) sum += buffer.getUint8(i);
    if (buffer.getUint8(30) != (sum & 0xFF)) {
      throw Exception("CBEP Checksum Mismatch. Packet corrupted in transit.");
    }

    final type = MeshPacketType.values[buffer.getUint8(1)];
    final hopCount = buffer.getUint8(2);
    final priority = buffer.getUint8(3);
    
    final pIdHash = buffer.getUint32(4).toString();
    final sIdHash = buffer.getUint32(8).toString();
    
    final lat = buffer.getFloat32(12);
    final lng = buffer.getFloat32(16);

    List<int> path = [];
    for (int i = 0; i < 5; i++) {
      int id = buffer.getUint16(20 + (i * 2));
      if (id != 0) path.add(id);
    }

    return MeshPacket(
      packetId: pIdHash, // Treat the hash as the ID string for the DB cache
      sourceId: sIdHash,
      type: type,
      lat: lat,
      lng: lng,
      hopCount: hopCount,
      priority: priority,
      relayPathShortIds: path,
    );
  }
  
  // Backward compatibility wrapper for SQLite storage (db handles JSON blobs)
  Map<String, dynamic> toMap() {
    return {
      'packetId': packetId.hashCode.toString(),
      'sourceId': sourceId.hashCode.toString(),
      'ttl': hopCount,
      'type': type.index,
      'payload': '{"lat":$lat, "lng":$lng, "path":$relayPathShortIds}',
      'hopCount': hopCount,
      'timestamp': timestamp,
    };
  }

  factory MeshPacket.fromMap(Map<String, dynamic> map) {
    final payload = jsonDecode(map['payload'] as String);
    return MeshPacket(
      packetId: map['packetId'],
      sourceId: map['sourceId'],
      type: MeshPacketType.values[map['type']],
      lat: (payload['lat'] as num).toDouble(),
      lng: (payload['lng'] as num).toDouble(),
      hopCount: map['hopCount'] ?? map['ttl'],
      relayPathShortIds: List<int>.from(payload['path'] ?? []),
      timestamp: map['timestamp'],
    );
  }

  MeshPacket copyWith({String? packetId, int? hopCount, List<int>? newPath}) {
    return MeshPacket(
      packetId: packetId ?? this.packetId,
      sourceId: sourceId,
      type: type,
      lat: lat,
      lng: lng,
      hopCount: hopCount ?? this.hopCount,
      priority: this.priority,
      relayPathShortIds: newPath ?? this.relayPathShortIds,
      timestamp: timestamp,
    );
  }
}
