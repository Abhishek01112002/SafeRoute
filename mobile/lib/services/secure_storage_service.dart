// lib/services/secure_storage_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static final SecureStorageService _instance = SecureStorageService._internal();
  static const String _tokenKey = 'saferoute_jwt_token';
  static const String _refreshTokenKey = 'saferoute_refresh_token';
  static const String _touristIdKey = 'saferoute_tourist_id';
  static const String _tuidKey = 'saferoute_tuid';
  static const String _meshSecretKey = 'saferoute_mesh_secret';
  static const String _meshKeyVersionKey = 'saferoute_mesh_key_version';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: false,  // FIX: Don't wipe keystore on error - prevents guest mode fallback
    ),
  );

  factory SecureStorageService() => _instance;

  SecureStorageService._internal();

  // -------------------------------------------------------------------------
  // ACCESS TOKEN
  // -------------------------------------------------------------------------

  /// Save JWT token securely
  Future<void> saveToken(String token) async {
    try {
      await _storage.write(key: _tokenKey, value: token);
      debugPrint('✅ Token saved securely');
    } catch (e) {
      debugPrint('❌ Error saving token: $e');
    }
  }

  /// Retrieve JWT token (FIX #7: validates structure, auto-clears if corrupted)
  Future<String?> getToken() async {
    try {
      final token = await _storage.read(key: _tokenKey);
      if (token == null || token.isEmpty) return null;

      // Validate: must be 'offline-token' or a valid 3-part JWT
      if (token != 'offline-token' && token.split('.').length != 3) {
        debugPrint('🛑 Corrupted token detected in storage. Auto-clearing.');
        await _safeDelete(_tokenKey);
        return null;
      }
      return token;
    } catch (e) {
      debugPrint('❌ Error retrieving token (storage may be corrupted): $e');
      // FIX #7: If storage itself throws, nuke it and recover
      await _emergencyStorageRecovery();
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // REFRESH TOKEN
  // -------------------------------------------------------------------------

  /// Save Refresh token securely
  Future<void> saveRefreshToken(String token) async {
    try {
      await _storage.write(key: _refreshTokenKey, value: token);
      debugPrint('✅ Refresh Token saved securely');
    } catch (e) {
      debugPrint('❌ Error saving refresh token: $e');
    }
  }

  /// Retrieve Refresh token (FIX #7: validates structure)
  Future<String?> getRefreshToken() async {
    try {
      final token = await _storage.read(key: _refreshTokenKey);
      if (token == null || token.isEmpty) return null;

      if (token.split('.').length != 3) {
        debugPrint('🛑 Corrupted refresh token detected. Auto-clearing.');
        await _safeDelete(_refreshTokenKey);
        return null;
      }
      return token;
    } catch (e) {
      debugPrint('❌ Error retrieving refresh token (storage may be corrupted): $e');
      await _emergencyStorageRecovery();
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // TOKEN STATUS
  // -------------------------------------------------------------------------

  /// Check if a valid token exists
  Future<bool> hasToken() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  /// Delete tokens (logout)
  Future<void> deleteToken() async {
    try {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _refreshTokenKey);
      debugPrint('✅ Tokens deleted');
    } catch (e) {
      debugPrint('❌ Error deleting token: $e');
    }
  }

  // -------------------------------------------------------------------------
  // TOURIST ID
  // -------------------------------------------------------------------------

  Future<void> saveTouristId(String touristId) async {
    try {
      await _storage.write(key: _touristIdKey, value: touristId);
      debugPrint('✅ Tourist ID saved');
    } catch (e) {
      debugPrint('❌ Error saving tourist ID: $e');
    }
  }

  Future<String?> getTouristId() async {
    try {
      return await _storage.read(key: _touristIdKey);
    } catch (e) {
      debugPrint('❌ Error retrieving tourist ID: $e');
      return null;
    }
  }

  Future<void> saveTuid(String tuid) async {
    try {
      await _storage.write(key: _tuidKey, value: tuid);
      debugPrint('âœ… TUID saved');
    } catch (e) {
      debugPrint('âŒ Error saving TUID: $e');
    }
  }

  Future<String?> getTuid() async {
    try {
      return await _storage.read(key: _tuidKey);
    } catch (e) {
      debugPrint('âŒ Error retrieving TUID: $e');
      return null;
    }
  }

  Future<void> saveMeshKey({
    required String meshSecret,
    required int keyVersion,
  }) async {
    try {
      await _storage.write(key: _meshSecretKey, value: meshSecret);
      await _storage.write(
        key: _meshKeyVersionKey,
        value: keyVersion.toString(),
      );
      debugPrint('âœ… Mesh key saved');
    } catch (e) {
      debugPrint('âŒ Error saving mesh key: $e');
    }
  }

  Future<String?> getMeshSecret() async {
    try {
      return await _storage.read(key: _meshSecretKey);
    } catch (e) {
      debugPrint('âŒ Error retrieving mesh secret: $e');
      return null;
    }
  }

  Future<int?> getMeshKeyVersion() async {
    try {
      final raw = await _storage.read(key: _meshKeyVersionKey);
      return raw == null ? null : int.tryParse(raw);
    } catch (e) {
      debugPrint('âŒ Error retrieving mesh key version: $e');
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // CLEAR / RECOVERY
  // -------------------------------------------------------------------------

  /// Clear all auth data
  Future<void> clearAuthData() async {
    try {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _refreshTokenKey);
      await _storage.delete(key: _touristIdKey);
      await _storage.delete(key: _tuidKey);
      await _storage.delete(key: _meshSecretKey);
      await _storage.delete(key: _meshKeyVersionKey);
      debugPrint('✅ Auth data cleared');
    } catch (e) {
      debugPrint('❌ Error clearing auth data: $e');
      // If even clearing fails, try the nuclear option
      await _emergencyStorageRecovery();
    }
  }

  Future<void> clear() => clearAuthData();

  /// FIX #7: Emergency recovery when secure storage is completely corrupted.
  /// This wipes ALL keys and returns the app to a clean slate.
  Future<void> _emergencyStorageRecovery() async {
    try {
      debugPrint('🛑 EMERGENCY: Secure storage corrupted. Wiping all keys...');
      await _storage.deleteAll();
      debugPrint('✅ Emergency recovery complete. User must re-authenticate.');
    } catch (e) {
      debugPrint('💀 CRITICAL: Even emergency storage wipe failed: $e');
      // At this point the OS-level keystore is broken.
      // AndroidOptions(resetOnError: true) should handle this on next access.
    }
  }

  /// Safe delete that won't throw
  Future<void> _safeDelete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {
      // Swallow — we're already in error recovery
    }
  }

  // -------------------------------------------------------------------------
  // JWT EXPIRATION CHECK
  // -------------------------------------------------------------------------

  /// Decode JWT to check expiration (simple check, no signature validation)
  Future<bool> isTokenExpired() async {
    try {
      final token = await getToken();
      if (token == null) return true;
      if (token == 'offline-token') return false; // offline tokens never expire

      final parts = token.split('.');
      if (parts.length != 3) return true;

      final payloadJson = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final payload = jsonDecode(payloadJson) as Map<String, dynamic>;
      final exp = payload['exp'];
      if (exp is! num) return true;

      final expiresAt = DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000);
      return DateTime.now().toUtc().isAfter(expiresAt.toUtc());
    } catch (e) {
      debugPrint('❌ Error checking token expiration: $e');
      return true;
    }
  }
}
