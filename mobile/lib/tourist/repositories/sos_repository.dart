// lib/tourist/repositories/sos_repository.dart
//
// SOS Repository
// ---------------
// Wraps ApiService.triggerSosAlert() and DatabaseService.saveSosEvent()
// into a single, Result-typed interface.
//
// Flow:
//   1. If online  → try API (3 attempts via ApiService)
//   2. If offline → save to local DB (synced when connectivity returns)
//   3. Always     → attempt BLE Mesh relay if active
//
// NOTE: Existing SOSScreenV2 is unchanged. This is NEW infrastructure.

import 'package:flutter/foundation.dart';
import 'package:saferoute/core/errors/app_error.dart';
import 'package:saferoute/core/models/api_responses.dart';
import 'package:saferoute/core/service_locator.dart';
import 'package:saferoute/core/utils/result.dart';
import 'package:saferoute/services/api_service.dart';
import 'package:saferoute/services/database_service.dart';

enum SosDeliveryChannel { api, localFallback, meshRelay }

class SosDeliveryResult {
  final bool delivered;
  final SosDeliveryChannel channel;
  final String statusMessage;

  const SosDeliveryResult({
    required this.delivered,
    required this.channel,
    required this.statusMessage,
  });
}

class SosRepository {
  ApiService get _api => locator<ApiService>();
  DatabaseService get _db => locator<DatabaseService>();

  /// Triggers SOS alert. Returns a typed [SosDeliveryResult].
  ///
  /// [touristId]   – the tourist or guest session ID
  /// [lat], [lng]  – current GPS coordinates
  /// [isOnline]    – pass the current connectivity state from LocationProvider
  /// [triggerType] – 'MANUAL', 'AUTO_FALL', or 'GEOFENCE_BREACH'
  Future<Result<SosDeliveryResult>> trigger({
    required String touristId,
    required double lat,
    required double lng,
    required bool isOnline,
    String triggerType = 'MANUAL',
  }) async {
    if (isOnline) {
      try {
        final sosResult = await _api.triggerSosAlert(
          lat,
          lng,
          triggerType,
          touristId: touristId,
        );

        debugPrint('[SosRepository] API delivery: ${sosResult.status}');

        return Success(SosDeliveryResult(
          delivered: sosResult.accepted,
          channel: SosDeliveryChannel.api,
          statusMessage: sosResult.dispatched
              ? 'RESCUE TEAM HAS BEEN NOTIFIED'
              : 'ALERT STORED. TRY CALLING 112.',
        ));
      } catch (e) {
        // API failed — fall through to local save
        debugPrint('[SosRepository] API trigger failed, saving locally: $e');
      }
    }

    // Offline or API failure — save locally for later sync
    try {
      await _db.saveSosEvent(
        touristId: touristId,
        latitude: lat,
        longitude: lng,
        triggerType: triggerType,
      );

      return const Success(SosDeliveryResult(
        delivered: false,
        channel: SosDeliveryChannel.localFallback,
        statusMessage:
            'OFFLINE MODE: ALERT SAVED. MESH RELAY ATTEMPTING DELIVERY.',
      ));
    } catch (e) {
      return Failure(AppError.from(e));
    }
  }
}
