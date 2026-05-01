# Attendance System

Web-first classroom attendance system with a Flutter client, Flask REST API,
PostgreSQL storage, Redis duplicate protection, and optional Nginx TLS proxy.

The instructor creates a session, shares a QR/link, students submit attendance
from the web app, and the instructor can view, export, reset, close, or reopen
the session.

## Current Architecture

```text
Browser / Flutter client
        |
        | REST JSON
        v
Nginx reverse proxy (optional TLS)
        |
        v
Flask API
   |             |
   | SQL         | duplicate cache
   v             v
PostgreSQL     Redis
```

## Features

- Web-first Flutter UI with instructor and student flows.
- Session lifecycle: create, list, view, close, reopen, reset.
- Student submission with name, roll number, optional comments, location, and
  device fingerprint.
- Duplicate protection through Redis plus PostgreSQL unique constraints.
- Optional geofencing per session.
- CSV export for attendance records.
- Admin-only instructor routes protected by `X-Admin-Key`.
- CIDR allow-list for LAN/campus deployment. `X-Real-IP` is honored only when
  proxy-header trust is explicitly enabled and the peer is a trusted proxy.

## Repository Layout

```text
flask_api/      Flask API routes, services, Dockerfile, Compose, schema, Nginx config
flutter_app/    Flutter web/Linux client
docs/           Architecture, backend, frontend, user, and stress-test docs
setup.sh        Fresh-machine helper
run_flutter.sh  Web-first Flutter runner
run_flask.sh    Direct local Flask runner for non-Docker development
```

## Backend Setup

Docker Compose is the recommended backend path. The default stack starts Flask,
PostgreSQL, and Redis. The Nginx TLS proxy is optional because it requires local
certificate files.

```bash
cd flask_api
cp .env.example .env
# edit ADMIN_KEY and DB_PASS in .env
docker-compose up --build
```

Health check:

```bash
curl http://127.0.0.1:5000/health
```

If you use `docker compose` instead of `docker-compose`, the commands are the
same except for the CLI spelling.

To include the Nginx proxy after adding `flask_api/certs/fullchain.pem` and
`flask_api/certs/privkey.pem`:

```bash
docker-compose --profile proxy up --build
```

## Flutter Web Setup

Run the web app from the repository root:

```bash
ADMIN_KEY=<same-value-as-flask_api/.env> \
API_BASE_URL=http://127.0.0.1:5000 \
APP_BASE_URL=http://localhost:8080 \
bash run_flutter.sh web
```

The app reads these values through `--dart-define`; do not hardcode production
secrets in `flutter_app/lib/config.dart`.

## API Overview

Implemented routes:

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| `GET` | `/health` | No | API health |
| `POST` | `/session/new` | Admin | Create session |
| `GET` | `/sessions` | Admin | List sessions |
| `GET` | `/session/<id>` | No | Read session metadata |
| `POST` | `/session/<id>/submit` | No | Submit attendance |
| `GET` | `/session/<id>/records` | Admin | Read records |
| `GET` | `/session/<id>/export` | Admin | Export CSV |
| `POST` | `/session/<id>/close` | Admin | Close session |
| `POST` | `/session/<id>/open` | Admin | Reopen session |
| `POST` | `/session/<id>/reset` | Admin | Delete records |

## Validation

Useful checks before publishing:

```bash
python3 -m compileall -q flask_api/main.py flask_api/config.py flask_api/errors.py flask_api/services flask_api/stress_test.py
cd flutter_app
flutter analyze
flutter test
flutter build web --no-pub
```

## Publish Notes

- Runtime data, local certs, `.env`, virtualenvs, Flutter build output, and CSV
  exports are ignored by the root `.gitignore`.
- `flask_api/.env.example` is safe to commit; `flask_api/.env` is not.
- Android APK support is future scope in this checkout because the Android
  platform directory is not currently present. The web app is the primary
  supported target.
