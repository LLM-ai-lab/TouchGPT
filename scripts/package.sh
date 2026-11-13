#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$repo_root/resources/Info.plist")"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Expected a numeric major.minor.patch version in Info.plist" >&2
    exit 2
fi
app="$repo_root/build/Touch GPT.app"
dist="$repo_root/dist"
package_tmp="$(mktemp -d /tmp/touchgpt-release.XXXXXX)"
trap 'rm -rf "$package_tmp"' EXIT

"$repo_root/scripts/build.sh" "$app"
mkdir -p "$dist" "$package_tmp/TouchGPT-$version"
# Explicitly include the public project, never local state, build products or Git history.
for item in src resources scripts tests tools docs .github .gitignore .gitattributes \
            README.md README.en.md LICENSE THIRD_PARTY_NOTICES.md CONTRIBUTING.md CHANGELOG.md SECURITY.md; do
    if [[ ! -e "$repo_root/$item" ]]; then
        echo "Missing release input: $item" >&2
        exit 1
    fi
    rsync -a --exclude='.DS_Store' --exclude='._*' --exclude='__MACOSX' \
        --exclude='__pycache__' --exclude='*.pyc' --exclude='.env' --exclude='.env.*' \
        "$repo_root/$item" "$package_tmp/TouchGPT-$version/"
done

binary="TouchGPT-$version-macos-arm64.zip"
source="TouchGPT-$version-source.zip"
# ZIP preserves executable bits; omit Finder metadata and AppleDouble sidecar files.
ditto -c -k --norsrc --noextattr --keepParent "$app" "$package_tmp/$binary"
ditto -c -k --norsrc --noextattr --keepParent "$package_tmp/TouchGPT-$version" "$package_tmp/$source"
(
    cd "$package_tmp"
    shasum -a 256 "$binary" "$source" > SHA256SUMS.txt
)
mv "$package_tmp/$binary" "$package_tmp/$source" "$package_tmp/SHA256SUMS.txt" "$dist/"
echo "Packaged binary, source and checksums in: $dist"
