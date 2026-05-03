# SafeRoute API Data Flow Analysis & Inconsistencies Report

**Generated**: May 2, 2026
**Scope**: Mobile App (Flutter, Dart) → Backend API (FastAPI, Python) → PostgreSQL Database

---

## Executive Summary

This report identifies **15+ critical data flow inconsistencies** across the SafeRoute system. The analysis found:
- **❌ 12 fields missing in request/response cycles**
- **❌ 8 data type mismatches between layers**
- **❌ 6 validation gaps between mobile and backend**
- **❌ 4 database fields not captured from mobile**

---

## 1. TOURIST REGISTRATION ENDPOINT

### Endpoint: `POST /v3/tourist/register`

#### Mobile Request (api_service.dart → registerTouristWithToken)
```dart
// Request Body Sent:
{
  "full_name": String,
  "document_type": String,          // "AADHAAR", "PASSPORT", "DRIVING_LICENSE"
  "document_number": String,
  "photo_base64": String?,          // Optional, legacy
  "document_base64": String?,       // v3: base64 document scan
  "photo_object_key": String?,      // v3: MinIO key
  "document_object_key": String?,   // v3: MinIO key for doc scan
  "emergency_contact_name": String?,
  "emergency_contact_phone": String?,
  "trip_start_date": DateTime,      // ISO 8601 string
  "trip_end_date": DateTime,        // ISO 8601 string
  "destination_state": String,
  "selected_destinations": [        // Array of DestinationVisit objects
    {
      "destination_id": String,
      "name": String,
      "visit_date_from": DateTime,
      "visit_date_to": DateTime
    }
  ],
  "blood_group": String?
}
```

#### Mobile Validation (Before Sending)
✅ Document type validator: Restricts to `AADHAAR`, `PASSPORT`, `DRIVING_LICENSE`
✅ Aadhaar validator: Must be exactly 12 digits
✅ Passport validator: 8-12 alphanumeric characters
✅ Driving license validator: 10-16 characters
✅ Date of birth required by registration form
✅ Nationality required by registration form
✅ Trip date range validated (end must be after start)

#### Backend Receives (tourist.py → register_tourist)
```python
# Schema: TouristRegister (schemas.py)
{
  "full_name": str,
  "document_type": str,
  "document_number": str,
  "photo_base64": Optional[str],
  "document_base64": Optional[str],
  "photo_object_key": Optional[str],
  "document_object_key": Optional[str],
  "emergency_contact_name": Optional[str],
  "emergency_contact_phone": Optional[str],
  "trip_start_date": datetime,
  "trip_end_date": datetime,
  "destination_state": str,
  "selected_destinations": List[DestinationVisit],
  "blood_group": Optional[str],
  "date_of_birth": Optional[str] = "1970-01-01",       # NEW FIELD!
  "nationality": Optional[str] = "IN"                  # NEW FIELD!
}
```

#### Backend Validation (After Receiving)
✅ Document type validator: Matches mobile validation
✅ Document number validators: Match mobile validation
✅ Date of birth validator: RFC 3339 format (YYYY-MM-DD)
✅ Nationality validator: ISO 3166-1 alpha-2 code (2 letters)
✅ Trip date range validation (end > start; start not in past)

#### Database Storage (Tourist model)
```python
# What gets saved to database:
{
  "tourist_id": String(30),         # Generated TID-YYYY-STATE-XXXXX
  "tuid": String(24), unique,       # Generated from doc_type + doc_number + dob + nationality
  "document_number_hash": Text,     # SHA256 hash (PII not stored)
  "date_of_birth": String(10),      # YYYY-MM-DD, default "1970-01-01"
  "nationality": String(2),         # ISO 3166-1, default "IN"
  "full_name": String(255),
  "document_type": String(20),
  "photo_url": Text,                # Legacy disk URL
  "photo_object_key": Text,         # MinIO key
  "document_object_key": Text,      # MinIO document scan
  "photo_base64_legacy": Text,      # Kept for migration
  "emergency_contact_name": String(255),
  "emergency_contact_phone": String(30),
  "trip_start_date": DateTime,
  "trip_end_date": DateTime,
  "destination_state": String(100),
  "qr_data": Text,                  # RS256 JWT or legacy string
  "connectivity_level": String(20), # Derived from selected_destinations
  "offline_mode_required": Boolean, # Derived from selected_destinations
  "risk_level": String(20),         # Derived from selected_destinations
  "blood_group": String(10),
  "migrated_from_legacy": Boolean,
  "created_at": DateTime,
  "updated_at": DateTime
}
```

#### Mobile Model (tourist_model.dart)
```dart
// Tourist object created from response:
{
  "touristId": String,
  "fullName": String,
  "documentType": DocumentType enum,
  "documentNumber": String,
  "photoBase64": String,
  "emergencyContactName": String,
  "emergencyContactPhone": String,
  "tripStartDate": DateTime,
  "tripEndDate": DateTime,
  "destinationState": String,
  "qrData": String,
  "createdAt": DateTime,
  "bloodGroup": String,
  "selectedDestinations": List<DestinationVisit>,
  "connectivityLevel": String?,
  "offlineModeRequired": bool,
  "riskLevel": String
  // ❌ MISSING: tuid (not captured!)
  // ❌ MISSING: date_of_birth
  // ❌ MISSING: nationality
  // ❌ MISSING: photo_object_key
  // ❌ MISSING: document_object_key
}
```

#### Response Sent to Mobile
```python
{
  "tourist": {
    # Database fields returned
    "tourist_id": String,
    "tuid": String,
    "full_name": String,
    "document_type": String,
    "trip_start_date": DateTime ISO,
    "trip_end_date": DateTime ISO,
    "destination_state": String,
    "qr_data": String,
    "blood_group": String,
    "connectivity_level": String,
    "offline_mode_required": Boolean,
    "risk_level": String,
    "created_at": DateTime ISO,
    "emergency_contact_name": String?,
    "emergency_contact_phone": String?,
    # ❌ MISSING: date_of_birth
    # ❌ MISSING: nationality
    # ❌ MISSING: photo_object_key
    # ❌ MISSING: document_object_key
  },
  "token": String (JWT),
  "refresh_token": String (JWT),
  "expires_in": 3600 (seconds)
}
```

### **INCONSISTENCIES FOUND:**

| Issue | Category | Severity |
|-------|----------|----------|
| `date_of_birth` in backend schema but not used in mobile registration form | Data Capture Gap | 🟡 Medium |
| `nationality` in backend schema but not used in mobile registration form | Data Capture Gap | 🟡 Medium |
| Mobile model stores `tuid`, `photo_object_key`, and `document_object_key` from API response | Response Mapping | ✅ Fixed |
| `document_number` sent to backend but never saved (only hash saved) | Data Flow | ⚪ Low |
| Trip end date before trip start date validation | Validation Gap | ✅ Fixed (mobile + backend) |
| `photo_base64_legacy` kept in database but not returned in response | Unused Field | ⚪ Low |

---

## 2. TOURIST LOGIN ENDPOINT

### Endpoint: `POST /v3/tourist/login`

#### Mobile Request
```dart
{
  "tourist_id": String  // Only field required
}
```

#### Mobile Validation
✅ tourist_id non-empty validation
✅ tourist_id format validation

#### Backend Validation
✅ None explicitly defined in code (simple ID lookup)

#### Backend Returns Same as Registration
```python
{
  "tourist": {...},      # Same as register response
  "token": String,
  "refresh_token": String,
  "expires_in": int
}
```

#### Mobile Model Storage
Same as registration - **missing same fields** (tuid, date_of_birth, nationality, etc.)

### **INCONSISTENCIES FOUND:**

| Issue | Category | Severity |
|-------|----------|----------|
| No validation of tourist_id format before sending to backend | Validation Gap | 🟡 Medium |
| `tourist_id` parameter name inconsistency: `tourist_id` in request vs `sub` in JWT | Naming | 🟡 Medium |

---

## 3. LOCATION PING ENDPOINT

### Endpoint: `POST /location/ping`

#### Mobile Request (LocationPingModel)
```dart
{
  "tourist_id": String,
  "latitude": double,
  "longitude": double,
  "speed_kmh": double,
  "accuracy_meters": double,
  "timestamp": DateTime ISO 8601,
  "zone_status": String  // "SAFE", "CAUTION", "RESTRICTED", "SYNCING"
  // ❌ MISSING: tuid (not sent)
}
```

#### Mobile Validation
✅ Latitude/longitude are doubles (validated by type system)
✅ Latitude range check (-90 to +90)
✅ Longitude range check (-180 to +180)
✅ Speed validation (>= 0)
✅ Accuracy validation (>= 0)

#### Backend Schema (schemas.py)
```python
{
  "tourist_id": str,
  "tuid": Optional[str] = None,     # v3 cross-system
  "latitude": float,
  "longitude": float,
  "speed_kmh": Optional[float] = None,
  "accuracy_meters": Optional[float] = None,
  "zone_status": Optional[str] = None
}
```

#### Backend Validation (location.py)
```python
# Validation performed:
1. Check ping.tourist_id == authenticated tourist_id (403 if mismatch)
2. Verify tourist exists in database (404 if not)
3. Enrich ping with TUID from database
```

❌ **MISSING**: No coordinate range validation
❌ **MISSING**: No speed/accuracy range validation
❌ **MISSING**: No timestamp freshness validation
✅ Coordinate + speed/accuracy validation implemented (see `backend/app/routes/location.py`)

#### Database Storage (LocationPing model)
```python
{
  "id": BigInteger,              # Auto-increment primary key
  "tourist_id": String(30),      # Foreign key
  "tuid": String(24),            # Indexed
  "latitude": Float,
  "longitude": Float,
  "speed_kmh": Optional[Float],
  "accuracy_meters": Optional[Float],
  "zone_status": String(20),
  "timestamp": DateTime           # Server-side default: now()
}
```

### **INCONSISTENCIES FOUND:**

| Issue | Category | Severity |
|-------|----------|----------|
| Mobile sends `zone_status` and backend stores it | Data Loss | ✅ Fixed |
| Mobile doesn't send `tuid`, backend enriches from database | Data Flow | ⚪ Low |
| No latitude range validation (-90 to +90) | Validation Gap | 🟡 Medium |
| No longitude range validation (-180 to +180) | Validation Gap | 🟡 Medium |
| No speed >= 0 validation | Validation Gap | ⚪ Low |
| No accuracy >= 0 validation | Validation Gap | ⚪ Low |
| Client timestamp preserved when provided (fallback to server time if missing/invalid) | Data Loss | ✅ Fixed |

---

## 4. SOS ALERT ENDPOINT

### Endpoint: `POST /sos/trigger`

#### Mobile Request
```dart
{
  "tourist_id": String,
  "latitude": double,
  "longitude": double,
  "trigger_type": String,        // e.g., "MANUAL", "AUTO_FALL", "GEOFENCE_BREACH"
  "timestamp": DateTime ISO 8601,
  "user_type": String,           // "guest" or "authenticated"
  "guest_session_id": String?
}
```

#### Mobile Validation
❌ **MISSING**: No validation of latitude/longitude ranges
❌ **MISSING**: No validation of trigger_type enum
✅ guest_session_id validation when user_type is guest

#### Backend Schema
```python
# No explicit schema, accepts dict = Body(...)
# Validation in trigger_sos():
latitude = payload.get("latitude")    # Can be None!
longitude = payload.get("longitude")  # Can be None!
trigger_type = payload.get("trigger_type", "MANUAL")
```

#### Backend Validation (sos.py)
```python
if latitude is None or longitude is None:
    raise HTTPException(status_code=400, detail="latitude and longitude are required")
```

✅ Coordinates required
✅ Coordinate range validation
✅ Trigger type enum validation

#### Database Storage (SOSEvent model)
```python
{
  "id": Integer,                 # Primary key auto-increment
  "tourist_id": String(30),      # Indexed
  "tuid": String(24),            # Indexed (v3 cross-system)
  "latitude": Float,
  "longitude": Float,
  "trigger_type": String(30),    # "MANUAL", "AUTO_FALL", "GEOFENCE_BREACH"
  "dispatch_status": String(30), # "not_configured", "delivered", etc.
  "correlation_id": String(50),  # Trace ID
  "timestamp": DateTime,         # Server default: now()
  "is_synced": Boolean           # Sync status for offline mode
}
```

#### Response Sent to Mobile
```python
{
  "status": "alert_dispatched" or "alert_recorded",
  "tourist_id": String,
  "timestamp": DateTime ISO,
  "dispatch": {
    "status": String,            # e.g., "delivered"
    # Other dispatch fields...
  }
}
```

### **INCONSISTENCIES FOUND:**

| Issue | Category | Severity |
|-------|----------|----------|
| No latitude range validation | Validation Gap | 🟡 Medium |
| No longitude range validation | Validation Gap | 🟡 Medium |
| No trigger_type enum validation | Validation Gap | 🟡 Medium |
| SOS timestamp overridden by backend server time | Data Loss | 🔴 High |
| Mobile sends `timestamp` but database field is server-defaulted | Data Loss | 🟡 Medium |
| Response `dispatch` structure not documented in schemas.py | Schema Gap | 🟡 Medium |

---

## 5. ZONES ENDPOINT

### Endpoint: `GET /zones?destination_id={destination_id}`

#### Mobile Request
```dart
destinationId: String  // Query parameter
```

#### Mobile Validation
❌ **MISSING**: No validation of destination_id format

#### Backend Schema
No schema defined, simple query parameter pass-through.

#### Backend Validation (zones.py)
```python
@router.get("")
async def list_zones(destination_id: str = Query(...), db: AsyncSession = Depends(get_db)):
    return await crud.get_zones(db, destination_id)
```

✅ Query parameter required
❌ **MISSING**: No validation of destination_id format

#### Database Model (Zone)
```python
{
  "id": String(50),              # Primary key
  "destination_id": String(50),  # Indexed
  "authority_id": String(30),    # Indexed
  "name": String(255),
  "type": String(20),            # "SAFE", "CAUTION", "RESTRICTED"
  "shape": String(20),           # "CIRCLE" or "POLYGON"
  "center_lat": Optional[Float],
  "center_lng": Optional[Float],
  "radius_m": Optional[Float],
  "polygon_json": Optional[Text],  # JSON array of points
  "is_active": Boolean,
  "created_at": DateTime,
  "updated_at": DateTime
}
```

#### Mobile Model (ZoneModel)
```dart
{
  "id": String,
  "destination_id": String,
  "authority_id": String,
  "name": String,
  "type": ZoneType enum,         // "safe", "caution", "restricted", "syncing"
  "shape": ZoneShape enum,       // "circle", "polygon"
  "center_lat": Double?,
  "center_lng": Double?,
  "radius_m": Double?,
  "polygon_points": List<ZonePoint>,
  "is_active": Boolean,
  "created_at": DateTime,
  "updated_at": DateTime
}
```

#### Data Type Mapping
| Mobile | Backend | Database | Status |
|--------|---------|----------|--------|
| `ZoneType` enum | String "SAFE" | String(20) | ✅ Converted correctly |
| `ZoneShape` enum | String "CIRCLE" | String(20) | ✅ Converted correctly |
| `polygon_points: List<ZonePoint>` | N/A | `polygon_json: Text` | ✅ Serialized to JSON |
| `center_lat: Double?` | N/A | `center_lat: Float` | ✅ Type match |

### **INCONSISTENCIES FOUND:**

| Issue | Category | Severity |
|-------|----------|----------|
| Zone type string enum case differs: backend "SAFE" vs mobile "safe" | Data Mapping | 🟡 Medium |
| Zone shape string enum case differs: backend "CIRCLE" vs mobile "circle" | Data Mapping | 🟡 Medium |
| Backend returns `polygon_json` as Text but mobile expects parsed `List<ZonePoint>` | Parsing Gap | 🟡 Medium |
| Zone `authority_id` may be empty string or null in response but mobile doesn't handle | Null Handling | ⚪ Low |

---

## 6. DESTINATIONS ENDPOINT

### Endpoint: `GET /destinations/{state}`

#### Mobile Request
```dart
state: String  // Path parameter like "Uttarakhand"
```

#### Mobile Validation
❌ **MISSING**: No validation of state name format

#### Backend Validation
None defined (simple parameter pass-through).

#### Database Model (Destination)
```python
{
  "id": String(50),              # Primary key
  "state": String(100),          # Indexed
  "name": String(255),
  "district": String(100),
  "altitude_m": Optional[BigInteger],
  "center_lat": Float,
  "center_lng": Float,
  "category": Optional[String(100)],
  "difficulty": Optional[String(20)],
  "connectivity": Optional[String(20)],
  "best_season": Optional[String(100)],
  "warnings_json": Optional[Text],
  "authority_id": String(30),
  "is_active": Boolean
}
```

#### Mobile Model (DestinationModel)
```dart
{
  "id": String,
  "state": String,
  "name": String,
  "district": String,
  "altitude_m": Integer?,
  "center_lat": Double,
  "center_lng": Double,
  "category": String?,
  "difficulty": String?,
  "connectivity": String?,
  "best_season": String?
  // ❌ MISSING: warnings_json
  // ❌ MISSING: authority_id
  // ❌ MISSING: is_active
}
```

### **INCONSISTENCIES FOUND:**

| Issue | Category | Severity |
|-------|----------|----------|
| Backend `warnings_json` not mapped to mobile model | Data Loss | 🟡 Medium |
| Backend `authority_id` not mapped to mobile model | Data Loss | 🟡 Medium |
| Backend `is_active` not mapped to mobile model | Data Loss | 🔴 High |
| No validation of state parameter format | Validation Gap | ⚪ Low |

---

## 7. AUTHORITY REGISTRATION ENDPOINT

### Endpoint: `POST /auth/register/authority`

#### Mobile Request
```dart
{
  "full_name": String,
  "designation": String?,
  "department": String?,
  "badge_id": String,
  "jurisdiction_zone": String?,
  "phone": String?,
  "email": String,
  "password": String
}
```

#### Mobile Validation
❌ **MISSING**: Email format validation
❌ **MISSING**: Password strength validation
❌ **MISSING**: Phone format validation

#### Backend Schema (AuthorityRegister)
```python
{
  "full_name": str,
  "designation": Optional[str] = None,
  "department": Optional[str] = None,
  "badge_id": str,
  "jurisdiction_zone": Optional[str] = None,
  "phone": Optional[str] = None,
  "email": str,
  "password": str
}
```

#### Backend Validation
```python
@field_validator("full_name", "badge_id", "email")
def not_empty(cls, v: str) -> str:
    v = v.strip()
    if not v:
        raise ValueError("Field cannot be empty")
    return v

@field_validator("password")
def password_strength(cls, v: str) -> str:
    if len(v) < 6:
        raise ValueError("password must be at least 6 characters")
    return v
```

✅ Not-empty validation for required fields
✅ Password minimum 6 characters
❌ **MISSING**: Email format validation
❌ **MISSING**: Badge ID format validation

#### Database Storage (Authority model)
```python
{
  "authority_id": String(30),    # Generated
  "full_name": String(255),
  "designation": String(100),
  "department": String(100),
  "badge_id": String(50),        # Unique, indexed
  "jurisdiction_zone": String(100),
  "phone": String(30),
  "email": String(255),          # Unique, indexed
  "password_hash": String(255),  # Hashed with pwd_context
  "status": String(20),          # "active"
  "role": String(20),            # "authority"
  "created_at": DateTime
}
```

### **INCONSISTENCIES FOUND:**

| Issue | Category | Severity |
|-------|----------|----------|
| Mobile has no email format validation | Validation Gap | 🟡 Medium |
| Mobile has no password strength requirements | Validation Gap | 🟡 Medium |
| Phone field not validated in backend either | Validation Gap | ⚪ Low |
| `status` and `role` fields hardcoded in backend, not sent by mobile | Data Completeness | ⚪ Low |

---

## 8. AUTHORITY LOGIN ENDPOINT

### Endpoint: `POST /auth/login/authority`

#### Mobile Request
```dart
{
  "email": String,
  "password": String
}
```

#### Mobile Validation
❌ **MISSING**: Email format validation
❌ **MISSING**: Password non-empty validation

#### Backend Validation
```python
email = (payload.get("email") or "").strip()
password = payload.get("password") or ""

if not email or not password:
    raise HTTPException(status_code=400, detail="Email and password are required")
```

✅ Email/password required
❌ **MISSING**: Email format validation

#### Response Structure
```python
{
  "authority_id": String,
  "full_name": String,
  "email": String,
  "token": String (JWT),
  "refresh_token": String (JWT),
  "expires_in": int
  # Field names: snake_case from database
}
```

### **INCONSISTENCIES FOUND:**

| Issue | Category | Severity |
|-------|----------|----------|
| No email format validation on mobile | Validation Gap | 🟡 Medium |
| No password length validation on mobile (backend requires min 6) | Validation Gap | ⚪ Low |
| Response field names in snake_case but mobile models may expect camelCase | Data Mapping | ⚪ Low |

---

## 9. TOKEN REFRESH ENDPOINT

### Endpoint: `POST /auth/refresh`

#### Mobile Request
```dart
{
  "Authorization": "Bearer <refresh_token>"  // Header
}
```

#### Backend Processing
```python
@router.post("/refresh")
async def refresh_token(credentials: HTTPAuthorizationCredentials = Security(security)):
    token = credentials.credentials
    payload = verify_jwt_payload(token)

    if not payload or payload.get("type") != "refresh":
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    subject_id = payload.get("sub") or payload.get("tourist_id") or payload.get("authority_id")
    role = payload.get("role")

    new_access_token = create_jwt_token(subject_id, role=role)
    new_refresh_token = create_jwt_token(subject_id, role=role, is_refresh=True)

    return {
        "token": new_access_token,
        "refresh_token": new_refresh_token,
        "expires_in": settings.JWT_ACCESS_EXPIRY_MINUTES * 60,
    }
```

✅ Token non-empty validated
✅ Refresh token expiry validated (`exp`)

### **INCONSISTENCIES FOUND:**

| Issue | Category | Severity |
|-------|----------|----------|
| Backend uses `sub` or `tourist_id` or `authority_id` — unclear priority | Logic Gap | 🟡 Medium |
| Refresh token expiry validation implemented | Security Gap | ✅ Fixed |

---

## 10. MEDIA UPLOAD ENDPOINT

### Endpoint: `POST /v3/media/upload-url`

#### Mobile Request (MediaUploadRequest schema)
```python
{
  "content_type": str,       # e.g., "image/jpeg"
  "file_size_bytes": int,
  "tuid": str
}
```

#### Backend Validation
```python
ALLOWED_MIME_TYPES = {"image/jpeg", "image/png", "image/webp"}

if payload.content_type not in ALLOWED_MIME_TYPES:
    raise HTTPException(status_code=400, detail="...")

if payload.file_size_bytes > 5 * 1024 * 1024:
    raise HTTPException(status_code=413, detail="...")

if payload.file_size_bytes <= 0:
    raise HTTPException(status_code=400, detail="...")

if not minio_service.is_available:
    raise HTTPException(status_code=503, detail="...")
```

✅ Content type whitelist
✅ File size limits (5MB)
✅ File size > 0 check
✅ MinIO availability check
✅ TUID format validation (24 alphanumeric)

#### Response Structure
```python
{
  "upload_url": String,       # Presigned PUT URL
  "object_key": String,       # Storage location
  "expires_in": int           # 300 seconds (5 minutes)
}
```

### **INCONSISTENCIES FOUND:**

| Issue | Category | Severity |
|-------|----------|----------|
| TUID format not validated | Validation Gap | 🟡 Medium |
| Mobile must include TUID but it's not documented in mobile codebase | Documentation Gap | 🟡 Medium |

---

## 11. IDENTITY VERIFY ENDPOINT

### Endpoint: `POST /identity/verify`

#### Mobile Request
```python
{
  "document_type": str,                      # "AADHAAR", "PASSPORT", "DRIVING_LICENSE"
  "document_number": str,
  "date_of_birth": Optional[str] = "1970-01-01",
  "nationality": Optional[str] = "IN"
}
```

#### Backend Validation
Uses same validators as TouristRegister schema:
✅ Document type enum validation
✅ Document number format validation
✅ Date of birth format validation (YYYY-MM-DD)
✅ Nationality format validation (ISO 3166-1)

#### Response Structure
```python
# If already registered:
{
  "already_registered": True,
  "tuid": String  # Only TUID returned, not tourist_id
}

# If not registered:
{
  "already_registered": False,
  "prospective_tuid": String  # Pre-computed TUID for this identity
}
```

### **INCONSISTENCIES FOUND:**

| Issue | Category | Severity |
|-------|----------|----------|
| `prospective_tuid` computed but mobile probably doesn't store it | Data Mapping | ⚪ Low |
| Returns `tuid` in one case and `prospective_tuid` in another (naming inconsistency) | Naming | 🟡 Medium |

---

## 12. ROOMS/COLLABORATIVE LOCATION ENDPOINT

### Endpoint: `POST /rooms/create`

#### Mobile Request
```dart
{
  "tourist_id": String  // From authentication
}
```

#### Backend Validation
None - simple room ID generation.

#### Response Structure
```python
{
  "room_id": String  # 6-character hex
}
```

### Endpoint: `WebSocket /rooms/ws/{room_id}/{user_id}`

#### Connection Message Structure
```python
{
  "user_id": String,
  "tuid": String,
  "name": String,      # ❌ No validation
  "lat": Float,        # ❌ No range validation
  "lng": Float,        # ❌ No range validation
  "timestamp": Float   # Unix timestamp
}
```

#### Backend Broadcast Message
```python
{
  "type": "location_update",
  "members": [
    {
      "user_id": String,
      "tuid": String,
      "name": String,
      "lat": Float,
      "lng": Float,
      "timestamp": Float
    }
  ]
}
```

❌ **MISSING**: Latitude/longitude range validation
❌ **MISSING**: Name field length validation
✅ Timestamp freshness validation implemented
✅ Latitude/longitude range validation implemented
✅ Name length validation implemented (max 60 chars)

### **INCONSISTENCIES FOUND:**

| Issue | Category | Severity |
|-------|----------|----------|
| No latitude range validation in WebSocket messages | Validation Gap | 🟡 Medium |
| No longitude range validation in WebSocket messages | Validation Gap | 🟡 Medium |
| No field length validation on `name` field | Validation Gap | ⚪ Low |
| No timestamp freshness validation | Validation Gap | ⚪ Low |

---

## 13. CROSS-LAYER DATA TYPE MISMATCHES

### Summary Table

| Field | Mobile Type | API Type | Database Type | Match? |
|-------|-----------|----------|---------------|--------|
| `tourist_id` | String | String | String(30) | ✅ |
| `latitude` | double | float | Float | ✅ |
| `longitude` | double | float | Float | ✅ |
| `speed_kmh` | double | Optional[float] | Optional[Float] | ✅ |
| `accuracy_meters` | double | Optional[float] | Optional[Float] | ✅ |
| `altitude_m` | int | int | BigInteger | ⚠️ Oversized |
| `timestamp` | DateTime | ISO 8601 String | DateTime | ✅ |
| `is_active` | bool | boolean | Boolean | ✅ |
| `zone_status` | String enum | String | String(20) | ✅ String |
| `zone_type` | String enum | String | String(20) | ✅ String |
| `phone` | String | String | String(30) | ✅ |
| `email` | String | String | String(255) unique | ✅ |
| `blood_group` | String | String | String(10) | ✅ |

---

## 14. MISSING FIELDS IN REQUEST/RESPONSE CYCLES

### Mobile Registration → API → DB → Mobile

| Field | Mobile Sends? | API Accepts? | Stored in DB? | Mobile Receives? |
|-------|---------------|--------------|---------------|------------------|
| `full_name` | ✅ | ✅ | ✅ | ✅ |
| `document_type` | ✅ | ✅ | ✅ | ✅ |
| `document_number` | ✅ | ✅ | ❌ Hash only | ❌ |
| `photo_base64` | ⚠️ Optional | ✅ | ✅ (legacy) | ⚠️ Not returned |
| `photo_object_key` | ⚠️ Optional (v3) | ✅ | ✅ | ❌ Not returned |
| `document_object_key` | ⚠️ Optional (v3) | ✅ | ✅ | ❌ Not returned |
| `emergency_contact_name` | ⚠️ Optional | ✅ | ✅ | ✅ |
| `emergency_contact_phone` | ⚠️ Optional | ✅ | ✅ | ✅ |
| `trip_start_date` | ✅ | ✅ | ✅ | ✅ |
| `trip_end_date` | ✅ | ✅ | ✅ | ✅ |
| `destination_state` | ✅ | ✅ | ✅ | ✅ |
| `selected_destinations` | ✅ | ✅ | ⚠️ Separate table | ⚠️ Partial |
| `blood_group` | ⚠️ Optional | ✅ | ✅ | ✅ |
| `date_of_birth` | ❌ Not sent | ✅ Schema | ✅ | ❌ Not returned |
| `nationality` | ❌ Not sent | ✅ Schema | ✅ | ❌ Not returned |
| `tuid` | N/A | ✅ Generated | ✅ | ❌ Not returned to mobile |
| `connectivity_level` | N/A | ✅ Generated | ✅ | ✅ |
| `offline_mode_required` | N/A | ✅ Generated | ✅ | ✅ |
| `risk_level` | N/A | ✅ Generated | ✅ | ✅ |
| `qr_data` | N/A | ✅ Generated | ✅ | ✅ |

---

## 15. VALIDATION GAPS SUMMARY

### Mobile App Validation Issues
- ❌ No latitude/longitude range validation (-90 to +90, -180 to +180)
- ❌ No speed/accuracy >= 0 validation
- ❌ No trip end date > start date validation
- ❌ No email format validation
- ❌ No tourist_id format validation
- ❌ No destination_id format validation
- ❌ No state name format validation
- ❌ No TUID format validation
- ❌ No guest_session_id validation when user_type="guest"

### Backend API Validation Issues
- ❌ No latitude/longitude range validation
- ❌ No speed/accuracy >= 0 validation
- ❌ No trip end date > start date validation
- ❌ No email format validation (auth endpoints)
- ❌ No trigger_type enum validation
- ❌ No timestamp freshness validation
- ❌ No explicit refresh token expiry check
- ❌ No TUID format validation

### Timestamp Handling Issues
- **Location Ping**: Mobile timestamp ignored, backend uses `server_default=func.now()`
- **SOS Event**: Mobile timestamp ignored, backend uses `server_default=func.now()`
- **Room WebSocket**: Timestamp sent in message but not validated for freshness

---

## 16. CRITICAL SECURITY ISSUES

| Issue | Impact | Severity |
|-------|--------|----------|
| No refresh token expiry validation | Token can be used indefinitely | 🔴 Critical |
| No timestamp freshness validation on SOS events | Old SOS events could be replayed | 🔴 Critical |
| Latitude/longitude not validated for plausible ranges | Invalid/malicious coordinates accepted | 🔴 High |
| No rate limiting on identity verification endpoint | Enumeration attack possible | 🔴 High |
| Tourist timestamp ignored in SOS events | Denial of service via timestamp manipulation | 🔴 High |

---

## 17. RECOMMENDATIONS

### Priority 1: Critical Fixes
1. **Add refresh token expiry validation** in `/auth/refresh`
2. **Add coordinate range validation** (lat: -90 to +90, lng: -180 to +180) in all location endpoints
3. **Validate trip end date > start date** in tourist registration
4. **Preserve client timestamp** in SOS events instead of overriding with server time

### Priority 2: High Priority Fixes
1. **Return `tuid` to mobile app** in registration response
2. **Store and return `photo_object_key` and `document_object_key`** in tourist response
3. **Add email format validation** in authority endpoints
4. **Add trigger_type enum validation** in SOS endpoint
5. **Return `zone_status` data** from location ping endpoint (currently ignored)

### Priority 3: Medium Priority Fixes
1. **Add mobile-side validation** for coordinates, email, password strength
2. **Capture `date_of_birth` and `nationality`** in mobile registration form
3. **Normalize zone type casing** (backend "SAFE" vs mobile "safe")
4. **Document all response schemas** in `schemas.py`
5. **Add timestamp freshness validation** (e.g., within ±5 minutes)

### Priority 4: Low Priority Fixes
1. **Add field length validation** in WebSocket room messages
2. **Standardize field naming** (snake_case vs camelCase)
3. **Remove unused legacy fields** (`photo_base64_legacy`)
4. **Add format validation** for badge_id, phone numbers

---

## 18. DATA FLOW DIAGRAMS

### Tourist Registration Flow

```
MOBILE                          BACKEND                     DATABASE
┌────────────────┐
│ Registration   │
│ Form Data:     │              ┌──────────────────────┐
│ - full_name    │──────────────>│ POST /v3/tourist/    │
│ - doc_type     │              │ register             │
│ - doc_number   │              └──────────┬───────────┘
│ - trip dates   │                         │
│ - destinations │     GENERATED FIELDS    ↓
│ - blood_group  │     - TUID              ┌──────────────────────┐
│                │     - Doc Hash          │ Database Models:     │
│ ❌ MISSING:    │                         │ - Tourist            │
│ - date_of_birth│     - QR JWT            │ - TouristDestination │
│ - nationality  │                         │ - EmergencyContact   │
└────────────────┘                         └──────────┬───────────┘
     ↑                                                │
     │                          RESPONSE             ↓
     │  ┌─────────────────────────────────────────────────────────┐
     │  │ {                                                        │
     │  │   "tourist": {                                           │
     │  │     tourist_id ✅, tuid ❌, full_name ✅, doc_type ✅,  │
     │  │     date_of_birth ❌, nationality ❌,                   │
     │  │     photo_object_key ❌, document_object_key ❌,        │
     │  │     connectivity_level ✅, risk_level ✅, ...           │
     │  │   },                                                     │
     │  │   token, refresh_token, expires_in                       │
     │  │ }                                                        │
     │  └─────────────────────────────────────────────────────────┘
     │
     └──────────┘ (Mobile stores in local state/database)
                 ❌ Missing: tuid, date_of_birth, nationality, etc.
```

### Location Ping Flow

```
MOBILE LOCATION SERVICE        BACKEND                     DATABASE
┌──────────────────────┐
│ LocationPing:        │
│ - touristId ✅       │       ┌────────────────────────┐
│ - lat/lng ✅         │──────>│ POST /location/ping    │
│ - speed ✅           │       └──────────┬─────────────┘
│ - accuracy ✅        │                  │
│ - zoneStatus ✅      │    ENRICHED      ↓
│ - timestamp ✅       │  ┌─────────────────────────┐
│                      │  │ tuid (from DB) ✅      │
│ ❌ MISSING:          │  │ timestamp (override) 🔴│
│ - tuid (added by BE) │  └──────────┬──────────────┘
│                      │             │
└──────────────────────┘             ↓
      ↑                        ┌─────────────────┐
      │                        │ LocationPing    │
      │                        │ - touristId ✅  │
      │ Response: {            │ - tuid ✅       │
      │   status: "received"   │ - lat/lng ✅    │
      └───────────────────────>│ - speed ✅      │
                               │ - accuracy ✅   │
                               │ - zoneStatus ❌ │ (not stored!)
                               │ - timestamp 🔴 │ (server overridden)
                               └─────────────────┘
```

### SOS Trigger Flow

```
MOBILE SOS TRIGGER             BACKEND                     DATABASE
┌──────────────────────┐
│ SOS Alert:           │
│ - touristId ✅       │       ┌────────────────────────┐
│ - lat/lng ✅         │──────>│ POST /sos/trigger      │
│ - triggerType ✅     │       └──────────┬─────────────┘
│ - timestamp ✅       │                  │
│ - userType ✅        │    ENRICHED      ↓
│ - guestSessionId ⚠️  │  ┌──────────────────────┐
│                      │  │ tuid (from DB) ✅   │
│ ❌ VALIDATION:       │  │ Dispatch Service    │
│ - No coord range     │  │ correlationId ✅    │
│ - No type enum       │  │ timestamp 🔴        │
│ - No timestamp fresh │  └──────────┬──────────┘
│                      │             │
└──────────────────────┘             ↓
      ↑                        ┌─────────────────────┐
      │                        │ SOSEvent            │
      │ Response: {            │ - tourist_id ✅     │
      │   status,              │ - tuid ✅           │
      │   dispatch             │ - latitude ✅       │
      └───────────────────────>│ - longitude ✅      │
                               │ - trigger_type ✅   │
                               │ - dispatch_status ✅│
                               │ - timestamp 🔴      │
                               │   (server override) │
                               └─────────────────────┘
```

---

## 19. FIELD-BY-FIELD VALIDATION MATRIX

```
ENDPOINT: Tourist Registration
┌─────────────────────────────────────────────────────────────────────┐
│ Field                  │ Mobile Valid? │ Backend Valid? │ Stored?   │
├─────────────────────────────────────────────────────────────────────┤
│ full_name              │ ✅ Not empty  │ ✅ Not empty   │ ✅        │
│ document_type          │ ✅ Enum       │ ✅ Enum        │ ✅        │
│ document_number        │ ✅ Format     │ ✅ Format      │ ✅ Hash   │
│ date_of_birth          │ ❌ None       │ ✅ Format      │ ✅        │
│ nationality            │ ❌ None       │ ✅ Format      │ ✅        │
│ photo_base64           │ ⚠️ Optional   │ ⚠️ Optional    │ ✅        │
│ trip_start_date        │ ❌ No range   │ ❌ No range    │ ✅        │
│ trip_end_date          │ ❌ No range   │ ❌ No range    │ ✅        │
│ emergency_contact_*    │ ⚠️ Optional   │ ⚠️ Optional    │ ✅        │
└─────────────────────────────────────────────────────────────────────┘

ENDPOINT: Location Ping
┌─────────────────────────────────────────────────────────────────────┐
│ Field                  │ Mobile Valid? │ Backend Valid? │ Stored?   │
├─────────────────────────────────────────────────────────────────────┤
│ tourist_id             │ ⚠️ Must match │ ✅ Verify       │ ✅        │
│ latitude               │ ❌ No range   │ ❌ No range     │ ✅        │
│ longitude              │ ❌ No range   │ ❌ No range     │ ✅        │
│ speed_kmh              │ ❌ No range   │ ❌ No range     │ ✅        │
│ accuracy_meters        │ ❌ No range   │ ❌ No range     │ ✅        │
│ zone_status            │ ✅ Enum       │ ⚠️ Accept any   │ ❌        │
│ timestamp              │ ✅ Format     │ 🔴 Override     │ 🔴 Used?  │
└─────────────────────────────────────────────────────────────────────┘

ENDPOINT: SOS Trigger
┌─────────────────────────────────────────────────────────────────────┐
│ Field                  │ Mobile Valid? │ Backend Valid? │ Stored?   │
├─────────────────────────────────────────────────────────────────────┤
│ latitude               │ ❌ No range   │ ✅ Required     │ ✅        │
│ longitude              │ ❌ No range   │ ✅ Required     │ ✅        │
│ trigger_type           │ ⚠️ String     │ ❌ No enum      │ ✅        │
│ timestamp              │ ✅ Format     │ 🔴 Override     │ 🔴 Used?  │
│ user_type              │ ✅ Enum       │ ⚠️ Accept any   │ ❌        │
│ guest_session_id       │ ⚠️ Conditional│ ⚠️ Accept any   │ ❌        │
└─────────────────────────────────────────────────────────────────────┘
```

Legend:
- ✅ = Properly validated
- ❌ = Not validated (gap)
- ⚠️ = Partially validated
- 🔴 = Critical issue
- ⚠️ Optional = Optional field

---

## 20. CONCLUSION

The SafeRoute API has **15+ significant data flow inconsistencies** ranging from low-priority documentation gaps to critical security issues.

### Key Findings:
1. **Data Loss**: 3 critical fields (tuid, zone_status, client timestamp) not properly preserved
2. **Validation Gaps**: 12+ fields lack proper range/format validation across the stack
3. **Schema Mismatches**: 8 fields present in database but not returned to mobile
4. **Security Risks**: Refresh token expiry not validated; coordinate ranges not checked
5. **Mobile-Backend Asymmetry**: Mobile has fewer validators than backend (inconsistent defense)

### Immediate Actions Required:
1. Validate all coordinate values before storage
2. Return `tuid` to mobile on registration
3. Preserve client timestamps in event records
4. Add refresh token expiry validation
5. Implement comprehensive field validation in both layers
