#!/bin/bash
# Requires a physical Touch Bar. Quit Touch GPT before running this documentation fixture.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
fixture="$root/build/Screenshot Fixture.app"
mkdir -p "$fixture/Contents/MacOS" "$fixture/Contents/Resources" "$root/docs/images"
cp "$root/resources/Info.plist" "$fixture/Contents/Info.plist"
cp "$root/resources/AppIcon.icns" "$fixture/Contents/Resources/"
rm -f "$fixture/Contents/Resources/GPTMark.png"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.touchgpt.documentation' "$fixture/Contents/Info.plist"
xcrun clang -arch arm64 -mmacosx-version-min=13.0 -fobjc-arc -O2 -Wno-unused-parameter \
    -I "$root/src" -framework AppKit -framework ServiceManagement -framework CoreGraphics -framework IOSurface -framework ImageIO \
    "$root/tools/capture_demo.m" "$root/src/Bridge.m" "$root/src/QuotaIcon.m" "$root/src/TouchBarProbe.m" \
    -o "$fixture/Contents/MacOS/TouchGPT"
codesign --force --sign - "$fixture"
"$fixture/Contents/MacOS/TouchGPT" "$root/docs/images"
