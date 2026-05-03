// lib/core/index.dart
//
// Core Module Barrel File
// -------------------------
// Single import point for core shared infrastructure.
// Usage: import 'package:saferoute/core/index.dart';

// Config
export 'config/env_config.dart';
export 'config/feature_flags.dart';

// Errors & Result
export 'errors/app_error.dart';
export 'utils/result.dart';

// Service Locator
export 'service_locator.dart';

// Providers
export 'providers/theme_provider.dart';

// Widgets
export 'widgets/async_state_widget.dart';
export 'widgets/error_boundary.dart';

// Models
export 'models/api_responses.dart';
