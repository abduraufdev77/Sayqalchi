# Sayqalchi for Windows — 0.6.0 preview

Windows 10 (1809 or later) / Windows 11, x64. The self-contained app includes
.NET; users do not need an SDK, account, API key or administrator access.
The first Windows release is a preview. macOS remains a separate native app.

## Install and use

Download the Windows EXE from the official GitHub release. Run it to install
Sayqalchi for your Windows user, or extract the portable ZIP and open
`Sayqalchi.exe`. The app starts paused on a fresh install.

1. Double-press **Right Shift** to enable it. The compact ö island sits flush
   against the top of the primary display. Double-click the tray icon also toggles it.
2. Type in an editable field and pause for 650 ms. Only the default service runs.
3. Review the compact result and press **Alt + Enter**, or click its combined
   button, to replace the captured draft. **Escape** dismisses the result.
4. Hover the island to reveal Format, Translate, Izohchi and Document. Switching
   tabs runs that tool for the current draft; it does not run every service.
5. Set the default in the main app's **Settings → Default service**. The active
   widget tab is green. The tray menu opens the main app and quits it.

Format preserves links, email addresses, paragraphs and Unicode. Changed spans
are orange. Translation uses anonymous MyMemory by default, or an explicitly
configured custom service. Uzbek Latin ↔ Cyrillic stays local. Izohchi previews
at most two meanings with one example each; More opens the complete parsed result.
Document reports counts and previews whitespace cleanup. Applying is explicit.

## Supported editors and limits

The Windows integration uses UI Automation on a dedicated worker thread. It reads
only a focused, enabled, non-password Edit/Document control that provides a writable
**ValuePattern**. This permits complete, verified replacement without injecting a
paste or selecting unrelated history. Standard Windows text boxes are covered by
an automated native integration check.

Custom editors without that writable pattern, some browser/contenteditable fields,
remote desktops, and apps running as administrator may not be accessible. They are
skipped; use the Playground and copy. This preview does not claim all Telegram,
Word or browser versions have been manually verified. Do not run the app as
administrator to work around an inaccessible editor.

Drafts longer than 200,000 UTF-16 units are rejected, not truncated. Replacement
rechecks foreground window, process, runtime element identity and the original
entire draft. A changed target is rejected. Password fields, terminal processes
and known password managers are excluded; Settings adds process exclusions.

## Credentials and privacy

- Format, Document and script conversion use no network.
- Only the default service runs after typing; other tabs process on demand.
- MyMemory requests contain text and language direction, with no shared token or
  email. The provider's limits apply and it may retain text. See its
  [usage limits](https://mymemory.translated.net/doc/usagelimits.php) and
  [terms](https://mymemory.translated.net/terms-and-conditions).
- Custom credentials are encrypted with Windows DPAPI for the current user,
  outside the installation at `%LOCALAPPDATA%\Sayqalchi\credential.bin`.
  Settings contain no key. No real `.env` file is copied into packages.
- HTTPS is required unless the user explicitly opts into HTTP for their custom
  service. HTTP exposes text and credentials; credentials are not forwarded through redirects.
- No typed-text log, clipboard history, analytics or cloud account.

The EXE is not yet Authenticode-signed. It may trigger a Windows reputation
warning. Verify the published SHA-256 digest and source; do not disable security
protections. Code signing is a separate distribution improvement.

## Build, test and package

Install the .NET 10 SDK and [Inno Setup 6](https://jrsoftware.org/isdl.php).
From a Windows PowerShell terminal in the repository:

```powershell
dotnet run --project windows/Sayqalchi.Core.Tests -c Release
dotnet build windows/Sayqalchi.Windows -c Release -r win-x64
./scripts/package-windows.ps1
./dist/windows-x64/Sayqalchi.exe --smoke-test
```

Packaging creates `Sayqalchi-0.6.0-windows-x64.exe`, a portable ZIP and
`SHA256SUMS-windows.txt`. The installer is per user and does not request elevation;
it adds Start Menu / optional desktop shortcuts and an uninstaller. It does not
silently add startup tasks. Settings remain outside the app when updating.

The **Windows** GitHub Actions job builds on Windows, runs service/engine checks,
exercises UI Automation on a disposable editor, renders WPF screenshots, and tests
a silent install/uninstall. It uploads verified downloads and smoke diagnostics as
workflow artifacts. `shared/format-fixtures.json` also runs in the macOS suite.

From macOS/Linux the core checks run with .NET 10, and the app can be
cross-compiled with `-r win-x64`; native UI checks require Windows.
