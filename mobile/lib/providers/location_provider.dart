import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:latlong2/latlong.dart';
import 'package:saferoute/models/location_ping_model.dart';
import 'package:saferoute/services/location_service.dart';
import 'package:saferoute/services/database_service.dart';
import 'package:saferoute/services/background_service.dart';
import 'package:saferoute/services/geofencing_engine.dart';
import 'package:saferoute/services/breadcrumb_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:saferoute/services/safety_engine.dart';
// import 'package:saferoute/services/fall_detection_service.dart';

class LocationProvider with ChangeNotifier {
  Position? _currentPosition;
  // DEFAULT-SAFE: Start in syncing state until zone data is loaded.
  // This prevents false "SECURE" display during cold start.
  ZoneType _zoneStatus = ZoneType.syncing;
  bool _isTracking = false;
  bool _isLocationActive = false;
  bool _isSosActive = false;
  bool _isMockMode = false;

  double _batteryLevel = 1.0;
  SafetyRiskLevel _riskLevel = SafetyRiskLevel.low;
  DateTime _lastMovementTime = DateTime.now();
  final Battery _battery = Battery();
  Timer? _safetyTimer;

  List<LocationPing> _unsyncedPings = [];
  String? _activeTouristId;

  StreamSubscription<Position>? _positionSubscription;

  // Internal Engines
  final LocationService _locationService = LocationService();
  final DatabaseService _dbService = DatabaseService();
  final GeofencingEngine _geofencing = GeofencingEngine();
  final BreadcrumbManager _breadcrumbs = BreadcrumbManager();

  // Smoothing and Hysteresis Variables
  Position? _lastSavedPosition;
  DateTime _lastSaveTime = DateTime.fromMillisecondsSinceEpoch(0);

  ZoneType _pendingZone = ZoneType.safe;
  DateTime? _pendingStartTime;

  // Getters
  Position? get currentPosition => _currentPosition;
  ZoneType get zoneStatus => _zoneStatus;
  bool get isTracking => _isTracking;
  bool get isLocationActive => _isLocationActive;
  bool get isSosActive => _isSosActive;
  bool get isMockMode => _isMockMode;
  List<LocationPing> get unsyncedPings => _unsyncedPings;
  List<LocationPing> get trail => _breadcrumbs.trail;
  int get unsyncedCount => _unsyncedPings.length;
  double get batteryLevel => _batteryLevel;
  SafetyRiskLevel get riskLevel => _riskLevel;
  DateTime get lastMovementTime => _lastMovementTime;

  /// Expose geofencing engine for backtrack boundary detection.
  GeofencingEngine get geofencing => _geofencing;

  void setSosActive(bool val) {
    _isSosActive = val;
    notifyListeners();
  }

  void setMockMode(bool val) {
    _isMockMode = val;
    notifyListeners();
  }

  Future<void> startTracking(BuildContext context) async {
    if (_isTracking) return;

    final prefs = await SharedPreferences.getInstance();
    _activeTouristId = prefs.getString('tourist_id') ?? (await _dbService.getTourist())?.touristId;

    // Pre-load zones for tourist's selected destination
    final destinationId = prefs.getString('primary_destination_id');
    if (destinationId != null) {
      await _geofencing.loadForDestination(destinationId);
    } else {
      // Fallback to state-based zones if primary destination is not set
      final state = prefs.getString('destination_state');
      if (state != null) {
        final legacyZones = await _dbService.getGeofenceZones(state);
        if (legacyZones.isNotEmpty) {
          _geofencing.setDynamicZones(legacyZones);
        }
      }
    }

    // Zones are now loaded (or confirmed empty) → transition from syncing to safe
    if (!_geofencing.isLoaded) {
      _geofencing.markLoaded();
    }
    // If we were in syncing state, transition to safe now that zones are loaded
    if (_zoneStatus == ZoneType.syncing) {
      _zoneStatus = ZoneType.safe;
    }

    PermissionStatus status = await Permission.location.status;
    if (!status.isGranted) {
      await _locationService.requestLocationPermission(context);
    }

    bool isRunning = await BackgroundService.isRunning();
    if (!isRunning) {
      await BackgroundService.initializeBackgroundService();
    }

    // Initialize decoupled engines
    await _breadcrumbs.initialize();

    if (_breadcrumbs.trail.isNotEmpty) {
      final last = _breadcrumbs.trail.last;
      _lastSavedPosition = Position(
        longitude: last.longitude, latitude: last.latitude,
        timestamp: last.timestamp, accuracy: last.accuracyMeters,
        altitude: 0, altitudeAccuracy: 0, heading: 0, headingAccuracy: 0,
        speed: last.speedKmh / 3.6, speedAccuracy: 0
      );
      _lastSaveTime = last.timestamp;
      _zoneStatus = last.zoneStatus;
    }

    _currentPosition = await _locationService.getCurrentLocation();
    if (_currentPosition != null) {
      _processPing(_currentPosition!);
    }

    _positionSubscription = _locationService.getLocationStream().listen(
      (Position position) => _processPing(position),
      onError: (error) {
        _isLocationActive = false;
        notifyListeners();
      }
    );

    _isTracking = true;
    _isLocationActive = true;

    // Start Safety Engine Loops
    _startSafetyMonitoring();

    notifyListeners();
  }

  void _startSafetyMonitoring() {
    _safetyTimer?.cancel();
    _safetyTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      _batteryLevel = (await _battery.batteryLevel) / 100.0;

      _riskLevel = SafetyEngine.calculateRisk(
        zone: _zoneStatus,
        batteryLevel: _batteryLevel,
        isMeshConnected: true,
        speedKmh: (_currentPosition?.speed ?? 0) * 3.6,
        lastMovementTime: _lastMovementTime,
      );

      _checkAdaptivePower();
      notifyListeners();
    });

    // FallDetectionService: Placeholder for future implementation.
    // Requirements for activation:
    // - Dampening filter: Average velocity < 0.2 m/s for > 300 seconds
    // - No manual interaction (screen touches) for 5 minutes
    // TODO: Implement FallDetectionService v2 with above safeguards
  }

  void _processPing(Position rawPos) {
    _isLocationActive = true;

    // 1. Accuracy Filter
    if (rawPos.accuracy > 20.0 && rawPos.accuracy != 1.0) {
      notifyListeners();
      return;
    }

    // 2. Kalman-lite Smoothing
    double smoothedLat = rawPos.latitude;
    double smoothedLng = rawPos.longitude;
    if (_currentPosition != null) {
      smoothedLat = 0.7 * _currentPosition!.latitude + 0.3 * rawPos.latitude;
      smoothedLng = 0.7 * _currentPosition!.longitude + 0.3 * rawPos.longitude;
    }

    _currentPosition = Position(
      latitude: smoothedLat, longitude: smoothedLng,
      timestamp: rawPos.timestamp, accuracy: rawPos.accuracy,
      altitude: rawPos.altitude, altitudeAccuracy: rawPos.altitudeAccuracy,
      heading: rawPos.heading, headingAccuracy: rawPos.headingAccuracy,
      speed: rawPos.speed, speedAccuracy: rawPos.speedAccuracy,
    );

    if (rawPos.speed > 0.5) {
      _lastMovementTime = DateTime.now();
    }

    // 3. Hysteresis — 2s stability before committing zone change
    ZoneType instantZone = _geofencing.getZoneType(LatLng(smoothedLat, smoothedLng));
    if (instantZone != _zoneStatus) {
      if (instantZone != _pendingZone) {
        _pendingZone = instantZone;
        _pendingStartTime = DateTime.now();
      } else if (_pendingStartTime != null &&
                 DateTime.now().difference(_pendingStartTime!).inSeconds >= 2) {
        _zoneStatus = instantZone; // State change triggered
        // Only haptic for DANGER transitions — safe is the silent norm
        if (instantZone.isDanger) {
          _triggerZoneHaptic();
        }
      }
    } else {
       _pendingZone = instantZone;
    }

    // 4. Persistence (>= 5m distance & >= 2s interval)
    if (_lastSavedPosition == null) {
      _triggerSave(_currentPosition!);
    } else {
      final timeGap = DateTime.now().difference(_lastSaveTime).inSeconds;
      final dist = Geolocator.distanceBetween(
        _lastSavedPosition!.latitude, _lastSavedPosition!.longitude,
        smoothedLat, smoothedLng
      );

      if (dist >= 5.0 && timeGap >= 2) {
        _triggerSave(_currentPosition!);
      }
    }

    notifyListeners();
  }

  Future<void> _triggerSave(Position pos) async {
    final touristId = _activeTouristId ?? (await _dbService.getTourist())?.touristId;
    if (touristId == null || touristId.isEmpty) {
      debugPrint("LocationProvider: skipping ping save because no tourist is registered.");
      return;
    }
    _activeTouristId = touristId;

    _lastSavedPosition = pos;
    _lastSaveTime = DateTime.now();

    final ping = LocationPing(
      touristId: touristId,
      latitude: pos.latitude,
      longitude: pos.longitude,
      speedKmh: pos.speed * 3.6,
      accuracyMeters: pos.accuracy,
      timestamp: _lastSaveTime,
      isSynced: false,
      zoneStatus: _zoneStatus,
    );

    await _breadcrumbs.savePoint(ping);
  }

  void forceAddMockPing(LatLng coordinate) {
     _processPing(Position(
        longitude: coordinate.longitude, latitude: coordinate.latitude,
        timestamp: DateTime.now(), accuracy: 1.0,
        altitude: 0, altitudeAccuracy: 0, heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0
      ));
  }

  void _triggerZoneHaptic() {
    switch (_zoneStatus) {
      case ZoneType.restricted:
        HapticFeedback.heavyImpact();
        Future.delayed(const Duration(milliseconds: 200), () => HapticFeedback.heavyImpact());
        break;
      case ZoneType.caution:
        HapticFeedback.mediumImpact();
        break;
      case ZoneType.safe:
        // Silent — safe is the default norm, no need to alert
        break;
      case ZoneType.syncing:
        // No haptic during sync
        break;
    }
  }

  Future<void> stopTracking() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _safetyTimer?.cancel();
    // FallDetectionService().stopMonitoring();
    _isTracking = false;
    _isLocationActive = false;
    notifyListeners();
  }

  Future<void> clearTrail() async {
    await _breadcrumbs.clearAll();
    _lastSavedPosition = null;
    notifyListeners();
  }

  void _checkAdaptivePower() {
    if (!_isTracking) return;

    LocationAccuracy targetAccuracy = LocationAccuracy.high;
    int targetFilter = 10;

    if (_batteryLevel < 0.10) {
      targetAccuracy = LocationAccuracy.low;
      targetFilter = 100;
    } else if (_batteryLevel < 0.20) {
      targetAccuracy = LocationAccuracy.medium;
      targetFilter = 50;
    }

    // Logic to restart stream if settings changed would go here
    // For this demo, we will just log the adaptive shift
    debugPrint("ADAPTIVE POWER: Accuracy=$targetAccuracy, Filter=$targetFilter");
  }

  Future<void> fetchUnsyncedPings() async {
    _unsyncedPings = await _dbService.getUnsyncedPings();
    notifyListeners();
  }
}
