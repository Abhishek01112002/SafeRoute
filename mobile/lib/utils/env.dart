// lib/utils/env.dart

class Env {
  /// Defines whether the app is running in a development/sandbox environment.
  /// Set this using --dart-define=ENV=dev
  static const bool isDev = bool.fromEnvironment('ENV') == 'dev';

  /// The base URL for the backend API.
  /// Automatically routes to a staging/local environment when in dev mode
  /// to prevent accidental corruption of production databases.
  static const String apiBaseUrl = isDev
      ? 'http://10.198.71.18:8000' // Your laptop's local IP address
      : 'https://api.saferoute.app';
}
