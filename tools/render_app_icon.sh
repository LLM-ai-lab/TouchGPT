#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d /tmp/touchgpt-icon.XXXXXX)"
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/AppIcon.iconset" "$root/docs/images"
xcrun clang -fobjc-arc -I "$root/src" -framework AppKit "$root/tools/render_app_icon.m" \
    "$root/src/QuotaIcon.m" -o "$scratch/render-app-icon"
"$scratch/render-app-icon" "$scratch/AppIcon.iconset"
iconutil -c icns -o "$root/resources/AppIcon.icns" "$scratch/AppIcon.iconset"
cp "$scratch/AppIcon.iconset/icon_256x256.png" "$root/docs/images/app-icon.png"
