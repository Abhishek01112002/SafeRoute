// lib/services/simulation_engine.dart
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math' as math;

class SimulatedNode {
  final String id;
  final LatLng position;
  final double batteryHistory;
  final String status;

  SimulatedNode({
    required this.id,
    required this.position,
    required this.batteryHistory,
    required this.status,
  });
}

class SimulationEngine {
  /// Generates deterministic nearby nodes based on location and time.
  /// This ensures that users in the same area see the same "mesh traffic".
  static List<SimulatedNode> getNearbyNodes(LatLng center, DateTime time) {
    // 1. Create a seed based on location (coarse) and time window (5 mins)
    // We round Lat/Lng to ~100m for seed stability
    final double coarseLat = (center.latitude * 100).round() / 100.0;
    final double coarseLng = (center.longitude * 100).round() / 100.0;
    final int timeWindow = (time.millisecondsSinceEpoch / (1000 * 60)).floor();

    final String seedSource = "$coarseLat|$coarseLng|$timeWindow";
    final bytes = utf8.encode(seedSource);
    final hash = sha256.convert(bytes);

    // Use first 4 bytes of hash as seed for Random
    final int seed = hash.bytes[0] + (hash.bytes[1] << 8) + (hash.bytes[2] << 16) + (hash.bytes[3] << 24);
    final random = math.Random(seed);

    // 2. Generate 2-5 nodes
    final int count = 2 + random.nextInt(4);
    final List<SimulatedNode> nodes = [];

    for (int i = 0; i < count; i++) {
      // Deterministic jitter based on node index + timeWindow
      final jitterRandom = math.Random(seed + i);
      final double jitterLat = (jitterRandom.nextDouble() - 0.5) * 0.00005; // ~5m noise
      final double jitterLng = (jitterRandom.nextDouble() - 0.5) * 0.00005;

      // Offset nodes within ~500m of user
      final double latOffset = (random.nextDouble() - 0.5) * 0.005 + jitterLat;
      final double lngOffset = (random.nextDouble() - 0.5) * 0.005 + jitterLng;

      final String nodeId = "TR-${hash.bytes[i % hash.bytes.length].toRadixString(16).padLeft(2, '0')}-${i+100}";
      final double battery = 0.4 + (random.nextDouble() * 0.6); // 40-100%
      final status = random.nextDouble() > 0.8 ? "CAUTION" : "SECURE";

      nodes.add(SimulatedNode(
        id: nodeId,
        position: LatLng(center.latitude + latOffset, center.longitude + lngOffset),
        batteryHistory: battery,
        status: status,
      ));
    }

    return nodes;
  }
}
