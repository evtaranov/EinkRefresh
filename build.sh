#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="$HOME/Applications/EinkRefresh.app"
mkdir -p "$APP/Contents/MacOS"
swiftc -O main.swift -o "$APP/Contents/MacOS/EinkRefresh"
cat > "$APP/Contents/Info.plist" <<'P'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.eink-refresh</string>
<key>CFBundleName</key><string>EinkRefresh</string>
<key>CFBundleExecutable</key><string>EinkRefresh</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
P
codesign --force --sign - "$APP"
echo "$APP"
