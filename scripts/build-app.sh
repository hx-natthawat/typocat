#!/bin/bash
# Builds build/TypoCat.app (menu-bar agent).
# Signs with SIGN_IDENTITY, else "TypoCat Local Signing" if
# ./scripts/make-signing-cert.sh created it, else ad-hoc. Ad-hoc signatures change
# every build, so macOS drops Accessibility access after each rebuild.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/fetch-word-lists.sh

swift build -c release
APP=build/TypoCat.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/TypoCat "$APP/Contents/MacOS/"
cp Resources/AppIcon.icns Resources/Manee.png "$APP/Contents/Resources/"
# Word lists are compiled to .tcdict, which the app maps from disk instead of parsing at launch.
for f in Data/*_50k.txt; do
  name=$(basename "$f" .txt)
  .build/release/TypoCat --compile-dict "${name%_50k}" "$f" "$APP/Contents/Resources/$name.tcdict"
done
# VERSION comes from the release tag in CI (v0.2.0 → 0.2.0).
VERSION="${VERSION:-0.2.0}"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>TypoCat</string>
  <key>CFBundleIdentifier</key><string>com.typocat.app</string>
  <key>CFBundleName</key><string>TypoCat</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>LSMultipleInstancesProhibited</key><true/>
</dict>
</plist>
PLIST
if [ -z "${SIGN_IDENTITY:-}" ] && security find-certificate -c "TypoCat Local Signing" >/dev/null 2>&1; then
  SIGN_IDENTITY="TypoCat Local Signing"
fi
codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Built $APP"
