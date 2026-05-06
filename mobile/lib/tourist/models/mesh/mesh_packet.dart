import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

enum MeshPacketType {
  locationUpdate,
  sosAlert,
  ack,
}

class MeshPacket {
  static const int protocolVersion = 3;
  static const int cbepLength = 31;
  static const int legacyCbepLength = 24;

  final String packetId;
  final String sourceId;
  final MeshPacketType type;
  final double lat;
  final double lng;
  final int hopCount;
  final int priority;
  final int keyVersion;
  final String idempotencyKey;
  final String idempotencyHashHex;
  final String tuidSuffix;
  final int unixMinute;
  final int flags;
  final int signature;
  final int signatureByteLength;
  final List<int> relayPathShortIds;

  int get version => protocolVersion;
  int get timestamp => unixMinute * 60000;

  MeshPacket({
    String? packetId,
    required this.sourceId,
    required this.type,
    required this.lat,
    required this.lng,
    this.hopCount = 5,
    this.priority = 0,
    this.keyVersion = 0,
    String? idempotencyKey,
    String? idempotencyHashHex,
    String? tuidSuffix,
    int? unixMinute,
    this.flags = 0,
    this.signature = 0,
    this.signatureByteLength = 4,
    List<int>? relayPathShortIds,
  })  : packetId = packetId ?? const Uuid().v4(),
        idempotencyKey = idempotencyKey ?? packetId ?? const Uuid().v4(),
        idempotencyHashHex = idempotencyHashHex ??
            _hashIdempotency(idempotencyKey ?? packetId ?? const Uuid().v4()),
        tuidSuffix = (tuidSuffix ?? _suffix(sourceId)).toUpperCase(),
        unixMinute = unixMinute ??
            DateTime.now().toUtc().millisecondsSinceEpoch ~/ 60000,
        relayPathShortIds = (relayPathShortIds ?? []).take(5).toList();

  factory MeshPacket.signedSos({
    required String originTuid,
    required String meshSecret,
    required int keyVersion,
    required String idempotencyKey,
    required double lat,
    required double lng,
  }) {
    final quantizedLat = double.parse(lat.toStringAsFixed(4));
    final quantizedLng = double.parse(lng.toStringAsFixed(4));
    final packet = MeshPacket(
      packetId: idempotencyKey,
      sourceId: originTuid,
      type: MeshPacketType.sosAlert,
      lat: quantizedLat,
      lng: quantizedLng,
      priority: 1,
      keyVersion: keyVersion,
      idempotencyKey: idempotencyKey,
      tuidSuffix: _suffix(originTuid),
    );
    return packet.copyWith(signature: packet.generateSignature(meshSecret));
  }

  static String _hashIdempotency(String value) {
    return hex
        .encode(sha256.convert(utf8.encode(value)).bytes.take(6).toList());
  }

  static String _suffix(String value) {
    final normalized = value.trim().toUpperCase();
    if (normalized.length >= 4) {
      return normalized.substring(normalized.length - 4);
    }
    return normalized.padLeft(4, '0');
  }

  String canonicalPayload({String triggerType = 'MANUAL'}) {
    return 'v1:${idempotencyHashHex.toLowerCase()}:${tuidSuffix.toUpperCase()}:'
        '${lat.toStringAsFixed(6)}:${lng.toStringAsFixed(6)}:'
        '$unixMinute:${triggerType.toUpperCase()}';
  }

  int generateSignature(String secret, {int bytesLen = 4}) {
    final digest = Hmac(sha256, utf8.encode(secret))
        .convert(utf8.encode(canonicalPayload()))
        .bytes;
    var value = 0;
    for (final byte in digest.take(bytesLen.clamp(1, 4))) {
      value = (value << 8) | byte;
    }
    return value;
  }

  Uint8List toCBEPBytes() {
    final buffer = ByteData(cbepLength);
    buffer.setUint8(
      0,
      (protocolVersion << 4) | (hopCount.clamp(0, 15).toInt() & 0x0F),
    );
    buffer.setUint8(1, type.index);
    buffer.setUint8(2, keyVersion & 0xFF);
    buffer.setUint8(3, flags & 0xFF);

    final idHash =
        hex.decode(idempotencyHashHex.padRight(12, '0').substring(0, 12));
    for (var i = 0; i < 6; i++) {
      buffer.setUint8(4 + i, idHash[i]);
    }

    final suffixBytes =
        ascii.encode(tuidSuffix.padLeft(4, '0').substring(0, 4));
    for (var i = 0; i < 4; i++) {
      buffer.setUint8(10 + i, suffixBytes[i]);
    }

    buffer.setInt32(14, (lat * 1000000).round());
    buffer.setInt32(18, (lng * 1000000).round());
    buffer.setUint32(22, unixMinute);
    buffer.setUint32(26, signature);

    var sum = 0;
    for (var i = 0; i < 30; i++) {
      sum += buffer.getUint8(i);
    }
    buffer.setUint8(30, sum & 0xFF);
    return buffer.buffer.asUint8List();
  }

  Uint8List toLegacyCBEPBytes() {
    final buffer = ByteData(legacyCbepLength);
    buffer.setUint8(
      0,
      (protocolVersion << 4) | (hopCount.clamp(0, 15).toInt() & 0x0F),
    );
    buffer.setUint8(1, type.index);
    buffer.setUint8(2, keyVersion & 0xFF);

    final idHash =
        hex.decode(idempotencyHashHex.padRight(12, '0').substring(0, 12));
    for (var i = 0; i < 6; i++) {
      buffer.setUint8(3 + i, idHash[i]);
    }

    final suffixBytes =
        ascii.encode(tuidSuffix.padLeft(4, '0').substring(0, 4));
    for (var i = 0; i < 4; i++) {
      buffer.setUint8(9 + i, suffixBytes[i]);
    }

    _setInt24(buffer, 13, (lat * 10000).round());
    _setInt24(buffer, 16, (lng * 10000).round());
    buffer.setUint16(19, unixMinute & 0xFFFF);

    final sig24 = signatureByteLength == 3
        ? signature & 0xFFFFFF
        : (signature >> 8) & 0xFFFFFF;
    buffer.setUint8(21, (sig24 >> 16) & 0xFF);
    buffer.setUint8(22, (sig24 >> 8) & 0xFF);
    buffer.setUint8(23, sig24 & 0xFF);
    return buffer.buffer.asUint8List();
  }

  factory MeshPacket.fromCBEPBytes(Uint8List bytes) {
    if (bytes.length == legacyCbepLength) {
      return _fromLegacyCBEPBytes(bytes);
    }
    if (bytes.length < cbepLength) {
      throw Exception('Invalid CBEP payload length');
    }
    final buffer = ByteData.sublistView(bytes);
    var sum = 0;
    for (var i = 0; i < 30; i++) {
      sum += buffer.getUint8(i);
    }
    if (buffer.getUint8(30) != (sum & 0xFF)) {
      throw Exception('CBEP checksum mismatch');
    }

    final versionHop = buffer.getUint8(0);
    final version = versionHop >> 4;
    if (version != protocolVersion) {
      throw Exception('Incompatible mesh protocol version: $version');
    }

    final rawType = buffer.getUint8(1);
    final type = rawType >= 0 && rawType < MeshPacketType.values.length
        ? MeshPacketType.values[rawType]
        : MeshPacketType.sosAlert;
    final idHash = <int>[];
    for (var i = 0; i < 6; i++) {
      idHash.add(buffer.getUint8(4 + i));
    }
    final suffixBytes = <int>[];
    for (var i = 0; i < 4; i++) {
      suffixBytes.add(buffer.getUint8(10 + i));
    }
    final tuidSuffix = ascii.decode(suffixBytes).toUpperCase();
    final idempotencyHashHex = hex.encode(idHash);
    final unixMinute = buffer.getUint32(22);

    return MeshPacket(
      packetId: '$tuidSuffix-$idempotencyHashHex-$unixMinute',
      sourceId: tuidSuffix,
      type: type,
      lat: buffer.getInt32(14) / 1000000.0,
      lng: buffer.getInt32(18) / 1000000.0,
      hopCount: versionHop & 0x0F,
      priority: type == MeshPacketType.sosAlert ? 1 : 0,
      keyVersion: buffer.getUint8(2),
      idempotencyKey: '$tuidSuffix-$idempotencyHashHex-$unixMinute',
      idempotencyHashHex: idempotencyHashHex,
      tuidSuffix: tuidSuffix,
      unixMinute: unixMinute,
      flags: buffer.getUint8(3),
      signature: buffer.getUint32(26),
      signatureByteLength: 4,
    );
  }

  static MeshPacket _fromLegacyCBEPBytes(Uint8List bytes) {
    final buffer = ByteData.sublistView(bytes);
    final versionHop = buffer.getUint8(0);
    final version = versionHop >> 4;
    if (version != protocolVersion) {
      throw Exception('Incompatible mesh protocol version: $version');
    }

    final rawType = buffer.getUint8(1);
    final type = rawType >= 0 && rawType < MeshPacketType.values.length
        ? MeshPacketType.values[rawType]
        : MeshPacketType.sosAlert;
    final idHash = <int>[];
    for (var i = 0; i < 6; i++) {
      idHash.add(buffer.getUint8(3 + i));
    }
    final suffixBytes = <int>[];
    for (var i = 0; i < 4; i++) {
      suffixBytes.add(buffer.getUint8(9 + i));
    }
    final tuidSuffix = ascii.decode(suffixBytes).toUpperCase();
    final idempotencyHashHex = hex.encode(idHash);
    final unixMinute = _expandUnixMinute(buffer.getUint16(19));
    final sig24 = (buffer.getUint8(21) << 16) |
        (buffer.getUint8(22) << 8) |
        buffer.getUint8(23);

    return MeshPacket(
      packetId: '$tuidSuffix-$idempotencyHashHex-$unixMinute',
      sourceId: tuidSuffix,
      type: type,
      lat: _getInt24(buffer, 13) / 10000.0,
      lng: _getInt24(buffer, 16) / 10000.0,
      hopCount: versionHop & 0x0F,
      priority: type == MeshPacketType.sosAlert ? 1 : 0,
      keyVersion: buffer.getUint8(2),
      idempotencyKey: '$tuidSuffix-$idempotencyHashHex-$unixMinute',
      idempotencyHashHex: idempotencyHashHex,
      tuidSuffix: tuidSuffix,
      unixMinute: unixMinute,
      signature: sig24,
      signatureByteLength: 3,
    );
  }

  static void _setInt24(ByteData buffer, int offset, int value) {
    final encoded = value < 0 ? value + 0x1000000 : value;
    buffer.setUint8(offset, (encoded >> 16) & 0xFF);
    buffer.setUint8(offset + 1, (encoded >> 8) & 0xFF);
    buffer.setUint8(offset + 2, encoded & 0xFF);
  }

  static int _getInt24(ByteData buffer, int offset) {
    final value = (buffer.getUint8(offset) << 16) |
        (buffer.getUint8(offset + 1) << 8) |
        buffer.getUint8(offset + 2);
    return (value & 0x800000) != 0 ? value - 0x1000000 : value;
  }

  static int _expandUnixMinute(int minuteMod) {
    final nowMinute = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 60000;
    final base = nowMinute & ~0xFFFF;
    final candidates = [
      base - 0x10000 + minuteMod,
      base + minuteMod,
      base + 0x10000 + minuteMod,
    ];
    candidates
        .sort((a, b) => (a - nowMinute).abs().compareTo((b - nowMinute).abs()));
    return candidates.first;
  }

  Map<String, dynamic> toRelayPayload() {
    return {
      'origin_tuid_suffix': tuidSuffix,
      'idempotency_hash': idempotencyHashHex,
      'latitude': lat,
      'longitude': lng,
      'unix_minute': unixMinute,
      'trigger_type': 'MANUAL',
      'key_version': keyVersion,
      'origin_signature': signature
          .toRadixString(16)
          .padLeft(signatureByteLength.clamp(1, 4) * 2, '0'),
      'packet_id': packetId,
      'relay_path':
          relayPathShortIds.map((id) => id.toRadixString(16)).toList(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'packetId': packetId,
      'sourceId': sourceId,
      'type': type.index,
      'payload': jsonEncode({
        'lat': lat,
        'lng': lng,
        'priority': priority,
        'keyVersion': keyVersion,
        'idempotencyKey': idempotencyKey,
        'idempotencyHashHex': idempotencyHashHex,
        'tuidSuffix': tuidSuffix,
        'unixMinute': unixMinute,
        'flags': flags,
        'sig': signature,
        'sigBytes': signatureByteLength,
        'path': relayPathShortIds,
        'ver': protocolVersion,
      }),
      'hopCount': hopCount,
      'timestamp': unixMinute * 60000,
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
      hopCount: map['hopCount'] ?? 5,
      priority: payload['priority'] ?? 0,
      keyVersion: payload['keyVersion'] ?? 0,
      idempotencyKey: payload['idempotencyKey'],
      idempotencyHashHex: payload['idempotencyHashHex'],
      tuidSuffix: payload['tuidSuffix'],
      unixMinute: payload['unixMinute'],
      flags: payload['flags'] ?? 0,
      signature: payload['sig'] ?? 0,
      signatureByteLength: payload['sigBytes'] ?? 4,
      relayPathShortIds: List<int>.from(payload['path'] ?? []),
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
      keyVersion: keyVersion,
      idempotencyKey: idempotencyKey,
      idempotencyHashHex: idempotencyHashHex,
      tuidSuffix: tuidSuffix,
      unixMinute: unixMinute,
      flags: flags,
      signature: signature ?? this.signature,
      signatureByteLength: signatureByteLength,
      relayPathShortIds: newPath ?? relayPathShortIds,
    );
  }
}
