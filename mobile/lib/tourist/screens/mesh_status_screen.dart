import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:saferoute/utils/app_theme.dart';
import 'package:saferoute/tourist/providers/location_provider.dart';
import 'package:saferoute/tourist/providers/tourist_provider.dart';
import 'package:saferoute/tourist/providers/mesh_provider.dart';
import 'package:saferoute/widgets/premium_widgets.dart';
import 'package:saferoute/widgets/sync_status_chip.dart';

class MeshStatusScreen extends StatefulWidget {
  const MeshStatusScreen({super.key});

  @override
  State<MeshStatusScreen> createState() => _MeshStatusScreenState();
}

class _MeshStatusScreenState extends State<MeshStatusScreen> {
  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
    final meshProvider = context.read<MeshProvider>();
    final tourist = context.read<TouristProvider>().tourist;
    if (tourist != null) {
      meshProvider.init(tourist.touristId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mesh = context.watch<MeshProvider>();
    final tourist = context.read<TouristProvider>().tourist;
    final locationProvider = context.watch<LocationProvider>();
    final selfId = 'TID-OFFLINE-${tourist?.touristId.hashCode.abs().toString().substring(0, 6) ?? "547858"}';

    return Stack(
      children: [
        SingleChildScrollView(
          padding: EdgeInsets.only(
            left: AppSpacing.l,
            right: AppSpacing.l,
            top: MediaQuery.of(context).padding.top + kToolbarHeight + AppSpacing.m,
            bottom: AppSpacing.xl
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildEliteHeader(mesh),
              const SizedBox(height: AppSpacing.xl),
              const SyncStatusChip(),
              const SizedBox(height: AppSpacing.l),

              EliteSurface(
                padding: const EdgeInsets.all(AppSpacing.l),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.bluetooth_searching_rounded, color: theme.colorScheme.primary, size: 20),
                        const SizedBox(width: AppSpacing.m),
                        Text("MESH IDENTITY", style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.38), fontWeight: FontWeight.w900, fontSize: 9, letterSpacing: 1.5)),
                        const Spacer(),
                        _statusBadge(mesh.isMeshActive ? "ACTIVE" : "INACTIVE", mesh.isMeshActive),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.m),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.m),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(AppSpacing.radiusM),
                      ),
                      child: Row(
                        children: [
                          Text("NODE ID:", style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 9, fontWeight: FontWeight.w900)),
                          const SizedBox(width: 8),
                          Text(selfId, style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.xl),

              EliteButton(
                onPressed: mesh.isMeshActive
                  ? () => mesh.sendSosRelay(
                      locationProvider.currentPosition?.latitude ?? 0.0,
                      locationProvider.currentPosition?.longitude ?? 0.0,
                    )
                  : null,
                color: AppColors.zoneRed,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.sos_rounded, size: 18),
                    SizedBox(width: AppSpacing.m),
                    Text("BROADCAST SOS VIA MESH", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1)),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.xxl),

              Text("NEARBY NODES (SIMPLE VIEW)", style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.38), fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 2)),
              const SizedBox(height: AppSpacing.m),
              _buildNearbyMembers(mesh),

              const SizedBox(height: AppSpacing.xl),

              // Advanced Toggle
              Center(
                child: TextButton.icon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    setState(() => _showAdvanced = !_showAdvanced);
                  },
                  icon: Icon(_showAdvanced ? Icons.visibility_off_rounded : Icons.insights_rounded, size: 14, color: theme.colorScheme.primary),
                  label: Text(_showAdvanced ? "HIDE DIAGNOSTICS" : "SHOW NETWORK TOPOLOGY",
                    style: TextStyle(color: theme.colorScheme.primary, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)),
                ),
              ),

              if (_showAdvanced) ...[
                const SizedBox(height: AppSpacing.xl),
                Text("NETWORK TRAFFIC (ADVANCED)", style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.38), fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 2)),
                const SizedBox(height: AppSpacing.m),
                _buildActivityList(mesh),
              ],

              const SizedBox(height: 100),
            ],
          ),
        ),
        Positioned(
          bottom: AppSpacing.xl,
          right: AppSpacing.l,
          child: FloatingActionButton.extended(
            onPressed: () {
              if (mesh.isMeshActive) {
                mesh.broadcastLocation(0.0, 0.0);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SIGNAL BROADCASTED')));
              }
            },
            backgroundColor: theme.colorScheme.primary,
            icon: Icon(Icons.waves_rounded, color: theme.colorScheme.onPrimary),
            label: Text('BEACON', style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 10)),
          ),
        )
      ],
    );
  }

  Widget _buildEliteHeader(MeshProvider mesh) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.colorScheme.primary, theme.colorScheme.primary.withValues(alpha: 0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusL),
        boxShadow: [BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.2), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.hub_rounded, color: theme.colorScheme.onPrimary, size: 32),
              const SizedBox(width: AppSpacing.m),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("HYBRID SIGNAL", style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 1)),
                  Text("BLE MESH NETWORK ACTIVE", style: TextStyle(color: theme.colorScheme.onPrimary.withValues(alpha: 0.6), fontWeight: FontWeight.bold, fontSize: 8)),
                ],
              ),
              const Spacer(),
              _actionIcon(mesh.isMeshActive ? Icons.power_settings_new_rounded : Icons.power_rounded, () {
                mesh.isMeshActive ? mesh.stopMesh() : mesh.startMesh();
              }),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _headerStat("ACTIVE PEERS", mesh.nearbyNodes.length.toString()),
              _headerStat("PROTOCOL", "B-M17"),
              _headerStat("HOPS", "MAX 7"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerStat(String label, String value) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(value, style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w900, fontSize: 16)),
        Text(label, style: TextStyle(color: theme.colorScheme.onPrimary.withValues(alpha: 0.38), fontWeight: FontWeight.w900, fontSize: 7, letterSpacing: 0.5)),
      ],
    );
  }

  Widget _statusBadge(String label, bool active) {
    final color = active ? AppColors.zoneGreen : AppColors.zoneRed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w900)),
    );
  }

  Widget _buildNearbyMembers(MeshProvider mesh) {
    final theme = Theme.of(context);
    if (mesh.nearbyNodes.isEmpty) {
      return EliteSurface(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.sensors_off_rounded, color: theme.colorScheme.onSurface.withValues(alpha: 0.1), size: 32),
              const SizedBox(height: AppSpacing.m),
              Text("SCANNING FOR SIGNALS...", style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.24), fontSize: 9, fontWeight: FontWeight.w900)),
            ],
          ),
        ),
      );
    }

    return Column(
      children: mesh.nearbyNodes.map((node) => EliteSurface(
        margin: const EdgeInsets.only(bottom: AppSpacing.s),
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Row(
          children: [
            Icon(Icons.bluetooth_searching_rounded, color: theme.colorScheme.primary, size: 16),
            const SizedBox(width: AppSpacing.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(node.name.toUpperCase(), style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w900, fontSize: 11)),
                  Text('NODE: ${node.userId}', style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.38), fontSize: 8, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Text('${node.rssi} dBm', style: const TextStyle(color: AppColors.zoneGreen, fontSize: 9, fontWeight: FontWeight.w900)),
          ],
        ),
      )).toList(),
    );
  }

  Widget _buildActivityList(MeshProvider mesh) {
    final theme = Theme.of(context);
    if (mesh.recentActivity.isEmpty) {
      return Center(child: Text('NO MESH TRAFFIC DETECTED', style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.1), fontSize: 9, fontWeight: FontWeight.w900)));
    }

    return Column(
      children: mesh.recentActivity.map((packet) {
        final timeStr = "${DateTime.fromMillisecondsSinceEpoch(packet.timestamp).hour.toString().padLeft(2, '0')}:${DateTime.fromMillisecondsSinceEpoch(packet.timestamp).minute.toString().padLeft(2, '0')}";
        final isSos = packet.type.toString().contains('SOS');

        return EliteSurface(
          margin: const EdgeInsets.only(bottom: AppSpacing.s),
          padding: const EdgeInsets.all(AppSpacing.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(isSos ? Icons.warning_amber_rounded : Icons.share_location_rounded,
                       color: isSos ? AppColors.zoneRed : theme.colorScheme.primary, size: 18),
                  const SizedBox(width: AppSpacing.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isSos ? 'EMERGENCY SOS RELAY' : 'LOCATION SYNC',
                          style: TextStyle(color: isSos ? AppColors.zoneRed : theme.colorScheme.primary, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 0.5)
                        ),
                        Text('SOURCE: ${packet.sourceId.substring(0, 8)}...', style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.38), fontSize: 8, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  Text(timeStr, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.24), fontSize: 9, fontWeight: FontWeight.w900)),
                ],
              ),
              if (packet.relayPathShortIds.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.m),
                Divider(color: theme.dividerColor),
                const SizedBox(height: AppSpacing.s),
                Text("MESH PEER ROUTE", style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.1), fontSize: 7, fontWeight: FontWeight.w900, letterSpacing: 1)),
                const SizedBox(height: AppSpacing.s),
                Wrap(
                  spacing: 4,
                  children: [
                    _hopDot("ORG"),
                    ...packet.relayPathShortIds.map((h) => _hopDot(h.toRadixString(16).toUpperCase())),
                    _hopDot("YOU", isMe: true),
                  ],
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _hopDot(String label, {bool isMe = false}) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isMe ? theme.colorScheme.primary.withValues(alpha: 0.1) : theme.colorScheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: isMe ? theme.colorScheme.primary : theme.dividerColor),
      ),
      child: Text(label, style: TextStyle(color: isMe ? theme.colorScheme.onSurface : theme.colorScheme.onSurface.withValues(alpha: 0.24), fontSize: 7, fontWeight: FontWeight.bold)),
    );
  }

  Widget _actionIcon(IconData icon, VoidCallback onTap) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.onPrimary.withValues(alpha: 0.1),
          shape: BoxShape.circle,
          border: Border.all(color: theme.colorScheme.onPrimary.withValues(alpha: 0.24))
        ),
        child: Icon(icon, color: theme.colorScheme.onPrimary, size: 20),
      ),
    );
  }
}
