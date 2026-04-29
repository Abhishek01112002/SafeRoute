// lib/screens/navigation_screen.dart
// ══════════════════════════════════════════════════════════════
// SAFEROUTE — ADAPTIVE SMART NAVIGATION (AERO EDITION)
// ══════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart'; 
import 'package:flutter/services.dart'; 
import 'package:provider/provider.dart';
import '../providers/location_provider.dart';
import '../services/database_service.dart';
import '../services/pathfinding_service.dart';
import '../models/location_ping_model.dart';
import '../services/database_tile_provider.dart';
import '../utils/app_theme.dart';
import '../widgets/premium_widgets.dart';
import '../providers/tourist_provider.dart';
import 'tactical_ar_screen.dart';

enum _NavMode { detecting, online, offline }

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final MapController _mapController = MapController();
  final PathfindingService _pathfinder = PathfindingService();

  _NavMode _mode = _NavMode.detecting;
  Position? _currentPosition;
  NavigationResult? _navResult;
  List<LatLng>? _routePoints; 

  bool _isLoading = true;
  bool _isNavigating = false;
  bool _followUser = true;

  StreamSubscription<Position>? _positionSub;
  StreamSubscription<ConnectivityResult>? _connectivitySub;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  ZoneType _lastAlertedZone = ZoneType.none;
  Color _tintColor = Colors.transparent;
  double _tintOpacity = 0.0;
  String? _statusLabel;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _pulseAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOutCirc),
    );

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
    if (!mounted) return;
    String msg = "";
    Color color = Colors.black;

    if (z == ZoneType.red) {
      msg = "⚠️ RESTRICTED AREA DETECTED";
      color = AppColors.zoneRed;
      HapticFeedback.heavyImpact();
    } else if (z == ZoneType.yellow) {
      msg = "⚠️ ELEVATED RISK ZONE";
      color = AppColors.zoneYellow;
      HapticFeedback.mediumImpact();
    } else if (z == ZoneType.greenInner || z == ZoneType.greenOuter) {
      msg = "✅ SECURE PERIMETER REACHED";
      color = AppColors.zoneGreen;
      HapticFeedback.lightImpact();
    } else return;

    setState(() {
      _tintColor = color;
      _tintOpacity = 0.12;
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _tintOpacity = 0.0);
    });

    _showStatusLabel(msg);

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg.toUpperCase(),
          style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 10, letterSpacing: 1.5)),
      backgroundColor: color.withOpacity(0.9),
      behavior: SnackBarBehavior.floating,
      elevation: 30,
      margin: const EdgeInsets.fromLTRB(AppSpacing.m, 0, AppSpacing.m, 160),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusS)),
      duration: const Duration(seconds: 4),
    ));
  }

  void _showStatusLabel(String text) {
     _statusTimer?.cancel();
     setState(() => _statusLabel = text);
     _statusTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _statusLabel = null);
     });
  }

  Future<void> _initialize() async {
    await _detectAndSetMode();
    await _updatePosition();
    _setupGpsStream();
    setState(() => _isLoading = false);
    
    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      _detectAndSetMode();
    });
  }

  void _setupGpsStream() {
    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 2),
    ).listen((pos) {
      if (!mounted) return;
      if (pos.accuracy > 50) return; 

      setState(() => _currentPosition = pos);
      
      if (_followUser) {
        _mapController.move(LatLng(pos.latitude, pos.longitude), 17.5);
      }
    });
  }

  Future<void> _updatePosition() async {
    try {
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (!mounted) return;
      setState(() => _currentPosition = pos);
    } catch (e) {
      debugPrint('[Nav] GPS error: $e');
    }
  }

  Future<void> _detectAndSetMode() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    setState(() {
      _mode = (connectivityResult == ConnectivityResult.none) ? _NavMode.offline : _NavMode.online;
    });
  }

  Future<void> _findSafeRoute() async {
    if (_currentPosition == null) return;
    setState(() => _isNavigating = true);

    final result = _pathfinder.findRouteToSafety(
      currentLat: _currentPosition!.latitude,
      currentLng: _currentPosition!.longitude,
    );

    if (result.pathFound && result.path.isNotEmpty) {
      final goalNode = result.path.last;
      List<LatLng> points = [
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        ...result.offlineGeometries.map((c) => LatLng(c['lat']!, c['lng']!))
      ];

      if (_mode == _NavMode.online) {
        try {
          final dio = Dio();
          final url = 'http://router.project-osrm.org/route/v1/foot/'
              '${_currentPosition!.longitude},${_currentPosition!.latitude};'
              '${goalNode.lng},${goalNode.lat}?overview=full&geometries=geojson';
          
          final response = await dio.get(url, options: Options(receiveTimeout: const Duration(seconds: 5)));
          if (response.statusCode == 200) {
            final coords = response.data['routes'][0]['geometry']['coordinates'] as List;
            points = coords.map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
          }
        } catch (e) {
          debugPrint('OSRM fallback to A*: $e');
        }
      }

      if (!mounted) return;
      setState(() {
        _navResult = result;
        _routePoints = points;
        _isNavigating = false;
        _followUser = false;
      });

      _mapController.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.all(70),
        maxZoom: 17.5,
      ));
    } else {
      if (!mounted) return;
      setState(() => _isNavigating = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseCtrl.dispose();
    _positionSub?.cancel();
    _connectivitySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isSosActive = context.watch<LocationProvider>().isSosActive;

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // ── Map Layer (The World) ───────────────────────────────────
          RepaintBoundary(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentPosition != null 
                    ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude) 
                    : const LatLng(30.3367, 78.0273),
                initialZoom: 17.0,
                maxZoom: 18.5,
                onMapEvent: (e) {
                  if ((e is MapEventScrollWheelZoom || e is MapEventMove) && e.source != MapEventSource.mapController) {
                    setState(() => _followUser = false);
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://mt1.google.com/vt/lyrs=$_mapType&x={x}&y={y}&z={z}', 
                  userAgentPackageName: 'com.saferoute.app',
                  tileProvider: DatabaseTileProvider(),
                ),
                
                // ── Routes & Zones ────────────────────────────────────────
                _buildZonesLayer(),
                
                if (_routePoints != null)
                   PolylineLayer(
                     polylines: [
                       Polyline(points: _routePoints!, strokeWidth: 8, color: theme.colorScheme.primary.withOpacity(0.3)),
                       Polyline(points: _routePoints!, strokeWidth: 3, color: theme.colorScheme.primary),
                     ],
                   ),

                // ── Dynamic Markers ───────────────────────────────────────
                _buildMarkersLayer(),
              ],
            ),
          ),

          // ── Zone Tint Overlay (Emotional UI) ────────────────────────
          IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              color: _tintColor.withOpacity(_tintOpacity),
            ),
          ),

          // ── HUD Elements ──────────────────────────────────────────
          _buildTopHud(),
          _buildRightControls(),
          
          if (_navResult != null && !isSosActive)
            Positioned(top: 100, left: AppSpacing.m, right: 80, child: _buildResultCard()),

          if (isSosActive) _buildSosHud(),

          if (_statusLabel != null)
            Positioned(top: 180, left: 0, right: 0, child: Center(child: EliteSurface(child: Text(_statusLabel!.toUpperCase(), style: const TextStyle(color: AppColors.accent, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 2))))),

          Align(alignment: Alignment.bottomCenter, child: _buildActionPanel()),

          if (_isLoading) _buildOnboardingLoader(),
        ],
      ),
    );
  }

  Widget _buildTopHud() {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: Container(
        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + AppSpacing.s, left: AppSpacing.m, right: AppSpacing.m, bottom: AppSpacing.m),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withOpacity(0.7), Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            _buildModeChip(),
            const Spacer(),
            EliteSurface(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.satellite_alt_rounded, size: 14, color: AppColors.accent),
                  const SizedBox(width: 6),
                  Text("PRECISION GPS", style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeChip() {
    final isOnline = _mode == _NavMode.online;
    return EliteSurface(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: isOnline ? AppColors.zoneGreen : AppColors.zoneYellow)),
          const SizedBox(width: 8),
          Text(isOnline ? "HYBRID ONLINE" : "OFFLINE ENGINE", style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)),
        ],
      ),
    );
  }

  Widget _buildRightControls() {
    return Positioned(
      right: AppSpacing.m,
      top: MediaQuery.of(context).padding.top + 80,
      child: Column(
        children: [
          _mapActionBtn(
            icon: _followUser ? Icons.my_location_rounded : Icons.location_searching_rounded, 
            active: _followUser, 
            onTap: () {
              setState(() => _followUser = true);
              if (_currentPosition != null) _mapController.move(LatLng(_currentPosition!.latitude, _currentPosition!.longitude), 17.5);
            }
          ),
          const SizedBox(height: AppSpacing.m),
          _mapActionBtn(
            icon: Icons.layers_rounded, 
            active: false, 
            onTap: _showMapTypeSelector
          ),
          const SizedBox(height: AppSpacing.m),
          _mapActionBtn(
            icon: Icons.view_in_ar_rounded, 
            active: false, 
            onTap: () {
              LatLng? target;
              if (_routePoints != null && _routePoints!.isNotEmpty) {
                target = _routePoints!.last;
              }
              Navigator.push(context, MaterialPageRoute(builder: (context) => TacticalARScreen(targetDestination: target)));
            }
          ),
        ],
      ),
    );
  }

  void _showMapTypeSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => EliteSurface(
        margin: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("MAP DISPLAY MODE", style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 2)),
            const SizedBox(height: AppSpacing.l),
            _mapTypeOption("SATELLITE HYBRID", Icons.layers_rounded, 'y', true),
            const SizedBox(height: AppSpacing.m),
            _mapTypeOption("TERRAIN VIEW", Icons.terrain_rounded, 'p', false),
            const SizedBox(height: AppSpacing.m),
            _mapTypeOption("STANDARD VECTOR", Icons.map_rounded, 'm', false),
          ],
        ),
      ),
    );
  }

  String _mapType = 'y';
  Widget _mapTypeOption(String label, IconData icon, String type, bool active) {
    bool isSelected = _mapType == type;
    return EliteButton(
      onPressed: () {
        setState(() => _mapType = type);
        Navigator.pop(context);
      },
      color: isSelected ? AppColors.primary : Colors.white.withOpacity(0.05),
      child: Row(
        children: [
          Icon(icon, size: 20, color: isSelected ? Colors.white : Colors.white60),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _mapActionBtn({required IconData icon, required bool active, required VoidCallback onTap}) {
    return EliteSurface(
      padding: EdgeInsets.zero, width: 48, height: 48,
      child: IconButton(
        icon: Icon(icon, color: active ? AppColors.primary : Colors.white60, size: 20),
        onPressed: onTap,
      ),
    );
  }

  Widget _buildActionPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.m, 0, AppSpacing.m, 110),
      child: EliteSurface(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EliteButton(
              onPressed: _isNavigating ? null : _findSafeRoute,
              child: _isNavigating 
                ? const GlimmerLoader(width: 40, height: 4)
                : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.shield_rounded, size: 18), SizedBox(width: 8), Text("RETRACE TO SAFETY")]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    return EliteSurface(
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.navigation_rounded, color: AppColors.accent, size: 16),
              const SizedBox(width: 8),
              Text("${(_navResult!.totalDistanceMeters / 1000).toStringAsFixed(1)} KM", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
              const Spacer(),
              Text("${_navResult!.estimatedMinutes} MIN", style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w900, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSosHud() {
    return Positioned(
      top: 100, left: AppSpacing.m, right: AppSpacing.m,
      child: EliteSurface(
        color: AppColors.zoneRed.withOpacity(0.9),
        child: Row(
          children: [
            const Icon(Icons.broadcast_on_personal_rounded, color: Colors.white, size: 24),
            const SizedBox(width: AppSpacing.m),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("SOS BROADCAST ACTIVE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11)), Text("RESCUE CENTERS MONITORING...", style: TextStyle(color: Colors.white70, fontSize: 8))])),
            IconButton(onPressed: () => context.read<LocationProvider>().setSosActive(false), icon: const Icon(Icons.close_rounded, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _buildOnboardingLoader() {
    return Container(
      color: AppColors.backgroundDark,
      child: const Center(child: GlimmerLoader(width: 250, height: 2)),
    );
  }

  // ── Layers ────────────────────────────────────────────────────

  Widget _buildZonesLayer() {
     return PolygonLayer(
       polygons: [
         // Placeholder for real zones from DB
         Polygon(
           points: const [LatLng(30.3369, 77.8696), LatLng(30.3367, 77.8702), LatLng(30.3345, 77.8709), LatLng(30.3355, 77.8684)],
           color: AppColors.zoneGreen.withOpacity(0.1),
           borderColor: AppColors.zoneGreen.withOpacity(0.4),
           borderStrokeWidth: 2,
         ),
       ],
     );
  }

  Widget _buildMarkersLayer() {
    final tourist = context.watch<TouristProvider>().tourist;
    return MarkerLayer(
      markers: [
        if (_currentPosition != null)
          Marker(
            point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
            width: 100, height: 100,
            child: _UserMarker(
              heading: _currentPosition!.heading,
              pulse: _pulseAnim,
            ),
          ),
      ],
    );
  }
}

// ── Aero Widgets ───────────────────────────────────────────────

class _UserMarker extends StatelessWidget {
  final double heading;
  final Animation<double> pulse;

  const _UserMarker({required this.heading, required this.pulse});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Aura Wave
            Opacity(
              opacity: 1 - pulse.value,
              child: Container(
                width: 60 * pulse.value, height: 60 * pulse.value,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.primary, width: 2)),
              ),
            ),
            
            // Directional Shield
            Transform.rotate(
              angle: heading * (3.14159 / 180),
              child: ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(colors: [AppColors.primary, AppColors.accent]).createShader(bounds),
                child: const Icon(Icons.navigation_rounded, color: Colors.white, size: 32),
              ),
            ),

            // Inner Crystal
            Container(
              width: 14, height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle, color: Colors.white,
                boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.8), blurRadius: 10, spreadRadius: 2)],
              ),
            ),
          ],
        );
      },
    );
  }
}
