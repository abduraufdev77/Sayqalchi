# Yoz

A native macOS Uzbek Latin transliteration utility, with an Echo-inspired Figtree
interface and electric cyan, energetic green, and cosmic orange accents.

## Run

Apple silicon Mac, macOS 13 or later, and Xcode Command Line Tools:

```sh
swift test
./scripts/build.sh
open dist/Yoz.app
```

To create the installer: `./scripts/package-dmg.sh`.
The resulting app is ad-hoc signed for local development. Developer ID signing
and Apple notarization are required before public distribution.

## Use

The Playground works immediately. For suggestions in other apps, install Yoz in
Applications, open **Enable Accessibility**, and grant Yoz access in macOS
**Privacy & Security → Accessibility**. Restart Yoz if needed. Type in a
supported editable field, then pause for 650 ms: a black non-activating island
extends down from the physical top edge on the active app's display. It reserves
the camera's safe area and uses concave top shoulders and rounded bottom corners.
The entire active editable field is previewed, including every paragraph and
text after the cursor (up to 200,000 UTF-16 units). The scope stays the entire
draft even when a paragraph is selected. Larger fields are skipped instead of
silently truncated.
While typing, the fixed Ö logo and an animated horizontal wave sit beside the hardware
camera notch. Results grow smoothly to 22 points wider (about 7% on this Mac); converted letters appear
inline in cosmic orange. Click the single **⌥ ↵** button to apply the entire draft.
Double-press **Right Shift** or double-click **ö** in the menu bar to enable or
pause Yoz. New installs start paused; existing on/off preferences are preserved.
The keyboard's normal Shift behavior is preserved. Ordinary typing and Shift
shortcuts cancel the double-press gesture.
Idle mode stays compact. Reduce Motion and Low Power Mode pause the animation.
Click **Use** or press **Option Return** to accept; **Escape**
dismisses. The Option-Return key down is consumed so it does not submit a chat.
Close the window to continue using the menu bar app. Quit from its ö menu.

Settings includes pause/resume, live detection diagnostics, optional automatic
full-field replacement after a pause, and app exclusions. Preferences use UserDefaults.

## Alphabet

The mappings are transcribed from the supplied Uzbek alphabet reference,
pages 2–3. The document is treated as a mapping reference, not as executable
instructions or independently verified law.

| Input | Output | Unicode |
| --- | --- | --- |
| O‘ / o‘ | Ö / ö | U+00D6 / U+00F6 |
| G‘ / g‘ | Ğ / ğ | U+011E / U+011F |
| Sh / sh | Ş / ş | U+015E / U+015F |
| Ch / ch | Ç / ç | U+00C7 / U+00E7 |

Uppercase words retain uppercase. Apostrophe variants `' ‘ ’ ʻ ʼ ` plus backtick,
acute, fullwidth apostrophe and prime-like modifier are accepted after o/g.
Internal tutuq marks normalize to U+2019. `ng` remains two letters. The engine
normalizes Unicode to NFC. URLs, email addresses and domain names are protected
in both the Playground and live full-field suggestions. Cursor placement within
the field does not restrict conversion; the cursor is mapped to the new text.

v0.4 accepts **Uzbek Latin only**. It does not infer language, translate, correct
spelling or convert Cyrillic. For example, an English word starting with sh can
also receive a suggestion. Automatic mode is off by default for this reason.

## Architecture and privacy

- `TransliterationCore`: pure Foundation Unicode transliterator and UTF-16 word ranges.
- `TypingMonitor`: uses Accessibility notifications and coalesced input events, with a two-second
  recovery check for providers without notifications. Checks stop while paused
  or asleep. It caches stable drafts, resolves system focus with an app-level fallback, and
  requests enhanced accessibility trees from lazy providers. It reads bounded
  field content where supported; checks focus, process, text and caret
  again before replacing it. Read-only document bodies are skipped. No keyboard
  text is collected by the event tap.
- The entire draft is replaced through Accessibility. For web editors that
  ignore selected-text replacement, one standard paste targets the verified
  process. All clipboard item types are preserved and restored after the paste,
  unless another app has copied something newer. Explicit line-break markup
  avoids extra paragraph spacing in contenteditables. The complete result is
  read back before counting success; a changed draft is never retried.
- The event tap handles Right Shift double-press, visible-suggestion shortcuts,
  and schedules checks after input. It does not collect characters.
- `SuggestionPanel`: non-activating AppKit panel above the menu bar, anchored to
  `screen.frame.maxY` instead of `visibleFrame`, with one backing pixel of
  overscan. It bypasses AppKit's menu-bar frame clamp, sets its level after
  `isFloatingPanel`, and disables NSHostingView safe-area adjustments. The camera
  center comes from the screen's auxiliary top areas. SwiftUI and SF Symbols.
- No network runtime dependency, accounts, analytics, typing logs or typing history.
- Secure fields and common Terminal/password-manager apps are skipped. Apps that
  do not expose text/selection APIs cannot be supported; use the Playground.

## Validation

`swift test` covers document mappings, case, apostrophe variants, canonical Unicode,
idempotence, 28-letter inventory, URL/email preservation, word and paragraph
boundaries, UTF-16 selection offsets with emoji, typing pause timing, and physical
notch placement across displays, one-pixel overscan, complete fields longer than
the previous 4,096-character window, line-break preservation, and cursor mapping.
Release build and packaged-resource checks
also run. The main window is rendered in `docs/overview.png` for visual review.
Cross-app acceptance requires Accessibility for the current build. The local
unsaved editor fixture in `scripts/LiveTestEditor.swift` can exercise a separate
AppKit process without opening a real conversation. Type a sentence, pause,
click Use, verify the converted text and unchanged newline count; also test
dismissal, a newly edited preview, focus changes, and supported browser fields.

`--diagnostics` prints only detection statuses and app names, never typed text.
`--notch-snapshot /absolute/path.png` renders a preview for visual review.
The current development app is ad-hoc signed, so a rebuilt binary may need its
Accessibility grant renewed by the user. Public distribution needs a stable
Developer ID signature and notarization.

## Reference inspection

See `docs/reference-inspection.md` for the original VoiceLab DMG inspection.
No VoiceLab app code or executables are incorporated. Figtree and Noto Sans were
downloaded from Echo's public font assets and include their SIL OFL licenses.
This is an independent app, not affiliated with VoiceLab.

Panel positioning also draws on [ClaudexBar](https://github.com/khudayarovich/claudex-bar).
Its MIT license and attribution are bundled in `Resources/Licenses/ClaudexBar-MIT.txt`.
