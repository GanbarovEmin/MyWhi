#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MyWhi"
APP_BUNDLE="$ROOT/dist/${APP_NAME}.app"

usage() {
  cat <<'EOF'
Usage: script/build_and_run.sh [--verify] [--logs]

Builds MyWhi.app with the project build.sh, stops any running copy, and opens
the freshly built bundle.
EOF
}

VERIFY=0
LOGS=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --verify) VERIFY=1 ;;
    --logs) LOGS=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

cd "$ROOT"

pkill -x "$APP_NAME" 2>/dev/null || true
"$ROOT/build.sh"
/usr/bin/open -n "$APP_BUNDLE"

if [[ "$VERIFY" == "1" ]]; then
  for _ in {1..30}; do
    if pgrep -x "$APP_NAME" >/dev/null; then
      echo "Verified: $APP_NAME is running"
      break
    fi
    sleep 0.5
  done
  pgrep -x "$APP_NAME" >/dev/null
fi

if [[ "$LOGS" == "1" ]]; then
  /usr/bin/log stream --info --predicate 'process == "MyWhi"'
fi
