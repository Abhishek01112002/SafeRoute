// lib/services/pathfinding_service.dart
// Per-destination A* pathfinding engine.
// Graph is fetched from the backend API and cached in local SQLite.
// Works with ZERO internet once cached. Only requires GPS.

import 'dart:math';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:saferoute/models/trail_graph_model.dart';
import 'package:saferoute/models/zone_model.dart';
import 'package:saferoute/services/api_service.dart';
import 'package:saferoute/services/database_service.dart';

// ── Navigation result ─────────────────────────────────────────────────────────

class NavigationResult {
  final List<TrailNode> path;
  final List<Map<String, double>> offlineGeometries;
  final double totalDistanceMeters;
  final int estimatedMinutes;
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

  static const NavigationResult noPath = NavigationResult(
    path: [],
    offlineGeometries: [],
    totalDistanceMeters: 0,
    estimatedMinutes: 0,
    pathFound: false,
    message: 'No safe route found. Activate SOS immediately.',
  );

  static const NavigationResult noGraph = NavigationResult(
    path: [],
    offlineGeometries: [],
    totalDistanceMeters: 0,
    estimatedMinutes: 0,
    pathFound: false,
    message: 'Trail map not available for this destination. Use SOS if in danger.',
  );
}

// ── A* node ──────────────────────────────────────────────────────────────────

class _AStarNode {
  final String id;
  final double gCost;
  final double hCost;
  final _AStarNode? parent;
  double get fCost => gCost + hCost;

  const _AStarNode({required this.id, required this.gCost, required this.hCost, this.parent});
}

// ── Service ───────────────────────────────────────────────────────────────────

class PathfindingService {
  TrailGraph? _graph;
  Map<String, TrailNode> _nodes = {};
  Map<String, List<TrailEdge>> _adjacency = {};
  String? _loadedDestinationId;

  bool get isLoaded => _graph != null && !_graph!.isEmpty;

  // ── Load graph for a destination ──────────────────────────────────────────

  Future<void> loadForDestination(String destinationId) async {
    if (_loadedDestinationId == destinationId && isLoaded) return;

    TrailGraph? graph;

    // 1. Try API
    try {
      graph = await ApiService().getTrailGraph(destinationId);
      if (graph != null && !graph.isEmpty) {
        await DatabaseService().saveTrailGraph(graph);
        debugPrint('[Pathfinding] Graph loaded from API: ${graph.nodes.length} nodes for $destinationId');
      }
    } catch (e) {
      debugPrint('[Pathfinding] API failed: $e — trying cache');
    }

    // 2. Try local cache
    if (graph == null || graph.isEmpty) {
      graph = await DatabaseService().getTrailGraph(destinationId);
      if (graph != null && !graph.isEmpty) {
        debugPrint('[Pathfinding] Graph loaded from cache: ${graph.nodes.length} nodes for $destinationId');
      }
    }

    // 3. Last-ditch bundled fallback (Legacy)
    if (graph == null || graph.isEmpty) {
      try {
        final String jsonStr = await rootBundle.loadString('assets/trail_graph.json');
        final Map<String, dynamic> data = json.decode(jsonStr);
        graph = TrailGraph.fromJson(data);
        debugPrint('[Pathfinding] Graph loaded from bundled asset fallback');
      } catch (e) {
        debugPrint('[Pathfinding] Asset fallback failed: $e');
      }
    }

    if (graph == null || graph.isEmpty) {
      debugPrint('[Pathfinding] No trail graph for $destinationId — offline nav disabled');
      _graph = null;
      return;
    }

    _graph = graph;
    _loadedDestinationId = destinationId;
    _buildAdjacency(graph);
  }

  void _buildAdjacency(TrailGraph graph) {
    _nodes = {for (final n in graph.nodes) n.id: n};
    _adjacency = {};

    for (final edge in graph.edges) {
      _adjacency.putIfAbsent(edge.fromId, () => []).add(edge);
      // Bidirectional — reverse the offline path if it exists
      final List<Map<String, double>> reversedPath = edge.offlinePath
          .map((p) => <String, double>{'lat': p['lat']!, 'lng': p['lng']!})
          .toList()
          .reversed
          .toList();
          
      _adjacency.putIfAbsent(edge.toId, () => []).add(TrailEdge(
        fromId: edge.toId,
        toId: edge.fromId,
        weightMeters: edge.weightMeters,
        offlinePath: reversedPath,
      ));
    }
  }

  // ── Find route to nearest safe zone ──────────────────────────────────────

  NavigationResult findRouteToSafety({
    required double currentLat,
    required double currentLng,
  }) {
    if (!isLoaded) return NavigationResult.noGraph;

    final start = _nearestNode(currentLat, currentLng);
    if (start == null) return NavigationResult.noPath;

    if (start.zoneType == ZoneType.safe) {
      return NavigationResult(
        path: [start],
        offlineGeometries: [{'lat': start.lat, 'lng': start.lng}],
        totalDistanceMeters: 0,
        estimatedMinutes: 0,
        pathFound: true,
        message: 'You are already in a safe zone.',
      );
    }

    final safeNodes = _nodes.values
        .where((n) => n.zoneType == ZoneType.safe)
        .toList();
    if (safeNodes.isEmpty) return NavigationResult.noPath;

    final goal = _nearestAmong(start, safeNodes);
    final rawPath = _aStar(start.id, goal.id);
    if (rawPath == null) return NavigationResult.noPath;

    double totalDist = 0;
    final fullCurve = <Map<String, double>>[];

    if (rawPath.length == 1) {
      fullCurve.add({'lat': rawPath[0].lat, 'lng': rawPath[0].lng});
    }

    for (int i = 0; i < rawPath.length - 1; i++) {
      final from = rawPath[i];
      final to = rawPath[i + 1];
      final edges = _adjacency[from.id] ?? [];
      final edge = edges.where((e) => e.toId == to.id).firstOrNull;

      if (edge != null && edge.offlinePath.isNotEmpty) {
        for (final p in edge.offlinePath) {
          fullCurve.add({'lat': p['lat']!, 'lng': p['lng']!});
        }
      } else {
        if (i == 0) fullCurve.add({'lat': from.lat, 'lng': from.lng});
        fullCurve.add({'lat': to.lat, 'lng': to.lng});
      }

      totalDist += _haversineM(from.lat, from.lng, to.lat, to.lng);
    }

    final minutes = (totalDist / 1000 / 4.0 * 60).ceil();

    return NavigationResult(
      path: rawPath,
      offlineGeometries: fullCurve,
      totalDistanceMeters: totalDist,
      estimatedMinutes: minutes,
      pathFound: true,
      message: 'Head to ${goal.name}. ${totalDist.toStringAsFixed(0)}m, ~$minutes min.',
    );
  }

  // ── A* ────────────────────────────────────────────────────────────────────

  List<TrailNode>? _aStar(String startId, String goalId) {
    final goal = _nodes[goalId]!;
    final openSet = <String, _AStarNode>{};
    final closedSet = <String>{};

    openSet[startId] = _AStarNode(
      id: startId, gCost: 0,
      hCost: _haversineM(_nodes[startId]!.lat, _nodes[startId]!.lng, goal.lat, goal.lng),
    );

    while (openSet.isNotEmpty) {
      final current = openSet.values.reduce((a, b) => a.fCost < b.fCost ? a : b);

      if (current.id == goalId) return _reconstruct(current);

      openSet.remove(current.id);
      closedSet.add(current.id);

      for (final edge in _adjacency[current.id] ?? []) {
        if (closedSet.contains(edge.toId)) continue;
        final neighbour = _nodes[edge.toId];
        if (neighbour == null) continue;
        // Penalise restricted zones 3× to route around them
        final penalty = neighbour.zoneType == ZoneType.restricted ? 3.0 : 1.0;
        final newG = current.gCost + edge.weightMeters * penalty;
        final existing = openSet[edge.toId];
        if (existing == null || newG < existing.gCost) {
          openSet[edge.toId] = _AStarNode(
            id: edge.toId,
            gCost: newG,
            hCost: _haversineM(neighbour.lat, neighbour.lng, goal.lat, goal.lng),
            parent: current,
          );
        }
      }
    }
    return null;
  }

  List<TrailNode> _reconstruct(_AStarNode node) {
    final path = <TrailNode>[];
    _AStarNode? cur = node;
    while (cur != null) { path.add(_nodes[cur.id]!); cur = cur.parent; }
    return path.reversed.toList();
  }

  // ── Utilities ─────────────────────────────────────────────────────────────

  TrailNode? _nearestNode(double lat, double lng) {
    TrailNode? nearest;
    double min = double.infinity;
    for (final n in _nodes.values) {
      final d = _haversineM(lat, lng, n.lat, n.lng);
      if (d < min) { min = d; nearest = n; }
    }
    return nearest;
  }

  TrailNode _nearestAmong(TrailNode from, List<TrailNode> candidates) =>
      candidates.reduce((a, b) =>
          _haversineM(from.lat, from.lng, a.lat, a.lng) <
          _haversineM(from.lat, from.lng, b.lat, b.lng) ? a : b);

  double _haversineM(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _rad(double deg) => deg * pi / 180;

  Map<String, TrailNode> get nodes => Map.unmodifiable(_nodes);
}
