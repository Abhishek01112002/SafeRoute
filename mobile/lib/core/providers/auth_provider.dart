// lib/providers/auth_provider.dart
import 'package:flutter/material.dart';
import 'package:saferoute/services/secure_storage_service.dart';
import 'package:saferoute/core/service_locator.dart';

class AuthProvider with ChangeNotifier {
  final SecureStorageService _secureStorage = locator<SecureStorageService>();

  String? _token;
  String? _touristId;
  bool _isLoggedIn = false;
  bool _isLoading = false;
  String? _errorMessage;

  // Getters
  String? get token => _token;
  String? get touristId => _touristId;
  bool get isLoggedIn => _isLoggedIn;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Initialize auth state from secure storage
  Future<void> initializeAuth() async {
    _isLoading = true;
    notifyListeners();

    try {
      final token = await _secureStorage.getToken();
      final touristId = await _secureStorage.getTouristId();

      if (token != null && touristId != null) {
        _token = token;
        _touristId = touristId;

        // Check if token is expired
        final isExpired = await _secureStorage.isTokenExpired();
        if (!isExpired) {
          _isLoggedIn = true;
          debugPrint('✅ Auth restored from storage');
        } else {
          // Token expired, clear it
          await logout();
        }
      }
    } catch (e) {
      debugPrint('❌ Error initializing auth: $e');
      _errorMessage = 'Failed to initialize auth';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Login with token (called after registration or login API call)
  Future<void> loginWithToken({
    required String token,
    required String touristId,
  }) async {
    try {
      _token = token;
      _touristId = touristId;

      // Save to secure storage
      await _secureStorage.saveToken(token);
      await _secureStorage.saveTouristId(touristId);

      _isLoggedIn = true;
      _errorMessage = null;

      debugPrint('✅ User logged in: $touristId');
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to save auth token';
      debugPrint('❌ Error during login: $e');
      notifyListeners();
    }
  }

  /// Logout
  Future<void> logout() async {
    try {
      await _secureStorage.clearAuthData();
      _token = null;
      _touristId = null;
      _isLoggedIn = false;
      _errorMessage = null;

      debugPrint('✅ User logged out');
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to logout';
      debugPrint('❌ Error during logout: $e');
      notifyListeners();
    }
  }

  /// Refresh token
  Future<void> refreshToken(String newToken) async {
    try {
      _token = newToken;
      await _secureStorage.saveToken(newToken);
      debugPrint('✅ Token refreshed');
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to refresh token';
      debugPrint('❌ Error refreshing token: $e');
      notifyListeners();
    }
  }

  /// Set error message
  void setError(String message) {
    _errorMessage = message;
    notifyListeners();
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
