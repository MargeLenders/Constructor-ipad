#!/bin/bash
# ==============================================================================
# 🏗️ Constructor (1997) Zero-Touch iPad Installer
# Native Apple Silicon Container for iPadOS & macOS
#
# GitHub Repository: https://github.com/MargeLenders/Constructor-ipad
#
# Quick execution via curl:
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/MargeLenders/Constructor-ipad/main/install.sh)"
#
# Or local execution:
#   ./install.sh [optional_path_to_gog_installer.pkg]
# ==============================================================================

set -eo pipefail

# ANSI Colors
BOLD="\033[1m"
GREEN="\033[1;32m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

echo ""
echo -e "${CYAN}============================================================================${RESET}"
echo -e "${BOLD}${CYAN}   🏗️  CONSTRUCTOR (1997) ZERO-TOUCH INSTALLER FOR IPAD${RESET}"
echo -e "${CYAN}   Native Apple Silicon Container (Swift & MetalKit)${RESET}"
echo -e "${CYAN}============================================================================${RESET}"
echo ""

# ------------------------------------------------------------------------------
# 1. Self-Bootstrap / Repository Setup
# ------------------------------------------------------------------------------
REPO_URL="https://github.com/MargeLenders/Constructor-ipad.git"
ROOT_DIR=""

if [ -f "./ConstructorIOS/ConstructorApp_iOS.swift" ]; then
    ROOT_DIR="$(pwd)"
elif [ -f "./Constructor-ipad/ConstructorIOS/ConstructorApp_iOS.swift" ]; then
    ROOT_DIR="$(pwd)/Constructor-ipad"
    cd "$ROOT_DIR"
elif [ -f "$HOME/Developer/Constructor-ipad/ConstructorIOS/ConstructorApp_iOS.swift" ]; then
    ROOT_DIR="$HOME/Developer/Constructor-ipad"
    cd "$ROOT_DIR"
    echo -e "${CYAN}🔄 Syncing latest code from GitHub...${RESET}"
    git pull --quiet 2>/dev/null || true
else
    TARGET_DIR="$HOME/Developer/Constructor-ipad"
    echo -e "${CYAN}📥 Step 1/6: Downloading Constructor repository into ${TARGET_DIR}...${RESET}"
    mkdir -p "$HOME/Developer"
    git clone --depth 1 "$REPO_URL" "$TARGET_DIR"
    ROOT_DIR="$TARGET_DIR"
    cd "$ROOT_DIR"
fi

cd "$ROOT_DIR"
chmod +x ./scripts/*.sh 2>/dev/null || true

# ------------------------------------------------------------------------------
# 2. Check System Prerequisites (Xcode & Developer Tools)
# ------------------------------------------------------------------------------
echo -e "${CYAN}🔍 Step 2/6: Checking development environment...${RESET}"

if ! command -v xcode-select >/dev/null 2>&1; then
    echo -e "${RED}❌ Xcode command line tools are not installed.${RESET}"
    echo -e "👉 Please run: ${BOLD}xcode-select --install${RESET} and try again."
    exit 1
fi

IPHONE_SDK=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)
if [ -z "$IPHONE_SDK" ]; then
    echo -e "${YELLOW}⚠️  Full Xcode application not selected (or iOS SDK missing).${RESET}"
    echo -e "👉 Make sure Xcode is installed from the Mac App Store and run:"
    echo -e "   ${BOLD}sudo xcode-select -s /Applications/Xcode.app/Contents/Developer${RESET}"
    exit 1
fi
echo -e "${GREEN}✅ iOS SDK located: $(basename "$IPHONE_SDK")${RESET}"

# ------------------------------------------------------------------------------
# 3. Locate or Request GOG Installer (.pkg)
# ------------------------------------------------------------------------------
echo -e "${CYAN}📦 Step 3/6: Locating Constructor (1997) game files...${RESET}"

clean_path() {
    python3 -c "
import sys, os
p = sys.argv[1].strip()
if (p.startswith('\"') and p.endswith('\"')) or (p.startswith('\'') and p.endswith('\'')):
    p = p[1:-1].strip()
p = p.replace(r'\\ ', ' ')
p = p.replace(r'\ ', ' ')
p = os.path.expanduser(p)
print(p)
" "$1" 2>/dev/null || echo "$1"
}

GOG_PKG=""
if [ -n "$1" ]; then
    CANDIDATE="$(clean_path "$1")"
    if [ -e "$CANDIDATE" ]; then
        GOG_PKG="$CANDIDATE"
    fi
fi

# Auto-detection if not specified
if [ -z "$GOG_PKG" ]; then
    if [ -f "$ROOT_DIR/ConstructorIOS/Constructor.zip" ] && [ $(stat -f%z "$ROOT_DIR/ConstructorIOS/Constructor.zip" 2>/dev/null || echo 0) -gt 350000000 ]; then
        echo -e "${GREEN}✅ Game payload already packaged (Constructor.zip present).${RESET}"
        GOG_PKG="ALREADY_PREPARED"
    else
        # Search ~/Downloads and current dir for GOG package
        AUTO_PKG=$(find "$HOME/Downloads" -maxdepth 2 -iname "*constructor*.pkg" 2>/dev/null | head -n 1 || true)
        if [ -z "$AUTO_PKG" ]; then
            AUTO_PKG=$(find "$HOME/Downloads" -maxdepth 2 -iname "constructor*.pkg" 2>/dev/null | head -n 1 || true)
        fi
        if [ -z "$AUTO_PKG" ]; then
            AUTO_PKG=$(find "$ROOT_DIR/.." -maxdepth 2 -iname "*constructor*.pkg" 2>/dev/null | head -n 1 || true)
        fi

        if [ -n "$AUTO_PKG" ] && [ -f "$AUTO_PKG" ]; then
            echo -e "${GREEN}🎯 Automatically detected GOG installer:${RESET} $AUTO_PKG"
            GOG_PKG="$AUTO_PKG"
        fi
    fi
fi

# Fallback: Drag and drop prompt if not already prepared
if [ "$GOG_PKG" != "ALREADY_PREPARED" ]; then
    while [ -z "$GOG_PKG" ] || [ ! -e "$GOG_PKG" ]; do
        echo ""
        echo -e "${BOLD}${YELLOW}┌────────────────────────────────────────────────────────────────────────┐${RESET}"
        echo -e "${BOLD}${YELLOW}│ 🎮 Please DRAG AND DROP your downloaded GOG installer file (.pkg)      │${RESET}"
        echo -e "${BOLD}${YELLOW}│    into this Terminal window and press ENTER:                          │${RESET}"
        echo -e "${BOLD}${YELLOW}└────────────────────────────────────────────────────────────────────────┘${RESET}"
        printf "👉 Drag & Drop file here: "
        read -r RAW_INPUT < /dev/tty
        GOG_PKG="$(clean_path "$RAW_INPUT")"
        if [ ! -e "$GOG_PKG" ]; then
            echo -e "${RED}❌ File not found at: '$GOG_PKG'. Please try dragging it again.${RESET}"
        fi
    done

    echo -e "${CYAN}⚙️ Extracting and packaging game payload...${RESET}"
    "$ROOT_DIR/scripts/prepare_payload.sh" "$GOG_PKG"
fi

# ------------------------------------------------------------------------------
# 4. Compile DOSBox-Pure Emulation Core (ARM64 iOS)
# ------------------------------------------------------------------------------
echo -e "${CYAN}⚙️ Step 4/6: Checking emulation engine (dosbox-pure ARM64)...${RESET}"

if [ ! -f "$ROOT_DIR/ConstructorIOS/dosbox_pure_libretro_ios.dylib" ]; then
    echo -e "${CYAN}🔨 Compiling dosbox-pure for iPadOS (multi-threaded)...${RESET}"
    "$ROOT_DIR/scripts/build_core.sh" ios
else
    echo -e "${GREEN}✅ dosbox_pure_libretro_ios.dylib ready.${RESET}"
fi

# ------------------------------------------------------------------------------
# 5. Detect Connected iPad
# ------------------------------------------------------------------------------
echo -e "${CYAN}📱 Step 5/6: Detecting connected iPad...${RESET}"

query_device() {
    python3 -c "
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
                devices.append({'name': name, 'udid': udid, 'state': state, 'model': model, 'is_ipad': is_ipad, 'available': is_available})
    
    ipads_avail = [d for d in devices if d['is_ipad'] and d['available']]
    other_avail = [d for d in devices if not d['is_ipad'] and d['available']]
    ipads_unavail = [d for d in devices if d['is_ipad']]
    
    selected = None
    if ipads_avail:
        selected = ipads_avail[0]
    elif other_avail:
        selected = other_avail[0]
    elif ipads_unavail:
        selected = ipads_unavail[0]
    elif devices:
        selected = devices[0]
        
    if selected:
        print(f\"{selected['udid']}|{selected['name']}|{selected['state']}|{selected['model']}\")
except Exception:
    pass
" 2>/dev/null || true
}

DEV_INFO=$(query_device)

while true; do
    if [ -n "$DEV_INFO" ]; then
        IFS="|" read -r TARGET_UDID TARGET_NAME TARGET_STATE TARGET_MODEL <<< "$DEV_INFO"
        if [[ "$TARGET_STATE" == *"available"* ]] || [[ "$TARGET_STATE" == *"connected"* ]]; then
            echo -e "${GREEN}✅ Device connected: ${BOLD}${TARGET_NAME}${RESET} (${TARGET_MODEL})"
            echo -e "   Identifier: ${CYAN}${TARGET_UDID}${RESET}"
            break
        else
            echo ""
            echo -e "${YELLOW}⚠️  Device detected: ${BOLD}${TARGET_NAME}${RESET} (${TARGET_MODEL})"
            echo -e "${YELLOW}   Status is '${TARGET_STATE}' (screen may be locked or pending authorization).${RESET}"
            echo -e "👉 Please ${BOLD}UNLOCK YOUR IPAD${RESET} and tap ${BOLD}'Trust this computer'${RESET} if prompted."
            printf "👉 Press [ENTER] once unlocked to continue: "
            read -r _ < /dev/tty
            sleep 1
            DEV_INFO=$(query_device)
        fi
    else
        echo ""
        echo -e "${YELLOW}🔌 No iPad detected via USB or local network.${RESET}"
        echo -e "👉 Please connect your iPad to this Mac with a cable, unlock it, and press [ENTER]: "
        read -r _ < /dev/tty
        sleep 1
        DEV_INFO=$(query_device)
    fi
done

# ------------------------------------------------------------------------------
# 6. Build & Code-Sign the Application
# ------------------------------------------------------------------------------
echo -e "${CYAN}🔨 Step 6/6: Building and signing Constructor app...${RESET}"

TEAM_ID=$(security find-certificate -c "Apple Development" -p 2>/dev/null | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU=\([^,]*\).*/\1/p' | head -n 1 || true)
if [ -n "$TEAM_ID" ]; then
    echo -e "${GREEN}🔑 Apple Developer Team detected:${RESET} $TEAM_ID"
fi

BUILD_SUCCESS=false
APP_PATH=""

# Primary build method: Xcodebuild with automatic provisioning
echo -e "${CYAN}Building with xcodebuild...${RESET}"
BUILD_ARGS=(-project Constructor.xcodeproj -scheme Constructor -destination "generic/platform=iOS" -allowProvisioningUpdates SYMROOT="$ROOT_DIR/build")
if [ -n "$TEAM_ID" ]; then
    BUILD_ARGS+=(DEVELOPMENT_TEAM="$TEAM_ID")
fi

if xcodebuild "${BUILD_ARGS[@]}" build > /tmp/constructor_xcodebuild.log 2>&1; then
    BUILD_SUCCESS=true
    if [ -d "$ROOT_DIR/build/Debug-iphoneos/Constructor.app" ]; then
        APP_PATH="$ROOT_DIR/build/Debug-iphoneos/Constructor.app"
    elif [ -d "$ROOT_DIR/build/Release-iphoneos/Constructor.app" ]; then
        APP_PATH="$ROOT_DIR/build/Release-iphoneos/Constructor.app"
    fi
else
    echo -e "${YELLOW}⚠️ xcodebuild encountered an issue. Switching to direct toolchain build...${RESET}"
fi

# Fallback build method: Direct swiftc + actool + codesign
if [ "$BUILD_SUCCESS" != "true" ] || [ -z "$APP_PATH" ]; then
    "$ROOT_DIR/scripts/build_ipados.sh"
    APP_PATH="$ROOT_DIR/build/Constructor_iOS.app"
fi

if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}❌ Build failed. Check /tmp/constructor_xcodebuild.log for details.${RESET}"
    exit 1
fi
echo -e "${GREEN}✅ Constructor app built and signed successfully!${RESET}"

# ------------------------------------------------------------------------------
# 7. Install & Launch on iPad
# ------------------------------------------------------------------------------
echo -e "${CYAN}🚀 Installing Constructor on your iPad (${TARGET_NAME})...${RESET}"
xcrun devicectl device install app --device "$TARGET_UDID" "$APP_PATH"

echo -e "${CYAN}⚡ Launching Constructor...${RESET}"
xcrun devicectl device process launch --device "$TARGET_UDID" com.margelenders.constructor || true

echo ""
echo -e "${GREEN}============================================================================${RESET}"
echo -e "${BOLD}${GREEN}   🎉 SUCCESS! Constructor (1997) is now running on your iPad!${RESET}"
echo -e "${GREEN}============================================================================${RESET}"
echo ""
echo -e "${BOLD}👉 FIRST TIME LAUNCHING?${RESET}"
echo -e "   If iPadOS displays ${YELLOW}\"Untrusted Developer\"${RESET} or ${YELLOW}\"Developer Mode Required\"${RESET}:"
echo -e "   1. On your iPad, open ${BOLD}Settings${RESET} ➜ ${BOLD}General${RESET} ➜ ${BOLD}VPN & Device Management${RESET}."
echo -e "   2. Under 'Developer App', tap your Apple ID and tap ${BOLD}'Trust'${RESET}."
echo -e "   3. (If not already active) Enable Developer Mode: ${BOLD}Settings${RESET} ➜ ${BOLD}Privacy & Security${RESET} ➜ ${BOLD}Developer Mode${RESET} ➜ Restart."
echo -e "   4. Tap the ${BOLD}Constructor${RESET} icon on your Home Screen to play!"
echo ""
echo -e "${BOLD}🎮 QUICK TOUCH CONTROLS:${RESET}"
echo -e "   • ${BOLD}1-Finger Tap${RESET}: Left-Click (select, build, buy)"
echo -e "   • ${BOLD}2-Finger Tap or Long Press${RESET}: Right-Click (cancel, context menu)"
echo -e "   • ${BOLD}2-Finger Drag / Pan${RESET}: Smooth 60 FPS map scrolling with inertia"
echo -e "   • ${BOLD}Apple Pencil${RESET}: Pixel-perfect cursor + double-tap/squeeze for Right-Click"
echo ""
