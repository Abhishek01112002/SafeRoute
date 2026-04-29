// lib/services/location_service.dart
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  bool _isRequestingPermission = false;

  factory LocationService() => _instance;

  LocationService._internal();

  Future<bool> requestLocationPermission([BuildContext? context]) async {
    if (_isRequestingPermission) return false;
    _isRequestingPermission = true;

    try {
      PermissionStatus status = await Permission.location.request();

      if (status.isGranted) {
        PermissionStatus alwaysStatus = await Permission.locationAlways.request();
        return alwaysStatus.isGranted;
      }

      if (status.isPermanentlyDenied && context != null && context.mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Location Permission Required"),
            content: const Text(
                "SafeRoute needs background location to protect you. Please enable it in settings."),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () {
                  openAppSettings();
                  Navigator.pop(ctx);
                },
                child: const Text("Open Settings"),
              ),
            ],
          ),
        );
      }
    } finally {
      _isRequestingPermission = false;
    }

    return false;
  }

  Future<Position?> getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.deniedForever) return null;

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (e) {
      return null;
    }
  }

  Stream<Position> getLocationStream({
    LocationAccuracy accuracy = LocationAccuracy.high,
    int distanceFilter = 10,
  }) {
    final LocationSettings locationSettings = LocationSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilter,
    );
    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }

  double calculateSpeed(Position prev, Position curr) {
    double distanceInMeters = Geolocator.distanceBetween(
      prev.latitude,
      prev.longitude,
      curr.latitude,
      curr.longitude,
    );

    double timeInSeconds =
        curr.timestamp.difference(prev.timestamp).inSeconds.toDouble();
    if (timeInSeconds <= 0) return 0.0;

    double metersPerSecond = distanceInMeters / timeInSeconds;
    return metersPerSecond * 3.6; // Convert to km/h
  }

  bool isWithinBounds(double lat, double lng) {
    // North East India approximate bounds: lat 21-30, lng 88-98
    return lat >= 21.0 && lat <= 30.0 && lng >= 88.0 && lng <= 98.0;
  }
}
