#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
mkdir -p build/GlowESP.framework
xcrun --sdk iphoneos clang++ -std=c++17 -fobjc-arc -fvisibility=hidden \
  -arch arm64 -isysroot "$SDK" -miphoneos-version-min=15.0 \
  -dynamiclib src/Runtime.mm src/Overlay.mm \
  -framework Foundation -framework UIKit -framework QuartzCore \
  -install_name '@rpath/GlowESP.framework/GlowESP' \
  -o build/GlowESP.framework/GlowESP
cp Info.plist build/GlowESP.framework/Info.plist
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" build/GlowESP.framework
fi
echo 'Built build/GlowESP.framework. This is not an installable or signed IPA.'
