#!/bin/bash
# =============================================================================
# run_flask.sh — Start the Flask REST API
# Usage: bash run_flask.sh
# =============================================================================

CYAN='\033[0;36m'; GREEN='\033[0;32m'; NC='\033[0m'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLASK_DIR="$SCRIPT_DIR/flask_api"

# Activate venv
if [ ! -f "$FLASK_DIR/venv/bin/activate" ]; then
    echo -e "\033[0;31m[ERROR]\033[0m venv not found. Run bash setup.sh first."
    exit 1
fi

source "$FLASK_DIR/venv/bin/activate"

# Default env vars (override by setting them before running this script)
export ADMIN_KEY="${ADMIN_KEY:-supersecret}"
export APP_BASE_URL="${APP_BASE_URL:-http://localhost:8080}"
export DEBUG="${DEBUG:-true}"
export PORT="${PORT:-8080}"

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Flask API starting...${NC}"
echo -e "  URL      : http://0.0.0.0:$PORT"
echo -e "  Admin key: $ADMIN_KEY"
echo -e "  DB       : $FLASK_DIR/attendance.db"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

cd "$FLASK_DIR"
python main.py
