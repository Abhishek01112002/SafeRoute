import 'package:flutter_test/flutter_test.dart';
import 'package:saferoute/tourist/models/mesh/mesh_packet.dart';
import 'package:saferoute/tourist/models/mesh/mesh_node.dart';

void main() {
  group('MeshPacket Tests', () {
    test('MeshPacket serialization and deserialization', () {
      final packet = MeshPacket(
        sourceId: 'userA',
        type: MeshPacketType.sosAlert,
        lat: 28.6,
        lng: 77.2,
      );

      final map = packet.toMap();

      expect(map['sourceId'], packet.sourceId); // toMap stores raw string
      expect(map['type'], MeshPacketType.sosAlert.index);

      final deserialized = MeshPacket.fromMap(map);

      expect(deserialized.packetId, packet.packetId); // round-trips cleanly
      expect(deserialized.sourceId, packet.sourceId);
      expect(deserialized.type, packet.type);
      expect(deserialized.lat, 28.6);
      expect(deserialized.lng, 77.2);
      expect(deserialized.hopCount, 5); // Default hop count
    });

    test('MeshPacket copyWith hopCount logic', () {
      final packet = MeshPacket(
        sourceId: 'userA',
        type: MeshPacketType.locationUpdate,
        lat: 0.0,
        lng: 0.0,
        hopCount: 3,
      );

      final relayedPacket = packet.copyWith(hopCount: packet.hopCount - 1);

      expect(relayedPacket.packetId,
          packet.packetId); // MUST be same ID so caching prevents loops
      expect(relayedPacket.hopCount, 2);
    });

    test('CBEP v3 full packet preserves relay fields', () {
      final packet = MeshPacket.signedSos(
        originTuid: 'TID-2026-UK-AB8E8',
        meshSecret: 'test-secret',
        keyVersion: 7,
        idempotencyKey: 'field-test-001',
        lat: 30.733312,
        lng: 79.066671,
      );

      final decoded = MeshPacket.fromCBEPBytes(packet.toCBEPBytes());

      expect(decoded.type, MeshPacketType.sosAlert);
      expect(decoded.keyVersion, 7);
      expect(decoded.tuidSuffix, 'B8E8');
      expect(decoded.idempotencyHashHex, packet.idempotencyHashHex);
      expect(decoded.signatureByteLength, 4);
      expect(decoded.toRelayPayload()['origin_signature'], hasLength(8));
    });

    test('legacy CBEP fallback fits old Android BLE advertising', () {
      final packet = MeshPacket.signedSos(
        originTuid: 'TID-2026-UK-FEAE5',
        meshSecret: 'test-secret',
        keyVersion: 3,
        idempotencyKey: 'field-test-legacy-001',
        lat: 30.733312,
        lng: 79.066671,
      );

      final bytes = packet.toLegacyCBEPBytes();
      final decoded = MeshPacket.fromCBEPBytes(bytes);

      expect(bytes, hasLength(MeshPacket.legacyCbepLength));
      expect(decoded.type, MeshPacketType.sosAlert);
      expect(decoded.keyVersion, 3);
      expect(decoded.tuidSuffix, 'EAE5');
      expect(decoded.idempotencyHashHex, packet.idempotencyHashHex);
      expect(decoded.signatureByteLength, 3);
      expect(decoded.toRelayPayload()['origin_signature'], hasLength(6));
      expect(decoded.lat, closeTo(30.7333, 0.0001));
      expect(decoded.lng, closeTo(79.0667, 0.0001));
    });
  });

  group('MeshNode Tests', () {
    test('MeshNode creation from scan', () {
      final node = MeshNode.fromScan('node_123', 'SR-Alice', -65);

      expect(node.userId, 'node_123');
      expect(node.name, 'SR-Alice');
      expect(node.rssi, -65);
      expect(
          DateTime.now().difference(node.lastSeen).inSeconds, 0); // Roughly now
    });
  });
}
