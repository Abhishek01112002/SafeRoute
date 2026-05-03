// lib/services/breadcrumb_manager.dart
import 'package:saferoute/core/models/location_ping_model.dart';
import 'package:saferoute/services/database_service.dart';
import 'package:saferoute/core/service_locator.dart';

class BreadcrumbManager {
  final DatabaseService _dbService = locator<DatabaseService>();
  final List<LocationPing> _trail = [];
  static const int kMaxTrailSize = 2000;

  List<LocationPing> get trail => List.unmodifiable(_trail);

  Future<void> initialize() async {
    final history = await _dbService.getTrailPings();
    _trail.clear();
    _trail.addAll(history);
  }

  Future<void> savePoint(LocationPing ping) async {
    if (_trail.length >= kMaxTrailSize) {
      _trail.removeAt(0);
    }
    _trail.add(ping);
    await _dbService.savePing(ping);
  }

  Future<void> clearAll() async {
    _trail.clear();
    await _dbService.clearTrail();
  }
}
