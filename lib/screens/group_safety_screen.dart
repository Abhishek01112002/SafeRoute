import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:saferoute/providers/location_provider.dart';
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
      return const Center(child: GlimmerLoader(width: double.infinity, height: 400));
    }

    if (tourist == null) {
      return const Center(child: Text("REGISTRATION REQUIRED", style: TextStyle(color: Colors.white24, fontWeight: FontWeight.w900, letterSpacing: 2)));
    }

    if (!room.isInRoom) {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: AppSpacing.xl),
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
                    child: const Icon(Icons.group_add_rounded, size: 48, color: AppColors.primary),
                  ),
                  const SizedBox(height: AppSpacing.l),
                  const Text("ESTABLISH SAFETY GROUP", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1)),
                  const SizedBox(height: AppSpacing.xs),
                  const Text(
                    "SYNC WITH TRAVEL COMPANIONS FOR REAL-TIME PROXIMITY ALERTS.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  EliteButton(
                    onPressed: room.isLoading ? null : () => room.createAndJoinRoom(
                      userId: tourist.touristId,
                      name: tourist.fullName,
                    ),
                    child: room.isLoading 
                      ? const GlimmerLoader(width: 100, height: 14)
                      : const Text("INITIALIZE NEW ROOM", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1)),
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
                  child: Text("OR JOIN EXISTING", style: TextStyle(color: Colors.white.withOpacity(0.1), fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 2)),
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
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 4, fontSize: 18),
                    decoration: InputDecoration(
                      hintText: "ENTER ROOM ID",
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.1), letterSpacing: 2, fontSize: 14),
                      prefixIcon: const Icon(Icons.vpn_key_rounded, color: Colors.white24, size: 18),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    textCapitalization: TextCapitalization.characters,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.m),
                  EliteButton(
                    isPrimary: false,
                    onPressed: room.isLoading ? null : () {
                      final id = _roomIdController.text.trim().toUpperCase();
                      if (id.isNotEmpty) {
                        room.joinRoom(
                          roomId: id,
                          userId: tourist.touristId,
                          name: tourist.fullName,
                        );
                      }
                    },
                    child: const Text("JOIN NETWORK", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1)),
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
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: AppSpacing.m),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.05),
            border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
          ),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("ACTIVE ROOM SIGNAL", style: TextStyle(color: Colors.white24, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1)),
                  Text(room.roomId ?? '---', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 4)),
                ],
              ),
              const Spacer(),
              _actionIcon(Icons.copy_rounded, () async {
                await Clipboard.setData(ClipboardData(text: room.roomId ?? ''));
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("ID COPIED")));
              }),
              const SizedBox(width: AppSpacing.s),
              _actionIcon(Icons.exit_to_app_rounded, () => room.leaveRoom(), color: AppColors.zoneRed),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(AppSpacing.l),
          child: Row(
            children: [
              Text("NETWORK MEMBERS", style: TextStyle(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 2)),
              Spacer(),
              Icon(Icons.radar_rounded, color: AppColors.primary, size: 14),
            ],
          ),
        ),
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
                      backgroundColor: isMe ? AppColors.primary : Colors.white.withOpacity(0.1),
                      child: Text(
                        m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                        style: TextStyle(color: isMe ? Colors.white : Colors.white38, fontSize: 12, fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isMe ? '${m.name} (YOU)' : m.name.toUpperCase(),
                            style: TextStyle(color: isMe ? Colors.white : Colors.white70, fontWeight: FontWeight.w900, fontSize: 11),
                          ),
                          Text(
                            'LOC: ${m.lat.toStringAsFixed(4)}, ${m.lng.toStringAsFixed(4)}',
                            style: const TextStyle(fontSize: 8, color: Colors.white24, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.location_on_rounded, color: AppColors.zoneGreen, size: 16),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _actionIcon(IconData icon, VoidCallback onTap, {Color color = Colors.white54}) {
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
}
