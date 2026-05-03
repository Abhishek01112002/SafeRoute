enum Environment { dev, staging, prod }

class EnvConfig {
  static late final Environment environment;
  static late final String apiBaseUrl;
  static late final String webSocketUrl;

  static void init({
    required Environment env,
    required String apiBaseUrl,
    required String webSocketUrl,
  }) {
    environment = env;
    EnvConfig.apiBaseUrl = apiBaseUrl;
    EnvConfig.webSocketUrl = webSocketUrl;
  }

  static bool get isDev => environment == Environment.dev;
  static bool get isProd => environment == Environment.prod;
}
