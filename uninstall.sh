#!/usr/bin/env bash
# uninstall.sh — Remove MyWhi.app from /Applications and
# optionally purge the user data folder.

set -euo pipefail

DEST="/Applications/MyWhi.app"
DATA="$HOME/Library/Application Support/MyWhi"

pkill -f "MyWhi" >/dev/null 2>&1 || true
sleep 0.3

if [ -d "$DEST" ]; then
  rm -rf "$DEST"
  printf '\033[1;32m[uninstall]\033[0m Removed %s\n' "$DEST"
else
  printf '\033[1;33m[uninstall]\033[0m %s not present\n' "$DEST"
fi

if [ -d "$DATA" ]; then
  rm -rf "$DATA"
  printf '\033[1;32m[uninstall]\033[0m Removed %s\n' "$DATA"
fi

if [ -d "/tmp/mywhi" ]; then
  rm -rf "/tmp/mywhi"
  printf '\033[1;32m[uninstall]\033[0m Removed /tmp/mywhi\n'
fi

if [ -d "/tmp/hermes-dictate" ]; then
  rm -rf "/tmp/hermes-dictate"
  printf '\033[1;32m[uninstall]\033[0m Removed /tmp/hermes-dictate (legacy)\n'
fi

printf '\n[uninstall] Done.\n'
