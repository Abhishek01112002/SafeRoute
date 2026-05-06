import 'dart:math' as math;

class RoomMember {
  final String userId;
  final String touristId;
  final String? tuid;
  final String name;
  final String displayName;
  final String role;
  final String sharingStatus;
  final double? lat;
  final double? lng;
  final double? timestamp;
  final double? accuracyMeters;
  final double? batteryLevel;
  final String zoneStatus;
  final String? source;
  final String? trustLevel;
  final DateTime? clientTimestamp;
  final DateTime? lastSeenAt;
  final DateTime? serverUpdatedAt;
  final bool isStale;

  const RoomMember({
    required this.userId,
    required this.touristId,
    required this.name,
    required this.displayName,
    this.tuid,
    this.role = 'MEMBER',
    this.sharingStatus = 'SHARING',
    this.lat,
    this.lng,
    this.timestamp,
    this.accuracyMeters,
    this.batteryLevel,
    this.zoneStatus = 'UNKNOWN',
    this.source,
    this.trustLevel,
    this.clientTimestamp,
    this.lastSeenAt,
    this.serverUpdatedAt,
    this.isStale = true,
  });

  factory RoomMember.fromJson(Map<String, dynamic> json) {
    final userId = (json['user_id'] ?? json['tourist_id'] ?? '').toString();
    final displayName =
        (json['display_name'] ?? json['name'] ?? 'Team member').toString();
    final timestamp = _toDouble(json['timestamp']);
    return RoomMember(
      userId: userId,
      touristId: (json['tourist_id'] ?? userId).toString(),
      tuid: json['tuid']?.toString(),
      name: (json['name'] ?? displayName).toString(),
      displayName: displayName,
      role: (json['role'] ?? 'MEMBER').toString().toUpperCase(),
      sharingStatus:
          (json['sharing_status'] ?? 'SHARING').toString().toUpperCase(),
      lat: _toDouble(json['lat'] ?? json['latitude']),
      lng: _toDouble(json['lng'] ?? json['longitude']),
      timestamp: timestamp,
      accuracyMeters: _toDouble(json['accuracy_meters']),
      batteryLevel: _toDouble(json['battery_level']),
      zoneStatus: (json['zone_status'] ?? 'UNKNOWN').toString().toUpperCase(),
      source: json['source']?.toString(),
      trustLevel: json['trust_level']?.toString(),
      clientTimestamp: _parseDate(json['client_timestamp']) ??
          (timestamp == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  (timestamp * 1000).round(),
                )),
      lastSeenAt: _parseDate(json['last_seen_at']),
      serverUpdatedAt: _parseDate(json['server_updated_at']),
      isStale: json['is_stale'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'tourist_id': touristId,
        'tuid': tuid,
        'name': name,
        'display_name': displayName,
        'role': role,
        'sharing_status': sharingStatus,
        'lat': lat,
        'lng': lng,
        'timestamp': timestamp,
        'accuracy_meters': accuracyMeters,
        'battery_level': batteryLevel,
        'zone_status': zoneStatus,
        'source': source,
        'trust_level': trustLevel,
        'client_timestamp': clientTimestamp?.toIso8601String(),
        'last_seen_at': lastSeenAt?.toIso8601String(),
        'server_updated_at': serverUpdatedAt?.toIso8601String(),
        'is_stale': isStale,
      };

  bool get hasLocation => lat != null && lng != null;
  bool get isSharing => sharingStatus == 'SHARING';
  bool get isPaused => sharingStatus == 'PAUSED';
  bool get isMeshFallback => source == 'mesh' || trustLevel == 'mesh_trusted';
  bool get isAdvisory => trustLevel == 'advisory';

  String get statusLabel {
    if (isPaused) return 'Paused';
    if (!hasLocation) return 'Waiting for signal';
    if (isAdvisory) return 'Advisory relay';
    if (isMeshFallback) return 'Mesh fallback';
    if (isStale) return 'Stale signal';
    return 'Live signal';
  }

  Duration? get signalAge {
    final updatedAt = serverUpdatedAt ?? clientTimestamp ?? lastSeenAt;
    if (updatedAt == null) return null;
    return DateTime.now().difference(updatedAt.toLocal());
  }

  // Distance in km using Haversine formula.
  double? distanceTo(RoomMember other) {
    if (!hasLocation || !other.hasLocation) return null;
    const r = 6371.0;
    final dLat = _toRad(other.lat! - lat!);
    final dLng = _toRad(other.lng! - lng!);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat!)) *
            math.cos(_toRad(other.lat!)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  double _toRad(double deg) => deg * math.pi / 180;
}
