#!/usr/bin/env bash
# Re-derive the vendored Lucide set from an upstream release (#18, #19, #34).
#
#   tools/vendor-lucide.sh              re-vendor the pinned version
#   tools/vendor-lucide.sh 1.29.0       bump to a new one
#
# The set in `assets/icons/lucide/` is forest-shell-normalized, not pristine:
# `stroke-width` 1.5 and `stroke`/`fill` `#ffffff` are baked in, because Qt's
# SVG renderer resolves neither `currentColor` nor a runtime stroke weight.
# Provenance is therefore *this script* plus the pinned version — download,
# apply the two rewrites, replace the directory wholesale. Never hand-edit a
# file in there; re-run this instead.
#
# The download is the release's `lucide-icons-<version>.zip` asset, of which
# only `icons/*.svg` and `icons/LICENSE` are kept (the sibling `*.json`
# metadata is not vendored — the filenames are the lookup key, so there is no
# manifest to maintain).
set -euo pipefail

version="${1:-1.28.0}"
repo="$(cd "$(dirname "$0")/.." && pwd)"
dest="$repo/assets/icons/lucide"
url="https://github.com/lucide-icons/lucide/releases/download/${version}/lucide-icons-${version}.zip"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "fetching lucide $version"
curl -fsSL -o "$work/lucide.zip" "$url"
unzip -q "$work/lucide.zip" -d "$work/unpacked"

src="$work/unpacked/icons"
[[ -d "$src" ]] || { echo "no icons/ in the release asset" >&2; exit 1; }

count=$(find "$src" -maxdepth 1 -name '*.svg' | wc -l)
echo "unpacked $count icons"

# Wholesale replacement, so an icon dropped upstream disappears here too rather
# than lingering as a name that resolves on one machine and not the next.
rm -rf "$dest"
mkdir -p "$dest"
cp "$src"/*.svg "$dest/"
cp "$src/LICENSE" "$dest/LICENSE"

"$repo/tools/normalize-lucide.py" "$dest"
"$repo/tools/normalize-lucide.py" --check "$dest"

echo "vendored lucide $version -> ${dest#"$repo"/}"
echo "remember to update the pinned version in assets/README.md and in this script"
