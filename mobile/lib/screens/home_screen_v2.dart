// lib/screens/home_screen_v2.dart
// Production-grade Home Screen with card-based layout and premium components
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:saferoute/utils/app_theme.dart';
import 'package:saferoute/widgets/premium_widgets.dart';
import 'package:saferoute/providers/tourist_provider.dart';
import 'package:saferoute/providers/location_provider.dart';
import 'package:saferoute/providers/theme_provider.dart';
import 'package:saferoute/providers/navigation_provider.dart';
import 'package:saferoute/providers/safety_system_provider.dart';
import 'package:saferoute/mesh/providers/mesh_provider.dart';
import 'package:saferoute/widgets/zone_status_card.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/location_ping_model.dart';
import 'package:saferoute/services/database_tile_provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:saferoute/screens/tactical_ar_screen.dart';
import 'package:saferoute/services/safety_engine.dart';
import 'dart:ui';

class HomeScreenV2 extends StatelessWidget {
  const HomeScreenV2({super.key});

  @override
  Widget build(BuildContext context) {
    final tourist = context.watch<TouristProvider>().tourist;
    
    if (tourist == null) {
      return const _LoadingHomeState();
    }

    return const Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          AuroraBackground(),
          _HomeContent(),
        ],
      ),
    );
  }
}

class _HomeContent extends StatefulWidget {
  const _HomeContent();

  @override
  State<_HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<_HomeContent> with SingleTickerProviderStateMixin {
  late AnimationController _staggerCtrl;
  
  @override
  void initState() {
    super.initState();
    _staggerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
  }

  @override
  void dispose() {
    _staggerCtrl.dispose();
    super.dispose();
  }

  Animation<double> _step(double index) {
    final start = (index * 0.1).clamp(0.0, 0.4);
    final end = (start + 0.6).clamp(0.0, 1.0);
    return CurvedAnimation(
      parent: _staggerCtrl,
      curve: Interval(start, end, curve: AppMotion.smooth),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tourist = context.read<TouristProvider>().tourist!;
    
    final tripDayCount = DateTime.now().difference(tourist.tripStartDate).inDays + 1;
    final totalTripDays = tourist.tripEndDate.difference(tourist.tripStartDate).inDays + 1;
    final tripProgress = (tripDayCount / totalTripDays.clamp(1, 1000)).clamp(0.0, 1.0);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // ── Header ──
        SliverAppBar(
          floating: true,
          snap: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          toolbarHeight: 0, // Hidden appbar for cleaner look
        ),

        // ── Main Content ──
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 60),
                
                // Welcome Message
                FadeTransition(
                  opacity: _step(0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome Back,',
                        style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.5)),
                      ),
                      Text(
                        tourist.fullName.split(' ').first,
                        style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 32),

                // Zone Status
                FadeTransition(
                  opacity: _step(1),
                  child: Selector<LocationProvider, ZoneType>(
                    selector: (_, provider) => provider.zoneStatus,
                    builder: (context, status, __) => ZoneStatusCard(status: status),
                  ),
                ),

                const SizedBox(height: 16),

                // NEW: Tactical Telemetry HUD (Coordinates + Time)
                FadeTransition(
                  opacity: _step(1.5),
                  child: const _TacticalStatusHUD(),
                ),

                const SizedBox(height: 24),

                // NEW: AI Safety Advisor Briefing
                FadeTransition(
                  opacity: _step(1.8),
                  child: const _SafetyAdvisorCard(),
                ),

                const SizedBox(height: 24),

                // Mini Map (Issue #8 Speed HUD)
                FadeTransition(
                  opacity: _step(2),
                  child: const _MiniMapCard(),
                ),

                const SizedBox(height: 24),

                // NEW: Mission Chronology (Timeline)
                FadeTransition(
                  opacity: _step(2.5),
                  child: const _MissionChronology(),
                ),

                const SizedBox(height: 24),

                // NEW: Safety Score & Mesh Analytics
                FadeTransition(
                  opacity: _step(2.8),
                  child: const _SafetyScoreCard(),
                ),

                const SizedBox(height: 24),

                // Quick Actions (Issue #8 Navigation)
                FadeTransition(
                  opacity: _step(3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'SAFETY MISSION CONTROL',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2, color: AppColors.primary),
                      ),
                      const SizedBox(height: 16),
                      _QuickActionsGrid(),
                    ],
                  ),
                ),

                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniMapCard extends StatelessWidget {
  const _MiniMapCard();

  @override
  Widget build(BuildContext context) {
    final locProv = context.watch<LocationProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final pos = locProv.currentPosition;
    
    return EliteSurface(
      padding: EdgeInsets.zero,
      height: 200,
      child: Stack(
        children: [
           AbsorbPointer(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: pos != null 
                    ? LatLng(pos.latitude, pos.longitude) 
                    : const LatLng(26.1445, 91.7362),
                initialZoom: 14.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: themeProvider.mapUrlTemplate,
                  userAgentPackageName: 'com.shivalik.saferoute',
                  tileProvider: DatabaseTileProvider(),
                ),
                if (pos != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(pos.latitude, pos.longitude),
                        width: 80,
                        height: 80,
                        child: PulseMarker(
                          color: AppColors.primary, 
                          size: 14,
                          speed: pos.speed, // SPEED DISPLAYED HERE
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          // Label Overlay
          Positioned(
            top: 12,
            right: 12,
            child: EliteSurface(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              borderRadius: 20,
              color: Colors.black54,
              child: Row(
                children: [
                  const Icon(Icons.satellite_alt_rounded, size: 12, color: AppColors.accent),
                  const SizedBox(width: 6),
                  Text(
                    themeProvider.mapMode == MapMode.satellite ? 'SAT-ACTIVE' : 'VECTOR-ACTIVE',
                    style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionsGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final navProv = context.read<MainNavigationProvider>();

    return Row(
      children: [
        Expanded(
          child: _QuickActionCard(
            icon: Icons.navigation_rounded,
            label: 'Tactical',
            color: AppColors.info,
            onTap: () => navProv.setIndex(5), // Navigation
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _QuickActionCard(
            icon: Icons.groups_rounded,
            label: 'Patrol',
            color: AppColors.accent,
            onTap: () => navProv.setIndex(2), // Group
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _QuickActionCard(
            icon: Icons.sos_rounded,
            label: 'Panic',
            color: AppColors.danger,
            onTap: () => navProv.setIndex(4), // SOS
          ),
        ),
      ],
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return EliteSurface(
      padding: const EdgeInsets.symmetric(vertical: 20),
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(height: 8),
          Text(
            label.toUpperCase(),
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1, color: color),
          ),
        ],
      ),
    );
  }
}

class _LoadingHomeState extends StatelessWidget {
  const _LoadingHomeState();
  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

// ── NEW: Safety Score & Analytics ──────────────────────────────────────────
class _SafetyScoreCard extends StatelessWidget {
  const _SafetyScoreCard();

  @override
  Widget build(BuildContext context) {
    final locProv = context.watch<LocationProvider>();
    final meshProv = context.watch<MeshProvider>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Calculate heuristic safety score
    double score = 0.7; // Base score
    if (locProv.zoneStatus == ZoneType.red) score -= 0.4;
    else if (locProv.zoneStatus == ZoneType.yellow) score -= 0.15;
    else if (locProv.zoneStatus == ZoneType.greenInner) score += 0.25;

    if (meshProv.isMeshActive) {
      score += (meshProv.nearbyNodes.length * 0.05).clamp(0.0, 0.15);
    }
    
    score = score.clamp(0.1, 1.0);
    final String label = score > 0.8 ? 'OPTIMAL' : (score > 0.4 ? 'STABLE' : 'CRITICAL');
    final Color scoreColor = score > 0.8 ? AppColors.success : (score > 0.4 ? AppColors.warning : AppColors.danger);

    return EliteSurface(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
               const Text(
                'SECURITY ARCHITECTURE',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: AppColors.primary),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: scoreColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: scoreColor.withOpacity(0.3)),
                ),
                child: Text(
                  label,
                  style: TextStyle(color: scoreColor, fontSize: 8, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                     _buildMetricRow('Network Mesh nodes', '${meshProv.nearbyNodes.length}', meshProv.isMeshActive ? AppColors.success : Colors.grey, isDark),
                     const SizedBox(height: 12),
                     _buildMetricRow('Geofence Integrity', locProv.isTracking ? 'LOCKED' : 'IDLE', locProv.isTracking ? AppColors.primary : Colors.grey, isDark),
                  ],
                ),
              ),
              const Expanded(flex: 1, child: SizedBox()),
              SizedBox(
                width: 60,
                height: 60,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: score,
                      strokeWidth: 8,
                      backgroundColor: isDark ? Colors.white10 : Colors.black12,
                      valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                      strokeCap: StrokeCap.round,
                    ),
                    Center(
                      child: Text(
                        '${(score * 100).toInt()}%',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricRow(String label, String value, Color color, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.black54)),
        Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}

// ── NEW: Tactical Telemetry HUD ──────────────────────────────────────────────
class _TacticalStatusHUD extends StatelessWidget {
  const _TacticalStatusHUD();

  @override
  Widget build(BuildContext context) {
    final locProv = context.watch<LocationProvider>();
    final pos = locProv.currentPosition;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    final lastSync = pos != null 
        ? DateFormat('HH:mm:ss').format(pos.timestamp) 
        : 'SCANNING...';

    return EliteSurface(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildHudItem('LATITUDE', pos?.latitude.toStringAsFixed(6) ?? '---.------', isDark),
              _buildHudItem('LONGITUDE', pos?.longitude.toStringAsFixed(6) ?? '---.------', isDark),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Colors.white10),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildHudItem('ACCURACY', '${pos?.accuracy.toStringAsFixed(1) ?? "--"} m', isDark),
              _buildHudItem('LAST SYNC', lastSync, isDark, isHighlight: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHudItem(String label, String value, bool isDark, {bool isHighlight = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 8,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w900,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
            color: isHighlight 
                ? AppColors.primary 
                : (isDark ? Colors.white : Colors.black87),
          ),
        ),
      ],
    );
  }
}

// ── NEW: AI Safety Advisor Briefing ──────────────────────────────────────────
class _SafetyAdvisorCard extends StatelessWidget {
  const _SafetyAdvisorCard();

  @override
  Widget build(BuildContext context) {
    final safetyProv = context.watch<SafetySystemProvider>();
    final riskLevel = safetyProv.currentRisk;
    final theme = Theme.of(context);
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            SafetyEngine.getRiskColor(riskLevel).withOpacity(0.1),
            AppColors.accent.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withOpacity(0.2), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.psychology_outlined, color: SafetyEngine.getRiskColor(riskLevel), size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TACTICAL ADVISOR',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: AppColors.primary),
                ),
                const SizedBox(height: 8),
                Text(
                  '${SafetyEngine.getRiskLabel(riskLevel)}: ${SafetyEngine.getRiskAdvice(riskLevel)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                    color: SafetyEngine.getRiskColor(riskLevel),
                  ),
                ),
                StreamBuilder<SafetyEvent>(
                  stream: safetyProv.eventStream,
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data!.type == SafetyEventType.riskUpdated) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'EVENT: ${snapshot.data!.message}',
                          style: const TextStyle(fontSize: 9, color: AppColors.primary, fontWeight: FontWeight.bold),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── NEW: Mission Chronology (Timeline) ──────────────────────────────────────
class _MissionChronology extends StatelessWidget {
  const _MissionChronology();

  @override
  Widget build(BuildContext context) {
    final safetyProv = context.watch<SafetySystemProvider>();
    final timeline = safetyProv.activityLog.take(8).toList();
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'MISSION CHRONOLOGY',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2, color: AppColors.primary),
        ),
        const SizedBox(height: 16),
        if (timeline.isEmpty)
          const Text('Awaiting initial system scan...', style: TextStyle(color: Colors.white24, fontSize: 12)),
        ...timeline.map((event) => _buildTimelineItem(event, theme)).toList(),
      ],
    );
  }

  Widget _buildTimelineItem(SafetyEvent event, ThemeData theme) {
    final timeStr = DateFormat('HH:mm:ss').format(event.timestamp);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              timeStr,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white38 : Colors.black38,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 4),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: _getEventColor(event.type), 
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: _getEventColor(event.type).withOpacity(0.5), blurRadius: 4),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: EliteSurface(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              borderRadius: 12,
              child: Text(
                event.message,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, height: 1.3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getEventColor(SafetyEventType type) {
    switch (type) {
      case SafetyEventType.sosTriggered: return Colors.redAccent;
      case SafetyEventType.riskUpdated: return Colors.orangeAccent;
      case SafetyEventType.zoneChanged: return AppColors.primary;
      case SafetyEventType.nodeDetected: return Colors.greenAccent;
      default: return Colors.grey;
    }
  }
}
