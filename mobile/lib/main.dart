// lib/main.dart
// Default entry point — forwards to dev configuration.
// For production, run: flutter run -t lib/main_prod.dart
// For dev emulator, run: flutter run -t lib/main_dev.dart
// For dev on physical device, pass your machine LAN IP with:
//   --dart-define=SAFEROUTE_API_BASE_URL=http://<LAN_IP>:8000
//   --dart-define=SAFEROUTE_WS_URL=ws://<LAN_IP>:8000

import 'package:saferoute/bootstrap.dart';
import 'package:saferoute/core/config/env_config.dart';

const String _apiBaseUrl = String.fromEnvironment(
  'SAFEROUTE_API_BASE_URL',
  defaultValue: 'http://10.198.71.74:8000',
);

const String _webSocketUrl = String.fromEnvironment(
  'SAFEROUTE_WS_URL',
  defaultValue: 'ws://10.198.71.74:8000',
);

void main() {
  EnvConfig.init(
    env: Environment.dev,
    // Defaults can be overridden with --dart-define for device testing.
    apiBaseUrl: _apiBaseUrl,
    webSocketUrl: _webSocketUrl,
  );

  bootstrap();
}
