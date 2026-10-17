#!/bin/bash
# Builds build/TypoCat.app (menu-bar agent).
# Set SIGN_IDENTITY to a code-signing certificate name to keep Accessibility
# access across rebuilds; the default ad-hoc signature changes every build.
set -euo pipefail
cd "$(dirname "$0")/.."

# English plus languages whose macOS layouts use a non-Latin script (Language.bundled).
BASE=https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018
for lang in en ru uk bg sr mk kk el he ar fa ur hy ka hi th; do
  f="Data/${lang}_50k.txt"
  [ -f "$f" ] && continue
  # Small corpora only publish a full list; keep its 50k most frequent lines.
  curl -fsSL -o "$f" "$BASE/$lang/${lang}_50k.txt" \
    || { curl -fsSL "$BASE/$lang/${lang}_full.txt" | head -n 50000 > "$f"; } \
    || { rm -f "$f"; echo "warning: no word list for $lang; its layout won't be detected"; }
done

swift build -c release
APP=build/TypoCat.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/TypoCat "$APP/Contents/MacOS/"
cp Data/*_50k.txt "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>TypoCat</string>
  <key>CFBundleIdentifier</key><string>com.typocat.app</string>
  <key>CFBundleName</key><string>TypoCat</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>LSMultipleInstancesProhibited</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Built $APP"
