import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:convert/convert.dart';
import 'package:uuid/uuid.dart';

enum MeshPacketType {
  LOCATION_UPDATE, // 0
  SOS_ALERT,       // 1
  ACK              // 2
}

class MeshPacket {
  final int version = 2; // Protocol bump for signing
  final String packetId;
  final String sourceId;
  final MeshPacketType type;
  final double lat;
  final double lng;
  final int hopCount;
  final int priority;
  final List<int> relayPathShortIds; // Max 3 items (v2 protocol adjustment)
  final int timestamp;
  final int signature; // 4-byte HMAC truncation

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
    this.signature = 0,
  })  : packetId = packetId ?? const Uuid().v4(),
        relayPathShortIds = (relayPathShortIds ?? []).take(3).toList(),
        timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  /// Generates a string-based HMAC-SHA256 signature for backend synchronization.
  /// Format: "suffix:lat:lng:timestamp"
  String generateHmacSignature(String tuid) {
    final suffix = sourceId.length > 4 ? sourceId.substring(sourceId.length - 4) : sourceId;
    final payload = "$suffix:${lat.toStringAsFixed(6)}:${lng.toStringAsFixed(6)}:${DateTime.fromMillisecondsSinceEpoch(timestamp).toIso8601String()}";

    final hmac = Hmac(sha256, utf8.encode(tuid));
    final digest = hmac.convert(utf8.encode(payload));
    return digest.toString();
  }

  /// Generates a 4-byte signature based on packet contents and a shared secret.
  /// Only signs immutable fields so relayers can update hopCount/path without breaking the signature.
  int generateSignature(String secret) {
    // If secret is the TUID, we can derive the 4-byte signature from the full HMAC
    final fullSignature = generateHmacSignature(secret);
    final signatureBytes = hex.decode(fullSignature).take(4).toList();
    return ByteData.sublistView(Uint8List.fromList(signatureBytes)).getUint32(0);
  }

  // Convert to 31-byte CBEP v2 Protocol
  Uint8List toCBEPBytes() {
    final buffer = ByteData(31);

    buffer.setUint8(0, version);
    buffer.setUint8(1, type.index);
    buffer.setUint8(2, hopCount);
    buffer.setUint8(3, priority);

    buffer.setUint32(4, packetId.hashCode & 0xFFFFFFFF);
    buffer.setUint32(8, sourceId.hashCode & 0xFFFFFFFF);

    buffer.setFloat32(12, lat);
    buffer.setFloat32(16, lng);

    // Relay Path Tracking (up to 3 devices * 2 bytes = 6 bytes)
    for (int i = 0; i < 3; i++) {
      if (i < relayPathShortIds.length) {
        buffer.setUint16(20 + (i * 2), relayPathShortIds[i] & 0xFFFF);
      } else {
        buffer.setUint16(20 + (i * 2), 0);
      }
    }

    // 4-byte signature
    buffer.setUint32(26, signature);

    // Basic checksum (still used for quick corruption check)
    int sum = 0;
    for (int i = 0; i < 30; i++) {
      sum += buffer.getUint8(i);
    }
    buffer.setUint8(30, sum & 0xFF);

    return buffer.buffer.asUint8List();
  }

  factory MeshPacket.fromCBEPBytes(Uint8List bytes) {
    if (bytes.length < 31) throw Exception("Invalid CBEP Payload Length");
    final buffer = ByteData.sublistView(bytes);

    // Quick Checksum Verify
    int sum = 0;
    for (int i = 0; i < 30; i++) {
      sum += buffer.getUint8(i);
    }
    if (buffer.getUint8(30) != (sum & 0xFF)) {
      throw Exception("CBEP Checksum Mismatch");
    }

    final ver = buffer.getUint8(0);
    if (ver != 2) throw Exception("Incompatible Mesh Protocol Version: $ver");

    final type = MeshPacketType.values[buffer.getUint8(1)];
    final hopCount = buffer.getUint8(2);
    final priority = buffer.getUint8(3);
    final pIdHash = buffer.getUint32(4).toString();
    final sIdHash = buffer.getUint32(8).toString();
    final lat = buffer.getFloat32(12);
    final lng = buffer.getFloat32(16);

    List<int> path = [];
    for (int i = 0; i < 3; i++) {
      int id = buffer.getUint16(20 + (i * 2));
      if (id != 0) path.add(id);
    }

    final signature = buffer.getUint32(26);

    return MeshPacket(
      packetId: pIdHash,
      sourceId: sIdHash,
      type: type,
      lat: lat,
      lng: lng,
      hopCount: hopCount,
      priority: priority,
      relayPathShortIds: path,
      signature: signature,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'packetId': packetId,
      'sourceId': sourceId,
      'type': type.index,
      'payload': jsonEncode({
        'lat': lat,
        'lng': lng,
        'path': relayPathShortIds,
        'sig': signature,
        'ver': version,
      }),
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
      hopCount: map['hopCount'] ?? 3,
      relayPathShortIds: List<int>.from(payload['path'] ?? []),
      timestamp: map['timestamp'],
      signature: payload['sig'] ?? 0,
    );
  }

  MeshPacket copyWith({
    String? packetId,
    int? hopCount,
    List<int>? newPath,
    int? signature,
  }) {
    return MeshPacket(
      packetId: packetId ?? this.packetId,
      sourceId: sourceId,
      type: type,
      lat: lat,
      lng: lng,
      hopCount: hopCount ?? this.hopCount,
      priority: priority,
      relayPathShortIds: newPath ?? relayPathShortIds,
      timestamp: timestamp,
      signature: signature ?? this.signature,
    );
  }
}
