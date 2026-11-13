#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app="${1:-$repo_root/build/Touch GPT.app}"
if [[ "$app" != /* ]]; then app="$PWD/$app"; fi
if [[ "$app" != *.app ]]; then
    echo "Output path must end in .app" >&2
    exit 2
fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$repo_root/resources/Info.plist" "$app/Contents/Info.plist"
cp "$repo_root/resources/AppIcon.icns" "$app/Contents/Resources/"
# Remove the old image if rebuilding into a bundle made by an earlier release.
rm -f "$app/Contents/Resources/GPTMark.png"
cp "$repo_root/LICENSE" "$repo_root/THIRD_PARTY_NOTICES.md" "$app/Contents/Resources/"
xcrun clang -arch arm64 -mmacosx-version-min=13.0 -fobjc-arc -O2 -Wall -Wextra \
    -Wno-unused-parameter -framework AppKit -framework ServiceManagement \
    -framework CoreGraphics -framework IOSurface \
    "$repo_root/src/main.m" "$repo_root/src/Bridge.m" "$repo_root/src/QuotaIcon.m" \
    "$repo_root/src/TouchBarProbe.m" -o "$app/Contents/MacOS/TouchGPT"
# Local ad hoc signing: this does not create a Developer ID signature or notarization.
codesign --force --sign - "$app"
codesign --verify --strict "$app"
plutil -lint "$app/Contents/Info.plist"
echo "Built: $app"
