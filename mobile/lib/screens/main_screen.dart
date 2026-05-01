// lib/main_screen.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:saferoute/utils/app_theme.dart';
import 'package:saferoute/providers/location_provider.dart';
import 'package:saferoute/providers/tourist_provider.dart';
import 'package:saferoute/providers/navigation_provider.dart';
import 'package:saferoute/widgets/premium_widgets.dart';

// Screens (v2 - FAANG Grade Redesign)
import 'package:saferoute/screens/home_screen_v2.dart';
import 'package:saferoute/screens/digital_id_screen_v2.dart';
import 'package:saferoute/screens/group_safety_screen_v2.dart';
import 'package:saferoute/mesh/screens/mesh_status_screen.dart';
import 'package:saferoute/screens/sos_screen_v2.dart';
import 'package:saferoute/screens/navigation_screen_v2.dart';
import 'package:saferoute/screens/onboarding_screen.dart';
import 'package:saferoute/models/tourist_model.dart';
import 'package:saferoute/mesh/providers/mesh_provider.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  // Entry animation controller
  late AnimationController _entryCtrl;

  final List<Widget> _screens = [
    const HomeScreenV2(),
    const DigitalIDScreenV2(),
    const GroupSafetyScreenV2(),
    const MeshStatusScreen(),
    const SOSScreenV2(),
    const NavigationScreenV2(),
  ];

  String _getAppBarTitle(int index) {
    switch (index) {
      case 0:
        return "DASHBOARD";
      case 1:
        return "SAFETY ID";
      case 2:
        return "GROUP NETWORK";
      case 3:
        return "MESH STATUS";
      case 4:
        return "EMERGENCY SOS";
      case 5:
        return "LIVE NAVIGATION";
      default:
        return "SAFEROUTE";
    }
  }

  @override
  void initState() {
    super.initState();

    // Entry animation — scale + fade + slide for premium feel
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _entryCtrl.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startSafetyServices();
    });
  }

  Future<void> _startSafetyServices() async {
    final touristProv = context.read<TouristProvider>();
    final locationProvider = context.read<LocationProvider>();
    final meshProvider = context.read<MeshProvider>();

    if (touristProv.userState == UserState.GUEST &&
        touristProv.guestSessionId == null) {
      await touristProv.setGuestMode();
    }

    if (!mounted) return;

    final isGuest = touristProv.userState == UserState.GUEST;
    final userId =
        isGuest ? touristProv.guestSessionId : touristProv.tourist?.touristId;

    if (userId == null || userId.isEmpty) {
      debugPrint(
          'MainScreen: skipping safety services until identity is ready.');
      return;
    }

    await locationProvider.startTracking();
    if (!mounted) return;

    meshProvider.setGuestMode(isGuest);
    await meshProvider.init(userId);
    await meshProvider.startMesh();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout Safety Protocol?'),
        content: const Text(
            'Your local safety data will be securely wiped. This action is irreversible.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCEL')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('LOGOUT',
                style: TextStyle(
                    color: AppColors.danger, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (!mounted) return;
      await context.read<TouristProvider>().logout();
      if (!mounted) return;

      // Navigate to Onboarding and clear stack
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => OnboardingScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final navProv = context.watch<MainNavigationProvider>();
    final currentIndex = navProv.currentIndex;
    final isOnline = context.watch<TouristProvider>().isOnline;
    final locationProvider = context.watch<LocationProvider>();
    final isTracking = locationProvider.isTracking;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 400),
          opacity: navProv.isImmersive ? 0.0 : 1.0,
          child: IgnorePointer(
            ignoring: navProv.isImmersive,
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: AppBar(
                  title: Text(
                    _getAppBarTitle(currentIndex),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  actions: [
                    _LiveStatusChip(isTracking: isTracking, isOnline: isOnline),
                    IconButton(
                      icon: Icon(Icons.logout_rounded,
                          size: 20,
                          color: theme.colorScheme.onSurface.withOpacity(0.4)),
                      onPressed: () => _handleLogout(context),
                      tooltip: 'Logout',
                    ),
                    const SizedBox(width: AppSpacing.s),
                  ],
                  elevation: 0,
                  backgroundColor: theme.brightness == Brightness.dark
                      ? Colors.black.withOpacity(0.6)
                      : Colors.white.withOpacity(0.6),
                ),
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          // ── Animated Content Layer (Liquid Transitions) ──────────────────
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 600),
            switchInCurve: Curves.easeOutQuart,
            switchOutCurve: Curves.easeInQuart,
            transitionBuilder: (Widget child, Animation<double> animation) {
              final slideAnimation = Tween<Offset>(
                begin: const Offset(0.0, 0.05),
                end: Offset.zero,
              ).animate(animation);

              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: slideAnimation,
                  child: ScaleTransition(
                    scale:
                        Tween<double>(begin: 0.98, end: 1.0).animate(animation),
                    child: child,
                  ),
                ),
              );
            },
            child: KeyedSubtree(
              key: ValueKey<int>(currentIndex),
              child: _screens[currentIndex],
            ),
          ),

          // ── Floating Mission Dock (Mission Control) ──────────────────────
          AnimatedPositioned(
            duration: const Duration(milliseconds: 400),
            bottom: navProv.isImmersive ? -150 : 30,
            left: 20,
            right: 20,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: navProv.isImmersive ? 0.0 : 1.0,
              child: IgnorePointer(
                ignoring: navProv.isImmersive,
                child: MissionDock(
                  currentIndex: currentIndex,
                  onChanged: (index) => navProv.setIndex(index),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mission Dock Component ──────────────────────────────────────────────────
class MissionDock extends StatelessWidget {
  final int currentIndex;
  final Function(int) onChanged;

  const MissionDock(
      {super.key, required this.currentIndex, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return EliteSurface(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      borderRadius: 40,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _SpringDockItem(
            icon: Icons.grid_view_rounded,
            label: 'Home',
            isSelected: currentIndex == 0,
            onTap: () => onChanged(0),
          ),
          _SpringDockItem(
            icon: Icons.badge_rounded,
            label: 'ID',
            isSelected: currentIndex == 1,
            onTap: () => onChanged(1),
          ),
          _SpringDockItem(
            icon: Icons.group_rounded,
            label: 'Team',
            isSelected: currentIndex == 2,
            onTap: () => onChanged(2),
          ),
          _SpringDockItem(
            icon: Icons.hub_rounded,
            label: 'Mesh',
            isSelected: currentIndex == 3,
            onTap: () => onChanged(3),
          ),
          _SpringDockItem(
            icon: Icons.sos_rounded,
            label: 'SOS',
            isSelected: currentIndex == 4,
            color: AppColors.danger,
            onTap: () => onChanged(4),
          ),
          _SpringDockItem(
            icon: Icons.explore_rounded,
            label: 'Map',
            isSelected: currentIndex == 5,
            onTap: () => onChanged(5),
          ),
        ],
      ),
    );
  }
}

class _SpringDockItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final Color? color;

  const _SpringDockItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.color,
  });

  @override
  State<_SpringDockItem> createState() => _SpringDockItemState();
}

class _SpringDockItemState extends State<_SpringDockItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _scale = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _anim, curve: Curves.elasticOut),
    );
  }

  @override
  void didUpdateWidget(_SpringDockItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected) {
      _anim.forward();
    } else {
      _anim.reverse();
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isSelected
        ? (widget.color ?? AppColors.primaryHighContrast)
        : Colors.white38;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: _scale,
              child: Icon(widget.icon, color: color, size: 24),
            ),
            if (widget.isSelected)
              Container(
                margin: const EdgeInsets.only(top: 4),
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: color.withOpacity(0.5), blurRadius: 4)
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Live Status Chip ─────────────────────────────────────────────────────────
// Subtly animated indicator in the AppBar
class _LiveStatusChip extends StatefulWidget {
  final bool isTracking;
  final bool isOnline;
  const _LiveStatusChip({required this.isTracking, required this.isOnline});

  @override
  State<_LiveStatusChip> createState() => _LiveStatusChipState();
}

class _LiveStatusChipState extends State<_LiveStatusChip>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.isTracking ? AppColors.zoneGreen : AppColors.zoneYellow;
    final label = widget.isTracking
        ? (widget.isOnline ? "TRACKING" : "OFFLINE")
        : "STARTING...";

    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08 + (_pulseAnim.value * 0.06)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: color.withOpacity(_pulseAnim.value),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: color.withOpacity(0.5), blurRadius: 4)
                ],
              ),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 8,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
