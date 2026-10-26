# Sayqalchi on Android: implementation options

Android support is assessed, not shipped in 0.6.0. There is no APK download yet.
The Windows/macOS desktop watcher cannot be reused unchanged on a phone.

| Approach | Experience | Works across apps | Tradeoff |
| --- | --- | --- | --- |
| **Sayqalchi keyboard (recommended for live typing)** | Type, pause, review suggestions above the keyboard, tap to apply. Format / Translate / Izohchi badges replace the desktop tool strip. | In apps accepting the selected input method. | Users must choose Sayqalchi as their active keyboard; it cannot sit on top of Gboard as a second keyboard. A usable keyboard needs language switching, composition, selection, emoji, accessibility and layout work. |
| **Selected-text action (recommended first Android release)** | Select text → Sayqalchi → Format / Translate / Izohchi → return the result. Share-to-Sayqalchi and a small playground handle read-only sources. | Apps exposing Android's `ACTION_PROCESS_TEXT` selection menu or Share. | Deliberate selection rather than automatic suggestions. Some apps omit the action or only allow copying. |
| **Installable web playground** | Paste text, choose a service, copy the result. | Through explicit copy/paste. | No cross-app typing monitor, arbitrary app access or automatic replacement. |
| Accessibility service + floating overlay | Desktop-like monitoring and overlay. | Varies widely with app accessibility support and OS restrictions. | Broad permissions, fragile editor coverage and more background work. Not the recommended first implementation. |

## Recommended order

1. Ship a small native Kotlin companion: playground + `ACTION_PROCESS_TEXT` + Share receiver. Offline formatting and script conversion first; translation and dictionary lookup only when requested. No Accessibility or overlay permission.
2. Add an optional `InputMethodService` keyboard for people who want suggestions as they type. Keep the selected-text action for users who prefer their existing keyboard.
3. Reuse the same alphabet and script fixtures as desktop; run them in Android tests. Share the service contracts, direction whitelist, provider quotas and error semantics. Native host integrations remain separate.

## Keyboard behavior

- Suggestions live above the keyboard rather than covering the camera/notch.
- Debounce after a 650 ms typing pause; process only the configured default tool. Cancel stale requests when the input or language changes.
- Read only the active input connection. Do not scan other apps or log drafts.
- Skip password/PIN fields and respect an editor's private/no-learning hints. Start with local Format as the default. Explain online processing before users choose Translate or Izohchi as their default.
- `InputConnection` context can be limited. Replace the user's explicit selection, or a verified complete extracted draft. If the editor returns a partial passage, do not label it “Entire draft” or overwrite unseen text.
- Preserve composing text, selection and undo behavior; test Telegram, Gmail, browsers, Google Docs and office editors on real devices.
- Public translation needs no shared API key. Custom credentials belong in storage encrypted with an Android Keystore-backed key, never source files or the APK.
- Stop work when the keyboard hides. No background polling, clipboard history or idle animations.

## Platform sources

- [Android: create an input method](https://developer.android.com/develop/ui/views/touch-and-input/creating-input-method)
- [InputConnection](https://developer.android.com/reference/android/view/inputmethod/InputConnection)
- [ACTION_PROCESS_TEXT and EXTRA_PROCESS_TEXT_READONLY](https://developer.android.com/reference/android/content/Intent#ACTION_PROCESS_TEXT)
- [Receive simple data from other apps](https://developer.android.com/training/sharing/receive)
- [Android Keystore](https://developer.android.com/privacy-and-security/keystore)
