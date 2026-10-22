#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
./scripts/build.sh
YOZ_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' packaging/Info.plist)"
YOZ_STAGE="$(mktemp -d -t yoz-dmg)"
trap 'rm -rf "$YOZ_STAGE"' EXIT
ditto dist/Yoz.app "$YOZ_STAGE/Sayqalchi.app"
ln -s /Applications "$YOZ_STAGE/Applications"
cp docs/INSTALL.txt "$YOZ_STAGE/Read me.txt"
hdiutil create -volname "Sayqalchi $YOZ_VERSION" -srcfolder "$YOZ_STAGE" -ov -format UDZO "dist/Sayqalchi-$YOZ_VERSION-arm64.dmg"
(cd dist && LC_ALL=C LANG=C shasum -a 256 "Sayqalchi-$YOZ_VERSION-arm64.dmg" > SHA256SUMS.txt)
echo "Packaged: $PWD/dist/Sayqalchi-$YOZ_VERSION-arm64.dmg"
