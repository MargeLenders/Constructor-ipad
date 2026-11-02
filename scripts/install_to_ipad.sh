#!/bin/bash
# ==============================================================================
# install_to_ipad.sh
# Installs and launches Constructor on a connected iPad using xcrun devicectl.
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH=""
if [ -d "$ROOT_DIR/build/Debug-iphoneos/Constructor.app" ]; then
    APP_PATH="$ROOT_DIR/build/Debug-iphoneos/Constructor.app"
elif [ -d "$ROOT_DIR/build/Constructor_iOS.app" ]; then
    APP_PATH="$ROOT_DIR/build/Constructor_iOS.app"
elif [ -d "$ROOT_DIR/build/Release-iphoneos/Constructor.app" ]; then
    APP_PATH="$ROOT_DIR/build/Release-iphoneos/Constructor.app"
fi

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
    echo "❌ Error: Built application not found in build directory"
    echo "👉 Build it first with: ./scripts/build_ipados.sh or ./install.sh"
    exit 1
fi

DEVICE_UDID="${1:-$DEVICE_UDID}"

if [ -z "$DEVICE_UDID" ]; then
    echo "🔍 Detecting connected iPad / iOS devices..."
    DEVICE_UDID=$(python3 -c "
import subprocess, re
try:
    out = subprocess.check_output(['xcrun', 'devicectl', 'list', 'devices'], text=True)
    devices = []
    for line in out.splitlines():
        if 'physical' in line:
            parts = re.split(r'\s{2,}', line.strip())
            if len(parts) >= 4:
                name = parts[0]
                udid = parts[1].replace('(UDID)', '').strip()
                state = parts[2].strip()
                model = parts[3].strip() if len(parts) > 3 else ''
                is_ipad = 'ipad' in name.lower() or 'ipad' in model.lower()
                is_available = 'available' in state.lower() or 'connected' in state.lower()
                devices.append({'name': name, 'udid': udid, 'state': state, 'is_ipad': is_ipad, 'available': is_available})
    ipads = [d for d in devices if d['is_ipad']]
    if ipads:
        print(ipads[0]['udid'])
    elif devices:
        print(devices[0]['udid'])
except Exception:
    pass
" 2>/dev/null || true)
fi

if [ -z "$DEVICE_UDID" ]; then
    echo "❌ No connected iPad detected automatically via USB or WiFi."
    echo ""
    echo "Manual usage:"
    echo "  $0 <DEVICE_UDID>"
    echo ""
    echo "To list available device identifiers:"
    echo "  xcrun devicectl list devices"
    exit 1
fi

BUNDLE_ID=$(python3 -c "
import plistlib
try:
    with open('$APP_PATH/Info.plist', 'rb') as f:
        plist = plistlib.load(f)
    print(plist.get('CFBundleIdentifier', 'com.yourname.constructor'))
except Exception:
    print('com.yourname.constructor')
" 2>/dev/null || echo "com.yourname.constructor")

echo "📱 Installing Constructor onto device ($DEVICE_UDID)..."
xcrun devicectl device install app --device "$DEVICE_UDID" "$APP_PATH"

echo "🚀 Launching Constructor on device ($BUNDLE_ID)..."
xcrun devicectl device process launch --device "$DEVICE_UDID" "$BUNDLE_ID" || true

echo "🎉 Constructor is now running on your iPad!"
