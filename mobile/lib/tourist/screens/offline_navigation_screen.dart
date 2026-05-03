// lib/tourist/screens/offline_navigation_screen.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:saferoute/tourist/providers/location_provider.dart';
import 'package:saferoute/services/database_tile_provider.dart';
import 'package:saferoute/services/pathfinding_service.dart';
import 'package:saferoute/core/models/location_ping_model.dart';
import 'package:saferoute/core/models/zone_model.dart';
import 'package:saferoute/core/service_locator.dart';

class OfflineNavigationScreen extends StatefulWidget {
  const OfflineNavigationScreen({super.key});

  @override
  State<OfflineNavigationScreen> createState() =>
      _OfflineNavigationScreenState();
}

class _OfflineNavigationScreenState extends State<OfflineNavigationScreen>
    with TickerProviderStateMixin {
  final PathfindingService _pathfinder = locator<PathfindingService>();
  final MapController _mapController = MapController();

  Position? _currentPosition;
  NavigationResult? _navResult;
  bool _isLoading = true;
  bool _isNavigating = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // The fallback mock location directly on a trail node for hackathon indoor demo
  static const double _mockLat = 30.3365;
  static const double _mockLng = 77.8690;

  ZoneType _lastAlertedZone = ZoneType.safe;

  @override
  void initState() {
    super.initState();
    _pulseController =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.2, end: 1.0).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));

    _initialize();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prov = context.read<LocationProvider>();
      _lastAlertedZone = prov.zoneStatus;
      prov.addListener(_onZoneChangeAlert);
    });
  }

  void _onZoneChangeAlert() {
    if (!mounted) return;
    final prov = context.read<LocationProvider>();
    if (prov.zoneStatus != _lastAlertedZone) {
      _lastAlertedZone = prov.zoneStatus;
      _showZoneSnackbar(_lastAlertedZone);
    }
  }

  void _showZoneSnackbar(ZoneType z) {
    // DEFAULT-SAFE: Only alert on danger zone entries.
    // Safe is the silent norm — no snackbar needed.
    String msg;
    switch (z) {
      case ZoneType.restricted:
        msg = "🚨 DANGER: You entered a Restricted Zone";
        break;
      case ZoneType.caution:
        msg = "⚠️ CAUTION: You entered a moderate-risk area";
        break;
      case ZoneType.safe:
      case ZoneType.syncing:
        return; // Silent — safe is the default
    }

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(
              fontWeight: FontWeight.bold, color: Colors.white)),
      backgroundColor: const Color(0xFF1B2332),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 3),
    ));
  }

  Future<void> _initialize() async {
    debugPrint('[Offline] Starting Initialization...');

    // 1. Load graph in background
    Future.microtask(() async {
      await _pathfinder.loadForDestination('demo_dest_id');
      debugPrint('[Offline] Graph loaded.');
    });

    // 2. Ready to show map core immediately
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }

    // 3. Get location with timeout
    await _getLocation();
  }

  Future<void> _getLocation() async {
    debugPrint('[Offline] Requesting initial lock (3s timeout)...');
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 3));

      if (mounted) {
        setState(() {
          _currentPosition = position;
        });
        _mapController.move(
            LatLng(position.latitude, position.longitude), 16.0);
        debugPrint('[Offline] Position locked.');
      }
    } catch (e) {
      debugPrint('[Offline] GPS Lock failed or timeout. Using Mock Engine.');
      if (mounted) {
        setState(() {
          _currentPosition = Position(
            longitude: _mockLng,
            latitude: _mockLat,
            timestamp: DateTime.now(),
            accuracy: 1.0,
            altitude: 0.0,
            altitudeAccuracy: 1.0,
            heading: 0.0,
            headingAccuracy: 1.0,
            speed: 0.0,
            speedAccuracy: 1.0,
          );
        });
        _mapController.move(const LatLng(_mockLat, _mockLng), 16.0);
      }
    }
  }

  void _findSafeRoute() {
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Awaiting GPS Array...")));
      return;
    }

    setState(() {
      _isNavigating = true;
      _navResult = null; // Clear old
    });

    final result = _pathfinder.findRouteToSafety(
      currentLat: _currentPosition!.latitude,
      currentLng: _currentPosition!.longitude,
    );

    setState(() {
      _navResult = result;
      _isNavigating = false;
    });

    if (result.pathFound && result.offlineGeometries.isNotEmpty) {
      final points = result.offlineGeometries
          .map((n) => LatLng(n['lat']!, n['lng']!))
          .toList();
      try {
        _mapController.fitCamera(CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(80),
        ));
      } catch (e) {
        debugPrint("Map fit error: $e");
      }
    }
  }

  /// DEFAULT-SAFE BACKTRACK: Retrace breadcrumbs until we leave the
  /// danger zone boundary. Uses geofencing engine for real boundary
  /// detection instead of relying on stored zone status of breadcrumbs.
  void _findSafeBacktrack() {
    final locProv = context.read<LocationProvider>();
    if (locProv.trail.isEmpty) return;

    setState(() => _isNavigating = true);

    List<LatLng> reversePath = [];
    bool exitedDanger = false;

    for (var dot in locProv.trail.reversed) {
      final point = LatLng(dot.latitude, dot.longitude);
      reversePath.add(point);

      // Boundary detection: check if this breadcrumb is outside all
      // active danger zones using the geofencing engine.
      if (!locProv.geofencing.isPointInDangerZone(point)) {
        exitedDanger = true;
        break;
      }
    }

    if (reversePath.length > 1) {
      const distance = Distance();
      double totalDist = 0;
      for (int i = 0; i < reversePath.length - 1; i++) {
        totalDist += distance(reversePath[i], reversePath[i + 1]);
      }

      setState(() {
        _isNavigating = false;
        _navResult = NavigationResult(
          path: [],
          offlineGeometries: reversePath
              .map((e) => {'lat': e.latitude, 'lng': e.longitude})
              .toList(),
          totalDistanceMeters: totalDist,
          estimatedMinutes: (totalDist / 1000 / 4.0 * 60).ceil(),
          pathFound: true,
          message: exitedDanger
              ? "Follow glowing footprints to safety."
              : "Retrace your path — stay alert.",
        );
      });

      try {
        _mapController.fitCamera(CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(reversePath),
          padding: const EdgeInsets.all(80),
        ));
      } catch (e) {
        // ignore
      }
    } else {
      setState(() => _isNavigating = false);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B14), // Deep tactical black/navy
      appBar: AppBar(
        title: const Text("Tactical Offline Radar",
            style: TextStyle(
                fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 18)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        foregroundColor: Colors.white,
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Tactical Map Radar Base
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
                initialCenter: LatLng(_mockLat, _mockLng),
                initialZoom: 15.0,
                minZoom: 5.0,
                maxZoom: 18.0,
                backgroundColor: Color(0xFF070B14)),
            children: [
              // Standard OSM Fallback (even if offline, it handles the "No Internet" UI better)
              TileLayer(
                urlTemplate:
                    'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}',
                userAgentPackageName: 'com.shivalik.saferoute',
                tileProvider: DatabaseTileProvider(), // PERSISTENT CACHE
              ),

              // 1. Radar Grid Circles Base
              if (_currentPosition != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: LatLng(_currentPosition!.latitude,
                          _currentPosition!.longitude),
                      color: Colors.transparent,
                      borderColor: const Color(0xFF00D4AA).withOpacity(0.05),
                      borderStrokeWidth: 2,
                      radius: 300,
                      useRadiusInMeter: true,
                    ),
                    CircleMarker(
                      point: LatLng(_currentPosition!.latitude,
                          _currentPosition!.longitude),
                      color: Colors.transparent,
                      borderColor: const Color(0xFF00D4AA).withOpacity(0.1),
                      borderStrokeWidth: 2,
                      radius: 800,
                      useRadiusInMeter: true,
                    ),
                  ],
                ),

              // ── FAANG Decoupled Trail (Consumer restricts rebuild memory) ──
              Consumer<LocationProvider>(
                builder: (context, locProv, child) {
                  final trail = locProv.trail;
                  if (trail.isEmpty) return const SizedBox.shrink();

                  return CircleLayer(
                    circles: List.generate(trail.length, (i) {
                      final p = trail[i];
                      // DEFAULT-SAFE: Trail dot colors
                      Color c;
                      switch (p.zoneStatus) {
                        case ZoneType.restricted:
                          c = Colors.redAccent;
                          break;
                        case ZoneType.caution:
                          c = Colors.amberAccent;
                          break;
                        case ZoneType.safe:
                          c = const Color(0xFF00D4AA); // Teal — safe default
                          break;
                        case ZoneType.syncing:
                          c = Colors.blueGrey;
                          break;
                      }

                      // Fade effect logic
                      double op = ((i + 1) / trail.length).clamp(0.2, 1.0);

                      return CircleMarker(
                        point: LatLng(p.latitude, p.longitude),
                        color: c.withOpacity(op),
                        borderColor: Colors.black.withOpacity(op * 0.5),
                        borderStrokeWidth: 1.0,
                        radius: 5.0, // Crisp dots
                        useRadiusInMeter: false,
                      );
                    }),
                  );
                },
              ),

              // ── Entry Point Markers ──
              Consumer<LocationProvider>(builder: (context, locProv, child) {
                final trail = locProv.trail;
                if (trail.isEmpty) return const SizedBox.shrink();

                final markers = <Marker>[];
                ZoneType? prevZ;

                for (int i = 0; i < trail.length; i++) {
                  final p = trail[i];
                  final z = p.zoneStatus;

                  // Only show transition markers for danger zone entries
                  if (prevZ != null && prevZ != z && z.isDanger) {
                    Color c = Colors.grey;
                    IconData ic = Icons.location_on;
                    switch (z) {
                      case ZoneType.restricted:
                        c = Colors.redAccent;
                        ic = Icons.warning_rounded;
                        break;
                      case ZoneType.caution:
                        c = Colors.amberAccent;
                        ic = Icons.error_outline;
                        break;
                      default:
                        break; // safe/syncing — no markers
                    }

                    markers.add(Marker(
                      point: LatLng(p.latitude, p.longitude),
                      width: 34,
                      height: 34,
                      child: Icon(ic, color: c, size: 30, shadows: const [
                        Shadow(color: Colors.black, blurRadius: 4)
                      ]),
                    ));
                  }
                  prevZ = z;
                }
                return MarkerLayer(markers: markers);
              }),

              // 2. Extracted Polylines drawn dynamically via offlineGeometries curves
              if (_navResult != null && _navResult!.pathFound)
                PolylineLayer(
                  polylines: [
                    // Outer neon glow
                    Polyline(
                      points: _navResult!.offlineGeometries
                          .map((n) => LatLng(n['lat']!, n['lng']!))
                          .toList(),
                      color: const Color(0xFF00D4AA).withOpacity(0.3),
                      strokeWidth: 14,
                    ),
                    // Inner dense line
                    Polyline(
                      points: _navResult!.offlineGeometries
                          .map((n) => LatLng(n['lat']!, n['lng']!))
                          .toList(),
                      color: const Color(0xFF00D4AA),
                      strokeWidth: 6,
                      isDotted: false,
                    ),
                  ],
                ),

              // ZONE POLYGONS — DEFAULT-SAFE MODEL
              // Only DANGER zones (caution + restricted) are rendered.
              // No green zone polygons — everywhere else is implicitly safe.
              PolygonLayer(
                polygons: [
                  // CAUTION ZONE (Moderate Risk — Yellow)
                  Polygon(
                    points: const [
                      LatLng(30.3371500, 77.8692639),
                      LatLng(30.3369583, 77.8696472),
                      LatLng(30.3366222, 77.8693694),
                      LatLng(30.3362750, 77.8690833),
                      LatLng(30.3364694, 77.8688333),
                      LatLng(30.3365111, 77.8685583),
                      LatLng(30.3371500, 77.8692639),
                    ],
                    isFilled: true,
                    color: Colors.yellow.withOpacity(0.20),
                    borderColor: Colors.orange,
                    borderStrokeWidth: 2.0,
                  ),

                  // RESTRICTED ZONE (High Risk — Red)
                  Polygon(
                    points: const [
                      LatLng(30.3367222, 77.8681639),
                      LatLng(30.3365111, 77.8685583),
                      LatLng(30.3361194, 77.8689889),
                      LatLng(30.3355472, 77.8684444),
                      LatLng(30.3358361, 77.8679139),
                      LatLng(30.3363389, 77.8678833),
                      LatLng(30.3367222, 77.8681639),
                    ],
                    isFilled: true,
                    color: Colors.red.withOpacity(0.20),
                    borderColor: Colors.red,
                    borderStrokeWidth: 2.5,
                  ),
                ],
              ),

              // 3. Mathematical topological markers
              MarkerLayer(
                markers: [
                  ..._pathfinder.nodes.values.map((node) => Marker(
                        width: 20,
                        height: 20,
                        point: LatLng(node.lat, node.lng),
                        child: Container(
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              // DEFAULT-SAFE node colors
                              color: node.zoneType == ZoneType.restricted
                                  ? Colors.redAccent.withOpacity(0.4)
                                  : node.zoneType == ZoneType.caution
                                      ? Colors.orangeAccent.withOpacity(0.4)
                                      : const Color(0xFF00D4AA).withOpacity(0.3),
                              border: Border.all(
                                color: node.zoneType == ZoneType.restricted
                                    ? Colors.redAccent
                                    : node.zoneType == ZoneType.caution
                                        ? Colors.orangeAccent
                                        : const Color(0xFF00D4AA),
                                width: 1.5,
                              )),
                        ),
                      )),

                  // GPS Tracker Node
                  if (_currentPosition != null)
                    Marker(
                      width: 60,
                      height: 60,
                      point: LatLng(_currentPosition!.latitude,
                          _currentPosition!.longitude),
                      child: AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) => Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 60 * _pulseAnimation.value,
                              height: 60 * _pulseAnimation.value,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF00D4AA).withOpacity(
                                    0.4 * (1.0 - _pulseAnimation.value)),
                              ),
                            ),
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                  color: const Color(0xFF00D4AA),
                                  shape: BoxShape.circle,
                                  border:
                                      Border.all(color: Colors.white, width: 2),
                                  boxShadow: const [
                                    BoxShadow(
                                        color: Color(0xFF00D4AA),
                                        blurRadius: 8,
                                        spreadRadius: 2)
                                  ]),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),

          if (_isLoading) ...[
            Container(color: const Color(0xFF070B14)),
            const Center(
                child: CircularProgressIndicator(color: Color(0xFF00D4AA))),
          ],

          // HUD for Offline Status
          Positioned(
            top: 50,
            left: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.8),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                children: [
                  Icon(Icons.wifi_off, color: Colors.white, size: 14),
                  SizedBox(width: 6),
                  Text("OFFLINE MODE — RADAR ACTIVE",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),

          // Premium Glassmorphic Control Panel
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_navResult != null && _navResult!.pathFound) ...[
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Distance",
                                    style: TextStyle(
                                        color: Colors.white54, fontSize: 12)),
                                Text(
                                    "\${_navResult!.totalDistanceMeters.toStringAsFixed(0)}M",
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text("ETA",
                                    style: TextStyle(
                                        color: Colors.white54, fontSize: 12)),
                                Text("\${_navResult!.estimatedMinutes} MIN",
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton(
                          onPressed: _isNavigating ? null : _findSafeRoute,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00D4AA),
                            foregroundColor: Colors.black,
                            elevation: 8,
                            shadowColor:
                                const Color(0xFF00D4AA).withOpacity(0.5),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _isNavigating
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                      color: Colors.black, strokeWidth: 2))
                              : const Text(
                                  "ENGAGE SAFE ROUTE",
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.5),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton(
                          onPressed: _isNavigating ? null : _findSafeBacktrack,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            elevation: 8,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text(
                            "RETRACE TO SAFETY",
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
