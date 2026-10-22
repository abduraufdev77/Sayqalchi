# Yoz 0.5.0 preview validation

The stable **v0.4.2** release was published before assistant development, with
its original DMG and checksum. It remains a formatter-only release.

## Automated checks

35 tests pass, including the original 27 regressions and eight assistant tests:

- All six translation language pairs and the authenticated request schema.
- Full Unicode paragraphs preserved in requests and streamed results.
- No usable result for truncated streams, service errors, or rejected keys.
- HTTPS default, explicit HTTP opt-in, and no credentials/query in service URLs.
- Four dictionary meanings extracted; compact results contain two meanings and
  at most one example each; unrelated page content is excluded.
- Long dictionary queries and oversized translation drafts rejected intact.
- Spacing cleanup preserves indentation and blank lines and is idempotent.

## Render checks

Native app captures were inspected for Format, Translate, compact Izohchi,
expanded Izohchi and Document. The persistent Ö/waveform band remains centered
above the toolbar. Compact entries show two meanings; More opens the larger
view with all meanings and one example per meaning. The source remains linked.
Only synthetic drafts are used in the capture workflow.

## Service checks

Izoh.uz returned its public `jamoa` entry without authentication. Its current
HTML was parsed successfully in the native app, producing four meanings.
Savodxon returned HTTP 403 to automated retrieval; it is offered as a browser
link, with no claim of an undocumented API integration.

The configured service returned its supported-language catalog with the user's
API key. After the user explicitly approved HTTP for this development service,
all six directions completed live: Uzbek ↔ English, Uzbek ↔ Russian, and Uzbek
Latin ↔ Cyrillic. The two-paragraph Uzbek→English test preserved its blank line.
Sample language translations completed in roughly 0.8–1.6 seconds; deterministic
script conversions completed in roughly 0.03–0.04 seconds. These samples are not
throughput guarantees.

HTTPS on the supplied port failed protocol negotiation; the endpoint serves
plain HTTP. The app requires explicit HTTP opt-in and never silently downgrades
HTTPS or disables certificate validation. No API key is committed or bundled.

## Replacement safeguards and remaining manual checks

The original full-draft formatter's AppKit/WebKit replacement checks are recorded
in [live-test-results.md](live-test-results.md). The assistant reuses that path
and additionally compares the captured full draft and editor before applying.
Changing the draft requires Refresh. Manual input can be copied, and cannot
replace an unrelated editor. Only complete translation streams can be applied.

The native query field was exercised through UI automation: entering `jamoa`
and clicking Find meaning returned the live four-meaning entry. Compact and
expanded layouts were also captured and inspected.

Source-language and target-language popovers were exercised in the native UI,
including Russian selection, swapping the pair, choosing English, and translating
the two-paragraph synthetic draft. The widget showed the completed English result
with both paragraphs intact and rounded Copy/More controls.

Physical hover timing and assistant replacement in Telegram/Office still require
live acceptance with those editors; they are not recorded as verified here.

The build is ad-hoc signed for local preview, not Developer-ID signed or notarized.

## Hover collapse update (build 9)

The hover close now ignores duplicate geometry targets while a resize is in
flight. This preserves the native canvas until the silhouette finishes shrinking;
reversing hover preserves the current canvas as well. A bounded cleanup restores
the small native window after the animation. Expansion and collapse both use a
0.46-second spring response. Low Power Mode pauses the continuous waveform but
keeps the brief resize fluid; the explicit Reduce Motion preference still applies.

Native collapse captures show intermediate silhouette heights of approximately
320 → 132 → 43 → 33 points. These use the same close path as hover exit, including
the assistant's immediate and debounced updates. The existing 35 tests pass.

## Automatic preparation update (build 10)

A stable focused draft now prepares Format, Translate, Izohchi and Document in
parallel after the existing 650 ms pause detector. Format and Document are local;
the configured translation service receives the full draft, and Izoh.uz receives
only the selected phrase or the word at the cursor. Manual input uses the same
pause delay. Pausing Yoz, changing text/focus, and entering protected editors
invalidate pending work. Incomplete streams cannot be applied or copied.

Tabs share one prepared snapshot. Switching tabs or closing/reopening the hover
panel retains completed results; cursor-only movement reuses translation. New
typing invalidates Use immediately. Applying a result suppresses retranslating the
inserted text until a real edit occurs. Background work continues while a hover
panel collapses, and More retains the larger view for reading.

The native synthetic check processed a two-paragraph draft through all four tools
without pressing a processing button. Its English translation preserved the blank
line; the caret word `jamoa` returned four meanings, with two in the compact view.
Captures were inspected for every tab. The language badges are 28 points tall;
promotional headings, explanatory body copy, and processing action buttons were
removed. Explicit copy and replacement controls remain.

45 automated tests pass. New tests cover manual debounce, all-tab preparation,
latest-language selection, cancellation, stale-result protection, pause handling,
caret-only reuse, cached tabs, applied-text suppression, and dictionary query scope.


## Default service and permission recovery (build 11)

Supersedes build 10's all-tab preparation: only the configured default runs with
the notch collapsed (Format initially). Opening another tab runs only that tool;
leaving cancels its unfinished request. Completed results remain cached for the
unchanged draft. The persistent default is configured in the main Settings page,
with green badges; the notch's active tab is also green.

Permission recovery runs independently of suggestion polling, including while
paused. A newly granted permission installs the event tap without restarting;
disabled taps are re-enabled and invalid taps are recreated. Right Shift uses
its device-specific modifier bit and ignores Left Shift and modifier chords.
The build script prefers an installed Developer ID or Apple Development signing
identity so the designated requirement survives rebuilds. Ad-hoc signing remains
an explicit fallback when no identity exists. Moving from an older ad-hoc build
requires approving the newly signed app once through macOS Settings.


Validation: 48 automated tests pass, including no network requests with Format
as default, on-demand requests, cancellation when leaving a service, persistent
default selection, cache reuse, and physical-key flag/chord handling. The running
certificate-signed app reports Ready to write and Connected · shortcut active.
The default Format badge was visually checked in Settings. Two rebuilt binaries
have identical certificate-based designated requirements. The DMG checksum,
image integrity, and strict bundle signature verification pass.


## Automatic result presentation (build 12)

A completed result from the default service now expands the notch automatically,
without hover. It stays open for Option Return, Escape, or the close button;
hover exit (including an already scheduled exit) cannot dismiss it. New typing
collapses the result and invalidates Use immediately. Completed translations open
only after the final stream event. Errors also become visible. Dismissal survives
caret movement and the unchanged draft; a fresh edit allows the next result.
Unchanged formatter output does not produce a replacement popup. Other services
still run only when opened, unless configured as default.

Validation: all 51 tests pass. The native synthetic check no longer calls open()
after receiving its stable sample draft: it reports visible=true, pinned=true,
and canApply=true. Format and live Translate screenshots were inspected with
the two-paragraph result and combined Option Return accept button. The latest
DMG checksum and strict app signature checks pass. The UI automation could edit
the separate local editor but could not bring it to the foreground, so the
physical cross-app Option Return action was not revalidated in this check.


## Compact automatic results (build 13)

Automatic results use the original band width plus 22 points (339 points on the
185-point notch), with content-driven height capped for long drafts. The compact
view shows the result, Copy, More, dismiss, and the combined Option Return button.
It omits the toolbar and fixed-height empty area. Hover expands the full tools;
leaving smoothly returns to the pinned compact result. More opens the large detail
view. Formatting retains orange changed-letter highlights; translations are orange.
All 52 tests pass, including compact/hover/detail transitions and acceptance state.

Native short-result captures confirm a 339 × 132 point window for both Format
and Translate, with 269 points of content width. The sample `shahar` produced
`şahar` and `city`; the accept button remains available without hover. Strict
signature and DMG checksum verification passed.
