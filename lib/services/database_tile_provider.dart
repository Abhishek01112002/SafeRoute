import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:dio/dio.dart';
import 'database_service.dart';

/// A custom [TileProvider] that caches map tiles in the application's
/// internal SQLite database for instant offline access and faster re-loads.
class DatabaseTileProvider extends TileProvider {
  final _db = DatabaseService();
  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  ));

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _DatabaseImageProvider(
      coordinates: coordinates,
      urlTemplate: options.urlTemplate!,
      db: _db,
      dio: _dio,
    );
  }

  /// Proactively downloads and caches tiles for a specific radius around a location.
  /// Used for "Immediate Load" optimization of current live location.
  static Future<void> precacheArea({
    required LatLng center,
    required double zoom,
    required String urlTemplate,
  }) async {
    final dio = Dio();
    final db = DatabaseService();
    
    // Calculate a small grid around the center (3x3 tiles at current zoom)
    final z = zoom.toInt();
    final x = ((center.longitude + 180) / 360 * (1 << z)).toInt();
    final y = ((1 - (math.log(math.tan(center.latitude * math.pi / 180) + 1 / math.cos(center.latitude * math.pi / 180)) / math.pi)) / 2 * (1 << z)).toInt();
    
    debugPrint('[Cache] Pre-caching live area at z:$z');

    for (int dx = -1; dx <= 1; dx++) {
      for (int dy = -1; dy <= 1; dy++) {
        final tx = x + dx;
        final ty = y + dy;
        final key = '$z-$tx-$ty';
        
        final existing = await db.getTile(key);
        if (existing == null) {
          final url = urlTemplate
              .replaceFirst('{z}', z.toString())
              .replaceFirst('{x}', tx.toString())
              .replaceFirst('{y}', ty.toString());
          
          try {
            final res = await dio.get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
            if (res.data != null) {
              await db.saveTile(key, res.data!);
            }
          } catch (_) {}
        }
      }
    }
  }

  /// Returns the number of cached tiles in the database.
  /// Used for Issue #3 warning logic.
  Future<int> getTileCount() async {
    try {
      final db = await DatabaseService().database;
      final results = await db.rawQuery('SELECT COUNT(*) as count FROM map_tiles');
      return results.first['count'] as int;
    } catch (_) {
      return 0;
    }
  }

  /// Pre-populates offline tiles for key regions during app initialization.
  /// Addresses Issue #3: Offline Map Database Not Pre-populated
  static Future<void> prePopulateOfflineTiles() async {
    final db = DatabaseService();
    final dio = Dio();

    // Define key regions for North East India trekking
    final regions = [
      // Kedarnath region
      {'name': 'Kedarnath', 'center': const LatLng(30.735, 79.066), 'zoom': 13, 'radius': 2},
      // Tungnath region  
      {'name': 'Tungnath', 'center': const LatLng(30.49, 79.22), 'zoom': 13, 'radius': 2},
      // Badrinath region
      {'name': 'Badrinath', 'center': const LatLng(30.74, 79.49), 'zoom': 13, 'radius': 2},
    ];

    const urlTemplate = 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}';

    for (final region in regions) {
      final center = region['center'] as LatLng;
      final zoom = region['zoom'] as int;
      final radius = region['radius'] as int;

      debugPrint('[Offline] Pre-populating tiles for ${region['name']}');

      // Calculate tile coordinates for the region
      final z = zoom;
      final centerX = ((center.longitude + 180) / 360 * (1 << z)).toInt();
      final centerY = ((1 - (math.log(math.tan(center.latitude * math.pi / 180) + 1 / math.cos(center.latitude * math.pi / 180)) / math.pi)) / 2 * (1 << z)).toInt();

      // Download tiles in a radius around center
      for (int dx = -radius; dx <= radius; dx++) {
        for (int dy = -radius; dy <= radius; dy++) {
          final x = centerX + dx;
          final y = centerY + dy;
          final tileKey = '$z-$x-$y';

          // Check if already cached
          final existing = await db.getTile(tileKey);
          if (existing != null) continue;

          // Download tile
          final url = urlTemplate
              .replaceFirst('{z}', z.toString())
              .replaceFirst('{x}', x.toString())
              .replaceFirst('{y}', y.toString());

          try {
            final response = await dio.get<List<int>>(
              url,
              options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 10)),
            );
            if (response.data != null) {
              await db.saveTile(tileKey, response.data!);
              debugPrint('[Offline] Cached tile $tileKey for ${region['name']}');
            }
          } catch (e) {
            debugPrint('[Offline] Failed to cache tile $tileKey: $e');
          }
        }
      }
    }

    debugPrint('[Offline] Tile pre-population complete');
  }
}

class _DatabaseImageProvider extends ImageProvider<TileCoordinates> {
  final TileCoordinates coordinates;
  final String urlTemplate;
  final DatabaseService db;
  final Dio dio;

  _DatabaseImageProvider({
    required this.coordinates,
    required this.urlTemplate,
    required this.db,
    required this.dio,
  });

  @override
  Future<TileCoordinates> obtainKey(ImageConfiguration configuration) {
    return Future.value(coordinates);
  }

  @override
  ImageStreamCompleter loadImage(TileCoordinates key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0, // REQUIRED for many Flutter versions
      debugLabel: 'tile-${key.x}-${key.y}-${key.z}',
    );
  }

  Future<ui.Codec> _loadAsync(
    TileCoordinates key,
    ImageDecoderCallback decode,
  ) async {
    final tileKey = '${key.z}-${key.x}-${key.y}';

    try {
      // 1. Check SQLite Cache
      final cachedData = await db.getTile(tileKey);
      if (cachedData != null) {
        return await decode(await ui.ImmutableBuffer.fromUint8List(Uint8List.fromList(cachedData)));
      }

      // 2. Cache MISS -> Fetch from Network
      final url = urlTemplate
          .replaceFirst('{z}', key.z.toString())
          .replaceFirst('{x}', key.x.toString())
          .replaceFirst('{y}', key.y.toString());
          
      final response = await dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );

      if (response.data != null) {
        // 3. Save to Database (background)
        unawaited(db.saveTile(tileKey, response.data!));
        return await decode(await ui.ImmutableBuffer.fromUint8List(Uint8List.fromList(response.data!)));
      }
    } catch (e) {
      debugPrint('[Cache] Error loading tile $tileKey: $e');
    }

    // 4. Ultimate Fallback (1x1 transparent pixel)
    return await decode(await ui.ImmutableBuffer.fromUint8List(
      Uint8List.fromList([71, 73, 70, 56, 57, 97, 1, 0, 1, 0, 128, 0, 0, 0, 0, 0, 255, 255, 255, 33, 249, 4, 1, 0, 0, 0, 0, 44, 0, 0, 0, 0, 1, 0, 1, 0, 0, 2, 2, 68, 1, 0, 59])
    ));
  }
}
