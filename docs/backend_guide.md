# Backend Guide

## Overview

The backend is a Flask REST API under `flask_api/`. `main.py` owns Flask setup,
middleware, routes, and response formatting. Configuration, error types, and
the database/cache/session workflows live in separate modules so failures are
easier to isolate.

Current implemented responsibilities:

- Health check.
- Create attendance sessions.
- List and read sessions.
- Accept student attendance submissions.
- Read records and export CSV.
- Close, reopen, and reset sessions.
- Enforce admin-key authentication on instructor routes.
- Reject requests from disallowed subnets.
- Reject duplicate submissions through Redis and database constraints.

## Source Layout

```text
flask_api/
├── main.py
├── config.py
├── errors.py
├── services/
│   ├── attendance_service.py
│   ├── cache_service.py
│   └── database.py
├── requirements.txt
├── stress_test.py
├── Dockerfile
├── docker-compose.yml
├── init.sql
├── nginx.conf
└── certs/
```

## Technology Stack

- Flask 3
- Flask-CORS
- PostgreSQL 15
- psycopg2
- Redis 7
- Gunicorn
- gevent workers
- Nginx reverse proxy
- Docker Compose

## Environment Variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `DB_HOST` | `localhost` | PostgreSQL host |
| `DB_NAME` | `attendance` | PostgreSQL database name |
| `DB_USER` | `admin` | PostgreSQL username |
| `DB_PASS` | `dev-db-password` in direct local mode | PostgreSQL password |
| `REDIS_HOST` | `localhost` | Redis host |
| `ADMIN_KEY` | `dev-admin-key` in direct local mode | Shared admin key for instructor routes |
| `PORT` | `5000` | Flask development server port |
| `ALLOWED_SUBNETS` | `127.0.0.1/32,::1/128,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12` | CIDR ranges allowed to call non-health routes |
| `TRUST_PROXY_HEADERS` | `false` | Whether to honor `X-Real-IP` from trusted proxy peers |
| `TRUSTED_PROXY_SUBNETS` | `127.0.0.1/32,::1/128` | CIDR ranges allowed to supply proxy headers |

Docker Compose sets these variables for the API container and includes common
private network ranges.

## Running With Docker Compose

From the backend directory:

```bash
cd /home/pro2024001/attendancesystem/flask_api
cp .env.example .env
# edit ADMIN_KEY and DB_PASS
docker-compose up --build
```

This starts:

- `cisco_api`: Flask API with Gunicorn.
- `cisco_postgres`: PostgreSQL database.
- `cisco_redis`: Redis cache.

The Nginx proxy is optional and is behind the `proxy` Compose profile because it
requires certificate files in `flask_api/certs/`:

```bash
docker-compose --profile proxy up --build
```

Health check:

```bash
curl http://127.0.0.1:5000/health
```

## Running Without Docker

Running without Docker requires local PostgreSQL and Redis with matching
credentials and schema. The simplest direct command is:

```bash
cd /home/pro2024001/attendancesystem/flask_api
source venv/bin/activate
python -m pip install -r requirements.txt
ADMIN_KEY=dev-admin-key DB_PASS=dev-db-password ALLOWED_SUBNETS=127.0.0.1/32 python main.py
```

The current `main.py` listens on `PORT`, defaulting to `5000`.

## Database Schema

The schema is initialized by `flask_api/init.sql` in Docker Compose. The API
also runs the same idempotent schema setup from `services/database.py` on first
database use, which keeps direct local runs aligned with Compose.

### `sessions`

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `VARCHAR(20)` | Primary key |
| `course_name` | `VARCHAR(100)` | Required |
| `created_at` | `TIMESTAMP` | Defaults to current timestamp |
| `is_active` | `BOOLEAN` | Defaults to `TRUE` |
| `geo_lat` | `DOUBLE PRECISION` | Optional geofence latitude |
| `geo_lon` | `DOUBLE PRECISION` | Optional geofence longitude |
| `geo_radius` | `DOUBLE PRECISION` | Radius in metres, defaults to `100` |

### `attendance`

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `SERIAL` | Primary key |
| `session_id` | `VARCHAR(20)` | References `sessions(id)` |
| `name` | `VARCHAR(120)` | Student name |
| `roll_no` | `VARCHAR(50)` | Required |
| `fingerprint` | `VARCHAR(255)` | Required |
| `latitude` | `DOUBLE PRECISION` | Optional submission latitude |
| `longitude` | `DOUBLE PRECISION` | Optional submission longitude |
| `comments` | `TEXT` | Optional comments |
| `submitted_at` | `TIMESTAMP` | Defaults to current timestamp |

Constraints:

- `UNIQUE(session_id, fingerprint)`
- `UNIQUE(session_id, roll_no)`

Indexes:

- `idx_att_session` on `attendance(session_id)`
- `idx_att_roll_no` on `attendance(roll_no)`

## Middleware

`restrict_subnet()` runs before every request except `/health`.

Behavior:

1. Reads `request.remote_addr`.
2. If `TRUST_PROXY_HEADERS=true`, reads `X-Real-IP` only when the remote peer is
   inside `TRUSTED_PROXY_SUBNETS`.
3. Parses the resolved client IP.
4. Checks whether the IP belongs to any CIDR in `ALLOWED_SUBNETS`.
5. Returns `403` for unauthorized networks.
6. Returns `400` for malformed IPs.

Nginx is configured to pass the true client IP through `X-Real-IP`. Enable
`TRUST_PROXY_HEADERS=true` only when Flask is behind a trusted proxy that
overwrites that header.

## Implemented API Endpoints

### `GET /health`

Purpose:

- Confirm that the API process is alive.

Example:

```bash
curl http://127.0.0.1:5000/health
```

Response:

```json
{
  "status": "ok",
  "infrastructure": "PostgreSQL + Redis + Host Nginx"
}
```

### `POST /session/new`

Purpose:

- Create a new attendance session.

Request:

```bash
curl -X POST http://127.0.0.1:5000/session/new \
  -H "Content-Type: application/json" \
  -H "X-Admin-Key: $ADMIN_KEY" \
  -d '{"course_name":"Data Structures"}'
```

Request body:

```json
{
  "course_name": "Data Structures"
}
```

Response:

```json
{
  "id": "A1B2C3D4E5",
  "session_id": "A1B2C3D4E5",
  "course_name": "Data Structures",
  "created_at": "2026-05-01T10:15:00",
  "is_active": true,
  "geo_lat": null,
  "geo_lon": null,
  "geo_radius": 100
}
```

Status codes:

- `201`: session created.
- `401`: admin key is missing or invalid.
- `403`: client subnet is not allowed.
- `500`: database connection or insert failure.

Notes:

- Session IDs are generated as 10-character uppercase hex strings.
- Empty or missing course names become `Default Course`.
- `geo_lat`, `geo_lon`, and `geo_radius` are stored when provided.

### `POST /session/<session_id>/submit`

Purpose:

- Submit attendance for one student.

Request:

```bash
curl -X POST http://127.0.0.1:5000/session/A1B2C3D4E5/submit \
  -H "Content-Type: application/json" \
  -d '{"name":"Ada Lovelace","roll_no":"PRO2024001","fingerprint":"DEVICE123","latitude":25.43,"longitude":81.77,"comments":""}'
```

Request body:

```json
{
  "name": "Ada Lovelace",
  "roll_no": "PRO2024001",
  "fingerprint": "DEVICE123",
  "latitude": 25.43,
  "longitude": 81.77,
  "comments": ""
}
```

Response:

```json
{
  "message": "Attendance recorded"
}
```

Status codes:

- `201`: attendance recorded.
- `400`: required fields are missing.
- `403`: session is closed or subnet is blocked.
- `404`: session does not exist.
- `409`: duplicate submission.

Duplicate protection:

1. Redis checks `attend:<session_id>:<fingerprint>`.
2. If present, the request returns `409`.
3. If absent, PostgreSQL insert is attempted.
4. PostgreSQL unique constraints catch race conditions.
5. On success, Redis caches the fingerprint for two hours.

## Other Implemented Endpoints

These routes are implemented for the Flutter instructor dashboard and student
session-loading flow:

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| `GET` | `/sessions` | Admin | List sessions |
| `GET` | `/session/<id>` | Public | Get one session |
| `GET` | `/session/<id>/records` | Admin | Get attendance records |
| `GET` | `/session/<id>/export` | Admin | Export CSV |
| `POST` | `/session/<id>/close` | Admin | Close session |
| `POST` | `/session/<id>/open` | Admin | Reopen session |
| `POST` | `/session/<id>/reset` | Admin | Delete records and clear Redis keys |

## Nginx Design

File: `flask_api/nginx.conf`

Behavior:

- Listens on port `80` and redirects to HTTPS.
- Listens on port `443` with the certificates in `flask_api/certs/`.
- Proxies requests to `127.0.0.1:5000`.
- Sets `X-Real-IP`; Flask honors it only when proxy-header trust is enabled and
  the proxy peer is trusted.
- Adds basic request limiting with `limit_req`.

## Security Design

Current layers:

- CIDR allow-list for non-health routes.
- Trusted-proxy checking before using `X-Real-IP`.
- Redis duplicate-submission interception.
- PostgreSQL uniqueness constraints.
- Nginx TLS termination.
- CORS enabled for frontend access.

Limitations:

- No JWT or per-user login.
- Device fingerprints are user-controlled input.
- No audit trail yet.

## Design Notes

The current backend has a focused, high-concurrency submission path:

- Keep session creation simple.
- Keep student submission small.
- Use Redis for fast duplicate detection.
- Use database constraints as the source of truth.
- Use subnet filtering to keep usage inside expected networks.

The next backend expansion should prioritize matching the existing Flutter
contract before adding new product features.
