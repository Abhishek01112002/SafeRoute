// lib/main.dart
// Default entry point — forwards to dev configuration.
// For production, run: flutter run -t lib/main_prod.dart
// For dev emulator, run: flutter run -t lib/main_dev.dart
// For dev on physical device, run: flutter run -t lib/main_dev.dart
//   (change apiBaseUrl in main_dev.dart to your machine's LAN IP)

import 'package:saferoute/bootstrap.dart';
import 'package:saferoute/core/config/env_config.dart';

void main() {
  EnvConfig.init(
    env: Environment.dev,
    // Android emulator: 10.0.2.2 maps to host machine localhost
    // Physical device: replace with your machine's LAN IP, e.g. 192.168.1.x:8001
    apiBaseUrl: 'http://10.0.2.2:8001',
    webSocketUrl: 'ws://10.0.2.2:8001',
  );

  bootstrap();
}
