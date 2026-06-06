#!/bin/bash
# =============================================================================
# run_flutter.sh — Run Flutter app on Linux desktop
# Usage: bash run_flutter.sh
# =============================================================================

CYAN='\033[0;36m'; GREEN='\033[0;32m'; NC='\033[0m'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUTTER_DIR="$SCRIPT_DIR/flutter_app"

export PATH="$HOME/flutter/bin:$PATH"

# Bypass proxy for localhost traffic
export NO_PROXY=localhost,127.0.0.1,127.0.0.0/8,::1

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Flutter → Linux Desktop${NC}"
echo -e "  Hot reload : press  r  in this terminal"
echo -e "  Hot restart: press  R"
echo -e "  Quit       : press  q"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

cd "$FLUTTER_DIR"
flutter run -d linux
