import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:saferoute/utils/app_theme.dart';
import 'package:saferoute/tourist/providers/tourist_provider.dart';

class ConnectivityChip extends StatelessWidget {
  const ConnectivityChip({super.key});

  @override
  Widget build(BuildContext context) {
    final isOnline = context.watch<TouristProvider>().isOnline;
    final color = isOnline ? AppColors.zoneGreen : AppColors.zoneRed;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            isOnline ? "ONLINE" : "OFFLINE",
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
