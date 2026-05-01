// lib/services/pathfinding_service.dart
// ============================================================
// SAFEROUTE — OFFLINE AI PATHFINDING ENGINE
// Works with ZERO internet, ZERO Bluetooth, ZERO network
// Only requirement: GPS (always works via satellites)
// ============================================================

import 'dart:math';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────
// DATA MODELS
// ─────────────────────────────────────────

import '../models/location_ping_model.dart';

class TrailNode {
  final String id;
  final double lat;
  final double lng;
  final ZoneType zone;
  final String name;

  const TrailNode({
    required this.id,
    required this.lat,
    required this.lng,
    required this.zone,
    required this.name,
  });

  factory TrailNode.fromJson(Map<String, dynamic> json) {
    return TrailNode(
      id: json['id'],
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      zone: ZoneTypeExtension.fromString(json['zone'] ?? ""),
      name: json['name'] ?? '',
    );
  }
}

class TrailEdge {
  final String fromId;
  final String toId;
  final double weightMeters; // actual distance in meters
  final List<dynamic>? offlinePath; // Pre-computed geometry for offline curves

  const TrailEdge({
    required this.fromId,
    required this.toId,
    required this.weightMeters,
    this.offlinePath,
  });

  factory TrailEdge.fromJson(Map<String, dynamic> json) {
    return TrailEdge(
      fromId: json['from'],
      toId: json['to'],
      weightMeters: (json['weight'] as num).toDouble(),
      offlinePath: json['offline_path'],
    );
  }
}

class NavigationResult {
  final List<TrailNode> path;       // ordered list of nodes to follow
  final List<Map<String, double>> offlineGeometries; // Curvy path array for offline
  final double totalDistanceMeters;
  final int estimatedMinutes;       // walking at ~4 km/h
  final bool pathFound;
  final String message;

  const NavigationResult({
    required this.path,
    required this.offlineGeometries,
    required this.totalDistanceMeters,
    required this.estimatedMinutes,
    required this.pathFound,
    required this.message,
  });

  static NavigationResult noPath() => const NavigationResult(
    path: [],
    offlineGeometries: [],
    totalDistanceMeters: 0,
    estimatedMinutes: 0,
    pathFound: false,
    message: 'No safe route found. Activate SOS immediately.',
  );
}

// ─────────────────────────────────────────
// A* PATHFINDING ENGINE
// ─────────────────────────────────────────

class _AStarNode {
  final String id;
  final double gCost;   // cost from start
  final double hCost;   // heuristic to goal
  final _AStarNode? parent;

  double get fCost => gCost + hCost;

  const _AStarNode({
    required this.id,
    required this.gCost,
    required this.hCost,
    this.parent,
  });
}

class PathfindingService {
  Map<String, TrailNode> _nodes = {};
  final Map<String, List<TrailEdge>> _adjacency = {};
  bool _isLoaded = false;

  // ── Load trail graph from local asset (no internet needed) ──
  Future<void> loadGraph() async {
    if (_isLoaded) return;

    try {
      // Load from assets/trail_graph.json (bundled with app)
      final String jsonStr =
          await rootBundle.loadString('assets/trail_graph.json');
      final Map<String, dynamic> data = json.decode(jsonStr);

      final List nodesJson  = data['nodes']  as List;
      final List edgesJson  = data['edges']  as List;

      _nodes = {
        for (var n in nodesJson)
          (n['id'] as String): TrailNode.fromJson(n as Map<String, dynamic>)
      };

      for (var e in edgesJson) {
        final edge = TrailEdge.fromJson(e as Map<String, dynamic>);
        // Bidirectional — trail goes both ways
        _adjacency.putIfAbsent(edge.fromId, () => []).add(edge);
        
        List<dynamic>? reverseCurve;
        if (edge.offlinePath != null) {
          reverseCurve = List.from(edge.offlinePath!.reversed);
        }
        
        _adjacency.putIfAbsent(edge.toId,   () => []).add(
          TrailEdge(
            fromId: edge.toId,
            toId: edge.fromId,
            weightMeters: edge.weightMeters,
            offlinePath: reverseCurve,
          ),
        );
      }

      _isLoaded = true;
      debugPrint('[Pathfinding] Graph loaded: ${_nodes.length} nodes, '
          '${edgesJson.length} edges');
    } catch (e) {
      debugPrint('[Pathfinding] ERROR loading graph: $e');
    }
  }

  // ── Main entry point: find route to nearest safe zone ──
  NavigationResult findRouteToSafety({
    required double currentLat,
    required double currentLng,
  }) {
    if (!_isLoaded || _nodes.isEmpty) {
      return NavigationResult.noPath();
    }

    // 1. Snap tourist to nearest node on the trail graph
    final startNode = _nearestNode(currentLat, currentLng);
    if (startNode == null) return NavigationResult.noPath();

    // If already in safe zone — no navigation needed
    if (startNode.zone == ZoneType.greenOuter || startNode.zone == ZoneType.greenInner) {
      return NavigationResult(
        path: [startNode],
        offlineGeometries: [{"lat": startNode.lat, "lng": startNode.lng}],
        totalDistanceMeters: 0,
        estimatedMinutes: 0,
        pathFound: true,
        message: 'You are already in a safe zone.',
      );
    }

    // 2. Find all safe-zone nodes as potential goals
    final safeNodes = _nodes.values
        .where((n) => n.zone == ZoneType.greenOuter || n.zone == ZoneType.greenInner)
        .toList();

    if (safeNodes.isEmpty) return NavigationResult.noPath();

    // 3. Run A* toward the geographically nearest safe node
    //    (heuristic = straight-line distance to nearest safe zone)
    final goalNode = _nearestAmong(startNode, safeNodes);
    final rawPath = _aStar(startNode.id, goalNode.id);

    if (rawPath == null) return NavigationResult.noPath();

    // 4. Calculate stats and build High-Res offline curves
    double totalDist = 0;
    List<Map<String, double>> fullCurve = [];
    
    if (rawPath.length == 1) {
       fullCurve.add({"lat": rawPath[0].lat, "lng": rawPath[0].lng});
    }

    for (int i = 0; i < rawPath.length - 1; i++) {
      final fromNode = rawPath[i];
      final toNode = rawPath[i + 1];
      
      final edgeList = _adjacency[fromNode.id];
      // Using firstWhere with nullable return inside try/catch or collection if
      final edgeListMatches = edgeList?.where((e) => e.toId == toNode.id).toList();
      final edge = (edgeListMatches != null && edgeListMatches.isNotEmpty) ? edgeListMatches.first : null;
      
      if (edge != null && edge.offlinePath != null && edge.offlinePath!.isNotEmpty) {
          for (var p in edge.offlinePath!) {
              fullCurve.add({
                "lat": (p['lat'] as num).toDouble(), 
                "lng": (p['lng'] as num).toDouble()
              });
          }
      } else {
          // Fallback to straight lines if script not run yet
          if (i == 0) fullCurve.add({"lat": fromNode.lat, "lng": fromNode.lng});
          fullCurve.add({"lat": toNode.lat, "lng": toNode.lng});
      }

      totalDist += _haversineMeters(
        fromNode.lat, fromNode.lng,
        toNode.lat, toNode.lng,
      );
    }

    final minutes = (totalDist / 1000 / 4.0 * 60).ceil(); // 4 km/h walk

    return NavigationResult(
      path: rawPath,
      offlineGeometries: fullCurve,
      totalDistanceMeters: totalDist,
      estimatedMinutes: minutes,
      pathFound: true,
      message: 'Route found! Head to ${goalNode.name}. '
          '${totalDist.toStringAsFixed(0)}m, ~$minutes min.',
    );
  }

  // ── A* Algorithm (pure Dart, no dependencies) ──
  List<TrailNode>? _aStar(String startId, String goalId) {
    final goal = _nodes[goalId]!;

    final openSet  = <String, _AStarNode>{};
    final closedSet = <String>{};

    openSet[startId] = _AStarNode(
      id: startId,
      gCost: 0,
      hCost: _haversineMeters(
        _nodes[startId]!.lat, _nodes[startId]!.lng,
        goal.lat, goal.lng,
      ),
    );

    while (openSet.isNotEmpty) {
      // Pick node with lowest f = g + h
      final current = openSet.values
          .reduce((a, b) => a.fCost < b.fCost ? a : b);

      if (current.id == goalId) {
        return _reconstructPath(current);
      }

      openSet.remove(current.id);
      closedSet.add(current.id);

      for (final edge in _adjacency[current.id] ?? []) {
        if (closedSet.contains(edge.toId)) continue;

        final neighborNode = _nodes[edge.toId];
        if (neighborNode == null) continue;

        // Penalize paths through restricted zones (3× weight)
        final zonePenalty = neighborNode.zone == ZoneType.red ? 3.0 : 1.0;
        final newG = current.gCost + edge.weightMeters * zonePenalty;

        final existing = openSet[edge.toId];
        if (existing == null || newG < existing.gCost) {
          openSet[edge.toId] = _AStarNode(
            id: edge.toId,
            gCost: newG,
            hCost: _haversineMeters(
              neighborNode.lat, neighborNode.lng,
              goal.lat, goal.lng,
            ),
            parent: current,
          );
        }
      }
    }

    return null; // no path found
  }

  List<TrailNode> _reconstructPath(_AStarNode node) {
    final path = <TrailNode>[];
    _AStarNode? current = node;
    while (current != null) {
      path.add(_nodes[current.id]!);
      current = current.parent;
    }
    return path.reversed.toList();
  }

  // ── Utilities ──

  TrailNode? _nearestNode(double lat, double lng) {
    TrailNode? nearest;
    double minDist = double.infinity;
    for (final node in _nodes.values) {
      final d = _haversineMeters(lat, lng, node.lat, node.lng);
      if (d < minDist) { minDist = d; nearest = node; }
    }
    return nearest;
  }

  TrailNode _nearestAmong(TrailNode from, List<TrailNode> candidates) {
    return candidates.reduce((a, b) {
      final dA = _haversineMeters(from.lat, from.lng, a.lat, a.lng);
      final dB = _haversineMeters(from.lat, from.lng, b.lat, b.lng);
      return dA < dB ? a : b;
    });
  }

  /// Haversine formula — accurate GPS distance in meters
  double _haversineMeters(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371000.0; // Earth radius in meters
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) *
            sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _toRad(double deg) => deg * pi / 180;

  // Expose nodes for map rendering
  Map<String, TrailNode> get nodes => Map.unmodifiable(_nodes);
}
