# SafeRoute: AI & ML Implementation Roadmap

This document outlines a structured, high-impact Artificial Intelligence (AI) and Machine Learning (ML) integration roadmap for SafeRoute. The focus is strictly on **safety, security, and offline reliability** to make the app an essential, life-saving tool for tourists in extreme environments.

---

## 1. Phase 1: On-Device Edge AI (Offline Capabilities)
*These models run directly on the smartphone without requiring an internet connection. Crucial for remote mountain and forest areas.*

### A. Fall & Abnormal Movement Detection (Sensors AI)
**Objective:** Automatically detect if a tourist has suffered a severe fall, crash, or is running in panic, and trigger an automated SOS if they become unresponsive.

**Implementation Steps:**
1. **Data Collection:** Collect dataset of human movements (walking, running, falling, sudden impacts) using phone accelerometer and gyroscope data (e.g., MobAct or SisFall datasets).
2. **Model Training:** Train a lightweight Time-Series model (e.g., Random Forest or a small 1D-CNN/LSTM) using Python (TensorFlow/Keras).
3. **Conversion:** Convert the trained model to `.tflite` (TensorFlow Lite) to ensure the file size is under 5MB.
4. **App Integration:**
   - Integrate the `tflite_flutter` package in the SafeRoute mobile app.
   - Run a background service that samples sensor data every few seconds and feeds it to the model.
5. **Action Logic:** If a "Fall" is predicted with >90% confidence -> Trigger a 10-second loud alarm and UI prompt. If not dismissed -> Automatically dispatch the **Offline Mesh SOS Packet**.

### B. Smart Battery & Connectivity Predictor
**Objective:** Warn tourists to conserve battery before they enter known dead-zones or cold areas where battery drains faster.

**Implementation Steps:**
1. **Feature Engineering:** Use inputs like Current Battery %, Altitude, GPS Location, and Local Temperature.
2. **Model:** A very simple Regression model or rule-based heuristic engine.
3. **App Integration:** When a user sets a destination or enters a geofence, the app calculates the estimated battery drain.
4. **Action:** Prompt the user: *"You are entering a zero-network zone with low temperatures. Your 40% battery might only last 2 hours. Switch to Power Saving Mode now."*

---

## 2. Phase 2: Backend AI (Cloud & Predictive Analytics)
*These models reside on the backend server (`backend/app/services/ai/`) and require internet to process large datasets and provide intelligent routing.*

### A. Dynamic Route Risk Scoring System
**Objective:** Assign a dynamic "Safety Score" (1-100) to trails and routes based on real-time and historical data.

**Implementation Steps:**
1. **Data Aggregation:** Connect APIs for real-time Weather (wind, rain, temperature), Historical Accident/SOS data, and Time-of-Day.
2. **Model Training:** Use `scikit-learn` or `XGBoost` in Python to create a risk classification model.
   - *Features:* Trail steepness, weather severity, time until sunset, past incident frequency.
3. **Backend Integration:** Create a FastAPI endpoint `/api/v3/routes/risk-score`.
4. **App UI:** When a tourist views a downloaded map, routes dynamically color-code (Green = Safe, Yellow = Caution, Red = Highly Dangerous).

### B. Smart SOS Triage & Contextualization
**Objective:** Provide Rescue Authorities with an intelligent summary of the emergency rather than just raw coordinates.

**Implementation Steps:**
1. **Context Engine:** When the backend receives an SOS (via internet or mesh gateway), a Python script gathers the user's last known state (battery, altitude, weather at coordinates).
2. **LLM/NLP Summarization:** Pass this data to a fast LLM API (like Gemini or OpenAI) or use a rigid templating engine to generate a high-priority summary.
3. **Output to Dashboard:** Display to authorities: *"HIGH PRIORITY: Tourist likely injured (Fall Detected). Altitude 3200m. Weather dropping to -2°C in 1 hour. Battery 12%."* This helps them decide between a foot rescue or helicopter dispatch.

---

## 3. Phase 3: Advanced Futuristic Enhancements

### A. Offline First-Aid & Survival SLM (Small Language Model)
**Objective:** Provide a pocket survival guide that can answer contextual medical or survival questions without internet.

**Implementation Steps:**
1. **Model Selection:** Use a highly quantized Small Language Model (SLM) like **Gemma 2B** or **Phi-3 Mini** (4-bit quantization, approx. 1.5GB size).
2. **Deployment:** Use frameworks like `MediaPipe` or `MLC LLM` to run the model natively on iOS and Android.
3. **Use Case:** A tourist types/speaks: *"I was bitten by a snake with a diamond pattern, what should I do?"* The offline AI instantly provides critical first-aid steps.

### B. Acoustic Threat Detection (Audio AI)
**Objective:** Detect environmental dangers by listening to the surroundings.

**Implementation Steps:**
1. **Model:** Use Google's `YAMNet` (quantized for mobile), which can recognize 521 audio events.
2. **Optimization:** Run audio sampling locally in chunks to save battery.
3. **Triggers:** Set strict confidence thresholds for sounds like "Gunshot", "Scream", or "Wild Animal Growl".
4. **Action:** If detected, silently switch the app to high-frequency location tracking and prep an SOS payload.

### C. Crowd & Stampede Predictor (Authority Level)
**Objective:** Prevent disasters in narrow, highly-populated religious or tourist treks (e.g., Kedarnath, Kumbh).

**Implementation Steps:**
1. **Clustering:** Use backend algorithms (like DBSCAN) on the live location data of all active SafeRoute users.
2. **Density Mapping:** Calculate user density per square meter on the map.
3. **Action:** If density crosses a critical threshold, trigger a "Stampede Warning" to the Authority Dashboard and send push notifications diverting incoming tourists to alternate holding zones.

---

## Summary of Tech Stack Required

| Feature | Tech Stack / Tool | Where it runs |
| :--- | :--- | :--- |
| **Fall Detection** | TensorFlow Lite, tflite_flutter | Mobile App (Offline) |
| **Survival Assistant** | Gemma 2B (Quantized), MLC LLM | Mobile App (Offline) |
| **Risk Scoring** | FastAPI, scikit-learn, XGBoost | Backend Server |
| **Smart SOS Triage** | Python, LLM API | Backend Server |
| **Stampede Predictor** | Python, DBSCAN (Clustering) | Backend Server |
