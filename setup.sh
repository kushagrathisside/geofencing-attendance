#!/bin/bash
# =============================================================================
# setup.sh — Run ONCE on a fresh machine to install everything
# Usage   : bash setup.sh
# =============================================================================

set -e

CYAN='\033[0;36m'; GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${CYAN}[SETUP]${NC} $1"; }
ok()   { echo -e "${GREEN}[  OK ]${NC} $1"; }
fail() { echo -e "${RED}[FAIL ]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -----------------------------------------------------------------------------
# 1. System packages
# -----------------------------------------------------------------------------
log "Installing system dependencies..."
sudo apt update
sudo apt install -y \
    curl git unzip xz-utils zip \
    clang cmake ninja-build pkg-config \
    libgtk-3-dev lld binutils mesa-utils \
    python3 python3-pip python3-venv \
    adb
ok "System dependencies installed."

# -----------------------------------------------------------------------------
# 2. Flutter SDK
# -----------------------------------------------------------------------------
if [ -d "$HOME/flutter" ]; then
    ok "Flutter already at ~/flutter — skipping clone."
else
    log "Cloning Flutter stable..."
    git clone https://github.com/flutter/flutter.git -b stable "$HOME/flutter"
    ok "Flutter cloned."
fi

if ! grep -q 'flutter/bin' "$HOME/.bashrc"; then
    echo 'export PATH="$HOME/flutter/bin:$PATH"' >> "$HOME/.bashrc"
    ok "Flutter added to PATH."
fi
export PATH="$HOME/flutter/bin:$PATH"

log "Pre-caching Flutter artifacts..."
flutter precache --linux --web --android
ok "Flutter pre-cached."

# -----------------------------------------------------------------------------
# 3. Flask virtual environment
# -----------------------------------------------------------------------------
FLASK_DIR="$SCRIPT_DIR/flask_api"
if [ ! -d "$FLASK_DIR/venv" ]; then
    log "Creating Python venv..."
    python3 -m venv "$FLASK_DIR/venv"
fi
log "Installing Flask dependencies..."
"$FLASK_DIR/venv/bin/pip" install --upgrade pip -q
"$FLASK_DIR/venv/bin/pip" install flask flask-cors geopy -q
ok "Flask ready."

# -----------------------------------------------------------------------------
# 4. Flutter packages + platform support
# -----------------------------------------------------------------------------
FLUTTER_DIR="$SCRIPT_DIR/flutter_app"
cd "$FLUTTER_DIR"

log "Getting Flutter packages..."
flutter pub get

[ ! -d "$FLUTTER_DIR/linux" ] && flutter create . --platforms linux && ok "Linux platform added."
[ ! -d "$FLUTTER_DIR/web"   ] && flutter create . --platforms web   && ok "Web platform added."
[ ! -d "$FLUTTER_DIR/android" ] && flutter create . --platforms android && ok "Android platform added."

ok "Flutter app ready."

# -----------------------------------------------------------------------------
# 5. Proxy / NO_PROXY
# -----------------------------------------------------------------------------
if ! grep -q 'NO_PROXY' "$HOME/.bashrc"; then
    echo 'export NO_PROXY=localhost,127.0.0.1,127.0.0.0/8,::1' >> "$HOME/.bashrc"
    ok "NO_PROXY set."
fi

# -----------------------------------------------------------------------------
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        Setup complete! ✓                 ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo "  1. Edit  flutter_app/lib/config.dart   ← set kBaseUrl + kAdminKey"
echo "  2. Run:  bash run_flask.sh             ← Terminal 1"
echo "  3. Run:  bash run_flutter.sh           ← Terminal 2  (Linux desktop)"
echo "  4. Run:  bash run_mobile.sh            ← Terminal 2  (Android phone)"
echo ""
echo "  source ~/.bashrc   ← apply PATH in current terminal"
