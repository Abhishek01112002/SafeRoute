// lib/core/models/api_responses.dart
//
// Typed API Response DTOs
// ------------------------
// These classes wrap the raw Map<String, dynamic> responses from ApiService,
// providing compile-time safety and explicit nullability.
//
// Used by Repository classes — the ApiService raw methods are unchanged.

import 'package:saferoute/tourist/models/tourist_model.dart';

// ---------------------------------------------------------------------------
// Tourist Auth Responses
// ---------------------------------------------------------------------------

class RegisterTouristResponse {
  final String? token;
  final String? refreshToken;
  final Tourist? tourist;

  const RegisterTouristResponse({
    this.token,
    this.refreshToken,
    this.tourist,
  });

  bool get isValid => token != null && tourist != null;

  factory RegisterTouristResponse.fromRaw(Map<String, dynamic> raw) {
    return RegisterTouristResponse(
      token: raw['token'] as String?,
      refreshToken: raw['refresh_token'] as String?,
      tourist: raw['tourist'] is Tourist
          ? raw['tourist'] as Tourist
          : raw['tourist'] is Map<String, dynamic>
              ? Tourist.fromJson(raw['tourist'] as Map<String, dynamic>)
              : null,
    );
  }
}

class LoginTouristResponse {
  final String? token;
  final String? refreshToken;
  final Tourist? tourist;

  const LoginTouristResponse({
    this.token,
    this.refreshToken,
    this.tourist,
  });

  bool get isValid => tourist != null;

  factory LoginTouristResponse.fromRaw(Map<String, dynamic> raw) {
    return LoginTouristResponse(
      token: raw['token'] as String?,
      refreshToken: raw['refresh_token'] as String?,
      tourist: raw['tourist'] is Tourist
          ? raw['tourist'] as Tourist
          : raw['tourist'] is Map<String, dynamic>
              ? Tourist.fromJson(raw['tourist'] as Map<String, dynamic>)
              : null,
    );
  }
}

// ---------------------------------------------------------------------------
// SOS Response
// ---------------------------------------------------------------------------

class SosTriggerResponse {
  final bool accepted;
  final bool dispatched;
  final String status;
  final String dispatchStatus;

  const SosTriggerResponse({
    required this.accepted,
    required this.dispatched,
    required this.status,
    required this.dispatchStatus,
  });

  factory SosTriggerResponse.fromRaw(Map<String, dynamic> raw) {
    final dispatch = raw['dispatch'] is Map ? raw['dispatch'] as Map : {};
    final statusCode = raw['status_code'] as int? ?? 200;
    return SosTriggerResponse(
      accepted: statusCode == 200 || statusCode == 201,
      dispatched: dispatch['status'] == 'delivered',
      status: raw['status']?.toString() ?? 'unknown',
      dispatchStatus: dispatch['status']?.toString() ?? 'unknown',
    );
  }

  factory SosTriggerResponse.allFailed() => const SosTriggerResponse(
        accepted: false,
        dispatched: false,
        status: 'all_attempts_failed',
        dispatchStatus: 'failed',
      );
}

// ---------------------------------------------------------------------------
// Zone Response
// ---------------------------------------------------------------------------

class ZoneStatusResponse {
  final String zoneId;
  final String status;
  final String? description;
  final double? latitude;
  final double? longitude;
  final double? radiusMeters;

  const ZoneStatusResponse({
    required this.zoneId,
    required this.status,
    this.description,
    this.latitude,
    this.longitude,
    this.radiusMeters,
  });

  factory ZoneStatusResponse.fromJson(Map<String, dynamic> json) {
    return ZoneStatusResponse(
      zoneId: json['zone_id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'UNKNOWN',
      description: json['description'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      radiusMeters: (json['radius_meters'] as num?)?.toDouble(),
    );
  }
}

// ---------------------------------------------------------------------------
// Authority Auth Response
// ---------------------------------------------------------------------------

class AuthorityLoginResponse {
  final String? token;
  final String? authorityId;
  final String? role;

  const AuthorityLoginResponse({
    this.token,
    this.authorityId,
    this.role,
  });

  bool get isValid => token != null;

  factory AuthorityLoginResponse.fromRaw(Map<String, dynamic> raw) {
    return AuthorityLoginResponse(
      token: raw['token'] as String?,
      authorityId: raw['authority_id'] as String?,
      role: raw['role'] as String?,
    );
  }
}
