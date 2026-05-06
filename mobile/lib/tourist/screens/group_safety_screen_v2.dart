// lib/screens/group_safety_screen_v2.dart - Group Safety Team Radar
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:saferoute/core/service_locator.dart';
import 'package:saferoute/services/api_service.dart';
import 'package:saferoute/tourist/models/room_member_model.dart';
import 'package:saferoute/tourist/providers/location_provider.dart';
import 'package:saferoute/tourist/providers/room_provider.dart';
import 'package:saferoute/tourist/providers/tourist_provider.dart';
import 'package:saferoute/utils/app_theme.dart';
import 'package:saferoute/widgets/premium_widgets.dart';
import 'package:saferoute/widgets/sync_status_chip.dart';

class GroupSafetyScreenV2 extends StatefulWidget {
  const GroupSafetyScreenV2({super.key});

  @override
  State<GroupSafetyScreenV2> createState() => _GroupSafetyScreenV2State();
}

class _GroupSafetyScreenV2State extends State<GroupSafetyScreenV2> {
  bool _isSendingSos = false;

  @override
  Widget build(BuildContext context) {
    final roomProvider = context.watch<RoomProvider>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const AuroraBackground(),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(context, roomProvider, theme, isDark),
                Expanded(
                  child: roomProvider.isInRoom
                      ? _buildCommandCentre(
                          context, roomProvider, theme, isDark)
                      : _buildEmpty(context, roomProvider, theme, isDark),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    RoomProvider room,
    ThemeData theme,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room.isInRoom ? room.groupName.toUpperCase() : 'GROUP SAFETY',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Team Radar',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Refresh group',
            onPressed: room.isLoading
                ? null
                : () => unawaited(room.refreshActiveGroup()),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 10),
          const SizedBox(width: 118, child: SyncStatusChip(compact: true)),
        ],
      ),
    );
  }

  Widget _buildEmpty(
    BuildContext context,
    RoomProvider room,
    ThemeData theme,
    bool isDark,
  ) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.radar_rounded,
              size: 78,
              color: isDark ? Colors.white24 : Colors.black26,
            ),
            const SizedBox(height: 24),
            const Text(
              'NO ACTIVE TEAM',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1),
            ),
            const SizedBox(height: 8),
            Text(
              'Create or join a temporary safety group for this trip.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.black54,
                fontSize: 13,
              ),
            ),
            if (room.error != null) ...[
              const SizedBox(height: 18),
              _buildAlertStrip(room.error!, AppColors.warning, isDark),
            ],
            const SizedBox(height: 32),
            EliteButton(
              onPressed:
                  room.isLoading ? null : () => _showJoinRoomDialog(context),
              icon: Icons.qr_code_scanner_rounded,
              child: Text(room.isLoading ? 'SYNCING' : 'JOIN BY CODE'),
            ),
            const SizedBox(height: 12),
            EliteButton(
              onPressed:
                  room.isLoading ? null : () => _showCreateRoomDialog(context),
              isPrimary: false,
              icon: Icons.group_add_rounded,
              child: const Text('CREATE TEAM'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommandCentre(
    BuildContext context,
    RoomProvider room,
    ThemeData theme,
    bool isDark,
  ) {
    final maxDistanceKm = _maxSeparationKm(room);
    final state = _opsState(room, maxDistanceKm);

    return RefreshIndicator(
      onRefresh: room.refreshActiveGroup,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
        children: [
          if (room.error != null) ...[
            _buildAlertStrip(room.error!, AppColors.warning, isDark),
            const SizedBox(height: 14),
          ],
          _buildStatusPanel(room, state, maxDistanceKm, isDark),
          const SizedBox(height: 14),
          _buildInvitePanel(room, isDark),
          const SizedBox(height: 14),
          _buildSharingControl(room, isDark),
          const SizedBox(height: 14),
          _buildSosBanner(context, room, isDark),
          const SizedBox(height: 14),
          _buildRadarPanel(room, isDark),
          const SizedBox(height: 18),
          _buildMemberSection(room, isDark),
          const SizedBox(height: 18),
          EliteButton(
            onPressed: room.canMutateMembership ? room.leaveRoom : null,
            isPrimary: false,
            color: AppColors.danger.withValues(alpha: 0.12),
            icon: Icons.logout_rounded,
            child: const Text(
              'LEAVE TEAM',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPanel(
    RoomProvider room,
    _OpsState state,
    double? maxDistanceKm,
    bool isDark,
  ) {
    return EliteSurface(
      padding: const EdgeInsets.all(16),
      borderRadius: 18,
      borderColor: state.color,
      borderOpacity: 0.35,
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: state.color.withValues(alpha: 0.16),
              border: Border.all(color: state.color.withValues(alpha: 0.55)),
            ),
            child: Icon(state.icon, color: state.color, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  state.subtitle,
                  style: TextStyle(
                    color: isDark ? Colors.white60 : Colors.black54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _metricText('${room.members.length}', 'members', isDark),
              const SizedBox(height: 6),
              _metricText(
                maxDistanceKm == null
                    ? '--'
                    : '${(maxDistanceKm * 1000).round()}m',
                'spread',
                isDark,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInvitePanel(RoomProvider room, bool isDark) {
    final code = room.inviteCode ?? room.roomId ?? '';
    return EliteSurface(
      padding: const EdgeInsets.all(16),
      borderRadius: 18,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: QrImageView(
              data: code,
              version: QrVersions.auto,
              size: 82,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'INVITE CODE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  code,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  room.isOfflineSnapshot
                      ? 'Offline snapshot'
                      : 'Expires after 24 hours',
                  style: TextStyle(
                    color: room.isOfflineSnapshot
                        ? AppColors.warning
                        : (isDark ? Colors.white54 : Colors.black54),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSharingControl(RoomProvider room, bool isDark) {
    return EliteSurface(
      padding: const EdgeInsets.all(16),
      borderRadius: 18,
      child: Row(
        children: [
          Icon(
            room.isSharingLocation
                ? Icons.my_location_rounded
                : Icons.location_disabled_rounded,
            color:
                room.isSharingLocation ? AppColors.success : AppColors.warning,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Location Sharing',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  room.isOfflineSnapshot
                      ? 'Reconnect before changing safety state'
                      : (room.isSharingLocation
                          ? 'Session sharing is live'
                          : 'Paused for this group'),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: room.isSharingLocation,
            activeThumbColor: AppColors.success,
            onChanged: room.isOfflineSnapshot ? null : room.setSharingLocation,
          ),
        ],
      ),
    );
  }

  Widget _buildSosBanner(BuildContext context, RoomProvider room, bool isDark) {
    return EliteSurface(
      padding: const EdgeInsets.all(16),
      borderRadius: 18,
      color: AppColors.danger.withValues(alpha: isDark ? 0.18 : 0.08),
      borderColor: AppColors.danger,
      borderOpacity: 0.3,
      child: Row(
        children: [
          const Icon(Icons.emergency_share_rounded, color: AppColors.danger),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Group SOS',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  'Sends your SOS with this group context.',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              foregroundColor: AppColors.danger,
              backgroundColor: AppColors.danger.withValues(alpha: 0.12),
            ),
            onPressed: _isSendingSos || room.groupId == null
                ? null
                : () => unawaited(_triggerGroupSos(context, room)),
            icon: _isSendingSos
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sos_rounded),
            label: const Text('SOS'),
          ),
        ],
      ),
    );
  }

  Widget _buildRadarPanel(RoomProvider room, bool isDark) {
    return EliteSurface(
      padding: const EdgeInsets.all(16),
      borderRadius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.radar_rounded,
                  size: 19, color: AppColors.accent),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Radar Picture',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                room.isSocketConnected ? 'LIVE' : 'RECONNECTING',
                style: TextStyle(
                  color: room.isSocketConnected
                      ? AppColors.success
                      : AppColors.warning,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 250,
            child: CustomPaint(
              painter: _TeamRadarPainter(
                members: room.members,
                currentUserId: room.currentMember?.userId,
                isDark: isDark,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _legendDot(AppColors.success, 'live'),
              const SizedBox(width: 12),
              _legendDot(AppColors.warning, 'stale'),
              const SizedBox(width: 12),
              _legendDot(AppColors.info, 'mesh'),
              const SizedBox(width: 12),
              _legendDot(Colors.grey, 'paused'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMemberSection(RoomProvider room, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TEAM MEMBERS',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
            color: isDark ? Colors.white60 : Colors.black54,
          ),
        ),
        const SizedBox(height: 12),
        ...room.members.map((member) {
          final distanceKm = room.currentMember?.distanceTo(member);
          return _memberTile(member, distanceKm, isDark);
        }),
      ],
    );
  }

  Widget _memberTile(RoomMember member, double? distanceKm, bool isDark) {
    final color = _memberColor(member);
    final age = _formatAge(member.signalAge);
    final initial = member.displayName.trim().isEmpty
        ? '?'
        : member.displayName.trim()[0].toUpperCase();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: EliteSurface(
        padding: const EdgeInsets.all(13),
        borderRadius: 16,
        borderColor: color,
        borderOpacity: 0.18,
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: color.withValues(alpha: 0.16),
              child: Text(
                initial,
                style: TextStyle(color: color, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${member.statusLabel} · ${member.zoneStatus} · $age',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              distanceKm == null || distanceKm == 0
                  ? '--'
                  : distanceKm < 1
                      ? '${(distanceKm * 1000).round()}m'
                      : '${distanceKm.toStringAsFixed(1)}km',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertStrip(String text, Color color, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricText(String value, String label, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isDark ? Colors.white54 : Colors.black54,
          ),
        ),
      ],
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }

  Future<void> _triggerGroupSos(BuildContext context, RoomProvider room) async {
    final pos = context.read<LocationProvider>().currentPosition;
    final tourist = context.read<TouristProvider>().tourist;
    if (pos == null || tourist == null || room.groupId == null) {
      _snack(context, 'GPS or tourist identity is not ready yet.');
      return;
    }

    setState(() => _isSendingSos = true);
    try {
      final result = await locator<ApiService>().triggerSosAlert(
        pos.latitude,
        pos.longitude,
        'MANUAL',
        touristId: tourist.touristId,
        groupId: room.groupId,
      );
      if (!context.mounted) return;
      _snack(
        context,
        result.accepted
            ? 'Group SOS sent to command centre.'
            : 'SOS was not accepted.',
      );
    } finally {
      if (mounted) {
        setState(() => _isSendingSos = false);
      }
    }
  }

  void _showJoinRoomDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Join Team'),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Invite code'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () async {
              final inviteCode = controller.text.trim();
              if (inviteCode.isEmpty) return;
              final tourist = context.read<TouristProvider>().tourist;
              if (tourist == null) return;
              final consent = await _showLocationSharingConsent(context);
              if (consent != true || !context.mounted) return;
              Navigator.pop(dialogContext);
              final room = context.read<RoomProvider>();
              room.setSharingLocation(true);
              unawaited(room.joinRoom(
                roomId: inviteCode,
                userId: tourist.touristId,
                name: tourist.fullName,
              ));
            },
            child: const Text('JOIN'),
          ),
        ],
      ),
    );
  }

  void _showCreateRoomDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create Team'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Team name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () async {
              final tourist = context.read<TouristProvider>().tourist;
              if (tourist == null) return;
              final consent = await _showLocationSharingConsent(context);
              if (consent != true || !context.mounted) return;
              Navigator.pop(dialogContext);
              final room = context.read<RoomProvider>();
              room.setSharingLocation(true);
              unawaited(room.createAndJoinRoom(
                userId: tourist.touristId,
                name: tourist.fullName,
                groupName: controller.text,
              ));
            },
            child: const Text('CREATE'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showLocationSharingConsent(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Location Sharing'),
        content: const Text(
          'Exact location is shared only for this active safety group and can be paused anytime.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('AGREE'),
          ),
        ],
      ),
    );
  }

  _OpsState _opsState(RoomProvider room, double? maxDistanceKm) {
    if (room.isOfflineSnapshot) {
      return const _OpsState(
        title: 'Offline Snapshot',
        subtitle: 'Cached state is visible. Membership actions are locked.',
        color: AppColors.warning,
        icon: Icons.cloud_off_rounded,
      );
    }
    if (room.members.any((m) => m.isPaused)) {
      return const _OpsState(
        title: 'Sharing Paused',
        subtitle: 'One or more members paused live sharing.',
        color: AppColors.warning,
        icon: Icons.location_disabled_rounded,
      );
    }
    if (room.staleMemberCount > 0) {
      return const _OpsState(
        title: 'Signal Stale',
        subtitle: 'Refresh or wait for the next heartbeat.',
        color: AppColors.warning,
        icon: Icons.wifi_tethering_error_rounded,
      );
    }
    if (maxDistanceKm != null && maxDistanceKm >= 1.0) {
      return const _OpsState(
        title: 'Separation Danger',
        subtitle: 'Team spread is above 1 kilometer.',
        color: AppColors.danger,
        icon: Icons.warning_amber_rounded,
      );
    }
    if (maxDistanceKm != null && maxDistanceKm >= 0.3) {
      return const _OpsState(
        title: 'Separation Caution',
        subtitle: 'Team spread is above 300 meters.',
        color: AppColors.warning,
        icon: Icons.social_distance_rounded,
      );
    }
    return const _OpsState(
      title: 'Team Cohesive',
      subtitle: 'Live signals are within the safety envelope.',
      color: AppColors.success,
      icon: Icons.verified_user_rounded,
    );
  }

  double? _maxSeparationKm(RoomProvider room) {
    final me = room.currentMember;
    if (me == null || !me.hasLocation) return null;
    double? maxDistance;
    for (final member in room.members) {
      if (member.userId == me.userId) continue;
      final distance = me.distanceTo(member);
      if (distance == null) continue;
      maxDistance =
          maxDistance == null ? distance : math.max(maxDistance, distance);
    }
    return maxDistance;
  }

  Color _memberColor(RoomMember member) {
    if (member.isPaused) return Colors.grey;
    if (member.isMeshFallback) return AppColors.info;
    if (member.isStale) return AppColors.warning;
    if (!member.hasLocation) return Colors.grey;
    return AppColors.success;
  }

  String _formatAge(Duration? age) {
    if (age == null) return '--';
    if (age.inSeconds < 60) return '${age.inSeconds}s';
    if (age.inMinutes < 60) return '${age.inMinutes}m';
    return '${age.inHours}h';
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _OpsState {
  final String title;
  final String subtitle;
  final Color color;
  final IconData icon;

  const _OpsState({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.icon,
  });
}

class _TeamRadarPainter extends CustomPainter {
  final List<RoomMember> members;
  final String? currentUserId;
  final bool isDark;

  _TeamRadarPainter({
    required this.members,
    required this.currentUserId,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 18;
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.12);
    final sweepPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = AppColors.accent.withValues(alpha: 0.35);

    for (final fraction in const [0.33, 0.66, 1.0]) {
      canvas.drawCircle(center, radius * fraction, ringPaint);
    }
    canvas.drawLine(
      center.translate(-radius, 0),
      center.translate(radius, 0),
      ringPaint,
    );
    canvas.drawLine(
      center.translate(0, -radius),
      center.translate(0, radius),
      ringPaint,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi / 3,
      false,
      sweepPaint,
    );

    final current = _currentMember;
    _drawDot(canvas, center, 'ME', AppColors.accent, isLarge: true);
    if (current == null || !current.hasLocation) {
      _drawCenteredText(canvas, size, 'AWAITING GPS LOCK');
      return;
    }

    for (final member in members) {
      if (member.userId == current.userId || !member.hasLocation) continue;
      final distanceKm = current.distanceTo(member);
      if (distanceKm == null) continue;
      final bearing = _bearingRadians(
        current.lat!,
        current.lng!,
        member.lat!,
        member.lng!,
      );
      final clamped = math.min(distanceKm / 1.0, 1.0);
      final offset = Offset(
        math.sin(bearing) * radius * clamped,
        -math.cos(bearing) * radius * clamped,
      );
      _drawDot(
        canvas,
        center + offset,
        _initial(member.displayName),
        _memberColor(member),
      );
    }
  }

  RoomMember? get _currentMember {
    if (currentUserId == null) return null;
    final matches = members.where((m) => m.userId == currentUserId);
    return matches.isEmpty ? null : matches.first;
  }

  void _drawDot(
    Canvas canvas,
    Offset point,
    String label,
    Color color, {
    bool isLarge = false,
  }) {
    final dotPaint = Paint()..color = color.withValues(alpha: 0.22);
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color;
    final r = isLarge ? 18.0 : 14.0;
    canvas.drawCircle(point, r, dotPaint);
    canvas.drawCircle(point, r, strokePaint);
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: isLarge ? 10 : 9,
          fontWeight: FontWeight.w900,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      point - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  void _drawCenteredText(Canvas canvas, Size size, String label) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.42),
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        size.height - textPainter.height - 4,
      ),
    );
  }

  Color _memberColor(RoomMember member) {
    if (member.isPaused) return Colors.grey;
    if (member.isMeshFallback) return AppColors.info;
    if (member.isStale) return AppColors.warning;
    return AppColors.success;
  }

  String _initial(String name) =>
      name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

  double _bearingRadians(double lat1, double lon1, double lat2, double lon2) {
    final p1 = _toRad(lat1);
    final p2 = _toRad(lat2);
    final dLon = _toRad(lon2 - lon1);
    final y = math.sin(dLon) * math.cos(p2);
    final x = math.cos(p1) * math.sin(p2) -
        math.sin(p1) * math.cos(p2) * math.cos(dLon);
    return math.atan2(y, x);
  }

  double _toRad(double deg) => deg * math.pi / 180;

  @override
  bool shouldRepaint(covariant _TeamRadarPainter oldDelegate) {
    return oldDelegate.members != members ||
        oldDelegate.currentUserId != currentUserId ||
        oldDelegate.isDark != isDark;
  }
}
