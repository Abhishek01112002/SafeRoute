import 'package:flutter/foundation.dart';

enum AnalyticsEvent {
  onboardingSkip,
  onboardingLoginSuccess,
  onboardingLoginFailure,
  onboardingRegisterSuccess,
  permissionDenied,
  permissionGranted,
  sosTriggered,
  meshPacketRelayed,
}

class AnalyticsService {
  static final AnalyticsService _instance = AnalyticsService._internal();
  factory AnalyticsService() => _instance;
  AnalyticsService._internal();

  void logEvent(AnalyticsEvent event, {Map<String, dynamic>? properties}) {
    if (kDebugMode) {
      debugPrint('[ANALYTICS] Event: ${event.name} | Props: $properties');
    }

    // Production analytics collector integration belongs here.
  }

  void logUserConversion(String from, String to) {
    if (kDebugMode) {
      debugPrint('[CONVERSION] User upgraded from $from to $to');
    }
  }
}
