import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:saferoute/services/database_tile_provider.dart';
import 'package:saferoute/services/database_service.dart';
import 'package:saferoute/core/service_locator.dart';

class OfflineRegion {
  final String name;
  final LatLng min;
  final LatLng max;

  OfflineRegion({required this.name, required this.min, required this.max});
}

class DownloadProgress {
  final String regionName;
  final int total;
  final int downloaded;
  final bool isComplete;

  DownloadProgress({
    required this.regionName,
    required this.total,
    required this.downloaded,
    this.isComplete = false,
  });

  double get progress => total == 0 ? 0 : downloaded / total;
}

class TileDownloaderService {
  static final TileDownloaderService _instance =
      TileDownloaderService._internal();
  factory TileDownloaderService() => _instance;
  TileDownloaderService._internal();

  final _dio = Dio();
  final _db = locator<DatabaseService>();

  // Region Definitions
  static final Map<String, OfflineRegion> regions = {
    'KEDARNATH': OfflineRegion(
      name: 'Kedarnath Expedition',
      min: const LatLng(30.70, 79.03),
      max: const LatLng(30.78, 79.11),
    ),
    'TUNGNATH': OfflineRegion(
      name: 'Tungnath Sanctuary',
      min: const LatLng(30.46, 79.18),
      max: const LatLng(30.53, 79.25),
    ),
  };

  /// Converts a LatLng to tile coordinates (x, y) for a given zoom.
  math.Point<int> _latLonToTile(LatLng pos, int zoom) {
    final n = math.pow(2, zoom);
    final x = ((pos.longitude + 180) / 360 * n).toInt();
    final y = ((1 -
                (math.log(math.tan(pos.latitude * math.pi / 180) +
                        1 / math.cos(pos.latitude * math.pi / 180)) /
                    math.pi)) /
            2 *
            n)
        .toInt();
    return math.Point(x, y);
  }

  /// Downloads all tiles for a region between specified zoom levels.
  Stream<DownloadProgress> downloadRegion(String regionKey,
      {int minZoom = 12,
      int maxZoom = 16,
      required String urlTemplate}) async* {
    final region = regions[regionKey];
    if (region == null) return;

    final List<String> tileQueue = [];

    // 1. Calculate tile queue
    for (int z = minZoom; z <= maxZoom; z++) {
      final pMin = _latLonToTile(region.min, z);
      final pMax = _latLonToTile(region.max, z);

      final xMin = math.min(pMin.x, pMax.x);
      final xMax = math.max(pMin.x, pMax.x);
      final yMin = math.min(pMin.y, pMax.y);
      final yMax = math.max(pMin.y, pMax.y);

      for (int x = xMin; x <= xMax; x++) {
        for (int y = yMin; y <= yMax; y++) {
          tileQueue.add(DatabaseTileProvider.cacheKeyFor(
            urlTemplate: urlTemplate,
            z: z,
            x: x,
            y: y,
          ));
        }
      }
    }

    final int total = tileQueue.length;
    int downloaded = 0;

    yield DownloadProgress(regionName: regionKey, total: total, downloaded: 0);

    // 2. Download loop (Sequential for safety, could be parallelized)
    for (final tileKey in tileQueue) {
      final parts = tileKey.split('-');
      final z = parts[parts.length - 3];
      final x = parts[parts.length - 2];
      final y = parts[parts.length - 1];

      final existing = await _db.getTile(tileKey);
      if (existing != null) {
        downloaded++;
        if (downloaded % 10 == 0) {
          yield DownloadProgress(
              regionName: regionKey, total: total, downloaded: downloaded);
        }
        continue;
      }

      final url = urlTemplate
          .replaceFirst('{z}', z)
          .replaceFirst('{x}', x)
          .replaceFirst('{y}', y);

      try {
        final res = await _dio.get<List<int>>(
          url,
          options: Options(
              responseType: ResponseType.bytes,
              receiveTimeout: const Duration(seconds: 5)),
        );

        if (res.data != null) {
          await _db.saveTile(tileKey, res.data!);
        }
      } catch (e) {
        debugPrint('Failed to download tile $tileKey: $e');
      }

      downloaded++;
      // Report progress every 5 tiles or at the end
      if (downloaded % 5 == 0 || downloaded == total) {
        yield DownloadProgress(
            regionName: regionKey, total: total, downloaded: downloaded);
      }
    }

    yield DownloadProgress(
        regionName: regionKey,
        total: total,
        downloaded: total,
        isComplete: true);
  }
}
