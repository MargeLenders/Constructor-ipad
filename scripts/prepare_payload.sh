#!/bin/bash
# ==============================================================================
# prepare_payload.sh
# Extracts and packages Constructor (1997) game files for iPadOS & macOS.
# Supports:
#   1. GOG macOS installer (.pkg): e.g. constructor_en_2.0.0.14.pkg
#   2. Directory containing extracted DOS files (GAME.EXE, const.iso, etc.)
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEST_IOS="$ROOT_DIR/ConstructorIOS/Constructor.zip"
DEST_HOST="$ROOT_DIR/ConstructorHost/Constructor.zip"

INPUT_SOURCE="${1}"

if [ -z "$INPUT_SOURCE" ]; then
    echo "❌ Error: You must specify the path to the GOG installer (.pkg) or game directory."
    echo ""
    echo "Usage:"
    echo "  $0 <path_to_gog_installer.pkg>"
    echo "  $0 <path_to_extracted_game_directory>"
    echo ""
    echo "Example:"
    echo "  $0 ~/Downloads/constructor_en_2.0.0.14.pkg"
    exit 1
fi

if [ ! -e "$INPUT_SOURCE" ]; then
    echo "❌ Error: File or directory '$INPUT_SOURCE' does not exist."
    exit 1
fi

TEMP_WORK_DIR=$(mktemp -d /tmp/constructor_payload_XXXXXX)
trap 'rm -rf "$TEMP_WORK_DIR"' EXIT

STAGE_DIR="$TEMP_WORK_DIR/payload_stage"
mkdir -p "$STAGE_DIR"

echo "=== 📦 PREPARING CONSTRUCTOR (1997) PAYLOAD ==="

if [ -f "$INPUT_SOURCE" ] && [[ "$INPUT_SOURCE" == *.pkg ]]; then
    echo "1. Expanding official GOG installer (.pkg)..."
    EXPAND_DIR="$TEMP_WORK_DIR/pkg_expanded"
    pkgutil --expand "$INPUT_SOURCE" "$EXPAND_DIR"

    BOXER_DIR="$EXPAND_DIR/package.pkg/Scripts/payload/Contents/Resources/Constructor.boxer"
    if [ ! -d "$BOXER_DIR" ]; then
        echo "❌ Error: Unrecognized internal GOG package structure."
        exit 1
    fi

    echo "2. Copying MS-DOS game files and CD image (const.iso)..."
    HARDDISK_DIR="$BOXER_DIR/C Constructor.harddisk"
    if [ -d "$HARDDISK_DIR" ]; then
        cp -R "$HARDDISK_DIR"/* "$STAGE_DIR/"
    else
        echo "❌ Error: C Constructor.harddisk not found in package."
        exit 1
    fi

    if [ -f "$BOXER_DIR/D const.iso" ]; then
        cp "$BOXER_DIR/D const.iso" "$STAGE_DIR/const.iso"
    elif [ -f "$BOXER_DIR/const.iso" ]; then
        cp "$BOXER_DIR/const.iso" "$STAGE_DIR/const.iso"
    else
        echo "⚠️ Warning: CD image (const.iso) not found. The game may lack CD audio and cinematics."
    fi

elif [ -d "$INPUT_SOURCE" ]; then
    echo "1. Copying game files from local directory: $INPUT_SOURCE..."
    cp -R "$INPUT_SOURCE"/* "$STAGE_DIR/"
else
    echo "❌ Error: Unsupported input type. Must be a .pkg file or a directory."
    exit 1
fi

# Clean up unnecessary macOS/Boxer files if present
rm -f "$STAGE_DIR/manual.pdf" "$STAGE_DIR/support.txt" "$STAGE_DIR/bxlaunch.bat" "$STAGE_DIR/bxlaunch_m.bat" "$STAGE_DIR/.DS_Store"

echo "3. Generating autoboot configuration (AUTOBOOT.DBP)..."
printf "C:\\\\GAME.EXE\n" > "$STAGE_DIR/AUTOBOOT.DBP"

echo "4. Packaging Constructor.zip optimized for DOSBox-Pure..."
TEMP_ZIP="$TEMP_WORK_DIR/Constructor.zip"
(
    cd "$STAGE_DIR"
    zip -q -r -0 "$TEMP_ZIP" ./*
)

echo "5. Installing Constructor.zip into project bundles..."
cp "$TEMP_ZIP" "$DEST_IOS"
mkdir -p "$(dirname "$DEST_HOST")"
cp "$TEMP_ZIP" "$DEST_HOST"

ZIP_SIZE=$(du -h "$DEST_IOS" | awk '{print $1}')
echo ""
echo "=== ✅ PAYLOAD SUCCESSFULLY PREPARED ==="
echo "📁 iPadOS target: $DEST_IOS ($ZIP_SIZE)"
echo "📁 macOS target:  $DEST_HOST ($ZIP_SIZE)"
echo "🚀 Ready to build and run on your iPad."
