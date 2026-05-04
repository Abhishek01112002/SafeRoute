import 'package:saferoute/bootstrap.dart';
import 'package:saferoute/core/config/env_config.dart';

void main() {
  EnvConfig.init(
    env: Environment.prod,
    apiBaseUrl: 'https://saferoute-api-71ez.onrender.com',
    webSocketUrl: 'wss://saferoute-api-71ez.onrender.com',
  );

  bootstrap();
}
