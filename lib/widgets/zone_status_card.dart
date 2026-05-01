import 'package:flutter/material.dart';
import 'package:saferoute/models/location_ping_model.dart';
import 'package:saferoute/utils/app_theme.dart';
import 'package:saferoute/widgets/premium_widgets.dart';

class ZoneStatusCard extends StatelessWidget {
  final ZoneType status;

  const ZoneStatusCard({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Gradient gradient;
    IconData icon;
    String description;
    String title = status.displayName.toUpperCase();
    Color primaryColor;

    switch (status) {
      case ZoneType.greenOuter:
      case ZoneType.greenInner:
        primaryColor = AppColors.zoneGreen;
        gradient = LinearGradient(colors: [
          AppColors.zoneGreen,
          AppColors.zoneGreen.withOpacity(0.7)
        ]);
        icon = Icons.shield_moon_rounded;
        description =
            "You are under active protection. Stay within the perimeter.";
        break;
      case ZoneType.yellow:
        primaryColor = AppColors.zoneYellow;
        gradient = LinearGradient(
            colors: [AppColors.zoneYellow, const Color(0xFFF59E0B)]);
        icon = Icons.gpp_maybe_rounded;
        description = "Cuation required. Boundary drift detected.";
        break;
      case ZoneType.red:
        primaryColor = AppColors.zoneRed;
        gradient = LinearGradient(
            colors: [AppColors.zoneRed, const Color(0xFFB91C1C)]);
        icon = Icons.gpp_bad_rounded;
        description = "EMERGENCY: Restricted zone breech. Retrace immediately.";
        break;
      default:
        primaryColor = Colors.blueGrey;
        gradient = const LinearGradient(colors: [Colors.blueGrey, Colors.grey]);
        icon = Icons.help_outline_rounded;
        description = "Signal weak. Maintain visual contact with markers.";
    }

    return EliteSurface(
      padding: EdgeInsets.zero,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXL),
          boxShadow: [
            BoxShadow(
                color: primaryColor.withOpacity(isDark ? 0.08 : 0.05),
                blurRadius: 40,
                spreadRadius: -10)
          ],
        ),
        child: Column(
          children: [
            // ── Top Gradient Header ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.l, vertical: AppSpacing.m),
              decoration: BoxDecoration(
                gradient: gradient.withOpacity(0.1),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppSpacing.radiusXL)),
              ),
              child: Row(
                children: [
                  ShaderMask(
                    shaderCallback: (bounds) => gradient.createShader(bounds),
                    child: Icon(icon, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: AppSpacing.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: TextStyle(
                                color: isDark
                                    ? Colors.white
                                    : primaryColor.withOpacity(0.9),
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                letterSpacing: 0.5)),
                        Text("MISSION PERIMETER",
                            style: TextStyle(
                                color: (isDark ? Colors.white : Colors.black)
                                    .withOpacity(0.3),
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5)),
                      ],
                    ),
                  ),
                  _PulsingLiveIndicator(color: primaryColor),
                ],
              ),
            ),

            // ── Information Body ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(AppSpacing.l),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(description,
                      style: TextStyle(
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                          fontSize: 13,
                          height: 1.5,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: AppSpacing.l),

                  // ── Premium Distance Meter ──────────────────────────────────
                  Stack(
                    children: [
                      Container(
                        height: 6,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurface.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(seconds: 1),
                        height: 6,
                        width: MediaQuery.of(context).size.width *
                            0.4, // Mock distance
                        decoration: BoxDecoration(
                          gradient: gradient,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                                color: primaryColor.withOpacity(0.3),
                                blurRadius: 8)
                          ],
                        ),
                      ),
                    ],
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

class _PulsingLiveIndicator extends StatefulWidget {
  final Color color;
  const _PulsingLiveIndicator({required this.color});

  @override
  State<_PulsingLiveIndicator> createState() => _PulsingLiveIndicatorState();
}

class _PulsingLiveIndicatorState extends State<_PulsingLiveIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: widget.color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: widget.color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: Tween<double>(begin: 0.8, end: 1.2).animate(
                CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut)),
            child: Container(
                width: 6,
                height: 6,
                decoration:
                    BoxDecoration(color: widget.color, shape: BoxShape.circle)),
          ),
          const SizedBox(width: 6),
          Text("LIVE",
              style: TextStyle(
                  color: widget.color,
                  fontSize: 9,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}
