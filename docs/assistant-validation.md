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
