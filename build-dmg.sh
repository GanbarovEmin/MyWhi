#!/usr/bin/env bash
# build-dmg.sh — Build MyWhi.app, create .dmg, install to /Applications
#
# Usage: ./build-dmg.sh [--install]
#   --install   Also install to /Applications (requires sudo for DMG mount)

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_ROOT"

APP_NAME="MyWhi"
VERSION="3.9.0"
DIST_DIR="$PROJECT_ROOT/dist"
APP_BUNDLE="$DIST_DIR/${APP_NAME}.app"
DMG_PATH="$DIST_DIR/${APP_NAME}-${VERSION}.dmg"
STAGING="$DIST_DIR/staging"
SPARKLE_FRAMEWORK="$PROJECT_ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"

log() { printf '\033[1;34m[build]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[build]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[build]\033[0m %s\n' "$*" >&2; }

# ----------------------------------------------------------- 1. Build .app
log "Building Swift (release)…"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/MyWhi"
if [ ! -x "$BIN_PATH" ]; then
  err "Built binary not found at $BIN_PATH"
  exit 1
fi
log "Binary: $BIN_PATH ($(du -h "$BIN_PATH" | awk '{print $1}'))"

log "Assembling .app bundle…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/MyWhi"
chmod +x "$APP_BUNDLE/Contents/MacOS/MyWhi"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BUNDLE/Contents/MacOS/MyWhi" 2>/dev/null || true
cp -X "$PROJECT_ROOT/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
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
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

find "$APP_BUNDLE" -exec xattr -c {} + 2>/dev/null || true

log "Ad-hoc codesigning…"
codesign --force --deep --sign - "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --verbose=2 "$APP_BUNDLE" || warn "codesign verify warnings (non-fatal)"
log "Built: $APP_BUNDLE ($(du -sh "$APP_BUNDLE" | awk '{print $1}'))"

# -------------------------------------------------------------- 2. Create DMG
log "Creating DMG…"
rm -rf "$STAGING"
mkdir -p "$STAGING"
COPYFILE_DISABLE=1 ditto --noextattr --noqtn "$APP_BUNDLE" "$STAGING/$APP_NAME.app"

# Create a symlink to /Applications (classic DMG shortcut)
ln -s /Applications "$STAGING/Applications"

# Create DMG using hdiutil
log "Running hdiutil…"
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    -size 200m \
    "$DMG_PATH" 2>&1

rm -rf "$STAGING"
log "Created: $DMG_PATH ($(du -h "$DMG_PATH" | awk '{print $1}'))"

# -------------------------------------------------------------- 3. Install (optional)
if [ "${1:-}" = "--install" ]; then
    log "Installing to /Applications…"
    # Remove old version if exists
    if [ -d "/Applications/$APP_NAME.app" ]; then
        rm -rf "/Applications/$APP_NAME.app"
        log "Removed old /Applications/$APP_NAME.app"
    fi
    COPYFILE_DISABLE=1 ditto --noextattr --noqtn "$APP_BUNDLE" "/Applications/$APP_NAME.app"
    log "Installed: /Applications/$APP_NAME.app"
fi

# ------------------------------------------------------------------ Done
echo ""
log "────────────────────────────────────────────"
log " MyWhi v${VERSION} built successfully!"
log " App:      $APP_BUNDLE"
log " DMG:      $DMG_PATH"
if [ "${1:-}" = "--install" ]; then
    log " Installed: /Applications/$APP_NAME.app"
fi
log "────────────────────────────────────────────"
