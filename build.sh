#!/bin/bash
# Builds EinkRefresh.app into ~/Applications.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Applications/EinkRefresh.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$SRC_DIR/Info.plist" "$APP/Contents/Info.plist"

swiftc \
	-O \
	-target "$(uname -m)-apple-macos13.0" \
	-o "$APP/Contents/MacOS/EinkRefresh" \
	"$SRC_DIR/main.swift"

codesign --force --sign - "$APP"

echo "built: $APP"
