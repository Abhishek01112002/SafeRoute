# API Data Flow - Quick Reference & Checklists

---

## Critical Issues (Fix Immediately)

### ✅ Issue #1: Missing TUID in Mobile Response (RESOLVED in v3.1)
**Status**: FIXED.
**Location**: `/v3/tourist/register-multipart` response now explicitly includes `tuid`.
**Response Example:**
```json
{
  "tourist": {
    "tourist_id": "TID-2026-UK-...",
    "tuid": "ADR12345678901234567890",
    "full_name": "Abhishek Singh",
    "photo_object_key": "uploaded_files/tourist_.../profile.jpg"
  },
  "token": "..."
}
```

---

### ✅ Issue #2: Coordinate Range Validation (RESOLVED)
**Impact**: Invalid/malicious coordinates accepted
**Locations**:
- `/location/ping` (POST)
- `/sos/trigger` (POST)
- `/rooms/ws/{room_id}/{user_id}` (WebSocket)

**Status**: FIXED.
**Backend locations**:
- `backend/app/routes/location.py`
- `backend/app/routes/sos.py`
- `backend/app/routes/rooms.py`

**Fix**: Validation before storing
```python
# Latitude: -90 to +90
# Longitude: -180 to +180
if not (-90 <= latitude <= 90):
    raise HTTPException(400, "Invalid latitude")
if not (-180 <= longitude <= 180):
    raise HTTPException(400, "Invalid longitude")
```

---

### ✅ Issue #3: Client Timestamp Preserved (RESOLVED)
**Impact**: Original event time lost
**Locations**:
- `/location/ping` (timestamp ignored)
- `/sos/trigger` (timestamp ignored)

**Status**: FIXED.
**Backend locations**:
- `backend/app/models/database.py` (timestamp is nullable and no longer server-defaulted)
- `backend/app/db/crud.py` (stores `ping.timestamp` when provided)
- `backend/app/routes/sos.py` + `backend/app/db/crud.py` (stores client timestamp for SOS)

**Previous (Wrong):**
```python
timestamp: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
```

**Should Be:**
```python
timestamp: Mapped[datetime] = mapped_column(DateTime)
# Backend receives and stores client timestamp, doesn't override
```

---

### ✅ Issue #4: Refresh Token Expiry Validation (RESOLVED)
**Impact**: Tokens usable indefinitely
**Location**: `/auth/refresh` (POST)

**Status**: FIXED.
**Backend location**: `backend/app/routes/auth.py`

**Fix**: Verify token expiry before issuing new tokens
```python
payload = verify_jwt_payload(token)
if payload.get("exp") < datetime.datetime.utcnow().timestamp():
    raise HTTPException(401, "Refresh token expired")
```

---

### ✅ Issue #5: Zone Status Stored (RESOLVED)
**Impact**: Mobile sends zone_status but it's never saved
**Location**: `/location/ping` endpoint

**Status**: FIXED.
**Backend locations**:
- `backend/app/models/database.py` (`LocationPing.zone_status`)
- `backend/app/db/crud.py` (`create_location_ping` persists `zone_status`)

**Previous (Wrong):**
```python
await crud.create_location_ping(db, ping)
# ping.zone_status is ignored!
```

**Should Store:**
```python
await crud.create_location_ping(db, ping)
# LocationPing.zone_status should be populated from ping.zone_status
```

---

## High Priority Issues (Fix This Sprint)

### ✅ Issue #6: Missing Fields in Registration Response (RESOLVED in v3.1)
**Status**: FIXED. All fields including `tuid`, `photo_object_key`, and `document_object_key` are now returned in the registration response.

---

### ✅ Issue #7: Trigger Type Validation (RESOLVED)
**Impact**: Invalid trigger types accepted
**Location**: `/sos/trigger` (POST)

**Valid Types:**
- MANUAL
- AUTO_FALL
- GEOFENCE_BREACH

**Status**: FIXED.
**Backend location**: `backend/app/routes/sos.py`

**Fix**: Enum validation
```python
VALID_TRIGGER_TYPES = {"MANUAL", "AUTO_FALL", "GEOFENCE_BREACH"}
if trigger_type not in VALID_TRIGGER_TYPES:
    raise HTTPException(400, f"Invalid trigger_type. Must be one of {VALID_TRIGGER_TYPES}")
```

---

### 🟠 Issue #8: Zone Type Case Inconsistency
**Impact**: Potential parsing errors
**Details**:
- Backend returns: `"SAFE"`, `"CAUTION"`, `"RESTRICTED"`
- Mobile enum expects: `"safe"`, `"caution"`, `"restricted"`

**Fix**: Backend should return lowercase or mobile should normalize
```dart
// In ZoneTypeExtension.fromString():
static ZoneType fromString(String s) {
  switch (s.toUpperCase()) {  // Normalize to uppercase first
    case 'SAFE': return ZoneType.safe;
    case 'CAUTION': return ZoneType.caution;
    case 'RESTRICTED': return ZoneType.restricted;
    default: return ZoneType.safe;
  }
}
```

---

### ✅ Issue #9: Email + Password Validation in Authority Schema (RESOLVED)
**Impact**: Invalid emails accepted
**Locations**:
- `/auth/register/authority` (POST)
- `/auth/login/authority` (POST)

**Status**: FIXED (backend schema validation).
**Backend location**: `backend/app/models/schemas.py` (`AuthorityRegister`)

**Fix**: Email format validation
```python
@field_validator("email")
@classmethod
def validate_email(cls, v: str) -> str:
    if not re.match(r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$", v):
        raise ValueError("Invalid email format")
    return v
```

---

## Medium Priority Issues (Fix Next Sprint)

### ✅ Issue #10: Trip Date Range Validated (RESOLVED)
**Missing Check**: trip_end_date must be > trip_start_date

**Fix (Mobile - Dart):**
```dart
if (tripEndDate.isBefore(tripStartDate)) {
  throw Exception("Trip end date must be after start date");
}
```

**Status**: FIXED.
**Backend location**: `backend/app/models/schemas.py` (`TouristRegister`)

**Fix (Backend - Python):**
```python
@root_validator
def validate_trip_dates(cls, values):
    start = values.get('trip_start_date')
    end = values.get('trip_end_date')
    if start and end and end <= start:
        raise ValueError('trip_end_date must be after trip_start_date')
    return values
```

---

### ✅ Issue #11: Speed/Accuracy Validated (RESOLVED)
**Missing Checks**:
- speed_kmh must be >= 0
- accuracy_meters must be >= 0

**Status**: FIXED.
**Backend location**: `backend/app/routes/location.py`

**Fix (Backend):**
```python
if speed_kmh is not None and speed_kmh < 0:
    raise HTTPException(400, "speed_kmh must be >= 0")
if accuracy_meters is not None and accuracy_meters < 0:
    raise HTTPException(400, "accuracy_meters must be >= 0")
```

---

### ✅ Issue #12: TUID Format Validated (RESOLVED)
**Impact**: Invalid TUIDs accepted by media upload
**Location**: `/v3/media/upload-url` (POST)

**TUID Format**: 24-character alphanumeric
**Status**: FIXED.
**Backend location**: `backend/app/routes/media.py`

**Fix**:
```python
if not re.match(r"^[a-zA-Z0-9]{24}$", payload.tuid):
    raise HTTPException(400, "Invalid TUID format (must be 24 alphanumeric)")
```

---

### ✅ Issue #13: Destination State Validation (RESOLVED)
**Impact**: Invalid states accepted
**Location**: `/destinations/{state}` (GET)

**Valid States** (from schema):
- Uttarakhand
- Meghalaya
- Arunachal Pradesh
- Assam

**Status**: FIXED.
**Backend location**: `backend/app/routes/destinations.py`

**Fix**:
```python
VALID_STATES = {"Uttarakhand", "Meghalaya", "Arunachal Pradesh", "Assam"}
if state not in VALID_STATES:
    raise HTTPException(400, f"Invalid state. Must be one of {VALID_STATES}")
```

---

### ✅ Issue #14: Additional Validation Hardening (RESOLVED)
**Status**: FIXED.

**Backend fixes:**
- `POST /identity/verify` now validates `document_type`, `document_number`, `date_of_birth`, `nationality`
- `POST /auth/login/authority` now validates email format
- `POST /v3/tourist/login` now validates `tourist_id` format
- `POST /sos/trigger` now enforces timestamp freshness window
- `WS /rooms/ws/{room_id}/{user_id}` now validates timestamp freshness

**Mobile fixes:**
- SOS client validates coordinates, trigger type enum, and guest session rules before sending
- Authority registration/login screens now validate email and enforce stronger password rules

---

### ✅ Issue #15: Location Ping Timestamp Freshness (RESOLVED)
**Status**: FIXED.
**Backend location**: `backend/app/routes/location.py`

**Behavior**:
- If client sends a timestamp, backend rejects stale/future values beyond drift window.
- Keeps previously added coordinate/speed/accuracy validations.

---

## 🆕 V3 Identity Protocol (Multipart)

### [POST] `/v3/tourist/register-multipart`
**Status**: RECOMMENDED (v3.1+)
**Content-Type**: `multipart/form-data`

**Form Fields:**
- `full_name`: string
- `document_type`: string (AADHAAR, PASSPORT, DRIVING_LICENSE)
- `document_number`: string
- `trip_start_date`: ISO datetime
- `trip_end_date`: ISO datetime
- `destination_state`: string
- `blood_group`: string
- `selected_destinations`: JSON string (List of DestinationVisit)
- `profile_photo`: File (image/jpeg, image/png)
- `document_scan`: File (application/pdf, image/jpeg)

**Response**: Returns `tourist` object with `tuid`, `photo_object_key`, and `document_object_key`.

---

### [POST] `/v3/tourist/register` (DEPRECATED)
**Status**: DEPRECATED (legacy Base64 support only)
**Warning**: This endpoint consumes high memory and will be removed in v4.0. Use `/v3/tourist/register-multipart` instead.

---

### [GET] `/v3/media/download/{file_path:path}`
**Status**: NEW
**Authentication**: Required (JWT)
**Purpose**: Securely download identity media (photos/docs).
**Security**: Enforces `tourist_id` ownership and blocks path traversal (`..`).

---

## Data Mapping Reference

### Tourist Registration Payload

**Mobile Sends → Backend Receives → Database Stores**

```
Field                      Mobile  Backend  Database  Mobile Gets Back
─────────────────────────────────────────────────────────────────────
full_name                  ✅      ✅       ✅        ✅
document_type              ✅      ✅       ✅        ✅
document_number            ✅      ✅       ✅ Hash    ❌ (security)
date_of_birth              ❌      ✅       ✅        ❌
nationality                ❌      ✅       ✅        ❌
photo_base64               ⚠️      ✅       ✅        ⚠️
photo_object_key           ⚠️      ✅       ✅        ❌
document_object_key        ⚠️      ✅       ✅        ❌
emergency_contact_name     ⚠️      ✅       ✅        ✅
emergency_contact_phone    ⚠️      ✅       ✅        ✅
trip_start_date            ✅      ✅       ✅        ✅
trip_end_date              ✅      ✅       ✅        ✅
destination_state          ✅      ✅       ✅        ✅
selected_destinations      ✅      ✅       ⚠️ Separate Table ⚠️
blood_group                ⚠️      ✅       ✅        ✅
tuid (generated)           N/A     ✅       ✅        ❌ **CRITICAL**
connectivity_level         N/A     ✅       ✅        ✅
offline_mode_required      N/A     ✅       ✅        ✅
risk_level                 N/A     ✅       ✅        ✅
qr_data (signed JWT)       N/A     ✅       ✅        ✅
```

---

### Location Ping Payload

```
Field                      Mobile  Backend  Database  Notes
───────────────────────────────────────────────────────────────────
tourist_id                 ✅      ✅       ✅        Must match JWT
latitude                   ✅      ✅ ❌Validate  ✅ Range: -90 to +90
longitude                  ✅      ✅ ❌Validate  ✅ Range: -180 to +180
speed_kmh                  ✅      ✅ ❌Validate  ✅ Must be >= 0
accuracy_meters            ✅      ✅ ❌Validate  ✅ Must be >= 0
zone_status                ✅      ⚠️ Accept   ❌ NOT STORED!
timestamp                  ✅      ✅ 🔴 Override  🔴 Client time ignored
tuid                       ❌      ✅ Enriched ✅ From DB
```

---

### SOS Trigger Payload

```
Field                      Mobile  Backend  Database  Notes
───────────────────────────────────────────────────────────────────
tourist_id                 ✅      ✅       ✅
latitude                   ✅      ✅ ❌Validate  ✅ Range: -90 to +90
longitude                  ✅      ✅ ❌Validate  ✅ Range: -180 to +180
trigger_type               ✅      ✅ ❌Enum     ✅ Must validate enum
timestamp                  ✅      ✅ 🔴 Override  🔴 Client time ignored
user_type                  ✅      ⚠️ Accept   ❌ NOT STORED
guest_session_id           ⚠️      ⚠️ Accept   ❌ NOT STORED
tuid                       ❌      ✅ Enriched ✅ From DB
dispatch_status            N/A     ✅ Generated ✅ From dispatch service
correlation_id             N/A     ✅ From Request ✅ For tracing
```

---

## Endpoint Validation Checklist

### POST /v3/tourist/register

**Mobile Before Sending:**
- [ ] Full name not empty
- [ ] Document type is enum (AADHAAR, PASSPORT, DRIVING_LICENSE)
- [ ] Document number matches format for type
- [ ] Trip end date > trip start date
- [ ] States/destinations exist

**Backend After Receiving:**
- [ ] Full name not empty
- [ ] Document type is enum
- [ ] Document number format matches type
- [ ] Date of birth YYYY-MM-DD format
- [ ] Nationality ISO 3166-1 2-letter code
- [ ] Trip end date > trip start date
- [ ] ❌ MISSING: Duplicate document check uses hash

---

### POST /location/ping

**Mobile Before Sending:**
- [ ] Latitude -90 to +90
- [ ] Longitude -180 to +180
- [ ] Speed >= 0
- [ ] Accuracy >= 0
- [ ] Zone status is valid enum

**Backend After Receiving:**
- [ ] Latitude -90 to +90
- [ ] Longitude -180 to +180
- [ ] Speed >= 0
- [ ] Accuracy >= 0
- [ ] Tourist ID matches JWT
- [ ] Tourist exists in database

---

### POST /sos/trigger

**Mobile Before Sending:**
- [ ] Latitude -90 to +90
- [ ] Longitude -180 to +180
- [ ] Trigger type is valid (MANUAL, AUTO_FALL, GEOFENCE_BREACH)
- [ ] If user_type="guest", guest_session_id not empty

**Backend After Receiving:**
- [ ] Latitude required, range check
- [ ] Longitude required, range check
- [ ] Trigger type enum validation
- [ ] Tourist exists if authenticated
- [ ] Rate limit: 3/minute

---

## Response Field Mapping Issues

### Missing in Mobile Response

**Should be returned but aren't:**
1. `tuid` - Cross-system identity (CRITICAL)
2. `date_of_birth` - Registration data
3. `nationality` - Registration data
4. `photo_object_key` - MinIO storage location
5. `document_object_key` - MinIO storage location
6. `destination` details - Only stores destination_state

**Workaround for TUID**: Mobile can derive TUID locally using:
```dart
tuid = generateTUID(docType, docNumber, dateOfBirth, nationality)
// But this requires date_of_birth and nationality to be captured
```

---

## Testing Checklist

### Coordinate Boundary Tests
```
Latitude:
  ✅ 0 (equator)
  ✅ 90 (north pole)
  ✅ -90 (south pole)
  ❌ 91 (over north pole)
  ❌ -91 (over south pole)

Longitude:
  ✅ 0 (prime meridian)
  ✅ 180 (date line)
  ✅ -180 (date line)
  ❌ 181 (over date line)
  ❌ -181 (over date line)
```

### Date Range Tests
```
Trip Dates:
  ✅ Start: 2025-01-01, End: 2025-01-02
  ✅ Start: 2025-01-01, End: 2025-01-01 (same day)
  ❌ Start: 2025-01-02, End: 2025-01-01 (reversed)
  ❌ Start: 2025-01-01, End: 2024-12-31 (past)
```

### Enum Tests
```
Trigger Types:
  ✅ "MANUAL"
  ✅ "AUTO_FALL"
  ✅ "GEOFENCE_BREACH"
  ❌ "manual" (lowercase)
  ❌ "INVALID_TYPE"

Document Types:
  ✅ "AADHAAR"
  ✅ "PASSPORT"
  ✅ "DRIVING_LICENSE"
  ❌ "AADHAR" (misspelled)
  ❌ "VOTER_ID" (not supported)

Zone Types:
  ✅ "SAFE"/"CAUTION"/"RESTRICTED" (backend)
  ✅ "safe"/"caution"/"restricted" (mobile)
  ❌ Case mismatch handling (ambiguous)
```

---

## Deployment Checklist

### Before Production Release

- [ ] Coordinate validation added to all location endpoints
- [ ] Trip date range validation on backend
- [ ] Refresh token expiry validation implemented
- [ ] TUID returned in registration response
- [ ] Timestamp NOT overridden by backend
- [ ] Zone status stored in database
- [ ] Email format validation in auth endpoints
- [ ] Trigger type enum validation
- [ ] TUID format validation in media upload
- [ ] Speed/accuracy >= 0 validation
- [ ] All fields documented in schemas.py
- [ ] Case handling for enums standardized
- [ ] Rate limits verified on all endpoints

---

## Implementation Priority

**Week 1 (Critical):**
1. Add coordinate validation
2. Return TUID in registration
3. Fix timestamp preservation
4. Add refresh token expiry check

**Week 2 (High Priority):**
5. Store zone_status in database
6. Add email validation
7. Add trigger_type validation
8. Add trip date range validation

**Week 3 (Medium Priority):**
9. Add speed/accuracy validation
10. Add TUID format validation
11. Add state validation
12. Normalize enum casing
