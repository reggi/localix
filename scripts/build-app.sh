#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_NAME="Localix"
APP="$ROOT/dist/$APP_NAME.app"

cd "$ROOT"
set -- -c release
for arch in ${ARCHS:-}; do
    set -- "$@" --arch "$arch"
done

swift build "$@"
BIN_DIR=$(swift build "$@" --show-bin-path)

"$ROOT/scripts/build-icon.sh"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Localix" "$APP/Contents/MacOS/Localix"
cp "$ROOT/App/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/App/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

if [ "${APP_VERSION:-}" ]; then
    /usr/libexec/PlistBuddy \
        -c "Set :CFBundleShortVersionString $APP_VERSION" \
        "$APP/Contents/Info.plist"
fi

if [ "${BUILD_NUMBER:-}" ]; then
    /usr/libexec/PlistBuddy \
        -c "Set :CFBundleVersion $BUILD_NUMBER" \
        "$APP/Contents/Info.plist"
fi

if [ "${CODE_SIGN_IDENTITY:-}" ]; then
    codesign --force --sign "$CODE_SIGN_IDENTITY" "$APP"
else
    codesign \
        --force \
        --sign - \
        --requirements '=designated => identifier "local.reggi.localix"' \
        "$APP"
fi

printf 'Built %s\n' "$APP"
