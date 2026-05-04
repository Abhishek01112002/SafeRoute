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
      expect(deserialized.hopCount, 3); // Default hop count
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
