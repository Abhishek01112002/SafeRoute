class Validators {
  static String? validateTripDates(DateTime start, DateTime end) {
    if (end.isBefore(start)) {
      return "Trip end date must be after start date";
    }
    if (end.isAtSameMomentAs(start)) {
      return "Trip must be at least 1 day long";
    }
    return null;
  }

  static String? validateCoordinates(double? lat, double? lng) {
    if (lat == null || lng == null) return null;

    if (lat < -90 || lat > 90) {
      return "Latitude must be between -90 and +90 degrees";
    }
    if (lng < -180 || lng > 180) {
      return "Longitude must be between -180 and +180 degrees";
    }
    return null;
  }

  static String? validateSpeed(double? speed) {
    if (speed == null) return null;
    if (speed < 0) {
      return "Speed cannot be negative";
    }
    return null;
  }

  static String? validateAccuracy(double? accuracy) {
    if (accuracy == null) return null;
    if (accuracy < 0) {
      return "Accuracy cannot be negative";
    }
    return null;
  }

  static String? validateEmail(String email) {
    final emailRegex =
        RegExp(r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$");
    if (!emailRegex.hasMatch(email)) {
      return "Please enter a valid email address";
    }
    return null;
  }

  static String? validateSosTriggerType(String triggerType) {
    const valid = {"MANUAL", "AUTO_FALL", "GEOFENCE_BREACH"};
    if (!valid.contains(triggerType)) {
      return "Invalid trigger type. Must be MANUAL, AUTO_FALL, or GEOFENCE_BREACH";
    }
    return null;
  }

  static String? validateGuestSessionId(String? userType, String? guestSessionId) {
    if (userType == "guest") {
      if (guestSessionId == null || guestSessionId.trim().isEmpty) {
        return "guest_session_id is required for guest users";
      }
    }
    return null;
  }
}
