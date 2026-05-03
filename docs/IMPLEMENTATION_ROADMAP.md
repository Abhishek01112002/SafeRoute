# SafeRoute: Implementation Roadmap & Checklist

## Phase-Based Rollout Strategy

---

## **PHASE 1: SOS RELIABILITY (Week 1-2)**
*Goal: Guarantee SOS reaches authorities (life-critical)*

### Backend Changes
- [ ] Create `sos_queue` table in PostgreSQL
  ```sql
  CREATE TABLE sos_queue (
    sos_id UUID PRIMARY KEY,
    tourist_id VARCHAR(30),
    latitude FLOAT,
    longitude FLOAT,
    status VARCHAR(20),  -- PENDING, SENT_FIREBASE, SENT_SMS, FAILED
    retry_count INT DEFAULT 0,
    last_retry_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    ttl_expires_at TIMESTAMP
  );
  ```

- [ ] Implement `SOSQueueService` class
  - Method: `enqueue_sos(tourist_id, lat, lng) → sos_id`
  - Worker task: `_dispatch_worker()` (retry every 30s)
  - Max retries: 120 attempts (2 hours)
  - Channels: Firebase → SMS → Admin alert

- [ ] Replace current `dispatch_sos()` with queue-based version
  - Old: `send_firebase(token); return`
  - New: `await SOSQueueService.enqueue_sos(...); return`

- [ ] Add SOS delivery audit table
  ```sql
  CREATE TABLE sos_delivery_audit (
    sos_id UUID,
    channel VARCHAR(20),  -- FIREBASE, SMS, BLE, etc.
    status VARCHAR(20),   -- SUCCESS, FAILED, TIMEOUT
    authority_id VARCHAR(30),
    timestamp TIMESTAMP,
    error_message TEXT
  );
  ```

### Mobile Changes
- [ ] Modify SOS trigger UI
  - Show: "SOS STORED - Will send when signal returns" (until success)
  - Update: "Sent to 3 authorities" (once confirmed)
  - Don't let user dismiss until confirmed

- [ ] Implement local SOS queue
  ```dart
  await db.insert('sos_local', {
    'sos_id': sosId,
    'lat': lat,
    'lng': lng,
    'status': 'PENDING',
    'created_at': DateTime.now(),
  });
  ```

- [ ] Add retry mechanism
  - On connectivity change: retry sending queued SOS
  - Play alert sound every 30s until sent

### Testing
- [ ] Scenario: SOS with NO network
  - Expected: SOS stored, retried when signal returns
  - Verify: SOS appears in authority dashboard after reconnection

- [ ] Scenario: SOS with weak 2G signal
  - Expected: First SMS succeeds, Firebase retries in background
  - Verify: Both channels logged in audit trail

- [ ] Load test: 1000 SOS per minute
  - Expected: All queued and processed within 5 minutes
  - Verify: Database doesn't collapse

---

## **PHASE 2: NAVIGATION & ZONE ALERTS (Week 2-4)**

### Part A: Waypoint Navigation

#### Backend
- [ ] Create `waypoint_sequences` table
  ```sql
  CREATE TABLE waypoint_sequences (
    sequence_id UUID PRIMARY KEY,
    destination_id VARCHAR(50),
    name VARCHAR(255),  -- "Cherrapunji to Mawsmai"
    waypoints JSONB,    -- [{"lat": X, "lng": Y, "name": "...", "order": 1}, ...]
    created_by_authority VARCHAR(30),
    created_at TIMESTAMP
  );
  ```

- [ ] Implement `WaypointNavigationService`
  - Method: `get_sequence(destination_id) → waypoints`
  - Validation: Check 3+ waypoints per sequence

- [ ] Add endpoint: `GET /destinations/{destination_id}/navigation-sequence`
  - Returns: Full waypoint sequence for offline caching

#### Mobile
- [ ] Implement `WaypointNavigator` class
  - Input: Current GPS + waypoint sequence
  - Calculate: Bearing + distance to next waypoint
  - Update: Every 5 seconds
  - Display: Compass UI with distance

- [ ] UI Component: Waypoint Navigation Screen
  ```
  ┌─────────────────────┐
  │   🧭 NEXT WAYPOINT  │
  │   ↗ Northeast       │
  │   2.3 km            │
  │   Cherrapunji       │
  │                     │
  │ [⚠️ OFF TRAIL?]    │
  │ Nearest shelter:    │
  │ 📍 Shelter A 500m SE│
  └─────────────────────┘
  ```

- [ ] Add "Trail Deviation Detection"
  - If off-trail (via geofence): show nearest shelter location
  - Suggest: "Head to shelter A (500m southeast)"

### Part B: OS Geofencing

#### Mobile
- [ ] Integrate `geolocator` or `flutter_geofence` package
  - iOS: `CLLocationManager.startMonitoring(CLCircularRegion)`
  - Android: `GeofencingClient.addGeofences(Geofence)`

- [ ] Implement `GeofenceManager` class
  ```dart
  Future<void> setupGeofencesForDestination(destId) async {
    final zones = await db.query('zones', 
        where: 'destination_id = ?', whereArgs: [destId]);
    
    for (var zone in zones) {
      await geolocator.addGeofence(
        latitude: zone['center_lat'],
        longitude: zone['center_lng'],
        radius: zone['radius_m'],
        name: zone['id'],
      );
    }
  }
  ```

- [ ] Handle geofence callbacks
  ```dart
  void onGeofenceEnter(String zoneId) async {
    final zone = await db.get('zones', zoneId);
    
    if (zone['type'] == 'RESTRICTED') {
      HapticFeedback.heavyImpact();
      Vibration.vibrate(duration: 500);
      _playAlarmSound();
    } else if (zone['type'] == 'CAUTION') {
      HapticFeedback.mediumImpact();
    }
    
    showZoneAlert(zone);
  }
  ```

- [ ] UI Component: Zone Alert
  ```
  ┌──────────────────────────┐
  │ 🚨 ENTERING CAUTION ZONE │
  │ Landslide Risk Area      │
  │ Name: Northern Cliffs    │
  │                          │
  │ ⚠️ Stay on marked trail  │
  │ 🏥 Nearest hospital:     │
  │    10 km SE              │
  │                          │
  │ [OK] [📞 Call Help]      │
  └──────────────────────────┘
  ```

### Testing
- [ ] Test waypoint navigation
  - Move tourist GPS manually through sequence
  - Verify: Compass updates correctly
  - Verify: Distance decreases as approach waypoint

- [ ] Test geofencing
  - Create test geofence in app
  - Move tourist into geofence (via simulator)
  - Verify: Haptic fires, alert shows

---

## **PHASE 3: REAL-TIME TRACKING (Week 4-5)**

### Backend
- [ ] Implement batch location storage
  ```python
  @router.post("/location/batch-ping")
  async def receive_location_batch(payload, tourist_id, db):
      locations = payload['locations']
      for loc in locations:
          await crud.create_location_ping(db, LocationPing(...))
      
      # Broadcast latest
      latest = locations[-1]
      await broadcaster.broadcast_location(
          tourist_id, latest['lat'], latest['lng']
      )
  ```

- [ ] Implement broadcaster
  ```python
  class RealtimeBroadcaster:
      authority_connections = {}  # {auth_id: [ws1, ws2, ...]}
      
      async def broadcast_location(self, tourist_id, lat, lng):
          authorities = await get_watching_authorities(tourist_id)
          for auth_id in authorities:
              for ws in self.authority_connections.get(auth_id, []):
                  await ws.send_text(json.dumps({
                      'type': 'location_update',
                      'lat': lat, 'lng': lng,
                      'timestamp': now()
                  }))
  ```

- [ ] Add WebSocket endpoint for authorities
  ```python
  @router.websocket("/ws/authority/{authority_id}/locations")
  async def authority_location_stream(ws, authority_id):
      await broadcaster.register_authority(authority_id, ws)
      # Connection stays open; receives broadcasts
  ```

### Mobile
- [ ] Modify location service to batch uploads
  ```dart
  class LocationBatchService {
    Timer.periodic(Duration(minutes: 3), (_) async {
      if (_buffer.isEmpty) return;
      
      final batch = _buffer.toList();
      _buffer.clear();
      
      await api.post('/location/batch-ping', {
        'locations': batch.map((l) => l.toJson()).toList(),
      });
    });
  }
  ```

### Dashboard (React)
- [ ] Add WebSocket hook
  ```tsx
  useEffect(() => {
    const ws = new WebSocket(`wss://api/ws/authority/${authorityId}/locations`);
    ws.onmessage = (e) => {
      const data = JSON.parse(e.data);
      updateTouristPosition(data.tourist_id, data.lat, data.lng);
    };
  }, []);
  ```

- [ ] Update map component
  ```tsx
  <Marker position={[location.lat, location.lng]} />
  <Popup>
    Last updated: {Math.round((Date.now() - lastUpdate) / 1000)}s ago
  </Popup>
  ```

### Testing
- [ ] Test batch upload
  - Move tourist GPS 10 times (over 2 min)
  - Upload happens at 3-min mark
  - Verify: Server receives all 10 pings at once

- [ ] Test real-time broadcast
  - Authority opens SOS detail
  - Tourist moves GPS
  - Verify: Map updates within 3 seconds of upload

---

## **PHASE 4: BATTERY OPTIMIZATION (Week 5-6)**

### Mobile
- [ ] Implement battery-aware GPS polling
  ```dart
  void _adjustGPSPoll() {
    final batteryLevel = battery.level;
    final zoneType = currentZone.type;
    
    int interval;
    if (batteryLevel > 50) {
      interval = zoneType == 'RESTRICTED' ? 10 : 60;
    } else if (batteryLevel > 20) {
      interval = zoneType == 'RESTRICTED' ? 20 : 120;
    } else {
      interval = zoneType == 'RESTRICTED' ? 30 : 300;
    }
    
    gpsService.setPollInterval(Duration(seconds: interval));
  }
  ```

- [ ] Implement battery-aware haptics
  ```dart
  void triggerHaptic(type) {
    if (battery.level < 15) {
      // Skip haptics under 15% battery
      return;
    }
    HapticFeedback.mediumImpact();
  }
  ```

- [ ] Implement battery critical UI
  ```dart
  if (battery.level < 10) {
    showCriticalBatteryBanner(
      title: '🔋 BATTERY CRITICAL',
      subtitle: 'SOS ready. All other features disabled.',
      actions: [
        'SOS',  // Only SOS button enabled
      ]
    );
  }
  ```

### Testing
- [ ] Simulate low battery scenario
  - Start with 100% battery
  - Navigate through SAFE + CAUTION + RESTRICTED zones
  - Measure battery drain at each zone
  - Verify: Total drain < 50% for 8-hour trip

---

## **PHASE 5: AUTHORITY REGISTRATION (Week 6-7)**

### Backend
- [ ] Integrate OCR service
  ```python
  class IDOCRService:
      @staticmethod
      async def extract_from_image(image_base64: str) -> dict:
          # Call Tesseract or AWS Rekognition
          result = await aws_rekognition.detect_document_text(image_base64)
          return {
              'name': result['name'],
              'document_number': result['doc_id'],
              'dob': result['dob'],
          }
  ```

- [ ] Add QR generation endpoint
  ```python
  @router.post("/authority/register/tourist/scan")
  async def register_via_scan(image_file, authority_id, db):
      image_bytes = await image_file.read()
      extracted = await IDOCRService.extract_from_image(image_bytes)
      
      tuid = generate_tuid(extracted['document_number'], 
                          extracted['dob'], 'IN')
      
      qr_code = await QRService.generate(tuid)
      
      return {
          'tuid': tuid,
          'qr_code_url': qr_code,
          'print_ready': True
      }
  ```

### Dashboard
- [ ] Add "Scan ID Card" interface
  - Camera access
  - Upload to backend
  - Show extracted data for confirmation
  - Generate printable QR code

### Mobile
- [ ] Add QR login screen
  ```dart
  class QRLoginScreen extends StatelessWidget {
    @override
    Widget build(BuildContext context) {
      return QRView(
        onQRViewCreated: (controller) {
          controller.scannedDataStream.listen((scanData) {
            _loginWithTUID(scanData.code);
          });
        },
      );
    }
  }
  ```

### Testing
- [ ] Scan various ID types
  - Passport, Aadhaar, Driving License
  - Verify: OCR extracts correctly
  - Verify: QR generates and scans

---

## **PHASE 6: TRIP TEMPLATES (Week 7-8)**

### Backend
- [ ] Create trip template schema
  ```sql
  CREATE TABLE trip_templates (
    template_id UUID PRIMARY KEY,
    destination_id VARCHAR(50),
    name VARCHAR(255),
    duration_days INT,
    difficulty VARCHAR(20),
    created_by_authority VARCHAR(30)
  );
  
  CREATE TABLE trip_template_stops (
    stop_id UUID PRIMARY KEY,
    template_id UUID REFERENCES trip_templates,
    day_number INT,
    name VARCHAR(255),
    center_lat FLOAT,
    center_lng FLOAT,
    order_index INT
  );
  ```

- [ ] Add template creation endpoint
  ```python
  @router.post("/authority/templates")
  async def create_template(body, authority_id, db):
      template = await crud.create_trip_template(db, {
          'name': body['name'],
          'destination_id': body['destination_id'],
          'duration_days': body['duration_days'],
          'created_by_authority': authority_id,
      })
      
      for stop in body['stops']:
          await crud.create_template_stop(db, {
              'template_id': template.id,
              'day_number': stop['day'],
              'name': stop['name'],
              'center_lat': stop['lat'],
              'center_lng': stop['lng'],
          })
  ```

- [ ] Add tourist trip creation from template
  ```python
  @router.post("/tourist/trips/from-template/{template_id}")
  async def create_trip_from_template(template_id, tourist_id, db):
      template = await crud.get_trip_template(db, template_id)
      stops = await crud.get_template_stops(db, template_id)
      
      trip = Trip(tourist_id=tourist_id, status='ACTIVE')
      for stop in stops:
          trip.stops.append(TripStop(...))
      
      await crud.create_trip(db, trip)
      return {'trip_id': trip.trip_id}
  ```

### Dashboard
- [ ] Add template builder UI
  - Input: Destination, name, duration
  - Add stops: Name, coordinates, day
  - Review and publish

### Mobile
- [ ] Display available templates on registration
  - Tourist selects "Meghalaya Scenic Loop"
  - App downloads template waypoints + zones
  - Pre-cache everything locally

### Testing
- [ ] Create template with 4 stops
  - Tourist selects template
  - Verify: All waypoints downloaded
  - Verify: Navigation uses template sequence

---

## **VERIFICATION CHECKLIST**

### Phase 1 Complete?
- [ ] SOS queued even with NO network
- [ ] SOS retries every 30s
- [ ] Tourist sees status ("Queued", "Sent", etc.)
- [ ] Authority receives SOS on dashboard
- [ ] Load test: 1000 SOS handled

### Phase 2 Complete?
- [ ] Waypoint compass shows bearing + distance
- [ ] Geofence triggers haptic on zone entry
- [ ] Off-trail detection works
- [ ] Shelter location shown on deviation

### Phase 3 Complete?
- [ ] Locations uploaded in batches every 3 min
- [ ] Dashboard receives updates via WebSocket
- [ ] Latency < 60 seconds typical
- [ ] Map shows smooth movement

### Phase 4 Complete?
- [ ] GPS poll rate adapts by zone + battery
- [ ] Battery lasts 8 hours minimum
- [ ] Haptics disabled < 15%
- [ ] Critical battery UI shows correctly

### Phase 5 Complete?
- [ ] OCR extracts ID info accurately
- [ ] QR code generates and scans
- [ ] Tourist can login with QR
- [ ] Works with any phone

### Phase 6 Complete?
- [ ] Authority creates templates
- [ ] Tourist selects template
- [ ] Waypoints guide entire trip
- [ ] Authority sees expected path

---

## **Success Metrics**

After all 6 phases:

✅ **Safety**
- SOS delivery: 99.9%+ (vs. current ~95%)
- SOS acknowledgment time: < 2 min (vs. current unknown)
- Tourist gets lost: < 1% (vs. current >10%)

✅ **Experience**
- Battery lasts full trip (100% adoption)
- Registration works without camera (100% inclusive)
- Rescue coordination time: 15 min (vs. current 2 hours)

✅ **Reliability**
- Waypoint navigation: works offline (zero network dependency)
- Zone alerts: instant (< 2s vs. current 60s)
- Real-time tracking: 30-60s latency (vs. current 10s polling)

✅ **Scale**
- Handle 10,000 simultaneous tourists
- Handle 1,000 SOS per minute
- Handle 1M location pings per day

---

**Total Effort: 6-8 weeks**  
**Team: 2-3 backend engineers + 1 mobile engineer + 1 DevOps**  
**Output: Production-ready SafeRoute system**
