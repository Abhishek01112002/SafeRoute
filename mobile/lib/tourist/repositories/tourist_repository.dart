// lib/tourist/repositories/tourist_repository.dart
//
// Tourist Repository
// -------------------
// Sits between Providers and raw Services. Implements:
//   - Cache-first data access (local DB → then API)
//   - Typed Result<T> return values (no raw Maps, no throwing)
//   - Single source of truth for tourist data operations
//
// NOTE: Existing TouristProvider is unchanged. This is NEW infrastructure
//       available for new features and gradual migration.

import 'package:flutter/foundation.dart';
import 'package:saferoute/core/errors/app_error.dart';
import 'package:saferoute/core/models/api_responses.dart';
import 'package:saferoute/core/service_locator.dart';
import 'package:saferoute/core/utils/result.dart';
import 'package:saferoute/services/api_service.dart';
import 'package:saferoute/services/database_service.dart';
import 'package:saferoute/services/secure_storage_service.dart';
import 'package:saferoute/tourist/models/tourist_model.dart';

class TouristRepository {
  ApiService get _api => locator<ApiService>();
  DatabaseService get _db => locator<DatabaseService>();
  SecureStorageService get _secureStorage => locator<SecureStorageService>();

  // ---------------------------------------------------------------------------
  // READ — Cache-first tourist fetch
  // ---------------------------------------------------------------------------

  /// Returns the tourist profile.
  /// Tries local DB first for instant offline response, falls back to API.
  Future<Result<Tourist>> getTourist() async {
    try {
      // 1. Try local cache first (instant, offline-safe)
      final cached = await _db.getTourist();
      if (cached != null) {
        debugPrint('[TouristRepository] Returning cached tourist: ${cached.touristId}');
        return Success(cached);
      }

      // 2. Nothing in cache — try API
      final touristId = await _secureStorage.getTouristId();
      if (touristId == null) {
        return const Failure(NotFoundError(resource: 'tourist_id in secure storage'));
      }

      final raw = await _api.loginTourist(touristId);
      final response = LoginTouristResponse.fromRaw(raw);

      if (response.tourist == null) {
        return const Failure(NotFoundError(resource: 'tourist from API'));
      }

      // 3. Cache the result
      await _db.saveTourist(response.tourist!);
      return Success(response.tourist!);
    } on ApiException catch (e) {
      return Failure(AppError.from(e));
    } catch (e) {
      return Failure(AppError.from(e));
    }
  }

  // ---------------------------------------------------------------------------
  // REGISTER
  // ---------------------------------------------------------------------------

  /// Registers a tourist. Returns typed [RegisterTouristResponse] on success.
  Future<Result<RegisterTouristResponse>> register(
    Map<String, dynamic> formData,
  ) async {
    try {
      final raw = await _api.registerTouristWithToken(formData);
      final response = RegisterTouristResponse.fromRaw(raw);

      if (!response.isValid) {
        return const Failure(
          ServerError(statusCode: 200, detail: 'Missing token or tourist in response'),
        );
      }

      return Success(response);
    } on ApiException catch (e) {
      return Failure(AppError.from(e));
    } catch (e) {
      return Failure(AppError.from(e));
    }
  }

  // ---------------------------------------------------------------------------
  // LOGIN
  // ---------------------------------------------------------------------------

  /// Logs in a tourist by ID. Returns typed response.
  Future<Result<LoginTouristResponse>> login(String touristId) async {
    try {
      final raw = await _api.loginTourist(touristId);
      final response = LoginTouristResponse.fromRaw(raw);

      if (!response.isValid) {
        return const Failure(
          AuthError(reason: AuthErrorReason.unauthorized),
        );
      }

      // Persist locally
      await _db.saveTourist(response.tourist!);
      return Success(response);
    } on RateLimitException catch (e) {
      return Failure(RateLimitError(retryAfter: e.retryAfter));
    } on ApiException catch (e) {
      return Failure(AppError.from(e));
    } catch (e) {
      return Failure(AppError.from(e));
    }
  }

  // ---------------------------------------------------------------------------
  // DELETE (local only)
  // ---------------------------------------------------------------------------

  /// Clears tourist data from local cache.
  Future<Result<void>> clearLocal() async {
    try {
      await _db.deleteTourist();
      return const Success(null);
    } catch (e) {
      return Failure(AppError.from(e));
    }
  }
}
