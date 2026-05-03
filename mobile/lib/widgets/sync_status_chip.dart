import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:saferoute/mesh/providers/mesh_provider.dart';
import 'package:saferoute/providers/tourist_provider.dart';
import 'package:saferoute/utils/app_theme.dart';
import 'package:saferoute/widgets/premium_widgets.dart';

class SyncStatusChip extends StatefulWidget {
  final bool compact;

  const SyncStatusChip({super.key, this.compact = false});

  @override
  State<SyncStatusChip> createState() => _SyncStatusChipState();
}

class _SyncStatusChipState extends State<SyncStatusChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.45, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tourist = context.watch<TouristProvider>();
    final mesh = context.watch<MeshProvider>();
    final tone = _resolveTone(
      online: tourist.isOnline,
      meshActive: mesh.isMeshActive,
      nodes: mesh.nearbyNodes.length,
    );

    return Semantics(
      label: 'Sync status ${tone.label}',
      child: EliteSurface(
        padding: EdgeInsets.symmetric(
          horizontal: widget.compact ? 10 : 12,
          vertical: widget.compact ? 8 : 10,
        ),
        borderRadius: 16,
        color: Colors.white.withValues(alpha: tourist.isOnline ? 0.12 : 0.10),
        borderColor: tone.color.withValues(alpha: 0.45),
        borderOpacity: 0.45,
        child: Row(
          mainAxisSize: widget.compact ? MainAxisSize.min : MainAxisSize.max,
          children: [
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) => Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: tone.color.withValues(alpha: _pulse.value),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: tone.color.withValues(alpha: 0.55),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (widget.compact)
              _SyncLabel(label: tone.label, compact: true)
            else
              Expanded(child: _SyncLabel(label: tone.label, compact: false)),
          ],
        ),
      ),
    );
  }

  _SyncTone _resolveTone({
    required bool online,
    required bool meshActive,
    required int nodes,
  }) {
    if (online) return const _SyncTone('ONLINE SYNC', AppColors.success);
    if (meshActive && nodes > 0) {
      return _SyncTone('OFFLINE / BLE MESH $nodes', AppColors.info);
    }
    if (meshActive && nodes == 0) {
      return const _SyncTone('OFFLINE / MESH SCANNING', AppColors.warning);
    }
    return const _SyncTone('OFFLINE / LOCAL QUEUE', AppColors.warning);
  }
}

class _SyncLabel extends StatelessWidget {
  final String label;
  final bool compact;

  const _SyncLabel({required this.label, required this.compact});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w800,
        fontSize: compact ? 9 : 10,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _SyncTone {
  final String label;
  final Color color;

  const _SyncTone(this.label, this.color);
}
