#!/bin/bash
# Builds SelfControl.app for local personal use (ad-hoc signed, no Apple
# Developer account needed) and installs it to the Desktop.
set -euo pipefail

WORKSPACE="selfcontrol.xcworkspace"
SCHEME="SelfControl"
DEST_APP="$HOME/Desktop/SelfControl.app"

cd "$(dirname "$0")"

echo "==> Building $SCHEME..."
BUILD_DIR=$(xcodebuild -workspace "$WORKSPACE" -scheme "$SCHEME" \
  -configuration Debug -destination 'platform=macOS' \
  -showBuildSettings 2>/dev/null | awk -F'= ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')

xcodebuild -workspace "$WORKSPACE" -scheme "$SCHEME" \
  -configuration Debug -destination 'platform=macOS' \
  clean build \
  MACOSX_DEPLOYMENT_TARGET=10.13 GCC_PRECOMPILE_PREFIX_HEADER=NO \
  ENABLE_DEBUG_DYLIB=NO

BUILT_APP="$BUILD_DIR/SelfControl.app"
if [ ! -d "$BUILT_APP" ]; then
  echo "error: build succeeded but $BUILT_APP not found" >&2
  exit 1
fi

echo "==> Installing to $DEST_APP..."
osascript -e 'quit app "SelfControl"' 2>/dev/null || true
sleep 1
rm -rf "$DEST_APP"
cp -R "$BUILT_APP" "$DEST_APP"

echo "==> Verifying signature..."
codesign -dvvv "$DEST_APP" 2>&1 | head -3

echo "==> Launching..."
open "$DEST_APP"

echo "Done. $DEST_APP is built, signed, and running."
