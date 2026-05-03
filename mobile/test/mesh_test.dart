import 'package:flutter_test/flutter_test.dart';
import 'package:saferoute/mesh/models/mesh_packet.dart';
import 'package:saferoute/mesh/models/mesh_node.dart';

void main() {
  group('MeshPacket Tests', () {
    test('MeshPacket serialization and deserialization', () {
      final packet = MeshPacket(
        sourceId: 'userA',
        type: MeshPacketType.SOS_ALERT,
        lat: 28.6,
        lng: 77.2,
      );

      final map = packet.toMap();

      expect(map['sourceId'],
          packet.sourceId.hashCode.toString()); // map stores hash string
      expect(map['type'], MeshPacketType.SOS_ALERT.index);

      final deserialized = MeshPacket.fromMap(map);

      expect(
          deserialized.packetId,
          packet.packetId.hashCode
              .toString()); // DB persistence stores hash IDs
      expect(deserialized.sourceId, packet.sourceId.hashCode.toString());
      expect(deserialized.type, packet.type);
      expect(deserialized.lat, 28.6);
      expect(deserialized.lng, 77.2);
      expect(deserialized.hopCount, 3); // Default hop count
    });

    test('MeshPacket copyWith hopCount logic', () {
      final packet = MeshPacket(
        sourceId: 'userA',
        type: MeshPacketType.LOCATION_UPDATE,
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
