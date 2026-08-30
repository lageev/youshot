#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

swift build -c release --product YouShot
bin="$(swift build -c release --show-bin-path)/YouShot"
app="$root/dist/YouShot.app"
bundle_id="com.youshot.app"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/YouShot"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_id" "$app/Contents/Info.plist"
if [[ -f "$root/Resources/AppIcon/YouShot.icns" ]]; then
    cp "$root/Resources/AppIcon/YouShot.icns" "$app/Contents/Resources/YouShot.icns"
fi
cp "$root/Resources/MenuBarIcon.png" "$app/Contents/Resources/MenuBarIcon.png"
printf 'APPL????' > "$app/Contents/PkgInfo"
chmod +x "$app/Contents/MacOS/YouShot"
codesign --force --deep --sign - "$app"

echo "Built $app"
