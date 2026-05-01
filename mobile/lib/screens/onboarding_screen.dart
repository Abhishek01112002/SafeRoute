// lib/screens/onboarding_screen.dart
import 'package:flutter/material.dart';
import 'package:saferoute/utils/app_theme.dart';
import 'package:saferoute/widgets/premium_widgets.dart';

// Screens
import 'package:saferoute/screens/registration_screen.dart';
import 'package:saferoute/screens/authority_login_screen.dart';
import 'package:saferoute/screens/authority_registration_screen.dart';
import 'package:saferoute/screens/permission_setup_screen.dart';
import 'package:provider/provider.dart';
import 'package:saferoute/providers/tourist_provider.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: [
          // ── Premium Aurora Canvas ──
          Positioned.fill(child: AuroraBackground()),

          // ── Top Action Bar (Skip) ──
          Positioned(
            top: MediaQuery.of(context).padding.top + AppSpacing.s,
            right: AppSpacing.m,
            child: TextButton.icon(
              onPressed: () => _handleSkip(context),
              icon: const Icon(Icons.forward_rounded, size: 16),
              label: const Text(
                "SKIP TO DASHBOARD",
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                    letterSpacing: 1),
              ),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: Column(
                  children: [
                    const SizedBox(height: 80),

                    // ── Mission Logo ──
                    Hero(
                      tag: 'app_logo',
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.primary.withOpacity(0.05),
                          border: Border.all(
                              color:
                                  theme.colorScheme.primary.withOpacity(0.15)),
                          boxShadow: [
                            BoxShadow(
                                color:
                                    theme.colorScheme.primary.withOpacity(0.1),
                                blurRadius: 40,
                                spreadRadius: 5),
                          ],
                        ),
                        child: Icon(Icons.shield_rounded,
                            size: 80, color: theme.colorScheme.primary),
                      ),
                    ),

                    const SizedBox(height: AppSpacing.xxl),

                    // ── Brand Identity ──
                    Text(
                      "SAFEROUTE",
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 8.0,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      "NEXT-GEN TOURIST GUARDIAN",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withOpacity(0.4),
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        fontSize: 9,
                      ),
                    ),

                    const SizedBox(height: 40),

                    // ── Mission Statement ──
                    EliteSurface(
                      color: theme.colorScheme.primary.withOpacity(0.05),
                      padding: const EdgeInsets.all(AppSpacing.l),
                      child: Column(
                        children: [
                          Text(
                            "SafeRoute provides enterprise-grade safety monitoring even in zero-connectivity zones using BLE Mesh technology. Register your identity to ensure local authorities can locate you during emergencies.",
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              height: 1.6,
                              color:
                                  theme.colorScheme.onSurface.withOpacity(0.7),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _featureBadge(Icons.hub_rounded, "MESH"),
                              const SizedBox(width: 8),
                              _featureBadge(
                                  Icons.offline_pin_rounded, "OFFLINE"),
                              const SizedBox(width: 8),
                              _featureBadge(Icons.sos_rounded, "SOS"),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 100),

                    Text(
                      "INITIALIZE ACCESS ROLE",
                      style: TextStyle(
                          color: theme.colorScheme.onSurface.withOpacity(0.15),
                          letterSpacing: 3,
                          fontWeight: FontWeight.w900,
                          fontSize: 10),
                    ),

                    const SizedBox(height: AppSpacing.xl),

                    // ── Role Selection ──
                    _roleCard(
                      context,
                      "TOURIST MODULE",
                      "ENROLL & EXPLORE SAFELY",
                      Icons.person_pin_circle_rounded,
                      () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const RegistrationScreen())),
                    ),

                    const SizedBox(height: AppSpacing.m),

                    _roleCard(
                      context,
                      "AUTHORITY HUB",
                      "COMMAND & RESCUE OPS",
                      Icons.security_rounded,
                      () => _showAuthorityOptions(context),
                    ),

                    const SizedBox(height: AppSpacing.xl),

                    TextButton(
                      onPressed: () => _showLoginDialog(context),
                      child: Text(
                        "ALREADY REGISTERED? LOGIN",
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                          letterSpacing: 1,
                        ),
                      ),
                    ),

                    const SizedBox(height: 60),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAuthorityOptions(BuildContext context) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => EliteSurface(
        margin: const EdgeInsets.all(AppSpacing.l),
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("AUTHORITY CLEARANCE",
                style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0)),
            Text("SECURE GATEWAY FOR PERSONNEL",
                style: TextStyle(
                    color: theme.colorScheme.onSurface.withOpacity(0.3),
                    fontSize: 9,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: AppSpacing.xl),
            _authorityTile(
              context,
              Icons.key_rounded,
              "ACCESS COMMAND CENTER",
              theme.colorScheme.primary,
              () {
                Navigator.pop(ctx);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AuthorityLoginScreen()));
              },
            ),
            const SizedBox(height: AppSpacing.m),
            _authorityTile(
              context,
              Icons.assignment_ind_rounded,
              "ENLIST NEW PERSONNEL",
              AppColors.accent,
              () {
                Navigator.pop(ctx);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AuthorityRegistrationScreen()));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _authorityTile(BuildContext context, IconData icon, String label,
      Color color, VoidCallback onTap) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: EliteSurface(
        padding: const EdgeInsets.all(AppSpacing.m),
        color: color.withOpacity(0.05),
        borderOpacity: 0.1,
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: AppSpacing.m),
            Text(label,
                style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    letterSpacing: 0.5)),
            const Spacer(),
            Icon(Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurface.withOpacity(0.2), size: 20),
          ],
        ),
      ),
    );
  }

  Widget _roleCard(BuildContext context, String title, String subtitle,
      IconData icon, VoidCallback onTap) {
    final theme = Theme.of(context);
    final isTourist = title.contains("TOURIST");

    return EliteSurface(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.l, vertical: AppSpacing.xl),
      color: isTourist
          ? theme.colorScheme.primary.withOpacity(0.1)
          : Colors.transparent,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.m),
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (isTourist ? AppColors.primary : AppColors.accent)
                    .withOpacity(0.1)),
            child: Icon(icon,
                color: isTourist ? AppColors.primary : AppColors.accent,
                size: 24),
          ),
          const SizedBox(width: AppSpacing.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5)),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface.withOpacity(0.4))),
              ],
            ),
          ),
          Icon(Icons.arrow_forward_ios_rounded,
              size: 14,
              color: isTourist ? AppColors.primary : AppColors.accent),
        ],
      ),
    );
  }

  void _handleSkip(BuildContext context) async {
    final touristProvider = context.read<TouristProvider>();
    await touristProvider.setGuestMode();
    if (context.mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PermissionSetupScreen()),
      );
    }
  }

  void _showLoginDialog(BuildContext context) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.black.withOpacity(0.9),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusL)),
        title: const Text("SECURE LOGIN",
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: 1)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Enter your 12-digit Identity Protocol ID to restore your authenticated session.",
              style:
                  TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
            ),
            const SizedBox(height: AppSpacing.l),
            EliteSurface(
              child: TextField(
                controller: controller,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                  hintText: "TID-XXXX-XXXX",
                  hintStyle: TextStyle(color: Colors.white24),
                  border: InputBorder.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
          EliteButton(
            isFullWidth: false,
            onPressed: () async {
              final prov = context.read<TouristProvider>();
              if (prov.isLocked) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(
                          "Account locked. Try again in ${prov.remainingLockSeconds}s")),
                );
                return;
              }

              final id = controller.text.trim();
              if (id.isEmpty) return;

              final success = await prov.loginTouristSecure(id);
              if (success && ctx.mounted) {
                Navigator.pop(ctx);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const PermissionSetupScreen()),
                );
              } else if (ctx.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(prov.errorMessage ??
                        "Invalid ID or Authentication Failed"),
                    backgroundColor: AppColors.zoneRed,
                  ),
                );
              }
            },
            child: const Text("AUTHENTICATE"),
          ),
        ],
      ),
    );
  }

  Widget _featureBadge(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primary)),
        ],
      ),
    );
  }
}
