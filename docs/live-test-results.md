# Yoz validation

## Version 0.4.2

- 27 automated tests pass. New checks cover equal screen coordinates across
  compact/result frames, result-body alignment with the band, external-display
  origins, backing scales, and AppKit's whole-point rounding.
- Expansion adds 22 pt: compact 317 pt, result 339 pt on this Mac. The band has
  one 24 pt horizontal-padding token. The result body stays 269 pt wide and
  aligns with the logo's leading frame and waveform's trailing frame (35 pt
  result inset). Its text does not rewrap during the morph.
- The silhouette now interpolates explicitly in an AnimatableModifier. Result
  content fades in after 75 ms; collapse fades it out first. The persistent band
  is outside that resizing layer. Native canvas shrink waits for animation
  completion; older completion callbacks cannot interrupt a newer transition.
- Captured expansion states showed visible heights of 32.5, 86, and 182.5 pt.
  In processing, idle, result, and all three transition captures, the cyan logo's
  measured left edge stayed at screen x=622.5 pt and top y=978 pt; the waveform's
  right edge stayed at x=890 pt. Measurements include each capture's actual
  native panel origin and backing scale. Capture geometry is stored beside PNGs.
- This update changes notch presentation only. Previously verified full-draft
  conversion and Right Shift toggle behavior are unchanged.

## Version 0.4.1

- Processing keeps the same static Ö logo as idle and result states.
- The orbital indicator is removed. Only the right waveform is inside the
  animation timeline, which remains paused for idle, Reduce Motion and Low
  Power Mode.

## Version 0.4.0

- 24 automated tests pass, including precise inline highlight spans, protected
  addresses, double-press timing, held-key suppression, and interrupted gestures.
- Result width on this Mac is 368 pt (compact: 317 pt; previous result: 600 pt).
  Body type is 14 pt, with only converted letters highlighted in cosmic orange.
- One shared ⌥ ↵ control replaces the checkmark and separate keycap outlines.
- A persistent Ö/waveform strip occupies the camera-safe area in result mode.
  The result waveform settles after 1.1 seconds. A single SwiftUI hosting tree
  springs from the compact silhouette on a union canvas before the panel shrinks.
- Input notifications and coalesced keyboard/mouse events replace the 160 ms
  polling loop. A two-second watchdog recovers unsupported AX providers. Stable
  drafts skip repeat conversion. Pausing or sleeping cancels scheduled checks.
  Timeline animation stops while idle, in Reduce Motion, or in Low Power Mode.
- Right Shift double-press and double-clicking ö toggle the persisted enabled
  state. Shift shortcuts/other modifiers interrupt the keyboard gesture. New
  installs start paused; updates preserve the previous preference.
- Release-app CPU samples at rest reported 0.0%; resident memory was about 78 MiB.
  These short samples do not establish a battery-life guarantee.
- Live AX inspection confirmed the complete two-paragraph preview, enabled
  combined accept control, and persistent result strip. The user physically
  verified that double-pressing Right Shift pauses and re-enables Yoz.
  Menu-bar double-click still needs its own manual acceptance check.
- The web-editor fallback now uses one normal paste instead of rapid Unicode
  chunks. It provides plain text and escaped line-break markup and restores all
  previous clipboard item types unless a newer copy has occurred. Success is
  counted only after the entire resulting value matches the preview.
- Live rich-editor acceptance passed after activation stabilized: one click
  replaced both paragraphs of the complete two-paragraph draft, preserving the
  exact blank line and the separate read-only history. Native Select All in
  the verified editor includes paragraph boundaries that text-only AX ranges
  omit. The monitor read the complete value back before counting success.
- The automation tool rejects modifier-only key presses; the user confirmed
  both Right Shift toggles physically. Timing/chord rejection is also covered
  by automated tests. No Telegram message, email, or post was sent.

## Version 0.3.1

- 20 automated tests pass, including a complete two-paragraph draft,
  focus inside either paragraph, eight nested wrappers, a selected paragraph,
  unreadable editable roots, protected ancestors, and unrelated text controls.
- The monitor resolves the containing editor instead of returning the first
  editable paragraph. It prefers the editor's full value over a shorter
  paragraph-local character count. Selecting a paragraph keeps full-draft scope.
- A separate-process WKWebView fixture exposed two paragraph children inside
  one contenteditable textbox, alongside a separate read-only history element.
  The live Yoz notch displayed both paragraphs together and `Entire draft`.
- The initial live replacement check found that WebKit can report success for
  AXSelectedText without changing its value. A trial AXValue fallback changed
  both paragraphs but duplicated line breaks; that fallback was removed.
- The final build instead verifies the entire value after replacement and, only
  if the original draft, full selection, editor identity and foreground app are
  unchanged, tries bounded Unicode input. A partial or different result cannot
  trigger a second replacement.
- Final live verification of that fallback and native multi-paragraph cursor
  restoration is pending: macOS Secure Input became active during testing.
  Yoz pauses rather than attempting replacement in that state.
- The rich-editor fixture is local and unsaved. No message or email was sent.

## Version 0.3

- 15 automated tests pass. New coverage includes all paragraphs and text after
  the cursor, fields longer than 4,096 characters, Unicode cursor mapping, the
  hardware notch center, and top-edge overscan at different backing scales.
- The release app builds and recognizes the existing Accessibility grant.
- The actual AppKit panel reports level **27**, above menu-bar level **24**.
  On this Retina Mac the requested one-pixel overscan is rounded outward by
  AppKit to two pixels: screen top 982 pt, actual panel top 983 pt.
- Expanded, typing, and idle raster captures all have opaque black pixels at
  the first physically visible screen row, sampled across the center body.
  Native measurements are saved in `notch-*-layout.json` beside the captures.
- The compact typing indicator uses a rotating globe and a horizontal waveform;
  animation pauses when idle or when Reduce Motion is enabled.
- The preview fits its text height, has tighter padding, and gives long text a
  scrolling region up to 200 pt high. Use now has a bold checkmark and clearer
  shortcut glyphs.
- Full-field scope supports up to 200,000 UTF-16 units, including all paragraphs
  and text after the cursor. At this version, a deliberate selection limited scope (changed in 0.3.1). Read-only
  document bodies and protected inputs are excluded.
- The 0.3 signature, installer checksum and bundled MIT attribution verify.
- The final live multi-paragraph Use/cursor-restoration test is **pending**:
  computer use reported that the Mac was locked. The local unsaved test editor
  is prepared with two paragraphs and its cursor at the end of the first line.
  No Telegram message or email was sent during testing.

## Version 0.2

22 October 2026, Asia/Tashkent.

## Confirmed

- Release app builds and runs with the existing Accessibility grant on this Mac.
- 11 automated tests pass: character mapping, case, Unicode, URL protection,
  full-paragraph ranges, unchanged final words, pause invalidation, and physical
  top-edge geometry across displays.
- A real sentence typed in the separate-process local AppKit editor triggers
  “waiting for a pause” and then “suggestion ready” in the running monitor.
- The actual `Yoz Notch` accessibility window exposes the full source sentence,
  converted sentence, dismissal control, and an enabled **Use suggested text**
  button.
- Clicking **Use** changed `O'zbekcha yozish juda oson. Salom!` to
  `Özbekça yoziş juda oson. Salom!` in the separate editor.
- The editor reported 31 characters and **0 newlines** after replacement. Its
  text view retained focus. The monitor read the result back for confirmation.
- The replacement does not use the clipboard.
- The release app signature and DMG checksum verify successfully.

## Not yet confirmed

Global shortcut, Escape dismissal, automatic mode, and compatibility in specific
Telegram/mail/browser editors still need their own live acceptance checks.
Do not infer support in every custom editor from the AppKit test.

## Changes from 0.1

- The island touches the physical screen edge instead of floating below the
  menu bar, with a camera-safe top inset and Notchy-inspired shoulders.
- Manual suggestions preview the paragraph before the cursor after a 650 ms
  pause, including changes earlier than an unchanged last word.
- A visible **Use** button replaces the reviewed text without activating Yoz.
- Focus resolution uses system focus, application focus, and ancestor selection
  support. Enhanced accessibility trees are requested for lazy providers.
- Settings reports live detection status. Optional diagnostic console output
  contains app names/statuses, never the user's typed text.
- Closing a demo preview restores an already-ready live suggestion.
