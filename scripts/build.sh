#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release
YOZ_BUILD_DIR="$(swift build -c release --show-bin-path)"
mkdir -p "$PWD/dist"
YOZ_STAGE="$(mktemp -d "$PWD/dist/.yoz-build.XXXXXX")"
trap 'rm -rf "$YOZ_STAGE"' EXIT
YOZ_APP="$YOZ_STAGE/Sayqalchi.app"
mkdir -p "$YOZ_APP/Contents/MacOS" "$YOZ_APP/Contents/Resources"
cp "$YOZ_BUILD_DIR/Yoz" "$YOZ_APP/Contents/MacOS/Yoz"
# Replace generated resources so stale/read-only dependency notices cannot break rebuilds.
rm -rf "$YOZ_APP/Contents/Resources/Yoz_Yoz.bundle"
cp -R "$YOZ_BUILD_DIR/Yoz_Yoz.bundle" "$YOZ_APP/Contents/Resources/"
cp packaging/Info.plist "$YOZ_APP/Contents/Info.plist"
if [[ -f packaging/Yoz.icns ]]; then cp packaging/Yoz.icns "$YOZ_APP/Contents/Resources/"; fi
python3 scripts/audit-secrets.py --bundle "$YOZ_APP"
# An ad-hoc signature pins Accessibility approval to the binary hash. Prefer
# a certificate so successive builds retain the same designated requirement.
# CI/distribution can select an identity explicitly with YOZ_SIGNING_IDENTITY.
YOZ_SIGNER="${YOZ_SIGNING_IDENTITY:-}"
if [[ -z "$YOZ_SIGNER" ]]; then
    YOZ_IDENTITIES="$(security find-identity -v -p codesigning)"
    YOZ_SIGNER="$(print -r -- "$YOZ_IDENTITIES" | awk '/"Developer ID Application:/{print $2; exit}')"
    if [[ -z "$YOZ_SIGNER" ]]; then
        YOZ_SIGNER="$(print -r -- "$YOZ_IDENTITIES" | awk '/"Apple Development:/{print $2; exit}')"
    fi
fi
if [[ -z "$YOZ_SIGNER" ]]; then
    YOZ_SIGNER="-"
    echo "No signing certificate found; ad-hoc builds need Accessibility approval again after rebuilding."
fi
codesign --force --deep --sign "$YOZ_SIGNER" --identifier uz.yoz.transliterator "$YOZ_APP"
codesign --verify --deep --strict "$YOZ_APP"
# Keep the canonical local path: macOS Accessibility grants can be path-bound.
# The display name is Sayqalchi, and a new-name link opens this same signed app.
if [[ -e "$PWD/dist/Yoz.app" || -L "$PWD/dist/Yoz.app" ]]; then mv "$PWD/dist/Yoz.app" "$YOZ_STAGE/previous.app"; fi
if ! mv "$YOZ_APP" "$PWD/dist/Yoz.app"; then
    if [[ -e "$YOZ_STAGE/previous.app" || -L "$YOZ_STAGE/previous.app" ]]; then mv "$YOZ_STAGE/previous.app" "$PWD/dist/Yoz.app"; fi
    exit 1
fi
if [[ -d "$PWD/dist/Sayqalchi.app" && ! -L "$PWD/dist/Sayqalchi.app" ]]; then
    mv "$PWD/dist/Sayqalchi.app" "$YOZ_STAGE/previous-name.app"
fi
ln -sfn Yoz.app "$PWD/dist/Sayqalchi.app"
echo "Built: $PWD/dist/Sayqalchi.app"
