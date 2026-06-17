#!/usr/bin/env bash
# uninstall.sh — Remove Hermes Dictate.app from /Applications and
# optionally purge the user data folder.

set -euo pipefail

DEST="/Applications/Hermes Dictate.app"
DATA="$HOME/Library/Application Support/HermesDictate"
RECORDINGS="/tmp/hermes-dictate"

pkill -f "HermesDictate" >/dev/null 2>&1 || true
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

if [ -d "$RECORDINGS" ]; then
  rm -rf "$RECORDINGS"
  printf '\033[1;32m[uninstall]\033[0m Removed %s\n' "$RECORDINGS"
fi

printf '\n[uninstall] Done.\n'
printf 'The venv at ~/Documents/Hermes.Dictate/venv/ is left in place.\n'
printf 'Remove it manually with: rm -rf ~/Documents/Hermes.Dictate/venv\n'
