// lib/screens/map_placeholder_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:saferoute/providers/location_provider.dart';
import 'package:saferoute/models/location_ping_model.dart';
import 'package:saferoute/widgets/zone_status_card.dart';

class MapPlaceholderScreen extends StatelessWidget {
  const MapPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final locationProvider = context.watch<LocationProvider>();
    final position = locationProvider.currentPosition;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Live Safety Map", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Map Placeholder
            Container(
              height: 300,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.map_outlined, size: 80, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    "Live Map - Coming in Phase 2",
                    style: TextStyle(color: Colors.grey, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 40, vertical: 8),
                    child: Text(
                      "Integrated satellite views and real-time mesh networking visualization.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            Selector<LocationProvider, ZoneType>(
              selector: (_, prov) => prov.zoneStatus,
              builder: (_, status, __) => ZoneStatusCard(status: status),
            ),
            
            const SizedBox(height: 32),
            const Text(
              "Current Coordinates",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _CoordinateItem(label: "LATITUDE", value: position?.latitude.toStringAsFixed(6) ?? "0.000000"),
                    Container(height: 40, width: 1, color: Colors.grey.shade300),
                    _CoordinateItem(label: "LONGITUDE", value: position?.longitude.toStringAsFixed(6) ?? "0.000000"),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 32),
            const Text(
              "Recent Location History",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            // Simple list of last 10 pings placeholder
            Selector<LocationProvider, ZoneType>(
              selector: (_, prov) => prov.zoneStatus,
              builder: (_, status, __) => ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 10,
                itemBuilder: (context, index) {
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.circle, size: 10, color: Colors.green),
                    title: Text("Ping #${10 - index}"),
                    subtitle: Text("Verified via GPS - ${DateTime.now().subtract(Duration(minutes: index * 5)).toString().substring(11, 16)}"),
                    trailing: Text(
                      status.displayName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _CoordinateItem({required String label, required String value}) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, letterSpacing: 1.1)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
      ],
    );
  }
}
