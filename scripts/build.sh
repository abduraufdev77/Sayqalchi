#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release
YOZ_BUILD_DIR="$(swift build -c release --show-bin-path)"
mkdir -p "$PWD/dist"
YOZ_STAGE="$(mktemp -d "$PWD/dist/.yoz-build.XXXXXX")"
trap 'rm -rf "$YOZ_STAGE"' EXIT
YOZ_APP="$YOZ_STAGE/Yoz.app"
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
# Never overwrite a running executable's mapped pages or expose an unsigned
# half-built bundle at its normal launch path.
if [[ -d "$PWD/dist/Yoz.app" ]]; then mv "$PWD/dist/Yoz.app" "$YOZ_STAGE/previous.app"; fi
if ! mv "$YOZ_APP" "$PWD/dist/Yoz.app"; then
    if [[ -d "$YOZ_STAGE/previous.app" ]]; then mv "$YOZ_STAGE/previous.app" "$PWD/dist/Yoz.app"; fi
    exit 1
fi
echo "Built: $PWD/dist/Yoz.app"
