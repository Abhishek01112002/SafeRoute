import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:saferoute/utils/app_theme.dart';
import 'package:saferoute/widgets/premium_widgets.dart';
import 'package:saferoute/providers/tourist_provider.dart';
import 'package:saferoute/providers/location_provider.dart';
import 'package:saferoute/widgets/zone_status_card.dart';
import 'package:saferoute/models/location_ping_model.dart';

import 'package:saferoute/providers/theme_provider.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeProvider = context.watch<ThemeProvider>();
    final provider = context.watch<TouristProvider>();
    final tourist = provider.tourist;
    final locationProvider = context.watch<LocationProvider>();
    final isDark = theme.brightness == Brightness.dark;
    
    if (tourist == null) {
      if (provider.isLoading) return _buildLoadingState(context);
      return Center(child: Text("Registration Required", style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold)));
    }

    final tripDayCount = DateTime.now().difference(tourist.tripStartDate).inDays + 1;
    final totalTripDays = tourist.tripEndDate.difference(tourist.tripStartDate).inDays + 1;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // ── Aurora Background Aura (The Artist's Layer) ─────────────────
          Positioned(
            top: -100,
            right: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(isDark ? 0.08 : 0.05), blurRadius: 100, spreadRadius: 50)],
                color: AppColors.primary.withOpacity(isDark ? 0.05 : 0.03),
              ),
            ),
          ),
          Positioned(
            bottom: 100,
            left: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: AppColors.accent.withOpacity(isDark ? 0.05 : 0.03), blurRadius: 120, spreadRadius: 60)],
                color: AppColors.accent.withOpacity(isDark ? 0.03 : 0.02),
              ),
            ),
          ),

          // ── Main Content ──────────────────────────────────────────────────
          SingleChildScrollView(
            padding: EdgeInsets.only(
              left: AppSpacing.l, 
              right: AppSpacing.l, 
              top: MediaQuery.of(context).padding.top + kToolbarHeight + AppSpacing.xl,
              bottom: AppSpacing.xxl
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header Section ──────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("MISSION STATUS",
                          style: TextStyle(color: theme.colorScheme.primary, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
                        const SizedBox(height: 4),
                        Text(tourist.fullName.toUpperCase(),
                          style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w900, fontSize: 24, letterSpacing: -0.5)),
                      ],
                    ),
                    _ThemeToggle(themeProvider: themeProvider),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxl),

                // ── Safety HUD ──────────────────────────────────────────────
                Selector<LocationProvider, ZoneType>(
                  selector: (_, provider) => provider.zoneStatus,
                  builder: (_, status, __) => ZoneStatusCard(status: status),
                ),
                const SizedBox(height: AppSpacing.xl),

                // ── Survival Stats ──────────────────────────────────────────
                Row(
                  children: [
                    _eliteStatCard(context, "DAY", "$tripDayCount/$totalTripDays", Icons.auto_awesome_rounded, AppColors.primary),
                    const SizedBox(width: AppSpacing.m),
                    _eliteStatCard(context, "PENDING", "${locationProvider.unsyncedCount}", Icons.waves_rounded, AppColors.zoneYellow),
                    const SizedBox(width: AppSpacing.m),
                    _eliteStatCard(context, "NODES", "0", Icons.share_location_rounded, AppColors.accent),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxl),

                // ── Recent Activity Section ─────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("TRAIL LOGS",
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: theme.colorScheme.onSurface.withOpacity(0.4))),
                    TextButton(
                      onPressed: () {},
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                      child: Text("MONITOR", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: theme.colorScheme.primary)),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.m),

                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: 4,
                  separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.m),
                  itemBuilder: (context, index) {
                    final time = DateTime.now().subtract(Duration(minutes: index * 45));
                    final lat = 30.3367 + (index * 0.0012);
                    final lng = 78.0273 - (index * 0.0008);
                    return _buildActivityItem(context, index, time, lat, lng);
                  },
                ),
                const SizedBox(height: 120), // Padding for Floating Dock
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _eliteStatCard(BuildContext context, String title, String value, IconData icon, Color color) {
    final theme = Theme.of(context);
    return Expanded(
      child: EliteSurface(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl, horizontal: AppSpacing.s),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: AppSpacing.m),
            Text(value, style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
            const SizedBox(height: 4),
            Text(title, style: TextStyle(fontSize: 9, color: theme.colorScheme.onSurface.withOpacity(0.4), fontWeight: FontWeight.w900, letterSpacing: 1)),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityItem(BuildContext context, int index, DateTime time, double lat, double lng) {
    final theme = Theme.of(context);
    return EliteSurface(
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.my_location_rounded, size: 20, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("COORD RECORDED", style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 11, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text("${lat.toStringAsFixed(4)}°N, ${lng.toStringAsFixed(4)}°E", 
                  style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withOpacity(0.4), fontFamily: 'monospace')),
                Text(DateFormat('hh:mm a').format(time).toUpperCase(), 
                  style: TextStyle(fontSize: 9, color: theme.colorScheme.primary, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.zoneGreen.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: const [
                Icon(Icons.shield_rounded, color: AppColors.zoneGreen, size: 14),
                Text("VERIFIED", style: TextStyle(color: AppColors.zoneGreen, fontSize: 8, fontWeight: FontWeight.w900)),
               ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _ThemeToggle extends StatelessWidget {
  final ThemeProvider themeProvider;
  const _ThemeToggle({required this.themeProvider});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        themeProvider.toggleTheme();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        width: 48, height: 48,
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withOpacity(0.1),
          shape: BoxShape.circle,
          border: Border.all(color: theme.colorScheme.primary.withOpacity(0.2)),
        ),
        child: Icon(
          themeProvider.isDarkMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
          color: theme.colorScheme.primary,
          size: 20,
        ),
      ),
    );
  }
}
