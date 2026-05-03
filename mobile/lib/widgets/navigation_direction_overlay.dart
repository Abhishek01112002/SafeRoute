import 'package:flutter/material.dart';
import 'package:saferoute/tourist/providers/navigation_provider.dart';
import 'package:saferoute/utils/app_theme.dart';
import 'package:saferoute/widgets/premium_widgets.dart';

class NavigationDirectionOverlay extends StatelessWidget {
  final NavigationLeg leg;

  const NavigationDirectionOverlay({super.key, required this.leg});

  @override
  Widget build(BuildContext context) {
    return EliteSurface(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      borderRadius: 20,
      blur: 30,
      color: Colors.black.withValues(alpha: 0.30),
      borderColor: AppColors.accent.withValues(alpha: 0.5),
      borderOpacity: 0.45,
      child: Row(
        children: [
          Icon(_directionIcon(leg.direction), color: Colors.white, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  leg.maneuver,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${leg.remainingDistanceMeters.toStringAsFixed(0)} m  •  ETA ${leg.eta.inMinutes} min',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              leg.direction,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.7,
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _directionIcon(String direction) {
    switch (direction) {
      case 'N':
        return Icons.arrow_upward_rounded;
      case 'E':
        return Icons.arrow_forward_rounded;
      case 'S':
        return Icons.arrow_downward_rounded;
      default:
        return Icons.arrow_back_rounded;
    }
  }
}
