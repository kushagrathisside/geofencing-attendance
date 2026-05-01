# Attendance System Documentation

This folder contains the project documentation for the attendance system.

The documents are based on the current repository layout:

- Flask API in `flask_api/`
- Flutter client in `flutter_app/`
- Docker Compose infrastructure in `flask_api/docker-compose.yml`
- Stress test script in `flask_api/stress_test.py`

## Documents

- [User Manual](user_manual.md)
- [Frontend Guide](frontend_guide.md)
- [Backend Guide](backend_guide.md)
- [Architectural Documentation](architecture.md)
- [Stress Testing Information](stress_testing.md)

## Current-State Note

The Flask API and Flutter client now share the same session-management contract:
session creation, listing, detail loading, attendance submission, record
loading, CSV export, close, reopen, and reset are implemented.

The app is web-first. Android remains optional future scope until the Flutter
Android platform directory is regenerated and validated.
