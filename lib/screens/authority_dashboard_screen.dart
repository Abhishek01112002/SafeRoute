import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:saferoute/providers/location_provider.dart';
import 'package:saferoute/providers/safety_system_provider.dart';
import 'package:saferoute/providers/tourist_provider.dart';
import 'package:saferoute/services/safety_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saferoute/screens/onboarding_screen.dart';
import 'package:saferoute/widgets/connectivity_chip.dart';
import 'package:saferoute/services/simulation_engine.dart';

class AuthorityDashboardScreen extends StatefulWidget {
  const AuthorityDashboardScreen({super.key});

  @override
  State<AuthorityDashboardScreen> createState() => _AuthorityDashboardScreenState();
}

class _AuthorityDashboardScreenState extends State<AuthorityDashboardScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Consumer<TouristProvider>(
          builder: (context, touristProv, _) {
            final state = touristProv.tourist?.destinationState ?? "NORTH ZONE";
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Authority Command Center", style: const TextStyle(fontWeight: FontWeight.bold)),
                Text("JURISDICTION: SAFETY NETWORK COMMAND - ${state.toUpperCase()}", 
                  style: const TextStyle(fontSize: 10, letterSpacing: 1)),
              ],
            );
          },
        ),
        actions: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: ConnectivityChip(),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _showLogoutDialog(context),
            tooltip: "Logout",
          ),
        ],
      ),
      body: Column(
        children: [
          // 2A: Top Stats Bar
          _buildStatsBar(),
          
          // 2B: Live Map (Expanded)
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  children: [
                    Consumer2<LocationProvider, SafetySystemProvider>(
                      builder: (context, locProv, safetyProv, _) {
                        final pos = locProv.currentPosition;
                        final center = pos != null ? LatLng(pos.latitude, pos.longitude) : const LatLng(30.1467, 79.2140);
                        
                        return FlutterMap(
                          options: MapOptions(
                            initialCenter: center,
                            initialZoom: 14.0,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.saferoute.app',
                            ),
                            MarkerLayer(
                              markers: [
                                // Current User Node
                                Marker(
                                  point: center,
                                  child: const Icon(Icons.my_location, color: Colors.blue, size: 24),
                                ),
                                // Deterministic Simulated Nodes
                                ...safetyProv.nearbyNodes.map((node) => Marker(
                                  point: node.position,
                                  child: Icon(
                                    Icons.person_pin_circle, 
                                    color: node.status == "CAUTION" ? Colors.orange : Colors.green, 
                                    size: 30
                                  ),
                                )).toList(),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                    
                    // 2C: SOS Alert Overlay (Bottom)
                    _buildSOSAlertPanel(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBar() {
    return Consumer<SafetySystemProvider>(
      builder: (context, safetyProv, _) {
        final nodes = safetyProv.nearbyNodes;
        final sosCount = safetyProv.activityLog.where((e) => e.type == SafetyEventType.sosTriggered).length;
        
        return Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _statItem("TOTAL TOURISTS", "${nodes.length + 120}", Colors.blue),
              _statItem("ACTIVE SOS", sosCount.toString().padLeft(2, '0'), Colors.red, isUrgent: sosCount > 0),
              _statItem("PENDING ID", "04", Colors.orange),
            ],
          ),
        );
      },
    );
  }

  Widget _statItem(String label, String value, Color color, {bool isUrgent = false}) {
    return Expanded(
      child: Card(
        elevation: 0,
        color: color.withOpacity(0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color.withOpacity(0.3)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
              Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSOSAlertPanel() {
    return Consumer<SafetySystemProvider>(
      builder: (context, safetyProv, _) {
        final recentAlerts = safetyProv.activityLog
            .where((e) => e.type == SafetyEventType.sosTriggered || e.type == SafetyEventType.riskUpdated)
            .take(2)
            .toList();

        if (recentAlerts.isEmpty) return const SizedBox.shrink();

        return Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black.withOpacity(0.9), Colors.transparent],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      "LIVE COMMAND ALERTS", 
                      style: TextStyle(color: Colors.white.withOpacity(0.9), fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1)
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...recentAlerts.map((event) => _sosAlertTile(
                  event.type == SafetyEventType.sosTriggered ? "DEMO_USER_01" : "SYSTEM_NODE",
                  event.message,
                  "${DateTime.now().difference(event.timestamp).inSeconds}s ago"
                )).toList(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sosAlertTile(String name, String location, String time) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: Colors.red, child: const Icon(Icons.sos, color: Colors.white)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(location, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text("RESPOND"),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Logout"),
        content: const Text("Are you sure you want to logout from the Command Center?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          TextButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                  (route) => false,
                );
              }
            },
            child: const Text("Logout", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
