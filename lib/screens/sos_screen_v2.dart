// lib/screens/sos_screen_v2.dart - Emergency SOS Screen (Elite)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:saferoute/services/api_service.dart';
import 'package:saferoute/services/database_service.dart';
import 'package:saferoute/providers/location_provider.dart';
import 'package:saferoute/utils/app_theme.dart';
import 'package:saferoute/providers/tourist_provider.dart';
import 'package:saferoute/mesh/providers/mesh_provider.dart';
import 'package:saferoute/widgets/premium_widgets.dart';
import 'dart:ui';
import 'dart:math' as math;

class SOSScreenV2 extends StatefulWidget {
  const SOSScreenV2({super.key});

  @override
  State<SOSScreenV2> createState() => _SOSScreenV2State();
}

class _SOSScreenV2State extends State<SOSScreenV2>
    with TickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late AnimationController _vignetteCtrl;
  late Animation<double> _pulseAnim;
  late Animation<double> _vignetteAnim;

  bool _isActivated = false;
  int _holdDuration = 0;
  final int _requiredHoldTime = 3000;
  bool _isHolding = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _vignetteCtrl = AnimationController(
       vsync: this,
       duration: const Duration(milliseconds: 3000),
    );

    _pulseAnim = Tween<double>(begin: 0.8, end: 1.8).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut),
    );
    
    _vignetteAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _vignetteCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _vignetteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Red Tinted Aurora Background
          Positioned.fill(
            child: Opacity(
              opacity: 0.3,
              child: const AuroraBackground(),
            ),
          ),
          
          // 2. Animated Blood-Pulse Vignette
          AnimatedBuilder(
            animation: _vignetteAnim,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      Colors.transparent,
                      AppColors.danger.withOpacity(0.4 * _vignetteAnim.value),
                    ],
                    stops: const [0.4, 1.0],
                  ),
                ),
              );
            },
          ),

          SafeArea(
            child: _isActivated ? _buildActivated(theme) : _buildIdle(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildIdle(ThemeData theme) {
    final tourist = context.watch<TouristProvider>().tourist;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const EliteSurface(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            borderRadius: 30,
            color: Colors.white10,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.danger),
                SizedBox(width: 8),
                Text(
                  'EMERGENCY COMMS ACTIVE',
                  style: TextStyle(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          Stack(
            alignment: Alignment.center,
            children: [
              ScaleTransition(
                scale: _pulseAnim,
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.danger.withOpacity(0.2),
                      width: 4,
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onLongPressStart: (_) {
                  setState(() {
                    _isHolding = true;
                    _holdDuration = 0;
                  });
                  _vignetteCtrl.forward();
                  _simulateHold();
                },
                onLongPressEnd: (_) {
                  _vignetteCtrl.reverse();
                  if (_holdDuration < _requiredHoldTime) {
                    setState(() {
                      _isHolding = false;
                      _holdDuration = 0;
                    });
                  }
                },
                child: EliteSurface(
                  width: 180,
                  height: 180,
                  borderRadius: 100,
                  color: AppColors.danger,
                  borderColor: Colors.white24,
                  blur: 30,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.sos_rounded, size: 60, color: Colors.white),
                        if (_holdDuration > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 12.0),
                            child: Text(
                              '${((_requiredHoldTime - _holdDuration) / 1000).toStringAsFixed(1)}s',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
          Text(
            'HOLD TO TRANSMIT',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              color: AppColors.danger,
            ),
          ),
          
          const SizedBox(height: 40),
          
          // Quick Call Options (Issue #5 Fix)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Row(
              children: [
                Expanded(
                  child: _buildCallAction(
                    icon: Icons.local_police_rounded,
                    label: 'CALL 112',
                    color: AppColors.info,
                    onTap: () => _makePhoneCall('112'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildCallAction(
                    icon: Icons.contact_emergency_rounded,
                    label: 'EMERGENCY CONTACT',
                    color: AppColors.warning,
                    onTap: () {
                      if (tourist != null) {
                        _makePhoneCall(tourist.emergencyContactPhone);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return EliteSurface(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      color: color.withOpacity(0.1),
      borderColor: color,
      borderOpacity: 0.3,
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivated(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              PulseMarker(color: AppColors.success, size: 40),
              EliteSurface(
                width: 140,
                height: 140,
                borderRadius: 70,
                color: AppColors.success,
                child: const Icon(
                  Icons.wifi_tethering_rounded,
                  size: 60,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
          Text(
            'SIGNAL BROADCASTING',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              color: AppColors.success,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'RESCUE TEAMS HAVE BEEN NOTIFIED',
            style: theme.textTheme.labelMedium?.copyWith(
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 60),
          EliteSurface(
            onTap: () => setState(() => _isActivated = false),
            width: 200,
            color: Colors.white12,
            child: const Center(
              child: Text(
                'CANCEL ALERT',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _simulateHold() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted && _isHolding) {
        setState(() => _holdDuration += 100);
        
        if (_holdDuration % 300 == 0) {
          HapticFeedback.mediumImpact();
        }
        
        if (_holdDuration < _requiredHoldTime) {
          _simulateHold();
        } else {
          _triggerSOS();
        }
      }
    });
  }

  Future<void> _triggerSOS() async {
    final locProv = context.read<LocationProvider>();
    final touristProv = context.read<TouristProvider>();
    final tourist = touristProv.tourist;
    
    if (tourist == null) return;

    setState(() => _isActivated = true);
    HapticFeedback.heavyImpact();

    Position? pos = locProv.currentPosition;
    
    if (pos == null || DateTime.now().difference(pos.timestamp).inMinutes > 5) {
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
      } catch (e) {
        pos = await Geolocator.getLastKnownPosition();
      }
    }

    if (pos == null) return;

    final api = ApiService();
    final db = DatabaseService();

    try {
      if (touristProv.isOnline) {
        await api.sendSosAlert(pos.latitude, pos.longitude, "MANUAL", touristId: tourist.touristId);
      } else {
        await db.saveSosEvent(
          touristId: tourist.touristId, 
          latitude: pos.latitude, 
          longitude: pos.longitude, 
          triggerType: "MANUAL"
        );
      }
    } catch (e) {
      await db.saveSosEvent(
          touristId: tourist.touristId, 
          latitude: pos.latitude, 
          longitude: pos.longitude, 
          triggerType: "MANUAL"
      );
    }

    try {
      final meshProv = context.read<MeshProvider>();
      if (meshProv.isMeshActive) {
        await meshProv.sendSosRelay(pos.latitude, pos.longitude);
      }
    } catch (_) {}
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: phoneNumber,
    );
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(
        launchUri,
        mode: LaunchMode.externalApplication,
      );
    } else {
      debugPrint('Could not launch $launchUri');
    }
  }
}
