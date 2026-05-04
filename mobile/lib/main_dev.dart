import 'package:saferoute/bootstrap.dart';
import 'package:saferoute/core/config/env_config.dart';

void main() {
  EnvConfig.init(
    env: Environment.dev,
    // Run `ipconfig` (Windows) or `ifconfig` (Mac/Linux) to find your machine's local IP.
    // Use port 8000 to match the local backend default (uvicorn main:app --port 8000).
    apiBaseUrl: 'http://10.198.71.74:8000',
    webSocketUrl: 'ws://10.198.71.74:8000',
  );

  bootstrap();
}
