#!/bin/bash
# Packs build/TypoCat.app into build/TypoCat.dmg: a drag-to-Applications window
# with the installer background. Run ./scripts/build-app.sh first.
# Laying out the window asks Finder through AppleScript; without that permission
# the disk image still works, just without the background.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/TypoCat.app
DMG=build/TypoCat.dmg
VOLUME=TypoCat
[ -d "$APP" ] || { echo "Missing $APP: run ./scripts/build-app.sh first" >&2; exit 1; }

work=$(mktemp -d)
trap 'hdiutil detach "/Volumes/$VOLUME" -quiet 2>/dev/null || true; rm -rf "$work"' EXIT
mkdir -p "$work/root/.background"
cp -R "$APP" "$work/root/"
ln -s /Applications "$work/root/Applications"
cp Resources/dmg-background.tiff "$work/root/.background/background.tiff"

hdiutil detach "/Volumes/$VOLUME" -quiet 2>/dev/null || true
hdiutil create -quiet -volname "$VOLUME" -srcfolder "$work/root" -fs HFS+ -format UDRW -ov "$work/rw.dmg"
hdiutil attach -quiet -noautoopen "$work/rw.dmg"

cat > "$work/layout.applescript" <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLUME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 840, 540}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "TypoCat.app" of container window to {170, 200}
    set position of item "Applications" of container window to {470, 200}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT
# Finder can hang without a GUI session (some CI runners), so give it a minute at most.
osascript "$work/layout.applescript" &
pid=$!
for _ in $(seq 60); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
if kill -0 "$pid" 2>/dev/null; then kill "$pid"; echo "Finder layout timed out; the disk image has no background" >&2
elif ! wait "$pid"; then echo "Finder layout skipped (allow Automation for Finder to get the background)" >&2; fi

sync
hdiutil detach "/Volumes/$VOLUME" -quiet
rm -f "$DMG"
hdiutil convert -quiet "$work/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG"
echo "Built $DMG"
