// test/core/result_test.dart
//
// Tests for the Result<T> sealed type and its extension methods.
// Pure unit tests — no Flutter, no network.

import 'package:flutter_test/flutter_test.dart';
import 'package:saferoute/core/errors/app_error.dart';
import 'package:saferoute/core/utils/result.dart';
import 'package:saferoute/services/api_service.dart';

void main() {
  group('Result — basic construction', () {
    test('Success wraps data correctly', () {
      const result = Success(42);
      expect(result.data, 42);
    });

    test('Failure wraps error correctly', () {
      const error = NetworkError(detail: 'no wifi');
      const result = Failure<int>(error);
      expect(result.error, isA<NetworkError>());
    });
  });

  group('ResultExtension — isSuccess / isFailure', () {
    test('Success.isSuccess returns true', () {
      const result = Success('hello');
      expect(result.isSuccess, isTrue);
      expect(result.isFailure, isFalse);
    });

    test('Failure.isFailure returns true', () {
      const result = Failure<String>(OfflineError());
      expect(result.isFailure, isTrue);
      expect(result.isSuccess, isFalse);
    });
  });

  group('ResultExtension — dataOrNull / errorOrNull', () {
    test('Success.dataOrNull returns data', () {
      const result = Success('abc');
      expect(result.dataOrNull, 'abc');
      expect(result.errorOrNull, isNull);
    });

    test('Failure.errorOrNull returns error', () {
      const result = Failure<String>(OfflineError());
      expect(result.errorOrNull, isA<OfflineError>());
      expect(result.dataOrNull, isNull);
    });
  });

  group('ResultExtension — getOrElse', () {
    test('Success.getOrElse returns data', () {
      const result = Success(10);
      expect(result.getOrElse(0), 10);
    });

    test('Failure.getOrElse returns fallback', () {
      const result = Failure<int>(NetworkError());
      expect(result.getOrElse(99), 99);
    });
  });

  group('ResultExtension — map', () {
    test('Success.map transforms data', () {
      const result = Success(5);
      final mapped = result.map((d) => d * 2);
      expect(mapped, isA<Success<int>>());
      expect((mapped as Success<int>).data, 10);
    });

    test('Failure.map passes error through unchanged', () {
      const result = Failure<int>(ServerError(statusCode: 500));
      final mapped = result.map((d) => d * 2);
      expect(mapped, isA<Failure<int>>());
    });
  });

  group('ResultExtension — fold', () {
    test('fold calls onSuccess for Success', () {
      const result = Success('data');
      final out = result.fold(
        onSuccess: (d) => 'got: $d',
        onFailure: (e) => 'error',
      );
      expect(out, 'got: data');
    });

    test('fold calls onFailure for Failure', () {
      const result = Failure<String>(OfflineError());
      final out = result.fold(
        onSuccess: (d) => 'got: $d',
        onFailure: (e) => 'error: ${e.runtimeType}',
      );
      expect(out, 'error: OfflineError');
    });
  });

  group('runCatching — async helper', () {
    test('wraps successful async call in Success', () async {
      final result = await runCatching(() async => 'hello');
      expect(result, isA<Success<String>>());
      expect(result.dataOrNull, 'hello');
    });

    test('wraps thrown ApiException in Failure', () async {
      final result = await runCatching<int>(() async {
        throw ApiException('Something failed', statusCode: 500);
      });
      expect(result, isA<Failure<int>>());
      expect(result.errorOrNull, isA<ServerError>());
    });

    test('wraps generic Exception in Failure with UnknownError', () async {
      final result = await runCatching<int>(() async {
        throw Exception('unexpected');
      });
      expect(result, isA<Failure<int>>());
      expect(result.errorOrNull, isA<UnknownError>());
    });
  });
}
