// lib/screens/digital_id_screen_v2.dart - Digital ID Screen (Premium)
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:saferoute/providers/tourist_provider.dart';
import 'package:saferoute/utils/app_theme.dart';
import 'package:saferoute/widgets/premium_widgets.dart';

class DigitalIDScreenV2 extends StatelessWidget {
  const DigitalIDScreenV2({super.key});

  @override
  Widget build(BuildContext context) {
    final tourist = context.watch<TouristProvider>().tourist;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (tourist == null) {
      return const AuroraBackground(); // Loading fallback handled by main
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const AuroraBackground(),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const SizedBox(height: 20),

                  // 1. Digital Passport Card
                  EliteSurface(
                    padding: EdgeInsets.zero,
                    borderRadius: 30,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Card Header
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Color.lerp(
                                Colors.transparent,
                                tourist.destinationState.contains("Uttarakhand")
                                    ? Colors.orange
                                    : AppColors.primary,
                                0.1),
                            border: Border(
                                bottom: BorderSide(
                                    color: isDark
                                        ? Colors.white10
                                        : Colors.black12)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'REGISTERED SAFETY NETWORK',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 2,
                                      color: isDark
                                          ? Colors.white70
                                          : Colors.black54,
                                    ),
                                  ),
                                  Text(
                                    tourist.destinationState.toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                              const Icon(Icons.verified_user_rounded,
                                  color: AppColors.accent, size: 32),
                            ],
                          ),
                        ),

                        // Card Content
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Photo Section
                              _buildPhotoSection(tourist.photoBase64, isDark),
                              const SizedBox(width: 20),

                              // Info Section
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildInfoField(
                                        'FULL NAME', tourist.fullName, isDark),
                                    const SizedBox(height: 12),
                                    _buildInfoField('DOCUMENT ID',
                                        tourist.documentNumber, isDark),
                                    const SizedBox(height: 12),
                                    _buildInfoField(
                                        'VALID UNTIL',
                                        _formatDate(tourist.tripEndDate),
                                        isDark),
                                    const SizedBox(height: 12),
                                    _buildInfoField('BLOOD GROUP',
                                        tourist.bloodGroup, isDark),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // QR Section
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 30),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.black26 : Colors.white24,
                            borderRadius: const BorderRadius.vertical(
                                bottom: Radius.circular(30)),
                          ),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 10,
                                    )
                                  ],
                                ),
                                child: QrImageView(
                                  data: tourist.qrData,
                                  version: QrVersions.auto,
                                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                                  size: 180.0,
                                  gapless: false,
                                  foregroundColor: Colors.black,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'SCAN FOR SECURE VERIFICATION',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2,
                                  color:
                                      isDark ? Colors.white38 : Colors.black38,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // 2. Blockchain Verification Badge
                  EliteSurface(
                    color: AppColors.success.withOpacity(0.1),
                    borderColor: AppColors.success,
                    borderOpacity: 0.3,
                    child: Row(
                      children: [
                        const Icon(Icons.token_rounded,
                            color: AppColors.success),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'BLOCKCHAIN VERIFIED',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                  color: AppColors.success,
                                ),
                              ),
                              SelectableText(
                                tourist.blockchainHash,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontFamily: 'monospace',
                                  color:
                                      isDark ? Colors.white70 : Colors.black87,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 100), // Spacing for fab/dock
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoSection(String base64, bool isDark) {
    return Container(
      width: 100,
      height: 120,
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.black12,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
            color: AppColors.primary.withOpacity(0.5),
            width: 2), // High contrast border
        image: base64.isNotEmpty
            ? DecorationImage(
                image: MemoryImage(base64Decode(base64)),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: base64.isEmpty
          ? const Icon(Icons.person_rounded, size: 40, color: Colors.white24)
          : null,
    );
  }

  Widget _buildInfoField(String label, String value, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
            color: isDark ? Colors.white38 : Colors.black54,
          ),
        ),
        Text(
          value.toUpperCase(),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return "${date.day}/${date.month}/${date.year}";
  }
}
