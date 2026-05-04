import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'package:saferoute/core/constants/app_assets.dart';
import 'package:saferoute/core/models/location_ping_model.dart';
import 'package:saferoute/tourist/providers/mesh_provider.dart';
import 'package:saferoute/tourist/models/tourist_model.dart';
import 'package:saferoute/tourist/providers/location_provider.dart';
import 'package:saferoute/tourist/providers/navigation_provider.dart';
import 'package:saferoute/tourist/providers/safety_system_provider.dart';
import 'package:saferoute/tourist/providers/tourist_provider.dart';
import 'package:saferoute/tourist/providers/trip_provider.dart';
import 'package:saferoute/tourist/screens/registration_screen.dart';
import 'package:saferoute/tourist/screens/start_trip_screen.dart';
import 'package:saferoute/services/safety_engine.dart';
import 'package:saferoute/utils/app_theme.dart';
import 'package:saferoute/widgets/premium_widgets.dart';
import 'package:saferoute/widgets/sync_status_chip.dart';
import 'package:saferoute/widgets/zone_status_card.dart';

class HomeScreenV2 extends StatelessWidget {
  const HomeScreenV2({super.key});

  @override
  Widget build(BuildContext context) {
    final touristProvider = context.watch<TouristProvider>();
    final tourist = touristProvider.tourist;
    final userState = touristProvider.userState;

    if (tourist == null && userState != UserState.guest) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return const Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          _RiskAdaptiveAuroraBackground(),
          SafeArea(child: _HomeContent()),
        ],
      ),
    );
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final touristProvider = context.watch<TouristProvider>();
    final tourist = touristProvider.tourist;
    final userState = touristProvider.userState;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 110),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TopIdentityBar(
              name: tourist?.fullName.split(' ').first ?? 'Explorer'),
          const SizedBox(height: 16),
          const _MissionControlCard(),
          const SizedBox(height: 14),
          Selector<LocationProvider, ZoneType>(
            selector: (_, provider) => provider.zoneStatus,
            builder: (context, status, __) => ZoneStatusCard(status: status),
          ),
          const SizedBox(height: 14),
          const _TelemetryRow(),
          if (userState == UserState.guest) ...[
            const SizedBox(height: 14),
            const _GuestAccessBanner(),
          ],
          // Show 'Start a Trip' CTA for registered/authenticated tourists
          if (userState != UserState.guest) ...[
            const SizedBox(height: 14),
            const _ActiveTripBanner(),
          ],
          const SizedBox(height: 22),
          Text(
            'QUICK ACTIONS',
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.white70,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          const _QuickActionsGrid(),
          const SizedBox(height: 14),
          const _FieldReadinessGrid(),
        ],
      ),
    );
  }
}

class _FieldReadinessGrid extends StatelessWidget {
  const _FieldReadinessGrid();

  @override
  Widget build(BuildContext context) {
    final location = context.watch<LocationProvider>();
    final mesh = context.watch<MeshProvider>();
    final tourist = context.watch<TouristProvider>();
    final pos = location.currentPosition;
    final speedKmh = ((pos?.speed ?? 0) * 3.6).clamp(0, 199).round();

    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _ReadinessTile(
              width: tileWidth,
              icon: Icons.my_location_rounded,
              title: 'GPS',
              value: pos == null
                  ? 'ACQUIRING'
                  : '${pos.accuracy.toStringAsFixed(0)} M',
              tone: pos == null ? AppColors.warning : AppColors.success,
            ),
            _ReadinessTile(
              width: tileWidth,
              icon: Icons.hub_rounded,
              title: 'Mesh Nodes',
              value: mesh.isMeshActive
                  ? '${mesh.nearbyNodes.length} NEARBY'
                  : 'STANDBY',
              tone: mesh.isMeshActive ? AppColors.info : AppColors.warning,
            ),
            _ReadinessTile(
              width: tileWidth,
              icon: Icons.cloud_upload_rounded,
              title: 'Local Queue',
              value: tourist.isOnline
                  ? 'READY'
                  : '${location.unsyncedCount} WAITING',
              tone: tourist.isOnline || location.unsyncedCount == 0
                  ? AppColors.success
                  : AppColors.warning,
            ),
            _ReadinessTile(
              width: tileWidth,
              icon: Icons.speed_rounded,
              title: 'Pace',
              value: '$speedKmh KM/H',
              tone: AppColors.accent,
            ),
          ],
        );
      },
    );
  }
}

class _ReadinessTile extends StatelessWidget {
  final double width;
  final IconData icon;
  final String title;
  final String value;
  final Color tone;

  const _ReadinessTile({
    required this.width,
    required this.icon,
    required this.title,
    required this.value,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: EliteSurface(
        padding: const EdgeInsets.all(12),
        borderRadius: 16,
        color: Colors.white.withValues(alpha: 0.08),
        borderColor: tone.withValues(alpha: 0.38),
        borderOpacity: 0.38,
        child: Row(
          children: [
            Icon(icon, color: tone, size: 19),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RiskAdaptiveAuroraBackground extends StatelessWidget {
  const _RiskAdaptiveAuroraBackground();

  @override
  Widget build(BuildContext context) {
    return Selector<SafetySystemProvider, SafetyRiskLevel>(
      selector: (_, provider) => provider.currentRisk,
      builder: (context, risk, __) {
        final scheme = _riskScheme(risk);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeInOutCubic,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: scheme,
            ),
          ),
          child: const Stack(
            fit: StackFit.expand,
            children: [
              Opacity(opacity: 0.40, child: AuroraBackground()),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topCenter,
                    radius: 1.25,
                    colors: [Color(0x33000000), Color(0xAA000000)],
                    stops: [0.1, 1.0],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Color> _riskScheme(SafetyRiskLevel risk) {
    switch (risk) {
      case SafetyRiskLevel.high:
        return const [Color(0xFF591126), Color(0xFF1A0A14), Color(0xFF000000)];
      case SafetyRiskLevel.medium:
        return const [Color(0xFF5C3C08), Color(0xFF1D1604), Color(0xFF000000)];
      case SafetyRiskLevel.low:
        return const [Color(0xFF072437), Color(0xFF061627), Color(0xFF000000)];
    }
  }
}

class _TopIdentityBar extends StatelessWidget {
  final String name;
  const _TopIdentityBar({required this.name});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mission Control',
                style: style.labelLarge?.copyWith(
                  color: Colors.white70,
                  letterSpacing: 1.2,
                ),
              ),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        const SyncStatusChip(compact: true),
      ],
    );
  }
}

class _MissionControlCard extends StatelessWidget {
  const _MissionControlCard();

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocationProvider>();
    final safety = context.watch<SafetySystemProvider>();
    final risk = safety.currentRisk;
    final riskColor = SafetyEngine.getRiskColor(risk);
    final riskLabel = _riskUiLabel(risk);
    final progress = _riskProgress(risk);

    return EliteSurface(
      padding: const EdgeInsets.all(18),
      color: Colors.white.withValues(alpha: 0.10),
      borderColor: riskColor.withValues(alpha: 0.45),
      borderOpacity: 0.45,
      blur: 32,
      child: Row(
        children: [
          SizedBox(
            width: 114,
            height: 114,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 8,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation<Color>(riskColor),
                  strokeCap: StrokeCap.round,
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${(progress * 100).round()}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                        ),
                      ),
                      const Text(
                        'RISK',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                          fontSize: 9,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SAFETY RISK LEVEL',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white70,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  riskLabel,
                  style: TextStyle(
                    color: riskColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  SafetyEngine.getRiskAdvice(risk),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 10),
                _RiskLottieAccent(risk: risk, zone: loc.zoneStatus),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _riskUiLabel(SafetyRiskLevel risk) {
    switch (risk) {
      case SafetyRiskLevel.low:
        return 'SAFE';
      case SafetyRiskLevel.medium:
        return 'CAUTION';
      case SafetyRiskLevel.high:
        return 'RESTRICTED';
    }
  }

  double _riskProgress(SafetyRiskLevel risk) {
    switch (risk) {
      case SafetyRiskLevel.low:
        return 0.30;
      case SafetyRiskLevel.medium:
        return 0.62;
      case SafetyRiskLevel.high:
        return 0.94;
    }
  }
}

class _RiskLottieAccent extends StatelessWidget {
  final SafetyRiskLevel risk;
  final ZoneType zone;

  const _RiskLottieAccent({required this.risk, required this.zone});

  @override
  Widget build(BuildContext context) {
    final Color fallbackColor = SafetyEngine.getRiskColor(risk);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 56,
        child: Lottie.asset(
          AppAssets.animations.safetyOrb,
          fit: BoxFit.cover,
          repeat: true,
          errorBuilder: (_, __, ___) {
            return Container(
              color: fallbackColor.withValues(alpha: 0.12),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome_rounded,
                      color: fallbackColor, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Zone: ${zone.displayLabel.toUpperCase()}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TelemetryRow extends StatelessWidget {
  const _TelemetryRow();

  @override
  Widget build(BuildContext context) {
    final location = context.watch<LocationProvider>();
    final touristProvider = context.watch<TouristProvider>();

    // Battery value is sourced from the same pipeline pushed into
    // SafetySystemProvider.updateState(batteryLevel: ...).
    final battery = location.batteryLevel.clamp(0.0, 1.0);

    return Row(
      children: [
        Expanded(
          child: _TelemetryChip(
            icon: Icons.battery_full_rounded,
            title: 'Battery',
            value: '${(battery * 100).toInt()}%',
            tone: _batteryColor(battery),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _TelemetryChip(
            icon: touristProvider.isOnline
                ? Icons.cloud_done_rounded
                : Icons.cloud_off_rounded,
            title: 'Connectivity',
            value: touristProvider.isOnline ? 'ONLINE' : 'OFFLINE',
            tone: touristProvider.isOnline
                ? AppColors.success
                : AppColors.warning,
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(child: SyncStatusChip()),
      ],
    );
  }

  Color _batteryColor(double value) {
    if (value < 0.15) return AppColors.danger;
    if (value < 0.35) return AppColors.warning;
    return AppColors.accent;
  }
}

class _TelemetryChip extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color tone;

  const _TelemetryChip({
    required this.icon,
    required this.title,
    required this.value,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    return EliteSurface(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      borderRadius: 16,
      color: Colors.white.withValues(alpha: 0.09),
      borderColor: tone.withValues(alpha: 0.40),
      borderOpacity: 0.4,
      child: Row(
        children: [
          Icon(icon, color: tone, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionsGrid extends StatelessWidget {
  const _QuickActionsGrid();

  @override
  Widget build(BuildContext context) {
    final navProv = context.read<MainNavigationProvider>();

    return Row(
      children: [
        Expanded(
          child: _QuickActionCard(
            icon: Icons.navigation_rounded,
            label: 'Navigate',
            color: AppColors.info,
            onTap: () => navProv.setIndex(5),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickActionCard(
            icon: Icons.groups_rounded,
            label: 'Patrol',
            color: AppColors.accent,
            onTap: () => navProv.setIndex(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickActionCard(
            icon: Icons.sos_rounded,
            label: 'SOS',
            color: AppColors.danger,
            onTap: () => navProv.setIndex(4),
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
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 18),
      borderRadius: 18,
      color: color.withValues(alpha: 0.14),
      borderColor: color.withValues(alpha: 0.50),
      borderOpacity: 0.5,
      child: Column(
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 6),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 10,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _GuestAccessBanner extends StatelessWidget {
  const _GuestAccessBanner();

  @override
  Widget build(BuildContext context) {
    return EliteSurface(
      color: AppColors.warning.withValues(alpha: 0.12),
      borderColor: AppColors.warning.withValues(alpha: 0.45),
      borderOpacity: 0.45,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              color: AppColors.warning, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Guest mode active. Register to unlock full SOS identity and route safety features.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
          EliteButton(
            width: 96,
            height: 34,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RegistrationScreen()),
              );
            },
            child: const Text('REGISTER', style: TextStyle(fontSize: 10)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Active Trip Banner — shows current trip or CTA to start one
// ---------------------------------------------------------------------------

class _ActiveTripBanner extends StatelessWidget {
  const _ActiveTripBanner();

  @override
  Widget build(BuildContext context) {
    final tripProvider = context.watch<TripProvider>();
    final activeTrip = tripProvider.activeTrip;

    if (activeTrip != null) {
      // ── Has active trip ── show current stop summary
      final stop = activeTrip.currentStop;
      return EliteSurface(
        color: AppColors.success.withValues(alpha: 0.12),
        borderColor: AppColors.success.withValues(alpha: 0.45),
        borderOpacity: 0.45,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.flight_takeoff_rounded,
                color: AppColors.success, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ACTIVE TRIP',
                    style: TextStyle(
                      color: AppColors.success,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stop?.name ?? 'Trip in progress',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (stop?.destinationState != null)
                    Text(
                      stop!.destinationState!,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 11),
                    ),
                ],
              ),
            ),
            EliteButton(
              width: 80,
              height: 34,
              color: AppColors.danger.withValues(alpha: 0.8),
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('End Trip?'),
                    content: const Text(
                        'This will mark your current trip as completed.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('End Trip',
                              style: TextStyle(color: AppColors.danger))),
                    ],
                  ),
                );
                if (confirmed == true && context.mounted) {
                  await context.read<TripProvider>().endActiveTrip();
                }
              },
              child: const Text('END', style: TextStyle(fontSize: 10)),
            ),
          ],
        ),
      );
    }

    // ── No active trip ── prompt to start one
    return EliteSurface(
      color: AppColors.primary.withValues(alpha: 0.12),
      borderColor: AppColors.primary.withValues(alpha: 0.45),
      borderOpacity: 0.45,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const Icon(Icons.map_outlined, color: AppColors.primaryLight, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'No active trip. Start a trip to enable destination-aware safety alerts.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
          EliteButton(
            width: 96,
            height: 34,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StartTripScreen()),
              );
            },
            child: const Text('START', style: TextStyle(fontSize: 10)),
          ),
        ],
      ),
    );
  }
}
