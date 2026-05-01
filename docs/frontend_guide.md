# Frontend Guide

## Overview

The frontend is a Flutter application in `flutter_app/`. The primary target is
Flutter web, with Linux desktop useful for local testing. Android is optional
future scope until the Android platform directory is regenerated and validated.

The app provides two flows:

- Instructor: create, list, manage, export, reset, close, and reopen sessions.
- Student: open `/attend/<session_id>`, submit attendance, and see a clear
  success/duplicate/closed/error state.

## Runtime Configuration

Configuration is read from `--dart-define` values in `flutter_app/lib/config.dart`.

| Define | Purpose | Local example |
| --- | --- | --- |
| `API_BASE_URL` | Flask API origin | `http://127.0.0.1:5000` |
| `APP_BASE_URL` | Student-facing Flutter origin used in QR links | `http://localhost:8080` |
| `ADMIN_KEY` | Shared admin key sent to instructor routes | value from `flask_api/.env` |

Do not hardcode production secrets in Dart source. Use:

```bash
ADMIN_KEY=<admin-key> \
API_BASE_URL=http://127.0.0.1:5000 \
APP_BASE_URL=http://localhost:8080 \
bash run_flutter.sh web
```

## Source Layout

```text
flutter_app/lib/
├── main.dart
├── config.dart
├── models/
│   ├── attendance_record.dart
│   └── session.dart
├── services/
│   ├── api_service.dart
│   ├── csv_exporter.dart
│   ├── csv_exporter_io.dart
│   ├── csv_exporter_web.dart
│   └── fingerprint_service.dart
└── screens/
    ├── home_screen.dart
    ├── instructor/
    │   ├── create_session_screen.dart
    │   ├── instructor_home.dart
    │   └── session_detail_screen.dart
    └── student/
        └── student_form_screen.dart
```

## Navigation

Routes are defined in `main.dart` with `onGenerateRoute`.

| Route | Screen | Purpose |
| --- | --- | --- |
| `/` | `HomeScreen` | Role selection |
| `/instructor` | `InstructorHome` | Instructor dashboard |
| `/attend/<session_id>` | `StudentFormScreen` | Student attendance form |

`setPathUrlStrategy()` removes hash fragments from web URLs, so QR links can use
normal paths.

## API Contract

`ApiService` wraps the Flask contract:

| Method | Backend route | Used by |
| --- | --- | --- |
| `createSession` | `POST /session/new` | Create session |
| `listSessions` | `GET /sessions` | Instructor home |
| `getSession` | `GET /session/<id>` | Student form, create flow, toggle refresh |
| `submitAttendance` | `POST /session/<id>/submit` | Student form |
| `getRecords` | `GET /session/<id>/records` | Session detail |
| `exportCsv` | `GET /session/<id>/export` | Session detail |
| `closeSession` | `POST /session/<id>/close` | Session detail |
| `openSession` | `POST /session/<id>/open` | Session detail |
| `resetSession` | `POST /session/<id>/reset` | Session detail |

Admin routes include `X-Admin-Key`.

Error responses use an `error` message and may include a stable `code` value.
The student flow handles `duplicate` and `session_closed` specially; other
errors are shown as backend-provided messages.

## Web CSV Export

CSV export is authenticated through `ApiService.exportCsv()`.

- Web uses a Blob download through `csv_exporter_web.dart`.
- Native desktop writes the file to the Desktop directory when available, or to
  the user's home directory.

## Models

`Session.fromJson()` accepts PostgreSQL-style booleans and legacy integer
boolean values.

`AttendanceRecord.fromJson()` maps the backend record payload used by the
instructor record list and CSV export.

## Validation

Run these from `flutter_app/`:

```bash
flutter analyze
flutter test
flutter build web --no-pub
```
