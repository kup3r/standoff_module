#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
APP=build/GlowUITests.app
mkdir -p "$APP"
xcrun --sdk iphonesimulator clang++ -std=c++17 -fobjc-arc \
  -arch "$(uname -m)" -isysroot "$SDK" -mios-simulator-version-min=17.0 \
  tests/ui-smoke.mm src/Runtime.mm src/Overlay.mm \
  -framework UIKit -framework Foundation -framework QuartzCore -framework CoreGraphics \
  -o "$APP/GlowUITests"
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.glow.uitest</string>
<key>CFBundleExecutable</key><string>GlowUITests</string>
<key>CFBundleName</key><string>GlowUITests</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>MinimumOSVersion</key><string>17.0</string>
<key>UIDeviceFamily</key><array><integer>1</integer></array>
<key>LSRequiresIPhoneOS</key><true/>
<key>UILaunchScreen</key><dict/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
DEVICE="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(v["udid"] for group in d["devices"].values() for v in group if v["name"].startswith("iPhone")))')"
xcrun simctl boot "$DEVICE" || true
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl install "$DEVICE" "$APP"
xcrun simctl launch "$DEVICE" local.glow.uitest
CONTAINER="$(xcrun simctl get_app_container "$DEVICE" local.glow.uitest data)"
RESULT="$CONTAINER/Documents/ui-smoke.txt"
for i in {1..30}; do
  if [[ -f "$RESULT" ]]; then
    cat "$RESULT"
    cp "$RESULT" build/ui-smoke.txt
    if [[ "$(head -c 4 "$RESULT")" == PASS ]]; then exit 0; else exit 1; fi
  fi
  sleep 1
done
echo 'UI smoke app did not produce a result'
exit 1
