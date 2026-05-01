// lib/screens/tactical_ar_screen.dart
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'package:saferoute/providers/location_provider.dart';
import 'package:saferoute/utils/app_theme.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'dart:ui';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:saferoute/widgets/premium_widgets.dart';
import 'package:permission_handler/permission_handler.dart';

class TacticalARScreen extends StatefulWidget {
  final LatLng? targetDestination;
  const TacticalARScreen({super.key, this.targetDestination});

  @override
  State<TacticalARScreen> createState() => _TacticalARScreenState();
}

class _TacticalARScreenState extends State<TacticalARScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isInitialized = false;
  bool _isInitializing = false;
  String? _errorMessage;

  // Navigation State
  double _smoothHeading = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Hard Constraint: Lock Portrait
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    _initCamera();
  }

  Future<void> _initCamera() async {
    if (_isInitializing) return;
    _isInitializing = true;

    try {
      final cameras = await availableCameras();
      if (!mounted) return;

      if (cameras.isEmpty) {
        setState(() => _errorMessage = "No camera hardware detected.");
        return;
      }

      // Medium resolution for battery/performance balance
      _controller = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();

      if (!mounted) return;

      setState(() {
        _isInitialized = true;
        _errorMessage = null;
      });
    } catch (e) {
      debugPrint("AR Camera Error: $e");
      if (mounted) {
        setState(() =>
            _errorMessage = "Camera initialization failed. Check permissions.");
      }
    } finally {
      _isInitializing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    // Hard Constraint: Restore Orientations
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locProv = context.watch<LocationProvider>();

    // Safety Guard: Battery Exit (< 10%)
    if (locProv.batteryLevel < 0.10) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text("AR Terminated: Critical Battery Level"),
                backgroundColor: Colors.red),
          );
          Navigator.pop(context);
        }
      });
    }

    // Safety Guard: Idle Exit (> 30s)
    final idleSeconds = DateTime.now()
        .difference(locProv.currentPosition?.timestamp ?? DateTime.now())
        .inSeconds;
    if (idleSeconds > 30) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text("AR Terminated: No movement detected for 30s"),
                backgroundColor: Colors.orange),
          );
          Navigator.pop(context);
        }
      });
    }

    if (_errorMessage != null) {
      return _buildFallbackUI(context, _errorMessage!);
    }

    if (!_isInitialized || _controller == null) {
      return const Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: GlimmerLoader(width: 200, height: 2)));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Camera Feed with AspectRatio Fix
          Center(
            child: CameraPreview(_controller!),
          ),

          // 2. Glassmorphic HUD Overlay
          Positioned(
            top: 50,
            left: 20,
            right: 20,
            child: _buildHeaderHUD(locProv),
          ),

          // 3. Tactical AR Arrow (Directional)
          Center(
            child: _buildTacticalArrow(locProv),
          ),

          // 4. Information Panel
          Positioned(
            bottom: 120,
            left: 20,
            right: 20,
            child: _buildTelemetryPanel(locProv),
          ),

          // 5. Exit Control
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: FloatingActionButton.extended(
                elevation: 10,
                onPressed: () => Navigator.pop(context),
                backgroundColor: Colors.redAccent.withOpacity(0.8),
                icon: const Icon(Icons.close, color: Colors.white),
                label: const Text('TERMINATE SCAN',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackUI(BuildContext context, String error) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.compass_calibration_rounded,
                size: 80, color: AppColors.accent),
            const SizedBox(height: 24),
            Text("MISSION ADVISOR FALLBACK",
                style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 2)),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 14)),
            ),
            const SizedBox(height: 32),
            if (error.contains("permission"))
              EliteButton(
                onPressed: () => openAppSettings(),
                child: const Text("OPEN PERMISSION SETTINGS"),
              ),
            const SizedBox(height: 12),
            EliteButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("EXIT TO VECTOR MAP"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderHUD(LocationProvider loc) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.5),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('TACTICAL OVERLAY V2.0',
                      style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5)),
                  Text('BATTERY: ${(loc.batteryLevel * 100).toInt()}%',
                      style: TextStyle(
                          color: loc.batteryLevel < 0.2
                              ? Colors.redAccent
                              : Colors.white54,
                          fontSize: 9,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const Divider(color: Colors.white10, height: 20),
              Row(
                children: [
                  const Icon(Icons.gps_fixed,
                      size: 14, color: Colors.greenAccent),
                  const SizedBox(width: 8),
                  Text(
                      'GPS STRENGTH: ${loc.currentPosition?.accuracy.toStringAsFixed(1) ?? "0"}m',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if ((loc.currentPosition?.accuracy ?? 100) > 20)
                    const Text('⚠️ DRIFT DETECTED',
                        style: TextStyle(
                            color: Colors.orangeAccent,
                            fontSize: 9,
                            fontWeight: FontWeight.w900)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTacticalArrow(LocationProvider loc) {
    final pos = loc.currentPosition;
    if (pos == null || widget.targetDestination == null) {
      // Points North by default if no target
      final double h = (pos?.heading ?? 0.0).toDouble();
      return _renderArrow((0.0 - h) * (math.pi / 180));
    }

    // Constraint: Filter Accuracy > 20m
    if (pos.accuracy > 20.0) {
      return Opacity(
        opacity: 0.5,
        child: _renderArrow(_smoothHeading, warning: "LOW ACCURACY"),
      );
    }

    // Calculation: targetBearing = atan2(dy, dx)
    final double bearing = Geolocator.bearingBetween(
      pos.latitude,
      pos.longitude,
      widget.targetDestination!.latitude,
      widget.targetDestination!.longitude,
    );

    // Final Rotation: bearing - heading
    final targetRotation = (bearing - pos.heading) * (math.pi / 180);

    // Smoothing (Interpolation)
    _smoothHeading = targetRotation;

    return _renderArrow(targetRotation);
  }

  Widget _renderArrow(double rotation, {String? warning}) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: rotation),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      builder: (context, val, child) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0015) // Strong perspective
                ..rotateX(1.1) // "Flat" orientation
                ..rotateZ(val),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Pulse ring
                  Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AppColors.primary.withOpacity(0.2),
                            width: 1)),
                  ),
                  // The Arrow body
                  Container(
                    width: 45,
                    height: 160,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary,
                          AppColors.primary.withOpacity(0)
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(30),
                          topRight: Radius.circular(30)),
                      boxShadow: [
                        BoxShadow(
                            color: AppColors.primary.withOpacity(0.4),
                            blurRadius: 30,
                            spreadRadius: 10),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (warning != null)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: EliteSurface(
                    child: Text(warning,
                        style: const TextStyle(
                            color: Colors.orangeAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.w900))),
              ),
          ],
        );
      },
    );
  }

  Widget _buildTelemetryPanel(LocationProvider loc) {
    final pos = loc.currentPosition;
    String distance = "SEARCHING...";

    if (pos != null && widget.targetDestination != null) {
      final d = Geolocator.distanceBetween(
          pos.latitude,
          pos.longitude,
          widget.targetDestination!.latitude,
          widget.targetDestination!.longitude);
      distance = d > 1000
          ? "${(d / 1000).toStringAsFixed(2)} KM"
          : "${d.toInt()} METERS";
    }

    return EliteSurface(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _telemetryItem("RANGE TO TARGET", distance),
          Container(width: 1, height: 30, color: Colors.white10),
          _telemetryItem("BEARING", "${pos?.heading.toInt() ?? 0}°"),
          Container(width: 1, height: 30, color: Colors.white10),
          _telemetryItem("ALTITUDE", "${pos?.altitude.toInt() ?? 0} M"),
        ],
      ),
    );
  }

  Widget _telemetryItem(String label, String value) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(
                color: Colors.white38,
                fontSize: 8,
                fontWeight: FontWeight.w900,
                letterSpacing: 1)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace')),
      ],
    );
  }
}
