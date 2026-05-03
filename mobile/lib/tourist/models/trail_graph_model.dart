// lib/models/trail_graph_model.dart
// Per-destination trail graph — replaces the single bundled assets/trail_graph.json.
// The graph is served by the backend and cached locally in SQLite.

import 'dart:convert';
import 'package:saferoute/core/models/zone_model.dart';

// ── Node ──────────────────────────────────────────────────────────────────────

class TrailNode {
  final String id;
  final double lat;
  final double lng;
  final ZoneType zoneType;
  final String name;

  const TrailNode({
    required this.id,
    required this.lat,
    required this.lng,
    required this.zoneType,
    required this.name,
  });

  factory TrailNode.fromJson(Map<String, dynamic> j) => TrailNode(
    id:       j['id'] as String,
    lat:      (j['lat'] as num).toDouble(),
    lng:      (j['lng'] as num).toDouble(),
    zoneType: ZoneTypeExtension.fromString(j['zone_type'] as String? ?? j['zone'] as String? ?? ''),
    name:     j['name'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id':        id,
    'lat':       lat,
    'lng':       lng,
    'zone_type': zoneType.toApiString(),
    'name':      name,
  };
}

// ── Edge ──────────────────────────────────────────────────────────────────────

class TrailEdge {
  final String fromId;
  final String toId;
  final double weightMeters;
  final List<Map<String, double>> offlinePath; // pre-computed geometry points

  const TrailEdge({
    required this.fromId,
    required this.toId,
    required this.weightMeters,
    this.offlinePath = const [],
  });

  factory TrailEdge.fromJson(Map<String, dynamic> j) {
    List<Map<String, double>> path = [];
    if (j['offline_path'] is List) {
      path = (j['offline_path'] as List).map((p) {
        final m = p as Map<String, dynamic>;
        return <String, double>{
          'lat': (m['lat'] as num).toDouble(),
          'lng': (m['lng'] as num).toDouble(),
        };
      }).toList();
    }
    return TrailEdge(
      fromId:       j['from_node_id'] as String? ?? j['from'] as String,
      toId:         j['to_node_id'] as String? ?? j['to'] as String,
      weightMeters: (j['weight_meters'] as num? ?? j['weight'] as num).toDouble(),
      offlinePath:  path,
    );
  }

  Map<String, dynamic> toJson() => {
    'from_node_id':  fromId,
    'to_node_id':    toId,
    'weight_meters': weightMeters,
    'offline_path':  offlinePath,
  };
}

// ── Graph ─────────────────────────────────────────────────────────────────────

class TrailGraph {
  final String id;
  final String destinationId;
  final int version;
  final DateTime createdAt;
  final List<TrailNode> nodes;
  final List<TrailEdge> edges;

  const TrailGraph({
    required this.id,
    required this.destinationId,
    required this.version,
    required this.createdAt,
    required this.nodes,
    required this.edges,
  });

  factory TrailGraph.fromJson(Map<String, dynamic> j) {
    final nodesList = j['nodes'] as List? ?? [];
    final edgesList = j['edges'] as List? ?? [];

    return TrailGraph(
      id:            j['id'] as String? ?? '',
      destinationId: j['destination_id'] as String? ?? '',
      version:       (j['version'] as num? ?? 1).toInt(),
      createdAt:     DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
      nodes:         nodesList.map((n) => TrailNode.fromJson(n as Map<String, dynamic>)).toList(),
      edges:         edgesList.map((e) => TrailEdge.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id':             id,
    'destination_id': destinationId,
    'version':        version,
    'created_at':     createdAt.toIso8601String(),
    'nodes':          nodes.map((n) => n.toJson()).toList(),
    'edges':          edges.map((e) => e.toJson()).toList(),
  };

  /// SQLite flat map — full graph stored as JSON string in graph_json column
  Map<String, dynamic> toMap() => {
    'id':             id,
    'destination_id': destinationId,
    'version':        version,
    'graph_json':     json.encode(toJson()),
    'created_at':     createdAt.toIso8601String(),
  };

  factory TrailGraph.fromMap(Map<String, dynamic> m) {
    final graphJson = json.decode(m['graph_json'] as String) as Map<String, dynamic>;
    return TrailGraph.fromJson({
      ...graphJson,
      'id':             m['id'],
      'destination_id': m['destination_id'],
      'version':        m['version'],
      'created_at':     m['created_at'],
    });
  }

  bool get isEmpty => nodes.isEmpty;
}
