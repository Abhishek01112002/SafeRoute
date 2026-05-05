// lib/screens/registration_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:saferoute/utils/app_theme.dart';
import 'package:saferoute/widgets/premium_widgets.dart';
import 'package:saferoute/tourist/providers/tourist_provider.dart';
import 'package:saferoute/tourist/models/tourist_model.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:saferoute/screens/permission_setup_screen.dart';
import 'package:saferoute/services/api_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:saferoute/services/permission_service.dart';
import 'package:saferoute/widgets/loading_overlay.dart';
import 'package:intl/intl.dart';
import 'package:country_picker/country_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:saferoute/services/sync_engine.dart';
import 'package:saferoute/core/service_locator.dart';

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
  DocumentType _docType = DocumentType.aadhaar;
  String _docNumber = '';
  File? _photoFile;
  File? _documentFile;
  String? _documentName;
  DateTime? _selectedDob;
  Country? _selectedCountry;
  final String _emergencyName = '';
  String _emergencyPhone = '';
  double _uploadProgress = 0.0;

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
      final api = locator<ApiService>();
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
      final api = locator<ApiService>();
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
    unawaited(showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildSourceSheet(
        onSelected: (source) async {
          Navigator.pop(context);

          // Request appropriate permission
          final permission = source == ImageSource.camera
              ? Permission.camera
              : Permission.photos;

          final status = await PermissionService.requestPermission(
            permission: permission,
            context: context,
            rationaleTitle: source == ImageSource.camera
                ? 'Camera Access'
                : 'Photo Library Access',
            rationaleMessage: source == ImageSource.camera
                ? 'SafeRoute needs camera access to capture your profile photo.'
                : 'SafeRoute needs access to your photos to upload a profile picture.',
          );

          if (!status.isGranted && !status.isLimited) return;

          final XFile? image = await _picker.pickImage(
              source: source, imageQuality: 60, maxWidth: 800);
          if (image != null) {
            final file = File(image.path);
            final size = await file.length();
            if (size > 5 * 1024 * 1024) {
              _showError("Image too large (max 5MB)");
              return;
            }
            setState(() => _photoFile = file);
          }
        },
      ),
    ));
  }

  Future<void> _pickDocument() async {
    unawaited(showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildSourceSheet(
        title: "SCAN OR UPLOAD DOCUMENT",
        allowFiles: true,
        onSelected: (source) async {
          Navigator.pop(context);
          if (source == ImageSource.camera) {
            // Request Camera Permission
            final status = await PermissionService.requestPermission(
              permission: Permission.camera,
              context: context,
              rationaleTitle: 'Camera Access',
              rationaleMessage:
                  'SafeRoute needs camera access to scan your documents.',
            );
            if (!status.isGranted) return;

            final XFile? image = await _picker.pickImage(
                source: source, imageQuality: 70, maxWidth: 1000);
            if (image != null) {
              setState(() {
                _documentFile = File(image.path);
                _documentName = "scan.jpg";
              });
            }
          } else {
            // Gallery/File Selection - Request Storage/Photos Permission
            final status = await PermissionService.requestPermission(
              permission: Permission.photos,
              context: context,
              rationaleTitle: 'File Access',
              rationaleMessage:
                  'SafeRoute needs access to your files to upload document scans.',
            );
            if (!status.isGranted && !status.isLimited) return;

            final FilePickerResult? result =
                await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
            );

            if (result != null) {
              final file = File(result.files.single.path!);
              final size = await file.length();
              if (size > 10 * 1024 * 1024) {
                _showError("File too large (max 10MB)");
                return;
              }
              setState(() {
                _documentFile = file;
                _documentName = result.files.single.name;
              });
            }
          }
        },
      ),
    ));
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  void _handleNextStep() {
    final formState = _formKey.currentState;

    if (_currentStep == 0) {
      formState?.save();

      final errors = _identityStepErrors();
      if (errors.isNotEmpty) {
        _showError(errors.first);
        return;
      }
    } else {
      formState?.save();
    }

    setState(() => _currentStep++);
  }

  List<String> _identityStepErrors() {
    final errors = <String>[];
    final fullName = _fullName.trim();
    final docError = _documentNumberError(_docNumber);

    if (fullName.isEmpty) {
      errors.add("Full legal name is required");
    }
    if (docError != null) {
      errors.add(docError);
    }
    if (_selectedDob == null) {
      errors.add("Date of birth is required");
    } else {
      final age = DateTime.now().difference(_selectedDob!).inDays ~/ 365;
      if (age < 18) {
        errors.add("You must be at least 18 years old");
      }
    }
    if (_selectedCountry == null) {
      errors.add("Nationality is required");
    }
    if (_photoFile == null) {
      errors.add("Profile photo is required");
    }
    if (_documentFile == null) {
      errors.add("Document scan is required");
    }
    if (_emergencyPhone.trim().length != 10) {
      errors.add("Emergency phone must be exactly 10 digits");
    }

    return errors;
  }

  String? _documentNumberError(String value) {
    final rawValue = value.trim();
    final cleanValue = rawValue.replaceAll(RegExp(r'[\s-]'), '');

    if (cleanValue.isEmpty) {
      return "ID number is required";
    }

    switch (_docType) {
      case DocumentType.aadhaar:
        if (!RegExp(r'^\d{12}$').hasMatch(cleanValue)) {
          return "Aadhaar must be exactly 12 digits";
        }
        return null;
      case DocumentType.passport:
        if (!RegExp(r'^[A-Z0-9]{8,12}$').hasMatch(cleanValue.toUpperCase())) {
          return "Passport must be 8-12 alphanumeric characters";
        }
        return null;
      case DocumentType.drivingLicense:
        if (cleanValue.length < 10 || cleanValue.length > 16) {
          return "Driving license number must be 10-16 characters";
        }
        return null;
    }
  }

  String get _documentTypeApiValue {
    switch (_docType) {
      case DocumentType.aadhaar:
        return "AADHAAR";
      case DocumentType.passport:
        return "PASSPORT";
      case DocumentType.drivingLicense:
        return "DRIVING_LICENSE";
    }
  }

  Widget _buildSourceSheet({
    required Function(ImageSource) onSelected,
    String title = "SELECT SOURCE",
    bool allowFiles = false,
  }) {
    return EliteSurface(
      padding: const EdgeInsets.all(AppSpacing.l),
      borderRadius: 30,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: AppSpacing.l),
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.w900, letterSpacing: 1.5)),
          const SizedBox(height: AppSpacing.xl),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _sourceOption(
                icon: Icons.camera_alt_rounded,
                label: "CAMERA",
                onTap: () => onSelected(ImageSource.camera),
              ),
              _sourceOption(
                icon: allowFiles
                    ? Icons.file_present_rounded
                    : Icons.photo_library_rounded,
                label: allowFiles ? "GALLERY/FILE" : "GALLERY",
                onTap: () => onSelected(ImageSource.gallery),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Widget _sourceOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.l),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.primary, size: 30),
          ),
          const SizedBox(height: AppSpacing.s),
          Text(label,
              style: const TextStyle(
                  fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
        ],
      ),
    );
  }

  Future<void> _submitForm() async {
    _formKey.currentState?.save();

    final identityErrors = _identityStepErrors();
    if (identityErrors.isNotEmpty) {
      setState(() => _currentStep = 0);
      _showError(identityErrors.first);
      return;
    }

    if (_photoFile == null) {
      _showError("Profile photo is required");
      return;
    }
    if (_documentFile == null) {
      _showError("Document scan is required");
      return;
    }
    if (_selectedDob == null || _selectedCountry == null) {
      _showError("DOB and Nationality are required");
      return;
    }
    if (_emergencyPhone.trim().length != 10) {
      setState(() => _currentStep = 0);
      _showError("Emergency phone must be exactly 10 digits");
      return;
    }

    final fullName = _fullName.trim();
    final cleanedDocNumber = _docNumber.replaceAll(RegExp(r'[\s-]'), '');
    if (fullName.isEmpty || cleanedDocNumber.isEmpty) {
      setState(() => _currentStep = 0);
      _showError("Full legal name and ID number are required");
      return;
    }

    final dobString = DateFormat('yyyy-MM-dd').format(_selectedDob!);
    final nationalityCode = _selectedCountry!.countryCode;

    final start = DateTime.now();
    final end = DateTime.now().add(const Duration(days: 7));
    if (!end.isAfter(start)) {
      _showError("Trip end date must be after start date");
      return;
    }

    final Map<String, String> fields = {
      "full_name": fullName,
      "document_type": _documentTypeApiValue,
      "document_number": cleanedDocNumber,
      "trip_start_date": start.toIso8601String(),
      "trip_end_date": end.toIso8601String(),
      "destination_state": _selectedState ?? "Uttarakhand",
      "blood_group": _bloodGroup,
      "emergency_contact_name": _emergencyName,
      "emergency_contact_phone": _emergencyPhone,
      "date_of_birth": dobString,
      "nationality": nationalityCode,
      "selected_destinations_json": jsonEncode(_selectedDestinations
          .map((d) => {
                "destination_id": d['id'] ?? d['destination_id'],
                "name": d['name'],
                "visit_date_from": start.toIso8601String(),
                "visit_date_to": end.toIso8601String(),
              })
          .toList()),
    };

    final touristProvider = context.read<TouristProvider>();
    final success = await touristProvider.registerTouristMultipart(
      fields: fields,
      photoPath: _photoFile!.path,
      docPath: _documentFile!.path,
      onProgress: (progress) {
        setState(() => _uploadProgress = progress);
      },
    );

    if (!mounted) return;

    if (success && touristProvider.tourist != null) {
      // Trigger full sync to pull zones and trail graphs for selected destinations
      final touristId = touristProvider.tourist!.touristId;
      final destIds = _selectedDestinations
          .map((d) => (d['id'] ?? d['destination_id']).toString())
          .toList();

      unawaited(locator<SyncEngine>().fullSync(
        touristId: touristId,
        destinationIds: destIds,
      ));

      if (!mounted) return;
      final navigator = Navigator.of(context);
      unawaited(navigator.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const PermissionSetupScreen()),
          (route) => false));
    } else {
      _showError(touristProvider.errorMessage ?? "Registration failed");
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
          const Positioned.fill(child: AuroraBackground()),

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
          if (isLoading)
            LoadingOverlay(
              message: _uploadProgress > 0
                  ? "Uploading Securely... ${(_uploadProgress * 100).toStringAsFixed(0)}%"
                  : "Encrypting ID...",
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 4),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tourist registration',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 19,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Build your safety identity for offline rescue context.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(ThemeData theme) {
    const labels = ['Identity', 'Destination', 'Review'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
      child: EliteSurface(
        padding: const EdgeInsets.all(12),
        borderRadius: 18,
        color: Colors.white.withValues(alpha: 0.09),
        borderColor: AppColors.primary.withValues(alpha: 0.28),
        borderOpacity: 0.28,
        child: Row(
          children: List.generate(labels.length, (index) {
            return Expanded(
              child: _StepTab(
                label: labels[index],
                index: index,
                activeIndex: _currentStep,
              ),
            );
          }),
        ),
      ),
    );
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RegistrationPanel(
          title: 'Profile identity',
          subtitle: 'Use the same details carried on your travel document.',
          child: Column(
            children: [
              Center(
                child: Stack(
                  children: [
                    Container(
                      width: 116,
                      height: 116,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.08),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.35),
                          width: 2,
                        ),
                        image: _photoFile != null
                            ? DecorationImage(
                                image: FileImage(_photoFile!),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: _photoFile == null
                          ? const Icon(Icons.person_add_rounded,
                              size: 40, color: AppColors.primary)
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: FloatingActionButton.small(
                        onPressed: _pickImage,
                        child: const Icon(Icons.camera_alt_rounded),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              _eliteField(
                  label: "FULL LEGAL NAME",
                  icon: Icons.person_rounded,
                  initialValue: _fullName,
                  onChanged: (v) => _fullName = v,
                  onSaved: (v) => _fullName = v?.trim() ?? ''),
              const SizedBox(height: AppSpacing.m),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _buildDropDownField(
                      label: "DOC TYPE",
                      value: _docType.name,
                      items: DocumentType.values.map((e) => e.name).toList(),
                      onChanged: (v) => setState(
                          () => _docType = DocumentType.values.byName(v!)),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.m),
                  Expanded(
                    flex: 3,
                    child: _eliteField(
                        label: "ID NUMBER",
                        icon: Icons.badge_rounded,
                        initialValue: _docNumber,
                        onChanged: (v) => _docNumber = v,
                        onSaved: (v) => _docNumber = v?.trim() ?? ''),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.m),
              Row(
                children: [
                  Expanded(flex: 2, child: _buildDobField(theme)),
                  const SizedBox(width: AppSpacing.m),
                  Expanded(flex: 3, child: _buildNationalityField(theme)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _RegistrationPanel(
          title: 'Emergency readiness',
          subtitle: 'These details are stored for responders during SOS.',
          child: Column(
            children: [
              _DocumentUploadCard(
                documentFile: _documentFile,
                documentName: _documentName,
                onTap: _pickDocument,
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
                  Expanded(flex: 3, child: _buildEmergencyPhoneField(theme)),
                ],
              ),
            ],
          ),
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
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
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
    String? initialValue,
    ValueChanged<String>? onChanged,
  }) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                letterSpacing: 1.5)),
        const SizedBox(height: 8),
        EliteSurface(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
          child: TextFormField(
            initialValue: initialValue,
            onChanged: onChanged,
            onSaved: onSaved,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return "Field is required";
              }
              if (label.contains("ID NUMBER")) {
                return _documentNumberError(value);
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

  Widget _buildDobField(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("DATE OF BIRTH",
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                letterSpacing: 1.5)),
        const SizedBox(height: 8),
        EliteSurface(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
          child: TextFormField(
            readOnly: true,
            controller: TextEditingController(
              text: _selectedDob != null
                  ? DateFormat('yyyy-MM-dd').format(_selectedDob!)
                  : '',
            ),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate:
                    DateTime.now().subtract(const Duration(days: 365 * 18)),
                firstDate: DateTime(1900),
                lastDate: DateTime.now(),
                helpText: 'Select Date of Birth',
              );
              if (picked != null) {
                setState(() => _selectedDob = picked);
              }
            },
            validator: (value) {
              if (_selectedDob == null) {
                return 'Date of Birth is required';
              }
              // Age validation: must be 18+
              final age =
                  DateTime.now().difference(_selectedDob!).inDays ~/ 365;
              if (age < 18) {
                return 'You must be at least 18 years old';
              }
              return null;
            },
            decoration: const InputDecoration(
              border: InputBorder.none,
              icon: Icon(Icons.calendar_today_rounded,
                  color: AppColors.primary, size: 20),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmergencyPhoneField(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("EMERGENCY PHONE",
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                letterSpacing: 1.5)),
        const SizedBox(height: 8),
        EliteSurface(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
          child: TextFormField(
            initialValue: _emergencyPhone,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            onSaved: (value) => _emergencyPhone = value ?? '',
            onChanged: (value) => _emergencyPhone = value,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Emergency phone is required';
              }
              if (value.length != 10) {
                return 'Must be exactly 10 digits';
              }
              if (!RegExp(r'^\d+$').hasMatch(value)) {
                return 'Only numbers allowed';
              }
              return null;
            },
            decoration: const InputDecoration(
              border: InputBorder.none,
              icon: Icon(Icons.phone_android_rounded,
                  color: AppColors.primary, size: 20),
              counterText: '',
              hintText: '10-digit number',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNationalityField(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("NATIONALITY",
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                letterSpacing: 1.5)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () {
            showCountryPicker(
              context: context,
              showPhoneCode: false,
              countryListTheme: CountryListThemeData(
                borderRadius: BorderRadius.circular(20),
                inputDecoration: InputDecoration(
                  labelText: 'Search',
                  hintText: 'Start typing to search...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
              onSelect: (Country country) {
                setState(() {
                  _selectedCountry = country;
                });
              },
            );
          },
          child: EliteSurface(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.m, vertical: AppSpacing.s),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.flag_rounded,
                          color: AppColors.primary, size: 20),
                      const SizedBox(width: AppSpacing.s),
                      Expanded(
                        child: Text(
                          _selectedCountry?.name ?? 'Select your country',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: _selectedCountry != null
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurface
                                    .withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_drop_down,
                    color: AppColors.primary, size: 24),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDestinationStep(ThemeData theme) {
    return _RegistrationPanel(
      title: 'Trip destination',
      subtitle: 'Pick the region and trails so the app can cache zone data.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isLoadingStates)
            const GlimmerLoader(width: double.infinity, height: 48)
          else if (_states.isEmpty)
            const _EmptyDestinationState()
          else
            _buildDropDownField(
              label: "DESTINATION STATE",
              value: _selectedState ?? _states.first,
              items: _states,
              onChanged: (v) => setState(() {
                _selectedState = v;
                _selectedDestinations.clear();
                if (v != null) _fetchDestinations(v);
              }),
            ),
          const SizedBox(height: AppSpacing.l),
          const Text(
            "TRAILS AND ATTRACTIONS",
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: Colors.white60,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          if (_isLoadingDestinations)
            const GlimmerLoader(width: double.infinity, height: 120)
          else if (_availableDestinations.isEmpty)
            const _EmptyDestinationState()
          else
            ..._availableDestinations.map((dest) {
              final isSelected =
                  _selectedDestinations.any((d) => d['id'] == dest['id']);
              return _DestinationChoice(
                destination: dest,
                isSelected: isSelected,
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
              );
            }),
        ],
      ),
    );
  }

  Widget _buildReviewStep(ThemeData theme) {
    return Column(
      children: [
        _RegistrationPanel(
          title: 'Review safety profile',
          subtitle: 'Confirm the details that will support SOS response.',
          child: Column(
            children: [
              _ReviewTile(
                icon: Icons.person_rounded,
                label: 'Identity',
                value: _fullName.isEmpty
                    ? 'Captured after final validation'
                    : _fullName,
                color: AppColors.primary,
              ),
              _ReviewTile(
                icon: Icons.badge_rounded,
                label: 'Document',
                value:
                    '${_docType.name} / ${_docNumber.isEmpty ? 'Pending' : 'Provided'}',
                color: AppColors.info,
              ),
              _ReviewTile(
                icon: Icons.route_rounded,
                label: 'Destination',
                value: _selectedDestinations.isEmpty
                    ? (_selectedState ?? 'State selected')
                    : '${_selectedDestinations.length} selected in ${_selectedState ?? 'state'}',
                color: AppColors.accent,
              ),
              _ReviewTile(
                icon: Icons.bloodtype_rounded,
                label: 'Emergency',
                value:
                    'Blood $_bloodGroup / ${_emergencyPhone.isEmpty ? 'Phone pending' : _emergencyPhone}',
                color: AppColors.danger,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        EliteSurface(
          color: AppColors.success.withValues(alpha: 0.12),
          borderColor: AppColors.success.withValues(alpha: 0.34),
          borderOpacity: 0.34,
          padding: const EdgeInsets.all(14),
          child: const Row(
            children: [
              Icon(Icons.verified_user_rounded, color: AppColors.success),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Your identity and selected route context remain compatible with the existing backend registration flow.",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
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
                  onPressed: isLoading
                      ? null
                      : () {
                          if (_currentStep < 2) {
                            _handleNextStep();
                          } else {
                            _submitForm();
                          }
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
            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
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
        backgroundColor: Colors.black.withValues(alpha: 0.9),
        surfaceTintColor: AppColors.primary,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusL)),
        title: const Row(
          children: [
            Icon(Icons.security_rounded, color: AppColors.primary),
            SizedBox(width: 12),
            Text("PRIVACY PROTOCOL",
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

class _StepTab extends StatelessWidget {
  final String label;
  final int index;
  final int activeIndex;

  const _StepTab({
    required this.label,
    required this.index,
    required this.activeIndex,
  });

  @override
  Widget build(BuildContext context) {
    final active = activeIndex == index;
    final complete = activeIndex > index;
    final color = complete
        ? AppColors.success
        : active
            ? AppColors.primary
            : Colors.white38;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: color.withValues(alpha: active ? 0.45 : 0.18)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            complete ? Icons.check_circle_rounded : Icons.circle_rounded,
            color: color,
            size: complete || active ? 14 : 8,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: active || complete ? Colors.white : Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RegistrationPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _RegistrationPanel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return EliteSurface(
      padding: const EdgeInsets.all(16),
      borderRadius: 22,
      color: Colors.white.withValues(alpha: 0.10),
      borderColor: AppColors.primary.withValues(alpha: 0.24),
      borderOpacity: 0.24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _DocumentUploadCard extends StatelessWidget {
  final File? documentFile;
  final String? documentName;
  final VoidCallback onTap;

  const _DocumentUploadCard({
    required this.documentFile,
    required this.documentName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isPdf = documentName?.toLowerCase().endsWith('.pdf') ?? false;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 118,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.24)),
          image: documentFile != null && !isPdf
              ? DecorationImage(
                  image: FileImage(documentFile!),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: documentFile == null
            ? const _UploadPrompt()
            : isPdf
                ? _PdfPrompt(documentName: documentName ?? 'document.pdf')
                : const Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: EdgeInsets.all(10),
                      child: _SelectedBadge(label: 'Document attached'),
                    ),
                  ),
      ),
    );
  }
}

class _UploadPrompt extends StatelessWidget {
  const _UploadPrompt();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.document_scanner_rounded,
            color: AppColors.primary, size: 34),
        SizedBox(height: 8),
        Text(
          'Scan or upload identity document',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _PdfPrompt extends StatelessWidget {
  final String documentName;

  const _PdfPrompt({required this.documentName});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.picture_as_pdf_rounded,
            color: AppColors.danger, size: 38),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Text(
            documentName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _SelectedBadge extends StatelessWidget {
  final String label;

  const _SelectedBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _DestinationChoice extends StatelessWidget {
  final dynamic destination;
  final bool isSelected;
  final ValueChanged<bool?> onChanged;

  const _DestinationChoice({
    required this.destination,
    required this.isSelected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final name = '${destination['name'] ?? 'Destination'}';
    final district = '${destination['district'] ?? 'District'}';
    final altitude = '${destination['altitude_m'] ?? '--'}';

    return EliteSurface(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      borderRadius: 16,
      color: isSelected
          ? AppColors.primary.withValues(alpha: 0.16)
          : Colors.white.withValues(alpha: 0.07),
      borderColor: isSelected
          ? AppColors.primary.withValues(alpha: 0.45)
          : Colors.white.withValues(alpha: 0.12),
      borderOpacity: isSelected ? 0.45 : 0.12,
      child: CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: isSelected,
        activeColor: AppColors.primary,
        onChanged: onChanged,
        title: Text(
          name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 13,
          ),
        ),
        subtitle: Text(
          '$district / Altitude ${altitude}m',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _EmptyDestinationState extends StatelessWidget {
  const _EmptyDestinationState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: const Text(
        'Destination data is not available yet. You can continue and the app will use the selected state fallback.',
        style: TextStyle(
          color: Colors.white70,
          fontSize: 12,
          height: 1.35,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _ReviewTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
