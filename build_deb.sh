#!/bin/bash
# =============================================================================
# build_deb.sh — Packages AttendanceApp as a .deb for Ubuntu/Debian
#
# What it does:
#   1. Builds Flutter Linux release binary
#   2. Bundles Flask + venv inside the package
#   3. Creates a .desktop launcher
#   4. Produces attendanceapp_1.0.0_amd64.deb
#
# After install:
#   - App appears in application menu as "AttendanceApp"
#   - Run from terminal: attendanceapp
#   - Config lives at: ~/.config/attendanceapp/
#   - DB lives at:     ~/.local/share/attendanceapp/attendance.db
#
# Usage: bash build_deb.sh
# =============================================================================

set -e
CYAN='\033[0;36m'; GREEN='\033[0;32m'; NC='\033[0m'
log() { echo -e "${CYAN}[DEB]${NC} $1"; }
ok()  { echo -e "${GREEN}[ OK]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUTTER_DIR="$SCRIPT_DIR/flutter_app"
FLASK_DIR="$SCRIPT_DIR/flask_api"
VERSION="1.0.0"
PKG_NAME="attendanceapp"
ARCH="amd64"
DEB_ROOT="/tmp/${PKG_NAME}_${VERSION}"

export PATH="$HOME/flutter/bin:$PATH"

# ---- 1. Build Flutter release binary ----
log "Building Flutter release binary..."
cd "$FLUTTER_DIR"
flutter build linux --release
ok "Flutter binary built."

FLUTTER_BUILD="$FLUTTER_DIR/build/linux/x64/release/bundle"

# ---- 2. Create .deb directory structure ----
log "Creating .deb structure..."
rm -rf "$DEB_ROOT"
mkdir -p "$DEB_ROOT/DEBIAN"
mkdir -p "$DEB_ROOT/usr/bin"
mkdir -p "$DEB_ROOT/usr/lib/$PKG_NAME/flutter"
mkdir -p "$DEB_ROOT/usr/lib/$PKG_NAME/flask"
mkdir -p "$DEB_ROOT/usr/share/applications"
mkdir -p "$DEB_ROOT/usr/share/icons/hicolor/256x256/apps"

# ---- 3. Copy Flutter bundle ----
log "Copying Flutter bundle..."
cp -r "$FLUTTER_BUILD/." "$DEB_ROOT/usr/lib/$PKG_NAME/flutter/"

# ---- 4. Copy Flask + install venv inside package ----
log "Setting up Flask inside package..."
cp "$FLASK_DIR/main.py"          "$DEB_ROOT/usr/lib/$PKG_NAME/flask/"
cp "$FLASK_DIR/requirements.txt" "$DEB_ROOT/usr/lib/$PKG_NAME/flask/"

# Create a fresh venv inside the package
python3 -m venv "$DEB_ROOT/usr/lib/$PKG_NAME/flask/venv"
"$DEB_ROOT/usr/lib/$PKG_NAME/flask/venv/bin/pip" install \
    flask flask-cors geopy bcrypt PyJWT pyopenssl -q
ok "Flask venv created inside package."

# ---- 5. Launcher script ----
cat > "$DEB_ROOT/usr/bin/$PKG_NAME" << 'LAUNCHER'
#!/bin/bash
# AttendanceApp launcher

INSTALL_DIR="/usr/lib/attendanceapp"
DATA_DIR="$HOME/.local/share/attendanceapp"
CONFIG_DIR="$HOME/.config/attendanceapp"

mkdir -p "$DATA_DIR" "$CONFIG_DIR"

export NO_PROXY=localhost,127.0.0.1,127.0.0.0/8,::1
export DATABASE="$DATA_DIR/attendance.db"

# Generate JWT secret if not set
if [ ! -f "$CONFIG_DIR/jwt_secret" ]; then
    python3 -c "import secrets; print(secrets.token_hex(32))" > "$CONFIG_DIR/jwt_secret"
fi
export JWT_SECRET="$(cat "$CONFIG_DIR/jwt_secret")"

# Kill any existing instance
fuser -k 8080/tcp 2>/dev/null || true

# Start Flask
source "$INSTALL_DIR/flask/venv/bin/activate"
cd "$INSTALL_DIR/flask"
python main.py &
FLASK_PID=$!

# Wait for Flask
for i in $(seq 1 15); do
    curl -sk "https://127.0.0.1:8080/health" > /dev/null 2>&1 && break
    sleep 1
done

# Launch Flutter
"$INSTALL_DIR/flutter/attendance_app"

# Cleanup
kill $FLASK_PID 2>/dev/null || true
LAUNCHER
chmod +x "$DEB_ROOT/usr/bin/$PKG_NAME"

# ---- 6. .desktop file ----
cat > "$DEB_ROOT/usr/share/applications/$PKG_NAME.desktop" << DESKTOP
[Desktop Entry]
Name=AttendanceApp
Comment=Lecture attendance management system
Exec=attendanceapp
Icon=attendanceapp
Terminal=false
Type=Application
Categories=Education;Utility;
Keywords=attendance;lecture;students;
DESKTOP

# ---- 7. DEBIAN/control ----
cat > "$DEB_ROOT/DEBIAN/control" << CONTROL
Package: $PKG_NAME
Version: $VERSION
Section: education
Priority: optional
Architecture: $ARCH
Depends: python3, python3-venv, libgtk-3-0, libblkid1
Maintainer: IIITA AttendanceApp
Description: Lecture attendance management system
 AttendanceApp allows instructors to create attendance sessions,
 share QR codes with students, and export attendance CSV files.
 Students mark attendance from any phone browser on the same WiFi.
CONTROL

# ---- 8. postinst script ----
cat > "$DEB_ROOT/DEBIAN/postinst" << 'POSTINST'
#!/bin/bash
echo ""
echo "  AttendanceApp installed successfully!"
echo "  Run: attendanceapp"
echo "  Or find it in your application menu."
echo ""
echo "  Default login: admin / admin123"
echo "  Change your password after first login!"
echo ""
POSTINST
chmod 755 "$DEB_ROOT/DEBIAN/postinst"

# ---- 9. Build .deb ----
log "Building .deb package..."
cd /tmp
dpkg-deb --build "$DEB_ROOT" "$SCRIPT_DIR/${PKG_NAME}_${VERSION}_${ARCH}.deb"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  .deb package built!${NC}"
echo -e "  File: $SCRIPT_DIR/${PKG_NAME}_${VERSION}_${ARCH}.deb"
echo ""
echo -e "  Install on any Ubuntu/Debian machine:"
echo -e "    sudo dpkg -i ${PKG_NAME}_${VERSION}_${ARCH}.deb"
echo -e "    sudo apt install -f   # fix any missing deps"
echo ""
echo -e "  Then just run: attendanceapp"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"