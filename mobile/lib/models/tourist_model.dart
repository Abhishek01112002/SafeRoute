// lib/models/tourist_model.dart
import 'dart:convert';
import 'package:crypto/crypto.dart';

enum DocumentType { AADHAAR, PASSPORT }

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
  final String blockchainHash;
  final String bloodGroup;

  // New Fields
  final List<DestinationVisit> selectedDestinations;
  final String? connectivityLevel;
  final bool offlineModeRequired;
  final List<dynamic> geoFenceZones;
  final Map<String, dynamic> destinationEmergencyContacts;
  final String riskLevel;

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
    required this.blockchainHash,
    required this.bloodGroup,
    this.selectedDestinations = const [],
    this.connectivityLevel,
    this.offlineModeRequired = false,
    this.geoFenceZones = const [],
    this.destinationEmergencyContacts = const {},
    this.riskLevel = "LOW",
  });

  factory Tourist.fromJson(Map<String, dynamic> json) => Tourist(
        touristId: json["tourist_id"],
        fullName: json["full_name"],
        documentType: DocumentType.values.firstWhere((e) => e.toString().split('.').last == json["document_type"]),
        documentNumber: json["document_number"],
        photoBase64: json["photo_base64"],
        emergencyContactName: json["emergency_contact_name"],
        emergencyContactPhone: json["emergency_contact_phone"],
        tripStartDate: DateTime.parse(json["trip_start_date"]),
        tripEndDate: DateTime.parse(json["trip_end_date"]),
        destinationState: json["destination_state"],
        qrData: json["qr_data"],
        createdAt: DateTime.parse(json["created_at"]),
        blockchainHash: json["blockchain_hash"],
        bloodGroup: json["blood_group"] ?? "Unknown",
        selectedDestinations: json["selected_destinations"] != null 
            ? List<DestinationVisit>.from(json["selected_destinations"].map((x) => DestinationVisit.fromJson(x)))
            : [],
        connectivityLevel: json["connectivity_level"],
        offlineModeRequired: json["offline_mode_required"] ?? false,
        geoFenceZones: json["geo_fence_zones"] != null ? List<dynamic>.from(json["geo_fence_zones"]) : [],
        destinationEmergencyContacts: json["emergency_contacts"] ?? {},
        riskLevel: json["risk_level"] ?? "LOW",
      );

  Map<String, dynamic> toJson() => {
        "tourist_id": touristId,
        "full_name": fullName,
        "document_type": documentType.toString().split('.').last,
        "document_number": documentNumber,
        "photo_base64": photoBase64,
        "emergency_contact_name": emergencyContactName,
        "emergency_contact_phone": emergencyContactPhone,
        "trip_start_date": tripStartDate.toIso8601String(),
        "trip_end_date": tripEndDate.toIso8601String(),
        "destination_state": destinationState,
        "qr_data": qrData,
        "created_at": createdAt.toIso8601String(),
        "blockchain_hash": blockchainHash,
        "blood_group": bloodGroup,
        "selected_destinations": List<dynamic>.from(selectedDestinations.map((x) => x.toJson())),
        "connectivity_level": connectivityLevel,
        "offline_mode_required": offlineModeRequired,
        "geo_fence_zones": geoFenceZones,
        "emergency_contacts": destinationEmergencyContacts,
        "risk_level": riskLevel,
      };

  Map<String, dynamic> toMap() {
    return {
      'touristId': touristId,
      'fullName': fullName,
      'documentType': documentType.toString().split('.').last,
      'documentNumber': documentNumber,
      'photoBase64': photoBase64,
      'emergencyContactName': emergencyContactName,
      'emergencyContactPhone': emergencyContactPhone,
      'tripStartDate': tripStartDate.millisecondsSinceEpoch,
      'tripEndDate': tripEndDate.millisecondsSinceEpoch,
      'destinationState': destinationState,
      'qrData': qrData,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'blockchainHash': blockchainHash,
      'bloodGroup': bloodGroup,
      // Complex fields serialized for SQLite
      'selectedDestinations': jsonEncode(selectedDestinations.map((x) => x.toJson()).toList()),
      'connectivityLevel': connectivityLevel,
      'offlineModeRequired': offlineModeRequired ? 1 : 0,
      'geoFenceZones': jsonEncode(geoFenceZones),
      'destinationEmergencyContacts': jsonEncode(destinationEmergencyContacts),
      'riskLevel': riskLevel,
    };
  }

  factory Tourist.fromMap(Map<String, dynamic> map) {
    return Tourist(
      touristId: map['touristId'],
      fullName: map['fullName'],
      documentType: DocumentType.values.firstWhere((e) => e.toString().split('.').last == map['documentType']),
      documentNumber: map['documentNumber'],
      photoBase64: map['photoBase64'],
      emergencyContactName: map['emergencyContactName'],
      emergencyContactPhone: map['emergencyContactPhone'],
      tripStartDate: DateTime.fromMillisecondsSinceEpoch(map['tripStartDate']),
      tripEndDate: DateTime.fromMillisecondsSinceEpoch(map['tripEndDate']),
      destinationState: map['destinationState'],
      qrData: map['qrData'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt']),
      blockchainHash: map['blockchainHash'],
      bloodGroup: map['bloodGroup'] ?? "Unknown",
      selectedDestinations: map['selectedDestinations'] != null 
          ? List<DestinationVisit>.from(jsonDecode(map['selectedDestinations']).map((x) => DestinationVisit.fromJson(x)))
          : [],
      connectivityLevel: map['connectivityLevel'],
      offlineModeRequired: map['offlineModeRequired'] == 1,
      geoFenceZones: map['geoFenceZones'] != null ? jsonDecode(map['geoFenceZones']) : [],
      destinationEmergencyContacts: map['destinationEmergencyContacts'] != null ? jsonDecode(map['destinationEmergencyContacts']) : {},
      riskLevel: map['riskLevel'] ?? "LOW",
    );
  }

  static String generateBlockchainHash(Map<String, dynamic> data) {
    final content = jsonEncode(data);
    final bytes = utf8.encode(content);
    return sha256.convert(bytes).toString();
  }
}
