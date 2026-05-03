// test/core/app_error_test.dart
//
// Tests for the AppError hierarchy and ApiException converter.
// These are pure unit tests — no Flutter widgets, no async, no network.

import 'package:flutter_test/flutter_test.dart';
import 'package:saferoute/core/errors/app_error.dart';
import 'package:saferoute/services/api_service.dart';

void main() {
  group('AppError.from() — ApiException conversion', () {
    test('converts RateLimitException to RateLimitError', () {
      final e = RateLimitException(retryAfter: const Duration(seconds: 30));
      final error = AppError.from(e);

      expect(error, isA<RateLimitError>());
      expect((error as RateLimitError).retryAfter?.inSeconds, 30);
    });

    test('converts AuthCorruptionException to AuthError.sessionCorrupted', () {
      final e = AuthCorruptionException();
      final error = AppError.from(e);

      expect(error, isA<AuthError>());
      expect((error as AuthError).reason, AuthErrorReason.sessionCorrupted);
    });

    test('converts 401 ApiException to AuthError.unauthorized', () {
      final e = ApiException('Unauthorized', statusCode: 401);
      final error = AppError.from(e);

      expect(error, isA<AuthError>());
      expect((error as AuthError).reason, AuthErrorReason.unauthorized);
    });

    test('converts 404 ApiException to NotFoundError', () {
      final e = ApiException('Tourist not found', statusCode: 404);
      final error = AppError.from(e);

      expect(error, isA<NotFoundError>());
    });

    test('converts 422 ApiException to ValidationError', () {
      final e = ApiException('Validation error', statusCode: 422);
      final error = AppError.from(e);

      expect(error, isA<ValidationError>());
    });

    test('converts 500 ApiException to ServerError', () {
      final e = ApiException('Internal Server Error', statusCode: 500);
      final error = AppError.from(e);

      expect(error, isA<ServerError>());
      expect((error as ServerError).statusCode, 500);
    });

    test('converts generic ApiException (no code) to NetworkError', () {
      final e = ApiException('Connection timeout');
      final error = AppError.from(e);

      expect(error, isA<NetworkError>());
    });

    test('converts arbitrary Exception to UnknownError', () {
      final e = Exception('Something weird happened');
      final error = AppError.from(e);

      expect(error, isA<UnknownError>());
    });
  });

  group('AppError.userMessage — safe for display', () {
    test('NetworkError has a user-friendly message', () {
      const error = NetworkError(detail: 'timeout');
      expect(error.userMessage, isNotEmpty);
      expect(error.userMessage, isNot(contains('timeout'))); // no tech detail
    });

    test('OfflineError has a user-friendly message', () {
      const error = OfflineError();
      expect(error.userMessage, isNotEmpty);
    });

    test('RateLimitError with retryAfter includes seconds in message', () {
      const error = RateLimitError(retryAfter: Duration(seconds: 45));
      expect(error.userMessage, contains('45'));
    });

    test('RateLimitError without retryAfter still has message', () {
      const error = RateLimitError();
      expect(error.userMessage, isNotEmpty);
    });

    test('AuthError.locked includes minutes in message', () {
      const error = AuthError(
        reason: AuthErrorReason.locked,
        lockDuration: Duration(minutes: 15),
      );
      expect(error.userMessage, contains('15'));
    });

    test('ServerError always has a generic user message', () {
      const error = ServerError(statusCode: 503, detail: 'DB connection failed');
      // Should NOT expose DB details to user
      expect(error.userMessage, isNot(contains('DB')));
      expect(error.userMessage, isNotEmpty);
    });
  });

  group('AppError.logMessage — safe for logging', () {
    test('logMessage includes technical details', () {
      const error = ServerError(statusCode: 503, detail: 'DB connection failed');
      expect(error.logMessage, contains('503'));
      expect(error.logMessage, contains('DB connection failed'));
    });

    test('NetworkError.logMessage includes detail', () {
      const error = NetworkError(detail: 'timeout after 30s');
      expect(error.logMessage, contains('timeout after 30s'));
    });
  });
}
