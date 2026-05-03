// lib/authority/repositories/authority_repository.dart
//
// Authority Repository
// ---------------------
// Wraps ApiService authority methods into Result-typed calls.
// Existing AuthorityLoginScreen continues using ApiService directly.
// This is NEW infrastructure available for new features.

import 'package:saferoute/core/errors/app_error.dart';
import 'package:saferoute/core/models/api_responses.dart';
import 'package:saferoute/core/service_locator.dart';
import 'package:saferoute/core/utils/result.dart';
import 'package:saferoute/services/api_service.dart';

class AuthorityRepository {
  ApiService get _api => locator<ApiService>();

  /// Logs in an authority user. Returns typed [AuthorityLoginResponse].
  Future<Result<AuthorityLoginResponse>> login(
    String email,
    String password,
  ) async {
    try {
      final raw = await _api.loginAuthority(email, password);
      final response = AuthorityLoginResponse.fromRaw(raw);

      if (!response.isValid) {
        return const Failure(
          AuthError(reason: AuthErrorReason.unauthorized),
        );
      }

      return Success(response);
    } on RateLimitException catch (e) {
      return Failure(RateLimitError(retryAfter: e.retryAfter));
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        return const Failure(AuthError(reason: AuthErrorReason.unauthorized));
      }
      return Failure(AppError.from(e));
    } catch (e) {
      return Failure(AppError.from(e));
    }
  }

  /// Registers a new authority account. Returns typed response.
  Future<Result<AuthorityLoginResponse>> register(
    Map<String, dynamic> formData,
  ) async {
    try {
      final raw = await _api.registerAuthority(formData);
      final response = AuthorityLoginResponse.fromRaw(raw);
      return Success(response);
    } on ApiException catch (e) {
      return Failure(AppError.from(e));
    } catch (e) {
      return Failure(AppError.from(e));
    }
  }
}
