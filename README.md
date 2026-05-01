# Geofencing Attendance

A scalable, web-first attendance management platform designed for controlled environments such as campuses and enterprise training systems. The system integrates geofencing, duplicate detection, and network-level validation to ensure reliable and tamper-resistant attendance tracking.

---

## 🧭 Product Vision

Geofencing Attendance enforces three core guarantees:

- Presence must be **location-valid**
- Identity must be **consistent**
- Submissions must be **non-duplicated**

This is achieved using:
- CIDR-based network boundaries
- Redis-backed duplicate detection
- PostgreSQL constraint enforcement
- Optional geofence validation

---

## 🏗️ High-Level Architecture (HLD)

### System Layers

**Client Layer (Flutter Web)**
- Instructor dashboard and student interface
- QR-based session access
- Device fingerprinting and optional GPS capture

**Edge Layer (Nginx - Optional)**
- TLS termination
- Reverse proxy
- Request throttling
- Real IP forwarding

**Application Layer (Flask API)**
- Stateless REST services
- Session lifecycle control
- Validation logic (geofence, duplicates, subnet)

**Data Layer**
- PostgreSQL → persistent storage and constraints
- Redis → fast duplicate detection

---

## 🧱 Low-Level Design (LLD)

### Attendance Submission Flow

1. Request reaches Flask API
2. Subnet validation using CIDR rules
3. Payload validation (name, roll number, fingerprint)
4. Redis lookup for duplicate detection
5. Session validation from PostgreSQL
6. Geofence validation (if enabled)
7. Insert attendance record
8. PostgreSQL enforces uniqueness constraints
9. Redis cache updated with TTL
10. Response returned to client

### Design Guarantees

- Constant-time duplicate rejection via Redis
- Strong consistency via database constraints
- Minimal latency in write path
- Safe handling of race conditions

---

## ✨ Core Features

### Session Lifecycle
- Create, list, view sessions
- Close, reopen, reset attendance
- QR and link-based access

### Attendance Submission
- Name and roll number validation
- Device fingerprint tracking
- Optional GPS capture
- Real-time feedback (success, duplicate, closed)

### Geofencing
- Radius-based validation per session
- Enforced at submission time

### Data Export
- CSV export of attendance records

### Security
- Admin routes protected via X-Admin-Key
- CIDR subnet allow-list
- Proxy-aware IP validation
- Optional TLS via Nginx

---

## 📁 Repository Structure

```
.
├── flask_api/        Backend (Flask, services, Docker, DB)
├── flutter_app/      Flutter web client
├── docs/             Documentation
├── setup.sh          Setup helper
├── run_flutter.sh    Run frontend
├── run_flask.sh      Run backend locally
```

---

## ⚙️ Backend Setup

### Docker Compose (Recommended)

```
cd flask_api
cp .env.example .env
docker-compose up --build
```

Health check:

```
curl http://127.0.0.1:5000/health
```

### Enable Nginx Proxy

```
docker-compose --profile proxy up --build
```

---

## 🌐 Frontend Setup

```
ADMIN_KEY=<your_key> \
API_BASE_URL=http://127.0.0.1:5000 \
APP_BASE_URL=http://localhost:8080 \
bash run_flutter.sh web
```

---

## 🔌 API Overview

| Method | Endpoint | Access | Description |
|--------|----------|--------|-------------|
| GET | /health | Public | Health check |
| POST | /session/new | Admin | Create session |
| GET | /sessions | Admin | List sessions |
| GET | /session/<id> | Public | Get session |
| POST | /session/<id>/submit | Public | Submit attendance |
| GET | /session/<id>/records | Admin | Fetch records |
| GET | /session/<id>/export | Admin | Export CSV |
| POST | /session/<id>/close | Admin | Close session |
| POST | /session/<id>/open | Admin | Reopen session |
| POST | /session/<id>/reset | Admin | Reset session |

---

## 🗄️ Data Model

### Sessions
- id
- course_name
- created_at
- is_active
- geo_lat, geo_lon, geo_radius

### Attendance
- session_id
- name
- roll_no
- fingerprint
- latitude, longitude
- comments
- submitted_at

### Constraints
- Unique(session_id, fingerprint)
- Unique(session_id, roll_no)

---

## 🔁 Duplicate Protection Strategy

**Layer 1: Redis**
- Fast in-memory duplicate detection
- Key format: attend:<session_id>:<fingerprint>
- TTL-based caching

**Layer 2: PostgreSQL**
- Enforces uniqueness constraints
- Handles race conditions safely

---

## 🧪 Stress Testing

```
cd flask_api
ADMIN_KEY=<key> python stress_test.py
```

Expected result:
- 1 successful submission
- Remaining rejected as duplicates
- Zero failures

---

## 🧠 Design Principles

- Fast write-heavy system design
- Defense-in-depth validation
- Stateless API architecture
- Network-restricted trust model
- Web-first deployment strategy

---

## ⚠️ Current Limitations

- No user authentication system
- Device fingerprint is not strongly verifiable
- No connection pooling for database
- No observability (metrics/logging)
- Android support not finalized

---

## 📚 Documentation

- docs/user_manual.md
- docs/frontend_guide.md
- docs/backend_guide.md
- docs/architecture.md
- docs/stress_testing.md

---

## 🧪 Validation

```
python3 -m compileall flask_api

cd flutter_app
flutter analyze
flutter test
flutter build web --no-pub
```

---

## 📦 Publishing Notes

- Do not commit .env files
- Commit .env.example only
- Ignore build outputs and runtime data
- Web platform is primary target

---

## 🚀 Future Improvements

- JWT-based authentication system
- Instructor identity management
- Observability (Prometheus / OpenTelemetry)
- Connection pooling for PostgreSQL
- Horizontal scaling support
- Android platform stabilization

---
