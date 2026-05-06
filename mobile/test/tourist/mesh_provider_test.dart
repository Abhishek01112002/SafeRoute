import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saferoute/core/service_locator.dart';
import 'package:saferoute/services/analytics_service.dart';
import 'package:saferoute/services/mesh_service.dart';
import 'package:saferoute/tourist/models/mesh/mesh_node.dart';
import 'package:saferoute/tourist/models/mesh/mesh_packet.dart';
import 'package:saferoute/tourist/providers/mesh_provider.dart';

class MockMeshService implements MeshService {
  MockMeshService(this.result, {this.error});

  final MeshServiceStartResult result;
  final String? error;
  int initCount = 0;
  int startCount = 0;
  int stopCount = 0;
  String? initializedUserId;
  // ignore: close_sinks
  final nodesController = StreamController<List<MeshNode>>.broadcast();
  // ignore: close_sinks
  final packetsController = StreamController<MeshPacket>.broadcast();

  @override
  String? get lastError => error;

  @override
  String? get myUserId => initializedUserId;

  @override
  Stream<List<MeshNode>> get nearbyNodes => nodesController.stream;

  @override
  Stream<MeshPacket> get incomingPackets => packetsController.stream;

  @override
  Future<void> init(String userId) async {
    initCount++;
    initializedUserId = userId;
  }

  @override
  Future<MeshServiceStartResult> start() async {
    startCount++;
    return result;
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }

  @override
  Future<void> sendPacket(MeshPacket packet) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class MockAnalyticsService implements AnalyticsService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  setUp(() async {
    await locator.reset();
    locator.registerSingleton<AnalyticsService>(MockAnalyticsService());
  });

  tearDown(() async {
    await locator.reset();
  });

  Future<MeshProvider> buildProvider(MockMeshService service) async {
    locator.registerSingleton<MeshService>(service);
    final provider = MeshProvider();
    await provider.init('mesh-user');
    return provider;
  }

  test('successful manual start enters active state', () async {
    final service = MockMeshService(MeshServiceStartResult.success);
    final provider = await buildProvider(service);

    final started = await provider.startMesh();

    expect(started, isTrue);
    expect(provider.meshState, MeshRuntimeState.active);
    expect(provider.canBroadcast, isTrue);
    expect(service.startCount, 1);

    provider.dispose();
  });

  test('permission denied becomes permissionNeeded without throwing', () async {
    final service = MockMeshService(
      MeshServiceStartResult.permissionDenied,
      error: 'permission denied',
    );
    final provider = await buildProvider(service);

    final started = await provider.startMesh();

    expect(started, isFalse);
    expect(provider.meshState, MeshRuntimeState.permissionNeeded);
    expect(provider.canBroadcast, isFalse);
    expect(provider.lastError, 'permission denied');

    provider.dispose();
  });

  test('bluetooth off becomes bluetoothOff without throwing', () async {
    final service = MockMeshService(
      MeshServiceStartResult.bluetoothOff,
      error: 'bluetooth off',
    );
    final provider = await buildProvider(service);

    final started = await provider.startMesh();

    expect(started, isFalse);
    expect(provider.meshState, MeshRuntimeState.bluetoothOff);
    expect(provider.statusMessage, contains('Bluetooth is off'));

    provider.dispose();
  });

  test('unsupported device becomes unsupported without throwing', () async {
    final service = MockMeshService(
      MeshServiceStartResult.unsupported,
      error: 'unsupported',
    );
    final provider = await buildProvider(service);

    final started = await provider.startMesh();

    expect(started, isFalse);
    expect(provider.meshState, MeshRuntimeState.unsupported);
    expect(provider.statusMessage, contains('does not support'));

    provider.dispose();
  });

  test('stop returns mesh to idle and clears nodes', () async {
    final service = MockMeshService(MeshServiceStartResult.success);
    final provider = await buildProvider(service);
    await provider.startMesh();

    await provider.stopMesh();

    expect(provider.meshState, MeshRuntimeState.idle);
    expect(provider.isMeshActive, isFalse);
    expect(provider.nearbyNodes, isEmpty);
    expect(service.stopCount, 1);

    provider.dispose();
  });

  test('bootstrap and MainScreen do not auto-start mesh', () {
    final bootstrap = File('lib/bootstrap.dart').readAsStringSync();
    final mainScreen = File('lib/screens/main_screen.dart').readAsStringSync();

    expect(bootstrap, isNot(contains('startMesh()')));
    expect(mainScreen, isNot(contains('startMesh()')));
  });
}
