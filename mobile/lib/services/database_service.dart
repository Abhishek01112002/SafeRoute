// lib/services/database_service.dart
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:saferoute/models/tourist_model.dart';
import 'package:saferoute/models/location_ping_model.dart';
import 'package:saferoute/models/zone_model.dart';
import 'package:saferoute/models/trail_graph_model.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static Database? _database;

  factory DatabaseService() => _instance;

  DatabaseService._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'saferoute_v2.db');
    return await openDatabase(
      path,
      version: 8,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE tourists (
        touristId TEXT PRIMARY KEY,
        fullName TEXT,
        documentType TEXT,
        documentNumber TEXT,
        photoBase64 TEXT,
        emergencyContactName TEXT,
        emergencyContactPhone TEXT,
        tripStartDate INTEGER,
        tripEndDate INTEGER,
        destinationState TEXT,
        qrData TEXT,
        createdAt INTEGER,
        blockchainHash TEXT,
        selectedDestinations TEXT,
        connectivityLevel TEXT,
        offlineModeRequired INTEGER,
        geoFenceZones TEXT,
        destinationEmergencyContacts TEXT,
        riskLevel TEXT,
        bloodGroup TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE location_pings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        touristId TEXT,
        latitude REAL,
        longitude REAL,
        speedKmh REAL,
        accuracyMeters REAL,
        timestamp INTEGER,
        isSynced INTEGER,
        zoneStatus TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE sos_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        touristId TEXT,
        latitude REAL,
        longitude REAL,
        timestamp INTEGER,
        triggerType TEXT,
        isSynced INTEGER
      )
    ''');

    if (version >= 2) await _createMeshTables(db);
    if (version >= 3) await _createMapTileTable(db);
    if (version >= 4) await _createIndexes(db);
    if (version >= 5) await _createGeofenceTable(db);
    if (version >= 7) await _createZonesTable(db);
    if (version >= 8) await _createTrailGraphsTable(db);
  }

  Future<void> _createGeofenceTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS geofence_zones (
        id TEXT PRIMARY KEY,
        name TEXT,
        type TEXT,
        lat REAL,
        lng REAL,
        radius REAL,
        points TEXT,
        state TEXT
      )
    ''');
  }

  Future<void> _createZonesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS zones (
        id TEXT PRIMARY KEY,
        destination_id TEXT NOT NULL,
        authority_id TEXT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        shape TEXT NOT NULL DEFAULT 'CIRCLE',
        center_lat REAL,
        center_lng REAL,
        radius_m REAL,
        polygon_json TEXT DEFAULT '[]',
        is_active INTEGER DEFAULT 1,
        created_at TEXT,
        updated_at TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_zones_dest ON zones(destination_id, is_active)'
    );
  }

  Future<void> _createTrailGraphsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS trail_graphs (
        id TEXT PRIMARY KEY,
        destination_id TEXT UNIQUE NOT NULL,
        version INTEGER DEFAULT 1,
        graph_json TEXT NOT NULL,
        created_at TEXT
      )
    ''');
  }

  Future<void> _createIndexes(Database db) async {
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_ping_sync ON location_pings(isSynced, timestamp)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_ping_tourist ON location_pings(touristId, timestamp)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sos_sync ON sos_events(isSynced)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_mesh_timestamp ON mesh_packets(timestamp)');
  }

  Future<void> _createMapTileTable(Database db) async {
    await db.execute('''
      CREATE TABLE map_tiles (
        key TEXT PRIMARY KEY,
        tile_data BLOB,
        timestamp INTEGER
      )
    ''');
  }

  Future<void> _createMeshTables(Database db) async {
    await db.execute('''
      CREATE TABLE mesh_packets (
        packetId TEXT PRIMARY KEY,
        sourceId TEXT,
        targetId TEXT,
        groupId TEXT,
        type INTEGER,
        payload TEXT,
        hopCount INTEGER,
        timestamp INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE mesh_nodes (
        userId TEXT PRIMARY KEY,
        name TEXT,
        connected INTEGER,
        lastSeen INTEGER,
        battery INTEGER,
        lat REAL,
        lng REAL,
        rssi INTEGER
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) await _createMeshTables(db);
    if (oldVersion < 3) await _createMapTileTable(db);
    if (oldVersion < 4) await _createIndexes(db);
    if (oldVersion < 5) await _createGeofenceTable(db);
    if (oldVersion < 6) {
      try {
        await db.execute('ALTER TABLE tourists ADD COLUMN bloodGroup TEXT');
      } catch (_) {
        // Column already exists on some upgraded beta builds.
      }
    }
    if (oldVersion < 7) await _createZonesTable(db);
    if (oldVersion < 8) await _createTrailGraphsTable(db);
  }

  // ── Zone Methods (canonical schema) ──────────────────────────────────────

  Future<void> saveZones(String destinationId, List<ZoneModel> zones) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('zones', where: 'destination_id = ?', whereArgs: [destinationId]);
      for (final z in zones) {
        await txn.insert('zones', z.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<List<ZoneModel>> getZonesForDestination(String destinationId) async {
    final db = await database;
    final rows = await db.query(
      'zones',
      where: 'destination_id = ? AND is_active = 1',
      whereArgs: [destinationId],
    );
    return rows.map((r) => ZoneModel.fromMap(r)).toList();
  }

  // ── Legacy Zone Methods ──────────────────────────────────────────────────

  Future<void> saveGeofenceZones(String state, List<dynamic> zones) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('geofence_zones', where: 'state = ?', whereArgs: [state]);
      for (var zone in zones) {
        await txn.insert('geofence_zones', {
          'id': zone['id'] ?? zone['destination_id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
          'name': zone['name'],
          'type': zone['type'] ?? 'SAFE',
          'lat': zone['lat'] ?? (zone['center'] != null ? zone['center']['lat'] : 0.0),
          'lng': zone['lng'] ?? (zone['center'] != null ? zone['center']['lng'] : 0.0),
          'radius': zone['radius'] ?? 500.0,
          'points': zone['points'] != null ? zone['points'].toString() : null,
          'state': state,
        });
      }
    });
  }

  Future<List<Map<String, dynamic>>> getGeofenceZones(String state) async {
    final db = await database;
    return await db.query('geofence_zones', where: 'state = ?', whereArgs: [state]);
  }

  // ── Trail Graph Methods ────────────────────────────────────────────────────

  Future<void> saveTrailGraph(TrailGraph graph) async {
    final db = await database;
    await db.insert('trail_graphs', graph.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<TrailGraph?> getTrailGraph(String destinationId) async {
    final db = await database;
    final rows = await db.query(
      'trail_graphs',
      where: 'destination_id = ?',
      whereArgs: [destinationId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return TrailGraph.fromMap(rows.first);
  }

  // Mesh Packet Methods
  Future<void> saveMeshPacket(dynamic packet) async {
    final db = await database;
    await db.insert('mesh_packets', packet.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<bool> hasPacket(String packetId) async {
    final db = await database;
    final maps = await db
        .query('mesh_packets', where: 'packetId = ?', whereArgs: [packetId]);
    return maps.isNotEmpty;
  }

  // Tourists Table Methods
  Future<void> saveTourist(Tourist t) async {
    final db = await database;
    await db.insert('tourists', t.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Tourist?> getTourist() async {
    final db = await database;
    final List<Map<String, dynamic>> maps =
        await db.query('tourists', limit: 1);
    if (maps.isEmpty) return null;
    return Tourist.fromMap(maps.first);
  }

  Future<void> deleteTourist() async {
    final db = await database;
    await db.delete('tourists');
  }

  // Location Pings Table Methods
  Future<void> savePing(LocationPing ping) async {
    final db = await database;
    await db.insert('location_pings', ping.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<LocationPing>> getUnsyncedPings() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'location_pings',
      where: 'isSynced = ?',
      whereArgs: [0],
      orderBy: 'timestamp ASC',
      limit: 500,
    );
    return List.generate(maps.length, (i) => LocationPing.fromMap(maps[i]));
  }

  Future<void> markPingSynced(int id) async {
    final db = await database;
    await db.update(
      'location_pings',
      {'isSynced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteOldSyncedPings() async {
    final db = await database;
    final sevenDaysAgo =
        DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    await db.delete(
      'location_pings',
      where: 'isSynced = ? AND timestamp < ?',
      whereArgs: [1, sevenDaysAgo],
    );
  }

  // ── Hansel & Gretel Breadcrumb Fetcher ──
  Future<List<LocationPing>> getTrailPings() async {
    final db = await database;
    // Fetch last 2000 pins to save memory, chronological order
    final List<Map<String, dynamic>> maps = await db.query(
      'location_pings',
      orderBy: 'timestamp DESC',
      limit: 2000,
    );
    // Reverse because DESC fetched newest first, we want oldest -> newest for polyline graphing
    return maps.reversed.map((m) => LocationPing.fromMap(m)).toList();
  }

  Future<void> clearTrail() async {
    final db = await database;
    await db.delete('location_pings');
  }

  // SOS Events Table Methods
  Future<void> saveSosEvent({
    required String touristId,
    required double latitude,
    required double longitude,
    required String triggerType,
    bool isSynced = false,
  }) async {
    final db = await database;
    await db.insert('sos_events', {
      'touristId': touristId,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'triggerType': triggerType,
      'isSynced': isSynced ? 1 : 0,
    });
  }

  Future<List<Map<String, dynamic>>> getUnsyncedSosEvents() async {
    final db = await database;
    return await db.query('sos_events', where: 'isSynced = ?', whereArgs: [0]);
  }

  Future<void> markSosSynced(int id) async {
    final db = await database;
    await db.update(
      'sos_events',
      {'isSynced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> getUnsyncedSosCount() async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM sos_events WHERE isSynced = 0');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ── Map Tile Logic (V3) ──
  Future<void> saveTile(String key, List<int> data) async {
    final db = await database;
    await db.insert(
      'map_tiles',
      {
        'key': key,
        'tile_data': data,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<int>?> getTile(String key) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'map_tiles',
      columns: ['tile_data'],
      where: 'key = ?',
      whereArgs: [key],
    );
    if (maps.isEmpty) return null;
    return maps.first['tile_data'] as List<int>;
  }
}
