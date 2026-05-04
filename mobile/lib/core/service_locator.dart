import 'package:get_it/get_it.dart';

// Services
import 'package:saferoute/services/analytics_service.dart';
import 'package:saferoute/services/api_service.dart';
import 'package:saferoute/services/background_service.dart';
import 'package:saferoute/services/breadcrumb_manager.dart';
import 'package:saferoute/services/database_service.dart';
import 'package:saferoute/services/database_tile_provider.dart';
import 'package:saferoute/services/fall_detection_service.dart';
import 'package:saferoute/services/geofencing_engine.dart';
import 'package:saferoute/services/identity_service.dart';
import 'package:saferoute/services/location_service.dart';
import 'package:saferoute/services/mesh_service.dart';
import 'package:saferoute/services/notification_service.dart';
import 'package:saferoute/services/pathfinding_service.dart';
import 'package:saferoute/services/permission_service.dart';
import 'package:saferoute/services/room_service.dart';
import 'package:saferoute/services/safety_engine.dart';
import 'package:saferoute/services/secure_storage_service.dart';
import 'package:saferoute/services/simulation_engine.dart';
import 'package:saferoute/services/sync_engine.dart';

import 'package:saferoute/services/telemetry_service.dart';
import 'package:saferoute/services/tile_downloader_service.dart';

// Repositories
import 'package:saferoute/tourist/repositories/tourist_repository.dart';
import 'package:saferoute/tourist/repositories/sos_repository.dart';
import 'package:saferoute/authority/repositories/authority_repository.dart';

final locator = GetIt.instance;

void setupLocator() {
  // Core Services
  locator.registerLazySingleton(() => SecureStorageService());
  locator.registerLazySingleton(() => DatabaseService());
  locator.registerLazySingleton(() => ApiService());
  locator.registerLazySingleton(() => AnalyticsService());
  
  // Feature Services
  locator.registerLazySingleton(() => BackgroundService());
  locator.registerLazySingleton(() => BreadcrumbManager());
  locator.registerLazySingleton(() => DatabaseTileProvider());
  locator.registerLazySingleton(() => FallDetectionService());
  locator.registerLazySingleton(() => GeofencingEngine());
  locator.registerLazySingleton(() => IdentityService());
  locator.registerLazySingleton(() => LocationService());
  locator.registerLazySingleton(() => MeshService());
  locator.registerLazySingleton(() => NotificationService());
  locator.registerLazySingleton(() => PathfindingService());
  locator.registerLazySingleton(() => PermissionService());
  locator.registerLazySingleton(() => RoomService());
  locator.registerLazySingleton(() => SafetyEngine());
  locator.registerLazySingleton(() => SimulationEngine());
  locator.registerLazySingleton(() => SyncEngine());

  locator.registerLazySingleton(() => TelemetryService());
  locator.registerLazySingleton(() => TileDownloaderService());

  // Repositories (Result-typed data access layer)
  locator.registerLazySingleton(() => TouristRepository());
  locator.registerLazySingleton(() => SosRepository());
  locator.registerLazySingleton(() => AuthorityRepository());
}
