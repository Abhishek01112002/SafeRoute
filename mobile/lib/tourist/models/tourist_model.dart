// lib/models/tourist_model.dart
import 'dart:convert';

enum DocumentType { aadhaar, passport, drivingLicense }

enum UserState { guest, authenticated, registered }

class DestinationVisit {
  final String destinationId;
  final String name;
  final DateTime visitDateFrom;
  final DateTime visitDateTo;

  DestinationVisit({
    required this.destinationId,
    required this.name,
    required this.visitDateFrom,
    required this.visitDateTo,
  });

  factory DestinationVisit.fromJson(Map<String, dynamic> json) =>
      DestinationVisit(
        destinationId: json["destination_id"],
        name: json["name"],
        visitDateFrom: DateTime.parse(json["visit_date_from"]),
        visitDateTo: DateTime.parse(json["visit_date_to"]),
      );

  Map<String, dynamic> toJson() => {
        "destination_id": destinationId,
        "name": name,
        "visit_date_from": visitDateFrom.toIso8601String(),
        "visit_date_to": visitDateTo.toIso8601String(),
      };
}

class Tourist {
  final String touristId;
  final String fullName;
  final DocumentType documentType;
  final String documentNumber;
  final String photoBase64;
  final String emergencyContactName;
  final String emergencyContactPhone;
  final DateTime tripStartDate;
  final DateTime tripEndDate;
  final String destinationState;
  final String qrData;
  final DateTime createdAt;
  final String bloodGroup;

  // New Fields
  final List<DestinationVisit> selectedDestinations;
  final String? connectivityLevel;
  final bool offlineModeRequired;
  final List<dynamic> geoFenceZones;
  final Map<String, dynamic> destinationEmergencyContacts;
  final String riskLevel;
  final String? tuid;
  final String? photoObjectKey;
  final String? documentObjectKey;
  final bool isSynced;
  final Map<String, String>? registrationFields;

  Tourist({
    required this.touristId,
    required this.fullName,
    required this.documentType,
    required this.documentNumber,
    required this.photoBase64,
    required this.emergencyContactName,
    required this.emergencyContactPhone,
    required this.tripStartDate,
    required this.tripEndDate,
    required this.destinationState,
    required this.qrData,
    required this.createdAt,
    required this.bloodGroup,
    this.selectedDestinations = const [],
    this.connectivityLevel,
    this.offlineModeRequired = false,
    this.geoFenceZones = const [],
    this.destinationEmergencyContacts = const {},
    this.riskLevel = "LOW",
    this.tuid,
    this.photoObjectKey,
    this.documentObjectKey,
    this.isSynced = true,
    this.registrationFields,
  });

  static String _readString(
    Map<String, dynamic> json,
    String key, {
    String fallback = "",
  }) {
    final value = json[key];
    if (value == null) {
      return fallback;
    }
    return value.toString();
  }

  static bool _readBool(
    Map<String, dynamic> json,
    String key, {
    bool fallback = false,
  }) {
    final value = json[key];
    if (value == null) {
      return fallback;
    }
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (['true', '1', 'yes', 'y'].contains(normalized)) {
        return true;
      }
      if (['false', '0', 'no', 'n'].contains(normalized)) {
        return false;
      }
    }
    return fallback;
  }

  static DateTime _readDateTime(
    Map<String, dynamic> json,
    String key, {
    DateTime? fallback,
  }) {
    final value = json[key];
    if (value == null) {
      return fallback ?? DateTime.now();
    }
    return DateTime.tryParse(value.toString()) ?? fallback ?? DateTime.now();
  }

  static List<DestinationVisit> _readDestinations(dynamic value) {
    dynamic normalized = value;
    if (normalized is String && normalized.trim().isNotEmpty) {
      try {
        normalized = jsonDecode(normalized);
      } catch (_) {
        normalized = const [];
      }
    }
    if (normalized is! List) {
      return const [];
    }
    return normalized
        .whereType<Map>()
        .map((x) => DestinationVisit.fromJson(Map<String, dynamic>.from(x)))
        .toList();
  }

  static List<dynamic> _readDynamicList(dynamic value) {
    dynamic normalized = value;
    if (normalized is String && normalized.trim().isNotEmpty) {
      try {
        normalized = jsonDecode(normalized);
      } catch (_) {
        normalized = const [];
      }
    }
    return normalized is List ? List<dynamic>.from(normalized) : const [];
  }

  static Map<String, dynamic> _readDynamicMap(dynamic value) {
    dynamic normalized = value;
    if (normalized is String && normalized.trim().isNotEmpty) {
      try {
        normalized = jsonDecode(normalized);
      } catch (_) {
        normalized = const {};
      }
    }
    return normalized is Map ? Map<String, dynamic>.from(normalized) : const {};
  }

  static Map<String, String>? _readRegistrationFields(dynamic value) {
    if (value == null) {
      return null;
    }
    dynamic normalized = value;
    if (normalized is String && normalized.trim().isNotEmpty) {
      try {
        normalized = jsonDecode(normalized);
      } catch (_) {
        return null;
      }
    }
    if (normalized is! Map) {
      return null;
    }
    return normalized.map(
      (key, fieldValue) => MapEntry(key.toString(), fieldValue.toString()),
    );
  }

  // ignore: prefer_constructors_over_static_methods
  static Tourist fromJson(Map<String, dynamic> json) {
    // Safely parse document type — default to AADHAAR if unknown value received
    final rawDocType = _readString(json, "document_type", fallback: "AADHAAR");
    final docType = DocumentType.values.firstWhere(
      (e) => e.name.toUpperCase() == rawDocType.toUpperCase(),
      orElse: () => DocumentType.aadhaar,
    );

    return Tourist(
      touristId: _readString(json, "tourist_id"),
      fullName: _readString(json, "full_name"),
      documentType: docType,
      documentNumber: _readString(json, "document_number"),
      // FIX BUG 1+2: photo_base64 is absent in multipart responses (uses
      // photo_object_key instead). Null-coerce to empty string to prevent
      // a crash that silently triggered the offline fallback path.
      photoBase64: _readString(json, "photo_base64"),
      emergencyContactName: _readString(json, "emergency_contact_name"),
      emergencyContactPhone: _readString(json, "emergency_contact_phone"),
      tripStartDate: _readDateTime(json, "trip_start_date"),
      tripEndDate: _readDateTime(json, "trip_end_date"),
      destinationState:
          _readString(json, "destination_state", fallback: "Uttarakhand"),
      qrData: _readString(json, "qr_data"),
      createdAt: _readDateTime(json, "created_at"),
      bloodGroup: _readString(json, "blood_group", fallback: "Unknown"),
      selectedDestinations: _readDestinations(json["selected_destinations"]),
      connectivityLevel: json["connectivity_level"]?.toString(),
      offlineModeRequired: _readBool(json, "offline_mode_required"),
      geoFenceZones: _readDynamicList(json["geo_fence_zones"]),
      destinationEmergencyContacts: _readDynamicMap(json["emergency_contacts"]),
      riskLevel: _readString(json, "risk_level", fallback: "LOW"),
      // FIX BUG 2: tuid is returned by backend — ensure it is captured.
      tuid: json["tuid"]?.toString(),
      photoObjectKey: json["photo_object_key"]?.toString(),
      documentObjectKey: json["document_object_key"]?.toString(),
      isSynced: _readBool(json, "is_synced", fallback: true),
      registrationFields: _readRegistrationFields(json["registration_fields"]),
    );
  }

  Map<String, dynamic> toJson() => {
        "tourist_id": touristId,
        "full_name": fullName,
        "document_type": documentType.name.toUpperCase(),
        "document_number": documentNumber,
        "photo_base64": photoBase64,
        "emergency_contact_name": emergencyContactName,
        "emergency_contact_phone": emergencyContactPhone,
        "trip_start_date": tripStartDate.toIso8601String(),
        "trip_end_date": tripEndDate.toIso8601String(),
        "destination_state": destinationState,
        "qr_data": qrData,
        "created_at": createdAt.toIso8601String(),
        "blood_group": bloodGroup,
        "selected_destinations":
            List<dynamic>.from(selectedDestinations.map((x) => x.toJson())),
        "connectivity_level": connectivityLevel,
        "offline_mode_required": offlineModeRequired,
        "geo_fence_zones": geoFenceZones,
        "emergency_contacts": destinationEmergencyContacts,
        "risk_level": riskLevel,
        "tuid": tuid,
        "photo_object_key": photoObjectKey,
        "document_object_key": documentObjectKey,
        "is_synced": isSynced,
        "registration_fields": registrationFields,
      };

  Map<String, dynamic> toMap() {
    return {
      'touristId': touristId,
      'fullName': fullName,
      'documentType': documentType.name.toUpperCase(),
      'documentNumber': documentNumber,
      'photoBase64': photoBase64,
      'emergencyContactName': emergencyContactName,
      'emergencyContactPhone': emergencyContactPhone,
      'tripStartDate': tripStartDate.millisecondsSinceEpoch,
      'tripEndDate': tripEndDate.millisecondsSinceEpoch,
      'destinationState': destinationState,
      'qrData': qrData,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'bloodGroup': bloodGroup,
      // Complex fields serialized for SQLite
      'selectedDestinations':
          jsonEncode(selectedDestinations.map((x) => x.toJson()).toList()),
      'connectivityLevel': connectivityLevel,
      'offlineModeRequired': offlineModeRequired ? 1 : 0,
      'geoFenceZones': jsonEncode(geoFenceZones),
      'destinationEmergencyContacts': jsonEncode(destinationEmergencyContacts),
      'riskLevel': riskLevel,
      'tuid': tuid,
      'photoObjectKey': photoObjectKey,
      'documentObjectKey': documentObjectKey,
      'isSynced': isSynced ? 1 : 0,
      'registrationFields':
          registrationFields != null ? jsonEncode(registrationFields) : null,
    };
  }

  factory Tourist.fromMap(Map<String, dynamic> map) {
    return Tourist(
      touristId: map['touristId'],
      fullName: map['fullName'],
      documentType: DocumentType.values.firstWhere((e) =>
          e.name.toUpperCase() ==
          (map['documentType'] as String).toUpperCase()),
      documentNumber: map['documentNumber'],
      photoBase64: map['photoBase64'],
      emergencyContactName: map['emergencyContactName'],
      emergencyContactPhone: map['emergencyContactPhone'],
      tripStartDate: DateTime.fromMillisecondsSinceEpoch(map['tripStartDate']),
      tripEndDate: DateTime.fromMillisecondsSinceEpoch(map['tripEndDate']),
      destinationState: map['destinationState'],
      qrData: map['qrData'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt']),
      bloodGroup: map['bloodGroup'] ?? "Unknown",
      selectedDestinations: map['selectedDestinations'] != null
          ? List<DestinationVisit>.from(jsonDecode(map['selectedDestinations'])
              .map((x) => DestinationVisit.fromJson(x)))
          : [],
      connectivityLevel: map['connectivityLevel'],
      offlineModeRequired: map['offlineModeRequired'] == 1,
      geoFenceZones:
          map['geoFenceZones'] != null ? jsonDecode(map['geoFenceZones']) : [],
      destinationEmergencyContacts: map['destinationEmergencyContacts'] != null
          ? jsonDecode(map['destinationEmergencyContacts'])
          : {},
      riskLevel: map['riskLevel'] ?? "LOW",
      tuid: map['tuid'],
      photoObjectKey: map['photoObjectKey'],
      documentObjectKey: map['documentObjectKey'],
      isSynced: map['isSynced'] == 1,
      registrationFields: map['registrationFields'] != null
          ? Map<String, String>.from(jsonDecode(map['registrationFields']))
          : null,
    );
  }
}
