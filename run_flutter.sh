#!/bin/bash
# =============================================================================
# run_flutter.sh — Run the Flutter client
# Usage:
#   bash run_flutter.sh web      # default, web-first workflow
#   bash run_flutter.sh linux    # optional desktop workflow
# =============================================================================

set -e

CYAN='\033[0;36m'; GREEN='\033[0;32m'; NC='\033[0m'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUTTER_DIR="$SCRIPT_DIR/flutter_app"

export PATH="$HOME/flutter/bin:$PATH"
export NO_PROXY=localhost,127.0.0.1,127.0.0.0/8,::1

MODE="${1:-web}"
API_BASE_URL="${API_BASE_URL:-http://127.0.0.1:5000}"
WEB_PORT="${WEB_PORT:-8080}"
APP_BASE_URL="${APP_BASE_URL:-http://localhost:$WEB_PORT}"
ADMIN_KEY="${ADMIN_KEY:-dev-admin-key}"

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Flutter → ${MODE}${NC}"
echo -e "  API : $API_BASE_URL"
echo -e "  App : $APP_BASE_URL"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

cd "$FLUTTER_DIR"

COMMON_ARGS=(
  "--dart-define=API_BASE_URL=$API_BASE_URL"
  "--dart-define=APP_BASE_URL=$APP_BASE_URL"
  "--dart-define=ADMIN_KEY=$ADMIN_KEY"
)

case "$MODE" in
  web)
    flutter run -d chrome --web-port "$WEB_PORT" "${COMMON_ARGS[@]}"
    ;;
  linux)
    flutter run -d linux "${COMMON_ARGS[@]}"
    ;;
  *)
    echo "Usage: bash run_flutter.sh [web|linux]"
    exit 1
    ;;
esac
