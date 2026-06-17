#!/usr/bin/env bash
# install.sh — Copy dist/Hermes Dictate.app to /Applications.
#
# Refuses to overwrite without --force.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$PROJECT_ROOT/dist/Hermes Dictate.app"
DEST="/Applications/Hermes Dictate.app"

if [ ! -d "$SRC" ]; then
  printf '\033[1;31m[install]\033[0m %s not found. Run ./build.sh first.\n' "$SRC" >&2
  exit 1
fi

if [ -d "$DEST" ] && [ "${1:-}" != "--force" ]; then
  printf '\033[1;33m[install]\033[0m %s already exists. Use --force to replace.\n' "$DEST" >&2
  exit 1
fi

# Quit any running instance so the bundle is not locked.
# Use a short timeout; pkill can hang on the sandboxed shell if nothing matches.
timeout 2 pkill -f "HermesDictate" >/dev/null 2>&1 || true
sleep 0.3

# Clear quarantine if present (uncommon for ad-hoc, harmless if missing).
xattr -dr com.apple.quarantine "$SRC" 2>/dev/null || true
xattr -cr "$SRC" 2>/dev/null || true

rm -rf "$DEST"
cp -R "$SRC" "$DEST"

printf '\033[1;32m[install]\033[0m Installed: %s\n' "$DEST"
ls -la "$DEST"
