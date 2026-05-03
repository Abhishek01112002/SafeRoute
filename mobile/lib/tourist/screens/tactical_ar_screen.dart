import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:provider/provider.dart';
import 'package:saferoute/tourist/providers/location_provider.dart';
import 'package:saferoute/tourist/providers/navigation_provider.dart';
import 'package:saferoute/utils/app_theme.dart';
import 'package:saferoute/widgets/premium_widgets.dart';

class TacticalARScreen extends StatefulWidget {
  const TacticalARScreen({super.key});

  @override
  State<TacticalARScreen> createState() => _TacticalARScreenState();
}

class _TacticalARScreenState extends State<TacticalARScreen> {
  double _compassHeading = 0;
  StreamSubscription<CompassEvent>? _compassSubscription;

  @override
  void initState() {
    super.initState();
    // Listen to compass events for AR heading
    _compassSubscription = FlutterCompass.events?.listen((event) {
      if (mounted && event.heading != null) {
        setState(() {
          _compassHeading = event.heading!;
        });
      }
    });
  }

  @override
  void dispose() {
    _compassSubscription?.cancel();
    super.dispose();
  }

  /// Sensor fusion: Use GPS heading when moving (>1 m/s), compass when stationary
  double _calculateFusedHeading(LocationProvider location) {
    final gpsHeading = location.currentPosition?.heading;
    final speed = location.currentPosition?.speed ?? 0;

    // If moving faster than 1 m/s (3.6 km/h), trust GPS heading
    if (speed > 1.0 && gpsHeading != null && gpsHeading >= 0) {
      return gpsHeading;
    }

    // Otherwise use compass (which gives device orientation)
    return _compassHeading;
  }

  @override
  Widget build(BuildContext context) {
    final location = context.watch<LocationProvider>();
    final nav = context.watch<MainNavigationProvider>();
    final leg = nav.currentLeg;
    final fusedHeading = _calculateFusedHeading(location);
    final battery = location.batteryLevel;
    final lowPower = battery < 0.20;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF06131C), Color(0xFF000000)],
              ),
            ),
          ),
          Opacity(
            opacity: 0.16,
            child: lowPower
                ? const SizedBox.expand()
                : const AuroraBackground(),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            right: 16,
            child: Row(
              children: [
                EliteSurface(
                  onTap: () => Navigator.of(context).pop(),
                  width: 48,
                  height: 48,
                  borderRadius: 24,
                  padding: EdgeInsets.zero,
                  color: Colors.white.withValues(alpha: 0.1),
                  child: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: EliteSurface(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    borderRadius: 18,
                    color: Colors.white.withValues(alpha: 0.1),
                    borderColor: AppColors.accent.withValues(alpha: 0.45),
                    borderOpacity: 0.45,
                    child: const Text(
                      'TACTICAL AR OVERLAY',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Center(
            child: EliteSurface(
              width: 220,
              height: 220,
              borderRadius: 120,
              blur: lowPower ? 8 : 24,
              color: Colors.white.withValues(alpha: 0.06),
              borderColor: Colors.white24,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (!lowPower) const PulseMarker(color: AppColors.info, size: 26),
                  Transform.rotate(
                    angle: (fusedHeading * math.pi) / 180,
                    child: const Icon(
                      Icons.navigation_rounded,
                      color: Colors.white,
                      size: 74,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 26,
            child: EliteSurface(
              padding: const EdgeInsets.all(14),
              borderRadius: 18,
              color: Colors.black.withValues(alpha: 0.35),
              borderColor: AppColors.info.withValues(alpha: 0.45),
              borderOpacity: 0.45,
              child: nav.isNavigating && leg != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'HEAD ${fusedHeading.toStringAsFixed(0)}°  •  ${leg.direction}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          leg.maneuver,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${leg.remainingDistanceMeters.toStringAsFixed(0)} m remaining  •  ETA ${leg.eta.inMinutes} min',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    )
                  : const Text(
                      'Start guidance on map screen to activate directional AR cues.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
