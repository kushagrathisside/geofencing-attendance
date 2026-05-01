# Architectural Documentation

## System Purpose

The attendance system is designed for LAN or campus-network classroom use. It
lets instructors create short-lived sessions and lets students submit attendance
with duplicate protection.

The project currently contains:

- Flutter client for user interaction.
- Flask REST API for session and attendance operations.
- PostgreSQL for durable storage.
- Redis for duplicate-submission caching.
- Nginx for HTTPS proxying and client IP forwarding.

## High-Level Architecture

```text
Student / Instructor Device
          |
          | Flutter app HTTP/HTTPS requests
          v
Nginx Reverse Proxy
          |
          | X-Real-IP forwarded to Flask
          v
Flask API
   |             |
   | SQL         | Redis key lookup
   v             v
PostgreSQL     Redis
```

For local development, the Flutter app may call the Flask API directly on
`http://127.0.0.1:5000`.

## Components

### Flutter Client

Responsibilities:

- Render instructor and student workflows.
- Generate and display QR codes.
- Capture GPS location where supported.
- Generate a device fingerprint.
- Call the Flask API.
- Present friendly loading, success, duplicate, closed, and error states.

Primary files:

- `flutter_app/lib/main.dart`
- `flutter_app/lib/config.dart`
- `flutter_app/lib/services/api_service.dart`
- `flutter_app/lib/services/fingerprint_service.dart`
- `flutter_app/lib/screens/`

### Flask API

Responsibilities:

- Validate network access by CIDR.
- Create sessions.
- List sessions, read session details, and manage lifecycle state.
- Verify session existence and active state.
- Store attendance details and optional geofence coordinates.
- Export session records as CSV.
- Return conflict responses for duplicates.

Primary files:

- `flask_api/main.py`
- `flask_api/config.py`
- `flask_api/errors.py`
- `flask_api/services/attendance_service.py`
- `flask_api/services/cache_service.py`
- `flask_api/services/database.py`

### PostgreSQL

Responsibilities:

- Store sessions.
- Store attendance rows.
- Enforce uniqueness across session plus fingerprint.
- Enforce uniqueness across session plus roll number.

Schema file:

- `flask_api/init.sql`

### Redis

Responsibilities:

- Cache a successful `(session_id, fingerprint)` submission for two hours.
- Intercept repeated submissions before they hit PostgreSQL.

Key format:

```text
attend:<session_id>:<fingerprint>
```

### Nginx

Responsibilities:

- Terminate TLS.
- Redirect HTTP to HTTPS.
- Proxy requests to Flask.
- Forward true client IP in `X-Real-IP`.
- Apply basic request limiting.

Config file:

- `flask_api/nginx.conf`

## Data Model

```text
sessions
--------
id          primary key
course_name
created_at
is_active
geo_lat
geo_lon
geo_radius

attendance
----------
id          primary key
session_id  foreign key to sessions.id
name
roll_no
fingerprint
latitude
longitude
comments
submitted_at
```

Relationships:

- One session has many attendance records.
- Deleting a session cascades to attendance records.

Integrity rules:

- One fingerprint can submit once per session.
- One roll number can submit once per session.

## Request Flows

### Health Check

```text
Client -> Flask /health -> JSON status
```

This route bypasses the subnet filter.

### Create Session

```text
Instructor -> POST /session/new
Flask -> validate subnet
Flask -> validate admin key
Flask -> generate session ID
Flask -> insert into PostgreSQL
Flask -> return session ID
```

### Submit Attendance

```text
Student -> POST /session/<id>/submit
Flask -> validate subnet
Flask -> require name, roll_no, and fingerprint
Flask -> check Redis duplicate key
Flask -> load session from PostgreSQL
Flask -> reject missing or closed session
Flask -> enforce geofence when configured
Flask -> insert attendance row
PostgreSQL -> enforce unique constraints
Flask -> cache fingerprint in Redis for 2 hours
Flask -> return success or duplicate conflict
```

## Deployment Topology

Docker Compose runs three default services, with Nginx available through an
optional `proxy` profile:

```text
api    -> Flask/Gunicorn container
cache  -> redis:7-alpine
db     -> postgres:15-alpine
proxy  -> nginx:alpine, host network, optional profile
```

Network behavior:

- `proxy` uses host networking.
- `api`, `cache`, and `db` use the `backend_net` bridge network.
- The API exposes `127.0.0.1:5000:5000`.
- Nginx proxies to `127.0.0.1:5000`.

## Security Architecture

### Network Boundary

The Flask middleware accepts only configured CIDR ranges. Direct requests are
checked using `request.remote_addr`. If `TRUST_PROXY_HEADERS=true`, Flask uses
`X-Real-IP` only from peers inside `TRUSTED_PROXY_SUBNETS`, allowing Nginx to
forward the real client IP without letting direct clients spoof it.

### Duplicate Defense

Duplicate protection uses two layers:

1. Redis cache for fast rejection.
2. PostgreSQL unique constraints for correctness during races.

### TLS Boundary

Nginx terminates HTTPS using certificates from `flask_api/certs/`.

### Current Security Gaps

- There is no user login.
- There is no strong proof that a fingerprint belongs to a real student.
- Admin authentication is a shared key, not per-instructor identity.

## Frontend-Backend Contract

Current implemented backend contract:

| Method | Path | Auth |
| --- | --- | --- |
| `GET` | `/health` | Public |
| `POST` | `/session/new` | Admin |
| `GET` | `/sessions` | Admin |
| `GET` | `/session/<id>` | Public |
| `POST` | `/session/<id>/submit` | Public |
| `GET` | `/session/<id>/records` | Admin |
| `GET` | `/session/<id>/export` | Admin |
| `POST` | `/session/<id>/close` | Admin |
| `POST` | `/session/<id>/open` | Admin |
| `POST` | `/session/<id>/reset` | Admin |

## Scalability Considerations

Current strengths:

- PostgreSQL handles durable concurrent writes.
- Redis reduces duplicate write pressure.
- Gunicorn with gevent supports concurrent requests.
- Nginx can throttle excessive traffic.

Current limits:

- Every request opens a new PostgreSQL connection.
- No connection pooling.
- No structured metrics.
- No background cleanup for Redis or old sessions beyond Redis TTL.
- No horizontal API scaling notes yet.

Potential improvements:

- Add a PostgreSQL connection pool.
- Add structured request logging.
- Add Prometheus metrics or OpenTelemetry traces.
- Replace shared admin key with per-instructor login if this grows beyond a LAN classroom tool.
- Regenerate and validate Android platform files if APK release becomes a goal.
