#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
FLUTTER_DIR="$SCRIPT_DIR/flutter"
AVALONIA_DIR="$SCRIPT_DIR/avalonia/NezAvalonia"
ZIG_OUT="$LIB_DIR/zig-out/lib"

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
fail()  { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

usage() {
    cat <<'USAGE'
Nez — NES Emulator

Usage: ./build.sh <command> [--release]

  flutter             Build lib + run Flutter macOS app
  avalonia            Build lib + run Avalonia macOS app
  android             Build lib + run Flutter on Android
  android-avalonia    Build lib + run Avalonia on Android
  apk                 Build Flutter Android APK
  apk-avalonia        Build Avalonia Android APK
  lib                 Build Zig shared library only
  clean               Clean all build artifacts
  check               Check toolchain versions

Examples:
  ./build.sh flutter
  ./build.sh avalonia
  ./build.sh apk --release
  ./build.sh apk-avalonia --release
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
    ok "Flutter APK: $apk ($(du -h "$apk" | awk '{print $1}'))"
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
    [ -f "$apk" ] && ok "Avalonia APK: $apk ($(du -h "$apk" | awk '{print $1}'))" || fail "APK not found"
}

cmd_clean() {
    info "Cleaning..."
    (cd "$LIB_DIR" && rm -rf zig-out .zig-cache libnez_emu.*)
    (cd "$FLUTTER_DIR" && flutter clean 2>/dev/null || true)
    (cd "$AVALONIA_DIR" && dotnet clean 2>/dev/null && rm -f libnez_emu.* || true)
    rm -rf "$FLUTTER_DIR/android/app/src/main/jniLibs"
    rm -rf "$AVALONIA_DIR/lib/arm64-v8a"
    ok "Done"
}

# ---- Main ----
RELEASE=false; CMD=""
for arg in "$@"; do
    case "$arg" in --release) RELEASE=true ;; -h|--help) usage; exit 0 ;; *) CMD="$arg" ;; esac
done
MODE="debug"; $RELEASE && MODE="release"

case "${CMD:-flutter}" in
    flutter)           cmd_flutter ;;
    avalonia)          cmd_avalonia ;;
    android)           cmd_android ;;
    android-avalonia)  cmd_android_avalonia ;;
    apk)               cmd_apk "$MODE" ;;
    apk-avalonia)      cmd_apk_avalonia "$MODE" ;;
    lib)               check_tools; build_lib ;;
    clean)             cmd_clean ;;
    check)             check_tools ;;
    *)                 usage; exit 1 ;;
esac
