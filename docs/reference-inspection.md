# Reference inspection

Inspected 22 October 2026 (Asia/Tashkent).

## Echo

Reference: https://echo.voicelab.uz/

The site uses Figtree for Latin and Noto Sans for Cyrillic, with a warm light
background, dark pill actions, large regular-weight text, and a dark floating
dictation panel. Yoz translates that visual language into a native macOS utility
using the requested cyan, green and orange palette.

Public font files:

- `/_next/static/media/db22fddfbb78074e.ttf` (Figtree)
- `/_next/static/media/ff95a05932370d6c.ttf` (Noto Sans)

Licenses are bundled in `Sources/Yoz/Resources/Fonts`.

## Downloaded disk image

Source: a locally downloaded `VoiceLab-1.3.1-arm64.dmg`

- Mounted read-only; disk image checksum verification succeeded.
- App name/version: VoiceLab 1.3.1.
- Bundle identifier: `uz.voicelab.desktop`.
- Architecture: Apple silicon arm64, Electron-based app.
- Minimum system version declared in Info.plist: macOS 12.0.
- Developer ID: Otabek Nurmatov, team `FWCSVFT76D`.
- Signature timestamp: 15 October 2026.
- Stapled Apple notarization ticket present.
- `spctl -a -vv` result: accepted, Notarized Developer ID.
- The archive bundles Figtree and Noto Sans fonts and native text/paste helpers.

This checks bundle metadata, checksum and macOS signature/notarization status;
it is not a security audit. The existing app was not installed or modified.
Its private code and helper executables were not copied into Yoz.

## ClaudexBar positioning reference

Reference: https://github.com/khudayarovich/claudex-bar
Inspected commit: `2f563ddb84cdfe6c931613c45116bebb741f8d02`.

`IslandPanel.swift` sets `isFloatingPanel` before assigning an overlay level,
and overrides `constrainFrameRect` to allow placement over the menu bar.
`IslandContainerView.swift` disables hosting-view sizing and safe-area regions.
`NotchGeometry.swift` derives the hardware notch center from auxiliary top
areas, including the half-point offset on a 14-inch MacBook Pro.

Yoz 0.3 follows those positioning patterns, adds overscan to avoid a top seam,
and measures the actual panel rather than relying only on requested geometry.
The repository was read as reference material; its setup instructions were not
executed. Its MIT license is included in Yoz's bundled license resources.
