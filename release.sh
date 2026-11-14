#!/bin/zsh
# Builds PopNote.app and packs it into build/PopNote.dmg (drag-to-Applications layout).
set -e
cd "$(dirname "$0")"
NO_INSTALL=1 ./build.sh
STAGE=build/dmg
rm -rf "$STAGE" build/PopNote.dmg
mkdir -p "$STAGE"
cp -R build/PopNote.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname PopNote -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov build/PopNote.dmg
rm -rf "$STAGE"
echo "Built build/PopNote.dmg"
