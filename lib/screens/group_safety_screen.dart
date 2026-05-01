import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:saferoute/providers/tourist_provider.dart';
import 'package:saferoute/providers/room_provider.dart';
import 'package:saferoute/utils/app_theme.dart';
import 'package:saferoute/widgets/premium_widgets.dart';
import 'package:flutter/services.dart';

class GroupSafetyScreen extends StatefulWidget {
  const GroupSafetyScreen({super.key});

  @override
  State<GroupSafetyScreen> createState() => _GroupSafetyScreenState();
}

class _GroupSafetyScreenState extends State<GroupSafetyScreen> {
  final _roomIdController = TextEditingController();

  @override
  void dispose() {
    _roomIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = context.watch<RoomProvider>();
    final touristProvider = context.watch<TouristProvider>();
    final tourist = touristProvider.tourist;

    if (touristProvider.isLoading) {
      return const Center(
          child: GlimmerLoader(width: double.infinity, height: 400));
    }

    if (tourist == null) {
      return const Center(
          child: Text("REGISTRATION REQUIRED",
              style: TextStyle(
                  color: Colors.white24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2)));
    }

    if (!room.isInRoom) {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.l, vertical: AppSpacing.xl),
        child: Column(
          children: [
            EliteSurface(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.l),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.group_add_rounded,
                        size: 48, color: AppColors.primary),
                  ),
                  const SizedBox(height: AppSpacing.l),
                  const Text("ESTABLISH SAFETY GROUP",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1)),
                  const SizedBox(height: AppSpacing.xs),
                  const Text(
                    "SYNC WITH TRAVEL COMPANIONS FOR REAL-TIME PROXIMITY ALERTS.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white38,
                        fontSize: 9,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  EliteButton(
                    onPressed: room.isLoading
                        ? null
                        : () => room.createAndJoinRoom(
                              userId: tourist.touristId,
                              name: tourist.fullName,
                            ),
                    child: room.isLoading
                        ? const GlimmerLoader(width: 100, height: 14)
                        : const Text("INITIALIZE NEW ROOM",
                            style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 10,
                                letterSpacing: 1)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                Expanded(child: Divider(color: Colors.white.withOpacity(0.05))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
                  child: Text("OR JOIN EXISTING",
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.1),
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2)),
                ),
                Expanded(child: Divider(color: Colors.white.withOpacity(0.05))),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            EliteSurface(
              padding: const EdgeInsets.all(AppSpacing.l),
              child: Column(
                children: [
                  TextField(
                    controller: _roomIdController,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4,
                        fontSize: 18),
                    decoration: InputDecoration(
                      hintText: "ENTER ROOM ID",
                      hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.1),
                          letterSpacing: 2,
                          fontSize: 14),
                      prefixIcon: const Icon(Icons.vpn_key_rounded,
                          color: Colors.white24, size: 18),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    textCapitalization: TextCapitalization.characters,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.m),
                  EliteButton(
                    isPrimary: false,
                    onPressed: room.isLoading
                        ? null
                        : () async {
                            final id =
                                _roomIdController.text.trim().toUpperCase();
                            if (id.isNotEmpty) {
                              // ISSUE #6 FIX: Add privacy consent dialog before joining room
                              final consent =
                                  await _showPrivacyConsentDialog(context);
                              if (consent == true) {
                                room.joinRoom(
                                  roomId: id,
                                  userId: tourist.touristId,
                                  name: tourist.fullName,
                                );
                              }
                            }
                          },
                    child: const Text("JOIN NETWORK",
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 10,
                            letterSpacing: 1)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // In-Room View
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.l, vertical: AppSpacing.m),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.05),
            border: Border(
                bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
          ),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("ACTIVE ROOM SIGNAL",
                      style: TextStyle(
                          color: Colors.white24,
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1)),
                  Text(room.roomId ?? '---',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 4)),
                ],
              ),
              const Spacer(),
              _actionIcon(Icons.copy_rounded, () async {
                await Clipboard.setData(ClipboardData(text: room.roomId ?? ''));
                if (mounted)
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text("ID COPIED")));
              }),
              const SizedBox(width: AppSpacing.s),
              _actionIcon(Icons.exit_to_app_rounded, () => room.leaveRoom(),
                  color: AppColors.zoneRed),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(AppSpacing.l),
          child: Row(
            children: [
              Text("NETWORK MEMBERS",
                  style: TextStyle(
                      color: Colors.white24,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2)),
              Spacer(),
              Icon(Icons.radar_rounded, color: AppColors.primary, size: 14),
            ],
          ),
        ),
        // ISSUE #6 FIX: Add privacy controls section
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
          child: EliteSurface(
            padding: const EdgeInsets.all(AppSpacing.m),
            child: Row(
              children: [
                Icon(
                  room.isSharingLocation
                      ? Icons.location_on_rounded
                      : Icons.location_off_rounded,
                  color: room.isSharingLocation
                      ? AppColors.zoneGreen
                      : AppColors.zoneRed,
                  size: 16,
                ),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: Text(
                    room.isSharingLocation
                        ? "LOCATION SHARING ACTIVE"
                        : "LOCATION SHARING PAUSED",
                    style: TextStyle(
                      color: room.isSharingLocation
                          ? AppColors.zoneGreen
                          : AppColors.zoneRed,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Switch(
                  value: room.isSharingLocation,
                  onChanged: (value) => room.setSharingLocation(value),
                  activeColor: AppColors.primary,
                  inactiveThumbColor: AppColors.zoneRed,
                  inactiveTrackColor: AppColors.zoneRed.withOpacity(0.3),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
            itemCount: room.members.length,
            itemBuilder: (ctx, i) {
              final m = room.members[i];
              final isMe = m.userId == tourist.touristId;

              return EliteSurface(
                margin: const EdgeInsets.only(bottom: AppSpacing.s),
                padding: const EdgeInsets.all(AppSpacing.m),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: isMe
                          ? AppColors.primary
                          : Colors.white.withOpacity(0.1),
                      child: Text(
                        m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                        style: TextStyle(
                            color: isMe ? Colors.white : Colors.white38,
                            fontSize: 12,
                            fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isMe ? '${m.name} (YOU)' : m.name.toUpperCase(),
                            style: TextStyle(
                                color: isMe ? Colors.white : Colors.white70,
                                fontWeight: FontWeight.w900,
                                fontSize: 11),
                          ),
                          // ISSUE #6 FIX: Respect privacy - only show location if user is sharing
                          if (room.isSharingLocation)
                            Text(
                              'LOC: ${m.lat.toStringAsFixed(4)}, ${m.lng.toStringAsFixed(4)}',
                              style: const TextStyle(
                                  fontSize: 8,
                                  color: Colors.white24,
                                  fontWeight: FontWeight.bold),
                            )
                          else
                            Text(
                              isMe ? 'LOCATION HIDDEN' : 'LOCATION PRIVATE',
                              style: TextStyle(
                                  fontSize: 8,
                                  color: AppColors.zoneRed.withOpacity(0.7),
                                  fontWeight: FontWeight.bold),
                            ),
                        ],
                      ),
                    ),
                    Icon(
                      room.isSharingLocation
                          ? Icons.location_on_rounded
                          : Icons.location_off_rounded,
                      color: room.isSharingLocation
                          ? AppColors.zoneGreen
                          : AppColors.zoneRed,
                      size: 16,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _actionIcon(IconData icon, VoidCallback onTap,
      {Color color = Colors.white54}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.1)),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }

  /// ISSUE #6 FIX: Privacy consent dialog for location sharing
  Future<bool?> _showPrivacyConsentDialog(BuildContext context) async {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusM)),
        title: Row(
          children: [
            Icon(Icons.privacy_tip_rounded, color: AppColors.primary, size: 24),
            const SizedBox(width: AppSpacing.s),
            const Text("LOCATION SHARING CONSENT",
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "By joining this group, you agree to share your live location with other members for safety purposes.",
              style: TextStyle(
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                  fontSize: 12),
            ),
            const SizedBox(height: AppSpacing.m),
            _buildConsentPoint(
                "📍 Real-time GPS location will be visible to group members"),
            _buildConsentPoint(
                "🚨 Location data helps coordinate emergency responses"),
            _buildConsentPoint(
                "🔒 You can stop sharing at any time from group settings"),
            _buildConsentPoint(
                "📱 Location sharing respects your device privacy settings"),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text("CANCEL",
                style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.5))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("AGREE & JOIN",
                style: TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  Widget _buildConsentPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Text(
              text,
              style:
                  TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}
