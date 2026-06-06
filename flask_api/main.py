"""
AttendanceApp — Flask REST API v2
==================================
Instructor accounts stored in DB (bcrypt hashed passwords).
JWT authentication (2-hour tokens by default).
Role-based access: 'admin' can manage accounts, 'ta' cannot.
Auto-detects WiFi LAN IP (prefers wlo*/wlan*/wlp* interfaces).
Student HTML form served at /attend/<id>.

First run creates a default admin account:
  username: admin
  password: admin123   ← CHANGE THIS after first login

Run:
  pip install -r requirements.txt
  python main.py
"""

import csv
import io
import os
import re
import socket
import sqlite3
import uuid
from datetime import datetime, timedelta, timezone
from functools import wraps

import bcrypt
import jwt
from flask import Flask, g, jsonify, request, make_response
from flask_cors import CORS
from geopy.distance import geodesic
from markupsafe import escape

# ---------------------------------------------------------------------------
# App setup
# ---------------------------------------------------------------------------

app = Flask(__name__)
CORS(app)

DATABASE         = os.environ.get("DATABASE",         "attendance.db")
JWT_SECRET       = os.environ.get("JWT_SECRET",       "dev-secret")
JWT_EXPIRY_HOURS = int(os.environ.get("JWT_EXPIRY_HOURS", "2"))
DEFAULT_ADMIN_USER = os.environ.get("DEFAULT_ADMIN_USER", "admin")
DEFAULT_ADMIN_PASS = os.environ.get("DEFAULT_ADMIN_PASS", "admin123")
ENFORCE_LAN      = os.environ.get("ENFORCE_LAN",      "0") == "1"

if JWT_SECRET == "dev-secret":
    print("WARNING: Using insecure default JWT secret. Set JWT_SECRET env var before deployment.")


def is_local_ip(ip: str) -> bool:
    """Returns True only for RFC-1918 private addresses."""
    parts = ip.split(".")
    if len(parts) != 4 or not all(p.isdigit() for p in parts):
        return False
    return (
        ip.startswith("192.168.") or
        ip.startswith("10.") or
        (ip.startswith("172.") and 16 <= int(parts[1]) <= 31)
    )


# ---------------------------------------------------------------------------
# LAN IP — prefers WiFi interface (wlo*, wlan*, wlp*)
# ---------------------------------------------------------------------------

def get_lan_ip() -> str:
    """
    Tries to find the WiFi interface IP first (wlo*, wlan*, wlp*).
    Falls back to any non-loopback IP, then 127.0.0.1.
    """
    try:
        import subprocess
        result = subprocess.run(
            ["ip", "-4", "addr", "show"],
            capture_output=True, text=True, timeout=3
        )
        blocks = re.split(r'\n(?=\d+: )', result.stdout)
        wifi_ip = None
        any_ip  = None
        for block in blocks:
            if re.search(r'wlo|wlan|wlp', block):
                m = re.search(r'inet (\d+\.\d+\.\d+\.\d+)', block)
                if m:
                    wifi_ip = m.group(1)
            elif not re.search(r'127\.0\.0\.1|^.*lo:', block):
                m = re.search(r'inet (\d+\.\d+\.\d+\.\d+)', block)
                if m:
                    any_ip = m.group(1)
        return wifi_ip or any_ip or _fallback_ip()
    except Exception:
        return _fallback_ip()


def _fallback_ip() -> str:
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"


# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------

def get_db() -> sqlite3.Connection:
    if "db" not in g:
        g.db = sqlite3.connect(DATABASE, detect_types=sqlite3.PARSE_DECLTYPES)
        g.db.row_factory = sqlite3.Row
        g.db.execute("PRAGMA journal_mode=WAL")
        g.db.execute("PRAGMA foreign_keys=ON")
    return g.db


@app.teardown_appcontext
def close_db(exc=None):
    db = g.pop("db", None)
    if db:
        db.close()


def init_db():
    db = get_db()
    db.executescript("""
        CREATE TABLE IF NOT EXISTS instructors (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            username   TEXT NOT NULL UNIQUE,
            password   TEXT NOT NULL,
            full_name  TEXT NOT NULL DEFAULT '',
            role       TEXT NOT NULL DEFAULT 'ta',
            created_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS sessions (
            id          TEXT PRIMARY KEY,
            course_name TEXT NOT NULL,
            created_at  TEXT NOT NULL,
            is_active   INTEGER NOT NULL DEFAULT 1,
            geo_lat     REAL,
            geo_lon     REAL,
            geo_radius  REAL DEFAULT 100,
            created_by  TEXT
        );

        CREATE TABLE IF NOT EXISTS attendance (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id   TEXT NOT NULL,
            submitted_at TEXT NOT NULL,
            name         TEXT NOT NULL,
            roll_no      TEXT NOT NULL,
            comments     TEXT,
            latitude     REAL,
            longitude    REAL,
            fingerprint  TEXT NOT NULL,
            FOREIGN KEY (session_id) REFERENCES sessions(id)
        );

        CREATE INDEX IF NOT EXISTS idx_att_session ON attendance(session_id);
    """)
    db.commit()

    # Migration: enforce one submission per fingerprint per session.
    # Deduplicate first (keep earliest row), then recreate as UNIQUE.
    idx = db.execute(
        "SELECT sql FROM sqlite_master WHERE type='index' AND name='idx_att_fp'"
    ).fetchone()
    if idx is None or "UNIQUE" not in (idx["sql"] or "").upper():
        db.execute("""
            DELETE FROM attendance WHERE id NOT IN (
                SELECT MIN(id) FROM attendance GROUP BY session_id, fingerprint
            )
        """)
        db.execute("DROP INDEX IF EXISTS idx_att_fp")
        db.execute(
            "CREATE UNIQUE INDEX idx_att_fp ON attendance(session_id, fingerprint)"
        )
        db.commit()

    # Create default admin if no instructors exist
    count = db.execute("SELECT COUNT(*) FROM instructors").fetchone()[0]
    if count == 0:
        hashed = bcrypt.hashpw(
            DEFAULT_ADMIN_PASS.encode(), bcrypt.gensalt()
        ).decode()
        db.execute(
            "INSERT INTO instructors (username, password, full_name, role, created_at) VALUES (?,?,?,?,?)",
            (DEFAULT_ADMIN_USER, hashed, "Administrator", "admin",
             datetime.now(timezone.utc).isoformat()),
        )
        db.commit()
        print(f"\n  Default admin created: {DEFAULT_ADMIN_USER}")
        print("  *** Change this password after first login! ***\n")


def row_to_dict(row):
    return dict(row)


def session_or_404(session_id):
    return get_db().execute(
        "SELECT * FROM sessions WHERE id=?", (session_id,)
    ).fetchone()


# ---------------------------------------------------------------------------
# JWT Auth
# ---------------------------------------------------------------------------

def make_token(instructor_id: int, username: str, role: str) -> str:
    payload = {
        "sub":      str(instructor_id),
        "username": username,
        "role":     role,
        "exp":      datetime.now(timezone.utc) + timedelta(hours=JWT_EXPIRY_HOURS),
        "iat":      int(datetime.now(timezone.utc).timestamp()),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm="HS256")


def decode_token(token: str) -> dict:
    return jwt.decode(
        token,
        JWT_SECRET,
        algorithms=["HS256"],
        options={"verify_iat": False},
    )


def get_token_from_request() -> str | None:
    auth = request.headers.get("Authorization", "")
    if auth.startswith("Bearer "):
        return auth[7:]
    return None


def require_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        token = get_token_from_request()
        if not token:
            return jsonify({"error": "Missing token"}), 401
        try:
            payload = decode_token(token)
            g.instructor = payload
        except jwt.ExpiredSignatureError:
            return jsonify({"error": "Token expired"}), 401
        except jwt.InvalidTokenError:
            return jsonify({"error": "Invalid token"}), 401
        return f(*args, **kwargs)
    return decorated


def require_admin(f):
    """Admin-only routes."""
    @wraps(f)
    def decorated(*args, **kwargs):
        token = get_token_from_request()
        if not token:
            return jsonify({"error": "Missing token"}), 401
        try:
            payload = decode_token(token)
            g.instructor = payload
        except jwt.ExpiredSignatureError:
            return jsonify({"error": "Token expired"}), 401
        except jwt.InvalidTokenError:
            return jsonify({"error": "Invalid token"}), 401
        if payload.get("role") != "admin":
            return jsonify({"error": "Admin access required"}), 403
        return f(*args, **kwargs)
    return decorated


# ---------------------------------------------------------------------------
# Auth routes
# ---------------------------------------------------------------------------

@app.route("/auth/login", methods=["POST"])
def login():
    """
    POST /auth/login
    Body: { username, password }
    Returns: { token, username, role, full_name }
    """
    data     = request.get_json(force=True, silent=True) or {}
    username = data.get("username", "").strip().lower()
    password = data.get("password", "")

    if not username or not password:
        return jsonify({"error": "Username and password required"}), 400

    row = get_db().execute(
        "SELECT * FROM instructors WHERE username=?", (username,)
    ).fetchone()

    if not row or not bcrypt.checkpw(password.encode(), row["password"].encode()):
        return jsonify({"error": "Invalid username or password"}), 401

    token = make_token(row["id"], row["username"], row["role"])
    return jsonify({
        "token":            token,
        "username":         row["username"],
        "full_name":        row["full_name"],
        "role":             row["role"],
        "expires_in_hours": JWT_EXPIRY_HOURS,
    })


@app.route("/auth/me", methods=["GET"])
@require_auth
def me():
    """Returns current instructor info from token."""
    return jsonify(g.instructor)


@app.route("/auth/change-password", methods=["POST"])
@require_auth
def change_password():
    """
    POST /auth/change-password
    Body: { current_password, new_password }
    """
    data     = request.get_json(force=True, silent=True) or {}
    current  = data.get("current_password", "")
    new_pass = data.get("new_password", "")

    if not current or not new_pass:
        return jsonify({"error": "Both current and new password required"}), 400
    if len(new_pass) < 6:
        return jsonify({"error": "New password must be at least 6 characters"}), 400

    row = get_db().execute(
        "SELECT * FROM instructors WHERE id=?", (g.instructor["sub"],)
    ).fetchone()

    if not bcrypt.checkpw(current.encode(), row["password"].encode()):
        return jsonify({"error": "Current password is incorrect"}), 401

    hashed = bcrypt.hashpw(new_pass.encode(), bcrypt.gensalt()).decode()
    get_db().execute(
        "UPDATE instructors SET password=? WHERE id=?",
        (hashed, g.instructor["sub"])
    )
    get_db().commit()
    return jsonify({"message": "Password changed successfully"})


# ---------------------------------------------------------------------------
# Account management (admin only)
# ---------------------------------------------------------------------------

@app.route("/accounts", methods=["GET"])
@require_admin
def list_accounts():
    rows = get_db().execute(
        "SELECT id, username, full_name, role, created_at FROM instructors ORDER BY created_at ASC"
    ).fetchall()
    return jsonify([row_to_dict(r) for r in rows])


@app.route("/accounts", methods=["POST"])
@require_admin
def create_account():
    """
    POST /accounts
    Body: { username, password, full_name, role }
    role: 'admin' or 'ta'
    """
    data      = request.get_json(force=True, silent=True) or {}
    username  = data.get("username", "").strip().lower()
    password  = data.get("password", "")
    full_name = data.get("full_name", "").strip()
    role      = data.get("role", "ta")

    if not username or not password:
        return jsonify({"error": "Username and password required"}), 400
    if len(password) < 6:
        return jsonify({"error": "Password must be at least 6 characters"}), 400
    if role not in ("admin", "ta"):
        return jsonify({"error": "Role must be 'admin' or 'ta'"}), 400

    existing = get_db().execute(
        "SELECT id FROM instructors WHERE username=?", (username,)
    ).fetchone()
    if existing:
        return jsonify({"error": f"Username '{username}' already exists"}), 409

    hashed = bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()
    get_db().execute(
        "INSERT INTO instructors (username, password, full_name, role, created_at) VALUES (?,?,?,?,?)",
        (username, hashed, full_name, role, datetime.now(timezone.utc).isoformat()),
    )
    get_db().commit()
    return jsonify({"message": f"Account '{username}' created", "role": role}), 201


@app.route("/accounts/<int:account_id>", methods=["DELETE"])
@require_admin
def delete_account(account_id):
    if account_id == int(g.instructor["sub"]):
        return jsonify({"error": "Cannot delete your own account"}), 400

    row = get_db().execute(
        "SELECT id FROM instructors WHERE id=?", (account_id,)
    ).fetchone()
    if not row:
        return jsonify({"error": "Account not found"}), 404

    get_db().execute("DELETE FROM instructors WHERE id=?", (account_id,))
    get_db().commit()
    return jsonify({"message": "Account deleted"})


@app.route("/accounts/<int:account_id>/reset-password", methods=["POST"])
@require_admin
def reset_password(account_id):
    """Admin resets another user's password."""
    data     = request.get_json(force=True, silent=True) or {}
    new_pass = data.get("new_password", "")
    if len(new_pass) < 6:
        return jsonify({"error": "Password must be at least 6 characters"}), 400

    row = get_db().execute(
        "SELECT id FROM instructors WHERE id=?", (account_id,)
    ).fetchone()
    if not row:
        return jsonify({"error": "Account not found"}), 404

    hashed = bcrypt.hashpw(new_pass.encode(), bcrypt.gensalt()).decode()
    get_db().execute(
        "UPDATE instructors SET password=? WHERE id=?", (hashed, account_id)
    )
    get_db().commit()
    return jsonify({"message": "Password reset successfully"})


# ---------------------------------------------------------------------------
# Session management (any authenticated instructor)
# ---------------------------------------------------------------------------

@app.route("/session/new", methods=["POST"])
@require_auth
def create_session():
    data        = request.get_json(force=True, silent=True) or {}
    course_name = data.get("course_name", "").strip()
    if not course_name:
        return jsonify({"error": "course_name is required"}), 400

    session_id = uuid.uuid4().hex[:10].upper()
    now        = datetime.now(timezone.utc).isoformat()
    get_db().execute(
        "INSERT INTO sessions (id,course_name,created_at,is_active,geo_lat,geo_lon,geo_radius,created_by) VALUES (?,?,?,1,?,?,?,?)",
        (session_id, course_name, now,
         data.get("geo_lat"), data.get("geo_lon"), data.get("geo_radius", 100),
         g.instructor.get("username")),
    )
    get_db().commit()

    lan_ip = get_lan_ip()
    port   = os.environ.get("PORT", "8080")
    link   = f"http://{lan_ip}:{port}/attend/{session_id}"
    return jsonify({
        "session_id":  session_id,
        "link":        link,
        "course_name": course_name,
        "lan_ip":      lan_ip,
    }), 201


@app.route("/session/<session_id>", methods=["GET"])
def get_session(session_id):
    """Public endpoint — students and instructors both use this."""
    s = session_or_404(session_id)
    if s is None:
        return jsonify({"error": "Session not found"}), 404
    return jsonify(row_to_dict(s))


@app.route("/session/<session_id>/close", methods=["POST"])
@require_auth
def close_session(session_id):
    if not session_or_404(session_id):
        return jsonify({"error": "Session not found"}), 404
    get_db().execute("UPDATE sessions SET is_active=0 WHERE id=?", (session_id,))
    get_db().commit()
    return jsonify({"message": "Session closed"})


@app.route("/session/<session_id>/open", methods=["POST"])
@require_auth
def open_session(session_id):
    if not session_or_404(session_id):
        return jsonify({"error": "Session not found"}), 404
    get_db().execute("UPDATE sessions SET is_active=1 WHERE id=?", (session_id,))
    get_db().commit()
    return jsonify({"message": "Session reopened"})


@app.route("/session/<session_id>/reset", methods=["POST"])
@require_auth
def reset_session(session_id):
    if not session_or_404(session_id):
        return jsonify({"error": "Session not found"}), 404
    get_db().execute("DELETE FROM attendance WHERE session_id=?", (session_id,))
    get_db().commit()
    return jsonify({"message": "Records cleared"})


@app.route("/sessions", methods=["GET"])
@require_auth
def list_sessions():
    rows = get_db().execute(
        "SELECT * FROM sessions ORDER BY created_at DESC"
    ).fetchall()
    return jsonify([row_to_dict(r) for r in rows])


# ---------------------------------------------------------------------------
# Attendance submission (public — students)
# ---------------------------------------------------------------------------

@app.route("/attend/<session_id>", methods=["GET"])
def student_form(session_id):
    s = session_or_404(session_id)
    if s is None:
        return "<h2 style='font-family:sans-serif;padding:2rem'>Session not found.</h2>", 404
    html = build_student_html(s["id"], s["course_name"], bool(s["is_active"]))
    return html, 200, {"Content-Type": "text/html; charset=utf-8"}


@app.route("/session/<session_id>/submit", methods=["POST"])
def submit_attendance(session_id):
    s = session_or_404(session_id)
    if s is None:
        return jsonify({"error": "Session not found"}), 404
    if not s["is_active"]:
        return jsonify({"error": "Session is closed"}), 403

    if ENFORCE_LAN:
        ip = request.remote_addr or ""
        if not is_local_ip(ip):
            return jsonify({"error": "Not in local network"}), 403

    data    = request.get_json(force=True, silent=True) or {}
    missing = [f for f in ["name", "roll_no", "latitude", "longitude", "fingerprint"]
               if data.get(f) is None]
    if missing:
        return jsonify({"error": f"Missing fields: {', '.join(missing)}"}), 400

    name    = data["name"].strip()
    roll_no = data["roll_no"].strip()
    if len(name) > 100 or len(roll_no) > 50:
        return jsonify({"error": "Invalid input length"}), 400

    comments    = (data.get("comments") or "").strip()[:500]
    fingerprint = data["fingerprint"].strip()[:128]

    try:
        lat = float(data["latitude"])
        lon = float(data["longitude"])
    except (ValueError, TypeError):
        return jsonify({"error": "latitude and longitude must be numbers"}), 400

    if s["geo_lat"] and s["geo_lon"]:
        dist = geodesic((s["geo_lat"], s["geo_lon"]), (lat, lon)).meters
        if dist > s["geo_radius"]:
            return jsonify({
                "error":      "outside_geofence",
                "message":    f"Must be within {s['geo_radius']}m.",
                "distance_m": round(dist, 1),
            }), 403

    try:
        get_db().execute(
            "INSERT INTO attendance (session_id,submitted_at,name,roll_no,comments,latitude,longitude,fingerprint) "
            "VALUES (?,?,?,?,?,?,?,?)",
            (session_id, datetime.now(timezone.utc).isoformat(),
             name, roll_no, comments, lat, lon, fingerprint),
        )
        get_db().commit()
    except sqlite3.IntegrityError:
        return jsonify({"error": "duplicate", "message": "Already submitted."}), 409

    return jsonify({"message": "Attendance recorded"}), 201


# ---------------------------------------------------------------------------
# Records & Export
# ---------------------------------------------------------------------------

@app.route("/session/<session_id>/records", methods=["GET"])
@require_auth
def get_records(session_id):
    s = session_or_404(session_id)
    if s is None:
        return jsonify({"error": "Session not found"}), 404
    rows = get_db().execute(
        "SELECT id,submitted_at,name,roll_no,comments,latitude,longitude "
        "FROM attendance WHERE session_id=? ORDER BY submitted_at ASC",
        (session_id,)
    ).fetchall()
    return jsonify({
        "session": row_to_dict(s),
        "count":   len(rows),
        "records": [row_to_dict(r) for r in rows],
    })


@app.route("/session/<session_id>/export", methods=["GET"])
@require_auth
def export_csv(session_id):
    s = session_or_404(session_id)
    if s is None:
        return jsonify({"error": "Session not found"}), 404
    rows = get_db().execute(
        "SELECT submitted_at,name,roll_no,comments,latitude,longitude "
        "FROM attendance WHERE session_id=? ORDER BY submitted_at ASC",
        (session_id,)
    ).fetchall()
    buf = io.StringIO()
    w   = csv.writer(buf)
    w.writerow(["Timestamp", "Name", "RollNo", "Comments", "Latitude", "Longitude"])
    for r in rows:
        w.writerow(list(r))
    out = make_response(buf.getvalue())
    out.headers["Content-Disposition"] = f"attachment; filename={session_id}-attendance.csv"
    out.headers["Content-Type"]        = "text/csv"
    return out


# ---------------------------------------------------------------------------
# Health
# ---------------------------------------------------------------------------

@app.route("/health", methods=["GET"])
def health():
    lan_ip = get_lan_ip()
    port   = os.environ.get("PORT", "8080")
    return jsonify({"status": "ok", "lan_ip": lan_ip, "base_url": f"http://{lan_ip}:{port}"})


# ---------------------------------------------------------------------------
# Student HTML form
# ---------------------------------------------------------------------------

def build_student_html(session_id: str, course_name: str, is_active: bool) -> str:
    safe_name = str(escape(course_name))
    safe_id   = str(escape(session_id))

    if not is_active:
        return f"""<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Session Closed</title>
<link href="https://fonts.googleapis.com/css2?family=Syne:wght@700&family=Outfit:wght@400;500&display=swap" rel="stylesheet">
<style>*{{box-sizing:border-box;margin:0;padding:0}}
body{{background:#0a0a0f;color:#e8e8ec;font-family:'Outfit',sans-serif;min-height:100vh;display:flex;align-items:center;justify-content:center;padding:2rem}}
.card{{text-align:center;max-width:380px}}.icon{{font-size:4rem;margin-bottom:1.5rem}}
h1{{font-family:'Syne',sans-serif;font-size:1.8rem;margin-bottom:.75rem}}p{{color:#666;line-height:1.6}}</style>
</head><body><div class="card"><div class="icon">&#128274;</div><h1>Session Closed</h1>
<p>This session is no longer accepting submissions.<br>Please contact your instructor.</p></div></body></html>"""

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
<title>{safe_name} - Attendance</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Syne:wght@600;700&family=Outfit:wght@300;400;500;600&display=swap" rel="stylesheet">
<style>
  *, *::before, *::after {{ box-sizing:border-box; margin:0; padding:0; }}
  :root {{ --bg:#0a0a0f; --surface:#13131a; --border:#1e1e2a; --accent:#6c63ff; --text:#e8e8f0; --muted:#55556a; --success:#4ade80; --error:#f87171; --radius:14px; }}
  body {{ background:var(--bg); color:var(--text); font-family:'Outfit',sans-serif; min-height:100vh; display:flex; align-items:flex-start; justify-content:center; }}
  body::before {{ content:''; position:fixed; inset:0; background: radial-gradient(ellipse 60% 40% at 20% 20%,rgba(108,99,255,.12) 0%,transparent 60%), radial-gradient(ellipse 50% 35% at 80% 80%,rgba(255,101,132,.08) 0%,transparent 60%); pointer-events:none; z-index:0; }}
  .wrapper {{ position:relative; z-index:1; width:100%; max-width:440px; padding:2rem 1.5rem 3rem; }}
  .pill {{ display:inline-block; background:rgba(108,99,255,.15); border:1px solid rgba(108,99,255,.3); color:var(--accent); font-size:.65rem; font-weight:600; letter-spacing:.12em; text-transform:uppercase; padding:.3rem .8rem; border-radius:100px; margin-bottom:1rem; }}
  h1 {{ font-family:'Syne',sans-serif; font-size:clamp(1.5rem,5vw,2rem); font-weight:700; line-height:1.2; margin-bottom:.5rem; }}
  .session-id {{ font-family:monospace; font-size:.75rem; color:var(--muted); letter-spacing:.08em; }}
  .header {{ margin-bottom:2.5rem; }}
  .form {{ display:flex; flex-direction:column; gap:1.1rem; }}
  .field {{ display:flex; flex-direction:column; gap:.4rem; }}
  .field label {{ font-size:.7rem; font-weight:600; color:var(--muted); text-transform:uppercase; letter-spacing:.1em; }}
  .field input, .field textarea {{ background:var(--surface); border:1px solid var(--border); border-radius:var(--radius); padding:.85rem 1rem; color:var(--text); font-family:'Outfit',sans-serif; font-size:1rem; outline:none; transition:border-color .2s,box-shadow .2s; -webkit-appearance:none; }}
  .field input:focus, .field textarea:focus {{ border-color:var(--accent); box-shadow:0 0 0 3px rgba(108,99,255,.15); }}
  .field textarea {{ resize:none; height:72px; }}
  .btn {{ margin-top:.5rem; background:var(--accent); color:#fff; border:none; border-radius:var(--radius); padding:1rem; font-family:'Outfit',sans-serif; font-size:1rem; font-weight:600; cursor:pointer; transition:opacity .2s,transform .1s; -webkit-tap-highlight-color:transparent; width:100%; }}
  .btn:active {{ transform:scale(.98); }} .btn:disabled {{ opacity:.6; cursor:not-allowed; }}
  .status {{ margin-top:1rem; padding:.75rem 1rem; border-radius:var(--radius); font-size:.85rem; font-weight:500; display:none; align-items:center; gap:.6rem; }}
  .status.show {{ display:flex; }}
  .status.info    {{ background:rgba(108,99,255,.12); border:1px solid rgba(108,99,255,.25); color:#a5a0ff; }}
  .status.success {{ background:rgba(74,222,128,.1);  border:1px solid rgba(74,222,128,.25); color:var(--success); }}
  .status.error   {{ background:rgba(248,113,113,.1); border:1px solid rgba(248,113,113,.25); color:var(--error); }}
  .spinner {{ width:16px; height:16px; border:2px solid currentColor; border-top-color:transparent; border-radius:50%; animation:spin .7s linear infinite; flex-shrink:0; }}
  .result {{ display:none; flex-direction:column; align-items:center; text-align:center; padding:4rem 1rem; }}
  .result.show {{ display:flex; }}
  .result-icon {{ font-size:4.5rem; margin-bottom:1.5rem; }}
  .result h2 {{ font-family:'Syne',sans-serif; font-size:1.6rem; margin-bottom:.75rem; }}
  .result p {{ color:var(--muted); line-height:1.65; font-size:.95rem; }}
  .note {{ margin-top:1.5rem; text-align:center; font-size:.72rem; color:var(--muted); line-height:1.5; }}
  @keyframes spin {{ to {{ transform:rotate(360deg); }} }}
</style>
</head>
<body>
<div class="wrapper">
  <div id="formView">
    <div class="header">
      <div class="pill">Attendance</div>
      <h1>{safe_name}</h1>
      <div class="session-id">Session &middot; {safe_id}</div>
    </div>
    <div class="form">
      <div class="field"><label>Full Name</label><input type="text" id="name" placeholder="Your full name" autocomplete="name"></div>
      <div class="field"><label>Roll Number</label><input type="text" id="roll" placeholder="e.g. IML2024001" style="text-transform:uppercase" autocomplete="off"></div>
      <div class="field"><label>Comments <span style="font-weight:400;text-transform:none;letter-spacing:0">(optional)</span></label><textarea id="comments" placeholder="Anything to note?"></textarea></div>
      <button class="btn" id="submitBtn" onclick="handleSubmit()">Mark My Attendance</button>
      <div class="status info" id="status"><span class="spinner" id="spinner"></span><span id="statusText">Initialising&hellip;</span></div>
    </div>
    <p class="note">Your location is captured only to verify classroom presence.</p>
  </div>
  <div class="result" id="successView"><div class="result-icon">&#9989;</div><h2>Attendance Marked!</h2><p>Your attendance for <strong>{safe_name}</strong> has been successfully recorded.</p></div>
  <div class="result" id="deniedView"><div class="result-icon">&#9888;&#65039;</div><h2>Already Submitted</h2><p>Attendance from this device has already been recorded for this session.</p></div>
  <div class="result" id="errorView"><div class="result-icon">&#10060;</div><h2>Something went wrong</h2><p id="errorMsg">An error occurred.</p><button class="btn" style="margin-top:1.5rem;max-width:200px" onclick="showView('formView')">Try Again</button></div>
</div>
<script>
function getFingerprint() {{
  var raw = [navigator.userAgent,navigator.language,screen.width+'x'+screen.height,screen.colorDepth,new Date().getTimezoneOffset(),navigator.hardwareConcurrency||'',navigator.platform||''].join('|');
  var h=0; for(var i=0;i<raw.length;i++) h=((h<<5)-h+raw.charCodeAt(i))|0;
  return 'web-'+Math.abs(h).toString(16).padStart(8,'0');
}}
function showStatus(msg,type){{ type=type||'info'; var el=document.getElementById('status'); el.className='status show '+type; document.getElementById('statusText').textContent=msg; document.getElementById('spinner').style.display=type==='info'?'block':'none'; }}
function showView(id){{ ['formView','successView','deniedView','errorView'].forEach(function(v){{ var el=document.getElementById(v); el.classList.remove('show'); el.style.display='none'; }}); var el=document.getElementById(id); el.style.display=id==='formView'?'block':'flex'; el.classList.add('show'); }}
async function handleSubmit(){{
  var name=document.getElementById('name').value.trim();
  var roll=document.getElementById('roll').value.trim().toUpperCase();
  var comments=document.getElementById('comments').value.trim();
  if(!name){{alert('Please enter your name.');return;}}
  if(!roll){{alert('Please enter your roll number.');return;}}
  var btn=document.getElementById('submitBtn'); btn.disabled=true;
  showStatus('Getting your location…');
  try{{
    var pos=await new Promise(function(res,rej){{ if(!navigator.geolocation){{rej(new Error('Geolocation not supported.'));return;}} navigator.geolocation.getCurrentPosition(res,rej,{{enableHighAccuracy:true,timeout:15000,maximumAge:0}}); }});
    showStatus('Submitting…');
    var resp=await fetch('/session/{safe_id}/submit',{{method:'POST',headers:{{'Content-Type':'application/json'}},body:JSON.stringify({{name:name,roll_no:roll,comments:comments,latitude:pos.coords.latitude,longitude:pos.coords.longitude,fingerprint:getFingerprint()}})}});
    var data=await resp.json();
    if(resp.status===201){{showView('successView');}}
    else if(resp.status===409){{showView('deniedView');}}
    else if(resp.status===403&&data.error==='outside_geofence'){{document.getElementById('errorMsg').textContent='You must be within '+data.distance_m+'m of the classroom. You are currently '+Math.round(data.distance_m)+'m away.';showView('errorView');}}
    else{{document.getElementById('errorMsg').textContent=data.message||data.error||'Unknown error.';showView('errorView');}}
  }}catch(err){{
    btn.disabled=false;
    var msg=err.code===1?'Location permission denied. Please allow and retry.':err.code===2?'Could not get location. Check GPS is on.':err.code===3?'Location timed out. Try again.':(err.message||'Error.');
    showStatus(msg,'error');
  }}
}}
</script>
</body></html>"""


# ---------------------------------------------------------------------------
# Boot
# ---------------------------------------------------------------------------

with app.app_context():
    init_db()

if __name__ == "__main__":
    port   = int(os.environ.get("PORT", 8080))
    lan_ip = get_lan_ip()
    print(f"\n{'='*56}")
    print(f"  AttendanceApp API v2")
    print(f"  Local  : http://127.0.0.1:{port}")
    print(f"  Network: http://{lan_ip}:{port}  <- students use this")
    print(f"{'='*56}\n")
    app.run(
        host="0.0.0.0",
        port=port,
        debug=os.environ.get("DEBUG", "false").lower() == "true",
    )
