// lib/main.dart
// Default entry point. Debug keeps local dev defaults; release uses the
// deployed staging backend so `flutter run --release` cannot boot with HTTP.
// For dev on physical device, pass your machine LAN IP with:
//   --dart-define=SAFEROUTE_API_BASE_URL=http://<LAN_IP>:8000
//   --dart-define=SAFEROUTE_WS_URL=ws://<LAN_IP>:8000

import 'package:flutter/foundation.dart';
import 'package:saferoute/bootstrap.dart';
import 'package:saferoute/core/config/env_config.dart';

const String _devApiBaseUrl = 'http://10.43.205.74:8000';
const String _devWebSocketUrl = 'ws://10.43.205.74:8000';
const String _releaseApiBaseUrl = 'https://saferoute-backend-5ebu.onrender.com';
const String _releaseWebSocketUrl = 'wss://saferoute-backend-5ebu.onrender.com';

const String _apiBaseUrl = String.fromEnvironment(
  'SAFEROUTE_API_BASE_URL',
  defaultValue: kReleaseMode ? _releaseApiBaseUrl : _devApiBaseUrl,
);

const String _webSocketUrl = String.fromEnvironment(
  'SAFEROUTE_WS_URL',
  defaultValue: kReleaseMode ? _releaseWebSocketUrl : _devWebSocketUrl,
);

void main() {
  EnvConfig.init(
    env: kReleaseMode ? Environment.staging : Environment.dev,
    // Defaults can be overridden with --dart-define for device testing.
    apiBaseUrl: _apiBaseUrl,
    webSocketUrl: _webSocketUrl,
  );

  bootstrap();
}
