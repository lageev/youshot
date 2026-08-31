#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="${YOUSHOT_APP_PATH:-$root/dist/YouShot.app}"
profile="${YOUSHOT_NOTARY_PROFILE:-focusmic-notary}"
submission_archive="${YOUSHOT_NOTARY_ARCHIVE:-$root/dist/YouShot-notarization.zip}"

if [[ ! -d "$app" ]]; then
    echo "Missing $app; build a Developer ID signed app first." >&2
    exit 1
fi

signature="$(codesign --display --verbose=4 "$app" 2>&1)"
if [[ "$signature" != *"Authority=Developer ID Application:"* ]]; then
    echo "The app is not signed with a Developer ID Application certificate." >&2
    echo "Set YOUSHOT_CODESIGN_IDENTITY and run ./scripts/build.sh again." >&2
    exit 1
fi

codesign --verify --deep --strict --verbose=2 "$app"

rm -f "$submission_archive"
ditto -c -k --keepParent "$app" "$submission_archive"

xcrun notarytool submit "$submission_archive" \
    --keychain-profile "$profile" \
    --wait

xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=4 "$app"

echo "Notarized and stapled $app"
