#!/bin/bash
set -e

# Generate all app icons from docs/icon.svg
# Requires: rsvg-convert (librsvg), magick (ImageMagick)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR"/.. && pwd)"
SVG="$SCRIPT_DIR/icon.svg"
FLUTTER="$ROOT_DIR/flutter"
AVALONIA="$ROOT_DIR/avalonia/NezAvalonia"

[ -f "$SVG" ] || { echo "ERROR: $SVG not found"; exit 1; }

info() { echo -e "\033[0;36m[ICON]\033[0m $1"; }

# Helper: SVG → PNG at given size
svg2png() {
    local size="$1" out="$2"
    rsvg-convert -w "$size" -h "$size" -f png "$SVG" -o "$out"
}

# ============================================================
# 1. Flutter macOS AppIcon (all required sizes)
# ============================================================
info "Generating Flutter macOS icons..."
MACON_DIR="$FLUTTER/macos/Runner/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$MACON_DIR"
for s in 16 32 64 128 256 512 1024; do
    svg2png "$s" "$MACON_DIR/app_icon_${s}.png"
done
info "  → macOS icons done"

# ============================================================
# 2. Flutter Android mipmap icons
# ============================================================
info "Generating Flutter Android icons..."
declare -A DPI_SIZES=(
    ["mdpi"]=48
    ["hdpi"]=72
    ["xhdpi"]=96
    ["xxhdpi"]=144
    ["xxxhdpi"]=192
)
for dpi in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
    size="${DPI_SIZES[$dpi]}"
    dir="$FLUTTER/android/app/src/main/res/mipmap-$dpi"
    mkdir -p "$dir"
    svg2png "$size" "$dir/ic_launcher.png"
done
info "  → Android mipmap icons done"

# ============================================================
# 3. Flutter Web PWA icons
# ============================================================
info "Generating Flutter web icons..."
WEB_ICONS="$FLUTTER/web/icons"
mkdir -p "$WEB_ICONS"
svg2png 192 "$WEB_ICONS/Icon-192.png"
svg2png 512 "$WEB_ICONS/Icon-512.png"

# Maskable icons (with padding for safe area)
# PWA maskable icons need more padding — generate with rsvg-convert using viewBox offset
# Create a padded version: scale inner content to 75% centered
PADDED_SVG="/tmp/nez-icon-padded.svg"
# Use sed to strip the outer <svg> and </svg>, wrap in a padded container
cat > "$PADDED_SVG" <<SVGHEADER
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <svg x="128" y="128" width="768" height="768" viewBox="0 0 1024 1024">
SVGHEADER
# Extract inner content: everything between the opening svg tag and closing svg tag
sed -n '/^<svg/,/<\/svg>/p' "$SVG" | sed '1d;$d' >> "$PADDED_SVG"
echo "  </svg>" >> "$PADDED_SVG"
echo "</svg>" >> "$PADDED_SVG"

rsvg-convert -w 192 -h 192 -f png "$PADDED_SVG" -o "$WEB_ICONS/Icon-maskable-192.png"
rsvg-convert -w 512 -h 512 -f png "$PADDED_SVG" -o "$WEB_ICONS/Icon-maskable-512.png"

# Favicon
svg2png 32 "$FLUTTER/web/favicon.png"
info "  → Web PWA icons done"

# ============================================================
# 4. Avalonia Android icon (vector drawable from SVG)
# ============================================================
info "Generating Avalonia Android icon..."
AV_DRAWABLE="$AVALONIA/Resources/drawable"
mkdir -p "$AV_DRAWABLE"
# Convert SVG to Android vector drawable
# For simplicity, generate a PNG at 512x512 and reference it
# Actually, Avalonia Android uses the same mipmap pattern — let's create them
for dpi in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
    size="${DPI_SIZES[$dpi]}"
    dir="$AVALONIA/Resources/mipmap-$dpi"
    mkdir -p "$dir"
    svg2png "$size" "$dir/ic_launcher.png"
done
# Also update the vector drawable to match the icon design
cat > "$AV_DRAWABLE/icon.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="48dp"
    android:height="48dp"
    android:viewportWidth="1024"
    android:viewportHeight="1024">
    <!-- Background -->
    <path
        android:fillColor="#f8fafc"
        android:pathData="M180,0L844,0A180,180,0,0,1,1024,180L1024,844A180,180,0,0,1,844,1024L180,1024A180,180,0,0,1,0,844L0,180A180,180,0,0,1,180,0z"/>
    <!-- Controller body -->
    <path
        android:fillColor="#e2e8f0"
        android:pathData="M272,220 C280,230 392,210 520,210 C648,210 760,230 752,260 L780,300 C812,335 812,385 807,425 L802,640 C799,725 750,765 687,805 L637,838 C590,870 547,828 500,762 L460,710 C432,672 392,672 364,710 L324,762 C277,828 234,870 187,838 L137,805 C74,765 64,698 130,640 L125,425 C120,385 120,335 160,300 Z"/>
    <!-- D-Pad vertical -->
    <path
        android:fillColor="#cbd5e1"
        android:pathData="M272,238 L304,238 C308,238 312,242 312,246 L312,330 C312,334 308,338 304,338 L272,338 C268,338 264,334 264,330 L264,246 C264,242 268,238 272,238 Z"/>
    <!-- D-Pad horizontal -->
    <path
        android:fillColor="#cbd5e1"
        android:pathData="M248,274 L328,274 C332,274 336,278 336,282 L336,298 C336,302 332,306 328,306 L248,306 C244,306 240,302 240,298 L240,282 C240,278 244,274 248,274 Z"/>
    <!-- A Button -->
    <path
        android:fillColor="#fca5a5"
        android:pathData="M660,299 A37,37,0,1,1,660,373 A37,37,0,1,1,660,299 Z"/>
    <!-- B Button -->
    <path
        android:fillColor="#fca5a5"
        android:pathData="M588,329 A37,37,0,1,1,588,403 A37,37,0,1,1,588,329 Z"/>
</vector>
XMLEOF
info "  → Avalonia Android icons done"

# ============================================================
# 5. Avalonia macOS .app icon (icns)
# ============================================================
info "Generating Avalonia macOS icon..."
ICNS_DIR="/tmp/nez-icon.iconset"
rm -rf "$ICNS_DIR"
mkdir -p "$ICNS_DIR"
svg2png 16 "$ICNS_DIR/icon_16x16.png"
svg2png 32 "$ICNS_DIR/icon_16x16@2x.png"
svg2png 32 "$ICNS_DIR/icon_32x32.png"
svg2png 64 "$ICNS_DIR/icon_32x32@2x.png"
svg2png 128 "$ICNS_DIR/icon_128x128.png"
svg2png 256 "$ICNS_DIR/icon_128x128@2x.png"
svg2png 256 "$ICNS_DIR/icon_256x256.png"
svg2png 512 "$ICNS_DIR/icon_256x256@2x.png"
svg2png 512 "$ICNS_DIR/icon_512x512.png"
svg2png 1024 "$ICNS_DIR/icon_512x512@2x.png"

ICNS_OUT="$AVALONIA/Assets/nez.icns"
iconutil -c icns "$ICNS_DIR" -o "$ICNS_OUT" 2>/dev/null || {
    # Fallback: use ImageMagick if iconutil fails
    magick "$ICNS_DIR"/icon_512x512@2x.png "$ICNS_OUT"
}
info "  → macOS icns done: $ICNS_OUT"

# ============================================================
# 6. Avalonia Browser (WASM) favicon
# ============================================================
info "Generating Avalonia Browser favicon..."
BROWSER_WWW="$AVALONIA/NezAvalonia.Browser/wwwroot"
mkdir -p "$BROWSER_WWW"
svg2png 32 "$BROWSER_WWW/favicon.png"
info "  → Browser favicon done"

# ============================================================
# 7. Avalonia Windows .ico
# ============================================================
info "Generating Avalonia Windows ico..."
ICO_TMPDIR="/tmp/nez-ico"
rm -rf "$ICO_TMPDIR"
mkdir -p "$ICO_TMPDIR"
for s in 16 32 48 64 128 256; do
    svg2png "$s" "$ICO_TMPDIR/icon_${s}.png"
done
ICO_OUT="$AVALONIA/Assets/nez.ico"
magick "$ICO_TMPDIR"/icon_16.png "$ICO_TMPDIR"/icon_32.png "$ICO_TMPDIR"/icon_48.png "$ICO_TMPDIR"/icon_64.png "$ICO_TMPDIR"/icon_128.png "$ICO_TMPDIR"/icon_256.png "$ICO_OUT"
info "  → Windows ico done: $ICO_OUT"

# Cleanup
rm -rf "$ICNS_DIR" "$ICO_TMPDIR" "$PADDED_SVG"

echo ""
echo -e "\033[0;32m✓ All icons generated from docs/icon.svg\033[0m"
