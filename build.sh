#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
FLUTTER_DIR="$SCRIPT_DIR/flutter"
AVALONIA_DIR="$SCRIPT_DIR/avalonia/NezAvalonia"
ZIG_OUT="$LIB_DIR/zig-out/lib"
OUT_DIR="$SCRIPT_DIR/out"

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
fail()  { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

usage() {
    cat <<'USAGE'
Nez — NES Emulator

Usage: ./build.sh <command> [--release] [--no-rom]

  flutter             Build lib + run Flutter macOS app
  avalonia            Build lib + run Avalonia macOS app
  android             Build lib + run Flutter on Android
  android-avalonia    Build lib + run Avalonia on Android
  apk                 Build Flutter Android APK → out/
  apk-avalonia        Build Avalonia Android APK → out/
  dmg                 Build Flutter macOS DMG → out/
  dmg-avalonia        Build Avalonia macOS DMG → out/
  exe                 Build Flutter Windows EXE (requires Windows)
  exe-avalonia        Cross-compile Avalonia Windows EXE → out/
  all                 Build all: apk + apk-avalonia + dmg + dmg-avalonia + exe-avalonia → out/
  lib                 Build Zig shared library only
  clean               Clean all build artifacts
  check               Check toolchain versions

Examples:
  ./build.sh flutter
  ./build.sh avalonia
  ./build.sh apk --release
  ./build.sh apk --release --no-rom
  ./build.sh apk-avalonia --release
  ./build.sh exe
USAGE
}

check_tools() {
    command -v zig >/dev/null 2>&1 || fail "zig not found"
    ok "zig $(zig version)"
}

build_lib() {
    info "Building libnez_emu..."
    cd "$LIB_DIR"
    zig build lib -Doptimize=ReleaseFast
    ok "libnez_emu.dylib ($(du -h "$ZIG_OUT"/libnez_emu.* 2>/dev/null | head -1 | awk '{print $1}'))"
}

copy_dylib_flutter() {
    local dylib="$ZIG_OUT/libnez_emu.dylib"
    [ -f "$dylib" ] || fail "libnez_emu.dylib not found"
    for d in "$FLUTTER_DIR/build/macos/Build/Products"/*/nez_flutter.app/Contents/MacOS; do
        [ -d "$d" ] && cp -f "$dylib" "$d/" && codesign --force --sign - "$d/libnez_emu.dylib" 2>/dev/null || true
    done
}

copy_dylib_avalonia() {
    local dylib="$ZIG_OUT/libnez_emu.dylib"
    [ -f "$dylib" ] || fail "libnez_emu.dylib not found"
    cp -f "$dylib" "$AVALONIA_DIR/"
}

build_android_so() {
    info "Cross-compiling for Android arm64..."
    cd "$LIB_DIR"
    local ndk=""
    if [ -n "$ANDROID_NDK_HOME" ]; then
        ndk="$ANDROID_NDK_HOME"
    else
        for d in ~/Library/Android/sdk/ndk/*/; do
            if [ -d "${d}toolchains/llvm/prebuilt/darwin-x86_64/sysroot" ]; then
                ndk="${d%/}"
            fi
        done
    fi
    [ -z "$ndk" ] && fail "Android NDK not found (need darwin-x86_64 sysroot)"
    local sysroot="$ndk/toolchains/llvm/prebuilt/darwin-x86_64/sysroot"

    cat > /tmp/nez-android-libc.conf <<LIBC
include_dir=$sysroot/usr/include
sys_include_dir=$sysroot/usr/include/aarch64-linux-android
crt_dir=$sysroot/usr/lib/aarch64-linux-android/29
msvc_lib_dir=
kernel32_lib_dir=
kernel_header_dir=
gcc_dir=
LIBC
    zig build-lib src/ffi.zig -OReleaseFast -target aarch64-linux-android \
        --libc /tmp/nez-android-libc.conf -lc -dynamic --name nez_emu
    ok "Android .so compiled"
}

copy_so_flutter() {
    local so="$FLUTTER_DIR/android/app/src/main/jniLibs/arm64-v8a/libnez_emu.so"
    mkdir -p "$(dirname "$so")"
    cp -f "$LIB_DIR/libnez_emu.so" "$so"
    rm -f "$LIB_DIR/libnez_emu.so" "$LIB_DIR/libnez_emu.so.o"
    ok "Copied .so → Flutter jniLibs/"
}

copy_so_avalonia() {
    local dest="$AVALONIA_DIR/lib/arm64-v8a/libnez_emu.so"
    mkdir -p "$(dirname "$dest")"
    cp -f "$LIB_DIR/libnez_emu.so" "$dest"
    rm -f "$LIB_DIR/libnez_emu.so" "$LIB_DIR/libnez_emu.so.o"
    ok "Copied .so → Avalonia lib/arm64-v8a/"
}

# ---- Commands ----

cmd_flutter() {
    check_tools; command -v flutter >/dev/null 2>&1 || fail "flutter not found"
    build_lib
    info "Running Flutter macOS..."
    cd "$FLUTTER_DIR" && flutter pub get
    flutter build macos --debug
    copy_dylib_flutter
    flutter run -d macos
}

cmd_avalonia() {
    check_tools; command -v dotnet >/dev/null 2>&1 || fail "dotnet not found"
    build_lib; copy_dylib_avalonia
    info "Running Avalonia macOS..."
    cd "$AVALONIA_DIR" && dotnet run -f net10.0
}

cmd_android() {
    check_tools; command -v flutter >/dev/null 2>&1 || fail "flutter not found"
    build_android_so; copy_so_flutter
    cd "$FLUTTER_DIR" && flutter pub get && flutter run -d android
}

cmd_android_avalonia() {
    check_tools; command -v dotnet >/dev/null 2>&1 || fail "dotnet not found"
    build_android_so; copy_so_avalonia
    info "Running Avalonia Android..."
    cd "$AVALONIA_DIR" && dotnet run -f net10.0-android
}

cmd_apk() {
    local mode="${1:-debug}"
    check_tools; command -v flutter >/dev/null 2>&1 || fail "flutter not found"
    build_android_so; copy_so_flutter
    info "Building Flutter APK ($mode)..."
    cd "$FLUTTER_DIR" && flutter pub get && flutter build apk --"$mode"
    local apk="$FLUTTER_DIR/build/app/outputs/flutter-apk/app-$mode.apk"
    mkdir -p "$OUT_DIR"
    cp -f "$apk" "$OUT_DIR/nez-flutter-$mode.apk"
    ok "Flutter APK: $OUT_DIR/nez-flutter-$mode.apk ($(du -h "$apk" | awk '{print $1}'))"
}

cmd_apk_avalonia() {
    local mode="${1:-debug}"
    check_tools; command -v dotnet >/dev/null 2>&1 || fail "dotnet not found"
    build_android_so; copy_so_avalonia
    info "Building Avalonia APK ($mode)..."
    cd "$AVALONIA_DIR"
    if [ "$mode" = "release" ]; then
        dotnet publish -f net10.0-android -c Release
        local apk="$AVALONIA_DIR/bin/Release/net10.0-android/publish/com.nez.nez_avalonia-Signed.apk"
    else
        dotnet publish -f net10.0-android -c Debug
        local apk="$AVALONIA_DIR/bin/Debug/net10.0-android/publish/com.nez.nez_avalonia-Signed.apk"
    fi
    if [ -f "$apk" ]; then
        mkdir -p "$OUT_DIR"
        cp -f "$apk" "$OUT_DIR/nez-avalonia-$mode.apk"
        ok "Avalonia APK: $OUT_DIR/nez-avalonia-$mode.apk ($(du -h "$apk" | awk '{print $1}'))"
    else
        fail "APK not found"
    fi
}

cmd_clean() {
    info "Cleaning..."
    (cd "$LIB_DIR" && rm -rf zig-out .zig-cache libnez_emu.*)
    (cd "$FLUTTER_DIR" && flutter clean 2>/dev/null || true)
    (cd "$AVALONIA_DIR" && dotnet clean 2>/dev/null && rm -f libnez_emu.* || true)
    rm -rf "$FLUTTER_DIR/android/app/src/main/jniLibs"
    rm -rf "$AVALONIA_DIR/lib/arm64-v8a"
    rm -rf "$OUT_DIR"
    ok "Done"
}

cmd_dmg() {
    local mode="${1:-release}"
    check_tools; command -v flutter >/dev/null 2>&1 || fail "flutter not found"
    build_lib
    info "Building Flutter macOS app ($mode)..."
    cd "$FLUTTER_DIR" && flutter pub get
    flutter build macos --"$mode"
    copy_dylib_flutter

    local app_src="$FLUTTER_DIR/build/macos/Build/Products"
    local app=""
    if [ "$mode" = "release" ]; then
        app="$(find "$app_src/Release" -name '*.app' -maxdepth 1 2>/dev/null | head -1)"
    else
        app="$(find "$app_src/Debug" -name '*.app' -maxdepth 1 2>/dev/null | head -1)"
    fi
    [ -z "$app" ] && fail "macOS .app not found"

    mkdir -p "$OUT_DIR"
    local dest="$OUT_DIR/Nez.app"
    rm -rf "$dest"
    cp -R "$app" "$dest"
    # Copy dylib into the app bundle
    local dylib="$ZIG_OUT/libnez_emu.dylib"
    [ -f "$dylib" ] && cp -f "$dylib" "$dest/Contents/MacOS/" && codesign --force --sign - "$dest/Contents/MacOS/libnez_emu.dylib" 2>/dev/null || true
    ok "macOS app: $OUT_DIR/Nez.app"

    # Create DMG if hdiutil available
    if command -v hdiutil >/dev/null 2>&1; then
        info "Creating DMG..."
        local dmg="$OUT_DIR/Nez.dmg"
        rm -f "$dmg"
        hdiutil create -volname "Nez" -srcfolder "$dest" -ov -format UDZO "$dmg" 2>/dev/null
        [ -f "$dmg" ] && ok "DMG: $dmg ($(du -h "$dmg" | awk '{print $1}'))"
    fi
}

cmd_publish_avalonia() {
    local mode="${1:-release}"
    check_tools; command -v dotnet >/dev/null 2>&1 || fail "dotnet not found"
    build_lib; copy_dylib_avalonia
    info "Building Avalonia macOS ($mode)..."
    cd "$AVALONIA_DIR"
    local config="Release"
    [ "$mode" = "debug" ] && config="Debug"
    # NativeAOT needs OpenSSL and brotli from homebrew
    export LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:/opt/homebrew/opt/brotli/lib:/opt/homebrew/lib:${LIBRARY_PATH:-}"
    dotnet publish -f net10.0 -c "$config"
    local pub_dir="$AVALONIA_DIR/bin/$config/net10.0/osx-arm64/publish"
    [ -d "$pub_dir" ] || fail "Publish dir not found: $pub_dir"

    # Build .app bundle
    local app_dir="$OUT_DIR/Nez-Avalonia.app/Contents"
    rm -rf "$OUT_DIR/Nez-Avalonia.app"
    mkdir -p "$app_dir/MacOS" "$app_dir/Resources"
    cp -R "$pub_dir/"* "$app_dir/MacOS/"
    local dylib="$ZIG_OUT/libnez_emu.dylib"
    [ -f "$dylib" ] && cp -f "$dylib" "$app_dir/MacOS/"

    # Create Info.plist
    cat > "$app_dir/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Nez</string>
    <key>CFBundleDisplayName</key><string>Nez NES Emulator</string>
    <key>CFBundleIdentifier</key><string>com.nez.avalonia</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>NezAvalonia</string>
    <key>LSMinimumSystemVersion</key><string>12.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
    ok "Avalonia app: $OUT_DIR/Nez-Avalonia.app"

    # Create DMG
    if command -v hdiutil >/dev/null 2>&1; then
        info "Creating DMG..."
        local dmg="$OUT_DIR/Nez-Avalonia.dmg"
        rm -f "$dmg"
        hdiutil create -volname "Nez-Avalonia" -srcfolder "$OUT_DIR/Nez-Avalonia.app" -ov -format UDZO "$dmg" 2>/dev/null
        [ -f "$dmg" ] && ok "DMG: $dmg ($(du -h "$dmg" | awk '{print $1}'))"
    fi
}

cmd_exe() {
    check_tools; command -v flutter >/dev/null 2>&1 || fail "flutter not found"
    build_lib
    info "Building Flutter Windows EXE..."
    cd "$FLUTTER_DIR" && flutter pub get
    flutter build windows --release
    local exe_dir="$FLUTTER_DIR/build/windows/x64/runner/Release"
    [ -d "$exe_dir" ] || fail "Flutter Windows build dir not found. This command must run on Windows."
    mkdir -p "$OUT_DIR/nez-flutter-windows"
    cp -R "$exe_dir/"* "$OUT_DIR/nez-flutter-windows/"
    local dylib="$ZIG_OUT/nez_emu.dll"
    [ -f "$dylib" ] && cp -f "$dylib" "$OUT_DIR/nez-flutter-windows/"
    ok "Flutter Windows EXE: $OUT_DIR/nez-flutter-windows/"
}

cmd_exe_avalonia() {
    check_tools; command -v dotnet >/dev/null 2>&1 || fail "dotnet not found"

    info "Cross-compiling Zig for Windows x86_64..."
    cd "$LIB_DIR"
    zig build-lib src/ffi.zig -OReleaseFast -target x86_64-windows -lc -dynamic --name nez_emu
    ok "nez_emu.dll compiled"

    info "Copying nez_emu.dll → Avalonia project..."
    cp -f "$LIB_DIR/nez_emu.dll" "$AVALONIA_DIR/"
    ok "Copied nez_emu.dll"

    info "Publishing Avalonia for Windows x64..."
    cd "$AVALONIA_DIR"
    dotnet publish -f net10.0 -c Release -r win-x64 --self-contained true -p:PublishAot=false -p:PublishTrimmed=true -p:TrimMode=partial -p:UseMonoRuntime=false
    local pub_dir="$AVALONIA_DIR/bin/Release/net10.0/win-x64/publish"
    [ -d "$pub_dir" ] || fail "Publish dir not found: $pub_dir"

    local dest="$OUT_DIR/nez-windows"
    rm -rf "$dest"
    mkdir -p "$dest"
    cp -R "$pub_dir/"* "$dest/"
    cp -f "$LIB_DIR/nez_emu.dll" "$dest/"
    ok "Windows EXE: $dest/"

    # Clean up cross-compile artifacts
    rm -f "$LIB_DIR/nez_emu.dll" "$LIB_DIR/nez_emu.dll.o" "$LIB_DIR/nez_emu.lib" "$LIB_DIR/nez_emu.pdb"
}

# ---- ROM exclusion ----
NO_ROM=false
ROM_TMP=""

exclude_roms() {
    local rom_dir="$FLUTTER_DIR/roms"
    ROM_TMP=$(mktemp -d)
    local count=0
    for f in "$rom_dir"/*.nes "$rom_dir"/*.NES; do
        [ -f "$f" ] || continue
        mv "$f" "$ROM_TMP/"
        count=$((count + 1))
    done
    [ "$count" -gt 0 ] && info "Excluded $count ROM(s) from build → $ROM_TMP"
}

restore_roms() {
    if [ -n "$ROM_TMP" ] && [ -d "$ROM_TMP" ]; then
        local rom_dir="$FLUTTER_DIR/roms"
        for f in "$ROM_TMP"/*.nes "$ROM_TMP"/*.NES; do
            [ -f "$f" ] || continue
            mv "$f" "$rom_dir/"
        done
        rmdir "$ROM_TMP" 2>/dev/null
        ROM_TMP=""
        info "ROMs restored"
    fi
}

# Ensure ROMs are restored on exit
trap restore_roms EXIT

# ---- Main ----
RELEASE=false; NO_ROM=false; CMD=""
for arg in "$@"; do
    case "$arg" in --release) RELEASE=true ;; --no-rom) NO_ROM=true ;; -h|--help) usage; exit 0 ;; *) CMD="$arg" ;; esac
done
MODE="debug"; $RELEASE && MODE="release"
$NO_ROM && exclude_roms

case "${CMD:-flutter}" in
    flutter)           cmd_flutter ;;
    avalonia)          cmd_avalonia ;;
    android)           cmd_android ;;
    android-avalonia)  cmd_android_avalonia ;;
    apk)               cmd_apk "$MODE" ;;
    apk-avalonia)      cmd_apk_avalonia "$MODE" ;;
    dmg)               cmd_dmg "$MODE" ;;
    dmg-avalonia)      cmd_publish_avalonia "$MODE" ;;
    exe)               cmd_exe ;;
    exe-avalonia)      cmd_exe_avalonia ;;
    all)
        info "Building ALL targets → out/"
        cmd_apk "$MODE"
        cmd_apk_avalonia "$MODE"
        cmd_dmg "$MODE"
        cmd_publish_avalonia "$MODE"
        cmd_exe_avalonia
        echo ""
        info "All builds complete. Output:"
        ls -lh "$OUT_DIR"/ 2>/dev/null
        ;;
    lib)               check_tools; build_lib ;;
    clean)             cmd_clean ;;
    check)             check_tools ;;
    *)                 usage; exit 1 ;;
esac
