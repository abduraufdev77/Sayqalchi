# Release downloads

The README exposes versioned DMG, EXE and portable ZIP links. Release assets belong
on GitHub Releases, not in Git history. Never publish an EXE just because it
cross-compiles: wait for the Windows workflow's native smoke and installer checks.

1. Keep `packaging/Info.plist` and `windows/Directory.Build.props` versions aligned.
2. Run `swift test`, the Windows core checks and `python3 scripts/audit-secrets.py --history`.
3. Push the release commit. The Windows workflow builds the installer and ZIP;
   wait for all checks and download its `windows-downloads` artifact.
4. On the Mac with the existing signing certificate, run `./scripts/package-dmg.sh`.
   Never commit or upload the certificate/private key. Verify the built app with
   `codesign --verify --deep --strict dist/Sayqalchi.app`.
5. Review Windows smoke screenshots and the release notes. Create the release
   against the exact checked commit; label unverified platform previews as prereleases.
6. Attach the DMG, Windows EXE, portable ZIP and platform checksum manifests.
   Verify all three downloads exist before publishing download buttons for a new version.

Signing remains platform-specific: the current macOS build uses the maintainer's
Apple Development identity and is not notarized; Windows preview binaries are not
Authenticode-signed. Developer ID/notarization and Windows code signing can be
added without embedding keys in source or packages. Local rebuilds must retain
the same macOS certificate and installed path to preserve Accessibility approval.

## Attach Windows artifacts without downloading them locally

After the Windows job succeeds, create and push the reviewed tag explicitly (a
draft GitHub release alone does not create the Git tag), then create the draft
release with the Mac DMG and checksum. Run **Attach verified Windows downloads**
from Actions with that successful run ID and release tag. This workflow checks the
build came from this repository's `main`, compares platform source against the tag,
verifies the artifact checksums and attaches the EXE/ZIP directly on GitHub.
It does not publish the draft. Publish only after all assets are present.
