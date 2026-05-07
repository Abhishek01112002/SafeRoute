import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:dio/dio.dart';
import 'package:saferoute/tourist/models/tourist_model.dart';
import 'package:saferoute/tourist/providers/tourist_provider.dart';
import 'package:saferoute/services/api_service.dart';
import 'package:saferoute/services/secure_storage_service.dart';
import 'package:saferoute/core/config/env_config.dart';
import 'package:saferoute/utils/app_theme.dart';
import 'package:saferoute/widgets/app_ui.dart';
import 'package:saferoute/widgets/premium_widgets.dart';
import 'package:saferoute/core/service_locator.dart';

class DigitalIDScreenV2 extends StatelessWidget {
  const DigitalIDScreenV2({super.key});

  @override
  Widget build(BuildContext context) {
    final tourist = context.watch<TouristProvider>().tourist;

    if (tourist == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          const Positioned.fill(child: AuroraBackground()),
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _ScreenHeader(),
                  const SizedBox(height: 14),
                  _IdentityPassport(tourist: tourist),
                  const SizedBox(height: 14),
                  _QrVerificationCard(tourist: tourist),
                  const SizedBox(height: 14),
                  _TripAndEmergencyGrid(tourist: tourist),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScreenHeader extends StatelessWidget {
  const _ScreenHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Digital safety ID',
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Responder-ready identity, route, and emergency context.',
          style: TextStyle(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.64),
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

class _IdentityPassport extends StatelessWidget {
  final Tourist tourist;

  const _IdentityPassport({required this.tourist});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppSurface(
      padding: EdgeInsets.zero,
      color: theme.colorScheme.surface,
      borderColor: _syncColor.withValues(alpha: 0.38),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _syncColor.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppSpacing.radiusM)),
            ),
            child: Row(
              children: [
                Icon(
                  tourist.isSynced
                      ? Icons.verified_user_rounded
                      : Icons.offline_pin_rounded,
                  color: _syncColor,
                  size: 26,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tourist.isSynced
                            ? 'Verified safety network'
                            : 'Offline ID pending sync',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                      Text(
                        tourist.destinationState,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.62),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PhotoSection(tourist: tourist),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tourist.fullName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 18,
                          height: 1.15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _InfoLine(label: 'Tourist ID', value: tourist.touristId),
                      _InfoLine(
                        label: 'TUID',
                        value: tourist.tuid ??
                            (tourist.isSynced
                                ? 'Not assigned'
                                : 'Pending server sync'),
                      ),
                      _InfoLine(
                        label: 'Document',
                        value:
                            '${tourist.documentType.name} / ${_maskDocument(tourist.documentNumber)}',
                      ),
                      _InfoLine(
                        label: 'Blood',
                        value: tourist.bloodGroup,
                        valueColor: AppColors.danger,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color get _syncColor =>
      tourist.isSynced ? AppColors.success : AppColors.warning;

  String _maskDocument(String value) {
    if (value.length <= 4) return value.isEmpty ? 'Not provided' : value;
    return '•••• ${value.substring(value.length - 4)}';
  }
}

class _PhotoSection extends StatefulWidget {
  final Tourist tourist;

  const _PhotoSection({required this.tourist});

  @override
  State<_PhotoSection> createState() => _PhotoSectionState();
}

class _PhotoSectionState extends State<_PhotoSection> {
  late Future<Uint8List>? _photoFuture;

  @override
  void initState() {
    super.initState();
    _photoFuture = _initPhotoFuture();
  }

  Future<Uint8List>? _initPhotoFuture() {
    final tourist = widget.tourist;
    if (tourist.photoObjectKey != null && tourist.photoObjectKey!.isNotEmpty) {
      return _loadPhoto(tourist);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 98,
      height: 124,
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.42)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: _getImageContent(widget.tourist),
      ),
    );
  }

  Widget _getImageContent(Tourist tourist) {
    // Priority 1: Try backend photo endpoint if photoObjectKey exists (multipart uploads)
    if (_photoFuture != null) {
      return FutureBuilder<Uint8List>(
        future: _photoFuture!,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          if (snapshot.hasError || !snapshot.hasData) {
            // Fall through to base64 check below
            return _buildBase64OrPlaceholder(tourist);
          }
          return Image.memory(snapshot.data!, fit: BoxFit.cover);
        },
      );
    }

    // Priority 2: Base64 photo (legacy registrations)
    return _buildBase64OrPlaceholder(tourist);
  }

  Future<Uint8List> _loadPhoto(Tourist tourist) async {
    // Try S3-style fetch first
    try {
      return await locator<ApiService>()
          .fetchSecureMedia(tourist.photoObjectKey!);
    } catch (_) {
      // S3 fetch failed - try backend photo endpoint
      try {
        final dio = Dio();
        final secureStorage = locator<SecureStorageService>();
        final token = await secureStorage.getToken();
        final response = await dio.get(
          '${EnvConfig.apiBaseUrl}/v3/tourist/photo/${tourist.touristId}',
          options: Options(
            responseType: ResponseType.bytes,
            headers: token != null ? {'Authorization': 'Bearer $token'} : null,
          ),
        );
        if (response.data is Uint8List) {
          return response.data;
        }
        return Uint8List.fromList(response.data);
      } catch (_) {
        // Both methods failed
        rethrow;
      }
    }
  }

  Widget _buildBase64OrPlaceholder(Tourist tourist) {
    if (tourist.photoBase64.isNotEmpty) {
      try {
        return Image.memory(base64Decode(tourist.photoBase64),
            fit: BoxFit.cover);
      } catch (_) {
        return Icon(Icons.person_rounded,
            size: 42,
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.38));
      }
    }
    return Icon(Icons.person_rounded,
        size: 42,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38));
  }
}

class _QrVerificationCard extends StatelessWidget {
  final Tourist tourist;

  const _QrVerificationCard({required this.tourist});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppSurface(
      padding: const EdgeInsets.all(16),
      color: theme.colorScheme.surface,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: QrImageView(
              data: tourist.qrData,
              version: QrVersions.auto,
              errorCorrectionLevel: QrErrorCorrectLevel.M,
              size: 116,
              gapless: false,
              eyeStyle: const QrEyeStyle(color: Colors.black),
              dataModuleStyle: const QrDataModuleStyle(color: Colors.black),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Secure verification',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Scan to verify identity, trip validity, and emergency details.',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.64),
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                _StatusBadge(
                  label: tourist.isSynced ? 'Synced' : 'Offline saved',
                  color:
                      tourist.isSynced ? AppColors.success : AppColors.warning,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TripAndEmergencyGrid extends StatelessWidget {
  final Tourist tourist;

  const _TripAndEmergencyGrid({required this.tourist});

  @override
  Widget build(BuildContext context) {
    final destinations = tourist.selectedDestinations
        .map((destination) => destination.name)
        .where((name) => name.trim().isNotEmpty)
        .toList();

    return Column(
      children: [
        _DetailCard(
          icon: Icons.route_rounded,
          title: 'Trip coverage',
          rows: [
            _DetailRow('State', tourist.destinationState),
            _DetailRow('Valid from', _formatDate(tourist.tripStartDate)),
            _DetailRow('Valid until', _formatDate(tourist.tripEndDate)),
            _DetailRow(
              'Destinations',
              destinations.isEmpty
                  ? 'State-wide safety profile'
                  : destinations.join(', '),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _DetailCard(
          icon: Icons.contact_emergency_rounded,
          title: 'Emergency response',
          rows: [
            _DetailRow('Contact name', _fallback(tourist.emergencyContactName)),
            _DetailRow(
                'Contact phone', _fallback(tourist.emergencyContactPhone)),
            _DetailRow('Risk profile', tourist.riskLevel),
            _DetailRow(
              'Offline mode',
              tourist.offlineModeRequired ? 'Required' : 'Available',
            ),
          ],
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _fallback(String value) {
    return value.trim().isEmpty ? 'Not provided' : value;
  }
}

class _DetailCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<_DetailRow> rows;

  const _DetailCard({
    required this.icon,
    required this.title,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      child: AppSurface(
        padding: const EdgeInsets.all(16),
        color: theme.colorScheme.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.accent, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...rows.map((row) => _InfoLine(label: row.label, value: row.value)),
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoLine({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.56),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor ?? Theme.of(context).colorScheme.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DetailRow {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);
}
