// lib/utils/constants.dart
import 'package:flutter/material.dart';

// API configuration.
//
// Debug builds default to the adb-reversed local backend. Production builds
// must be launched with:
// --dart-define=SAFEROUTE_API_BASE_URL=https://api.your-domain.example
const String kBaseUrl = String.fromEnvironment(
  'SAFEROUTE_API_BASE_URL',
  defaultValue: 'http://10.198.71.18:8000',
);

// Optional SHA-256 fingerprint of the production TLS leaf certificate in hex.
// Leave empty during local development.
const String kPinnedCertificateSha256 = String.fromEnvironment(
  'SAFEROUTE_TLS_CERT_SHA256',
  defaultValue: '',
);

const String kAppName = 'SafeRoute';
const int kLocationIntervalSeconds = 30;
const int kAnomalyCheckMinutes = 5;
const double kSosHoldDuration = 3.0;

const List<String> kNeIndiaStates = [
  'Arunachal Pradesh',
  'Assam',
  'Manipur',
  'Meghalaya',
  'Mizoram',
  'Nagaland',
  'Sikkim',
  'Tripura',
];

const Map<String, String> kStateAbbreviations = {
  'Arunachal Pradesh': 'AR',
  'Assam': 'AS',
  'Manipur': 'MN',
  'Meghalaya': 'ML',
  'Mizoram': 'MZ',
  'Nagaland': 'NL',
  'Sikkim': 'SK',
  'Tripura': 'TR',
};

const Map<String, Color> kZoneStatusColors = {
  'SAFE': Colors.green,
  'CAUTION': Colors.amber,
  'RESTRICTED': Colors.red,
  'UNKNOWN': Colors.grey,
};
