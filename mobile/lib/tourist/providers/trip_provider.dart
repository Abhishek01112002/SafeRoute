// lib/tourist/providers/trip_provider.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:saferoute/tourist/models/trip_model.dart';
import 'package:saferoute/services/api_service.dart';
import 'package:saferoute/core/service_locator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Manages the tourist's active trip and trip history.
///
/// Usage:
///   context.watch<TripProvider>().activeTrip   // null = no active trip
///   context.read<TripProvider>().createTrip(...)
class TripProvider extends ChangeNotifier {
  Trip? _activeTrip;
  List<Trip> _tripHistory = [];
  bool _isLoading = false;
  String? _error;

  Trip? get activeTrip => _activeTrip;
  List<Trip> get tripHistory => _tripHistory;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasActiveTrip => _activeTrip != null;

  final _api = locator<ApiService>();

  // ---------------------------------------------------------------------------
  // Initialization — called by bootstrap after tourist is confirmed logged in
  // ---------------------------------------------------------------------------

  Future<void> initialize() async {
    // Try fast path: restore from local cache first
    await _restoreFromCache();
    // Then refresh from server in background
    _refreshActiveTrip();
  }

  // ---------------------------------------------------------------------------
  // Create a new trip
  // ---------------------------------------------------------------------------

  Future<Trip?> createTrip({
    required DateTime startDate,
    required DateTime endDate,
    required List<TripStopDraft> stops,
    String? notes,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final payload = {
        'trip_start_date': startDate.toIso8601String(),
        'trip_end_date': endDate.toIso8601String(),
        'notes': notes,
        'stops': stops.map((s) => s.toJson()).toList(),
      };

      final data = await _api.postJson('/v3/trips/', payload);
      final trip = Trip.fromJson(data as Map<String, dynamic>);

      _activeTrip = trip;
      await _cacheActiveTrip(trip);

      _isLoading = false;
      notifyListeners();
      return trip;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // End / complete the active trip
  // ---------------------------------------------------------------------------

  Future<bool> endActiveTrip() async {
    if (_activeTrip == null) return false;
    try {
      await _api.putJson('/v3/trips/${_activeTrip!.tripId}/end', {});
      _tripHistory.insert(0, _activeTrip!);
      _activeTrip = null;
      await _clearActiveTrip();
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Fetch trip history
  // ---------------------------------------------------------------------------

  Future<void> fetchHistory() async {
    try {
      final data = await _api.getJson('/v3/trips/') as Map<String, dynamic>;
      final list = (data['trips'] as List<dynamic>? ?? []);
      _tripHistory = list
          .map((t) => Trip.fromJson(t as Map<String, dynamic>))
          .where((t) => t.status != TripStatus.ACTIVE)
          .toList();
      notifyListeners();
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Refresh active trip from server (background, non-blocking)
  // ---------------------------------------------------------------------------

  Future<void> _refreshActiveTrip() async {
    try {
      final data = await _api.getJson('/v3/trips/active') as Map<String, dynamic>;
      final tripData = data['active_trip'];
      if (tripData != null) {
        _activeTrip = Trip.fromJson(tripData as Map<String, dynamic>);
        await _cacheActiveTrip(_activeTrip!);
      } else {
        _activeTrip = null;
        await _clearActiveTrip();
      }
      notifyListeners();
    } catch (_) {
      // Network failure — keep cached value
    }
  }

  // ---------------------------------------------------------------------------
  // Local cache (SharedPreferences) for offline resilience
  // ---------------------------------------------------------------------------

  Future<void> _cacheActiveTrip(Trip trip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_trip', jsonEncode(trip.toJson()));
  }

  Future<void> _clearActiveTrip() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('active_trip');
  }

  Future<void> _restoreFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('active_trip');
      if (raw != null) {
        _activeTrip = Trip.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        notifyListeners();
      }
    } catch (_) {}
  }
}

/// Lightweight data class for constructing a new trip stop.
/// Separate from TripStop to avoid requiring server-generated IDs.
class TripStopDraft {
  final String name;
  final String? destinationId;
  final String? destinationState;
  final DateTime visitDateFrom;
  final DateTime visitDateTo;
  final int orderIndex;
  final double? centerLat;
  final double? centerLng;

  const TripStopDraft({
    required this.name,
    this.destinationId,
    this.destinationState,
    required this.visitDateFrom,
    required this.visitDateTo,
    this.orderIndex = 1,
    this.centerLat,
    this.centerLng,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'destination_id': destinationId,
        'destination_state': destinationState,
        'visit_date_from': visitDateFrom.toIso8601String(),
        'visit_date_to': visitDateTo.toIso8601String(),
        'order_index': orderIndex,
        'center_lat': centerLat,
        'center_lng': centerLng,
      };
}
