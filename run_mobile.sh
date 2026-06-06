#!/bin/bash
# =============================================================================
# run_mobile.sh — Run Flutter app on Android phone
#
# Modes:
#   bash run_mobile.sh usb       → USB cable (default)
#   bash run_mobile.sh wifi      → Wireless ADB
#   bash run_mobile.sh pair      → Pair phone over WiFi (first time)
#   bash run_mobile.sh devices   → List connected devices
# =============================================================================

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUTTER_DIR="$SCRIPT_DIR/flutter_app"

export PATH="$HOME/flutter/bin:$PATH"
export NO_PROXY=localhost,127.0.0.1,127.0.0.0/8,::1

MODE="${1:-usb}"

# ---------------------------------------------------------------------------
header() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  Flutter → Android ($MODE mode)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# ---------------------------------------------------------------------------
list_devices() {
    echo -e "${CYAN}Connected devices:${NC}"
    flutter devices
}

# ---------------------------------------------------------------------------
run_usb() {
    header
    echo ""
    echo -e "${YELLOW}Checklist before continuing:${NC}"
    echo "  ✓ USB cable connected"
    echo "  ✓ USB Debugging enabled on phone"
    echo "  ✓ Tap 'Allow' on the phone if it asks to trust this computer"
    echo ""
    echo -e "Detected devices:"
    adb devices
    echo ""

    # Get device ID
    DEVICE=$(adb devices | grep -v "List" | grep "device$" | awk '{print $1}' | head -1)
    if [ -z "$DEVICE" ]; then
        echo -e "${RED}No Android device detected via USB.${NC}"
        echo "Make sure USB debugging is on and the cable is connected."
        exit 1
    fi
    echo -e "${GREEN}Using device: $DEVICE${NC}"
    echo ""

    # Get phone's IP for Flask (phone needs to reach your machine)
    HOST_IP=$(hostname -I | awk '{print $1}')
    echo -e "${YELLOW}NOTE:${NC} Your machine's IP is ${GREEN}$HOST_IP${NC}"
    echo "Make sure config.dart has:"
    echo "  const String kBaseUrl = \"http://$HOST_IP:8080\";"
    echo ""
    read -p "Press Enter when ready to build and run..."

    cd "$FLUTTER_DIR"
    flutter run -d "$DEVICE"
}

# ---------------------------------------------------------------------------
pair_wifi() {
    header
    echo ""
    echo -e "${YELLOW}WiFi Pairing steps on your phone:${NC}"
    echo "  1. Go to Settings → Developer Options"
    echo "  2. Tap 'Wireless debugging'"
    echo "  3. Tap 'Pair device with pairing code'"
    echo "  4. Note the IP:port and 6-digit code shown"
    echo ""
    read -p "Enter the pairing IP:port (e.g. 192.168.1.5:37264): " PAIR_ADDR
    read -p "Enter the 6-digit pairing code: " PAIR_CODE

    echo ""
    log "Pairing..."
    adb pair "$PAIR_ADDR" "$PAIR_CODE"
    echo -e "${GREEN}Paired! Now run:  bash run_mobile.sh wifi${NC}"
}

# ---------------------------------------------------------------------------
run_wifi() {
    header
    echo ""
    echo -e "${YELLOW}WiFi Connection steps on your phone:${NC}"
    echo "  1. Go to Settings → Developer Options → Wireless debugging"
    echo "  2. Note the IP address and port shown at the top"
    echo ""
    read -p "Enter the device IP:port (e.g. 192.168.1.5:42345): " WIFI_ADDR

    echo ""
    adb connect "$WIFI_ADDR"

    DEVICE=$(adb devices | grep "$WIFI_ADDR" | awk '{print $1}')
    if [ -z "$DEVICE" ]; then
        echo -e "${RED}Could not connect to $WIFI_ADDR${NC}"
        echo "Try running:  bash run_mobile.sh pair   first."
        exit 1
    fi

    echo -e "${GREEN}Connected: $DEVICE${NC}"
    echo ""

    HOST_IP=$(hostname -I | awk '{print $1}')
    echo -e "${YELLOW}NOTE:${NC} Your machine's IP is ${GREEN}$HOST_IP${NC}"
    echo "Make sure config.dart has:"
    echo "  const String kBaseUrl = \"http://$HOST_IP:8080\";"
    echo ""
    read -p "Press Enter when ready..."

    cd "$FLUTTER_DIR"
    flutter run -d "$DEVICE"
}

# ---------------------------------------------------------------------------
case "$MODE" in
    usb)     run_usb ;;
    wifi)    run_wifi ;;
    pair)    pair_wifi ;;
    devices) list_devices ;;
    *)
        echo "Usage: bash run_mobile.sh [usb|wifi|pair|devices]"
        exit 1
        ;;
esac
