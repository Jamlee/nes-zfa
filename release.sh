#!/bin/bash
set -e

# Release script: build all distributable packages without bundled ROMs
# Output goes to out/ directory

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }

echo ""
echo "╔══════════════════════════════════════╗"
echo "║     NEZ-ZFA Release Build            ║"
echo "║     All platforms, no bundled ROMs    ║"
echo "╚══════════════════════════════════════╝"
echo ""

# Clean previous output
rm -rf "$SCRIPT_DIR/out"

# Build all release targets without ROMs
"$SCRIPT_DIR/build.sh" dmg --release --no-rom
"$SCRIPT_DIR/build.sh" dmg-avalonia --release --no-rom
"$SCRIPT_DIR/build.sh" apk --release --no-rom
"$SCRIPT_DIR/build.sh" apk-avalonia --release --no-rom
"$SCRIPT_DIR/build.sh" exe-avalonia

echo ""
echo "╔══════════════════════════════════════╗"
echo "║     Release Build Complete!          ║"
echo "╚══════════════════════════════════════╝"
echo ""
info "Output directory:"
ls -lhS "$SCRIPT_DIR/out/" 2>/dev/null
echo ""
du -sh "$SCRIPT_DIR/out/"
