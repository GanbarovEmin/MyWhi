#!/usr/bin/env bash
# build.sh — Build MyWhi.app from source.
#
# v2.0: WhisperKit-only. No Python venv, no transcribe.py.
# Steps:
#   1. Compile Swift with Swift Package Manager (WhisperKit dep fetched automatically)
#   2. Wrap the binary in a .app bundle
#   3. Ad-hoc codesign the bundle
#
# Output: dist/MyWhi.app

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_ROOT"

APP_NAME="MyWhi"
APP_BUNDLE="$PROJECT_ROOT/dist/${APP_NAME}.app"
SPARKLE_FRAMEWORK="$PROJECT_ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"

log() { printf '\033[1;34m[build]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[build]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[build]\033[0m %s\n' "$*" >&2; }

# --------------------------------------------------------- 1. Swift build
log "Building Swift (release)…"
swift build -c release

# Resolve the produced binary path. Swift 6.x can place it under
# .build/release/ or .build/<arch>-apple-macosx/release/.
BIN_PATH="$(swift build -c release --show-bin-path)/MyWhi"
if [ ! -x "$BIN_PATH" ]; then
  err "Built binary not found at $BIN_PATH"
  exit 1
fi
log "Binary: $BIN_PATH ($(du -h "$BIN_PATH" | awk '{print $1}'))"

# ----------------------------------------------------- 2. Wrap in .app bundle
log "Assembling .app bundle…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/MyWhi"
chmod +x "$APP_BUNDLE/Contents/MacOS/MyWhi"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BUNDLE/Contents/MacOS/MyWhi" 2>/dev/null || true

# -X strips extended attributes (com.apple.provenance, FinderInfo) which
# would otherwise break ad-hoc codesigning with "resource fork... not allowed".
cp -X "$PROJECT_ROOT/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Bundle any Resources/* (e.g. AppIcon.icns). transcribe.py is no longer
# included — v2.0 is WhisperKit-only.
for f in "$PROJECT_ROOT"/Resources/*; do
  if [ -f "$f" ]; then
    cp -X "$f" "$APP_BUNDLE/Contents/Resources/$(basename "$f")"
  elif [ -d "$f" ]; then
    COPYFILE_DISABLE=1 ditto --noextattr --noqtn "$f" "$APP_BUNDLE/Contents/Resources/$(basename "$f")"
  fi
done

if [ -d "$SPARKLE_FRAMEWORK" ]; then
  log "Bundling Sparkle.framework…"
  COPYFILE_DISABLE=1 ditto --noextattr --noqtn "$SPARKLE_FRAMEWORK" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
else
  err "Sparkle.framework not found at $SPARKLE_FRAMEWORK"
  err "Run: swift package resolve"
  exit 1
fi

# PkgInfo lets macOS recognize the bundle type.
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

# Strip xattrs (FinderInfo/resource forks) that break ad-hoc signing. On recent
# macOS versions, recursive xattr can leave Finder metadata on package dirs, so
# clear each item explicitly.
find "$APP_BUNDLE" -exec xattr -c {} + 2>/dev/null || true

# ---------------------------------------------------------- 3. Ad-hoc sign
log "Ad-hoc codesigning…"
codesign --force --deep --sign - "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --verbose=2 "$APP_BUNDLE" || warn "codesign verify emitted warnings (non-fatal for personal use)"

# ------------------------------------------------------------------ Done
log "Built: $APP_BUNDLE"
du -sh "$APP_BUNDLE"
echo
echo "Contents:"
find "$APP_BUNDLE" -type f | sort | sed "s|$APP_BUNDLE|.|"
