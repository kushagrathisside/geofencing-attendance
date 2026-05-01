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
export ADMIN_KEY="${ADMIN_KEY:-dev-admin-key}"
export DB_HOST="${DB_HOST:-localhost}"
export DB_NAME="${DB_NAME:-attendance}"
export DB_USER="${DB_USER:-admin}"
export DB_PASS="${DB_PASS:-dev-db-password}"
export REDIS_HOST="${REDIS_HOST:-localhost}"
export ALLOWED_SUBNETS="${ALLOWED_SUBNETS:-127.0.0.1/32,::1/128,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12}"
export TRUST_PROXY_HEADERS="${TRUST_PROXY_HEADERS:-false}"
export TRUSTED_PROXY_SUBNETS="${TRUSTED_PROXY_SUBNETS:-127.0.0.1/32,::1/128}"
export PORT="${PORT:-5000}"

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Flask API starting...${NC}"
echo -e "  URL      : http://0.0.0.0:$PORT"
echo -e "  DB       : PostgreSQL $DB_USER@$DB_HOST/$DB_NAME"
echo -e "  Redis    : $REDIS_HOST:6379"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

cd "$FLASK_DIR"
python main.py
