// lib/models/emergency_contact_model.dart
// Emergency contact for a destination — stored per-destination in the backend DB.

class EmergencyContact {
  final String id;
  final String destinationId;
  final String label;         // e.g. "SDRF", "Local Police", "Hospital"
  final String phone;
  final String? secondaryPhone;
  final String? notes;

  const EmergencyContact({
    required this.id,
    required this.destinationId,
    required this.label,
    required this.phone,
    this.secondaryPhone,
    this.notes,
  });

  factory EmergencyContact.fromJson(Map<String, dynamic> j) => EmergencyContact(
    id:             j['id'] as String? ?? '',
    destinationId:  j['destination_id'] as String? ?? '',
    label:          j['label'] as String,
    phone:          j['phone'] as String,
    secondaryPhone: j['secondary_phone'] as String?,
    notes:          j['notes'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id':              id,
    'destination_id':  destinationId,
    'label':           label,
    'phone':           phone,
    'secondary_phone': secondaryPhone,
    'notes':           notes,
  };

  Map<String, dynamic> toMap() => toJson();

  factory EmergencyContact.fromMap(Map<String, dynamic> m) => EmergencyContact.fromJson(m);
}
