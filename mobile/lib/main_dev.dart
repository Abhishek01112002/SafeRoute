import 'package:saferoute/bootstrap.dart';
import 'package:saferoute/core/config/env_config.dart';

void main() {
  EnvConfig.init(
    env: Environment.dev,
    apiBaseUrl: 'http://10.198.71.74:8001', // Physical device on same WiFi
    webSocketUrl: 'ws://10.198.71.74:8001',
  );

  bootstrap();
}
