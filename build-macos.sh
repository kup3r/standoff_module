#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
BUILD_DIR="${BUILD_DIR:-build}"
DEV_BRIDGE="${GLOW_DEV_BRIDGE:-0}"
case "$DEV_BRIDGE" in 0|1) ;; *) echo 'GLOW_DEV_BRIDGE must be 0 or 1'; exit 1;; esac
mkdir -p "$BUILD_DIR/GlowESP.framework"
xcrun --sdk iphoneos clang++ -std=c++17 -fobjc-arc -fvisibility=hidden \
  -DGLOW_DEV_BRIDGE="$DEV_BRIDGE" \
  -arch arm64 -isysroot "$SDK" -miphoneos-version-min=15.0 \
  -dynamiclib src/Runtime.mm src/Overlay.mm \
  -framework Foundation -framework UIKit -framework QuartzCore -framework CoreGraphics \
  -install_name '@rpath/GlowESP.framework/GlowESP' \
  -o "$BUILD_DIR/GlowESP.framework/GlowESP"
cp Info.plist "$BUILD_DIR/GlowESP.framework/Info.plist"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" "$BUILD_DIR/GlowESP.framework"
fi
echo "Built $BUILD_DIR/GlowESP.framework. This is not an installable or signed IPA."
