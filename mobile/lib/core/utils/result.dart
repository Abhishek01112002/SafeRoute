// lib/core/utils/result.dart
//
// SafeRoute Result Type
// ----------------------
// A simple sealed type for representing success or failure without throwing.
// Services and Repositories return Result<T> instead of throwing exceptions.
// Providers use pattern matching to handle both cases cleanly.
//
// Usage:
//   final result = await repository.getTourist(id);
//   switch (result) {
//     case Success(data: final tourist) => showTourist(tourist);
//     case Failure(error: final e)      => showError(e.userMessage);
//   }

import 'package:saferoute/core/errors/app_error.dart';

/// Represents the outcome of an operation that can succeed or fail.
sealed class Result<T> {
  const Result();
}

/// The operation completed successfully with [data].
final class Success<T> extends Result<T> {
  final T data;
  const Success(this.data);

  @override
  String toString() => 'Success($data)';
}

/// The operation failed with an [error].
final class Failure<T> extends Result<T> {
  final AppError error;
  const Failure(this.error);

  @override
  String toString() => 'Failure($error)';
}

// ---------------------------------------------------------------------------
// Extension Methods — Convenient helpers for working with Result<T>
// ---------------------------------------------------------------------------

extension ResultExtension<T> on Result<T> {
  /// Returns the data if this is [Success], otherwise `null`.
  T? get dataOrNull => switch (this) {
        Success(data: final d) => d,
        Failure() => null,
      };

  /// Returns the error if this is [Failure], otherwise `null`.
  AppError? get errorOrNull => switch (this) {
        Success() => null,
        Failure(error: final e) => e,
      };

  /// Returns `true` if this result is a [Success].
  bool get isSuccess => this is Success<T>;

  /// Returns `true` if this result is a [Failure].
  bool get isFailure => this is Failure<T>;

  /// Transforms [Success] data with [mapper]. [Failure] is passed through.
  Result<R> map<R>(R Function(T data) mapper) => switch (this) {
        Success(data: final d) => Success(mapper(d)),
        Failure(error: final e) => Failure(e),
      };

  /// Calls [onSuccess] or [onFailure] depending on the result type.
  R fold<R>({
    required R Function(T data) onSuccess,
    required R Function(AppError error) onFailure,
  }) =>
      switch (this) {
        Success(data: final d) => onSuccess(d),
        Failure(error: final e) => onFailure(e),
      };

  /// Returns data if [Success], otherwise [fallback].
  T getOrElse(T fallback) => dataOrNull ?? fallback;
}

// ---------------------------------------------------------------------------
// Static Factory Helpers
// ---------------------------------------------------------------------------

/// Runs [body] and wraps the result in [Success] or [Failure].
/// Catches any exception and converts it to [AppError] via [AppError.from].
Future<Result<T>> runCatching<T>(Future<T> Function() body) async {
  try {
    return Success(await body());
  } catch (e) {
    return Failure(AppError.from(e));
  }
}
