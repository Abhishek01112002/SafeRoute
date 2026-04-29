import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:saferoute/utils/app_theme.dart';
import 'package:saferoute/widgets/premium_widgets.dart';
import 'package:saferoute/services/api_service.dart';
import 'package:saferoute/services/database_service.dart';
import 'package:saferoute/providers/location_provider.dart';
import 'package:saferoute/providers/tourist_provider.dart';
import 'package:flutter/services.dart';
import 'package:saferoute/utils/constants.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> with SingleTickerProviderStateMixin {
  bool _isSosActive = false;
  double _pressProgress = 0.0;
  Timer? _timer;
  DateTime? _sosSentAt;
  bool _isOfflineStored = false;
  String _sosStatus = "";

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _pulseController.repeat(reverse: true);
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (mounted) {
        setState(() {
          _pressProgress += 0.1 / kSosHoldDuration;
          if (_pressProgress >= 1.0) {
            _timer?.cancel();
            _pulseController.stop();
            _triggerSos();
          }
        });
      }
    });
  }

  void _cancelTimer() {
    _timer?.cancel();
    if (!_isSosActive) {
      _pulseController.stop();
      _pulseController.reset();
      if (mounted) {
        setState(() {
          _pressProgress = 0.0;
        });
      }
    }
  }

  void _triggerSos() async {
    final locProv = context.read<LocationProvider>();
    final tourist = context.read<TouristProvider>().tourist;
    final isOnline = context.read<TouristProvider>().isOnline;

    if (mounted) setState(() => _sosStatus = "ACQUIRING POSITION...");
    final location = locProv.currentPosition;

    if (tourist == null || location == null) {
      if (mounted) setState(() => _sosStatus = "");
      return;
    }

    final theme = Theme.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusM)),
        title: Text("PROCEED WITH SOS?", style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w900, fontSize: 16)),
        content: Text("Emergency services and contacts will receive your live coordinates.", 
          style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.54), fontSize: 12)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text("CANCEL", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.24)))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("SEND SOS", style: TextStyle(color: AppColors.zoneRed, fontWeight: FontWeight.w900))),
        ],
      ),
    );

    if (confirm == true) {
      if (!mounted) return;
      try {
        locProv.setSosActive(true);
        setState(() {
          _sosSentAt = DateTime.now();
          _sosStatus = "CONNECTING TO EMERGENCY SERVICES...";
        });

        const platform = MethodChannel('com.saferoute.app/sos');
        try { await platform.invokeMethod('startSOS').timeout(const Duration(seconds: 3)); } catch (_) {}

        final apiService = ApiService();
        final dbService = DatabaseService();

        if (isOnline) {
          try {
            if (mounted) setState(() => _sosStatus = "BROADCASTING VIA IP...");
            await apiService.sendSosAlert(location.latitude, location.longitude, "MANUAL", touristId: tourist.touristId).timeout(const Duration(seconds: 10));
            if (mounted) setState(() { _isOfflineStored = false; _sosStatus = "SIGNAL CONFIRMED ✓"; });
          } catch (e) {
            if (mounted) setState(() => _sosStatus = "NETWORK UNSTABLE — BUFFERING LOCALLY...");
            await dbService.saveSosEvent(touristId: tourist.touristId, latitude: location.latitude, longitude: location.longitude, triggerType: "MANUAL");
            if (mounted) setState(() { _isOfflineStored = true; _sosStatus = "SOS BUFFERED OFFLINE"; });
          }
        } else {
          await dbService.saveSosEvent(touristId: tourist.touristId, latitude: location.latitude, longitude: location.longitude, triggerType: "MANUAL");
          if (mounted) setState(() { _isOfflineStored = true; _sosStatus = "QUEUED — MESH RELAY ACTIVE"; });
        }
      } catch (e) {
        if (mounted) setState(() => _sosStatus = "CRITICAL ERROR — SOS BUFFERED");
      }
    } else {
      if (mounted) setState(() { _pressProgress = 0.0; _sosStatus = ""; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final location = context.watch<LocationProvider>().currentPosition;
    final tourist = context.watch<TouristProvider>().tourist;
    final isSosActive = context.watch<LocationProvider>().isSosActive;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          _SosRadarBg(color: isSosActive ? AppColors.zoneRed : theme.colorScheme.primary.withOpacity(0.3)),
          ListView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: AppSpacing.xxl),
            children: [
              if (tourist != null) _buildSafetyStatus(tourist),
              const SizedBox(height: AppSpacing.m),
              _buildCoordsHud(location, theme),
              const SizedBox(height: AppSpacing.xxl),
              _buildPanicTrigger(isSosActive, theme),
              const SizedBox(height: AppSpacing.xxl),
              if (isSosActive) _buildSosStatusPanel(theme),
              if (tourist != null) _buildDirectory(tourist, theme),
              const SizedBox(height: 120),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyStatus(dynamic tourist) {
    Color riskColor = (tourist.riskLevel == "HIGH" || tourist.riskLevel == "CRITICAL") ? AppColors.zoneRed : (tourist.riskLevel == "MODERATE" ? AppColors.zoneYellow : AppColors.zoneGreen);
    return EliteSurface(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: AppSpacing.m),
      child: Row(
        children: [
          Icon(Icons.shield_rounded, color: riskColor, size: 18),
          const SizedBox(width: AppSpacing.m),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("${tourist.riskLevel} ALERT STATUS", style: TextStyle(fontWeight: FontWeight.w900, color: riskColor, fontSize: 10)),
              Text(tourist.offlineModeRequired ? "HYBRID DEFENSE ACTIVE" : "STANDARD MONITORING", style: TextStyle(fontSize: 8, color: riskColor.withOpacity(0.5))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCoordsHud(dynamic location, ThemeData theme) {
    return EliteSurface(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.gps_fixed_rounded, color: theme.colorScheme.primary, size: 18),
              const SizedBox(width: AppSpacing.m),
              Text("MISSION COORDS", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4), fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 2)),
              const Spacer(),
              if (location != null) Text("STABLE SIGNAL", style: TextStyle(fontSize: 8, color: AppColors.zoneGreen, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: AppSpacing.m),
          if (location != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("${location.latitude.toStringAsFixed(6)}° N", style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w900)),
                Text("${location.longitude.toStringAsFixed(6)}° E", style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w900)),
              ],
            )
          else
            const GlimmerLoader(width: double.infinity, height: 20),
        ],
      ),
    );
  }

  Widget _buildPanicTrigger(bool isSosActive, ThemeData theme) {
    return Center(
      child: GestureDetector(
        onLongPressStart: (_) => isSosActive ? null : _startTimer(),
        onLongPressEnd: (_) => isSosActive ? null : _cancelTimer(),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 220, height: 220,
              decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: (isSosActive ? AppColors.zoneRed : AppColors.primary).withOpacity(0.1), blurRadius: 60)]),
            ),
            SizedBox(width: 200, height: 200, child: CircularProgressIndicator(value: _pressProgress, strokeWidth: 4, valueColor: AlwaysStoppedAnimation(isSosActive ? AppColors.zoneRed : AppColors.primary))),
            AnimatedBuilder(
              animation: _pulseController,
              builder: (ctx, child) => Transform.scale(scale: isSosActive ? 1.0 + (_pulseController.value * 0.05) : 1.0, child: child),
              child: Container(
                width: 170, height: 170,
                decoration: BoxDecoration(shape: BoxShape.circle, color: isSosActive ? AppColors.zoneRed : AppColors.primary, border: Border.all(color: Colors.white.withOpacity(0.2), width: 2)),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.sos_rounded, color: Colors.white, size: 48),
                  Text(isSosActive ? "ACTIVE" : "HOLD 3s", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10)),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSosStatusPanel(ThemeData theme) {
    return EliteSurface(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Column(
        children: [
          Text(_sosStatus.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.zoneRed)),
          const SizedBox(height: AppSpacing.m),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _statusBadge("IP", !_isOfflineStored),
              _statusBadge("MESH", _isOfflineStored),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String label, bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), color: active ? AppColors.zoneGreen.withOpacity(0.1) : Colors.transparent, border: Border.all(color: active ? AppColors.zoneGreen : Colors.white10)),
      child: Text(label, style: TextStyle(fontSize: 8, color: active ? AppColors.zoneGreen : Colors.white38)),
    );
  }

  Widget _buildDirectory(dynamic tourist, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.xl),
        Text("EMERGENCY DIRECTORY", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface.withOpacity(0.3))),
        const SizedBox(height: AppSpacing.m),
        _contactItem("REGIONAL HUB", "112", true, theme),
        _contactItem(tourist.emergencyContactName.toUpperCase(), tourist.emergencyContactPhone, false, theme),
      ],
    );
  }

  Widget _contactItem(String name, String phone, bool official, ThemeData theme) {
    return EliteSurface(
      margin: const EdgeInsets.only(bottom: AppSpacing.s),
      child: Row(
        children: [
          Icon(official ? Icons.emergency_rounded : Icons.person_rounded, color: theme.colorScheme.primary, size: 18),
          const SizedBox(width: AppSpacing.m),
          Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12))),
          IconButton(onPressed: () => launchUrl(Uri.parse("tel:$phone")), icon: const Icon(Icons.call_rounded, color: AppColors.zoneGreen, size: 18)),
        ],
      ),
    );
  }
}

class _SosRadarBg extends StatefulWidget {
  final Color color;
  const _SosRadarBg({required this.color});
  @override
  State<_SosRadarBg> createState() => _SosRadarBgState();
}

class _SosRadarBgState extends State<_SosRadarBg> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(animation: _ctrl, builder: (ctx, child) => CustomPaint(painter: _RadarPainter(progress: _ctrl.value, color: widget.color), child: Container()));
  }
}

class _RadarPainter extends CustomPainter {
  final double progress;
  final Color color;
  _RadarPainter({required this.progress, required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withOpacity((1 - progress) * 0.2)..style = PaintingStyle.stroke..strokeWidth = 2;
    canvas.drawCircle(Offset(size.width / 2, size.height / 2.5), progress * size.width * 0.8, paint);
    canvas.drawCircle(Offset(size.width / 2, size.height / 2.5), ((progress + 0.5) % 1.0) * size.width * 0.8, paint);
  }
  @override
  bool shouldRepaint(CustomPainter old) => true;
}
