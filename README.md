# Attendance App — Architecture & Interview Guide

## Project Overview

A lecture-attendance system where an instructor creates a **session** for each lecture,
shares a QR code, students submit attendance from their phones, and the instructor can
export a CSV and reset when done.

---

## System Architecture

```
┌─────────────────────────────────────┐
│           Flutter App               │
│   (Web · Android · iOS)             │
│                                     │
│  ┌────────────┐  ┌────────────────┐ │
│  │ Instructor │  │    Student     │ │
│  │   Screens  │  │  Form Screen   │ │
│  └─────┬──────┘  └──────┬─────────┘ │
│        │  HTTP REST JSON│           │
└────────┼───────────────┼────────────┘
         │               │
         ▼               ▼
┌─────────────────────────────────────┐
│         Flask REST API              │
│                                     │
│  • No templates — pure JSON         │
│  • CORS enabled (Flutter web)       │
│  • Admin key auth (header)          │
│  • Geofence validation              │
│  • Duplicate fingerprint check      │
│  • CSV export                       │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│          SQLite Database            │
│                                     │
│  sessions   │  attendance           │
│  ─────────  │  ──────────           │
│  id (PK)    │  id (PK)              │
│  course_name│  session_id (FK)      │
│  created_at │  submitted_at         │
│  is_active  │  name                 │
│  geo_lat    │  roll_no              │
│  geo_lon    │  fingerprint          │
│  geo_radius │  latitude             │
│             │  longitude            │
└─────────────────────────────────────┘
```

---

## Key Design Decisions

### 1. Session-based model (not date-based)

**Old approach:** one CSV per date (`IML-2025-08-11.csv`).

**Problem:** a lecturer might have multiple lectures in a day, or forget to reset.

**New approach:** every lecture is an explicit **session** with a unique ID.
The instructor controls the lifecycle: create → share → collect → export → reset/close.

---

### 2. Flask as a pure REST API (no HTML templates)

Flask's only job is business logic and storage. It returns JSON.
Flutter owns all UI. This separation means:
- The same API can serve a web app, mobile app, or even a CLI tool.
- Flutter can be swapped out without touching Flask.
- Flask can be deployed independently (Render, Railway, any VPS).

---

### 3. SQLite over CSV for storage

| | CSV | SQLite |
|---|---|---|
| Multi-session | One file per session, manual management | Single DB, indexed queries |
| Duplicate check | O(n) full-file scan | O(1) indexed lookup |
| Export | Already CSV | Flask queries → streams CSV |
| Complexity | Simple | Slightly more setup |

SQLite is still a single file, zero-config, and ships with Python.
We still offer CSV **export** — SQLite is just the internal store.

---

### 4. Anti-duplication: device fingerprinting

Each device produces a fingerprint:
- **Android:** SHA of `android_id + model + brand`
- **iOS:** SHA of `identifierForVendor`
- **Web:** hash of `userAgent + vendor + platform`

Flask checks `SELECT id FROM attendance WHERE session_id=? AND fingerprint=?`
before every insert. If a row exists → 409 Conflict → student sees "Already submitted".

**Limitation:** fingerprints can be spoofed on web (change browser/incognito).
For higher security, add a one-time PIN sent to student email.

---

### 5. Geofencing

When a session is created with `geo_lat`, `geo_lon`, and `geo_radius`:

```python
from geopy.distance import geodesic
distance = geodesic((session.geo_lat, session.geo_lon), (student_lat, student_lon)).meters
if distance > session.geo_radius:
    return 403  # outside fence
```

The geodesic distance accounts for the Earth's curvature (more accurate than
flat Euclidean distance for real-world coordinates).

Geofencing is **optional** — sessions without a geolocation accept submissions from anywhere.

---

### 6. Admin authentication

A single shared secret (`ADMIN_KEY` env var) is sent as an HTTP header:

```
X-Admin-Key: supersecret
```

The `@require_admin` decorator checks this on every instructor-only route.

**Interview note:** this is sufficient for a classroom tool. For production, you would use
JWT tokens (Flask-JWT-Extended) with per-user credentials.

---

## API Endpoints at a Glance

| Method | Endpoint | Auth | Purpose |
|--------|----------|------|---------|
| POST | `/session/new` | Admin | Create session → get ID + link |
| GET | `/sessions` | Admin | List all sessions |
| GET | `/session/<id>` | Public | Get session info (student uses this) |
| POST | `/session/<id>/submit` | Public | Student submits attendance |
| GET | `/session/<id>/records` | Admin | Get all records as JSON |
| GET | `/session/<id>/export` | Admin | Download CSV |
| POST | `/session/<id>/close` | Admin | Stop accepting submissions |
| POST | `/session/<id>/open` | Admin | Re-open a closed session |
| POST | `/session/<id>/reset` | Admin | Delete all records |

---

## Flutter App Structure

```
lib/
├── main.dart                        # App entry, routing
├── config.dart                      # API base URL, admin key
│
├── models/
│   ├── session.dart                 # Session data class + fromJson
│   └── attendance_record.dart       # AttendanceRecord + fromJson
│
├── services/
│   ├── api_service.dart             # All HTTP calls (one class)
│   └── fingerprint_service.dart     # Device fingerprint generation
│
└── screens/
    ├── home_screen.dart             # Role selector (Instructor / Student)
    ├── instructor/
    │   ├── instructor_home.dart     # Session list
    │   ├── create_session_screen.dart
    │   └── session_detail_screen.dart  # QR, records, export, reset
    └── student/
        └── student_form_screen.dart # The attendance form
```

**Routing:**
- `/`              → role selector
- `/instructor`    → instructor home
- `/attend/<id>`   → student form (the QR code links here)

`setPathUrlStrategy()` removes the `#` from Flutter web URLs so QR codes
like `https://yourapp.com/attend/A3F9C21B4D` work correctly.

---

## Data Flow: Student Submitting Attendance

```
Student scans QR → opens /attend/A3F9C21B4D
        │
        ▼
Flutter fetches GET /session/A3F9C21B4D
        │   (checks: does it exist? is it active?)
        ▼
Student fills form → taps "Mark My Attendance"
        │
        ▼
Flutter requests GPS permission → geolocator.getCurrentPosition()
        │   (native GPS, more accurate than browser geolocation)
        ▼
Flutter calls FingerprintService.getFingerprint()
        │   (device_info_plus → stable device ID)
        ▼
Flutter POSTs to /session/A3F9C21B4D/submit
  { name, roll_no, latitude, longitude, fingerprint }
        │
        ▼
Flask validates:
  1. Session exists + is_active == 1
  2. Geofence: geodesic distance ≤ geo_radius
  3. Duplicate: SELECT ... WHERE fingerprint = ?
        │
        ├── All pass → INSERT INTO attendance → 201 Created → ✅ Thank You
        ├── Geofence fail → 403 → ❌ Too far away
        └── Duplicate → 409 → ⚠️ Already submitted
```

---

## Deployment

### Flask API

```bash
# Local
pip install flask flask-cors geopy
ADMIN_KEY=yoursecret python main.py

# Render / Railway (free tier)
# Set env vars: ADMIN_KEY, APP_BASE_URL, PORT
# Start command: python main.py
```

### Flutter App

```bash
# Web (host on Firebase / Netlify / GitHub Pages)
flutter build web --base-href /

# Android APK
flutter build apk --release

# iOS
flutter build ios --release
```

Set `kBaseUrl` in `lib/config.dart` to your deployed Flask URL before building.

---

## What To Say In An Interview (90-second version)

> "The app follows a clean client-server separation. Flutter is the UI layer — it
> runs on web, Android, and iOS from a single codebase. Flask is a stateless REST
> API that handles all business logic and stores data in SQLite.
>
> The core entity is a **session**, representing one lecture. The instructor creates
> a session via a POST endpoint, which generates a unique ID and stores the session's
> geofence config — coordinates and an allowed radius. Flask returns a shareable URL
> containing the session ID, which the Flutter app renders as a QR code.
>
> When a student scans the QR, Flutter fetches the session to confirm it's active,
> then collects GPS coordinates natively via `geolocator` and a device fingerprint
> via `device_info_plus`. It POSTs these to Flask's submit endpoint. Flask validates
> two things: first, the geofence — it uses `geopy`'s geodesic distance to check
> whether the student is within the allowed radius. Second, duplicates — it queries
> for an existing fingerprint within the same session and returns a 409 if found.
>
> The instructor can then call `/export` to stream a CSV, or `/reset` to clear
> records. Flask is completely stateless — all state lives in SQLite — which makes
> it easy to deploy on any platform."

---

## Potential Improvements (for discussion)

| Improvement | Why |
|---|---|
| JWT auth instead of shared API key | Per-user instructor accounts |
| WebSocket or SSE for live updates | Instructor dashboard auto-refreshes |
| One-time roll-number PIN via email | Stronger anti-spoofing on web |
| PostgreSQL instead of SQLite | Multi-instance deployment |
| Rate limiting (Flask-Limiter) | Prevent submission flooding |
| Offline support in Flutter | Submit later if no connection |
