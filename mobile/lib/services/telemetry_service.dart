// lib/services/telemetry_service.dart
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

class TelemetryService {
  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;
  static final FirebaseCrashlytics _crashlytics = FirebaseCrashlytics.instance;

  // Log a custom event (e.g., screen view, button tap, feature usage)
  static void logEvent(String name, {Map<String, dynamic>? parameters}) {
    if (kReleaseMode) {
      _analytics.logEvent(
        name: name,
        parameters: parameters?.cast<String, Object>(),
      );
    } else {
      debugPrint('📊 [Analytics] $name $parameters');
    }
  }

  // Log a non-fatal error (e.g., API failure, BLE mesh error)
  static void logError(dynamic error, StackTrace? stack, {String? context}) {
    if (kReleaseMode) {
      _crashlytics.recordError(error, stack, reason: context);
    } else {
      debugPrint('⚠️ [Crashlytics] $context: $error\n$stack');
    }
  }

  // Log a fatal crash (use for uncaught exceptions – already handled by main.dart)
  static void logFatal(dynamic error, StackTrace stack, {String? context}) {
    if (kReleaseMode) {
      _crashlytics.recordError(error, stack, reason: context, fatal: true);
    } else {
      debugPrint('💀 [Fatal] $context: $error\n$stack');
    }
  }

  // Set custom user ID (e.g., tourist_id after login)
  static void setUserId(String? userId) {
    if (kReleaseMode && userId != null) {
      _crashlytics.setUserIdentifier(userId);
      _analytics.setUserId(id: userId);
    } else {
      debugPrint('👤 [User ID] $userId');
    }
  }

  // Set custom key/value for debugging (appears in Crashlytics logs)
  static void setCustomKey(String key, dynamic value) {
    if (kReleaseMode) {
      _crashlytics.setCustomKey(key, value);
    } else {
      debugPrint('🔑 [$key] $value');
    }
  }
}
