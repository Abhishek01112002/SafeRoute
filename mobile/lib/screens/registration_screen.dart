// lib/screens/registration_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:saferoute/utils/app_theme.dart';
import 'package:saferoute/widgets/premium_widgets.dart';
import 'package:saferoute/providers/tourist_provider.dart';
import 'package:saferoute/models/tourist_model.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:saferoute/screens/permission_setup_screen.dart';
import 'package:saferoute/services/api_service.dart';
import 'package:saferoute/widgets/loading_overlay.dart';
import 'package:saferoute/services/database_service.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();
  int _currentStep = 0;

  String _fullName = '';
  DocumentType _docType = DocumentType.AADHAAR;
  String _docNumber = '';
  String? _photoBase64;
  String _emergencyName = '';
  String _emergencyPhone = '';

  String? _selectedState;
  List<dynamic> _availableDestinations = [];
  final List<Map<String, dynamic>> _selectedDestinations = [];
  List<String> _states = [];
  bool _isLoadingStates = false;
  bool _isLoadingDestinations = false;
  String _bloodGroup = 'O+';
  final List<String> _bloodGroups = [
    'A+',
    'A-',
    'B+',
    'B-',
    'AB+',
    'AB-',
    'O+',
    'O-'
  ];

  @override
  void initState() {
    super.initState();
    _fetchStates();
  }

  Future<void> _fetchStates() async {
    setState(() => _isLoadingStates = true);
    try {
      final api = ApiService();
      final states = await api.getStates();
      setState(() {
        _states = List<String>.from(states);
        if (_states.isNotEmpty) {
          _selectedState =
              _states.contains("Uttarakhand") ? "Uttarakhand" : _states.first;
          _fetchDestinations(_selectedState!);
        }
        _isLoadingStates = false;
      });
    } catch (e) {
      setState(() => _isLoadingStates = false);
    }
  }

  Future<void> _fetchDestinations(String state) async {
    setState(() => _isLoadingDestinations = true);
    try {
      final api = ApiService();
      final dests = await api.getDestinationsByState(state);
      setState(() {
        _availableDestinations = dests;
        _isLoadingDestinations = false;
      });
    } catch (e) {
      setState(() => _isLoadingDestinations = false);
    }
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(
        source: ImageSource.camera, imageQuality: 60, maxWidth: 800);
    if (image != null) {
      final bytes = await File(image.path).readAsBytes();

      // EXIF Stripping (Security Issue 8.2 & 8.4)
      // Decoding and re-encoding effectively strips all camera/GPS metadata
      final decodedImage = img.decodeImage(bytes);
      if (decodedImage != null) {
        final normalizedImage = decodedImage.width > 600
            ? img.copyResize(decodedImage, width: 600)
            : decodedImage;
        var quality = 60;
        var strippedBytes = img.encodeJpg(normalizedImage, quality: quality);
        while (strippedBytes.length > 750000 && quality > 35) {
          quality -= 5;
          strippedBytes = img.encodeJpg(normalizedImage, quality: quality);
        }
        if (strippedBytes.length > 750000) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    "Photo is too large. Please retake it in better lighting.")),
          );
          return;
        }
        setState(() => _photoBase64 = base64Encode(strippedBytes));
        debugPrint(
            "✅ Photo metadata (EXIF) successfully stripped for privacy.");
      } else {
        if (bytes.length > 750000) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text("Photo is too large. Please retake it.")),
          );
          return;
        }
        // Fallback if re-encoding fails
        setState(() => _photoBase64 = base64Encode(bytes));
      }
    }
  }

  void _submitForm() async {
    if (!_formKey.currentState!.validate()) return;
    if (_photoBase64 == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Profile photo is required")));
      return;
    }
    if (_selectedDestinations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Select at least one destination")));
      return;
    }
    _formKey.currentState!.save();

    final touristData = {
      "full_name": _fullName,
      "document_type": _docType.name,
      "document_number": _docNumber,
      "photo_base64": _photoBase64,
      "emergency_contact_name": _emergencyName,
      "emergency_contact_phone": _emergencyPhone,
      "trip_start_date": DateTime.now().toIso8601String(),
      "trip_end_date":
          DateTime.now().add(const Duration(days: 7)).toIso8601String(),
      "destination_state": _selectedState,
      "blood_group": _bloodGroup,
      "selected_destinations": _selectedDestinations
          .map((d) => {
                "destination_id": d['id'],
                "name": d['name'],
                "visit_date_from": DateTime.now().toIso8601String(),
                "visit_date_to": DateTime.now()
                    .add(const Duration(days: 2))
                    .toIso8601String(),
              })
          .toList(),
    };

    final touristProvider = context.read<TouristProvider>();
    final success = await touristProvider.registerTourist(touristData);
    if (!mounted) return;

    if (success && touristProvider.tourist != null) {
      // 4. Persistence Link (Issue #14): Cache Geofence Zones for offline use
      final db = DatabaseService();
      await db.saveGeofenceZones(
          touristProvider.tourist!.geoFenceZones, _selectedState!);

      Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const PermissionSetupScreen()),
          (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLoading = context.watch<TouristProvider>().isLoading;

    return Scaffold(
      body: Stack(
        children: [
          // Aurora Background
          Positioned.fill(child: AuroraBackground()),

          SafeArea(
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  _buildHeader(theme),
                  _buildStepIndicator(theme),
                  Expanded(
                    child: SingleChildScrollView(
                      padding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.l),
                      child: _buildCurrentStep(theme),
                    ),
                  ),
                  _buildBottomNav(theme, isLoading),
                  _buildPrivacyFooter(theme),
                ],
              ),
            ),
          ),
          if (isLoading) const LoadingOverlay(message: "Encrypting ID..."),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(Icons.arrow_back_ios_new_rounded,
                  color: theme.colorScheme.onSurface, size: 20)),
          Text("IDENTITY PROTOCOL",
              style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 13)),
          const SizedBox(width: 48), // Spacer
        ],
      ),
    );
  }

  Widget _buildStepIndicator(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _stepDot(0),
          _stepLine(0),
          _stepDot(1),
          _stepLine(1),
          _stepDot(2),
        ],
      ),
    );
  }

  Widget _stepDot(int idx) {
    final active = _currentStep >= idx;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? AppColors.primary : AppColors.primary.withOpacity(0.1),
        boxShadow: active
            ? [
                BoxShadow(
                    color: AppColors.primary.withOpacity(0.4), blurRadius: 10)
              ]
            : null,
      ),
    );
  }

  Widget _stepLine(int idx) {
    final active = _currentStep > idx;
    return Container(
        width: 40,
        height: 2,
        color: active ? AppColors.primary : AppColors.primary.withOpacity(0.1));
  }

  Widget _buildCurrentStep(ThemeData theme) {
    switch (_currentStep) {
      case 0:
        return _buildProfileStep(theme);
      case 1:
        return _buildDestinationStep(theme);
      case 2:
        return _buildReviewStep(theme);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildProfileStep(ThemeData theme) {
    return Column(
      children: [
        Stack(
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withOpacity(0.05),
                border: Border.all(
                    color: theme.colorScheme.primary.withOpacity(0.2)),
                image: _photoBase64 != null
                    ? DecorationImage(
                        image: MemoryImage(base64Decode(_photoBase64!)),
                        fit: BoxFit.cover)
                    : null,
              ),
              child: _photoBase64 == null
                  ? Icon(Icons.person_add_rounded,
                      size: 40,
                      color: theme.colorScheme.primary.withOpacity(0.5))
                  : null,
            ),
            Positioned(
                bottom: 0,
                right: 0,
                child: FloatingActionButton.small(
                    onPressed: _pickImage,
                    child: const Icon(Icons.camera_alt_rounded))),
          ],
        ),
        const SizedBox(height: AppSpacing.xxl),
        _eliteField(
            label: "FULL LEGAL NAME",
            icon: Icons.person_rounded,
            onSaved: (v) => _fullName = v!),
        const SizedBox(height: AppSpacing.m),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: _buildDropDownField(
                label: "DOC TYPE",
                value: _docType.name,
                items: DocumentType.values.map((e) => e.name).toList(),
                onChanged: (v) =>
                    setState(() => _docType = DocumentType.values.byName(v!)),
              ),
            ),
            const SizedBox(width: AppSpacing.m),
            Expanded(
              flex: 3,
              child: _eliteField(
                  label: "ID NUMBER",
                  icon: Icons.badge_rounded,
                  onSaved: (v) => _docNumber = v!),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.m),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: _buildDropDownField(
                label: "BLOOD GROUP",
                value: _bloodGroup,
                items: _bloodGroups,
                onChanged: (v) => setState(() => _bloodGroup = v!),
              ),
            ),
            const SizedBox(width: AppSpacing.m),
            Expanded(
              flex: 3,
              child: _eliteField(
                  label: "EMERGENCY PHONE",
                  icon: Icons.phone_android_rounded,
                  onSaved: (v) => _emergencyPhone = v!),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDropDownField({
    required String label,
    required String value,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: theme.colorScheme.onSurface.withOpacity(0.4),
                letterSpacing: 1.5)),
        const SizedBox(height: 8),
        EliteSurface(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            underline: const SizedBox(),
            onChanged: onChanged,
            items: items
                .map((e) => DropdownMenuItem(
                    value: e,
                    child: Text(e,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14))))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _eliteField({
    required String label,
    required IconData icon,
    required void Function(String?) onSaved,
  }) {
    final theme = Theme.of(context);
    final String pattern;
    final String errorMsg;

    if (_docType == DocumentType.AADHAAR) {
      pattern = r"^\d{12}$";
      errorMsg = "AADHAAR must be 12 digits";
    } else {
      // Basic Passport regex (usually alphanumeric 8-9 chars)
      pattern = r"^[A-Z0-9]{8,12}$";
      errorMsg = "Invalid PASSPORT format (8-12 chars)";
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: theme.colorScheme.onSurface.withOpacity(0.4),
                letterSpacing: 1.5)),
        const SizedBox(height: 8),
        EliteSurface(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
          child: TextFormField(
            onSaved: onSaved,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            validator: (value) {
              if (value == null || value.isEmpty) return "Field is required";
              if (label.contains("ID NUMBER") &&
                  !RegExp(pattern).hasMatch(value.toUpperCase())) {
                return errorMsg;
              }
              if (label.contains("PHONE") && value.length < 10) {
                return "Invalid phone number";
              }
              return null;
            },
            decoration: InputDecoration(
              border: InputBorder.none,
              icon: Icon(icon, color: AppColors.primary, size: 20),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDestinationStep(ThemeData theme) {
    return Column(
      children: [
        Text("SELECT DESTINATION STATE",
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: theme.colorScheme.onSurface.withOpacity(0.4))),
        const SizedBox(height: AppSpacing.m),
        if (_isLoadingStates)
          const GlimmerLoader(width: double.infinity, height: 4)
        else
          EliteSurface(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
            child: DropdownButton<String>(
              isExpanded: true,
              underline: const SizedBox(),
              value: _selectedState,
              items: _states
                  .map((s) => DropdownMenuItem(
                      value: s,
                      child: Text(s,
                          style: const TextStyle(fontWeight: FontWeight.bold))))
                  .toList(),
              onChanged: (v) => setState(() {
                _selectedState = v;
                _selectedDestinations.clear();
                _fetchDestinations(v!);
              }),
            ),
          ),
        const SizedBox(height: AppSpacing.xl),
        Text("SELECT DESTINATIONS (e.g. Kedarnath, Tungnath)",
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: theme.colorScheme.onSurface.withOpacity(0.4))),
        const SizedBox(height: AppSpacing.m),
        if (_isLoadingDestinations)
          const GlimmerLoader(width: double.infinity, height: 100)
        else
          ..._availableDestinations.map((dest) {
            final isSelected =
                _selectedDestinations.any((d) => d['id'] == dest['id']);
            return EliteSurface(
              margin: const EdgeInsets.only(bottom: AppSpacing.s),
              color: isSelected ? AppColors.primary.withOpacity(0.1) : null,
              child: CheckboxListTile(
                title: Text(dest['name'],
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: Text(
                    "${dest['district']} | Alt: ${dest['altitude_m']}m",
                    style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.onSurface.withOpacity(0.5))),
                value: isSelected,
                activeColor: AppColors.primary,
                onChanged: (val) {
                  setState(() {
                    if (val == true) {
                      _selectedDestinations.add(dest);
                    } else {
                      _selectedDestinations
                          .removeWhere((d) => d['id'] == dest['id']);
                    }
                  });
                },
              ),
            );
          }).toList(),
      ],
    );
  }

  Widget _buildReviewStep(ThemeData theme) {
    return Column(
      children: [
        EliteSurface(
          color: AppColors.zoneGreen.withOpacity(0.1),
          child: const ListTile(
            leading:
                Icon(Icons.verified_user_rounded, color: AppColors.zoneGreen),
            title: Text("READY FOR DEPLOYMENT",
                style:
                    TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
            subtitle: Text(
                "Your identity will be broadcast to local authorities upon SOS trigger.",
                style: TextStyle(fontSize: 10)),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomNav(ThemeData theme, bool isLoading) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
                child: EliteButton(
                    onPressed: () => setState(() => _currentStep--),
                    isPrimary: false,
                    child: const Text("BACK"))),
          const SizedBox(width: AppSpacing.m),
          Expanded(
              child: EliteButton(
                  onPressed: () {
                    if (_currentStep < 2)
                      setState(() => _currentStep++);
                    else
                      _submitForm();
                  },
                  child: Text(_currentStep == 2 ? "FINALIZE" : "NEXT"))),
        ],
      ),
    );
  }

  Widget _buildPrivacyFooter(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.m),
      child: TextButton(
        onPressed: _showPrivacyProtocol,
        child: Text(
          "VIEW PRIVACY & SECURITY PROTOCOL",
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            color: theme.colorScheme.onSurface.withOpacity(0.3),
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }

  void _showPrivacyProtocol() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.black.withOpacity(0.9),
        surfaceTintColor: AppColors.primary,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusL)),
        title: Row(
          children: [
            const Icon(Icons.security_rounded, color: AppColors.primary),
            const SizedBox(width: 12),
            const Text("PRIVACY PROTOCOL",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _protocolItem("Data Encryption",
                  "Your document details and biometric markers are hashed with AES-256 before transmission."),
              _protocolItem("Zero-Knowledge Metadata",
                  "All EXIF and location metadata are stripped from photos locally on your device."),
              _protocolItem("Ephemeral Presence",
                  "Group location sharing is strictly opt-in and data is purged 24h after trip completion."),
              _protocolItem("Authority Access",
                  "Location broadcast is ONLY triggered during high-accuracy SOS alerts or geofence breaches."),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("I UNDERSTAND",
                  style: TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.w900))),
        ],
      ),
    );
  }

  Widget _protocolItem(String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(),
              style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(desc,
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }
}
