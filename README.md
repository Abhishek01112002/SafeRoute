# SafeRoute

A tourist safety ecosystem for North East India using BLE Mesh, GPS, and Blockchain.

## Monorepo Architecture

This repository is structured as a monorepo containing three main modules:

### 1. `mobile/`
The Flutter mobile application used by tourists and authorities.
- **Stack**: Flutter, Dart, SQLite, BLE Mesh, WebSocket
- **Run**: `cd mobile && flutter run`

### 2. `backend/`
The Python FastAPI backend service that coordinates safety alerts and zone management.
- **Stack**: Python, FastAPI, PostgreSQL (or SQLite locally), JWT
- **Run**: `cd backend && uvicorn main:app --reload`

### 3. `dashboard/`
The React web application for authorities to manage zones and monitor SOS alerts.
- **Stack**: React, Vite, TypeScript, Leaflet
- **Run**: `cd dashboard && npm install && npm run dev`
