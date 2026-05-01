# User Manual

## Purpose

This application manages classroom attendance sessions. An instructor creates a
session, shares a QR code or link, and students submit attendance from the web
app. The backend stores data in PostgreSQL and uses Redis plus database
constraints to prevent duplicate submissions.

## Requirements

Backend:

- Docker and Docker Compose, recommended.
- Or Python 3.12 plus local PostgreSQL and Redis for direct development.

Frontend:

- Flutter SDK.
- Chrome for the web-first workflow.

## Start The Backend

From the repository root:

```bash
cd flask_api
cp .env.example .env
# edit ADMIN_KEY and DB_PASS
docker-compose up --build
```

This default command starts Flask, PostgreSQL, and Redis. The Nginx TLS proxy is
optional because it needs local certificate files; start it with
`docker-compose --profile proxy up --build` after adding certs.

Health check:

```bash
curl http://127.0.0.1:5000/health
```

Expected response:

```json
{"status":"ok","infrastructure":"PostgreSQL + Redis + Host Nginx"}
```

## Start The Web App

From the repository root:

```bash
ADMIN_KEY=<same-value-as-flask_api/.env> \
API_BASE_URL=http://127.0.0.1:5000 \
APP_BASE_URL=http://localhost:8080 \
bash run_flutter.sh web
```

`API_BASE_URL` is the Flask API origin. `APP_BASE_URL` is the URL embedded in QR
codes and share links.

## Instructor Workflow

1. Start the backend.
2. Start the web app.
3. Choose `Instructor`.
4. Create a new session by entering a course name.
5. Optionally enable geofencing and capture the instructor location.
6. Share the generated QR code or link with students.
7. Monitor submissions from the session detail screen.
8. Export records, close/reopen the session, or reset records as needed.

Instructor routes require the configured admin key.

## Student Workflow

1. Open the link or scan the QR code for `/attend/<session_id>`.
2. Enter full name, roll number, and optional comments.
3. Allow location permission if prompted.
4. Submit attendance.
5. Review the result screen.

Possible results:

- `Attendance Marked`: submission was accepted.
- `Already Submitted`: Redis or PostgreSQL detected a duplicate fingerprint or
  roll number.
- `Session Closed`: the session exists but is inactive.
- `Session Not Found`: no matching session exists.
- `Something went wrong`: network, permission, admin key, or API error.

## Troubleshooting

### Backend health check fails

Make sure Docker Compose is running from `flask_api/`:

```bash
docker-compose ps
```

If your Docker installation uses the newer plugin command, use `docker compose`
instead.

### Requests return `401`

The admin key used by Flutter does not match `ADMIN_KEY` in `flask_api/.env`.
Restart the Flutter app with the correct `ADMIN_KEY=...` value.

### Requests return `403`

The backend subnet filter rejected the client IP. Confirm `ALLOWED_SUBNETS` in
`flask_api/.env` includes the network used by your browser or device.

### Flutter cannot connect to the API

Check `API_BASE_URL`. Desktop web can use `127.0.0.1`; another phone or laptop
needs a LAN-reachable host name or IP.

### QR links open the wrong place

Check `APP_BASE_URL`. It must point to the Flutter web app origin, not the Flask
API origin.

### Android APK

Android is a plus, not the primary target in this checkout. The Android platform
directory is currently missing, so regenerate it with:

```bash
cd flutter_app
flutter create . --platforms android
```

Then validate with `flutter build apk` before treating Android as release-ready.
