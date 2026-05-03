// lib/services/identity_service.dart
import 'dart:convert';
import 'package:crypto/crypto.dart';

class IdentityService {
  // MUST match _TUID_SALT in backend/app/services/identity_service.py
  static const String _tuidSalt = String.fromEnvironment(
    'SAFEROUTE_TUID_SALT',
    defaultValue: "SR_IDENTITY_V1_UTTARAKHAND_2025",
  );

  /// Generates a Cryptographic TUID for offline creation/verification.
  /// Uses double SHA-256 for collision resistance and irreversibility.
  ///
  /// [docType] e.g., "AADHAAR", "PASSPORT"
  /// [docNumber] e.g., "123456789012"
  /// [dob] YYYY-MM-DD
  /// [nationality] ISO 3166-1 alpha-2, e.g., "IN"
  static String generateTuid(
    String docType,
    String docNumber,
    String dob,
    String nationality,
  ) {
    // 1. Normalize formatting
    final nType = docType.trim().toUpperCase();
    final nNum = docNumber.trim().toUpperCase();
    final nDob = dob.trim();
    final nNat = nationality.trim().toUpperCase();

    // 2. Concatenate with salt
    final rawString = "$nType:$nNum:$nDob:$nNat:$_tuidSalt";

    // 3. Double SHA-256
    final firstHashBytes = sha256.convert(utf8.encode(rawString)).bytes;
    final firstHashHex = _bytesToHex(firstHashBytes);

    final secondHashBytes = sha256.convert(utf8.encode(firstHashHex)).bytes;
    final secondHashHex = _bytesToHex(secondHashBytes);

    // 4. Format: SR-{NAT}-{YY}-{12 chars of hash}
    final yearSuffix = DateTime.now().year.toString().substring(2);
    final uniqueSuffix = secondHashHex.substring(0, 12).toUpperCase();

    return "SR-$nNat-$yearSuffix-$uniqueSuffix";
  }

  /// Hashes a document number for secure local storage if needed.
  static String hashDocumentNumber(String docNumber) {
    final bytes = utf8.encode(docNumber.trim().toUpperCase());
    return sha256.convert(bytes).toString();
  }

  static String _bytesToHex(List<int> bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
