#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -z "${YOUSHOT_CODESIGN_IDENTITY:-}" ]]; then
    echo "Set YOUSHOT_CODESIGN_IDENTITY to your Developer ID Application identity." >&2
    exit 1
fi
if [[ -z "${YOUSHOT_VERSION:-}" || -z "${YOUSHOT_BUILD_NUMBER:-}" ]]; then
    echo "Set YOUSHOT_VERSION and YOUSHOT_BUILD_NUMBER for this release." >&2
    exit 1
fi

"$root/scripts/build.sh"
"$root/scripts/notarize.sh"
"$root/scripts/package_update.sh"

echo "Release artifacts are ready in $root/dist/updates"
