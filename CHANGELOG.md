# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Documentation
- Refreshed `docs/internal/DATA_CONSISTENCY_SUMMARY.md` to remove stale contradictions, normalize endpoint paths to mounted routes, and publish a verified current-state matrix for all 13 previously reported consistency issues.
- Added `docs/internal/MANUAL_VERIFICATION_CHECKLIST.md` with complete manual validation plan: test cases, acceptance criteria, regression protocol, performance gates, compatibility checks, documentation alignment checks, sign-off workflow, and defect-tracker evidence requirements.

### Fixed
- **Data Consistency (High Priority 8)**: Added `type` validation to `ZoneCreate` schema (`SAFE`, `CAUTION`, `RESTRICTED`) in `backend/app/models/schemas.py`.

### Verified
- Verified Critical Issue 1 (Missing TUID in Response): `create_tourist` and `_tourist_to_dict` return `tuid` properly.
- Verified Critical Issue 2 (No Coordinate Validation): Handled properly in `backend/app/routes/sos.py`.
- Verified Critical Issue 3 (Client Timestamp Overridden): Properly handled in `backend/app/routes/sos.py` and `LocationPing`.
- Verified Critical Issue 4 (Zone Status Not Stored): `create_location_ping` in `backend/app/db/crud.py` stores `zone_status`.
- Verified Critical Issue 5 (No Refresh Token Expiry Check): Expire time check correctly done in `backend/app/routes/auth.py`.
- Verified High Priority 6 (No trigger type enum validation): Correct validation is in `backend/app/routes/sos.py`.
- Verified High Priority 7 (No trip date range validation): Correctly handled in `backend/app/models/schemas.py`.
- Verified High Priority 9 (No email format validation): Added regex validation in `backend/app/models/schemas.py`.
- Verified High Priority 10 (Weak password validation): Proper strength check in `backend/app/models/schemas.py`.
- Verified High Priority 11 (No TUID format validation): Regex format validation exists in `backend/app/services/identity_service.py` and is used in `backend/app/routes/authority.py`.
- Verified High Priority 12 (No state name validation): Supported Indian states validated in `backend/app/models/schemas.py`.
- Verified High Priority 13 (No blood group validation): Handled in `backend/app/models/schemas.py`.
