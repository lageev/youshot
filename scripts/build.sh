#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

swift build -c release --product YouShot
bin="$(swift build -c release --show-bin-path)/YouShot"
app="$root/dist/YouShot.app"
bundle_id="top.yayalu.youshot"
version="${YOUSHOT_VERSION:-1.0.0}"
build_number="${YOUSHOT_BUILD_NUMBER:-1}"
update_feed_url="${YOUSHOT_UPDATE_FEED_URL:-https://youshot.yayalu.top/updates/appcast.xml}"
update_public_key="${YOUSHOT_UPDATE_PUBLIC_ED_KEY:-DtydhIQRBSDkhL52gYd72UOMjiK/5TkFVYQYZcaM5Sw=}"
codesign_identity="${YOUSHOT_CODESIGN_IDENTITY:--}"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$bin" "$app/Contents/MacOS/YouShot"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_id" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUFeedURL $update_feed_url" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $update_public_key" "$app/Contents/Info.plist"
if [[ -f "$root/Resources/AppIcon/YouShot.icns" ]]; then
    cp "$root/Resources/AppIcon/YouShot.icns" "$app/Contents/Resources/YouShot.icns"
fi
cp "$root/Resources/MenuBarIcon.png" "$app/Contents/Resources/MenuBarIcon.png"

sparkle_framework="$(find "$root/.build/artifacts" -path '*/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework' -print -quit)"
if [[ -z "$sparkle_framework" ]]; then
    echo "Sparkle.framework not found in SwiftPM artifacts" >&2
    exit 1
fi
ditto "$sparkle_framework" "$app/Contents/Frameworks/Sparkle.framework"

printf 'APPL????' > "$app/Contents/PkgInfo"
chmod +x "$app/Contents/MacOS/YouShot"
codesign_args=(--force --sign "$codesign_identity")
if [[ "$codesign_identity" != "-" ]]; then
    codesign_args+=(--options runtime --timestamp)
fi
codesign "${codesign_args[@]}" "$app"

echo "Built $app"
