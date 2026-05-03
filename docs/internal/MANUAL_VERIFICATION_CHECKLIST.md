# SafeRoute Manual Verification Checklist (Comprehensive)

Generated: May 3, 2026
Owner: QA + Backend + Mobile + Dashboard
Scope: Verification of all data-consistency bug fixes and regression safety

---

## 1) How To Use This Checklist

- Run all checks in this order: Environment Setup -> Functional -> Non-Functional -> Regression -> Compatibility -> Documentation -> Sign-off.
- For every test case, attach:
- Screenshot (UI/API client response)
- Log snippet (server/app logs with timestamp)
- Test result record (Pass/Fail, tester name, date/time)
- If any test fails, stop release for that scope and follow the escalation protocol in section 10.

---

## 2) Test Environment Matrix

| Environment | Backend | DB | Redis | Mobile | Dashboard | Notes |
|---|---|---|---|---|---|---|
| Local QA | FastAPI latest branch | PostgreSQL + SQLite compatibility | Enabled | Android device/emulator | Chrome/Edge | Primary manual validation |
| Staging | Deployed build candidate | PostgreSQL | Enabled | Android test devices | Chrome/Edge/Firefox | Pre-release sign-off |

Pre-checks before executing tests:
- API health endpoint returns 200.
- Test users/fixtures are seeded.
- Redis is reachable (for rate-limit and caching behavior).
- Test clock/timezone is documented.

---

## 3) Detailed Functional Test Plan (By Fixed Issue)

### 3.1 Critical Issues (1-5)

| Test ID | Fixed Issue | Test Case Steps | Expected Outcome | Acceptance Criteria | Evidence Required |
|---|---|---|---|---|---|
| DC-C01 | Missing TUID in response | Call `POST /v3/tourist/register` with valid payload. | Response `tourist` object includes non-empty `tuid`. | `tuid` present, format-valid, persisted in DB. | API response screenshot + DB row screenshot + backend log |
| DC-C02 | No coordinate validation | Call `POST /location/ping` with latitude `200` and valid token. | Request rejected with validation error. | HTTP 400/422 returned; no invalid row persisted. | API screenshot + DB query output + server log |
| DC-C03 | Client timestamp overridden | Send `POST /location/ping` and `POST /sos/trigger` with known client timestamp. | Stored timestamp equals client timestamp (within timezone normalization). | Timestamp preserved, not replaced by server-now (except null fallback). | API screenshot + DB row screenshot |
| DC-C04 | Zone status not stored | Send ping with `zone_status=RESTRICTED`. | Row saved with `zone_status=RESTRICTED`. | Exact value retrievable from DB/API trail. | API screenshot + DB row screenshot |
| DC-C05 | Refresh token expiry check | Use expired refresh token at `POST /auth/refresh`. | Unauthorized error. | HTTP 401 with expiry-related message; no access token issued. | API screenshot + auth log |

### 3.2 High-Priority Issues (6-13)

| Test ID | Fixed Issue | Test Case Steps | Expected Outcome | Acceptance Criteria | Evidence Required |
|---|---|---|---|---|---|
| DC-H06 | Trigger type enum validation | Call `POST /sos/trigger` with `trigger_type=INVALID_TYPE`. | Request rejected. | HTTP 400/422; no SOS row for invalid type. | API screenshot + DB query |
| DC-H07 | Trip date range validation | Register tourist where end date < start date. | Request rejected. | HTTP 400/422 with date-range message. | API screenshot |
| DC-H08 | Zone type casing inconsistency | Create zone with `type=safe`. | Type normalized/validated to allowed enum behavior. | Stored type is valid enum (`SAFE/CAUTION/RESTRICTED`) or request rejected if invalid. | API screenshot + DB row |
| DC-H09 | Email format validation | Register authority with bad email `abc@`. | Request rejected. | HTTP 400/422; no authority created. | API screenshot + DB query |
| DC-H10 | Password strength validation | Register authority with weak password `abc123`. | Request rejected. | HTTP 400/422 with strength error. | API screenshot |
| DC-H11 | TUID format validation | Call authority scan using malformed TUID. | Request rejected as invalid QR format. | HTTP 400 with validation message. | API screenshot + server log |
| DC-H12 | State name validation | Register tourist with invalid state `MoonState`. | Request rejected. | HTTP 400/422; no tourist created. | API screenshot |
| DC-H13 | Blood group validation | Register tourist with blood group `X+`. | Request rejected. | HTTP 400/422; no tourist created. | API screenshot |

---

## 4) Step-By-Step Validation Procedures (Functional + Non-Functional)

### 4.1 Functional Procedure (Standard)

1. Open API client (Postman/Insomnia).
2. Load the test case payload from section 3.
3. Send request with valid auth token unless the test is auth-failure specific.
4. Record status code and response body.
5. Verify DB result (row exists/does not exist as expected).
6. Capture screenshots and logs.
7. Mark Pass/Fail with exact reason.

### 4.2 Non-Functional Procedure

Security checks:
1. Verify validation failures do not leak internal stack traces.
2. Verify sensitive fields (raw document number, password hash) are not exposed in responses.
3. Verify rate-limited endpoints respond with expected limit behavior.

Reliability checks:
1. Repeat each critical endpoint test 5 times.
2. Confirm deterministic behavior across repeated runs.

Observability checks:
1. Confirm each request can be traced by timestamp/correlation id in logs.
2. Confirm failure logs include actionable detail.

---

## 5) Regression Testing Protocol

Run this mini-suite after each fix verification:
- Auth regression:
- Authority login still works with valid credentials.
- Tourist protected routes still reject mismatched IDs.
- Registration regression:
- Valid tourist registration still succeeds end-to-end.
- Duplicate document check still works.
- Location/SOS regression:
- Valid ping and valid SOS still persist and are queryable.
- Dashboard regression:
- Metrics endpoint still loads and values are returned.

Pass criteria:
- No previously working flow fails.
- No schema compatibility break for valid legacy/normal payloads where supported.

---

## 6) Performance Benchmarks (No Degradation Gate)

Measure before/after on staging build candidate.

| Endpoint | Target P50 | Target P95 | Error Rate | Notes |
|---|---|---|---|---|
| `POST /v3/tourist/register` | <= 400 ms | <= 900 ms | < 1% | Includes validation + DB write |
| `POST /location/ping` | <= 150 ms | <= 350 ms | < 1% | High-frequency path |
| `POST /sos/trigger` | <= 250 ms | <= 600 ms | < 1% | Includes dispatch attempt |
| `POST /auth/refresh` | <= 120 ms | <= 250 ms | < 1% | Token verification path |

Benchmark procedure:
1. Run 100 requests per endpoint with representative payloads.
2. Capture P50/P95 and error rate.
3. Compare to last approved baseline.
4. Fail verification if any endpoint exceeds threshold by >10% without approved exception.

---

## 7) Cross-Platform / Browser Compatibility

### 7.1 Dashboard (Web)
- Browsers:
- Chrome (latest), Edge (latest), Firefox (latest)
- Checks:
- Login flow
- Metrics rendering
- SOS list rendering
- Zone-related UI that depends on status/type

### 7.2 Mobile
- Platforms:
- Android emulator + at least one physical Android device
- Checks:
- Tourist registration flow
- Location ping flow (online and constrained-network mode)
- SOS trigger flow

Pass criteria:
- No validation mismatch between platforms.
- No platform-specific parsing/casing discrepancies.

---

## 8) Documentation Review Checklist

Verify all related documents are aligned:
- `docs/internal/DATA_CONSISTENCY_SUMMARY.md`
- `docs/internal/DATA_CONSISTENCY_REPORT.md`
- `docs/internal/API_DATA_FLOW_ANALYSIS.md`
- `docs/internal/API_QUICK_REFERENCE.md`
- `CHANGELOG.md`

Checks:
- Endpoint paths are current and use mounted prefixes.
- Issue statuses match code reality.
- Examples reflect current validators and accepted enums.
- Dates/version stamps are updated.

---

## 9) Stakeholder Sign-Off Criteria

Approval is complete only when all are signed:

| Role | Required Sign-off | Required Evidence |
|---|---|---|
| QA Lead | All mandatory tests passed or approved exception logged | Test report + evidence links |
| Backend Developer | Fixes verified at code path and runtime behavior | Code references + logs |
| Product Owner | User-impacting behavior matches acceptance criteria | Demo notes + summary report |

Release blocking conditions:
- Any unresolved Critical test failure.
- Missing evidence for passed tests.
- Missing sign-off from any required role.

---

## 10) Defect Tracking and Escalation Protocol

For each verified fix in defect tracker:
1. Change status to `Ready for QA`.
2. After pass, set to `Verified`.
3. Attach:
- Test case ID(s)
- Screenshots
- Logs
- DB/API evidence
- Tester and timestamp

If verification fails:
1. Immediately move ticket to `Reopened`.
2. Add exact reproduction steps:
- Request payload
- Endpoint
- Auth context
- Environment
- Actual vs expected result
3. Add severity (`Critical/High/Medium/Low`) and business impact.
4. Notify backend lead + QA lead + product owner same day.

---

## 11) Execution Log Template (Fillable)

| Test ID | Env | Tester | Date/Time | Result | Evidence Links | Notes |
|---|---|---|---|---|---|---|
| DC-C01 | Staging |  |  | Pass/Fail |  |  |
| DC-C02 | Staging |  |  | Pass/Fail |  |  |
| DC-C03 | Staging |  |  | Pass/Fail |  |  |
| DC-C04 | Staging |  |  | Pass/Fail |  |  |
| DC-C05 | Staging |  |  | Pass/Fail |  |  |
| DC-H06 | Staging |  |  | Pass/Fail |  |  |
| DC-H07 | Staging |  |  | Pass/Fail |  |  |
| DC-H08 | Staging |  |  | Pass/Fail |  |  |
| DC-H09 | Staging |  |  | Pass/Fail |  |  |
| DC-H10 | Staging |  |  | Pass/Fail |  |  |
| DC-H11 | Staging |  |  | Pass/Fail |  |  |
| DC-H12 | Staging |  |  | Pass/Fail |  |  |
| DC-H13 | Staging |  |  | Pass/Fail |  |  |

---

## 12) "Like a Child" Testing Guide (Very Simple Steps)

Think of testing like checking your school bag before class.
You check one pocket at a time so nothing is missing.

### A) For each bug fix
1. Pick one test card (example: `DC-C01`).
2. Do exactly what the card says.
3. See what happened.
4. If it matches expected result, put a green tick.
5. Take a picture (screenshot) and save proof.

### B) For functional checks
1. Send a request.
2. Read the reply.
3. Check the database.
4. Write pass/fail.

### C) For non-functional checks
1. Check it is safe (no secret data leaks).
2. Check it is stable (works same way many times).
3. Check logs are clear (so adults can debug quickly).

### D) For regression checks
1. Re-test old happy paths.
2. Make sure old working features still work.
3. If old thing breaks, mark as regression bug.

### E) For performance checks
1. Time how fast endpoint answers.
2. Compare with target time.
3. If too slow, raise performance issue.

### F) For compatibility checks
1. Try same flow in all required browsers/devices.
2. Confirm result is same everywhere.

### G) For documentation checks
1. Read docs and compare with real API behavior.
2. Fix docs if words do not match reality.

### H) For sign-off
1. QA says: tested and okay.
2. Developer says: code path is okay.
3. Product owner says: behavior is okay for users.
4. Only then mark done.

### I) If something fails
1. Do not hide it.
2. Write exact steps.
3. Attach proof.
4. Tell team quickly.

---

## 13) Final Acceptance Gate

Release is approved only if:
- All mandatory tests pass.
- Failed tests are resolved or formally accepted with waiver.
- Evidence package is complete.
- QA + Dev + Product owner sign-offs are complete.
