#!/bin/bash
set -e

# Release script: build all distributable packages
# Output goes to out/ directory

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }

echo ""
echo "╔══════════════════════════════════════╗"
echo "║     NEZ-ZFA Release Build            ║"
echo "║     All platforms                    ║"
echo "╚══════════════════════════════════════╝"
echo ""

# Clean previous output
rm -rf "$SCRIPT_DIR/out"

# Generate all icons from docs/icon.svg
if [ -f "$SCRIPT_DIR/scripts/generate_icons.sh" ]; then
    info "Syncing icons from docs/icon.svg..."
    bash "$SCRIPT_DIR/scripts/generate_icons.sh" || { echo "ERROR: Icon generation failed"; exit 1; }
    ok "Icons synced"
fi

# Clear build caches to avoid stale PCH/module paths (e.g. after project rename)
info "Clearing build caches..."
rm -rf \
  "$SCRIPT_DIR/flutter/build/macos/ModuleCache.noindex" \
  "$SCRIPT_DIR/flutter/build/macos/DerivedData" \
  "$SCRIPT_DIR/flutter/.dart_tool/flutter_build" \
  2>/dev/null || true
ok "Build caches cleared"

# Helper: clean intermediate artifacts after each build step
clean_flutter_build() {
  rm -rf \
    "$SCRIPT_DIR/flutter/build" \
    "$SCRIPT_DIR/flutter/android/app/src/main/jniLibs" \
    "$SCRIPT_DIR/lib/libnez_emu.so" \
    "$SCRIPT_DIR/lib/libnez_emu.so.o" \
    2>/dev/null || true
}

clean_avalonia_build() {
  rm -rf \
    "$SCRIPT_DIR/avalonia/NezAvalonia/bin" \
    "$SCRIPT_DIR/avalonia/NezAvalonia/obj" \
    "$SCRIPT_DIR/avalonia/NezAvalonia/lib" \
    "$SCRIPT_DIR/avalonia/NezAvalonia/libnez_emu.dylib" \
    "$SCRIPT_DIR/avalonia/NezAvalonia/NezAvalonia.Browser/bin" \
    "$SCRIPT_DIR/avalonia/NezAvalonia/NezAvalonia.Browser/obj" \
    2>/dev/null || true
}

clean_zig_artifacts() {
  rm -f \
    "$SCRIPT_DIR/lib/libnez_emu.so" \
    "$SCRIPT_DIR/lib/libnez_emu.so.o" \
    "$SCRIPT_DIR/lib/nez_emu.dll" \
    "$SCRIPT_DIR/lib/nez_emu.dll.o" \
    "$SCRIPT_DIR/lib/nez_emu.lib" \
    "$SCRIPT_DIR/lib/nez_emu.pdb" \
    2>/dev/null || true
  rm -rf \
    "$SCRIPT_DIR/lib/zig-out" \
    2>/dev/null || true
}

# Clean .app bundles from out/ after DMG packaging (no longer needed)
clean_out_apps() {
  rm -rf \
    "$SCRIPT_DIR/out"/*.app \
    2>/dev/null || true
}

# ---- Step 1: macOS Flutter DMG ----
info "[1/7] Building nez-macos-flutter.dmg ..."
"$SCRIPT_DIR/build.sh" dmg --release
clean_flutter_build
clean_out_apps
ok "[1/7] nez-macos-flutter.dmg done"

# ---- Step 2: macOS Avalonia DMG ----
info "[2/7] Building nez-macos-avalonia.dmg ..."
"$SCRIPT_DIR/build.sh" dmg-avalonia --release
clean_avalonia_build
clean_out_apps
ok "[2/7] nez-macos-avalonia.dmg done"

# ---- Step 3: Android Flutter APK ----
info "[3/7] Building nez-android-flutter.apk ..."
"$SCRIPT_DIR/build.sh" apk --release
clean_flutter_build
clean_zig_artifacts
ok "[3/7] nez-android-flutter.apk done"

# ---- Step 4: Android Avalonia APK ----
info "[4/7] Building nez-android-avalonia.apk ..."
"$SCRIPT_DIR/build.sh" apk-avalonia --release
clean_avalonia_build
clean_zig_artifacts
ok "[4/7] nez-android-avalonia.apk done"

# ---- Step 5: Flutter Web ----
info "[5/7] Building nez-web-flutter.zip ..."
"$SCRIPT_DIR/build.sh" web-flutter --release
clean_flutter_build
ok "[5/7] nez-web-flutter.zip done"

# ---- Step 6: Avalonia Web ----
info "[6/7] Building nez-web-avalonia.zip ..."
"$SCRIPT_DIR/build.sh" web-avalonia --release
clean_avalonia_build
ok "[6/7] nez-web-avalonia.zip done"

# ---- Step 7: Windows Avalonia ZIP ----
info "[7/7] Building nez-windows-avalonia.zip ..."
"$SCRIPT_DIR/build.sh" exe-avalonia
clean_avalonia_build
clean_zig_artifacts
ok "[7/7] nez-windows-avalonia.zip done"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║     Release Build Complete!          ║"
echo "╚══════════════════════════════════════╝"
echo ""
info "Output directory:"
ls -lhS "$SCRIPT_DIR/out/" 2>/dev/null
echo ""
du -sh "$SCRIPT_DIR/out/"
