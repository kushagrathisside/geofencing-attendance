import math
import uuid

from errors import ConflictError, ForbiddenError, NotFoundError, ValidationError


SESSION_SELECT = """
SELECT id, course_name, created_at, is_active, geo_lat, geo_lon, geo_radius
FROM sessions
WHERE id = %s
"""


class AttendanceService:
    def __init__(self, database, cache):
        self.database = database
        self.cache = cache

    def create_session(self, data):
        course_name = self._text(data.get("course_name")) or "Default Course"
        session_id = uuid.uuid4().hex[:10].upper()
        geo_lat = self._optional_float(data.get("geo_lat"), "geo_lat")
        geo_lon = self._optional_float(data.get("geo_lon"), "geo_lon")
        geo_radius = self._positive_float(data.get("geo_radius"), "geo_radius", 100)
        self._validate_geofence_values(geo_lat, geo_lon)

        with self.database.connection("session.create") as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO sessions (id, course_name, geo_lat, geo_lon, geo_radius)
                    VALUES (%s, %s, %s, %s, %s)
                    """,
                    (session_id, course_name, geo_lat, geo_lon, geo_radius),
                )
                row = self._fetch_session(cur, session_id)
            conn.commit()

        payload = self._serialize_session(row)
        payload["session_id"] = session_id
        return payload

    def list_sessions(self):
        with self.database.connection("session.list") as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT id, course_name, created_at, is_active, geo_lat, geo_lon, geo_radius
                    FROM sessions
                    ORDER BY created_at DESC
                    """
                )
                return [self._serialize_session(row) for row in cur.fetchall()]

    def get_session(self, session_id):
        with self.database.connection("session.get") as conn:
            with conn.cursor() as cur:
                row = self._fetch_session(cur, session_id)

        if row is None:
            raise NotFoundError("Session not found.")
        return self._serialize_session(row)

    def submit_attendance(self, session_id, data):
        name = self._text(data.get("name"))
        roll_no = self._text(data.get("roll_no")).upper()
        fingerprint = self._text(data.get("fingerprint"))
        comments = self._text(data.get("comments"))
        latitude = self._optional_float(data.get("latitude"), "latitude")
        longitude = self._optional_float(data.get("longitude"), "longitude")
        self._validate_submission_location(latitude, longitude)

        if not name or not roll_no or not fingerprint:
            raise ValidationError(
                "Name, roll number, and fingerprint are required.",
                code="missing_required_fields",
            )

        cache_key = f"attend:{session_id}:{fingerprint}"
        if self.cache.exists(cache_key):
            raise ConflictError("Already submitted.", code="duplicate")

        with self.database.connection("attendance.submit") as conn:
            with conn.cursor() as cur:
                session = self._fetch_session(cur, session_id)
                if not session:
                    raise NotFoundError("Session not found.", code="session_not_found")
                if not session[3]:
                    raise ForbiddenError("Session is closed.", code="session_closed")

                if self._has_geofence(session):
                    if latitude is None or longitude is None:
                        raise ValidationError(
                            "Location is required for this session.",
                            code="location_required",
                        )
                    distance = self._distance_meters(
                        float(session[4]),
                        float(session[5]),
                        latitude,
                        longitude,
                    )
                    if distance > float(session[6] or 100):
                        raise ForbiddenError(
                            "Student is outside the allowed attendance area.",
                            code="outside_geofence",
                        )

                try:
                    cur.execute(
                        """
                        INSERT INTO attendance
                            (session_id, name, roll_no, fingerprint, latitude, longitude, comments)
                        VALUES (%s, %s, %s, %s, %s, %s, %s)
                        """,
                        (
                            session_id,
                            name,
                            roll_no,
                            fingerprint,
                            latitude,
                            longitude,
                            comments,
                        ),
                    )
                    conn.commit()
                except Exception as exc:
                    if self.database.is_integrity_error(exc):
                        conn.rollback()
                        raise ConflictError("Already submitted.", code="duplicate") from exc
                    raise

        self.cache.set(cache_key, "1", 7200)
        return {"message": "Attendance recorded"}

    def list_records(self, session_id):
        with self.database.connection("attendance.records") as conn:
            with conn.cursor() as cur:
                session = self._fetch_session(cur, session_id)
                if not session:
                    raise NotFoundError("Session not found.")
                cur.execute(
                    """
                    SELECT id, submitted_at, name, roll_no, comments, latitude, longitude
                    FROM attendance
                    WHERE session_id = %s
                    ORDER BY submitted_at ASC, id ASC
                    """,
                    (session_id,),
                )
                records = [self._serialize_record(row) for row in cur.fetchall()]

        return {"session": self._serialize_session(session), "records": records}

    def export_records(self, session_id):
        with self.database.connection("attendance.export") as conn:
            with conn.cursor() as cur:
                session = self._fetch_session(cur, session_id)
                if not session:
                    raise NotFoundError("Session not found.")
                cur.execute(
                    """
                    SELECT submitted_at, name, roll_no, comments, latitude, longitude
                    FROM attendance
                    WHERE session_id = %s
                    ORDER BY submitted_at ASC, id ASC
                    """,
                    (session_id,),
                )
                return cur.fetchall()

    def set_session_active(self, session_id, is_active):
        with self.database.connection("session.set_active") as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "UPDATE sessions SET is_active = %s WHERE id = %s RETURNING id",
                    (is_active, session_id),
                )
                updated = cur.fetchone()
            conn.commit()

        if updated is None:
            raise NotFoundError("Session not found.")
        return {"message": "Session updated", "is_active": is_active}

    def reset_session(self, session_id):
        with self.database.connection("attendance.reset") as conn:
            with conn.cursor() as cur:
                session = self._fetch_session(cur, session_id)
                if not session:
                    raise NotFoundError("Session not found.")
                cur.execute("DELETE FROM attendance WHERE session_id = %s", (session_id,))
            conn.commit()

        self.cache.clear_session(session_id)
        return {"message": "Records cleared"}

    def _fetch_session(self, cur, session_id):
        cur.execute(SESSION_SELECT, (session_id,))
        return cur.fetchone()

    def _serialize_session(self, row):
        return {
            "id": row[0],
            "course_name": row[1],
            "created_at": row[2].isoformat() if row[2] else "",
            "is_active": bool(row[3]),
            "geo_lat": row[4],
            "geo_lon": row[5],
            "geo_radius": row[6] if row[6] is not None else 100,
        }

    def _serialize_record(self, row):
        return {
            "id": row[0],
            "submitted_at": row[1].isoformat() if row[1] else "",
            "name": row[2] or "",
            "roll_no": row[3],
            "comments": row[4] or "",
            "latitude": row[5],
            "longitude": row[6],
        }

    def _has_geofence(self, session_row):
        return session_row[4] is not None and session_row[5] is not None

    def _distance_meters(self, lat1, lon1, lat2, lon2):
        radius = 6371000.0
        phi1 = math.radians(lat1)
        phi2 = math.radians(lat2)
        delta_phi = math.radians(lat2 - lat1)
        delta_lambda = math.radians(lon2 - lon1)
        a = (
            math.sin(delta_phi / 2) ** 2
            + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2) ** 2
        )
        return radius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

    def _text(self, value):
        return str(value or "").strip()

    def _optional_float(self, value, field_name):
        if value is None or value == "":
            return None
        if isinstance(value, bool):
            raise ValidationError(f"{field_name} must be a number.")
        try:
            parsed = float(value)
        except (TypeError, ValueError) as exc:
            raise ValidationError(f"{field_name} must be a number.") from exc
        if not math.isfinite(parsed):
            raise ValidationError(f"{field_name} must be a finite number.")
        return parsed

    def _positive_float(self, value, field_name, default):
        parsed = self._optional_float(value, field_name)
        if parsed is None:
            parsed = float(default)
        if parsed <= 0:
            raise ValidationError(f"{field_name} must be greater than zero.")
        return parsed

    def _validate_geofence_values(self, latitude, longitude):
        if (latitude is None) != (longitude is None):
            raise ValidationError("Both geo_lat and geo_lon are required for geofencing.")
        self._validate_coordinate_pair(latitude, longitude)

    def _validate_submission_location(self, latitude, longitude):
        if (latitude is None) != (longitude is None):
            raise ValidationError("Both latitude and longitude are required.")
        self._validate_coordinate_pair(latitude, longitude)

    def _validate_coordinate_pair(self, latitude, longitude):
        if latitude is None and longitude is None:
            return
        if latitude < -90 or latitude > 90:
            raise ValidationError("latitude must be between -90 and 90.")
        if longitude < -180 or longitude > 180:
            raise ValidationError("longitude must be between -180 and 180.")
