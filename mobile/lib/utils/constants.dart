// lib/utils/constants.dart
import 'package:flutter/material.dart';

// Use localhost because of 'adb reverse tcp:8000 tcp:8000'
const String kBaseUrl = 'http://127.0.0.1:8000';

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
