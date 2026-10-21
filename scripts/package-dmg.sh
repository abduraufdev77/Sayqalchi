#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
./scripts/build.sh
YOZ_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' packaging/Info.plist)"
YOZ_STAGE="$(mktemp -d -t yoz-dmg)"
trap 'rm -rf "$YOZ_STAGE"' EXIT
ditto dist/Yoz.app "$YOZ_STAGE/Yoz.app"
ln -s /Applications "$YOZ_STAGE/Applications"
cp docs/INSTALL.txt "$YOZ_STAGE/Read me.txt"
hdiutil create -volname "Yoz $YOZ_VERSION" -srcfolder "$YOZ_STAGE" -ov -format UDZO "dist/Yoz-$YOZ_VERSION-arm64.dmg"
LC_ALL=C LANG=C shasum -a 256 "dist/Yoz-$YOZ_VERSION-arm64.dmg" > dist/SHA256SUMS.txt
echo "Packaged: $PWD/dist/Yoz-$YOZ_VERSION-arm64.dmg"
