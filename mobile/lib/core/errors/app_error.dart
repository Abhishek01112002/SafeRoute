// lib/core/errors/app_error.dart
//
// SafeRoute Unified Error Hierarchy
// ----------------------------------
// Maps all network, auth, and business errors to a single sealed type.
// UI code reads `error.userMessage`. Logging reads `error.logMessage`.
// Existing ApiException classes in api_service.dart are unchanged —
// use `AppError.fromApiException()` to bridge between them.

import 'package:saferoute/services/api_service.dart';

/// Base sealed class for all SafeRoute application errors.
sealed class AppError {
  const AppError();

  /// Human-readable message suitable for displaying to the user.
  String get userMessage;

  /// Technical message for logging/Crashlytics — never shown to user.
  String get logMessage;

  @override
  String toString() => 'AppError($runtimeType): $logMessage';

  // ---------------------------------------------------------------------------
  // Factory: Bridge from existing ApiException hierarchy
  // ---------------------------------------------------------------------------

  /// Converts any caught exception into a typed [AppError].
  /// This is the single conversion point — use it in repository catch blocks.
  static AppError from(Object error) {
    if (error is RateLimitException) {
      return RateLimitError(retryAfter: error.retryAfter);
    }
    if (error is AuthCorruptionException) {
      return const AuthError(reason: AuthErrorReason.sessionCorrupted);
    }
    if (error is ApiException) {
      final code = error.statusCode;
      if (code == 401) {
        return const AuthError(reason: AuthErrorReason.unauthorized);
      }
      if (code == 404) {
        return NotFoundError(resource: error.message);
      }
      if (code == 422) {
        return ValidationError(serverMessage: error.message);
      }
      if (code != null && code >= 500) {
        return ServerError(statusCode: code, detail: error.message);
      }
      return NetworkError(detail: error.message);
    }
    // Generic fallback
    return UnknownError(cause: error.toString());
  }
}

// ---------------------------------------------------------------------------
// Concrete Error Types
// ---------------------------------------------------------------------------

/// Network connectivity or timeout errors.
class NetworkError extends AppError {
  final String? detail;
  const NetworkError({this.detail});

  @override
  String get userMessage =>
      'Connection problem. Please check your internet and try again.';

  @override
  String get logMessage => 'NetworkError: ${detail ?? 'unknown network issue'}';
}

/// Device is offline (no connectivity detected locally).
class OfflineError extends AppError {
  const OfflineError();

  @override
  String get userMessage =>
      'You\'re offline. This action requires an internet connection.';

  @override
  String get logMessage => 'OfflineError: device has no connectivity';
}

/// Authentication / authorization failures.
enum AuthErrorReason { unauthorized, sessionCorrupted, tokenExpired, locked }

class AuthError extends AppError {
  final AuthErrorReason reason;
  final String? detail;
  final Duration? lockDuration;

  const AuthError({required this.reason, this.detail, this.lockDuration});

  @override
  String get userMessage {
    switch (reason) {
      case AuthErrorReason.unauthorized:
        return 'Your session has expired. Please log in again.';
      case AuthErrorReason.sessionCorrupted:
        return 'Your session data is corrupted. Please log in again.';
      case AuthErrorReason.tokenExpired:
        return 'Your login has expired. Please log in again.';
      case AuthErrorReason.locked:
        final mins = lockDuration?.inMinutes ?? 15;
        return 'Account locked due to failed attempts. Try again in $mins minutes.';
    }
  }

  @override
  String get logMessage => 'AuthError[$reason]: ${detail ?? ''}';
}

/// Server-side validation failed (HTTP 422).
class ValidationError extends AppError {
  final String? serverMessage;
  final List<String> fields;

  const ValidationError({this.serverMessage, this.fields = const []});

  @override
  String get userMessage =>
      serverMessage ?? 'Some fields are invalid. Please review your input.';

  @override
  String get logMessage =>
      'ValidationError: ${serverMessage ?? ''} fields=$fields';
}

/// Backend returned an unexpected 5xx error.
class ServerError extends AppError {
  final int statusCode;
  final String? detail;

  const ServerError({required this.statusCode, this.detail});

  @override
  String get userMessage =>
      'The server encountered an error. Please try again shortly.';

  @override
  String get logMessage => 'ServerError[$statusCode]: ${detail ?? ''}';
}

/// Resource not found (HTTP 404).
class NotFoundError extends AppError {
  final String resource;
  const NotFoundError({required this.resource});

  @override
  String get userMessage => 'The requested data could not be found.';

  @override
  String get logMessage => 'NotFoundError: $resource not found';
}

/// Rate limit hit (HTTP 429).
class RateLimitError extends AppError {
  final Duration? retryAfter;
  const RateLimitError({this.retryAfter});

  @override
  String get userMessage {
    if (retryAfter != null) {
      return 'Too many requests. Please wait ${retryAfter!.inSeconds} seconds.';
    }
    return 'Too many requests. Please wait a moment and try again.';
  }

  @override
  String get logMessage =>
      'RateLimitError: retry_after=${retryAfter?.inSeconds}s';
}

/// Catch-all for unexpected errors that don't fit above categories.
class UnknownError extends AppError {
  final String cause;
  const UnknownError({required this.cause});

  @override
  String get userMessage =>
      'Something went wrong. Please restart the app and try again.';

  @override
  String get logMessage => 'UnknownError: $cause';
}
