#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release
YOZ_BUILD_DIR="$(swift build -c release --show-bin-path)"
YOZ_APP="$PWD/dist/Yoz.app"
mkdir -p "$YOZ_APP/Contents/MacOS" "$YOZ_APP/Contents/Resources"
cp "$YOZ_BUILD_DIR/Yoz" "$YOZ_APP/Contents/MacOS/Yoz"
cp -R "$YOZ_BUILD_DIR/Yoz_Yoz.bundle" "$YOZ_APP/Contents/Resources/"
cp packaging/Info.plist "$YOZ_APP/Contents/Info.plist"
if [[ -f packaging/Yoz.icns ]]; then cp packaging/Yoz.icns "$YOZ_APP/Contents/Resources/"; fi
codesign --force --deep --sign - --identifier uz.yoz.transliterator "$YOZ_APP"
echo "Built: $YOZ_APP"
