import 'dart:math' as math;

class RoomMember {
  final String userId;
  final String name;
  final double lat;
  final double lng;
  final double timestamp;

  RoomMember({
    required this.userId,
    required this.name,
    required this.lat,
    required this.lng,
    required this.timestamp,
  });

  factory RoomMember.fromJson(Map<String, dynamic> json) => RoomMember(
        userId: json['user_id'],
        name: json['name'],
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        timestamp: (json['timestamp'] as num).toDouble(),
      );

  // Distance in km using Haversine formula
  double distanceTo(RoomMember other) {
    const R = 6371.0;
    final dLat = _toRad(other.lat - lat);
    final dLng = _toRad(other.lng - lng);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat)) * math.cos(_toRad(other.lat)) *
        math.sin(dLng / 2) * math.sin(dLng / 2);
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _toRad(double deg) => deg * math.pi / 180;
}
