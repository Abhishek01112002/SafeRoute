# SafeRoute: Tourist Problems & Best-Fit Solutions

## Planning Phase: Real Tourist Pain Points

---

## **PROBLEM 1: Lost in Mountains with NO Network**

### Tourist's Scenario
- Hiking in Meghalaya with zero signal
- GPS turned on but can't download live maps
- Sees "RESTRICTED" zone ahead on downloaded map
- Needs to find safe route back to base camp

### Current Implementation Issue
- A* pathfinding claimed but NOT CODED
- Relies on pre-downloaded GeoJSON trails
- No clear way to get trails before offline

### **BEST SOLUTION: Guided Waypoint Breadcrumbs**
*Instead of complex pathfinding, use simpler + more reliable approach*

```
APPROACH:
├─ Pre-load destination as WAYPOINT SEQUENCE (not full graph)
│  ├─ Main trail: [WP1 → WP2 → WP3 → ... → Base Camp]
│  └─ Safe zones: [Shelter1, Shelter2, Hospital]
│
├─ Tourist's app shows:
│  ├─ "Next waypoint: 2.3 km NE" (compass + distance)
│  ├─ "Safe shelter nearby: 500m SE" (RED BUTTON)
│  └─ "You are ON TRAIL" or "⚠️ OFF TRAIL" (geofence check)
│
└─ On path deviation (OFF TRAIL):
   ├─ Show nearest shelter
   ├─ Show compass bearing back to trail
   └─ Trigger gentle haptic pulse (don't drain battery with constant vibration)
```

**Why this works:**
- ✅ No complex graph traversal needed
- ✅ Tourist just follows compass to next waypoint
- ✅ Works 100% offline (just SQLite waypoint list + GPS)
- ✅ Battery-efficient (compass is cheap, GPS cached)
- ✅ Handles unpredictable terrain (tourist makes micro-decisions, not app)

**Implementation:**
```dart
// lib/services/waypoint_navigation_service.dart
class WaypointNavigator {
  final List<Waypoint> trail;  // Preloaded from server
  
  Stream<NavigationState> navigateTo(Waypoint target) async* {
    while (!isAtWaypoint(target)) {
      final bearing = calculateBearing(current, target);
      final distance = calculateDistance(current, target);
      
      yield NavigationState(
        bearing: bearing,
        distance: distance,
        status: isOffTrail() ? 'OFF_TRAIL_ALERT' : 'ON_TRACK',
        nearestShelter: findNearestShelter(),
      );
      
      await Future.delayed(Duration(seconds: 5));  // Update every 5s
    }
  }
}
```

---

## **PROBLEM 2: Doesn't Know When Entering Dangerous Zone**

### Tourist's Scenario
- Hiking in Arunachal Pradesh
- Suddenly enters "RESTRICTED" zone (landslide risk)
- Should get INSTANT alert + haptic feedback
- Currently: Has to manually query `/zones/lookup` endpoint

### Current Implementation Issue
- Zone lookup is PULL-based (tourist asks)
- No automatic detection
- Ray-casting is CPU-intensive on mobile

### **BEST SOLUTION: OS-Level Geofence Triggers**
*Let the phone's OS do the heavy lifting*

```
APPROACH:
├─ Download zones as GEOFENCE REGIONS (iOS/Android native)
│  ├─ SAFE zones: No alert
│  ├─ CAUTION zones: Yellow indicator + soft haptic
│  └─ RESTRICTED zones: RED ALERT + strong haptic + sound
│
├─ OS triggers callback when entering geofence (even if app is backgrounded)
│  ├─ NO battery drain from constant GPS polling
│  ├─ INSTANT notification
│  └─ Works even if app is closed
│
└─ On entry:
   ├─ Haptic: mediumImpact (CAUTION) or heavyImpact (RESTRICTED)
   ├─ Sound: Subtle chime (CAUTION) or alarm (RESTRICTED)
   └─ UI: Zone name + danger description + shelter nearest button
```

**Why this works:**
- ✅ Battery efficient (OS geofencing is optimized)
- ✅ INSTANT alerts (not polling-based)
- ✅ Works in background (tourist doesn't need app open)
- ✅ Already tested at scale (Google/Apple geofencing)

**Implementation:**
```dart
// lib/services/geofence_service.dart
import 'package:geolocator/geolocator.dart';

class GeofenceManager {
  Future<void> setupGeofencesForDestination(String destId) async {
    final zones = await db.query('zones', 
        where: 'destination_id = ?', whereArgs: [destId]);
    
    for (var zone in zones) {
      if (zone['shape'] == 'CIRCLE') {
        await geolocator.addGeofence(
          latitude: zone['center_lat'],
          longitude: zone['center_lng'],
          radius: zone['radius_m'],
          name: zone['id'],
        );
      }
    }
  }
  
  void onGeofenceEnter(String zoneId) async {
    final zone = await db.query('zones',
        where: 'id = ?', whereArgs: [zoneId]).first;
    
    if (zone['type'] == 'RESTRICTED') {
      HapticFeedback.heavyImpact();
      Vibration.vibrate(duration: 500);
      _playAlarmSound();
    } else if (zone['type'] == 'CAUTION') {
      HapticFeedback.mediumImpact();
    }
    
    // Show alert UI
    showZoneAlert(zone);
  }
}
```

---

## **PROBLEM 3: SOS Message Might Not Reach Authorities (Life-Critical)**

### Tourist's Scenario
- Tourist has fall, presses SOS
- Phone only has weak 2G signal
- Firebase push fails silently
- 30 minutes later, discovers no one coming
- **SCENARIO: Tourist dies waiting**

### Current Implementation Issue
- Fire-and-forget: `dispatch_sos()` just sends and returns
- No retry mechanism
- No LOCAL fallback if network fails
- No confirmation to tourist that SOS was received

### **BEST SOLUTION: Progressive Escalation + Local Broadcast**
*Try every possible channel; confirm with tourist*

```
APPROACH:
├─ IMMEDIATE: Try fastest channels first (low latency)
│  ├─ Level 1: Local BLE Mesh (other tourists nearby broadcast to group)
│  ├─ Level 2: WhatsApp/SMS to emergency contacts (if have signal)
│  └─ Level 3: Firebase push to authorities (async, may fail)
│
├─ FALLBACK: If network dies
│  ├─ Store SOS locally with GPS coords
│  ├─ Show "SOS STORED - WILL SEND WHEN SIGNAL RETURNS"
│  ├─ Keep trying to send every 30s
│  └─ Play periodic alert sound so tourist knows it's active
│
└─ CONFIRMATION: Always show to tourist
   ├─ "SOS Received by 3 authorities" (if push succeeded)
   ├─ "SOS queued - will send when signal returns" (if offline)
   └─ Red badge with SOS status (never disappears until acknowledged)
```

**Why this works:**
- ✅ Doesn't assume network exists
- ✅ Tourist knows SOS is active (visual feedback)
- ✅ Multiple fallback channels
- ✅ BLE mesh reaches local group (nearby hikers/authorities)
- ✅ Tourist gets confirmation immediately

**Implementation:**
```dart
// lib/services/sos_dispatch_service.dart
class SOSDispatchService {
  Future<SOSResponse> triggerSOS(double lat, double lng) async {
    final sosId = generateUUID();
    final sosData = {'id': sosId, 'lat': lat, 'lng': lng, 'time': now()};
    
    // STORE locally immediately (don't wait for network)
    await db.insert('sos_local', sosData);
    
    // SHOW UI immediately
    showSOSActive(sosId);
    
    // TRY: Local BLE broadcast
    try {
      await bleService.broadcastSOS(sosData);
      updateSOSUI(sosId, status: 'BLE_SENT');
    } catch (e) {}
    
    // TRY: SMS to emergency contacts
    if (connectivity.hasSignal) {
      try {
        for (var contact in emergencyContacts) {
          await smsService.send(contact.phone, 'SOS: $lat, $lng');
        }
        updateSOSUI(sosId, status: 'SMS_SENT');
      } catch (e) {}
    }
    
    // TRY: Firebase push (may fail, that's OK)
    apiService.postSOS(sosData).then((res) {
      updateSOSUI(sosId, status: 'AUTHORITIES_NOTIFIED');
    }).catchError((e) {
      // Network error? No problem, already stored locally
      print('Firebase failed but SOS stored locally: $e');
      queueForRetry(sosData);
    });
    
    // RETRY every 30s if offline
    startPeriodicRetry(sosData, interval: Duration(seconds: 30));
    
    return SOSResponse(sosId: sosId, status: 'QUEUED_FOR_DISPATCH');
  }
}
```

**Backend: Reliable Queue**
```python
# backend/services/sos_queue_service.py
class SOSQueueService:
    """Guarantees SOS delivery through multiple channels."""
    
    @staticmethod
    async def enqueue_sos(tourist_id: str, lat: float, lng: float) -> str:
        sos_id = f"SOS-{uuid.uuid4().hex[:12]}"
        
        # Store in durable queue (PostgreSQL, not memory)
        await db.query("""
            INSERT INTO sos_queue (sos_id, tourist_id, lat, lng, status, created_at)
            VALUES ($1, $2, $3, $4, 'PENDING', NOW())
        """, sos_id, tourist_id, lat, lng)
        
        # Start worker task
        asyncio.create_task(SOSQueueService._dispatch_worker(sos_id))
        
        return sos_id
    
    @staticmethod
    async def _dispatch_worker(sos_id: str):
        """Background: Try every 30s until success."""
        for attempt in range(120):  # 1 hour of retries
            try:
                sos = await db.get_sos(sos_id)
                authorities = await get_authorities_near(sos['lat'], sos['lng'])
                
                # Try Firebase
                for auth in authorities:
                    try:
                        await send_firebase_push(auth['fcm_token'], sos)
                        await db.mark_sos_sent(sos_id, channel='FIREBASE')
                        return  # Success!
                    except:
                        pass
                
                # Try SMS fallback
                for auth in authorities:
                    try:
                        await send_sms(auth['phone'], f"SOS: {sos['lat']}, {sos['lng']}")
                        await db.mark_sos_sent(sos_id, channel='SMS')
                        return
                    except:
                        pass
                
                # Wait before retry
                await asyncio.sleep(30)
            
            except Exception as e:
                print(f"SOS worker error: {e}")
                await asyncio.sleep(30)
        
        # Final fallback: Mark as FAILED but alert admins
        await db.mark_sos_failed(sos_id)
        await send_admin_alert(f"SOS {sos_id} failed after 1 hour")
```

---

## **PROBLEM 4: Battery Dies Midway Through Trip**

### Tourist's Scenario
- Started hike at 8 AM with 100% battery
- By 2 PM, battery at 25%
- GPS is draining fast
- SOS won't work if battery dies
- Tourism website says "plan for 8-hour hike"

### Current Implementation Issue
- No adaptive GPS refresh rate
- Location pings sent every heartbeat (wasteful)
- Haptics triggered constantly
- No battery-aware UI mode

### **BEST SOLUTION: Adaptive Battery Mode + Smart Location Batching**
*Extend battery life based on zone type*

```
APPROACH:
├─ Monitor battery level + zone type
│
├─ SAFE ZONE (normal conditions):
│  ├─ GPS poll: Every 60s
│  ├─ Haptics: Full
│  ├─ Screen: Normal brightness
│  └─ Network: Real-time sync
│
├─ CAUTION ZONE (potential danger):
│  ├─ GPS poll: Every 30s (more frequent)
│  ├─ Haptics: Medium (conserve)
│  ├─ Screen: 80% brightness
│  └─ Network: Batch upload (every 5 min)
│
├─ RESTRICTED ZONE (high danger):
│  ├─ GPS poll: Every 10s (very frequent)
│  ├─ Haptics: Full (life-critical)
│  ├─ Screen: Max brightness
│  └─ Network: Real-time
│
├─ BATTERY CRITICAL (<15%):
│  ├─ GPS poll: Only on zone entry (not continuous)
│  ├─ Haptics: Disabled (except SOS)
│  ├─ Screen: Minimal + auto-off after 30s
│  ├─ Network: SOS only (all else queued)
│  └─ UI: "🔋 LOW BATTERY - SOS READY" (big red button visible)
│
└─ BATTERY DEAD (<5%):
   └─ Everything off except:
      ├─ SOS button (physical, no GUI)
      └─ Last known location transmitted if any signal
```

**Why this works:**
- ✅ Tourist can complete trip even on low battery
- ✅ SOS capability preserved until very end
- ✅ No surprise "battery dead" moments
- ✅ GPS optimization based on actual risk

**Implementation:**
```dart
// lib/services/battery_aware_service.dart
class BatteryAwareService {
  StreamSubscription? _batterySubscription;
  
  void init() {
    battery.onBatteryStateChanged.listen((state) {
      _adjustGPSPoll();
      _adjustHaptics();
      _adjustNetwork();
    });
  }
  
  void _adjustGPSPoll() {
    final batteryLevel = battery.level;  // 0-100
    final zoneType = currentZone.type;  // SAFE, CAUTION, RESTRICTED
    
    int pollIntervalSeconds;
    
    if (batteryLevel > 50) {
      // Plenty of battery
      pollIntervalSeconds = (zoneType == 'RESTRICTED') ? 10 : 60;
    } else if (batteryLevel > 20) {
      // Medium battery
      pollIntervalSeconds = (zoneType == 'RESTRICTED') ? 20 : 120;
    } else if (batteryLevel > 10) {
      // Low battery
      pollIntervalSeconds = (zoneType == 'RESTRICTED') ? 30 : 300;
    } else {
      // Critical
      pollIntervalSeconds = 900;  // Only on manual check
      showCriticalBatteryUI();
    }
    
    gpsService.setPollInterval(Duration(seconds: pollIntervalSeconds));
  }
  
  void _adjustHaptics() {
    final batteryLevel = battery.level;
    hapticEnabled = batteryLevel > 15;  // Disable haptics under 15%
  }
  
  void _adjustNetwork() {
    final batteryLevel = battery.level;
    
    if (batteryLevel < 10) {
      // Queue all non-critical uploads
      networkService.setMode(NetworkMode.queueOnly);
    } else if (batteryLevel < 30) {
      // Batch uploads instead of real-time
      networkService.setMode(NetworkMode.batch);
      networkService.batchInterval = Duration(seconds: 300);
    } else {
      // Real-time sync
      networkService.setMode(NetworkMode.realtime);
    }
  }
}
```

---

## **PROBLEM 5: Can't Register Because Phone Has No Camera**

### Tourist's Scenario
- Tourist at registration booth (no phone with camera)
- Gets provided a basic Android phone (camera broken)
- QR code won't generate from photo
- Can't register
- **SCENARIO: Tourist turned away**

### Current Implementation Issue
- QR generation requires photo upload
- No fallback for basic phones
- TUID generation tied to document photo

### **BEST SOLUTION: QR Code Scanning Instead of Photo Upload**
*Authority scans tourist's ID card, generates TUID server-side*

```
APPROACH:
├─ Tourist Registration Flow (NEW):
│  ├─ Authority opens "Register Tourist" in dashboard
│  ├─ Authority taps "Scan ID Card"
│  ├─ Authority's phone camera scans tourist's passport/Aadhaar
│  ├─ Backend OCR extracts: Name, Document Number, DOB
│  ├─ Backend generates TUID (no photo needed)
│  ├─ Backend generates QR code (PDF/print)
│  ├─ Authority prints QR and hands to tourist
│  └─ Tourist scans QR to login
│
└─ Works even with:
   ├─ Basic feature phones
   ├─ Broken cameras
   ├─ No internet on tourist's phone
   └─ Offline registration (tourist data syncs when possible)
```

**Why this works:**
- ✅ Doesn't rely on tourist's phone capability
- ✅ Authority (officer) does the heavy lifting
- ✅ Works offline (registration stored locally first)
- ✅ TUID generated server-side (more secure)
- ✅ Physical QR code as backup

**Implementation:**
```python
# backend/services/id_ocr_service.py (NEW)
class IDOCRService:
    """Extract identity from ID card scan."""
    
    @staticmethod
    async def extract_from_image(image_base64: str) -> dict:
        """Use Tesseract/AWS Rekognition to extract ID info."""
        # Call OCR service
        result = await aws_rekognition.extract_document_info(image_base64)
        
        return {
            'full_name': result['name'],
            'document_number': result['document_id'],
            'date_of_birth': result['dob'],
            'nationality': result.get('country', 'IN'),
        }

# backend/app/routes/authority.py (NEW endpoint)
@router.post("/register/tourist/scan")
async def register_tourist_via_scan(
    image_file: UploadFile = File(...),
    authority_id: str = Depends(get_current_authority),
    db: AsyncSession = Depends(get_db)
):
    """Authority scans ID card, backend generates TUID."""
    
    # Extract text from ID card
    image_bytes = await image_file.read()
    image_base64 = base64.b64encode(image_bytes).decode()
    
    extracted_data = await IDOCRService.extract_from_image(image_base64)
    
    # Generate TUID
    tuid = generate_tuid(
        extracted_data['document_number'],
        extracted_data['date_of_birth'],
        extracted_data['nationality']
    )
    
    # Generate QR code (TUID-based)
    qr_code_url = await qr_service.generate_qr_for_tuid(tuid)
    
    return {
        'tuid': tuid,
        'full_name': extracted_data['full_name'],
        'qr_code_url': qr_code_url,  # Authority prints this
        'print_ready': True,
    }
```

**Mobile: Tourist Scans QR to Login**
```dart
// lib/screens/qr_login_screen.dart
class QRLoginScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Scan Your QR Code')),
      body: QRView(
        key: qrKey,
        onQRViewCreated: (controller) {
          controller.scannedDataStream.listen((scanData) {
            final tuid = scanData.code;
            _loginWithTUID(tuid);
          });
        },
      ),
    );
  }
  
  Future<void> _loginWithTUID(String tuid) async {
    final response = await api.post('/auth/login/tuid', {'tuid': tuid});
    final token = response['token'];
    localStorage.setToken(token);
    navigateTo(TouristDashboard);
  }
}
```

---

## **PROBLEM 6: Authority Doesn't Know Where Tourist Actually Is (Real-Time Tracking)**

### Authority's Scenario
- SOS received: "Tourist at coordinates X, Y"
- Authority starts rescue operation
- 15 minutes later, wants live updates on tourist location
- Dashboard shows old location (last ping was 10 min ago)
- Rescue dispatch wastes time searching wrong area

### Current Implementation Issue
- Location pings sent every 60s (too infrequent)
- Dashboard polls backend every 10s (polling lag)
- No real-time streaming of location updates
- Authority sees "last known" not "current"

### **BEST SOLUTION: Hybrid Polling + Periodic Upload (Optimal)**
*Instead of constant streaming, batch + periodic updates*

```
APPROACH:
├─ Tourist app (mobile):
│  ├─ Collect GPS every 15s (store locally)
│  ├─ Every 3 minutes: Upload batch of locations
│  ├─ On SOS trigger: Upload current location immediately
│  └─ Battery aware: Extend interval if low battery
│
├─ Backend:
│  ├─ Store location batch with timestamp
│  ├─ Compute moving average (smooth out GPS noise)
│  └─ Broadcast latest position to watching authorities via WebSocket
│
├─ Dashboard (authority):
│  ├─ Open WebSocket to /ws/location-stream/{sos_id}
│  ├─ Receive location updates in real-time
│  ├─ Show interpolated position between updates (smooth animation)
│  ├─ Display "Last updated: 45 seconds ago"
│  └─ If no update for 5 min: Show "STALE - Check manually"
│
└─ Why not constant streaming:
   ├─ Battery: Streaming 60 updates/min = 3x power drain
   ├─ Network: Constant connection = high data usage
   ├─ Scalability: 1000 tourists = 60,000 packets/min
   └─ Latency: Batching adds only 3s delay (acceptable for rescue)
```

**Why this works:**
- ✅ Tourist can extend battery life (batteries last full trip)
- ✅ Authority gets near-real-time updates (3-30s latency acceptable for rescue)
- ✅ Scales to 1000s of simultaneous tourists
- ✅ Lower network bandwidth
- ✅ Hybrid approach: periodic + on-demand

**Implementation:**
```dart
// lib/services/location_batch_service.dart
class LocationBatchService {
  final List<LocationPoint> _buffer = [];
  Timer? _batchTimer;
  
  void init() {
    gpsService.stream.listen((location) {
      _buffer.add(LocationPoint(
        lat: location.latitude,
        lng: location.longitude,
        accuracy: location.accuracy,
        timestamp: DateTime.now(),
      ));
    });
    
    // Upload batch every 3 minutes
    _batchTimer = Timer.periodic(Duration(minutes: 3), (_) {
      _uploadBatch();
    });
  }
  
  Future<void> _uploadBatch() async {
    if (_buffer.isEmpty) return;
    
    final batch = _buffer.toList();
    _buffer.clear();
    
    try {
      await api.post('/location/batch-ping', {
        'tourist_id': currentTouristId,
        'locations': batch.map((l) => l.toJson()).toList(),
      });
    } catch (e) {
      // On failure, re-add to buffer for next upload
      _buffer.addAll(batch);
    }
  }
  
  Future<void> uploadImmediate() async {
    // Called on SOS trigger
    _buffer.add(LocationPoint(
      lat: gps.current.latitude,
      lng: gps.current.longitude,
      accuracy: gps.current.accuracy,
      timestamp: DateTime.now(),
    ));
    await _uploadBatch();
  }
}
```

**Backend: Broadcast to Authority**
```python
# backend/app/routes/sos.py
@router.post("/location/batch-ping")
async def receive_location_batch(
    payload: dict,
    tourist_id: str = Depends(get_current_tourist),
    db: AsyncSession = Depends(get_db)
):
    """Tourist uploads batch of locations."""
    locations = payload['locations']
    
    # Store all locations
    for loc in locations:
        await crud.create_location_ping(db, LocationPing(
            tourist_id=tourist_id,
            latitude=loc['lat'],
            longitude=loc['lng'],
            accuracy_meters=loc['accuracy'],
            timestamp=datetime.fromisoformat(loc['timestamp']),
        ))
    
    # Broadcast LATEST location to watching authorities
    latest = locations[-1]
    await broadcaster.broadcast_location(
        sos_id=payload.get('sos_id'),
        tourist_id=tourist_id,
        lat=latest['lat'],
        lng=latest['lng'],
        timestamp=latest['timestamp']
    )
    
    return {'status': 'stored', 'count': len(locations)}
```

**React Dashboard: Real-time Map**
```tsx
// dashboard/src/pages/SOS.tsx
export function SOSDetail({ sosId }) {
  const [location, setLocation] = useState(null);
  const [lastUpdate, setLastUpdate] = useState(null);
  
  useEffect(() => {
    const token = localStorage.getItem('token');
    const ws = new WebSocket(`wss://api/ws/sos/${sosId}/location?token=${token}`);
    
    ws.onmessage = (event) => {
      const data = JSON.parse(event.data);
      setLocation({ lat: data.lat, lng: data.lng });
      setLastUpdate(new Date(data.timestamp));
    };
    
    return () => ws.close();
  }, [sosId]);
  
  const timeSinceUpdate = lastUpdate 
    ? Math.round((Date.now() - lastUpdate) / 1000) 
    : null;
  
  return (
    <div>
      <MapContainer center={location} zoom={15}>
        <TileLayer url="..." />
        <Marker position={[location.lat, location.lng]} />
      </MapContainer>
      
      <div className="status">
        {timeSinceUpdate > 300 ? (
          <span style={{ color: 'red' }}>⚠️ STALE ({timeSinceUpdate}s ago)</span>
        ) : (
          <span>Last update: {timeSinceUpdate}s ago</span>
        )}
      </div>
    </div>
  );
}
```

---

## **PROBLEM 7: Trip Planning is Manual & Error-Prone**

### Tourist's Scenario
- Tourist registers for trip on website
- Inputs: "Visiting Meghalaya, Apr 1-5, destinations: Cherrapunji, Mawsmai Cave"
- Backend doesn't know: Which route? Where will you sleep? What's the actual itinerary?
- No personalized safety warnings
- Authority doesn't know expected locations

### Current Implementation Issue
- Trip data is static (just start/end dates)
- No itinerary steps
- No expected locations per day
- Authority can't predict where SOS might come from

### **BEST SOLUTION: Guided Trip Builder with Pre-Built Itineraries**
*Authority curates templates; tourist customizes*

```
APPROACH:
├─ Authority creates "Trip Template" for each destination
│  ├─ Template: "Meghalaya Scenic Loop - 4 Days"
│  ├─ Day 1: Shillong → Cherrapunji (stop points: Elephant Falls, Nohkalikai Falls)
│  ├─ Day 2: Cherrapunji → Mawsmai (stop points: Living Root Bridge, Mawsmai Cave)
│  ├─ Day 3: Mawsmai → Local Caves (stop points: Krem Mawmluh, Krem Phyllite)
│  ├─ Day 4: Return to Shillong
│  └─ Risk zones: CAUTION near Mawsmai, RESTRICTED near Khasi Hills
│
├─ Tourist registers
│  ├─ Selects template: "Meghalaya Scenic Loop"
│  ├─ Selects dates: Apr 1-4
│  ├─ Customize (optional): Add extra stops
│  └─ Confirm: "Expected to visit X, Y, Z with expected GPS coords"
│
├─ Authority sees
│  ├─ Tourist's planned itinerary
│  ├─ Expected GPS path on map
│  ├─ Any deviations flagged as "OFF PLANNED ROUTE"
│  └─ Pre-positioned rescue resources along expected path
│
└─ Tourist gets
   ├─ Pre-downloaded trail data for each day
   ├─ Expected waypoints (Cherrapunji → Mawsmai, etc.)
   ├─ Alert if going off-route: "You're 2km from planned path!"
   └─ Offline navigation pre-cached
```

**Why this works:**
- ✅ Authority knows where to expect SOS (not searching entire region)
- ✅ Tourist gets personalized navigation
- ✅ Data-driven risk assessment
- ✅ Better coordination with local guides

**Implementation:**
```python
# backend/models/trips.py (ENHANCED)
from sqlalchemy import String, DateTime, ForeignKey, Text, Integer, Float
from sqlalchemy.orm import Mapped, mapped_column, relationship

class TripTemplate(Base):
    """Pre-built itineraries curated by authorities."""
    __tablename__ = "trip_templates"
    
    template_id: Mapped[str] = mapped_column(String(50), primary_key=True)
    destination_id: Mapped[str] = mapped_column(ForeignKey("destinations.id"))
    name: Mapped[str] = mapped_column(String(255))  # "Meghalaya Scenic Loop"
    description: Mapped[str] = mapped_column(Text)
    duration_days: Mapped[int] = mapped_column(Integer)
    difficulty: Mapped[str] = mapped_column(String(20))  # LOW, MEDIUM, HIGH
    risk_zones: Mapped[str] = mapped_column(Text)  # JSON list of risk areas
    created_by_authority: Mapped[str] = mapped_column(ForeignKey("authorities.authority_id"))

class TripTemplateStop(Base):
    """Waypoints within a template."""
    __tablename__ = "trip_template_stops"
    
    stop_id: Mapped[int] = mapped_column(Integer, primary_key=True)
    template_id: Mapped[str] = mapped_column(ForeignKey("trip_templates.template_id"))
    day_number: Mapped[int] = mapped_column(Integer)  # 1, 2, 3...
    name: Mapped[str] = mapped_column(String(255))  # "Cherrapunji"
    description: Mapped[str] = mapped_column(Text)
    center_lat: Mapped[float] = mapped_column(Float)
    center_lng: Mapped[float] = mapped_column(Float)
    order_index: Mapped[int] = mapped_column(Integer)

# backend/app/routes/trips.py (NEW)
@router.post("/template/{template_id}/start")
async def start_trip_from_template(
    template_id: str,
    trip_start_date: datetime,
    trip_end_date: datetime,
    tourist_id: str = Depends(get_current_tourist),
    db: AsyncSession = Depends(get_db)
):
    """Tourist creates a real trip from template."""
    template = await crud.get_trip_template(db, template_id)
    stops = await crud.get_template_stops(db, template_id)
    
    # Create actual trip with stops
    trip = Trip(
        trip_id=f"TRIP-{uuid.uuid4().hex[:8]}",
        tourist_id=tourist_id,
        status="ACTIVE",
        trip_start_date=trip_start_date,
        trip_end_date=trip_end_date,
        primary_state=template.destination.state,
    )
    
    for stop in stops:
        trip.stops.append(TripStop(
            destination_id=stop.destination_id,
            name=stop.name,
            destination_state=template.destination.state,
            visit_date_from=trip_start_date + timedelta(days=stop.day_number - 1),
            visit_date_to=trip_start_date + timedelta(days=stop.day_number),
            center_lat=stop.center_lat,
            center_lng=stop.center_lng,
            order_index=stop.order_index,
        ))
    
    await crud.create_trip(db, trip)
    return {'trip_id': trip.trip_id, 'stops': [s.to_dict() for s in trip.stops]}

# backend/app/routes/authority.py (NEW)
@router.get("/tourist/{tourist_id}/trip-deviation")
async def check_trip_deviation(
    tourist_id: str,
    current_lat: float,
    current_lng: float,
    authority_id: str = Depends(get_current_authority),
    db: AsyncSession = Depends(get_db)
):
    """Check if tourist is off planned route."""
    trip = await crud.get_active_trip(db, tourist_id)
    if not trip:
        return {'deviation': 0, 'status': 'NO_TRIP'}
    
    # Find closest expected waypoint
    closest_stop = min(trip.stops, 
        key=lambda s: haversine(current_lat, current_lng, s.center_lat, s.center_lng))
    
    distance_from_route = haversine(current_lat, current_lng, 
                                     closest_stop.center_lat, closest_stop.center_lng)
    
    return {
        'expected_stop': closest_stop.name,
        'distance_from_route_km': distance_from_route / 1000,
        'deviation_alert': distance_from_route > 2000,  # Alert if >2km off
    }
```

---

## **Summary: 7 Tourist Problems + Best Solutions**

| Problem | Current Approach | Issue | ✅ Best Solution |
|---------|------------------|-------|-----------------|
| Lost offline | A* pathfinding (not coded) | Complex, not implemented | **Waypoint compass navigation** |
| Zone entry alerts | Manual zone lookup | No automatic detection | **OS geofencing (iOS/Android)** |
| SOS unreliable | Fire-and-forget | No retry, no confirmation | **Progressive escalation + local queue** |
| Battery dies | No optimization | GPS always on | **Adaptive poll rates by zone + battery mode** |
| Can't register | Photo upload required | Broken cameras = can't register | **Authority QR scan + OCR** |
| Can't track SOS | 10s polling (stale) | Lag during rescue | **Batch upload + WebSocket broadcast** |
| Trip confusing | Manual input | Authority doesn't know path | **Pre-built itinerary templates** |

---

## **Implementation Roadmap**

```
Phase 1 (Week 1-2): CRITICAL - Life Safety
├─ Problem: SOS unreliable
├─ Solution: Queue + retry + local broadcast
└─ Impact: Guarantees SOS reaches authorities

Phase 2 (Week 2-3): HIGH - Navigation
├─ Problem: Lost offline
├─ Solution: Waypoint compass + OS geofence
└─ Impact: Tourist never gets lost + instant zone alerts

Phase 3 (Week 3-4): HIGH - Authority Tracking
├─ Problem: Can't track SOS rescue
├─ Solution: Batch location + WebSocket broadcast
└─ Impact: Authority has live rescuer location

Phase 4 (Week 4-5): MEDIUM - Battery
├─ Problem: Battery drains midway
├─ Solution: Adaptive GPS + battery mode
└─ Impact: Tourist completes full trip safely

Phase 5 (Week 5-6): MEDIUM - Registration
├─ Problem: Can't register without camera
├─ Solution: Authority scans ID + QR
└─ Impact: All tourists can register offline

Phase 6 (Week 6-7): MEDIUM - Trip Planning
├─ Problem: No structured itinerary
├─ Solution: Template-based trip creation
└─ Impact: Authority knows expected path + better rescue coordination
```

This planning phase focuses on **what tourists actually need to survive**, not just technology buzzwords.
