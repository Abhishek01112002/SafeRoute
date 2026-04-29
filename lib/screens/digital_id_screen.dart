import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:saferoute/utils/app_theme.dart';
import 'package:saferoute/widgets/premium_widgets.dart';
import 'package:saferoute/providers/location_provider.dart';
import 'package:saferoute/providers/tourist_provider.dart';
import 'package:saferoute/screens/onboarding_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:intl/intl.dart';

class DigitalIdScreen extends StatefulWidget {
  const DigitalIdScreen({super.key});

  @override
  State<DigitalIdScreen> createState() => _DigitalIdScreenState();
}

class _DigitalIdScreenState extends State<DigitalIdScreen> {
  int _devTapCount = 0;

  void _handleDevTap() {
    _devTapCount++;
    if (_devTapCount >= 5) {
      final locProv = context.read<LocationProvider>();
      final isMock = locProv.isMockMode;
      locProv.setMockMode(!isMock);
      _devTapCount = 0;
      
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(!isMock ? "DEMO MODE: FORCED MOCK ACTIVE" : "LIVE MODE: GPS RESTORED", 
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10)),
        backgroundColor: !isMock ? AppColors.zoneYellow : AppColors.zoneGreen,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tourist = context.watch<TouristProvider>().tourist;
    final isMock = context.watch<LocationProvider>().isMockMode;

    if (tourist == null) {
      return const Center(child: GlimmerLoader(width: 300, height: 500));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: AppSpacing.xl),
      child: Column(
        children: [
          // ── Premium Crystal ID Card ───────────────────────────────────────
          EliteSurface(
            padding: EdgeInsets.zero,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary.withOpacity(isDark ? 0.15 : 0.08),
                    theme.colorScheme.primary.withOpacity(isDark ? 0.05 : 0.03),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0.1,
                      child: CustomPaint(painter: _HolographicPainter(isDark: isDark)),
                    ),
                  ),
                  
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Icon(Icons.shield_rounded, color: theme.colorScheme.primary, size: 28),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: theme.colorScheme.primary.withOpacity(0.2)),
                              ),
                              child: Text(
                                "VERIFIED IDENTITY",
                                style: TextStyle(color: theme.colorScheme.primary, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: theme.colorScheme.primary.withOpacity(0.2), blurRadius: 20)],
                          ),
                          child: CircleAvatar(
                            radius: 50,
                            backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                            child: tourist.photoBase64.isEmpty
                                ? Icon(Icons.person_rounded, size: 48, color: theme.colorScheme.primary.withOpacity(0.5))
                                : CircleAvatar(
                                    radius: 48,
                                    backgroundImage: MemoryImage(base64Decode(tourist.photoBase64)),
                                  ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        
                        Text(
                          tourist.fullName.toUpperCase(),
                          style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tourist.touristId,
                          style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.3), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 3),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        
                        Divider(color: theme.colorScheme.onSurface.withOpacity(0.08)),
                        const SizedBox(height: AppSpacing.l),
                        
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _idDetail(context, "LOCATION", tourist.destinationState),
                            _idDetail(context, "BLOOD", tourist.bloodGroup),
                            _idDetail(context, "VITALITY", tourist.riskLevel, isRisk: true),
                            _idDetail(context, "EXPIRES", DateFormat('dd MMM yy').format(tourist.tripEndDate)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          if (tourist.offlineModeRequired || isMock)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.l),
              child: EliteSurface(
                color: AppColors.zoneYellow.withOpacity(0.1),
                padding: const EdgeInsets.all(AppSpacing.m),
                child: Row(
                  children: [
                    Icon(Icons.offline_pin_rounded, color: isMock ? AppColors.zoneRed : AppColors.zoneYellow, size: 18),
                    const SizedBox(width: AppSpacing.m),
                    Expanded(
                      child: Text(
                        isMock ? "FORCED MOCK MODE ACTIVE. SYSTEM EMULATING OFFLINE STATE." : "OFFLINE PROTECTION ACTIVE. POOR CONNECTIVITY DETECTED.",
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: isMock ? AppColors.zoneRed : AppColors.zoneYellow),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: AppSpacing.xl),

          ...tourist.selectedDestinations.map((dest) => EliteSurface(
                margin: const EdgeInsets.only(bottom: AppSpacing.s),
                padding: const EdgeInsets.all(AppSpacing.m),
                child: Row(
                  children: [
                    Icon(Icons.push_pin_rounded, color: theme.colorScheme.primary, size: 16),
                    const SizedBox(width: AppSpacing.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(dest.name.toUpperCase(), style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w900, fontSize: 12)),
                          Text(
                            "${DateFormat('MMM dd').format(dest.visitDateFrom)} — ${DateFormat('MMM dd').format(dest.visitDateTo)}",
                            style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withOpacity(0.4), fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )).toList(),
          
          const SizedBox(height: AppSpacing.xl),

          EliteSurface(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.m),
                  decoration: BoxDecoration(
                    color: Colors.white, 
                    borderRadius: BorderRadius.circular(AppSpacing.radiusM),
                  ),
                  child: QrImageView(
                    data: tourist.qrData,
                    version: QrVersions.auto,
                    size: 160.0,
                    gapless: true,
                    eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: AppColors.midnight),
                    dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: AppColors.midnight),
                  ),
                ),
                const SizedBox(height: AppSpacing.l),
                Text(
                  "SECURE IDENTITY TOKEN",
                  style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.3), fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 2),
                ),
                const SizedBox(height: AppSpacing.xl),
                Divider(color: theme.colorScheme.onSurface.withOpacity(0.08)),
                ExpansionTile(
                  title: Text("SECURE HASH", style: TextStyle(color: theme.colorScheme.primary.withOpacity(0.6), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
                      child: SelectableText(
                        tourist.blockchainHash,
                        style: TextStyle(fontSize: 9, color: theme.colorScheme.onSurface.withOpacity(0.4), fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: AppSpacing.xxl),
          
          EliteButton(
            onPressed: () => _confirmLogout(context),
            isPrimary: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.logout_rounded, size: 16),
                const SizedBox(width: AppSpacing.m),
                Text("TERMINATE SESSION", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1, color: theme.colorScheme.primary)),
              ],
            ),
          ),
          
          const SizedBox(height: AppSpacing.xl),
          
          GestureDetector(
            onTap: _handleDevTap,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.m),
              child: Text(
                "SAFEROUTE ELITE v1.0.4 PROD",
                style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.05), fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusM)),
        title: const Text("TERMINATE SESSION?", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
        content: const Text("Tracking will stop and local data will be purged.", style: TextStyle(color: Colors.white54, fontSize: 12)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("NO", style: TextStyle(color: Colors.white24, fontSize: 11))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text("YES, LOGOUT", style: TextStyle(color: AppColors.zoneRed, fontWeight: FontWeight.w900, fontSize: 11)),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      await context.read<TouristProvider>().logout();
      if (!context.mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const OnboardingScreen()),
        (route) => false,
      );
    }
  }

  Widget _idDetail(BuildContext context, String label, String value, {bool isRisk = false}) {
    final theme = Theme.of(context);
    Color valueColor = theme.colorScheme.onSurface;
    if (isRisk) {
      if (value == "MODERATE") valueColor = AppColors.zoneYellow;
      if (value == "HIGH" || value == "CRITICAL") valueColor = AppColors.zoneRed;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.3), fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1)),
        const SizedBox(height: 4),
        Text(
          value.toUpperCase(),
          style: TextStyle(color: valueColor, fontWeight: FontWeight.w900, fontSize: 12),
        ),
      ],
    );
  }
}

class _HolographicPainter extends CustomPainter {
  final bool isDark;
  _HolographicPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withOpacity(0.05)
      ..strokeWidth = 1;

    for (double i = 0; i < size.height; i += 4) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
