// lib/screens/group_safety_screen_v2.dart - Group Safety Screen (Premium)
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:saferoute/utils/app_theme.dart';
import 'package:saferoute/providers/room_provider.dart';
import 'package:saferoute/providers/tourist_provider.dart';
import 'package:saferoute/widgets/premium_widgets.dart';

class GroupSafetyScreenV2 extends StatelessWidget {
  const GroupSafetyScreenV2({super.key});

  @override
  Widget build(BuildContext context) {
    final roomProvider = context.watch<RoomProvider>();
    final members = roomProvider.members;
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
                _buildHeader(theme, isDark),
                Expanded(
                  child: members.isEmpty
                      ? _buildEmpty(context, theme, isDark)
                      : _buildMemberList(context, roomProvider, theme, isDark),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'GROUP NETWORK',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: AppColors.primary,
                ),
              ),
              Text(
                'Live Team Radar',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          EliteSurface(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            borderRadius: 20,
            color: AppColors.success.withOpacity(0.1),
            borderColor: AppColors.success,
            child: const Row(
              children: [
                Icon(Icons.wifi_rounded, size: 12, color: AppColors.success),
                SizedBox(width: 4),
                Text(
                  'ACTIVE',
                  style: TextStyle(
                      color: AppColors.success,
                      fontSize: 10,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, ThemeData theme, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline_rounded,
                size: 80, color: isDark ? Colors.white10 : Colors.black12),
            const SizedBox(height: 24),
            const Text(
              'NO ACTIVE PATROL',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1),
            ),
            const SizedBox(height: 8),
            Text(
              'Join a group to track your team members in real-time even offline.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: isDark ? Colors.white38 : Colors.black54,
                  fontSize: 12),
            ),
            const SizedBox(height: 40),
            EliteButton(
              onPressed: () => _showJoinRoomDialog(context),
              child: const Text('JOIN MISSION'),
            ),
            const SizedBox(height: 12),
            EliteButton(
              onPressed: () => _showCreateRoomDialog(context),
              isPrimary: false,
              child: const Text('CREATE NEW ROOM'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberList(
      BuildContext context, RoomProvider room, ThemeData theme, bool isDark) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // Privacy Banner
        _buildPrivacyDisclaimer(theme, isDark),
        const SizedBox(height: 24),

        // Settings Card
        EliteSurface(
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.location_on_rounded,
                        color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Location Visibility",
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Text("Allow team to see your live dot",
                            style: TextStyle(
                                fontSize: 10,
                                color:
                                    isDark ? Colors.white54 : Colors.black54)),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: room.isSharingLocation,
                    activeColor: AppColors.primary,
                    onChanged: (val) => room.setSharingLocation(val),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 32),
        const Text(
          'ACTIVE TEAM MEMBERS',
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              color: AppColors.primary),
        ),
        const SizedBox(height: 16),

        ...room.members.map((m) => _memberTile(m.name, true, isDark)),

        const SizedBox(height: 40),

        EliteButton(
          onPressed: () => room.leaveRoom(),
          color: AppColors.danger.withOpacity(0.1),
          child: const Text('ABANDON MISSION',
              style: TextStyle(color: AppColors.danger)),
        ),
        const SizedBox(height: 100),
      ],
    );
  }

  Widget _memberTile(String name, bool online, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: EliteSurface(
        padding: const EdgeInsets.all(12),
        borderRadius: 20,
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor:
                  online ? AppColors.success.withOpacity(0.2) : Colors.white10,
              child: Text(
                name[0].toUpperCase(),
                style: TextStyle(
                    color: online ? AppColors.success : Colors.white30,
                    fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(
                    online ? 'BROADCASTING PULSE' : 'SIGNAL LOST',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                      color: online ? AppColors.success : AppColors.danger,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white24),
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacyDisclaimer(ThemeData theme, bool isDark) {
    return EliteSurface(
      color: AppColors.primary.withOpacity(0.05),
      borderColor: AppColors.primary,
      borderOpacity: 0.2,
      child: Row(
        children: [
          const Icon(Icons.security_rounded,
              size: 20, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Your location is shared ONLY with verified group members. Signals are encrypted and rotatable.',
              style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.white60 : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  void _showJoinRoomDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Join Group'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Enter Room ID'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL')),
          TextButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                final tourist = context.read<TouristProvider>().tourist;
                if (tourist != null) {
                  final consent = await _showLocationSharingConsent(context);
                  if (consent != true || !context.mounted) return;
                  final room = context.read<RoomProvider>();
                  room.setSharingLocation(true);
                  room.joinRoom(
                    roomId: controller.text,
                    userId: tourist.touristId,
                    name: tourist.fullName,
                  );
                }
                Navigator.pop(context);
              }
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
      builder: (context) => AlertDialog(
        title: const Text('Create Group'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Room Name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL')),
          TextButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                final tourist = context.read<TouristProvider>().tourist;
                if (tourist != null) {
                  final consent = await _showLocationSharingConsent(context);
                  if (consent != true || !context.mounted) return;
                  final room = context.read<RoomProvider>();
                  room.setSharingLocation(true);
                  room.createAndJoinRoom(
                    userId: tourist.touristId,
                    name: tourist.fullName,
                  );
                }
                Navigator.pop(context);
              }
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
          'Group safety needs your live location. Only members in this room can see it, and you can pause sharing at any time.',
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
}
