# Attendance Flutter Client

Flutter client for the attendance system. The supported primary target is web.

## Run Web

From the repository root:

```bash
ADMIN_KEY=<backend-admin-key> \
API_BASE_URL=http://127.0.0.1:5000 \
APP_BASE_URL=http://localhost:8080 \
bash run_flutter.sh web
```

## Validate

```bash
flutter analyze
flutter test
flutter build web --no-pub
```

## Configuration

Runtime configuration comes from `--dart-define`:

- `API_BASE_URL`: Flask API origin.
- `APP_BASE_URL`: Flutter web origin used in QR links.
- `ADMIN_KEY`: shared admin key for instructor actions.

Android is optional future scope until the Android platform directory is
regenerated and validated.
