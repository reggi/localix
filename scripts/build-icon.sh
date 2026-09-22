#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SOURCE="$ROOT/App/Icon.png"
ICONSET="$ROOT/App/AppIcon.iconset"
OUTPUT="$ROOT/App/AppIcon.icns"

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

render_icon() {
    size=$1
    name=$2
    sips \
        -s format png \
        -z "$size" "$size" \
        "$SOURCE" \
        --out "$ICONSET/$name" \
        >/dev/null
}

render_icon 16 icon_16x16.png
render_icon 32 icon_16x16@2x.png
render_icon 32 icon_32x32.png
render_icon 64 icon_32x32@2x.png
render_icon 128 icon_128x128.png
render_icon 256 icon_128x128@2x.png
render_icon 256 icon_256x256.png
render_icon 512 icon_256x256@2x.png
render_icon 512 icon_512x512.png
render_icon 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET" -o "$OUTPUT"
rm -rf "$ICONSET"
