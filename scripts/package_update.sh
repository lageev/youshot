#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/dist/YouShot.app"
updates_dir="${YOUSHOT_UPDATES_DIR:-$root/dist/updates}"
sparkle_bin="${SPARKLE_BIN_DIR:-$root/.build/artifacts/sparkle/Sparkle/bin}"
download_prefix="${YOUSHOT_UPDATE_DOWNLOAD_PREFIX:-https://youshot.yayalu.top/updates/}"

if [[ ! -d "$app" ]]; then
    echo "Missing $app; run ./scripts/build.sh first." >&2
    exit 1
fi
if [[ -z "$sparkle_bin" || ! -x "$sparkle_bin/generate_appcast" ]]; then
    echo "Set SPARKLE_BIN_DIR to the bin directory from the official Sparkle release." >&2
    exit 1
fi

signature="$(codesign --display --verbose=4 "$app" 2>&1)"
if [[ "$signature" != *"Authority=Developer ID Application:"* ]]; then
    echo "Refusing to package an app without a Developer ID Application signature." >&2
    exit 1
fi
if ! xcrun stapler validate "$app" >/dev/null; then
    echo "Refusing to package an app without a valid notarization ticket." >&2
    echo "Run ./scripts/notarize.sh first." >&2
    exit 1
fi

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
archive="$updates_dir/YouShot-$version-$build_number.zip"

mkdir -p "$updates_dir"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
"$sparkle_bin/generate_appcast" \
    --account top.yayalu.youshot \
    --download-url-prefix "$download_prefix" \
    --link "https://youshot.yayalu.top" \
    "$updates_dir"

echo "Created $archive"
echo "Updated $updates_dir/appcast.xml"
