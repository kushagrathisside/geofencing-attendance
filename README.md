# GeoFencing Attendance

A lecture-attendance system for classrooms and labs. An instructor creates a **session** per lecture, students scan a QR code and submit attendance from their phones, and the instructor exports a CSV when done.

The backend is a **Flask REST API** with JWT authentication and SQLite storage. The frontend is a **Flutter** application that runs on Android, iOS, Linux desktop, and web from a single codebase.

---

## Table of Contents

- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Quick Start](#quick-start)
- [Environment Variables](#environment-variables)
- [Project Structure](#project-structure)
- [API Reference](#api-reference)
- [Authentication](#authentication)
- [Data Model](#data-model)
- [Geofencing](#geofencing)
- [Device Fingerprinting](#device-fingerprinting)
- [Deployment](#deployment)
- [Security Notes](#security-notes)

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Flutter App                          │
│            (Android · iOS · Web · Linux)                │
│                                                         │
│  ┌──────────────────────┐   ┌──────────────────────┐   │
│  │   Instructor Flow    │   │    Student Flow       │   │
│  │                      │   │                       │   │
│  │  Login → Sessions    │   │  Scan QR Code         │   │
│  │  Create / Manage     │   │  → /attend/<id>       │   │
│  │  Export CSV          │   │  Fill form → Submit   │   │
│  └──────────┬───────────┘   └──────────┬────────────┘  │
│             │  JWT Bearer               │  No Auth      │
└─────────────┼───────────────────────────┼───────────────┘
              │         HTTP/JSON          │
              ▼                           ▼
┌─────────────────────────────────────────────────────────┐
│                   Flask REST API                        │
│                                                         │
│  Auth        ─ /auth/login, /auth/me, /auth/change-pw  │
│  Accounts    ─ /accounts  (admin only)                  │
│  Sessions    ─ /session/new, /sessions, /session/<id>   │
│  Attendance  ─ /session/<id>/submit  (public)           │
│              ─ /session/<id>/records, /export           │
│  Lifecycle   ─ /session/<id>/open, /close, /reset       │
└──────────────────────────┬──────────────────────────────┘
                           │
                           ▼
              ┌────────────────────────┐
              │     SQLite Database    │
              │                        │
              │  instructors           │
              │  sessions              │
              │  attendance            │
              └────────────────────────┘
```

---

## Tech Stack

| Layer | Technology |
|---|---|
| Backend language | Python 3.10+ |
| Web framework | Flask 3.x |
| Authentication | JWT (`PyJWT`) + bcrypt password hashing |
| Geofencing | `geopy` geodesic distance |
| Database | SQLite 3 (via `sqlite3` stdlib) |
| CORS | `flask-cors` |
| XSS prevention | `markupsafe` |
| Frontend framework | Flutter 3.x (Dart) |
| HTTP client | `http` package |
| GPS | `geolocator` |
| Device ID | `device_info_plus` |
| Secure storage | `flutter_secure_storage` |
| QR generation | `qr_flutter` |
| CSV export | `share_plus` + `path_provider` |

---

## Quick Start

### Prerequisites

- Python 3.10+
- Flutter 3.x (`flutter` on `$PATH`)
- `uv` (optional, used by `setup.sh`) or `pip`

### 1. Clone and install

```bash
git clone https://github.com/your-org/geofencing-attendance.git
cd geofencing-attendance

# Install all dependencies (Python venv + Flutter packages)
bash setup.sh
```

### 2. Configure environment

```bash
cp .env.example .env
# Edit .env — set JWT_SECRET to a strong random value
```

### 3. Run

```bash
# Start Flask API + Flutter desktop app together
bash start.sh

# Or run them separately:
bash run_flask.sh          # API on http://0.0.0.0:8080
bash run_flutter.sh        # Flutter Linux desktop
```

On first run, a default admin account is created:

```
Username: admin
Password: admin123
```

Change this password immediately after first login via **Menu → Change Password**.

---

## Environment Variables

Set these in `.env` (loaded by `flask_api/main.py`) or export them before running.

| Variable | Default | Description |
|---|---|---|
| `JWT_SECRET` | `dev-secret` | **Required in production.** Signs all JWT tokens. Use a long random string. |
| `PORT` | `8080` | Port the Flask API listens on. |
| `DATABASE` | `attendance.db` | Path to the SQLite database file. |
| `JWT_EXPIRY_HOURS` | `2` | How long a login token stays valid. |
| `DEFAULT_ADMIN_USER` | `admin` | Username of the auto-created admin account. |
| `DEFAULT_ADMIN_PASS` | `admin123` | Password of the auto-created admin account. Change after first login. |
| `ENFORCE_LAN` | `0` | Set to `1` to reject requests from non-RFC-1918 IPs. |

> **Never commit `.env` to version control.** The `.gitignore` already excludes it.

---

## Project Structure

```
geofencing-attendance/
├── .env.example              # Environment variable template
├── .gitignore
├── setup.sh                  # One-shot install (venv + flutter pub get)
├── start.sh                  # Start API + desktop app together
├── run_flask.sh              # Start Flask API only
├── run_flutter.sh            # Start Flutter Linux desktop only
├── run_mobile.sh             # Build + run on connected Android device
│
├── flask_api/
│   ├── main.py               # Entire Flask application (single-file)
│   └── requirements.txt      # Python dependencies
│
└── flutter_app/
    ├── pubspec.yaml
    └── lib/
        ├── main.dart                          # App entry point, routing
        ├── config.dart                        # Compile-time constants (default URL, timeout)
        │
        ├── models/
        │   ├── session.dart                   # Session data class
        │   ├── attendance_record.dart         # AttendanceRecord data class
        │   └── instructor.dart                # Instructor account data class
        │
        ├── services/
        │   ├── auth_service.dart              # Login, JWT storage, server URL persistence
        │   ├── api_service.dart               # All HTTP calls
        │   └── fingerprint_service.dart       # Device fingerprint generation
        │
        ├── utils/
        │   ├── file_saver.dart                # Conditional export (native vs web)
        │   ├── file_saver_io.dart             # Dart IO implementation (mobile/desktop)
        │   └── file_saver_web.dart            # dart:html implementation (web)
        │
        └── screens/
            ├── home_screen.dart               # Entry screen (Instructor / Student selector)
            ├── login_screen.dart              # Instructor login + server URL config
            ├── instructor/
            │   ├── instructor_home.dart       # Session list
            │   ├── create_session_screen.dart # New session form with optional geofence
            │   ├── session_detail_screen.dart # QR code, records table, export, lifecycle
            │   └── accounts_screen.dart       # Admin: manage instructor accounts
            └── student/
                └── student_form_screen.dart   # Student attendance form
```

---

## API Reference

All endpoints return JSON. Error responses follow the shape `{ "error": "...", "message": "..." }`.

### Authentication

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `POST` | `/auth/login` | None | Authenticate and receive a JWT token |
| `GET` | `/auth/me` | Bearer | Get the current user's profile |
| `POST` | `/auth/change-password` | Bearer | Change own password |

**POST /auth/login**

```json
// Request
{ "username": "admin", "password": "admin123" }

// Response 200
{ "token": "<jwt>", "username": "admin", "role": "admin", "full_name": "Administrator" }
```

---

### Account Management _(admin role required)_

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `GET` | `/accounts` | Bearer (admin) | List all instructor accounts |
| `POST` | `/accounts` | Bearer (admin) | Create a new instructor account |
| `DELETE` | `/accounts/<id>` | Bearer (admin) | Delete an account |
| `POST` | `/accounts/<id>/reset-password` | Bearer (admin) | Reset another account's password |

**POST /accounts**

```json
// Request
{ "username": "prof.sharma", "password": "s3cur3!", "full_name": "Dr. Sharma", "role": "ta" }

// Response 201
{ "id": 3, "username": "prof.sharma", "full_name": "Dr. Sharma", "role": "ta" }
```

---

### Session Management

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `POST` | `/session/new` | Bearer | Create a new attendance session |
| `GET` | `/sessions` | Bearer | List all sessions |
| `GET` | `/session/<id>` | None | Get session info (used by students) |
| `POST` | `/session/<id>/close` | Bearer | Stop accepting submissions |
| `POST` | `/session/<id>/open` | Bearer | Re-open a closed session |
| `POST` | `/session/<id>/reset` | Bearer | Delete all attendance records for this session |

**POST /session/new**

```json
// Request — geofence fields are optional
{
  "course_name": "Introduction to Machine Learning",
  "geo_lat": 28.6139,
  "geo_lon": 77.2090,
  "geo_radius": 100
}

// Response 201
{
  "session_id": "A3F9C21B4D",
  "link": "http://192.168.1.10:8080/attend/A3F9C21B4D",
  "course_name": "Introduction to Machine Learning",
  "created_at": "2025-08-11T10:30:00+00:00"
}
```

---

### Attendance

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `GET` | `/attend/<id>` | None | Serve the student HTML form (browser fallback) |
| `POST` | `/session/<id>/submit` | None | Student submits attendance |
| `GET` | `/session/<id>/records` | Bearer | Get all attendance records as JSON |
| `GET` | `/session/<id>/export` | Bearer | Download attendance as CSV |

**POST /session/\<id\>/submit**

```json
// Request
{
  "name": "Priya Kapoor",
  "roll_no": "CS2301047",
  "fingerprint": "a3f2c1...",
  "latitude": 28.6141,
  "longitude": 77.2092,
  "comments": ""
}

// Response 201
{ "message": "Attendance recorded" }

// Response 403 — outside geofence
{ "error": "outside_geofence", "message": "You are 245m away. Maximum allowed: 100m." }

// Response 409 — duplicate submission
{ "error": "duplicate", "message": "Already submitted." }
```

---

### Utility

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `GET` | `/health` | None | Health check — returns `{ "status": "ok" }` |

---

## Authentication

The API uses **JWT Bearer tokens**.

```
POST /auth/login  →  { "token": "<jwt>" }

All protected requests:
  Authorization: Bearer <jwt>
```

Tokens expire after `JWT_EXPIRY_HOURS` (default 2 hours). On expiry the API returns `401` with `{ "error": "Token expired" }` — the Flutter app detects this and redirects to the login screen.

**Roles:**
- `admin` — full access: sessions, records, export, account management
- `ta` — can create and manage sessions and records, cannot manage accounts

Passwords are stored as **bcrypt hashes** (cost factor 12). Plaintext passwords are never logged or returned by any endpoint.

---

## Data Model

```sql
-- Instructor accounts
CREATE TABLE instructors (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    username   TEXT UNIQUE NOT NULL,
    password   TEXT NOT NULL,      -- bcrypt hash
    full_name  TEXT NOT NULL DEFAULT '',
    role       TEXT NOT NULL DEFAULT 'ta'  -- 'admin' | 'ta'
);

-- Attendance sessions (one per lecture)
CREATE TABLE sessions (
    id          TEXT PRIMARY KEY,  -- random 10-char hex
    course_name TEXT NOT NULL,
    created_at  TEXT NOT NULL,     -- ISO-8601 UTC
    is_active   INTEGER DEFAULT 1,
    geo_lat     REAL,              -- NULL = no geofencing
    geo_lon     REAL,
    geo_radius  REAL               -- metres
);

-- Individual attendance submissions
CREATE TABLE attendance (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id   TEXT NOT NULL REFERENCES sessions(id),
    submitted_at TEXT NOT NULL,
    name         TEXT NOT NULL,
    roll_no      TEXT NOT NULL,
    fingerprint  TEXT NOT NULL,
    latitude     REAL,
    longitude    REAL,
    comments     TEXT DEFAULT ''
);

-- Prevents the same device submitting twice in one session
CREATE UNIQUE INDEX idx_att_fp ON attendance(session_id, fingerprint);
```

---

## Geofencing

When a session is created with `geo_lat`, `geo_lon`, and `geo_radius`, every submission is validated on the server:

```python
from geopy.distance import geodesic

distance = geodesic(
    (session["geo_lat"], session["geo_lon"]),
    (student_lat, student_lon)
).meters

if distance > session["geo_radius"]:
    return 403  # outside fence
```

`geodesic` uses the WGS-84 ellipsoid model, which accounts for the Earth's curvature. This is more accurate than flat Euclidean distance for real-world GPS coordinates.

Geofencing is **optional**. Sessions created without geo fields accept submissions from any location.

**Desktop behaviour:** GPS is not available on Linux/Windows/macOS desktop. If a session has geofencing enabled and the student is on desktop, the Flutter app shows an explicit error asking them to use a mobile device instead of silently submitting `lat=0.0, lon=0.0`.

---

## Device Fingerprinting

Each device generates a stable fingerprint to prevent duplicate submissions within the same session.

| Platform | Source data |
|---|---|
| Android | SHA-256 of `android_id + model + brand` |
| iOS | SHA-256 of `identifierForVendor` |
| Web / Desktop | SHA-256 of `userAgent + vendor + platform` |

The server checks `SELECT id FROM attendance WHERE session_id=? AND fingerprint=?` before every insert. A match returns `409 Conflict`.

**Limitation:** Web fingerprints can be bypassed by using a different browser or an incognito window. For higher-assurance environments, supplement with a one-time PIN sent to a student email address.

---

## Deployment

### Flask API

```bash
# Set environment variables
export JWT_SECRET="$(openssl rand -hex 32)"
export PORT=8080

# Install dependencies
cd flask_api
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Run
python main.py
```

For production, run behind **gunicorn** and a reverse proxy (nginx):

```bash
pip install gunicorn
gunicorn -w 2 -b 0.0.0.0:8080 "main:app"
```

The API can be hosted on any platform that runs Python: **Render**, **Railway**, **Fly.io**, or a plain VPS.

### Flutter App

Configure the server URL at runtime from the login screen (**Advanced → Server URL**) — no rebuild needed.

```bash
# Android APK
flutter build apk --release

# Linux desktop
flutter build linux --release

# Web (host on Firebase Hosting, Netlify, or GitHub Pages)
flutter build web --base-href /
```

---

## Security Notes

| Area | Implementation |
|---|---|
| Passwords | bcrypt (cost 12) — never stored or logged in plaintext |
| Tokens | Short-lived JWT (2h default), differentiated expired vs invalid errors |
| XSS | `markupsafe.escape()` applied to all server-rendered HTML |
| Transport | HTTP on LAN by default; configure TLS via a reverse proxy for internet-facing deployments |
| Secret management | `JWT_SECRET` via environment variable; `.env` excluded from version control |
| LAN enforcement | Optional `ENFORCE_LAN=1` rejects requests from non-RFC-1918 addresses |
| Duplicate submissions | UNIQUE database index on `(session_id, fingerprint)` — enforced at the DB layer, not just application logic |
| SSL bypass | Removed — `http.Client()` used with no certificate override |
