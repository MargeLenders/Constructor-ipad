#!/bin/bash
# ==============================================================================
# build_core.sh
# Compiles dosbox-pure-src as a dylib for iPadOS (arm64) and/or macOS (arm64).
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="$ROOT_DIR/dosbox-pure-src"

TARGET="${1:-ios}" # Options: 'ios', 'macos', 'all'

echo "=== ⚙️ COMPILING DOSBOX-PURE CORE ==="

NCPU=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)

if [ "$TARGET" == "ios" ] || [ "$TARGET" == "all" ]; then
    echo "1. Building for iPadOS (arm64)..."
    (
        cd "$SRC_DIR"
        make clean 2>/dev/null || true
        make platform=ios-arm64 -j"$NCPU"
    )
    cp "$SRC_DIR/dosbox_pure_libretro_ios.dylib" "$ROOT_DIR/ConstructorIOS/"
    echo "✅ dosbox_pure_libretro_ios.dylib copied to ConstructorIOS/"
fi

if [ "$TARGET" == "macos" ] || [ "$TARGET" == "all" ]; then
    echo "2. Building for macOS (arm64)..."
    (
        cd "$SRC_DIR"
        make clean 2>/dev/null || true
        make platform=osx ARCH=arm64 -j"$NCPU"
    )
    cp "$SRC_DIR/dosbox_pure_libretro.dylib" "$ROOT_DIR/ConstructorHost/"
    echo "✅ dosbox_pure_libretro.dylib copied to ConstructorHost/"
fi

echo ""
echo "=== ✅ CORE SUCCESSFULLY COMPILED ==="
