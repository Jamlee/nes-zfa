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

  flutter         Build lib + run Flutter macOS app
  avalonia        Build lib + run Avalonia macOS app
  android         Build lib + run Flutter on Android
  apk             Build Android APK
  lib             Build Zig shared library only
  clean           Clean all build artifacts
  check           Check toolchain versions

Examples:
  ./build.sh flutter
  ./build.sh avalonia
  ./build.sh apk --release
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
    local so="$FLUTTER_DIR/android/app/src/main/jniLibs/arm64-v8a/libnez_emu.so"
    [ -f "$so" ] && [ "$so" -nt "$LIB_DIR/src/ffi.zig" ] && return

    info "Cross-compiling for Android arm64..."
    cd "$LIB_DIR"
    local ndk=""
    [ -n "$ANDROID_NDK_HOME" ] && ndk="$ANDROID_NDK_HOME" || \
        for d in ~/Library/Android/sdk/ndk/*/; do ndk="${d%/}"; done
    [ -z "$ndk" ] && fail "Android NDK not found"
    local sysroot="$ndk/toolchains/llvm/prebuilt/darwin-x86_64/sysroot"
    [ -d "$sysroot" ] || sysroot="$ndk/toolchains/llvm/prebuilt/linux-x86_64/sysroot"

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
    mkdir -p "$(dirname "$so")"
    mv libnez_emu.so "$so"; rm -f libnez_emu.so.o
    ok "Android .so ready"
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
    cd "$AVALONIA_DIR" && dotnet run
}

cmd_android() {
    check_tools; command -v flutter >/dev/null 2>&1 || fail "flutter not found"
    build_android_so
    cd "$FLUTTER_DIR" && flutter pub get && flutter run -d android
}

cmd_apk() {
    local mode="${1:-debug}"
    check_tools; command -v flutter >/dev/null 2>&1 || fail "flutter not found"
    build_android_so
    cd "$FLUTTER_DIR" && flutter pub get && flutter build apk --"$mode"
    ok "APK: $FLUTTER_DIR/build/app/outputs/flutter-apk/app-$mode.apk"
}

cmd_clean() {
    info "Cleaning..."
    (cd "$LIB_DIR" && rm -rf zig-out .zig-cache libnez_emu.*)
    (cd "$FLUTTER_DIR" && flutter clean 2>/dev/null || true)
    (cd "$AVALONIA_DIR" && dotnet clean 2>/dev/null && rm -f libnez_emu.* || true)
    rm -rf "$FLUTTER_DIR/android/app/src/main/jniLibs"
    ok "Done"
}

# ---- Main ----
RELEASE=false; CMD=""
for arg in "$@"; do
    case "$arg" in --release) RELEASE=true ;; -h|--help) usage; exit 0 ;; *) CMD="$arg" ;; esac
done
MODE="debug"; $RELEASE && MODE="release"

case "${CMD:-flutter}" in
    flutter)   cmd_flutter ;;
    avalonia)  cmd_avalonia ;;
    android)   cmd_android ;;
    apk)       cmd_apk "$MODE" ;;
    lib)       check_tools; build_lib ;;
    clean)     cmd_clean ;;
    check)     check_tools ;;
    *)         usage; exit 1 ;;
esac
