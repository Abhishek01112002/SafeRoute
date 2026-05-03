import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:saferoute/utils/app_theme.dart';
import 'package:saferoute/widgets/premium_widgets.dart';
import 'package:saferoute/services/identity_service.dart';
import 'package:saferoute/providers/tourist_provider.dart';

class DeveloperSandboxScreen extends StatefulWidget {
  const DeveloperSandboxScreen({super.key});

  @override
  State<DeveloperSandboxScreen> createState() => _DeveloperSandboxScreenState();
}

class _DeveloperSandboxScreenState extends State<DeveloperSandboxScreen> {
  // TUID Tester
  final _docTypeCtrl = TextEditingController(text: 'PASSPORT');
  final _docNumCtrl = TextEditingController();
  final _dobCtrl = TextEditingController(text: '1990-01-01');
  final _natCtrl = TextEditingController(text: 'US');
  String _computedTuid = '';

  // JWT Decoder
  final _jwtCtrl = TextEditingController();
  String _decodedJwt = '';

  @override
  void dispose() {
    _docTypeCtrl.dispose();
    _docNumCtrl.dispose();
    _dobCtrl.dispose();
    _natCtrl.dispose();
    _jwtCtrl.dispose();
    super.dispose();
  }

  void _calculateTuid() {
    if (_docNumCtrl.text.isEmpty) return;
    final tuid = IdentityService.generateTuid(
      _docTypeCtrl.text,
      _docNumCtrl.text,
      _dobCtrl.text,
      _natCtrl.text,
    );
    setState(() {
      _computedTuid = tuid;
    });
    HapticFeedback.mediumImpact();
  }

  void _decodeJwt() {
    final jwt = _jwtCtrl.text.trim();
    if (jwt.isEmpty) return;

    try {
      final parts = jwt.split('.');
      if (parts.length != 3) throw Exception('Invalid JWT structure');

      final payload = _decodeBase64(parts[1]);
      final map = json.decode(payload);

      setState(() {
        _decodedJwt = const JsonEncoder.withIndent('  ').convert(map);
      });
      HapticFeedback.mediumImpact();
    } catch (e) {
      setState(() {
        _decodedJwt = 'Error: Invalid JWT or payload\n$e';
      });
      HapticFeedback.vibrate();
    }
  }

  String _decodeBase64(String str) {
    String output = str.replaceAll('-', '+').replaceAll('_', '/');
    switch (output.length % 4) {
      case 0:
        break;
      case 2:
        output += '==';
        break;
      case 3:
        output += '=';
        break;
      default:
        throw Exception('Illegal base64url string!');
    }
    return utf8.decode(base64Url.decode(output));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final touristProv = context.watch<TouristProvider>();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          "DEVELOPER SANDBOX",
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.0,
              color: AppColors.accent),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.accent),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildWarningHeader(context),
            const SizedBox(height: AppSpacing.xl),

            // 1. TUID Algorithm Tester
            _buildSection(
              context,
              title: "1. CRYPTO: TUID GENERATOR",
              icon: Icons.fingerprint_rounded,
              child: Column(
                children: [
                  TextField(
                    controller: _docNumCtrl,
                    decoration: const InputDecoration(labelText: 'Document Number'),
                  ),
                  const SizedBox(height: AppSpacing.m),
                  EliteButton(
                    onPressed: _calculateTuid,
                    child: const Text("COMPUTE TUID"),
                  ),
                  if (_computedTuid.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: AppSpacing.m),
                      padding: const EdgeInsets.all(AppSpacing.m),
                      color: Colors.black26,
                      child: Text(
                        _computedTuid,
                        style: const TextStyle(fontFamily: 'monospace', color: Colors.greenAccent),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.l),

            // 2. Current Session Audit
            _buildSection(
              context,
              title: "2. AUDIT: CURRENT SESSION",
              icon: Icons.verified_user_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Tourist ID: ${touristProv.tourist?.touristId ?? 'NONE'}", style: const TextStyle(fontFamily: 'monospace')),
                  const SizedBox(height: 8),
                  Text("TUID: ${touristProv.tourist?.tuid ?? 'NONE'}", style: const TextStyle(fontFamily: 'monospace', color: Colors.greenAccent)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.l),

            // 3. JWT Decoder
            _buildSection(
              context,
              title: "3. CRYPTO: JWT DECODER",
              icon: Icons.qr_code_scanner_rounded,
              child: Column(
                children: [
                  TextField(
                    controller: _jwtCtrl,
                    decoration: const InputDecoration(labelText: 'Paste JWT Token'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: AppSpacing.m),
                  EliteButton(
                    onPressed: _decodeJwt,
                    child: const Text("DECODE PAYLOAD"),
                  ),
                  if (_decodedJwt.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: AppSpacing.m),
                      padding: const EdgeInsets.all(AppSpacing.m),
                      color: Colors.black26,
                      width: double.infinity,
                      child: Text(
                        _decodedJwt,
                        style: const TextStyle(fontFamily: 'monospace', color: Colors.greenAccent, fontSize: 10),
                      ),
                    ),
                ],
              ),
            ),
            // 4. Dashboard Bridge
            _buildSection(
              context,
              title: "4. BRIDGE: REACT COMMAND CENTER",
              icon: Icons.monitor_heart_rounded,
              child: Column(
                children: [
                  const Text(
                    "Launch the Command Center Dashboard in a browser to monitor live telemetry.",
                    style: TextStyle(fontSize: 10, color: Colors.white70),
                  ),
                  const SizedBox(height: AppSpacing.m),
                  EliteButton(
                    onPressed: () {
                      HapticFeedback.heavyImpact();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Mock Launch: Opening http://localhost:5173/")),
                      );
                    },
                    child: const Text("LAUNCH LOCALHOST:5173"),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.l),

            // 5. Mock Authority Gateway
            _buildSection(
              context,
              title: "5. GATEWAY: AUTHORITY SCANNER",
              icon: Icons.security_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    "Simulate an Authority role without polluting real production audit logs. Requires a test token.",
                    style: TextStyle(fontSize: 10, color: Colors.white70),
                  ),
                  const SizedBox(height: AppSpacing.m),
                  const TextField(
                    decoration: InputDecoration(
                      labelText: 'Test Authority JWT (Mock)',
                      hintText: 'Enter mock token to bypass auth',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.m),
                  EliteButton(
                    onPressed: () {
                      HapticFeedback.heavyImpact();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Mock Scanner Initialized")),
                      );
                    },
                    child: const Text("INITIALIZE SCANNER (MOCK)"),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, {required String title, required IconData icon, required Widget child}) {
    return EliteSurface(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.accent),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.m),
          child,
        ],
      ),
    );
  }

  Widget _buildWarningHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(
        color: AppColors.zoneYellow.withOpacity(0.1),
        border: Border.all(color: AppColors.zoneYellow.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(AppSpacing.radiusM),
      ),
      child: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: AppColors.zoneYellow),
          SizedBox(width: AppSpacing.m),
          Expanded(
            child: Text(
              "FAANG STAGING ONLY\nNetwork requests are automatically routed to the Staging API (https://staging-api.saferoute.app) to prevent production database corruption.",
              style: TextStyle(color: AppColors.zoneYellow, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
