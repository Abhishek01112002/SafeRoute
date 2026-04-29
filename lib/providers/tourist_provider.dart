// lib/providers/tourist_provider.dart
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saferoute/models/tourist_model.dart';
import 'package:saferoute/services/api_service.dart';
import 'package:saferoute/services/database_service.dart';
import 'package:saferoute/services/sync_service.dart';
import 'package:saferoute/services/secure_storage_service.dart';

class TouristProvider with ChangeNotifier {
  Tourist? _tourist;
  bool _isLoading = false;
  String? _errorMessage;
  bool _isOnline = true;

  Tourist? get tourist => _tourist;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isOnline => _isOnline;

  final ApiService _apiService = ApiService();
  final DatabaseService _dbService = DatabaseService();

  Future<void> loadTourist() async {
    _isLoading = true;
    notifyListeners();
    try {
      _tourist = await _dbService.getTourist();
      
      if (_tourist == null) {
        final prefs = await SharedPreferences.getInstance();
        final isRegistered = prefs.getBool('is_registered') ?? false;
        final touristId = prefs.getString('tourist_id');
        
        if (isRegistered && touristId != null && _isOnline) {
          debugPrint("🔄 Consistency Recovery: Registered but offline DB empty. Re-fetching...");
          try {
            final response = await _apiService.loginTourist(touristId);
            if (response['tourist'] != null) {
              _tourist = response['tourist'];
              await _dbService.saveTourist(_tourist!);
              debugPrint("✅ Recovery Successful.");
            }
          } catch (e) {
            debugPrint("❌ Recovery Failed: $e");
            // If re-fetch fails and we have no DB, we might need to reset
            await prefs.setBool('is_registered', false);
          }
        } else if (isRegistered) {
          debugPrint("⚠️ Data mismatch: registered but DB empty. Resetting.");
          await prefs.setBool('is_registered', false);
        }
      }
      await checkConnectivity();
    } catch (e) {
      _errorMessage = "Failed to load tourist data";
      debugPrint("LoadTourist Error: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> registerTourist(Map<String, dynamic> data) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // 1. Register with API and get JWT token
      final response = await _apiService.registerTouristWithToken(data);
      final token = response['token'];
      final registeredTourist = response['tourist'];
      
      if (registeredTourist != null && token != null) {
        // 2. Save to SQLite FIRST (Ensure persistence before marking registered)
        // This fixes Case 1: Data mismatch if app crashes during registration
        await _dbService.saveTourist(registeredTourist);

        // 3. Mark as registered in SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_registered', true);
        await prefs.setString('tourist_id', registeredTourist.touristId);
        
        // 4. Update memory state
        _tourist = registeredTourist;
        notifyListeners();

        // 5. Initialize/Start BLE Mesh for the new user (Issue #2)
        // We use a global key or provider finder in production, 
        // but here we expect the caller or main.dart to handle it, 
        // or we can trigger a notification/callback.
        
        // JWT token is already saved in SecureStorage by ApiService
        debugPrint('✅ Tourist registered with JWT auth and persisted to DB');

        return true;
      }
      return false;
    } catch (e) {
      _errorMessage = e.toString();
      debugPrint("Registration Error in Provider: $e");
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> checkConnectivity() async {
    // connectivity_plus v5.x handles ConnectivityResult directly
    final ConnectivityResult result = await Connectivity().checkConnectivity();
    final bool wasOffline = !_isOnline;
    _isOnline = result != ConnectivityResult.none;

    if (_isOnline) {
      _apiService.checkServerHealth().then((connected) {
        debugPrint("Backend Server Reachable: $connected");
        if (connected && wasOffline) {
          // Trigger sync if we just came back online (Issue #7)
          SyncService().syncOfflineData();
        }
      });
    }
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> logout() async {
    await _dbService.deleteTourist();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    final secureStorage = SecureStorageService();
    await secureStorage.clear(); // Ensure JWT is wiped
    _tourist = null;
    notifyListeners();
  }
}
