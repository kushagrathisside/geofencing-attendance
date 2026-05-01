import csv
import io
import ipaddress
from functools import wraps

from flask import Flask, Response, jsonify, request
from flask_cors import CORS

from config import AppConfig
from errors import ApiError
from services.attendance_service import AttendanceService
from services.cache_service import SubmissionCache
from services.database import DatabaseService, psycopg2


settings = AppConfig.from_env()

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = settings.max_content_length
CORS(app)

database = DatabaseService(settings, app.logger)
cache = SubmissionCache(settings.redis_host, app.logger)
attendance_service = AttendanceService(database, cache)


def error_response(message, status_code, **extra):
    payload = {"error": message}
    payload.update(extra)
    return jsonify(payload), status_code


def require_admin(fn):
    @wraps(fn)
    def wrapper(*args, **kwargs):
        if request.headers.get("X-Admin-Key") != settings.admin_key:
            return error_response("Invalid or missing admin key.", 401)
        return fn(*args, **kwargs)

    return wrapper


def _ip_in_subnets(ip_obj, subnets):
    for subnet in subnets:
        try:
            if ip_obj in ipaddress.ip_network(subnet, strict=False):
                return True
        except ValueError as exc:
            raise RuntimeError(f"Invalid subnet config: {subnet}") from exc
    return False


def _client_ip_from_request():
    remote_ip = ipaddress.ip_address(request.remote_addr or "")
    forwarded_ip = request.headers.get("X-Real-IP")

    if not settings.trust_proxy_headers or not forwarded_ip:
        return remote_ip

    if _ip_in_subnets(remote_ip, settings.trusted_proxy_subnets):
        return ipaddress.ip_address(forwarded_ip)

    app.logger.warning(
        "Ignoring X-Real-IP from untrusted peer %s",
        remote_ip,
    )
    return remote_ip


@app.before_request
def restrict_subnet():
    if request.path == "/health" or request.method == "OPTIONS":
        return None

    try:
        ip_obj = _client_ip_from_request()
    except ValueError:
        return error_response("Malformed IP address.", 400)
    except RuntimeError as exc:
        app.logger.error(str(exc))
        return error_response("Server network policy is misconfigured.", 500)

    try:
        if _ip_in_subnets(ip_obj, settings.allowed_subnets):
            return None
    except RuntimeError as exc:
        app.logger.error(str(exc))
        return error_response("Server network policy is misconfigured.", 500)

    return error_response(f"Network segmentation violation. IP {ip_obj} rejected.", 403)


@app.errorhandler(ApiError)
def handle_api_error(exc):
    return jsonify(exc.to_dict()), exc.status_code


@app.errorhandler(RuntimeError)
def handle_runtime_error(exc):
    return error_response(str(exc), 500)


if psycopg2 is not None:

    @app.errorhandler(psycopg2.Error)
    def handle_database_error(exc):
        database.log_database_error("unhandled", exc)
        return error_response("Database error.", 500, source="unhandled")


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok", "infrastructure": "PostgreSQL + Redis + Host Nginx"})


@app.route("/session/new", methods=["POST"])
@require_admin
def create_session():
    payload = attendance_service.create_session(request.get_json(silent=True) or {})
    return jsonify(payload), 201


@app.route("/sessions", methods=["GET"])
@require_admin
def list_sessions():
    return jsonify(attendance_service.list_sessions())


@app.route("/session/<session_id>", methods=["GET"])
def get_session(session_id):
    return jsonify(attendance_service.get_session(session_id))


@app.route("/session/<session_id>/submit", methods=["POST"])
def submit_attendance(session_id):
    payload = attendance_service.submit_attendance(
        session_id,
        request.get_json(silent=True) or {},
    )
    return jsonify(payload), 201


@app.route("/session/<session_id>/records", methods=["GET"])
@require_admin
def get_records(session_id):
    return jsonify(attendance_service.list_records(session_id))


@app.route("/session/<session_id>/export", methods=["GET"])
@require_admin
def export_records(session_id):
    rows = attendance_service.export_records(session_id)

    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(["submitted_at", "name", "roll_no", "comments", "latitude", "longitude"])
    for row in rows:
        writer.writerow(
            [
                row[0].isoformat() if row[0] else "",
                row[1],
                row[2],
                row[3] or "",
                row[4],
                row[5],
            ]
        )

    filename = f"{session_id}-attendance.csv"
    return Response(
        output.getvalue(),
        mimetype="text/csv",
        headers={"Content-Disposition": f"attachment; filename={filename}"},
    )


@app.route("/session/<session_id>/close", methods=["POST"])
@require_admin
def close_session(session_id):
    return jsonify(attendance_service.set_session_active(session_id, False))


@app.route("/session/<session_id>/open", methods=["POST"])
@require_admin
def open_session(session_id):
    return jsonify(attendance_service.set_session_active(session_id, True))


@app.route("/session/<session_id>/reset", methods=["POST"])
@require_admin
def reset_session(session_id):
    return jsonify(attendance_service.reset_session(session_id))


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=settings.port)
