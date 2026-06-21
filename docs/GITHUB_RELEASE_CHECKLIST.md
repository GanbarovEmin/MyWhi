# GitHub Release Checklist

MyWhi currently builds an ad-hoc signed macOS app and DMG with Sparkle update support. It is suitable for a public preview, but public distribution still needs a Developer ID certificate, hardened runtime review, and notarization.

## Before Release

- Run `swift test`.
- Run `./build-dmg.sh --install`.
- Open `/Applications/MyWhi.app`.
- Verify the right-click menu contains `Check for Updates...`.
- Verify microphone permission flow.
- Verify `Cmd+Option+D` starts/stops recording.
- Verify Settings opens from the desktop sidebar.
- Verify Accessibility warning appears only when auto-paste is enabled and permission is missing.
- Verify `appcast.xml` has a valid `sparkle:edSignature`.

## Build Artifacts

- App bundle: `dist/MyWhi.app`
- DMG: `dist/MyWhi-3.9.0.dmg`

`dist/` is gitignored. Attach the DMG to a GitHub Release and keep `appcast.xml` pointing at that release asset.

## Validation Commands

```bash
codesign --verify --verbose=2 dist/MyWhi.app
spctl --assess --type execute --verbose dist/MyWhi.app
hdiutil verify dist/MyWhi-3.9.0.dmg
otool -L dist/MyWhi.app/Contents/MacOS/MyWhi | grep Sparkle
```

`spctl` can reject ad-hoc signed local builds for public distribution. That is expected until Developer ID signing and notarization are configured.
