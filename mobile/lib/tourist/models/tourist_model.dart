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

  factory DestinationVisit.fromJson(Map<String, dynamic> json) => DestinationVisit(
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

  // ignore: prefer_constructors_over_static_methods
  static Tourist fromJson(Map<String, dynamic> json) {
    // Safely parse document type — default to AADHAAR if unknown value received
    final rawDocType = json["document_type"] as String? ?? "AADHAAR";
    final docType = DocumentType.values.firstWhere(
      (e) => e.name.toUpperCase() == rawDocType.toUpperCase(),
      orElse: () => DocumentType.aadhaar,
    );

    return Tourist(
      touristId: json["tourist_id"] as String,
      fullName: json["full_name"] as String? ?? "",
      documentType: docType,
      documentNumber: json["document_number"] as String? ?? "",
      // FIX BUG 1+2: photo_base64 is absent in multipart responses (uses
      // photo_object_key instead). Null-coerce to empty string to prevent
      // a crash that silently triggered the offline fallback path.
      photoBase64: json["photo_base64"] as String? ?? "",
      emergencyContactName: json["emergency_contact_name"] as String? ?? "",
      emergencyContactPhone: json["emergency_contact_phone"] as String? ?? "",
      tripStartDate: DateTime.parse(json["trip_start_date"] as String),
      tripEndDate: DateTime.parse(json["trip_end_date"] as String),
      destinationState: json["destination_state"] as String? ?? "Uttarakhand",
      qrData: json["qr_data"] as String? ?? "",
      createdAt: DateTime.tryParse(json["created_at"] as String? ?? "") ?? DateTime.now(),
      bloodGroup: json["blood_group"] as String? ?? "Unknown",
      selectedDestinations: json["selected_destinations"] != null
          ? List<DestinationVisit>.from(
              (json["selected_destinations"] as List).map(
                (x) => DestinationVisit.fromJson(x as Map<String, dynamic>),
              ),
            )
          : [],
      connectivityLevel: json["connectivity_level"] as String?,
      offlineModeRequired: json["offline_mode_required"] as bool? ?? false,
      geoFenceZones: json["geo_fence_zones"] != null
          ? List<dynamic>.from(json["geo_fence_zones"] as List)
          : [],
      destinationEmergencyContacts:
          (json["emergency_contacts"] as Map<String, dynamic>?) ?? {},
      riskLevel: json["risk_level"] as String? ?? "LOW",
      // FIX BUG 2: tuid is returned by backend — ensure it is captured.
      tuid: json["tuid"] as String?,
      photoObjectKey: json["photo_object_key"] as String?,
      documentObjectKey: json["document_object_key"] as String?,
      isSynced: json["is_synced"] as bool? ?? true,
      registrationFields: json["registration_fields"] != null
          ? Map<String, String>.from(json["registration_fields"] as Map)
          : null,
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
        "selected_destinations": List<dynamic>.from(selectedDestinations.map((x) => x.toJson())),
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
      'selectedDestinations': jsonEncode(selectedDestinations.map((x) => x.toJson()).toList()),
      'connectivityLevel': connectivityLevel,
      'offlineModeRequired': offlineModeRequired ? 1 : 0,
      'geoFenceZones': jsonEncode(geoFenceZones),
      'destinationEmergencyContacts': jsonEncode(destinationEmergencyContacts),
      'riskLevel': riskLevel,
      'tuid': tuid,
      'photoObjectKey': photoObjectKey,
      'documentObjectKey': documentObjectKey,
      'isSynced': isSynced ? 1 : 0,
      'registrationFields': registrationFields != null ? jsonEncode(registrationFields) : null,
    };
  }

  factory Tourist.fromMap(Map<String, dynamic> map) {
    return Tourist(
      touristId: map['touristId'],
      fullName: map['fullName'],
      documentType: DocumentType.values.firstWhere((e) => e.name.toUpperCase() == (map['documentType'] as String).toUpperCase()),
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
          ? List<DestinationVisit>.from(jsonDecode(map['selectedDestinations']).map((x) => DestinationVisit.fromJson(x)))
          : [],
      connectivityLevel: map['connectivityLevel'],
      offlineModeRequired: map['offlineModeRequired'] == 1,
      geoFenceZones: map['geoFenceZones'] != null ? jsonDecode(map['geoFenceZones']) : [],
      destinationEmergencyContacts: map['destinationEmergencyContacts'] != null ? jsonDecode(map['destinationEmergencyContacts']) : {},
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
