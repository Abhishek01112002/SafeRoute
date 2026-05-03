// lib/tourist/index.dart
//
// Tourist Module Barrel File
// ---------------------------
// Single import point for the entire tourist module.
// Usage: import 'package:saferoute/tourist/index.dart';
//
// When a file moves, update this barrel — all other imports still work.

// Screens
export 'screens/home_screen_v2.dart';
export 'screens/sos_screen_v2.dart';
export 'screens/navigation_screen_v2.dart';
export 'screens/offline_navigation_screen.dart';
export 'screens/registration_screen.dart';
export 'screens/digital_id_screen_v2.dart';
export 'screens/group_safety_screen_v2.dart';
export 'screens/tactical_ar_screen.dart';
export 'screens/mesh_status_screen.dart';

// Providers
export 'providers/tourist_provider.dart';
export 'providers/location_provider.dart';
export 'providers/mesh_provider.dart';
export 'providers/navigation_provider.dart';
export 'providers/room_provider.dart';
export 'providers/safety_system_provider.dart';

// Models
export 'models/tourist_model.dart';
export 'models/room_member_model.dart';
export 'models/trail_graph_model.dart';

// Repositories
export 'repositories/tourist_repository.dart';
export 'repositories/sos_repository.dart';
