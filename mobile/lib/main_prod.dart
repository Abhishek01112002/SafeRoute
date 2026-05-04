import 'package:saferoute/bootstrap.dart';
import 'package:saferoute/core/config/env_config.dart';

const String _apiBaseUrl = String.fromEnvironment(
  'SAFEROUTE_API_BASE_URL',
  defaultValue: 'https://saferoute-api-71ez.onrender.com',
);

const String _webSocketUrl = String.fromEnvironment(
  'SAFEROUTE_WS_URL',
  defaultValue: 'wss://saferoute-api-71ez.onrender.com',
);

void main() {
  EnvConfig.init(
    env: Environment.prod,
    apiBaseUrl: _apiBaseUrl,
    webSocketUrl: _webSocketUrl,
  );

  bootstrap();
}
