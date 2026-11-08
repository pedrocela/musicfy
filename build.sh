#!/bin/bash
# Builds Musicfy and assembles build/Musicfy.app.
#   ./build.sh            build
#   ./build.sh --install  build, copy to /Applications and open it
set -euo pipefail
cd "$(dirname "$0")"

# This Mac's architecture by default. ARCHS="arm64 x86_64" makes a universal app for
# Apple silicon and Intel (CI does that; it needs full Xcode, not just the command line tools).
read -ra ARCHS <<< "${ARCHS:-$(uname -m)}"
SWIFT_ARCHS=(); CLANG_ARCHS=()
for a in "${ARCHS[@]}"; do SWIFT_ARCHS+=(--arch "$a"); CLANG_ARCHS+=(-arch "$a"); done
swift build -c release "${SWIFT_ARCHS[@]}"
BIN_DIR="$(swift build -c release "${SWIFT_ARCHS[@]}" --show-bin-path)"

APP=build/Musicfy.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Musicfy" "$APP/Contents/MacOS/Musicfy"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Stamp the build: the commit count as the build number and the commit itself, so the menu
# says exactly which version is installed. Outside a git checkout it stays as it is.
if COMMIT="$(git rev-parse --short HEAD 2>/dev/null)"; then
  git diff --quiet HEAD -- 2>/dev/null || COMMIT="$COMMIT-dirty"
  BUILD_NUMBER="$(git rev-list --count HEAD)"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :MusicfyCommit string $COMMIT" "$APP/Contents/Info.plist"
fi

# The Now Playing reader for Podcasts: a small library that /usr/bin/perl loads, because
# MediaRemote only answers Apple's own binaries (see Helper/NowPlaying.m).
mkdir -p "$APP/Contents/Frameworks"
clang -dynamiclib -fobjc-arc -O2 "${CLANG_ARCHS[@]}" -mmacosx-version-min=14.0 \
  -framework Foundation -o "$APP/Contents/Frameworks/MusicfyNowPlaying.dylib" Helper/NowPlaying.m
codesign --force --sign - "$APP/Contents/Frameworks/MusicfyNowPlaying.dylib"
cp Resources/now-playing.pl "$APP/Contents/Resources/now-playing.pl"

# Redraw the icon when it is missing or its drawing changed.
if [ ! -f build/AppIcon.icns ] || [ tools/make-icon.swift -nt build/AppIcon.icns ]; then
  rm -rf build/AppIcon.iconset
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
  # Let Finder and the Dock pick up a new icon instead of the cached one.
  touch /Applications/Musicfy.app
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Musicfy.app || true
  open /Applications/Musicfy.app
  echo "Installed in /Applications and opened."
fi
