import 'package:flutter_test/flutter_test.dart';
import 'package:saferoute/tourist/models/tourist_model.dart';

void main() {
  group('Tourist.fromJson', () {
    test('parses SQLite-style int booleans from login response', () {
      final tourist = Tourist.fromJson({
        'tourist_id': 'TID-2026-UK-AB8E8',
        'tuid': 12345,
        'full_name': 'SafeRoute Tester',
        'document_type': 'AADHAAR',
        'document_number': 987654,
        'emergency_contact_name': null,
        'emergency_contact_phone': 9000000000,
        'trip_start_date': '2026-05-06 12:39:47.020527',
        'trip_end_date': '2026-05-13 12:39:47.020529',
        'destination_state': 'Uttarakhand',
        'qr_data': 'SAFEROUTE-TID-2026-UK-AB8E8',
        'created_at': '2026-05-06 07:09:47',
        'blood_group': 'O+',
        'selected_destinations':
            '[{"destination_id":"UK_KED_001","name":"Kedarnath","visit_date_from":"2026-05-06","visit_date_to":"2026-05-07"}]',
        'connectivity_level': 'POOR',
        'offline_mode_required': 1,
        'geo_fence_zones': '["SAFE"]',
        'emergency_contacts': '{"control":"112"}',
        'risk_level': 'HIGH',
        'photo_object_key': null,
        'document_object_key': null,
        'is_synced': 0,
        'registration_fields': {'age': 24},
      });

      expect(tourist.offlineModeRequired, isTrue);
      expect(tourist.isSynced, isFalse);
      expect(tourist.tuid, '12345');
      expect(tourist.documentNumber, '987654');
      expect(tourist.emergencyContactPhone, '9000000000');
      expect(tourist.selectedDestinations, hasLength(1));
      expect(tourist.geoFenceZones, ['SAFE']);
      expect(tourist.destinationEmergencyContacts['control'], '112');
      expect(tourist.registrationFields?['age'], '24');
    });
  });
}
