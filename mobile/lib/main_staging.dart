import 'package:saferoute/bootstrap.dart';
import 'package:saferoute/core/config/env_config.dart';

const String _apiBaseUrl = String.fromEnvironment(
  'SAFEROUTE_API_BASE_URL',
  defaultValue: 'https://saferoute-backend-5ebu.onrender.com',
);

const String _webSocketUrl = String.fromEnvironment(
  'SAFEROUTE_WS_URL',
  defaultValue: 'wss://saferoute-backend-5ebu.onrender.com',
);

void main() {
  EnvConfig.init(
    env: Environment.staging,
    apiBaseUrl: _apiBaseUrl,
    webSocketUrl: _webSocketUrl,
  );

  bootstrap();
}
