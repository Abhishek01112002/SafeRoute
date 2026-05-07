import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:saferoute/tourist/providers/tourist_provider.dart';
import 'package:saferoute/authority/screens/authority_login_screen.dart';
import 'package:saferoute/authority/screens/authority_registration_screen.dart';
import 'package:saferoute/screens/developer_sandbox_screen.dart';
import 'package:saferoute/screens/permission_setup_screen.dart';
import 'package:saferoute/tourist/screens/registration_screen.dart';
import 'package:saferoute/utils/app_theme.dart';
import 'package:saferoute/widgets/app_ui.dart';
import 'package:saferoute/utils/env.dart';
import 'package:saferoute/widgets/premium_widgets.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          const Positioned.fill(child: AuroraBackground()),
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _OnboardingTopBar(onSkip: () => _handleSkip(context)),
                  const SizedBox(height: 28),
                  const _BrandHero(),
                  const SizedBox(height: 20),
                  const _SafetyPromiseCard(),
                  const SizedBox(height: 28),
                  const _SectionLabel('Choose your access'),
                  const SizedBox(height: 12),
                  _roleCard(
                    context,
                    title: 'Tourist Module',
                    subtitle:
                        'Register identity, cache routes, and enable SOS context.',
                    icon: Icons.person_pin_circle_rounded,
                    color: AppColors.primary,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const RegistrationScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _roleCard(
                    context,
                    title: 'Authority Hub',
                    subtitle:
                        'Review zones, dispatch SOS alerts, and manage field ops.',
                    icon: Icons.security_rounded,
                    color: AppColors.accent,
                    onTap: () => _showAuthorityOptions(context),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: TextButton(
                      onPressed: () => _showLoginDialog(context),
                      child: const Text(
                        'Already registered? Restore your tourist ID',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  if (Env.isDev) ...[
                    const SizedBox(height: 18),
                    EliteButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DeveloperSandboxScreen(),
                        ),
                      ),
                      child: const Text('ACCESS DEV SANDBOX'),
                    ),
                  ],
                ],
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
        padding: const EdgeInsets.all(18),
        borderRadius: AppSpacing.radiusL,
        color: theme.colorScheme.surface,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Authority access',
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Secure entry for rescue teams and local administrators.',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.64),
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            _authorityTile(
              context,
              icon: Icons.key_rounded,
              label: 'Access command center',
              color: AppColors.primary,
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AuthorityLoginScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _authorityTile(
              context,
              icon: Icons.assignment_ind_rounded,
              label: 'Enlist new personnel',
              color: AppColors.accent,
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AuthorityRegistrationScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _authorityTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return AppSurface(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      color: color.withValues(alpha: 0.12),
      borderColor: color.withValues(alpha: 0.35),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
          Icon(Icons.chevron_right_rounded,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.54),
              size: 22),
        ],
      ),
    );
  }

  Widget _roleCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return AppSurface(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      color: theme.colorScheme.surface,
      borderColor: color.withValues(alpha: 0.30),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: color.withValues(alpha: 0.14),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.3,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.arrow_forward_rounded, size: 20, color: color),
        ],
      ),
    );
  }

  Future<void> _handleSkip(BuildContext context) async {
    final touristProvider = context.read<TouristProvider>();
    await touristProvider.setGuestMode();
    if (context.mounted) {
      unawaited(Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PermissionSetupScreen()),
      ));
    }
  }

  void _showLoginDialog(BuildContext context) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusL),
        ),
        title: const Text(
          'Restore tourist ID',
          style: TextStyle(
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter your tourist identity number to restore your authenticated session.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: AppSpacing.l),
            AppSurface(
              padding: EdgeInsets.zero,
              child: TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: 'TID-XXXX-XXXX',
                  border: InputBorder.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          EliteButton(
            isFullWidth: false,
            onPressed: () async {
              final provider = context.read<TouristProvider>();
              if (provider.isLocked) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Account locked. Try again in ${provider.remainingLockSeconds}s',
                    ),
                  ),
                );
                return;
              }

              final id = controller.text.trim();
              if (id.isEmpty) return;

              final success = await provider.loginTouristSecure(id);
              if (success && ctx.mounted) {
                Navigator.pop(ctx);
                unawaited(Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PermissionSetupScreen(),
                  ),
                ));
              } else if (ctx.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      provider.errorMessage ?? 'Invalid ID or login failed',
                    ),
                    backgroundColor: AppColors.danger,
                  ),
                );
              }
            },
            child: const Text('Restore'),
          ),
        ],
      ),
    );
  }
}

class _OnboardingTopBar extends StatelessWidget {
  final VoidCallback onSkip;

  const _OnboardingTopBar({required this.onSkip});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        const Icon(Icons.shield_rounded, color: AppColors.primary, size: 24),
        const SizedBox(width: 8),
        Text(
          'SafeRoute',
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: onSkip,
          icon: const Icon(Icons.dashboard_customize_rounded, size: 16),
          label: const Text('Guest mode'),
          style: TextButton.styleFrom(
            foregroundColor:
                theme.colorScheme.onSurface.withValues(alpha: 0.72),
          ),
        ),
      ],
    );
  }
}

class _BrandHero extends StatelessWidget {
  const _BrandHero();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your safety companion for remote trails.',
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontSize: 28,
            height: 1.12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Offline routes, BLE mesh relay, identity verification, and SOS context in one field-ready app.',
          style: TextStyle(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.70),
            fontSize: 14,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _SafetyPromiseCard extends StatelessWidget {
  const _SafetyPromiseCard();

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      padding: const EdgeInsets.all(14),
      color: Theme.of(context).colorScheme.surface,
      borderColor: AppColors.accent.withValues(alpha: 0.28),
      child: const Row(
        children: [
          _PromiseItem(icon: Icons.offline_pin_rounded, label: 'Offline ready'),
          _PromiseDivider(),
          _PromiseItem(icon: Icons.hub_rounded, label: 'Mesh relay'),
          _PromiseDivider(),
          _PromiseItem(icon: Icons.sos_rounded, label: 'SOS context'),
        ],
      ),
    );
  }
}

class _PromiseItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _PromiseItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: AppColors.accent, size: 20),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PromiseDivider extends StatelessWidget {
  const _PromiseDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 36,
      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.28),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: TextStyle(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
    );
  }
}
