#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
./scripts/build.sh
YOZ_DEST="/Applications/Sayqalchi.app"
if [[ -e "$YOZ_DEST" ]]; then
    YOZ_EXISTING_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$YOZ_DEST/Contents/Info.plist")"
    if [[ "$YOZ_EXISTING_ID" != "uz.yoz.transliterator" ]]; then
        echo "Refusing to replace an unrelated app at $YOZ_DEST" >&2
        exit 1
    fi
fi
YOZ_INSTALL_STAGE="$(mktemp -d /Applications/.sayqalchi-install.XXXXXX)"
trap 'rm -rf "$YOZ_INSTALL_STAGE"' EXIT
ditto dist/Sayqalchi.app "$YOZ_INSTALL_STAGE/Sayqalchi.app"
codesign --verify --deep --strict "$YOZ_INSTALL_STAGE/Sayqalchi.app"
# Quit normally before replacing its files. Never kill an unrelated process.
swift -e 'import AppKit; for app in NSRunningApplication.runningApplications(withBundleIdentifier: "uz.yoz.transliterator") { app.terminate() }; let until = Date().addingTimeInterval(5); while Date() < until && !NSRunningApplication.runningApplications(withBundleIdentifier: "uz.yoz.transliterator").isEmpty { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }; if !NSRunningApplication.runningApplications(withBundleIdentifier: "uz.yoz.transliterator").isEmpty { exit(1) }'
if [[ -e "$YOZ_DEST" ]]; then mv "$YOZ_DEST" "$YOZ_INSTALL_STAGE/previous.app"; fi
if ! mv "$YOZ_INSTALL_STAGE/Sayqalchi.app" "$YOZ_DEST"; then
    if [[ -e "$YOZ_INSTALL_STAGE/previous.app" ]]; then mv "$YOZ_INSTALL_STAGE/previous.app" "$YOZ_DEST"; fi
    exit 1
fi
echo "Installed: $YOZ_DEST"
echo "Open this copy from Applications. If an old Yoz approval is stale, remove it in Accessibility and add this app once."
