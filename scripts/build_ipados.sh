#!/bin/bash
# ==============================================================================
# build_ipados.sh
# Command line builder for iPadOS (arm64)
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
IOS_DIR="$ROOT_DIR/ConstructorIOS"
APP_DIR="$ROOT_DIR/build/Constructor_iOS.app"
FRAMEWORKS_DIR="$APP_DIR/Frameworks"

# Automatic detection of signing identity (using unambiguous SHA-1 hash)
SIGNING_IDENTITY="${SIGNING_IDENTITY:-$(security find-identity -v -p codesigning | grep "Apple Development" | head -n 1 | awk '{print $2}')}"
PROVISION_PROFILE="${PROVISION_PROFILE:-$(find "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" -name "*.mobileprovision" 2>/dev/null | head -n 1)}"
ENTITLEMENTS="$IOS_DIR/Constructor.entitlements"

echo "=== 🔨 COMPILING CONSTRUCTOR FOR IPADOS (ARM64) ==="

if [ ! -f "$IOS_DIR/Constructor.zip" ]; then
    echo "❌ Error: ConstructorIOS/Constructor.zip not found"
    echo "👉 Run first: ./scripts/prepare_payload.sh <path_to_gog.pkg>"
    exit 1
fi

if [ ! -f "$IOS_DIR/dosbox_pure_libretro_ios.dylib" ]; then
    echo "⚙️ Compiling required emulation core..."
    "$SCRIPT_DIR/build_core.sh" ios
fi

IPHONE_SDK=$(xcrun --sdk iphoneos --show-sdk-path)

echo "1. Preparing output directories..."
rm -rf "$ROOT_DIR/build"
mkdir -p "$APP_DIR"
mkdir -p "$FRAMEWORKS_DIR"

echo "2. Compiling Swift executable..."
SDKROOT="$IPHONE_SDK" swiftc -O -target arm64-apple-ios17.0 \
  -import-objc-header "$IOS_DIR/ConstructorIOS-Bridging-Header.h" \
  -I "$IOS_DIR" \
  -Xlinker -rpath -Xlinker @executable_path/Frameworks \
  -Xlinker -rpath -Xlinker @executable_path \
  "$IOS_DIR/AudioRingBuffer.swift" \
  "$IOS_DIR/AudioEngineManager.swift" \
  "$IOS_DIR/MetalRenderer.swift" \
  "$IOS_DIR/InputManager_iOS.swift" \
  "$IOS_DIR/GameMTKView_iOS.swift" \
  "$IOS_DIR/GameView_iOS.swift" \
  "$IOS_DIR/LibretroCore.swift" \
  "$IOS_DIR/GameSession.swift" \
  "$IOS_DIR/ConstructorApp_iOS.swift" \
  -o "$APP_DIR/Constructor"

echo "3. Compiling asset catalog and app icons..."
xcrun actool "$IOS_DIR/Assets.xcassets" \
  --compile "$APP_DIR" \
  --platform iphoneos \
  --minimum-deployment-target 17.0 \
  --target-device ipad \
  --target-device iphone \
  --app-icon AppIcon \
  --output-partial-info-plist "$ROOT_DIR/build/partial_info.plist" \
  --standalone-icon-behavior all

sips -z 167 167 "$IOS_DIR/Assets.xcassets/AppIcon.appiconset/AppIcon-Light.png" --out "$APP_DIR/AppIcon83.5x83.5@2x~ipad.png" > /dev/null 2>&1 || true
sips -z 152 152 "$IOS_DIR/Assets.xcassets/AppIcon.appiconset/AppIcon-Light.png" --out "$APP_DIR/AppIcon76x76@2x~ipad.png" > /dev/null 2>&1 || true
sips -z 120 120 "$IOS_DIR/Assets.xcassets/AppIcon.appiconset/AppIcon-Light.png" --out "$APP_DIR/AppIcon60x60@2x.png" > /dev/null 2>&1 || true
cp "$IOS_DIR/Assets.xcassets/AppIcon.appiconset/AppIcon-Light.png" "$APP_DIR/AppIcon1024x1024.png" 2>/dev/null || true

echo "4. Packaging bundle resources and emulation core..."
cp "$IOS_DIR/Info.plist" "$APP_DIR/Info.plist"
cp "$IOS_DIR/Constructor.zip" "$APP_DIR/Constructor.zip"
cp "$IOS_DIR/dosbox_pure_libretro_ios.dylib" "$FRAMEWORKS_DIR/dosbox_pure_libretro_ios.dylib"
cp "$IOS_DIR/dosbox_pure_libretro_ios.dylib" "$APP_DIR/dosbox_pure_libretro_ios.dylib"

install_name_tool -id @rpath/dosbox_pure_libretro_ios.dylib "$FRAMEWORKS_DIR/dosbox_pure_libretro_ios.dylib"
install_name_tool -id @rpath/dosbox_pure_libretro_ios.dylib "$APP_DIR/dosbox_pure_libretro_ios.dylib"

if [ -n "$SIGNING_IDENTITY" ] && [ -f "$PROVISION_PROFILE" ]; then
    echo "5. Code signing with identity: $SIGNING_IDENTITY..."
    cp "$PROVISION_PROFILE" "$APP_DIR/embedded.mobileprovision"
    codesign -f -s "$SIGNING_IDENTITY" --timestamp=none "$FRAMEWORKS_DIR/dosbox_pure_libretro_ios.dylib"
    codesign -f -s "$SIGNING_IDENTITY" --timestamp=none "$APP_DIR/dosbox_pure_libretro_ios.dylib"
    codesign -f -s "$SIGNING_IDENTITY" --entitlements "$ENTITLEMENTS" --timestamp=none "$APP_DIR"
    codesign -vvv --deep --strict "$APP_DIR"
    echo "=== ✅ APP SUCCESSFULLY BUILT AND SIGNED ==="
else
    echo "⚠️ Note: No code signing identity or provisioning profile detected in CLI environment."
    echo "👉 You can open the project in Xcode ('open Constructor.xcodeproj') to sign and deploy automatically with 1 click."
fi

echo "Bundle location: $APP_DIR"
