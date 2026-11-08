#!/bin/bash
# Builds Musicfy and assembles build/Musicfy.app.
#   ./build.sh            build
#   ./build.sh --install  build, copy to /Applications and open it
set -euo pipefail
cd "$(dirname "$0")"

ARCH="$(uname -m)"
swift build -c release --arch "$ARCH"
BIN_DIR="$(swift build -c release --arch "$ARCH" --show-bin-path)"

APP=build/Musicfy.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Musicfy" "$APP/Contents/MacOS/Musicfy"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [ ! -f build/AppIcon.icns ]; then
  swift tools/make-icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Local ad-hoc signature (no developer account). Enough to run it on this Mac.
codesign --force --sign - --identifier com.pedrocela.musicfy "$APP"
echo "Done: $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Musicfy || true
  sleep 1
  rm -rf /Applications/Musicfy.app
  cp -R "$APP" /Applications/
  open /Applications/Musicfy.app
  echo "Installed in /Applications and opened."
fi
