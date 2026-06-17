#!/usr/bin/env bash
# build.sh — Build MyWhi.app from source.
#
# Steps:
#   1. Create venv (if missing) and install faster-whisper (fallback engine)
#   2. Compile Swift with Swift Package Manager (WhisperKit dep fetched automatically)
#   3. Wrap the binary in a .app bundle
#   4. Ad-hoc codesign the bundle
#
# Output: dist/MyWhi.app

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_ROOT"

PYTHON_BIN="/usr/local/bin/python3"
VENV_DIR="$PROJECT_ROOT/venv"
VENV_PY="$VENV_DIR/bin/python3"
APP_NAME="MyWhi"
APP_BUNDLE="$PROJECT_ROOT/dist/${APP_NAME}.app"

log() { printf '\033[1;34m[build]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[build]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[build]\033[0m %s\n' "$*" >&2; }

# ---------------------------------------------------------------- 1. venv
if [ ! -x "$VENV_PY" ]; then
  log "Creating venv at $VENV_DIR (--system-site-packages, inherits existing faster-whisper)"
  # --system-site-packages: reuses the working system Python 3.14 +
  # faster-whisper at the user site (Library/Python/3.14/...). Avoids the
  # broken tokenizers import in a fully-isolated fresh venv on Py 3.14.
  # We still do not touch the existing install: we only read from it.
  "$PYTHON_BIN" -m venv "$VENV_DIR" --system-site-packages
  "$VENV_PY" -m pip install --upgrade pip --quiet
else
  log "Venv exists at $VENV_DIR"
fi

# Make sure faster-whisper is reachable. If the system site lacks it,
# fall back to installing a private copy into the venv.
if ! "$VENV_PY" -c "import faster_whisper" >/dev/null 2>&1; then
  warn "faster-whisper missing in venv + system site; installing into venv…"
  "$VENV_PY" -m pip install faster-whisper
fi

"$VENV_PY" -c "import faster_whisper, ctranslate2; print('faster-whisper OK at', faster_whisper.__file__)"

# --------------------------------------------------------- 2. Swift build
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

# ----------------------------------------------------- 3. Wrap in .app bundle
log "Assembling .app bundle…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/MyWhi"
chmod +x "$APP_BUNDLE/Contents/MacOS/MyWhi"

# -X strips extended attributes (com.apple.provenance, FinderInfo) which
# would otherwise break ad-hoc codesigning with "resource fork... not allowed".
cp -X "$PROJECT_ROOT/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp -X "$PROJECT_ROOT/transcribe.py" "$APP_BUNDLE/Contents/Resources/transcribe.py"

# Bundle any other Resources/* (e.g. AppIcon.icns). Transcribe.py is handled
# above explicitly so we don't double-copy it.
for f in "$PROJECT_ROOT"/Resources/*; do
  if [ -f "$f" ]; then
    cp -X "$f" "$APP_BUNDLE/Contents/Resources/$(basename "$f")"
  fi
done

# PkgInfo lets macOS recognize the bundle type.
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

# Strip xattrs (com.apple.provenance, FinderInfo) that break ad-hoc signing.
xattr -cr "$APP_BUNDLE"

# ---------------------------------------------------------- 4. Ad-hoc sign
log "Ad-hoc codesigning…"
codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --verbose=2 "$APP_BUNDLE" || warn "codesign verify emitted warnings (non-fatal for personal use)"

# ------------------------------------------------------------------ Done
log "Built: $APP_BUNDLE"
du -sh "$APP_BUNDLE"
echo
echo "Contents:"
find "$APP_BUNDLE" -type f | sort | sed "s|$APP_BUNDLE|.|"
