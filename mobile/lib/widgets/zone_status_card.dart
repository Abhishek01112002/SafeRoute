import 'package:flutter/material.dart';
import 'package:saferoute/core/models/location_ping_model.dart';
import 'package:saferoute/utils/app_theme.dart';
import 'package:saferoute/widgets/app_ui.dart';

class ZoneStatusCard extends StatelessWidget {
  final ZoneType status;

  const ZoneStatusCard({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final tone = _toneFor(status);
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return AppSurface(
      padding: EdgeInsets.zero,
      color: theme.colorScheme.surface,
      borderColor: tone.primary.withValues(alpha: 0.50),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXL),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              tone.primary.withValues(alpha: 0.14),
              theme.colorScheme.surface,
              tone.primary.withValues(alpha: 0.05),
            ],
          ),
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: tone.primary.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: tone.primary.withValues(alpha: 0.38),
                    ),
                  ),
                  child: Icon(tone.icon, color: tone.primary, size: 27),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tone.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tone.primary,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tone.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: onSurface.withValues(alpha: 0.62),
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                _LiveBadge(
                    color: tone.primary, syncing: status == ZoneType.syncing),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              tone.description,
              style: TextStyle(
                color: onSurface,
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            _ZoneStageRail(status: status),
            const SizedBox(height: 14),
            _ZoneGuidance(tone: tone),
          ],
        ),
      ),
    );
  }

  _ZoneTone _toneFor(ZoneType status) {
    switch (status) {
      case ZoneType.safe:
        return const _ZoneTone(
          title: 'Secure perimeter',
          subtitle: 'Authority zone status',
          description:
              'No active caution or restricted zone contains your current GPS point. Continue with normal awareness.',
          guidance: 'Stay on the planned trail',
          icon: Icons.shield_moon_rounded,
          primary: AppColors.success,
        );
      case ZoneType.caution:
        return const _ZoneTone(
          title: 'Caution zone',
          subtitle: 'Authority zone status',
          description:
              'You are inside a moderate-risk area. Slow down, keep the group together, and follow navigation guidance.',
          guidance: 'Move toward a secure segment',
          icon: Icons.gpp_maybe_rounded,
          primary: AppColors.warning,
        );
      case ZoneType.restricted:
        return const _ZoneTone(
          title: 'Restricted zone',
          subtitle: 'Authority zone status',
          description:
              'You are inside a high-risk area. Retrace to the last safe point and use SOS if movement is not possible.',
          guidance: 'Retrace immediately',
          icon: Icons.gpp_bad_rounded,
          primary: AppColors.danger,
        );
      case ZoneType.syncing:
        return const _ZoneTone(
          title: 'Syncing zones',
          subtitle: 'Local cache + live data',
          description:
              'Zone data is loading before the app confirms your perimeter. Treat the route as caution until synced.',
          guidance: 'Hold position while status updates',
          icon: Icons.sync_rounded,
          primary: AppColors.info,
        );
    }
  }
}

class _ZoneStageRail extends StatelessWidget {
  final ZoneType status;

  const _ZoneStageRail({required this.status});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ZoneStage(
            zone: ZoneType.safe,
            label: 'Safe',
            currentStatus: status,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ZoneStage(
            zone: ZoneType.caution,
            label: 'Caution',
            currentStatus: status,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ZoneStage(
            zone: ZoneType.restricted,
            label: 'Restricted',
            currentStatus: status,
          ),
        ),
      ],
    );
  }
}

class _ZoneStage extends StatelessWidget {
  final ZoneType zone;
  final String label;
  final ZoneType currentStatus;

  const _ZoneStage({
    required this.zone,
    required this.label,
    required this.currentStatus,
  });

  @override
  Widget build(BuildContext context) {
    final active = currentStatus == zone;
    final color = _colorFor(zone);
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          height: 7,
          decoration: BoxDecoration(
            color: active
                ? color
                : onSurface.withValues(
                    alpha: currentStatus == ZoneType.syncing ? 0.20 : 0.12,
                  ),
            borderRadius: BorderRadius.circular(999),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.45),
                      blurRadius: 12,
                    )
                  ]
                : null,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: active ? color : onSurface.withValues(alpha: 0.58),
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }

  Color _colorFor(ZoneType zone) {
    switch (zone) {
      case ZoneType.safe:
        return AppColors.success;
      case ZoneType.caution:
        return AppColors.warning;
      case ZoneType.restricted:
        return AppColors.danger;
      case ZoneType.syncing:
        return AppColors.info;
    }
  }
}

class _ZoneGuidance extends StatelessWidget {
  final _ZoneTone tone;

  const _ZoneGuidance({required this.tone});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tone.primary.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.primary.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          Icon(Icons.route_rounded, color: tone.primary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tone.guidance,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  final Color color;
  final bool syncing;

  const _LiveBadge({required this.color, required this.syncing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (syncing)
            SizedBox(
              width: 8,
              height: 8,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            )
          else
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          const SizedBox(width: 6),
          Text(
            syncing ? 'Sync' : 'Live',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoneTone {
  final String title;
  final String subtitle;
  final String description;
  final String guidance;
  final IconData icon;
  final Color primary;

  const _ZoneTone({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.guidance,
    required this.icon,
    required this.primary,
  });
}
