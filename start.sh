#!/bin/bash

# =============================================================================

# start.sh — Start AttendanceApp (Flask + Flutter)

# =============================================================================

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLASK_DIR="$SCRIPT_DIR/flask_api"
FLUTTER_DIR="$SCRIPT_DIR/flutter_app"

export PATH="$HOME/flutter/bin:$PATH"
export NO_PROXY=localhost,127.0.0.1,127.0.0.0/8,::1

log()  { echo -e "${CYAN}[START]${NC} $1"; }
ok()   { echo -e "${GREEN}[  OK ]${NC} $1"; }
fail() { echo -e "${RED}[FAIL ]${NC} $1"; exit 1; }

# ---- Check prerequisites ----

[ ! -f "$FLASK_DIR/venv/bin/activate" ] && fail "venv not found. Run: bash setup.sh first."
[ ! -d "$FLUTTER_DIR/linux" ]           && fail "Flutter linux platform missing. Run: bash setup.sh first."

# ---- Kill any existing process on port 8080 ----

log "Checking port 8080..."
fuser -k 8080/tcp 2>/dev/null && sleep 1 && log "Killed existing process on 8080."

# ---- Activate Flask env ----

source "$FLASK_DIR/venv/bin/activate"

# ---- Start Flutter in background ----

(
sleep 3
log "Launching Flutter app..."
cd "$FLUTTER_DIR"
flutter run -d linux
) &

# ---- Run Flask in FOREGROUND (CRITICAL FIX) ----

log "Starting Flask API..."
cd "$FLASK_DIR"
python main.py
