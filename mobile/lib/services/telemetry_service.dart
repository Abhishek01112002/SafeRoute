// lib/services/telemetry_service.dart
import 'package:flutter/foundation.dart';

/// TelemetryService: Error tracking and analytics framework
/// 
/// This service provides a foundation for collecting crash reports, errors, and analytics.
/// In production, integrate with services like:
/// - Firebase Crashlytics (Google Cloud)
/// - Sentry (sentry.io)
/// - Datadog
/// - LogRocket
/// 
/// Current implementation logs to console in debug mode.
/// For production, implement reportError() and trackEvent() with actual services.

class TelemetryService {
  static final TelemetryService _instance = TelemetryService._internal();
  
  factory TelemetryService() => _instance;
  
  TelemetryService._internal();

  /// Report a non-fatal error to telemetry service
  /// 
  /// In production, route this to Sentry, Crashlytics, etc.
  /// Example: 
  ///   await Sentry.captureException(error, stackTrace: stackTrace);
  Future<void> reportError(
    dynamic error, {
    StackTrace? stackTrace,
    String? context,
    Map<String, String>? customData,
  }) async {
    debugPrint('🔴 [ERROR] $error');
    if (context != null) debugPrint('   Context: $context');
    if (customData != null) debugPrint('   Data: $customData');
    if (stackTrace != null) debugPrint('   Stack: $stackTrace');

    // TODO: Integrate with production error tracking service
    // Example for Sentry:
    // await Sentry.captureException(
    //   error,
    //   stackTrace: stackTrace,
    //   withScope: (scope) {
    //     if (context != null) scope.setContext('additional', {'context': context});
    //     customData?.forEach((key, value) => scope.setTag(key, value));
    //   },
    // );
  }

  /// Track a custom event
  /// 
  /// Examples:
  ///   - User registration completed
  ///   - SOS triggered
  ///   - Offline sync successful
  ///   - Location permission denied
  Future<void> trackEvent(
    String eventName, {
    Map<String, String>? properties,
  }) async {
    debugPrint('📊 [EVENT] $eventName');
    if (properties != null) debugPrint('   Properties: $properties');

    // TODO: Integrate with analytics service
    // Example for Firebase Analytics:
    // await FirebaseAnalytics.instance.logEvent(
    //   name: eventName,
    //   parameters: properties,
    // );
  }

  /// Track user action (registration, login, SOS trigger, etc.)
  Future<void> trackUserAction(String action, {String? userId}) async {
    await trackEvent('user_action', properties: {
      'action': action,
      if (userId != null) 'user_id': userId,
    });
  }

  /// Report API errors with context
  Future<void> reportApiError({
    required String endpoint,
    required int statusCode,
    required String message,
    String? requestId,
  }) async {
    await reportError(
      'API Error: $statusCode on $endpoint',
      context: 'API Call',
      customData: {
        'endpoint': endpoint,
        'status_code': statusCode.toString(),
        'message': message,
        if (requestId != null) 'request_id': requestId,
      },
    );
  }

  /// Report background service errors
  Future<void> reportBackgroundServiceError(
    String errorType, {
    required String message,
    String? touristId,
  }) async {
    await reportError(
      'Background Service Error: $errorType',
      context: 'Background Service',
      customData: {
        'error_type': errorType,
        'message': message,
        if (touristId != null) 'tourist_id': touristId,
      },
    );
  }

  /// Report sync errors
  Future<void> reportSyncError({
    required String dataType, // 'ping', 'sos', 'room', etc.
    required int failedCount,
    String? lastError,
  }) async {
    await reportError(
      'Sync Failed: $dataType',
      context: 'Offline Sync',
      customData: {
        'data_type': dataType,
        'failed_count': failedCount.toString(),
        if (lastError != null) 'last_error': lastError,
      },
    );
  }

  /// Track authentication events
  Future<void> trackAuthEvent(String eventType, {String? reason}) async {
    await trackEvent('auth_event', properties: {
      'event': eventType,
      if (reason != null) 'reason': reason,
    });
  }

  /// Track emergency events (SOS triggered, etc.)
  Future<void> trackEmergencyEvent(String eventType, {String? details}) async {
    await trackEvent('emergency_event', properties: {
      'type': eventType,
      if (details != null) 'details': details,
    });
  }
}
