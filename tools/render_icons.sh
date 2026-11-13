#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$root/build/icons" "$root/docs/images"
xcrun clang -fobjc-arc -I "$root/src" -framework AppKit \
    "$root/tools/render_icons.m" "$root/src/QuotaIcon.m" -o "$root/build/icons/render-icons"
"$root/build/icons/render-icons" "$root/docs/images"
