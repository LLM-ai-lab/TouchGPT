#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$repo_root/build/tests"
mkdir -p "$test_dir"
# Native-architecture harnesses can also run on macOS CI hosts without a Touch Bar.
xcrun clang -fobjc-arc -O2 -Wall -Wextra -Wno-unused-parameter \
    -I "$repo_root/src" -framework AppKit \
    "$repo_root/tests/bridge_test.m" "$repo_root/src/Bridge.m" -o "$test_dir/bridge_test"
python3 "$repo_root/tests/integration_test.py" "$test_dir/bridge_test"
xcrun clang -fobjc-arc -O2 -Wall -Wextra -Wno-unused-parameter \
    -I "$repo_root/src" -framework AppKit -framework ServiceManagement \
    -framework CoreGraphics -framework IOSurface \
    "$repo_root/tests/icon-animation-check.m" "$repo_root/src/Bridge.m" \
    "$repo_root/src/QuotaIcon.m" "$repo_root/src/TouchBarProbe.m" -o "$test_dir/icon-animation-check"
"$test_dir/icon-animation-check"
