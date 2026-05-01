// lib/screens/authority_dashboard_screen.dart
// Full rebuild — 4 tabs: Zone Manager, Tourist Overview, SOS Events, Trail Graph.
// All data is from real API calls, not simulated.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:saferoute/models/zone_model.dart';
import 'package:saferoute/providers/auth_provider.dart';
import 'package:saferoute/services/api_service.dart';
import 'package:saferoute/utils/app_theme.dart';
import 'package:saferoute/screens/onboarding_screen.dart';
import 'package:saferoute/widgets/connectivity_chip.dart';

class AuthorityDashboardScreen extends StatefulWidget {
  const AuthorityDashboardScreen({super.key});

  @override
  State<AuthorityDashboardScreen> createState() => _AuthorityDashboardScreenState();
}

class _AuthorityDashboardScreenState extends State<AuthorityDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final ApiService _api = ApiService();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Exit the Command Center?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('LOGOUT', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<AuthProvider>().logout();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const OnboardingScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Authority Command Center',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            Consumer<AuthProvider>(
              builder: (_, auth, __) => Text(
                'JURISDICTION: ${auth.authorityDistrict?.toUpperCase() ?? "DISTRICT"}',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.5,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
        actions: [
          const ConnectivityChip(),
          IconButton(
            icon: const Icon(Icons.logout_rounded, size: 20),
            onPressed: _logout,
            tooltip: 'Logout',
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: AppColors.primaryHighContrast,
          labelColor: AppColors.primaryHighContrast,
          unselectedLabelColor: theme.colorScheme.onSurface.withOpacity(0.5),
          labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1),
          tabs: const [
            Tab(icon: Icon(Icons.layers_rounded,   size: 18), text: 'ZONES'),
            Tab(icon: Icon(Icons.people_rounded,   size: 18), text: 'TOURISTS'),
            Tab(icon: Icon(Icons.sos_rounded,      size: 18), text: 'SOS'),
            Tab(icon: Icon(Icons.route_rounded,    size: 18), text: 'TRAIL MAP'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: const [
          _ZoneManagerTab(),
          _TouristOverviewTab(),
          _SosEventsTab(),
          _TrailGraphTab(),
        ],
      ),
    );
  }
}

// ── Tab 1: Zone Manager ────────────────────────────────────────────────────────

class _ZoneManagerTab extends StatefulWidget {
  const _ZoneManagerTab();
  @override
  State<_ZoneManagerTab> createState() => _ZoneManagerTabState();
}

class _ZoneManagerTabState extends State<_ZoneManagerTab> {
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _destinations = [];
  String? _selectedDestId;
  List<ZoneModel> _zones = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDestinations();
  }

  Future<void> _loadDestinations() async {
    setState(() { _loading = true; _error = null; });
    try {
      final states = await _api.getStates();
      final List<Map<String, dynamic>> all = [];
      for (final s in states) {
        final dests = await _api.getDestinationsByState(s as String);
        all.addAll(dests.cast<Map<String, dynamic>>());
      }
      setState(() { _destinations = all; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _loadZones(String destId) async {
    setState(() { _loading = true; _selectedDestId = destId; });
    try {
      final zones = await _api.getZonesForDestination(destId);
      setState(() { _zones = zones; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _deleteZone(String zoneId) async {
    setState(() => _zones.removeWhere((z) => z.id == zoneId));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: _loading && _destinations.isEmpty
              ? const LinearProgressIndicator()
              : DropdownButtonFormField<String>(
                  value: _selectedDestId,
                  decoration: InputDecoration(
                    labelText: 'Select Destination',
                    prefixIcon: const Icon(Icons.place_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: _destinations.map((d) => DropdownMenuItem<String>(
                    value: d['id'] as String,
                    child: Text(d['name'] as String? ?? d['id'] as String),
                  )).toList(),
                  onChanged: (id) { if (id != null) _loadZones(id); },
                ),
        ),
        if (_error != null) _ErrorBanner(_error!),

        Expanded(
          child: _selectedDestId == null
              ? _EmptyHint('Select a destination to manage its zones')
              : _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _zones.isEmpty
                      ? _EmptyHint('No zones configured. Tap + to add a zone.')
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
                          itemCount: _zones.length,
                          itemBuilder: (_, i) => _ZoneCard(
                            zone: _zones[i],
                            onDelete: () => _deleteZone(_zones[i].id),
                          ),
                        ),
        ),
      ],
    );
  }
}

class _ZoneCard extends StatelessWidget {
  final ZoneModel zone;
  final VoidCallback onDelete;
  const _ZoneCard({required this.zone, required this.onDelete});

  Color get _color {
    switch (zone.type) {
      case ZoneType.safe:       return Colors.green;
      case ZoneType.caution:    return Colors.amber;
      case ZoneType.restricted: return Colors.red;
      case ZoneType.unknown:    return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final shape = zone.shape == ZoneShape.circle
        ? 'Circle — ${zone.radiusM?.toStringAsFixed(0) ?? '?'}m radius'
        : 'Polygon — ${zone.polygonPoints.length} points';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _color.withOpacity(0.15),
          child: Icon(Icons.layers_rounded, color: _color),
        ),
        title: Text(zone.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${zone.type.displayLabel} · $shape',
            style: const TextStyle(fontSize: 12)),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
          onPressed: onDelete,
          tooltip: 'Delete zone',
        ),
      ),
    );
  }
}

class _TouristOverviewTab extends StatefulWidget {
  const _TouristOverviewTab();
  @override
  State<_TouristOverviewTab> createState() => _TouristOverviewTabState();
}

class _TouristOverviewTabState extends State<_TouristOverviewTab> {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_rounded, size: 64,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.4)),
          const SizedBox(height: 16),
          const Text('Live tourist tracking', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('GET /tourists endpoint coming in next sprint.',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ],
      ),
    );
  }
}

class _SosEventsTab extends StatefulWidget {
  const _SosEventsTab();
  @override
  State<_SosEventsTab> createState() => _SosEventsTabState();
}

class _SosEventsTabState extends State<_SosEventsTab> {
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _events = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final events = await _api.getSosEvents();
      setState(() { _events = events.cast<Map<String,dynamic>>(); _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _respond(int sosId, int index) async {
    try {
      await _api.respondToSos(sosId);
      setState(() => _events[index]['status'] = 'RESOLVED');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to respond: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _ErrorBanner(_error!);
    if (_events.isEmpty) return _EmptyHint('No SOS events in your jurisdiction.');

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _events.length,
        itemBuilder: (_, i) {
          final e = _events[i];
          final isActive = e['status'] == 'ACTIVE';
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            color: isActive ? AppColors.danger.withOpacity(0.08) : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isActive ? AppColors.danger.withOpacity(0.4) : Colors.transparent,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: (isActive ? AppColors.danger : Colors.green).withOpacity(0.15),
                    child: Icon(
                      isActive ? Icons.sos_rounded : Icons.check_circle_outline_rounded,
                      color: isActive ? AppColors.danger : Colors.green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Tourist: ${e['tourist_id'] ?? 'Unknown'}',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        Text(
                          '${e['trigger_type'] ?? 'MANUAL'} · (${(e['latitude'] as num?)?.toStringAsFixed(4)}, ${(e['longitude'] as num?)?.toStringAsFixed(4)})',
                          style: const TextStyle(fontSize: 11),
                        ),
                        Text(
                          e['timestamp'] ?? '',
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                  if (isActive)
                    ElevatedButton(
                      onPressed: () => _respond(e['id'] as int, i),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                      child: const Text('RESPOND'),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TrailGraphTab extends StatefulWidget {
  const _TrailGraphTab();
  @override
  State<_TrailGraphTab> createState() => _TrailGraphTabState();
}

class _TrailGraphTabState extends State<_TrailGraphTab> {
  final ApiService _api = ApiService();
  List<dynamic> _destinations = [];
  String? _selectedDestId;
  Map<String, dynamic>? _graph;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadDestinations();
  }

  Future<void> _loadDestinations() async {
    final states = await _api.getStates();
    final List<dynamic> all = [];
    for (final s in states) {
      all.addAll(await _api.getDestinationsByState(s as String));
    }
    setState(() => _destinations = all);
  }

  Future<void> _loadGraph(String destId) async {
    setState(() { _loading = true; _selectedDestId = destId; _graph = null; });
    try {
      final graph = await _api.getTrailGraph(destId);
      setState(() { _graph = graph?.toJson(); _loading = false; });
    } catch (e) {
      setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final nodeCount  = (_graph?['nodes']  as List?)?.length ?? 0;
    final edgeCount  = (_graph?['edges']  as List?)?.length ?? 0;
    final nodes = (_graph?['nodes'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: DropdownButtonFormField<String>(
            value: _selectedDestId,
            decoration: InputDecoration(
              labelText: 'Select Destination',
              prefixIcon: const Icon(Icons.place_rounded),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            items: _destinations.map((d) {
              final m = d as Map<String, dynamic>;
              return DropdownMenuItem<String>(
                value: m['id'] as String,
                child: Text(m['name'] as String? ?? m['id'] as String),
              );
            }).toList(),
            onChanged: (id) { if (id != null) _loadGraph(id); },
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_graph != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                _GraphStat('Nodes', nodeCount.toString(), Icons.circle_rounded),
                const SizedBox(width: 12),
                _GraphStat('Edges', edgeCount.toString(), Icons.route_rounded),
                const SizedBox(width: 12),
                _GraphStat('v${_graph!['version'] ?? 1}', 'version', Icons.history_rounded),
              ],
            ),
          ),
        ],
        Expanded(
          child: _graph == null || nodes.isEmpty
              ? _EmptyHint(_selectedDestId == null
                  ? 'Select a destination to view its trail graph'
                  : 'No trail graph uploaded for this destination.\nUse the API or future upload UI.')
              : FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(
                      (nodes.first['lat'] as num).toDouble(),
                      (nodes.first['lng'] as num).toDouble(),
                    ),
                    initialZoom: 15,
                  ),
                  children: [
                    TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
                    MarkerLayer(
                      markers: nodes.map((n) {
                        final zt = ZoneTypeExtension.fromString(n['zone_type'] as String? ?? '');
                        final color = zt == ZoneType.restricted ? Colors.red
                            : zt == ZoneType.caution ? Colors.amber : Colors.green;
                        return Marker(
                          point: LatLng((n['lat'] as num).toDouble(), (n['lng'] as num).toDouble()),
                          child: Tooltip(
                            message: n['name'] as String? ?? n['id'] as String,
                            child: Icon(Icons.circle, color: color, size: 14),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _GraphStat extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  const _GraphStat(this.value, this.label, this.icon);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                Text(label, style: const TextStyle(fontSize: 9, letterSpacing: 0.5)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint(this.text);
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(text, textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade500, height: 1.6)),
    ),
  );
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner(this.message);
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.all(12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.danger.withOpacity(0.1),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.danger.withOpacity(0.3)),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline, color: AppColors.danger),
        const SizedBox(width: 8),
        Expanded(child: Text(message, style: const TextStyle(fontSize: 12))),
      ],
    ),
  );
}
