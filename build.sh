#!/bin/zsh
# Builds PopNote.app and installs it to /Applications.
set -e
cd "$(dirname "$0")"
APP=build/PopNote.app
rm -rf build
mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.popnote</string>
  <key>CFBundleName</key><string>PopNote</string>
  <key>CFBundleExecutable</key><string>PopNote</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
swiftc -O main.swift -o "$APP/Contents/MacOS/PopNote" -framework Cocoa -framework Carbon -framework ServiceManagement
codesign --force --sign - "$APP"
pkill -x PopNote || true
rm -rf /Applications/PopNote.app
cp -R "$APP" /Applications/
echo "Installed /Applications/PopNote.app"
