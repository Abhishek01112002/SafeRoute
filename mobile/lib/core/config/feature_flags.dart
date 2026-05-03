// lib/core/config/feature_flags.dart
//
// SafeRoute Feature Flags
// ------------------------
// Controls which features are enabled at runtime.
// Backed by a local static config for now, ready to connect to
// Firebase Remote Config or a backend /config endpoint.
//
// Usage:
//   if (FeatureFlags.isArModeEnabled) { ... }
//   if (FeatureFlags.isMeshV2Enabled) { ... }
//
// To toggle a flag for a release:
//   1. Development: change the static default below
//   2. Production: set via Firebase Remote Config (no APK release needed)
//   3. Per-environment: FeatureFlags.override() is called from bootstrap.dart

import 'package:flutter/foundation.dart';

class FeatureFlags {
  FeatureFlags._(); // static-only class

  // ---------------------------------------------------------------------------
  // Internal override map (for testing and dev overrides)
  // ---------------------------------------------------------------------------
  static final Map<String, bool> _overrides = {};

  /// Override flags at runtime (call from tests or bootstrap).
  static void override(Map<String, bool> flags) {
    _overrides.addAll(flags);
    debugPrint('[FeatureFlags] Overrides set: $flags');
  }

  /// Reset all overrides (useful in tests).
  static void resetOverrides() => _overrides.clear();

  // ---------------------------------------------------------------------------
  // Helper
  // ---------------------------------------------------------------------------
  static bool _get(String key, bool defaultValue) {
    return _overrides.containsKey(key) ? _overrides[key]! : defaultValue;
  }

  // ---------------------------------------------------------------------------
  // 📱 Mobile Features
  // ---------------------------------------------------------------------------

  /// Tactical AR overlay screen.
  /// Disable if ARCore issues arise on specific devices.
  static bool get isArModeEnabled => _get('ar_mode_enabled', true);

  /// BLE Mesh v2 protocol (upgraded packet format).
  /// Disable to fall back to v1 if compatibility issues arise.
  static bool get isMeshV2Enabled => _get('mesh_v2_enabled', false);

  /// Group Safety room feature.
  /// Enable when backend room sync is stable.
  static bool get isGroupSafetyEnabled => _get('group_safety_enabled', true);

  /// AI Risk Engine for offline fall detection.
  /// Disable to save battery if user opts out.
  static bool get isAiRiskEngineEnabled => _get('ai_risk_engine_enabled', true);

  /// Breadcrumb trail recording.
  static bool get isBreadcrumbEnabled => _get('breadcrumb_enabled', true);

  /// Offline tile download feature.
  static bool get isOfflineMapsEnabled => _get('offline_maps_enabled', true);

  /// Biometric authentication (Face ID / fingerprint) for Authority login.
  static bool get isBiometricAuthEnabled => _get('biometric_auth_enabled', false);

  /// New async state widget (replaces custom loading spinners).
  /// Gradual rollout flag.
  static bool get isAsyncStateWidgetEnabled => _get('async_state_widget_enabled', true);

  // ---------------------------------------------------------------------------
  // 🐍 Backend-controlled flags (read from /config endpoint in future)
  // ---------------------------------------------------------------------------

  /// Push notifications for SOS alerts via FCM.
  static bool get isPushNotificationsEnabled =>
      _get('push_notifications_enabled', false);

  /// Enhanced Correlation ID tracing in API calls.
  static bool get isCorrelationTracingEnabled =>
      _get('correlation_tracing_enabled', true);

  // ---------------------------------------------------------------------------
  // Debug helpers
  // ---------------------------------------------------------------------------

  /// Dump all flag states to console (dev builds only).
  static void debugPrintAll() {
    if (!kDebugMode) return;
    debugPrint('─── FeatureFlags ───────────────────────');
    debugPrint('  ar_mode:             $isArModeEnabled');
    debugPrint('  mesh_v2:             $isMeshV2Enabled');
    debugPrint('  group_safety:        $isGroupSafetyEnabled');
    debugPrint('  ai_risk_engine:      $isAiRiskEngineEnabled');
    debugPrint('  breadcrumb:          $isBreadcrumbEnabled');
    debugPrint('  offline_maps:        $isOfflineMapsEnabled');
    debugPrint('  biometric_auth:      $isBiometricAuthEnabled');
    debugPrint('  push_notifications:  $isPushNotificationsEnabled');
    debugPrint('  correlation_tracing: $isCorrelationTracingEnabled');
    debugPrint('────────────────────────────────────────');
  }
}
