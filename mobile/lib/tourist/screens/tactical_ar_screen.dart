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
    final theme = Theme.of(context);
    final safeColors = theme.extension<SafeRouteColors>()!;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.backgroundDark,
            ),
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
                  color: safeColors.mapOverlay,
                  borderColor:
                      theme.colorScheme.outline.withValues(alpha: 0.30),
                  child: Icon(Icons.arrow_back_rounded,
                      color: safeColors.mapOverlayText),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: EliteSurface(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    borderRadius: 18,
                    color: safeColors.mapOverlay,
                    borderColor: AppColors.accent.withValues(alpha: 0.45),
                    borderOpacity: 0.45,
                    child: Text(
                      'Directional AR',
                      style: TextStyle(
                        color: safeColors.mapOverlayText,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        letterSpacing: 0,
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
              blur: lowPower ? 6 : 10,
              color: safeColors.mapOverlay.withValues(alpha: 0.88),
              borderColor: theme.colorScheme.outline.withValues(alpha: 0.30),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (!lowPower)
                    const PulseMarker(color: AppColors.info, size: 26),
                  Transform.rotate(
                    angle: (fusedHeading * math.pi) / 180,
                    child: const Icon(
                      Icons.navigation_rounded,
                      color: AppColors.info,
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
              color: safeColors.mapOverlay,
              borderColor: AppColors.info.withValues(alpha: 0.45),
              borderOpacity: 0.45,
              child: nav.isNavigating && leg != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Heading ${fusedHeading.toStringAsFixed(0)} deg - ${leg.direction}',
                          style: TextStyle(
                            color: safeColors.mapOverlayText
                                .withValues(alpha: 0.70),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          leg.maneuver,
                          style: TextStyle(
                            color: safeColors.mapOverlayText,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${leg.remainingDistanceMeters.toStringAsFixed(0)} m remaining - ETA ${leg.eta.inMinutes} min',
                          style: TextStyle(
                            color: safeColors.mapOverlayText
                                .withValues(alpha: 0.70),
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      'Start guidance on map screen to activate directional AR cues.',
                      style: TextStyle(
                        color:
                            safeColors.mapOverlayText.withValues(alpha: 0.70),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
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
