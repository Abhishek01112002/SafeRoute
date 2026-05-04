// lib/providers/tourist_provider.dart
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saferoute/tourist/models/tourist_model.dart';
import 'package:saferoute/services/api_service.dart';
import 'package:saferoute/services/database_service.dart';
import 'package:saferoute/services/sync_service.dart';
import 'package:saferoute/services/secure_storage_service.dart';
import 'package:saferoute/services/analytics_service.dart';
import 'package:uuid/uuid.dart';
import 'package:saferoute/core/service_locator.dart';

class TouristProvider with ChangeNotifier {
  Tourist? _tourist;
  UserState _userState = UserState.guest;
  String? _guestSessionId;
  bool _isLoading = false;
  String? _errorMessage;
  bool _isOnline = true;

  // Security Hardening - Aligned with Backend (15 min lockout)
  int _failedLoginAttempts = 0;
  DateTime? _lockUntil;
  final int _maxFailedAttempts = 5;
  final Duration _lockDuration = const Duration(minutes: 15);  // Sync with backend

  Tourist? get tourist => _tourist;
  UserState get userState => _userState;
  String? get guestSessionId => _guestSessionId;
  bool get isLoading => _isLoading;
  bool get isOnline => _isOnline;
  String? get errorMessage => _errorMessage;

  bool get isLocked =>
      _lockUntil != null && DateTime.now().isBefore(_lockUntil!);
  int get remainingLockSeconds =>
      isLocked ? _lockUntil!.difference(DateTime.now()).inSeconds : 0;

  final ApiService _apiService = locator<ApiService>();
  final DatabaseService _dbService = locator<DatabaseService>();

  Future<void> loadTourist() async {
    _isLoading = true;
    notifyListeners();
    try {
      _tourist = await _dbService.getTourist();

      final prefs = await SharedPreferences.getInstance();
      final stateStr = prefs.getString('user_state') ?? 'GUEST';
      _userState = UserState.values.firstWhere(
        (e) => e.name.toUpperCase() == stateStr.toUpperCase(),
        orElse: () => UserState.guest,
      );
      _guestSessionId = prefs.getString('guest_session_id');

      // Enhanced consistency validation and repair
      await _validateAndRepairConsistency();

      // Session Integrity Check
      await _checkSessionIntegrity();

      await checkConnectivity();
    } catch (e) {
      _errorMessage = "Failed to load tourist data";
      debugPrint("LoadTourist Error: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Validates and repairs data consistency between SharedPreferences and Database
  Future<void> _validateAndRepairConsistency() async {
    final prefs = await SharedPreferences.getInstance();
    final isRegistered = prefs.getBool('is_registered') ?? false;
    final touristId = prefs.getString('tourist_id');

    debugPrint(
        "🔍 Consistency Check: isRegistered=$isRegistered, touristId=$touristId, DB_Tourist=${_tourist?.touristId}");

    // Case 1: SharedPreferences says registered but DB is empty
    if (isRegistered && _tourist == null) {
      if (touristId != null) {
        debugPrint(
            "🔄 Consistency Recovery: Registered in prefs but offline DB empty. Re-fetching...");

        final secureStorage = locator<SecureStorageService>();
        final token = await secureStorage.getToken();

        if (token != null && _isOnline) {
          try {
            final response = await _apiService.loginTourist(touristId);
            if (response['tourist'] != null) {
              _tourist = response['tourist'];
              await _dbService.saveTourist(_tourist!);
              debugPrint("✅ Recovery Successful from Backend.");
              return;
            }
          } catch (e) {
            debugPrint("❌ Backend Recovery Failed: $e");
          }
        }
      }

      debugPrint(
          "[!] Critical Data Mismatch: Registered but DB and recovery failed. Attempting re-login...");

      // FIX: Try to re-login with backend before giving up
      if (touristId != null && _isOnline) {
        try {
          final response = await _apiService.loginTourist(touristId);
          if (response['tourist'] != null) {
            _tourist = response['tourist'];
            await _dbService.saveTourist(_tourist!);
            _userState = UserState.authenticated;
            await prefs.setString('user_state', 'AUTHENTICATED');
            debugPrint("[!] Re-login recovery successful for $touristId");
            return;
          }
        } catch (e) {
          debugPrint("[!] Re-login recovery also failed: $e");
        }
      }

      // Only reset to guest if all recovery attempts failed AND we're offline
      debugPrint("[!] All recovery failed. Keeping registered state for offline use.");
      // Don't reset is_registered - the user can still use offline features
      // They'll be prompted to re-authenticate when connectivity returns
      _userState = UserState.registered;
      await prefs.setString('user_state', 'REGISTERED');
      return;
    }

    // Case 2: DB has tourist but SharedPreferences says not registered
    else if (!isRegistered && _tourist != null) {
      debugPrint(
          "🔄 Consistency Repair: DB has tourist but not marked registered in prefs. Fixing...");
      await prefs.setBool('is_registered', true);
      await prefs.setString('tourist_id', _tourist!.touristId);
    }

    // Case 3: ID mismatch between DB and SharedPreferences
    else if (isRegistered &&
        _tourist != null &&
        touristId != null &&
        _tourist!.touristId != touristId) {
      debugPrint(
          "⚠️ ID Mismatch: DB(${_tourist!.touristId}) vs Prefs($touristId). Using DB as source of truth.");
      await prefs.setString('tourist_id', _tourist!.touristId);
    }
  }

  Future<void> _checkSessionIntegrity() async {
    if (_userState == UserState.authenticated ||
        _userState == UserState.registered) {
      final secureStorage = locator<SecureStorageService>();
      final token = await secureStorage.getToken();

      if (token == null) {
        // FIX: Don't immediately downgrade to guest.
        // Token may be temporarily unavailable (Android keystore race condition).
        // Instead, check if we still have tourist data in local DB.
        if (_tourist != null) {
          debugPrint(
              "[!] Session token missing but tourist data exists in DB. Keeping session, will re-auth on next API call.");
          // Keep the session alive - the API interceptor will handle 401 gracefully
          return;
        }

        // Only downgrade if BOTH token AND local DB are empty
        debugPrint(
            "[!] Session integrity failed: No token and no local data. Downgrading to GUEST.");
        await downgradeToGuest();
      }
    }
  }

  Future<void> downgradeToGuest() async {
    _tourist = null;
    _userState = UserState.guest;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_state', 'GUEST');
    await (SecureStorageService()).clear();
    await setGuestMode();
    notifyListeners();
  }

  Future<bool> registerTourist(Map<String, dynamic> data) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    Tourist? tempTourist;

    try {
      // Phase 1: Register with API and validate response
      final response = await _apiService.registerTouristWithToken(data);
      final token = response['token'];
      tempTourist = response['tourist'];

      if (tempTourist == null || token == null) {
        throw Exception('Invalid registration response from server');
      }

      // Phase 2: Save to database FIRST (Ensure persistence before marking registered)
      await _dbService.saveTourist(tempTourist);

      // Phase 3: Update SharedPreferences atomically
      await prefs.setBool('is_registered', true);
      await prefs.setString('tourist_id', tempTourist.touristId);
      await prefs.setString('user_state', 'REGISTERED');

      // Phase 4: Update memory state
      _tourist = tempTourist;
      _userState = UserState.registered;

      locator<AnalyticsService>().logEvent(AnalyticsEvent.onboardingRegisterSuccess,
          properties: {'id': tempTourist.touristId});

      debugPrint('✅ Tourist registered with transaction-based consistency');
      notifyListeners();
      return true;
    } catch (e) {
      // Rollback: Clean up any partial state
      try {
        await prefs.setBool('is_registered', false);
        await prefs.remove('tourist_id');
      } catch (rollbackError) {
        debugPrint('⚠️ Rollback failed: $rollbackError');
      }

      _errorMessage = e.toString();
      debugPrint("Registration Error with rollback: $e");
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Advanced Registration (V3.1): Supports multipart/form-data for production scalability.
  Future<bool> registerTouristMultipart({
    required Map<String, String> fields,
    required String photoPath,
    required String docPath,
    Function(double)? onProgress,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // 1. Attempt Upload to Backend
      final response = await _apiService.registerTouristMultipart(
        fields: fields,
        photoPath: photoPath,
        docPath: docPath,
        onProgress: onProgress,
      );

      final Tourist? tempTourist = response['tourist'];
      final String? token = response['token'];

      if (tempTourist == null || token == null) {
        throw Exception('Server failed to initialize identity protocol');
      }

      // 2. Persistent Storage (FAANG-grade consistency)
      await _dbService.saveTourist(tempTourist);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_registered', true);
      await prefs.setString('tourist_id', tempTourist.touristId);
      // FIX BUG 1: Set AUTHENTICATED (not REGISTERED) so the session
      // integrity check passes and SOS / all API calls use the real JWT.
      await prefs.setString('user_state', 'AUTHENTICATED');
      // FIX BUG 1: Mark onboarding complete so bootstrap routes to MainScreen
      // on next cold start instead of showing OnboardingScreen again.
      await prefs.setBool('onboarding_completed', true);

      _tourist = tempTourist;
      _userState = UserState.authenticated;

      locator<AnalyticsService>().logEvent(AnalyticsEvent.onboardingRegisterSuccess,
          properties: {'id': tempTourist.touristId, 'method': 'multipart'});

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint("Registration (Multipart) API failed: $e. Falling back to offline mode.");

      // OFFLINE FALLBACK (Issue #15.2): Save locally for background sync
      final String tempId = "TID-OFFLINE-${DateTime.now().millisecondsSinceEpoch}";
      final offlineTourist = Tourist(
        touristId: tempId,
        fullName: fields['full_name'] ?? "Unknown",
        documentType: DocumentType.values.firstWhere(
            (e) => e.name.toUpperCase() == (fields['document_type'] ?? '').toUpperCase(),
            orElse: () => DocumentType.aadhaar),
        documentNumber: fields['document_number'] ?? "",
        photoBase64: "", // We have photoPath instead
        emergencyContactName: fields['emergency_contact_name'] ?? "",
        emergencyContactPhone: fields['emergency_contact_phone'] ?? "",
        tripStartDate: DateTime.tryParse(fields['trip_start_date'] ?? "") ?? DateTime.now(),
        tripEndDate: DateTime.tryParse(fields['trip_end_date'] ?? "") ?? DateTime.now().add(const Duration(days: 7)),
        destinationState: fields['destination_state'] ?? "Uttarakhand",
        qrData: "OFFLINE-ID-$tempId",
        createdAt: DateTime.now(),
        bloodGroup: fields['blood_group'] ?? "Unknown",
        isSynced: false,
        registrationFields: {
          ...fields,
          'local_photo_path': photoPath,
          'local_doc_path': docPath,
        },
      );

      await _dbService.saveTourist(offlineTourist);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_registered', true);
      await prefs.setString('tourist_id', tempId);
      await prefs.setString('user_state', 'REGISTERED'); // Let them in, but restricted

      _tourist = offlineTourist;
      _userState = UserState.registered;

      _errorMessage = "Registered offline. Identity will sync when online.";
      notifyListeners();
      return true; // Return true because they are successfully registered LOCALLY
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> checkConnectivity() async {
    final ConnectivityResult result = await Connectivity().checkConnectivity();
    final bool wasOffline = !_isOnline;
    _isOnline = result != ConnectivityResult.none;

    if (_isOnline) {
      unawaited(_apiService.checkServerHealth().then((connected) {
        debugPrint("Backend Server Reachable: $connected");
        if (connected && wasOffline) {
          unawaited(locator<SyncService>().syncOfflineData());
        }
      }));
    }
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> setGuestMode() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      _guestSessionId = const Uuid().v4();
      _userState = UserState.guest;

      await prefs.setBool('onboarding_completed', true);
      await prefs.setString('user_state', 'GUEST');
      await prefs.setString('guest_session_id', _guestSessionId!);

      locator<AnalyticsService>().logEvent(AnalyticsEvent.onboardingSkip,
          properties: {'session_id': _guestSessionId});

      debugPrint('🛡️ Guest mode activated: $_guestSessionId');
    } catch (e) {
      _errorMessage = "Failed to set guest mode";
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> loginTouristSecure(String touristId) async {
    if (isLocked) {
      _errorMessage =
          "Account locked. Try again in $remainingLockSeconds seconds.";
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _apiService.loginTourist(touristId);
      if (response['tourist'] != null) {
        _tourist = response['tourist'];
        _userState = UserState.authenticated;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_registered', true);
        await prefs.setString('tourist_id', _tourist!.touristId);
        await prefs.setString('user_state', 'AUTHENTICATED');
        await prefs.setBool('onboarding_completed', true);

        await _dbService.saveTourist(_tourist!);

        _failedLoginAttempts = 0;
        _lockUntil = null;
        locator<AnalyticsService>().logEvent(AnalyticsEvent.onboardingLoginSuccess,
            properties: {'id': touristId});

        notifyListeners();
        return true;
      }

      _handleFailedLogin();
      return false;
    } on RateLimitException catch (e) {
      // Backend enforced lockout - sync with it
      if (e.retryAfter != null) {
        _lockUntil = DateTime.now().add(e.retryAfter!);
        _failedLoginAttempts = 0;  // Reset counter as backend is now enforcing
        _errorMessage = "Account temporarily locked due to failed attempts. Try again in ${e.retryAfter!.inMinutes} minutes.";
      } else {
        _handleFailedLogin();
      }
      return false;
    } on ApiException catch (e) {
      // Check if error contains remaining_attempts info
      if (e.message.contains('remaining_attempts')) {
        _handleFailedLogin();
        _errorMessage = "Invalid tourist ID. ${_maxFailedAttempts - _failedLoginAttempts} attempts remaining.";
      } else {
        _handleFailedLogin();
        _errorMessage = "Login failed: ${e.message}";
      }
      return false;
    } catch (e) {
      _handleFailedLogin();
      _errorMessage = "Login failed: $e";
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _dbService.deleteTourist();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    final secureStorage = locator<SecureStorageService>();
    await secureStorage.clear();
    _tourist = null;
    _userState = UserState.guest;
    notifyListeners();

    await setGuestMode();
  }

  void _handleFailedLogin() {
    _failedLoginAttempts++;
    locator<AnalyticsService>().logEvent(AnalyticsEvent.onboardingLoginFailure,
        properties: {'attempt': _failedLoginAttempts});

    if (_failedLoginAttempts >= _maxFailedAttempts) {
      _lockUntil = DateTime.now().add(_lockDuration);
      _failedLoginAttempts = 0;
      _errorMessage = "Too many failed attempts. Account locked for 15 minutes.";
      debugPrint(
          "🚨 Security: Brute force protection triggered. Locked for 15 minutes.");
    } else {
      _errorMessage = "Invalid tourist ID. Attempt $_failedLoginAttempts of $_maxFailedAttempts.";
    }
  }

  Future<void> completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', true);
    debugPrint("✅ Onboarding marked as completed.");
  }
}
