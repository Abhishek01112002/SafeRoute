import 'package:latlong2/latlong.dart';
import 'package:saferoute/core/models/location_ping_model.dart';

class GeofenceZone {
  final String id;
  final String name;
  final LatLng center;
  final double radius;
  final ZoneType type;

  GeofenceZone({
    required this.id,
    required this.name,
    required this.center,
    required this.radius,
    required this.type,
  });

  factory GeofenceZone.fromMap(Map<String, dynamic> map) {
    return GeofenceZone(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      center: LatLng(map['lat']?.toDouble() ?? 0.0, map['lng']?.toDouble() ?? 0.0),
      radius: map['radius']?.toDouble() ?? 0.0,
      type: ZoneTypeExtension.fromString(map['type'] ?? ''),
    );
  }
}
