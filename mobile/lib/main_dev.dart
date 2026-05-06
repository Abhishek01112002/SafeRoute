import 'package:saferoute/bootstrap.dart';
import 'package:saferoute/core/config/env_config.dart';

const String _apiBaseUrl = String.fromEnvironment(
  'SAFEROUTE_API_BASE_URL',
  defaultValue: 'http://10.43.205.74:8000',
);

const String _webSocketUrl = String.fromEnvironment(
  'SAFEROUTE_WS_URL',
  defaultValue: 'ws://10.43.205.74:8000',
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
