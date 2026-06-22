#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

UNIVERSAL=1 "$ROOT/scripts/build-app.sh"

VERSION="$(plutil -extract CFBundleShortVersionString raw "$ROOT/Resources/Info.plist")"
OUTPUT="$ROOT/dist/Qingfeng-Flight-Reminder-$VERSION.dmg"
STAGE="$(mktemp -d /tmp/qingfeng-dmg.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/root"
ditto --norsrc --noextattr "$ROOT/dist/清风航线.app" "$STAGE/root/清风航线.app"
xattr -cr "$STAGE/root/清风航线.app"
codesign --force --deep --sign - \
  --entitlements "$ROOT/Resources/FlightReminder.entitlements" \
  "$STAGE/root/清风航线.app"
codesign --verify --deep --strict "$STAGE/root/清风航线.app"

ln -s /Applications "$STAGE/root/Applications"
rm -f "$OUTPUT"
hdiutil create \
  -volname "清风航线" \
  -srcfolder "$STAGE/root" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  "$OUTPUT"

echo "$OUTPUT"
