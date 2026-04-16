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

# Generate app icons from docs/icon.svg (if script exists)
generate_icons() {
    if [ -f "$SCRIPT_DIR/scripts/generate_icons.sh" ]; then
        info "Syncing icons from docs/icon.svg..."
        bash "$SCRIPT_DIR/scripts/generate_icons.sh" 2>/dev/null || true
    fi
}

usage() {
    cat <<'USAGE'
Nez — NES Emulator

Usage: ./build.sh <command> [--release]

  Platform targets (run / dev):
    macos               Build lib + run Flutter macOS app
    macos-avalonia      Build lib + run Avalonia macOS app
    android             Build lib + run Flutter on Android
    android-avalonia    Build lib + run Avalonia on Android
    web                 Build wasm + serve Flutter web (dev)
    web-avalonia        Build wasm + serve Avalonia Browser (dev)

  Release builds → out/:
    apk                 Flutter Android APK
    apk-avalonia        Avalonia Android APK
    dmg                 Flutter macOS DMG
    dmg-avalonia        Avalonia macOS DMG
    web-flutter         Flutter web release (zip)
    web-avalonia        Avalonia Browser release (zip)
    exe-avalonia        Avalonia Windows ZIP (cross-compile)

  Utilities:
    wasm                Build Zig → nez_emu.wasm only
    lib                 Build Zig shared library only
    all                 Build all: apk + apk-avalonia + dmg + dmg-avalonia + exe-avalonia
    clean               Clean all build artifacts
    check               Check toolchain versions

Examples:
  ./build.sh macos
  ./build.sh web
  ./build.sh apk --release
  ./build.sh apk-avalonia --release
  ./build.sh exe-avalonia
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

build_wasm() {
    info "Building nez_emu.wasm..."
    cd "$LIB_DIR"
    zig build wasm -Doptimize=ReleaseSmall
    ok "nez_emu.wasm ($(du -h "$LIB_DIR"/zig-out/bin/nez_emu.wasm 2>/dev/null | awk '{print $1}'))"
}

copy_wasm_flutter() {
    local wasm="$LIB_DIR/zig-out/bin/nez_emu.wasm"
    [ -f "$wasm" ] || fail "nez_emu.wasm not found"
    mkdir -p "$FLUTTER_DIR/web"
    cp -f "$wasm" "$FLUTTER_DIR/web/nez_emu.wasm"
    ok "Copied .wasm → Flutter web/"
}

copy_wasm_avalonia() {
    local wasm="$LIB_DIR/zig-out/bin/nez_emu.wasm"
    [ -f "$wasm" ] || fail "nez_emu.wasm not found"
    mkdir -p "$AVALONIA_DIR/NezAvalonia.Browser/wwwroot"
    cp -f "$wasm" "$AVALONIA_DIR/NezAvalonia.Browser/wwwroot/nez_emu.wasm"
    ok "Copied .wasm → Avalonia Browser wwwroot/"
}

# Copy ROMs into target roms dir (for Flutter assets / Avalonia embedded resources)
copy_roms() {
    local dest="$1"
    mkdir -p "$dest"
    local src="$SCRIPT_DIR/roms"
    if [ -d "$src" ] && [ "$(ls -A "$src" 2>/dev/null)" ]; then
        cp -f "$src/"*.nes "$dest/" 2>/dev/null || true
        ok "Copied ROMs → $dest/"
    fi
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
    build_lib; copy_roms "$FLUTTER_DIR/roms"
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
    build_android_so; copy_so_flutter; copy_roms "$FLUTTER_DIR/roms"
    cd "$FLUTTER_DIR" && flutter pub get && flutter run -d android
}

cmd_android_avalonia() {
    check_tools; command -v dotnet >/dev/null 2>&1 || fail "dotnet not found"
    build_android_so; copy_so_avalonia
    info "Running Avalonia Android..."
    cd "$AVALONIA_DIR" && dotnet run -f net10.0-android
}

cmd_flutter_web() {
    check_tools; command -v flutter >/dev/null 2>&1 || fail "flutter not found"
    build_wasm; copy_wasm_flutter; copy_roms "$FLUTTER_DIR/roms"
    info "Serving Flutter web..."
    cd "$FLUTTER_DIR" && flutter pub get && flutter run -d chrome
}

cmd_avalonia_web() {
    check_tools; command -v dotnet >/dev/null 2>&1 || fail "dotnet not found"
    build_wasm; copy_wasm_avalonia
    info "Building Avalonia Browser (WASM)..."
    cd "$AVALONIA_DIR/NezAvalonia.Browser"
    dotnet publish -f net10.0-browser -c Debug
    local pub_dir="$AVALONIA_DIR/NezAvalonia.Browser/bin/Debug/net10.0-browser/osx-arm64/publish/wwwroot"
    local pub_root="$AVALONIA_DIR/NezAvalonia.Browser/bin/Debug/net10.0-browser/osx-arm64/publish"
    [ -d "$pub_root" ] || fail "Avalonia Browser publish dir not found"

    mkdir -p "$OUT_DIR"
    if command -v zip >/dev/null 2>&1; then
        info "Packaging ZIP..."
        local tmp_dir="$OUT_DIR/nez-web-avalonia"
        rm -rf "$tmp_dir"
        mkdir -p "$tmp_dir"
        cp -R "$pub_root/"* "$tmp_dir/"
        (cd "$OUT_DIR" && zip -r -q "nez-web-avalonia.zip" "nez-web-avalonia" && rm -rf "nez-web-avalonia")
        [ -f "$OUT_DIR/nez-web-avalonia.zip" ] && ok "ZIP: $OUT_DIR/nez-web-avalonia.zip ($(du -h "$OUT_DIR/nez-web-avalonia.zip" | awk '{print $1}'))"
        info "Serve with: cd '$OUT_DIR' && python3 -m http.server 8080 && open http://localhost:8080"
    else
        local dest="$OUT_DIR/nez-web-avalonia"
        rm -rf "$dest"
        mkdir -p "$dest"
        cp -R "$pub_root/"* "$dest/"
        ok "Avalonia web: $dest/"
    fi
}

cmd_wasm() {
    check_tools; build_wasm
    info "WASM output: $ZIG_OUT/libnez_emu.wasm"
}

cmd_apk() {
    local mode="${1:-debug}"
    check_tools; command -v flutter >/dev/null 2>&1 || fail "flutter not found"
    build_android_so; copy_so_flutter; copy_roms "$FLUTTER_DIR/roms"
    info "Building Flutter APK ($mode)..."
    cd "$FLUTTER_DIR" && flutter pub get && flutter build apk --"$mode"
    local apk="$FLUTTER_DIR/build/app/outputs/flutter-apk/app-$mode.apk"
    mkdir -p "$OUT_DIR"
    cp -f "$apk" "$OUT_DIR/nez-android-flutter.apk"
    ok "Flutter APK: $OUT_DIR/nez-android-flutter.apk ($(du -h "$apk" | awk '{print $1}'))"
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
        cp -f "$apk" "$OUT_DIR/nez-android-avalonia.apk"
        ok "Avalonia APK: $OUT_DIR/nez-android-avalonia.apk ($(du -h "$apk" | awk '{print $1}'))"
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
    build_lib; copy_roms "$FLUTTER_DIR/roms"
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
    local dest="$OUT_DIR/nez-macos-flutter.app"
    rm -rf "$dest"
    cp -R "$app" "$dest"
    # Copy dylib into the app bundle
    local dylib="$ZIG_OUT/libnez_emu.dylib"
    [ -f "$dylib" ] && cp -f "$dylib" "$dest/Contents/MacOS/" && codesign --force --sign - "$dest/Contents/MacOS/libnez_emu.dylib" 2>/dev/null || true
    ok "macOS app: $OUT_DIR/nez-macos-flutter.app"

    # Create DMG if hdiutil available
    if command -v hdiutil >/dev/null 2>&1; then
        info "Creating DMG..."
        local dmg="$OUT_DIR/nez-macos-flutter.dmg"
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
    local app_dir="$OUT_DIR/nez-macos-avalonia.app/Contents"
    rm -rf "$OUT_DIR/nez-macos-avalonia.app"
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
    <key>CFBundleIconFile</key><string>nez</string>
    <key>LSMinimumSystemVersion</key><string>12.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
    # Copy app icon
    local icon="$AVALONIA_DIR/Assets/nez.icns"
    [ -f "$icon" ] && cp -f "$icon" "$app_dir/Resources/nez.icns"
    ok "Avalonia app: $OUT_DIR/nez-macos-avalonia.app"

    # Create DMG
    if command -v hdiutil >/dev/null 2>&1; then
        info "Creating DMG..."
        local dmg="$OUT_DIR/nez-macos-avalonia.dmg"
        rm -f "$dmg"
        hdiutil create -volname "Nez-Avalonia" -srcfolder "$OUT_DIR/nez-macos-avalonia.app" -ov -format UDZO "$dmg" 2>/dev/null
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
    mkdir -p "$OUT_DIR/nez-windows-flutter"
    cp -R "$exe_dir/"* "$OUT_DIR/nez-windows-flutter/"
    local dylib="$ZIG_OUT/nez_emu.dll"
    [ -f "$dylib" ] && cp -f "$dylib" "$OUT_DIR/nez-windows-flutter/"
    ok "Flutter Windows EXE: $OUT_DIR/nez-windows-flutter/"
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

    local dest="$OUT_DIR/nez-windows-avalonia"
    rm -rf "$dest"
    mkdir -p "$dest"
    cp -R "$pub_dir/"* "$dest/"
    cp -f "$LIB_DIR/nez_emu.dll" "$dest/"
    ok "Windows EXE: $dest/"

    # Package as zip
    if command -v zip >/dev/null 2>&1; then
        info "Packaging ZIP..."
        (cd "$OUT_DIR" && zip -r -q "nez-windows-avalonia.zip" "nez-windows-avalonia" && rm -rf "nez-windows-avalonia")
        [ -f "$OUT_DIR/nez-windows-avalonia.zip" ] && ok "ZIP: $OUT_DIR/nez-windows-avalonia.zip ($(du -h "$OUT_DIR/nez-windows-avalonia.zip" | awk '{print $1}'))"
    fi

    # Clean up cross-compile artifacts
    rm -f "$LIB_DIR/nez_emu.dll" "$LIB_DIR/nez_emu.dll.o" "$LIB_DIR/nez_emu.lib" "$LIB_DIR/nez_emu.pdb"
}

cmd_web_flutter() {
    check_tools; command -v flutter >/dev/null 2>&1 || fail "flutter not found"
    build_wasm; copy_wasm_flutter; copy_roms "$FLUTTER_DIR/roms"
    info "Building Flutter web release..."
    cd "$FLUTTER_DIR" && flutter pub get && flutter build web --release
    local web_dir="$FLUTTER_DIR/build/web"
    [ -d "$web_dir" ] || fail "Flutter web build dir not found"

    mkdir -p "$OUT_DIR"
    if command -v zip >/dev/null 2>&1; then
        info "Packaging ZIP..."
        local tmp_dir="$OUT_DIR/nez-web-flutter"
        rm -rf "$tmp_dir"
        cp -R "$web_dir" "$tmp_dir"
        (cd "$OUT_DIR" && zip -r -q "nez-web-flutter.zip" "nez-web-flutter" && rm -rf "nez-web-flutter")
        [ -f "$OUT_DIR/nez-web-flutter.zip" ] && ok "ZIP: $OUT_DIR/nez-web-flutter.zip ($(du -h "$OUT_DIR/nez-web-flutter.zip" | awk '{print $1}'))"
    else
        local dest="$OUT_DIR/nez-web-flutter"
        rm -rf "$dest"
        cp -R "$web_dir" "$dest"
        ok "Flutter web: $dest/"
    fi
}

cmd_web_avalonia() {
    check_tools; command -v dotnet >/dev/null 2>&1 || fail "dotnet not found"
    build_wasm; copy_wasm_avalonia
    info "Publishing Avalonia Browser (WASM)..."
    cd "$AVALONIA_DIR/NezAvalonia.Browser"
    dotnet publish -c Release
    local pub_dir="$AVALONIA_DIR/NezAvalonia.Browser/bin/Release/net10.0-browser/osx-arm64/publish/wwwroot"
    [ -d "$pub_dir" ] || fail "Avalonia Browser publish dir not found"

    # Include the index.html and framework files
    local pub_root="$AVALONIA_DIR/NezAvalonia.Browser/bin/Release/net10.0-browser/osx-arm64/publish"
    [ -d "$pub_root" ] || fail "Avalonia Browser publish root not found"

    mkdir -p "$OUT_DIR"
    if command -v zip >/dev/null 2>&1; then
        info "Packaging ZIP..."
        local tmp_dir="$OUT_DIR/nez-web-avalonia"
        rm -rf "$tmp_dir"
        mkdir -p "$tmp_dir"
        cp -R "$pub_root/"* "$tmp_dir/"
        (cd "$OUT_DIR" && zip -r -q "nez-web-avalonia.zip" "nez-web-avalonia" && rm -rf "nez-web-avalonia")
        [ -f "$OUT_DIR/nez-web-avalonia.zip" ] && ok "ZIP: $OUT_DIR/nez-web-avalonia.zip ($(du -h "$OUT_DIR/nez-web-avalonia.zip" | awk '{print $1}'))"
    else
        local dest="$OUT_DIR/nez-web-avalonia"
        rm -rf "$dest"
        cp -R "$pub_root/"* "$dest/"
        ok "Avalonia web: $dest/"
    fi
}

# ---- Main ----
RELEASE=false; CMD=""
for arg in "$@"; do
    case "$arg" in --release) RELEASE=true ;; -h|--help) usage; exit 0 ;; *) CMD="$arg" ;; esac
done
MODE="debug"; $RELEASE && MODE="release"

case "${CMD:-macos}" in
    macos)             cmd_flutter ;;
    macos-avalonia)    cmd_avalonia ;;
    android)           cmd_android ;;
    android-avalonia)  cmd_android_avalonia ;;
    web)               cmd_flutter_web ;;
    web-avalonia)      cmd_avalonia_web ;;
    web-flutter)       cmd_web_flutter ;;
    web-avalonia)      cmd_web_avalonia ;;
    wasm)              cmd_wasm ;;
    apk)               cmd_apk "$MODE" ;;
    apk-avalonia)      cmd_apk_avalonia "$MODE" ;;
    dmg)               cmd_dmg "$MODE" ;;
    dmg-avalonia)      cmd_publish_avalonia "$MODE" ;;
    exe)               cmd_exe ;;
    exe-avalonia)      cmd_exe_avalonia ;;
    all)
        info "Building ALL targets → out/"
        generate_icons
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
