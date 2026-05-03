import 'package:saferoute/bootstrap.dart';
import 'package:saferoute/core/config/env_config.dart';

void main() {
  EnvConfig.init(
    env: Environment.prod,
    apiBaseUrl: 'https://api.saferoute.app/api',
    webSocketUrl: 'wss://api.saferoute.app',
  );

  bootstrap();
}
