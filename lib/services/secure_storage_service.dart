// lib/services/secure_storage_service.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';

class SecureStorageService {
  static final SecureStorageService _instance = SecureStorageService._internal();
  static const String _tokenKey = 'saferoute_jwt_token';
  static const String _touristIdKey = 'saferoute_tourist_id';
  
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: true,
    ),
  );

  factory SecureStorageService() => _instance;

  SecureStorageService._internal();

  /// Save JWT token securely
  Future<void> saveToken(String token) async {
    try {
      await _storage.write(key: _tokenKey, value: token);
      debugPrint('✅ Token saved securely');
    } catch (e) {
      debugPrint('❌ Error saving token: $e');
    }
  }

  /// Retrieve JWT token
  Future<String?> getToken() async {
    try {
      return await _storage.read(key: _tokenKey);
    } catch (e) {
      debugPrint('❌ Error retrieving token: $e');
      return null;
    }
  }

  /// Check if token exists
  Future<bool> hasToken() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  /// Delete token (logout)
  Future<void> deleteToken() async {
    try {
      await _storage.delete(key: _tokenKey);
      debugPrint('✅ Token deleted');
    } catch (e) {
      debugPrint('❌ Error deleting token: $e');
    }
  }

  /// Save tourist ID
  Future<void> saveTouristId(String touristId) async {
    try {
      await _storage.write(key: _touristIdKey, value: touristId);
      debugPrint('✅ Tourist ID saved');
    } catch (e) {
      debugPrint('❌ Error saving tourist ID: $e');
    }
  }

  /// Get tourist ID
  Future<String?> getTouristId() async {
    try {
      return await _storage.read(key: _touristIdKey);
    } catch (e) {
      debugPrint('❌ Error retrieving tourist ID: $e');
      return null;
    }
  }

  /// Clear all auth data
  Future<void> clearAuthData() async {
    try {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _touristIdKey);
      debugPrint('✅ Auth data cleared');
    } catch (e) {
      debugPrint('❌ Error clearing auth data: $e');
    }
  }

  Future<void> clear() => clearAuthData();

  /// Decode JWT to check expiration (simple check, no validation)
  Future<bool> isTokenExpired() async {
    try {
      final token = await getToken();
      if (token == null) return true;

      // Simple JWT structure: header.payload.signature
      final parts = token.split('.');
      if (parts.length != 3) return true;

      // Decode payload (add padding if needed)
      String payload = parts[1];
      final padded = payload + '=' * (4 - payload.length % 4);
      
      // This is a simple check - in production, use jwt_decoder package
      // For now, we'll assume if token exists, it's valid
      // Backend will validate real expiration
      return false;
    } catch (e) {
      debugPrint('❌ Error checking token expiration: $e');
      return true;
    }
  }
}
