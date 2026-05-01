# Stress Testing Information

## Purpose

The stress test checks duplicate-submission behavior under concurrent load. It
creates one session, then sends 200 simultaneous attendance submissions with the
same roll number and fingerprint.

The expected result is:

- One successful database write.
- The remaining requests rejected as duplicates.
- No server crashes.

Script:

```text
flask_api/stress_test.py
```

## What The Test Measures

The script focuses on the submission path:

- Redis duplicate interception.
- PostgreSQL uniqueness constraints.
- API behavior under concurrent identical requests.
- Race-condition handling during duplicate attendance submissions.

It does not measure:

- Full user behavior with many unique students.
- Nginx request limiting.
- Browser or Flutter performance.
- Long-duration soak behavior.
- Database growth over time.

## Prerequisites

Start the backend:

```bash
cd /home/pro2024001/attendancesystem/flask_api
docker-compose up --build
```

In another terminal, make sure the API is reachable:

```bash
curl http://127.0.0.1:5000/health
```

The stress test uses Python `requests`. If it is not installed in the active
environment:

```bash
cd /home/pro2024001/attendancesystem/flask_api
source venv/bin/activate
pip install requests
```

## Running The Test

From the repository:

```bash
cd /home/pro2024001/attendancesystem/flask_api
source venv/bin/activate
ADMIN_KEY=<same-value-as-flask_api/.env> python stress_test.py
```

The script currently targets:

```python
BASE_URL = os.environ.get("BASE_URL", "http://127.0.0.1:5000")
```

This bypasses Nginx and hits the Flask API port directly.

## Test Phases

### Phase 1: Create Session

The script calls:

```http
POST /session/new
X-Admin-Key: <ADMIN_KEY>
```

Body:

```json
{
  "course_name": "Cisco Stress Test"
}
```

The returned `session_id` is used for the submission phase.

### Phase 2: Concurrent Submissions

The script sends 200 requests to:

```http
POST /session/<session_id>/submit
```

All requests use:

```json
{
  "roll_no": "PRO2024001",
  "fingerprint": "MOCK_HARDWARE_ID_999"
}
```

Concurrency model:

- `ThreadPoolExecutor`
- `max_workers=100`
- `200` total requests

### Phase 3: Result Summary

The script counts HTTP status codes and prints:

- `201 Created`
- `409 Conflict`
- `500 Server Errors`

Expected ideal distribution:

```text
201 Created (Database Writes):    1
409 Conflict (Redis Intercepts):  199
500 Server Errors (Crashes):      0
```

## Interpreting Results

### Success

If the output shows one `201` and 199 `409` responses, duplicate protection is
working for the tested race condition.

### More Than One `201`

This would indicate a serious duplicate-protection bug. PostgreSQL uniqueness
constraints should prevent this even if Redis misses a race.

### Any `500`

Check API logs:

```bash
cd /home/pro2024001/attendancesystem/flask_api
docker compose logs api
```

Common causes:

- Database connection failure.
- Missing schema.
- Redis connection failure.
- Unexpected exception handling a duplicate.

### `403` Responses

The subnet filter rejected the request. Confirm `ALLOWED_SUBNETS` allows the
client IP seen by Flask.

Docker Compose includes common private LAN ranges. If running `python main.py`
directly, set localhost explicitly:

```bash
ALLOWED_SUBNETS=127.0.0.1/32 python main.py
```

### Connection Refused

The API is not reachable at `http://127.0.0.1:5000`. Check:

```bash
docker compose ps
curl http://127.0.0.1:5000/health
```

## Testing Through Nginx

To include Nginx and TLS in the stress path, change `BASE_URL` in
`stress_test.py` to the proxy endpoint:

```python
BASE_URL = "https://<host-lan-ip>"
```

Additional changes may be needed if the certificate is self-signed, because
plain `requests.post()` verifies TLS certificates by default.

## Suggested Future Load Tests

Add tests for:

- Many unique students submitting at once.
- Mixed valid and duplicate submissions.
- Closed-session rejection.
- Missing session IDs.
- Invalid payloads.
- Long-running soak with repeated session creation.
- Nginx rate-limit behavior.
- PostgreSQL connection saturation.

Recommended metrics:

- Total requests.
- Requests per second.
- P50, P95, and P99 latency.
- Status-code distribution.
- PostgreSQL CPU and connection count.
- Redis hit/miss behavior.
- API container memory and CPU.

## Current Script Limitations

- It does not test `X-Real-IP` behavior.
- It bypasses Nginx by default.
- It assumes the backend is already initialized.
- It checks only one race condition.
- It reports status-code counts but not latency percentiles.
