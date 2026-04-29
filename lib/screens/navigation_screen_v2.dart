import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:saferoute/utils/app_theme.dart';
import 'package:saferoute/providers/location_provider.dart';
import 'package:saferoute/providers/theme_provider.dart';
import 'package:saferoute/services/database_tile_provider.dart';
import 'package:saferoute/services/tile_downloader_service.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/location_ping_model.dart';
import 'package:saferoute/widgets/premium_widgets.dart';
import 'package:saferoute/screens/tactical_ar_screen.dart';
import 'package:saferoute/providers/navigation_provider.dart';
import 'dart:ui';

class NavigationScreenV2 extends StatefulWidget {
  const NavigationScreenV2({super.key});

  @override
  State<NavigationScreenV2> createState() => _NavigationScreenV2State();
}

class _NavigationScreenV2State extends State<NavigationScreenV2> {
  final MapController _mapController = MapController();
  final TileDownloaderService _downloader = TileDownloaderService();
  
  // Tracking active downloads: RegionKey -> Progress
  final Map<String, DownloadProgress> _activeDownloads = {};
  bool _showOfflinePacks = false;

  void _startDownload(String regionKey, String urlTemplate) {
    setState(() {
      _activeDownloads[regionKey] = DownloadProgress(regionName: regionKey, total: 100, downloaded: 0);
    });

    _downloader.downloadRegion(regionKey, urlTemplate: urlTemplate).listen((progress) {
      if (mounted) {
        setState(() {
          _activeDownloads[regionKey] = progress;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final locationProvider = context.watch<LocationProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final navProvider = context.watch<MainNavigationProvider>();
    final currentPos = locationProvider.currentPosition;
    final trail = locationProvider.trail;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Initial center if location is null
    final LatLng center = currentPos != null 
        ? LatLng(currentPos.latitude, currentPos.longitude) 
        : const LatLng(30.3165, 78.0322); // Dehradun fallback

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          // Tactical Map Layer
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 15.0,
              onTap: (_, __) => navProvider.setImmersive(!navProvider.isImmersive),
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: themeProvider.mapUrlTemplate,
                userAgentPackageName: 'com.shivalik.saferoute',
                tileProvider: DatabaseTileProvider(),
              ),
              
              // 1. Breadcrumb Trail (Neon Glow)
              if (trail.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: trail.map((p) => LatLng(p.latitude, p.longitude)).toList(),
                      color: AppColors.primaryHighContrast.withOpacity(0.3),
                      strokeWidth: 8.0,
                    ),
                    Polyline(
                      points: trail.map((p) => LatLng(p.latitude, p.longitude)).toList(),
                      color: AppColors.primaryHighContrast,
                      strokeWidth: 3.0,
                    ),
                  ],
                ),

              // 2. Current Position Marker (Animated Pulse + Speed HUD)
              if (currentPos != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(currentPos.latitude, currentPos.longitude),
                      width: 100,
                      height: 100,
                      child: PulseMarker(
                        color: AppColors.primaryHighContrast,
                        size: 16,
                        speed: currentPos.speed,
                        heading: currentPos.heading, // Pass Heading to Marker
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // Top Overlay (HUD) - Always Visible
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                EliteSurface(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  borderRadius: 30,
                  color: Colors.white.withOpacity(0.0001), // Near-total transparency as requested
                  blur: 25, 
                  child: Row(
                    children: [
                      const Icon(Icons.shield_rounded, size: 16, color: AppColors.accent),
                      const SizedBox(width: 8),
                      Text(
                        _getZoneName(locationProvider.zoneStatus),
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildMapDiagnostic(context),
              ],
            ),
          ),

          // Right Sidebar Actions - Always Visible
          Positioned(
            top: 150,
            right: 16,
            child: Column(
              children: [
                // MAP MODE SWITCHER (Issue #8 Fix)
                _buildMapAction(
                  icon: themeProvider.mapMode == MapMode.satellite 
                      ? Icons.map_rounded 
                      : Icons.satellite_alt_rounded,
                  label: themeProvider.mapMode == MapMode.satellite ? 'STD' : 'SAT',
                  onTap: () => themeProvider.toggleMapMode(),
                ),
                const SizedBox(height: 12),
                _buildMapAction(
                  icon: Icons.gps_fixed_rounded,
                  onTap: () {
                    if (currentPos != null) {
                      _mapController.move(LatLng(currentPos.latitude, currentPos.longitude), 16.0);
                    }
                  },
                ),
                const SizedBox(height: 12),
                _buildMapAction(
                  icon: Icons.history_rounded,
                  onTap: () {
                    if (trail.isNotEmpty) {
                      final bounds = LatLngBounds.fromPoints(
                        trail.map((e) => LatLng(e.latitude, e.longitude)).toList()
                      );
                      _mapController.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(80)));
                    }
                  },
                ),
                const SizedBox(height: 12),
                _buildMapAction(
                  icon: Icons.download_for_offline,
                  label: 'OFFLINE',
                  onTap: () => setState(() => _showOfflinePacks = !_showOfflinePacks),
                ),
                const SizedBox(height: 12),
                _buildMapAction(
                  icon: Icons.view_in_ar_rounded,
                  label: 'AR VIEW',
                  onTap: () {
                    HapticFeedback.heavyImpact();
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const TacticalARScreen()),
                    );
                  },
                ),
              ],
            ),
          ),

          // Bottom Telemetry HUD - Always Visible
          Positioned(
            bottom: 40,
            left: 16,
            right: 16,
            child: _buildTelemetryHUD(locationProvider),
          ),

          // Speedometer HUD (Floating) - Always Visible
          Positioned(
            bottom: 40,
            left: 24,
            child: EliteSpeedometer(
              speed: currentPos?.speed ?? 0,
              isDark: isDark,
            ),
          ),

          // Offline Mission Control Panel (Animated)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOutCubic,
            bottom: _showOfflinePacks ? 0 : -350,
            left: 0,
            right: 0,
            child: EliteSurface(
              borderRadius: 30,
              blur: 40,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'OFFLINE MISSION PACKS',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                              fontSize: 12,
                              color: themeProvider.mapMode == MapMode.satellite ? Colors.white : AppColors.primary,
                            ),
                          ),
                          const Text('Himalayan Dead-Zone Assets', style: TextStyle(fontSize: 10, color: Colors.grey)),
                        ],
                      ),
                      IconButton(
                        onPressed: () => setState(() => _showOfflinePacks = false),
                        icon: const Icon(Icons.keyboard_arrow_down),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Kedarnath Pack
                  OfflinePackCard(
                    title: 'Kedarnath Basin',
                    subtitle: 'Glacial terrain, GPS Level 16 detail',
                    regionKey: 'KEDARNATH',
                    progress: _activeDownloads['KEDARNATH']?.progress ?? 0.0,
                    isDownloading: _activeDownloads['KEDARNATH'] != null && !_activeDownloads['KEDARNATH']!.isComplete,
                    onDownload: () => _startDownload('KEDARNATH', themeProvider.mapUrlTemplate),
                  ),
                  const SizedBox(height: 12),
                  // Tungnath Pack
                  OfflinePackCard(
                    title: 'Tungnath Sanctuary',
                    subtitle: 'Alpine meadows, GPS Level 16 detail',
                    regionKey: 'TUNGNATH',
                    progress: _activeDownloads['TUNGNATH']?.progress ?? 0.0,
                    isDownloading: _activeDownloads['TUNGNATH'] != null && !_activeDownloads['TUNGNATH']!.isComplete,
                    onDownload: () => _startDownload('TUNGNATH', themeProvider.mapUrlTemplate),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapAction({required IconData icon, String? label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      child: Column(
        children: [
          EliteSurface(
            padding: EdgeInsets.zero,
            width: 50,
            height: 50,
            borderRadius: 25,
            color: AppColors.primary.withOpacity(0.8),
            borderColor: Colors.white24,
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          if (label != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                label,
                style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTelemetryHUD(LocationProvider loc) {
    final pos = loc.currentPosition;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return EliteSurface(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildTelemetryItem('ALTITUDE', '${pos?.altitude.toStringAsFixed(0) ?? "---"} m', Icons.landscape_rounded, isDark),
          const VerticalDivider(width: 30),
          _buildTelemetryItem('SPEED', '${((pos?.speed ?? 0) * 3.6).toStringAsFixed(1)} KM/H', Icons.speed_rounded, isDark),
          const VerticalDivider(width: 30),
          _buildTelemetryItem('HEADING', '${pos?.heading.toStringAsFixed(0) ?? "---"}°', Icons.explore_rounded, isDark),
        ],
      ),
    );
  }

  Widget _buildTelemetryItem(String label, String value, IconData icon, bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.accent),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 14,
          fontFamily: 'monospace',
          color: isDark ? Colors.white : Colors.black87,
        )),
        Text(label, style: TextStyle(
          fontSize: 8, 
          letterSpacing: 1,
          color: isDark ? Colors.white38 : Colors.black54,
        )),
      ],
    );
  }

  String _getZoneName(ZoneType type) {
    switch (type) {
      case ZoneType.red: return "HIGH RISK";
      case ZoneType.yellow: return "CAUTION";
      case ZoneType.greenInner:
      case ZoneType.greenOuter: return "SECURE";
      default: return "SCANNING";
    }
  }

  Widget _buildMapDiagnostic(BuildContext context) {
    return FutureBuilder<int>(
      future: DatabaseTileProvider().getTileCount(),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        final bool isOfflineReady = count > 0;

        return EliteSurface(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          borderRadius: 20,
          color: isOfflineReady ? AppColors.success.withOpacity(0.2) : AppColors.warning.withOpacity(0.2),
          borderColor: isOfflineReady ? AppColors.success : AppColors.warning,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isOfflineReady ? Icons.offline_pin_rounded : Icons.cloud_queue_rounded,
                size: 14,
                color: isOfflineReady ? AppColors.success : AppColors.warning,
              ),
              const SizedBox(width: 6),
              Text(
                isOfflineReady ? 'LOCAL: $count' : 'CLOUDSYNC',
                style: TextStyle(
                  color: isOfflineReady ? AppColors.success : AppColors.warning, 
                  fontSize: 10, 
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
