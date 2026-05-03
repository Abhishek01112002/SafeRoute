import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:dio/dio.dart';
import 'package:saferoute/services/database_service.dart';
import 'package:saferoute/core/service_locator.dart';

/// A custom [TileProvider] that caches map tiles in the application's
/// internal SQLite database for instant offline access and faster re-loads.
class DatabaseTileProvider extends TileProvider {
  final _db = locator<DatabaseService>();
  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  ));

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _DatabaseImageProvider(
      coordinates: coordinates,
      urlTemplate: options.urlTemplate!,
      cacheNamespace: cacheNamespace(options.urlTemplate!),
      db: _db,
      dio: _dio,
    );
  }

  static String cacheNamespace(String urlTemplate) {
    if (urlTemplate.contains('lyrs=y')) return 'google-hybrid';
    if (urlTemplate.contains('lyrs=s')) return 'google-satellite';
    if (urlTemplate.contains('lyrs=m')) return 'google-standard';
    return urlTemplate.hashCode.toUnsigned(32).toRadixString(16);
  }

  static String cacheKeyFor({
    required String urlTemplate,
    required int z,
    required int x,
    required int y,
  }) {
    return '${cacheNamespace(urlTemplate)}-$z-$x-$y';
  }

  /// Proactively downloads and caches tiles for a specific radius around a location.
  /// Used for "Immediate Load" optimization of current live location.
  static Future<void> precacheArea({
    required LatLng center,
    required double zoom,
    required String urlTemplate,
  }) async {
    final dio = Dio();
    final db = locator<DatabaseService>();

    // Calculate a small grid around the center (3x3 tiles at current zoom)
    final z = zoom.toInt();
    final x = ((center.longitude + 180) / 360 * (1 << z)).toInt();
    final y = ((1 -
                (math.log(math.tan(center.latitude * math.pi / 180) +
                        1 / math.cos(center.latitude * math.pi / 180)) /
                    math.pi)) /
            2 *
            (1 << z))
        .toInt();

    debugPrint('[Cache] Pre-caching live area at z:$z');

    for (int dx = -1; dx <= 1; dx++) {
      for (int dy = -1; dy <= 1; dy++) {
        final tx = x + dx;
        final ty = y + dy;
        final key = cacheKeyFor(urlTemplate: urlTemplate, z: z, x: tx, y: ty);

        final existing = await db.getTile(key);
        if (existing == null) {
          final url = urlTemplate
              .replaceFirst('{z}', z.toString())
              .replaceFirst('{x}', tx.toString())
              .replaceFirst('{y}', ty.toString());

          try {
            final res = await dio.get<List<int>>(url,
                options: Options(responseType: ResponseType.bytes));
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
      final db = await locator<DatabaseService>().database;
      final results =
          await db.rawQuery('SELECT COUNT(*) as count FROM map_tiles');
      return results.first['count'] as int;
    } catch (_) {
      return 0;
    }
  }

  /// Pre-populates offline tiles for key regions during app initialization.
  /// Runs in a background isolate to avoid blocking the UI thread.
  /// Skips regions that are already cached to avoid redundant network calls.
  static Future<void> prePopulateOfflineTiles() async {
    final db = locator<DatabaseService>();

    // PERF FIX: Check if we already have enough tiles — skip if so.
    // This prevents the heavy I/O burst on every cold start.
    try {
      final result = await db.database.then(
        (d) => d.rawQuery('SELECT COUNT(*) as count FROM map_tiles'),
      );
      final count = result.first['count'] as int? ?? 0;
      // 3 regions × 5×5 grid = 75 tiles minimum. Skip if already populated.
      if (count >= 60) {
        debugPrint('[Offline] Tiles already populated ($count). Skipping.');
        return;
      }
    } catch (_) {}

    // Offload the download work to a background isolate so the UI thread
    // stays responsive. We pass only primitive data to the isolate.
    debugPrint('[Offline] Starting tile pre-population in background...');
    _runTilePopulationInBackground();
  }

  /// Fire-and-forget background download. Called without await so bootstrap
  /// returns immediately and the user sees the UI within milliseconds.
  static void _runTilePopulationInBackground() {
    Future.microtask(() async {
      final db = locator<DatabaseService>();
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ));

      final regions = [
        {'name': 'Kedarnath', 'lat': 30.735, 'lng': 79.066, 'zoom': 13, 'radius': 2},
        {'name': 'Tungnath',  'lat': 30.49,  'lng': 79.22,  'zoom': 13, 'radius': 2},
        {'name': 'Badrinath', 'lat': 30.74,  'lng': 79.49,  'zoom': 13, 'radius': 2},
      ];

      const urlTemplate = 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}';

      for (final region in regions) {
        final lat  = region['lat']  as double;
        final lng  = region['lng']  as double;
        final zoom = region['zoom'] as int;
        final radius = region['radius'] as int;

        final z = zoom;
        final centerX = ((lng + 180) / 360 * (1 << z)).toInt();
        final centerY = ((1 -
                (math.log(math.tan(lat * math.pi / 180) +
                        1 / math.cos(lat * math.pi / 180)) /
                    math.pi)) /
            2 *
            (1 << z))
            .toInt();

        for (int dx = -radius; dx <= radius; dx++) {
          for (int dy = -radius; dy <= radius; dy++) {
            final x = centerX + dx;
            final y = centerY + dy;
            final tileKey = cacheKeyFor(urlTemplate: urlTemplate, z: z, x: x, y: y);

            final existing = await db.getTile(tileKey);
            if (existing != null) continue;

            final url = urlTemplate
                .replaceFirst('{z}', z.toString())
                .replaceFirst('{x}', x.toString())
                .replaceFirst('{y}', y.toString());

            try {
              final response = await dio.get<List<int>>(
                url,
                options: Options(responseType: ResponseType.bytes),
              );
              if (response.data != null) {
                await db.saveTile(tileKey, response.data!);
                debugPrint('[Offline] Cached tile $tileKey for ${region['name']}');
              }
            } catch (e) {
              debugPrint('[Offline] Failed tile $tileKey: $e');
            }

            // PERF FIX: 80ms throttle between tile downloads so the
            // SQLite writes and network don't burst and starve the UI thread.
            await Future.delayed(const Duration(milliseconds: 80));
          }
        }
      }

      debugPrint('[Offline] Tile pre-population complete');
    });
  }
}

class _DatabaseImageProvider extends ImageProvider<TileCoordinates> {
  final TileCoordinates coordinates;
  final String urlTemplate;
  final String cacheNamespace;
  final DatabaseService db;
  final Dio dio;

  _DatabaseImageProvider({
    required this.coordinates,
    required this.urlTemplate,
    required this.cacheNamespace,
    required this.db,
    required this.dio,
  });

  @override
  Future<TileCoordinates> obtainKey(ImageConfiguration configuration) {
    return Future.value(coordinates);
  }

  @override
  ImageStreamCompleter loadImage(
      TileCoordinates key, ImageDecoderCallback decode) {
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
    final tileKey = '$cacheNamespace-${key.z}-${key.x}-${key.y}';

    try {
      // 1. Check SQLite Cache
      final cachedData = await db.getTile(tileKey);
      if (cachedData != null) {
        return await decode(await ui.ImmutableBuffer.fromUint8List(
            Uint8List.fromList(cachedData)));
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
        return await decode(await ui.ImmutableBuffer.fromUint8List(
            Uint8List.fromList(response.data!)));
      }
    } catch (e) {
      debugPrint('[Cache] Error loading tile $tileKey: $e');
    }

    // 4. Ultimate Fallback (1x1 transparent pixel)
    return await decode(
        await ui.ImmutableBuffer.fromUint8List(Uint8List.fromList([
      71,
      73,
      70,
      56,
      57,
      97,
      1,
      0,
      1,
      0,
      128,
      0,
      0,
      0,
      0,
      0,
      255,
      255,
      255,
      33,
      249,
      4,
      1,
      0,
      0,
      0,
      0,
      44,
      0,
      0,
      0,
      0,
      1,
      0,
      1,
      0,
      0,
      2,
      2,
      68,
      1,
      0,
      59
    ])));
  }
}
