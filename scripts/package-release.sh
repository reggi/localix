#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_NAME="Localix"
VERSION=${1:-}

if ! printf '%s\n' "$VERSION" | grep -Eq '^v?[0-9]+\.[0-9]+\.[0-9]+$'; then
    printf 'Usage: %s <MAJOR.MINOR.PATCH>\n' "$0" >&2
    exit 1
fi

VERSION=${VERSION#v}
ARTIFACT_BASE="$ROOT/dist/Localix-$VERSION-macOS-universal"
ZIP="$ARTIFACT_BASE.zip"
CHECKSUM="$ZIP.sha256"

APP_VERSION="$VERSION" \
BUILD_NUMBER="${BUILD_NUMBER:-1}" \
ARCHS="${ARCHS:-arm64 x86_64}" \
"$ROOT/scripts/build-app.sh"

rm -f "$ZIP" "$CHECKSUM"
ditto \
    -c \
    -k \
    --sequesterRsrc \
    --keepParent \
    "$ROOT/dist/$APP_NAME.app" \
    "$ZIP"
(
    cd "$ROOT/dist"
    shasum -a 256 "$(basename "$ZIP")"
) > "$CHECKSUM"

printf 'Packaged %s\n' "$ZIP"
printf 'Checksum %s\n' "$CHECKSUM"
