#!/bin/bash
# Renders the app icon (Resources/AppIcon.icns) and the social preview
# (docs/brand/social-preview.png) from docs/brand/app-icon.svg. Both outputs are
# committed, so building the app doesn't need this; rerun it after changing the SVG.
set -euo pipefail
cd "$(dirname "$0")/.."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
swiftc -O scripts/brand/render-svg.swift -o "$work/render-svg"
swiftc -O scripts/brand/social-preview.swift -o "$work/social-preview"

iconset="$work/AppIcon.iconset"
mkdir "$iconset"
for size in 16 32 128 256 512; do
  "$work/render-svg" docs/brand/app-icon.svg "$iconset/icon_${size}x${size}.png" "$size"
  "$work/render-svg" docs/brand/app-icon.svg "$iconset/icon_${size}x${size}@2x.png" $((size * 2))
done
iconutil -c icns "$iconset" -o Resources/AppIcon.icns

# Brand fonts (SIL Open Font License) from Google Fonts, only for rendering.
mkdir "$work/fonts"
base=https://github.com/google/fonts/raw/main/ofl
curl -fsSL -o "$work/fonts/Rubik.ttf" "$base/rubik/Rubik%5Bwght%5D.ttf"
curl -fsSL -o "$work/fonts/NotoSansThai.ttf" "$base/notosansthai/NotoSansThai%5Bwdth,wght%5D.ttf"
curl -fsSL -o "$work/fonts/PlexMono.ttf" "$base/ibmplexmono/IBMPlexMono-Medium.ttf"
"$work/social-preview" docs/brand/app-icon.svg "$work/fonts" docs/brand/social-preview.png
echo "Wrote Resources/AppIcon.icns and docs/brand/social-preview.png"
