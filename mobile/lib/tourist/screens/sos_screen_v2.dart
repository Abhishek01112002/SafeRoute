import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'package:saferoute/core/constants/app_assets.dart';
import 'package:saferoute/tourist/providers/mesh_provider.dart';
import 'package:saferoute/tourist/models/tourist_model.dart';
import 'package:saferoute/tourist/providers/location_provider.dart';
import 'package:saferoute/tourist/providers/tourist_provider.dart';
import 'package:saferoute/services/analytics_service.dart';
import 'package:saferoute/services/api_service.dart';
import 'package:saferoute/services/database_service.dart';
import 'package:saferoute/utils/app_theme.dart';
import 'package:saferoute/widgets/premium_widgets.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:saferoute/core/service_locator.dart';
import 'package:uuid/uuid.dart';

class SOSScreenV2 extends StatefulWidget {
  const SOSScreenV2({super.key});

  @override
  State<SOSScreenV2> createState() => _SOSScreenV2State();
}

class _SOSScreenV2State extends State<SOSScreenV2>
    with TickerProviderStateMixin {
  late final AnimationController _holdController;
  late final AnimationController _pulseController;
  Timer? _hapticTicker;
  Timer? _statusPollTimer;
  int _statusPollAttempt = 0;

  bool _isActivated = false;
  bool _isTriggering = false;
  bool _isHolding = false;
  double _holdProgress = 0;
  final int _requiredHoldMs = 3000;

  String _sosHeadline = 'SOS QUEUED SECURELY';
  String _sosDeliveryMessage = 'SafeRoute is reaching authorities.';

  @override
  void initState() {
    super.initState();

    _holdController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _requiredHoldMs),
    )
      ..addListener(() {
        if (!mounted) return;
        setState(() => _holdProgress = _holdController.value);
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed &&
            _isHolding &&
            !_isTriggering) {
          _isHolding = false;
          _stopHapticTicker();
          _triggerSOS();
        }
      });

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _stopHapticTicker();
    _statusPollTimer?.cancel();
    _holdController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _SosBackdrop(),
          SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _isActivated
                  ? _buildActivated(key: const ValueKey('activated'))
                  : _buildIdle(key: const ValueKey('idle')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdle({required Key key}) {
    final touristProvider = context.watch<TouristProvider>();
    final tourist = touristProvider.tourist;
    final isGuest = touristProvider.userState == UserState.guest;

    return LayoutBuilder(
      key: key,
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 30),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _StatusBanner(isGuest: isGuest),
                const SizedBox(height: 34),
                Semantics(
                  button: true,
                  label: 'Emergency SOS. Press and hold for three seconds.',
                  child: GestureDetector(
                    onLongPressStart: _startHold,
                    onLongPressMoveUpdate: _checkHoldBounds,
                    onLongPressEnd: (_) => _cancelHold(resetVisuals: true),
                    onLongPressCancel: () => _cancelHold(resetVisuals: true),
                    onTap: () => _showHoldHint(),
                    child: _HoldToTriggerButton(
                      holdProgress: _holdProgress,
                      pulseController: _pulseController,
                      isHolding: _isHolding,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _isHolding
                      ? 'Keep holding... ${(_requiredHoldMs / 1000 * (1 - _holdProgress)).clamp(0.0, 3.0).toStringAsFixed(1)}s'
                      : 'PRESS & HOLD 3s TO SEND SOS',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _isHolding ? Colors.white : Colors.white70,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 28),
                _QuickCallRow(tourist: tourist, onCall: _makePhoneCall),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActivated({required Key key}) {
    final touristProvider = context.watch<TouristProvider>();
    final meshProvider = context.watch<MeshProvider>();
    final locationProvider = context.watch<LocationProvider>();
    final position = locationProvider.currentPosition;

    return SingleChildScrollView(
      key: key,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: MediaQuery.of(context).size.height -
              MediaQuery.of(context).padding.vertical -
              44,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const _ActivatedVisual(),
            const SizedBox(height: 24),
            Text(
              _sosHeadline,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 28,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _sosDeliveryMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 32),
            _EmergencyDeliveryCard(
              isOnline: touristProvider.isOnline,
              isMeshActive: meshProvider.isMeshActive,
              meshNodes: meshProvider.nearbyNodes.length,
              gpsLabel: position == null
                  ? 'GPS FALLBACK'
                  : '${position.accuracy.toStringAsFixed(0)} M FIX',
            ),
            const SizedBox(height: 14),
            EliteSurface(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              borderRadius: 18,
              color: Colors.white.withValues(alpha: 0.12),
              borderColor: Colors.white30,
              borderOpacity: 0.3,
              onTap: () {
                _statusPollTimer?.cancel();
                setState(() => _isActivated = false);
                _resetHoldVisuals();
              },
              child: const Center(
                child: Text(
                  'DISMISS ALERT VIEW',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _startHold(LongPressStartDetails _) {
    if (_isTriggering || _isActivated) return;
    _isHolding = true;
    _holdController.forward(from: 0);
    HapticFeedback.selectionClick();
    _startHapticTicker();
  }

  void _checkHoldBounds(LongPressMoveUpdateDetails details) {
    // Cancel if finger drifts too far from center to avoid accidental brushes.
    final local = details.localPosition;
    const center = Offset(120, 120);
    if ((local - center).distance > 130) {
      _cancelHold(resetVisuals: true);
    }
  }

  void _cancelHold({required bool resetVisuals}) {
    if (!_isHolding) return;
    _isHolding = false;
    _stopHapticTicker();
    if (resetVisuals &&
        _holdController.status != AnimationStatus.reverse &&
        _holdController.value > 0) {
      _holdController.animateBack(0,
          duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    }
  }

  void _resetHoldVisuals() {
    _stopHapticTicker();
    _isHolding = false;
    _holdController.reset();
    if (mounted) {
      setState(() => _holdProgress = 0);
    }
  }

  void _startHapticTicker() {
    _stopHapticTicker();
    _hapticTicker = Timer.periodic(const Duration(milliseconds: 320), (_) {
      if (_isHolding) {
        HapticFeedback.mediumImpact();
      }
    });
  }

  void _stopHapticTicker() {
    _hapticTicker?.cancel();
    _hapticTicker = null;
  }

  void _showHoldHint() {
    if (_isTriggering || _isActivated) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content:
            Text('For safety, press and hold for 3 seconds to trigger SOS.'),
        duration: Duration(milliseconds: 1200),
      ),
    );
  }

  Future<void> _triggerSOS() async {
    final locProv = context.read<LocationProvider>();
    final touristProv = context.read<TouristProvider>();
    final meshProv = context.read<MeshProvider>();
    final isGuest = touristProv.userState == UserState.guest;
    final tourist = touristProv.tourist;

    if (!isGuest && tourist == null) {
      if (mounted) {
        setState(() {
          _sosDeliveryMessage = 'IDENTITY NOT READY. PLEASE REOPEN APP.';
          _isTriggering = false;
          _isActivated = false;
        });
        _resetHoldVisuals();
      }
      return;
    }
    if (_isTriggering) return;
    if (isGuest && touristProv.guestSessionId == null) {
      if (mounted) {
        setState(() {
          _sosDeliveryMessage = 'GUEST ID ERROR. PLEASE REOPEN APP.';
          _isTriggering = false;
          _isActivated = false;
        });
        _resetHoldVisuals();
      }
      return;
    }

    final effectiveUserId =
        isGuest ? touristProv.guestSessionId! : tourist!.touristId;

    locator<AnalyticsService>()
        .logEvent(AnalyticsEvent.sosTriggered, properties: {
      'user_state': touristProv.userState.name,
      'is_online': touristProv.isOnline,
    });

    setState(() {
      _isTriggering = true;
      _isActivated = true;
      _sosHeadline = 'SOS QUEUED SECURELY';
      _sosDeliveryMessage = 'Saving your SOS before contacting the network.';
    });
    unawaited(HapticFeedback.heavyImpact());

    Position? pos = locProv.currentPosition;

    if (pos == null || DateTime.now().difference(pos.timestamp).inMinutes > 5) {
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }
    }

    if (pos == null) {
      if (mounted) {
        setState(() {
          _sosDeliveryMessage = 'NO GPS FIX. CALL 112 IMMEDIATELY.';
          _isTriggering = false;
          _isActivated = false;
        });
        _resetHoldVisuals();
      }
      return;
    }

    final api = locator<ApiService>();
    final db = locator<DatabaseService>();
    final idempotencyKey = const Uuid().v4();
    final sosTimestamp = DateTime.now();
    final localSosId = await db.saveSosEvent(
      touristId: effectiveUserId,
      latitude: pos.latitude,
      longitude: pos.longitude,
      triggerType: 'MANUAL',
      idempotencyKey: idempotencyKey,
      timestamp: sosTimestamp,
    );

    try {
      if (touristProv.isOnline) {
        final result = await api.triggerSosAlert(
          pos.latitude,
          pos.longitude,
          'MANUAL',
          touristId: effectiveUserId,
          idempotencyKey: idempotencyKey,
          timestamp: sosTimestamp,
        );
        if (result.accepted && localSosId > 0) {
          await db.markSosAccepted(
            localSosId,
            serverSosId: result.sosId,
            deliveryState: result.deliveryState,
          );
        }
        if (mounted) {
          setState(() {
            _sosHeadline = result.dispatched
                ? 'RESCUE NETWORK NOTIFIED'
                : 'SOS QUEUED SECURELY';
            _sosDeliveryMessage = result.message ??
                'SOS queued securely. SafeRoute is reaching authorities.';
          });
        }
        if (result.sosId != null) {
          _startStatusPolling(result.sosId!);
        }
      } else {
        if (mounted) {
          setState(() {
            _sosHeadline = 'SOS SAVED OFFLINE';
            _sosDeliveryMessage =
                'Saved on this device. BLE relay will keep broadcasting until sync confirms it.';
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _sosHeadline = 'SOS SAVED OFFLINE';
          _sosDeliveryMessage =
              'Network failed. The same SOS is saved for retry and BLE relay.';
        });
      }
    }

    try {
      if (!meshProv.isMeshActive) {
        await meshProv.startMesh();
      }
      if (meshProv.canBroadcast) {
        await meshProv.sendSosRelay(
          pos.latitude,
          pos.longitude,
          idempotencyKey: idempotencyKey,
          originTuid: tourist?.tuid,
        );
        if (mounted) {
          setState(() {
            _sosDeliveryMessage = '$_sosDeliveryMessage MESH RELAY ACTIVE.';
          });
        }
      } else if (mounted) {
        setState(() {
          _sosDeliveryMessage =
              '$_sosDeliveryMessage BLE relay is not active: ${meshProv.statusMessage}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _sosDeliveryMessage =
              '$_sosDeliveryMessage BLE relay could not start: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTriggering = false;
        });
      }
    }
  }

  void _startStatusPolling(int sosId) {
    _statusPollTimer?.cancel();
    _statusPollAttempt = 0;
    const delays = [2, 5, 10, 30, 60];
    final api = locator<ApiService>();

    void scheduleNext() {
      final delaySeconds = delays[_statusPollAttempt < delays.length
          ? _statusPollAttempt
          : delays.length - 1];
      _statusPollAttempt++;
      _statusPollTimer = Timer(Duration(seconds: delaySeconds), () async {
        try {
          final status = await api.getSosStatus(sosId);
          if (!mounted) return;
          setState(() {
            if (status.authorityAcknowledged) {
              _sosHeadline = 'AUTHORITY ACKNOWLEDGED';
            } else if (status.rescueNetworkNotified) {
              _sosHeadline = 'RESCUE NETWORK NOTIFIED';
            } else {
              _sosHeadline = 'SOS QUEUED SECURELY';
            }
            _sosDeliveryMessage = status.message;
          });
          if (!status.authorityAcknowledged) {
            scheduleNext();
          }
        } catch (_) {
          if (mounted) scheduleNext();
        }
      });
    }

    scheduleNext();
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri, mode: LaunchMode.externalApplication);
    } else {
      debugPrint('Could not launch $launchUri');
    }
  }
}

class _SosBackdrop extends StatelessWidget {
  const _SosBackdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF5B0A20), Color(0xFF260815), Color(0xFF000000)],
            ),
          ),
        ),
        const Opacity(opacity: 0.22, child: AuroraBackground()),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 0.9,
              colors: [
                AppColors.danger.withValues(alpha: 0.15),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final bool isGuest;
  const _StatusBanner({required this.isGuest});

  @override
  Widget build(BuildContext context) {
    final mesh = context.watch<MeshProvider>();
    return Column(
      children: [
        EliteSurface(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          borderRadius: 16,
          color: Colors.white.withValues(alpha: 0.10),
          borderColor: AppColors.danger.withValues(alpha: 0.45),
          borderOpacity: 0.45,
          child: Row(
            children: [
              const Icon(Icons.shield_rounded,
                  color: AppColors.danger, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Emergency channel armed',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                mesh.isMeshActive
                    ? 'BLE MESH ${mesh.nearbyNodes.length}'
                    : 'DIRECT',
                style: TextStyle(
                  color: mesh.isMeshActive ? AppColors.info : Colors.white70,
                  fontWeight: FontWeight.w800,
                  fontSize: 10,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
        if (isGuest) ...[
          const SizedBox(height: 10),
          EliteSurface(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            borderRadius: 16,
            color: AppColors.warning.withValues(alpha: 0.12),
            borderColor: AppColors.warning.withValues(alpha: 0.45),
            borderOpacity: 0.45,
            child: const Text(
              'Guest mode: SOS includes limited identity. Registration improves responder context.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _HoldToTriggerButton extends StatelessWidget {
  final double holdProgress;
  final AnimationController pulseController;
  final bool isHolding;

  const _HoldToTriggerButton({
    required this.holdProgress,
    required this.pulseController,
    required this.isHolding,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      height: 240,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.08).animate(
              CurvedAnimation(parent: pulseController, curve: Curves.easeInOut),
            ),
            child: Container(
              width: 236,
              height: 236,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.danger.withValues(alpha: 0.25),
                  width: 3,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 214,
            height: 214,
            child: CircularProgressIndicator(
              value: holdProgress,
              strokeWidth: 9,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(
                isHolding ? Colors.white : AppColors.danger,
              ),
              strokeCap: StrokeCap.round,
            ),
          ),
          EliteSurface(
            width: 182,
            height: 182,
            borderRadius: 100,
            color: AppColors.danger.withValues(alpha: 0.92),
            borderColor: Colors.white70,
            borderOpacity: 0.5,
            blur: 20,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Lottie.asset(
                  AppAssets.animations.sosPulse,
                  width: 70,
                  height: 70,
                  repeat: true,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.sos_rounded,
                    size: 60,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isHolding
                      ? '${(3 - (holdProgress * 3)).clamp(0.0, 3.0).toStringAsFixed(1)}s'
                      : 'HOLD',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivatedVisual extends StatelessWidget {
  const _ActivatedVisual();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const PulseMarker(color: AppColors.success, size: 38),
          EliteSurface(
            width: 122,
            height: 122,
            borderRadius: 70,
            color: AppColors.success.withValues(alpha: 0.92),
            borderColor: Colors.white70,
            borderOpacity: 0.5,
            child: const Icon(
              Icons.support_agent_rounded,
              size: 58,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmergencyDeliveryCard extends StatelessWidget {
  final bool isOnline;
  final bool isMeshActive;
  final int meshNodes;
  final String gpsLabel;

  const _EmergencyDeliveryCard({
    required this.isOnline,
    required this.isMeshActive,
    required this.meshNodes,
    required this.gpsLabel,
  });

  @override
  Widget build(BuildContext context) {
    return EliteSurface(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      borderRadius: 18,
      color: Colors.white.withValues(alpha: 0.10),
      borderColor: AppColors.success.withValues(alpha: 0.32),
      borderOpacity: 0.32,
      child: Column(
        children: [
          _DeliveryPill(
            icon:
                isOnline ? Icons.cloud_done_rounded : Icons.cloud_queue_rounded,
            label: isOnline ? 'DIRECT DISPATCH' : 'SAVED LOCALLY',
            value: isOnline ? 'ACTIVE' : 'QUEUED',
            color: isOnline ? AppColors.success : AppColors.warning,
          ),
          const SizedBox(height: 10),
          _DeliveryPill(
            icon: Icons.my_location_rounded,
            label: 'LOCATION',
            value: gpsLabel,
            color: AppColors.info,
          ),
          const SizedBox(height: 10),
          _DeliveryPill(
            icon: Icons.hub_rounded,
            label: 'MESH RELAY',
            value: isMeshActive ? '$meshNodes NODES' : 'STANDBY',
            color: isMeshActive ? AppColors.accent : Colors.white70,
          ),
        ],
      ),
    );
  }
}

class _DeliveryPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _DeliveryPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 11,
            letterSpacing: 0.7,
          ),
        ),
      ],
    );
  }
}

class _QuickCallRow extends StatelessWidget {
  final Tourist? tourist;
  final ValueChanged<String> onCall;

  const _QuickCallRow({required this.tourist, required this.onCall});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _CallAction(
            icon: Icons.local_police_rounded,
            label: 'CALL 112',
            color: AppColors.info,
            onTap: () => onCall('112'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _CallAction(
            icon: Icons.contact_emergency_rounded,
            label: 'CONTACT',
            color: AppColors.warning,
            onTap: () {
              final phone = tourist?.emergencyContactPhone;
              if (phone != null && phone.trim().isNotEmpty) {
                onCall(phone);
              }
            },
          ),
        ),
      ],
    );
  }
}

class _CallAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _CallAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return EliteSurface(
      onTap: onTap,
      borderRadius: 16,
      padding: const EdgeInsets.symmetric(vertical: 14),
      color: color.withValues(alpha: 0.14),
      borderColor: color.withValues(alpha: 0.45),
      borderOpacity: 0.45,
      child: Column(
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}
