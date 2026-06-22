#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  swift build -c release --arch arm64 --arch x86_64
  BINARY="$ROOT/.build/apple/Products/Release/FlightReminder"
else
  swift build -c release
  BINARY="$ROOT/.build/release/FlightReminder"
fi

APP="$ROOT/dist/清风航线.app"
CONTENTS="$APP/Contents"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BINARY" "$CONTENTS/MacOS/FlightReminder"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/plane.png" "$CONTENTS/Resources/plane.png"
cp "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"

signed=false
for attempt in 1 2 3; do
  xattr -cr "$APP"
  xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
  xattr -d 'com.apple.fileprovider.fpfs#P' "$APP" 2>/dev/null || true
  if codesign --force --deep --sign - \
    --entitlements "$ROOT/Resources/FlightReminder.entitlements" \
    "$APP"; then
    signed=true
    break
  fi
  sleep 0.2
done

if [[ "$signed" != true ]]; then
  echo "Unable to sign $APP" >&2
  exit 1
fi

echo "$APP"
