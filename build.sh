#!/bin/zsh
# Builds PopNote.app (Apple silicon + Intel) and installs it to /Applications.
# NO_INSTALL=1 ./build.sh only builds it into build/.
set -e
cd "$(dirname "$0")"
APP=build/PopNote.app
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp icon/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.popnote</string>
  <key>CFBundleName</key><string>PopNote</string>
  <key>CFBundleExecutable</key><string>PopNote</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.1</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
# -file-prefix-map keeps this folder's absolute path out of the binary.
for arch in arm64 x86_64; do
  swiftc -O -target $arch-apple-macos13.0 -file-prefix-map "$PWD=." main.swift -o build/PopNote-$arch \
    -framework Cocoa -framework Carbon -framework ServiceManagement
done
lipo -create build/PopNote-arm64 build/PopNote-x86_64 -output "$APP/Contents/MacOS/PopNote"
rm build/PopNote-arm64 build/PopNote-x86_64
codesign --force --sign - "$APP"
[[ -n "$NO_INSTALL" ]] && { echo "Built $APP"; exit 0; }
pkill -x PopNote || true
rm -rf /Applications/PopNote.app
cp -R "$APP" /Applications/
echo "Installed /Applications/PopNote.app"
