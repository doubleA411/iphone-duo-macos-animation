#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/macTilt.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD/module-cache"
xcrun swiftc -O -target "$(uname -m)-apple-macosx26.0" -module-cache-path "$BUILD/module-cache" \
  "$ROOT"/Sources/*.swift -o "$APP/Contents/MacOS/macTilt" \
  -framework AppKit -framework SwiftUI -framework Metal -framework MetalKit \
  -framework ScreenCaptureKit -framework IOKit -framework QuartzCore
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/default.png" "$ROOT/Resources/AppIcon.icns" \
  "$ROOT/Sources/FoldShaders.metal" "$APP/Contents/Resources/"
# Use a consistent certificate to preserve Screen Recording permission across builds.
# Ad-hoc signing is available for local builds but can require permission renewal.
SIGNING_IDENTITY="${MACTILT_SIGNING_IDENTITY:--}"
codesign --force --sign "$SIGNING_IDENTITY" "$APP"
codesign --verify --strict "$APP"
printf 'Built: %s\n' "$APP"
