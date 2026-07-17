#!/usr/bin/env bash
# Run Aunty on Chrome with a PERSISTENT profile + fixed port.
#
# Why: `flutter run -d chrome` normally uses a throwaway Chrome user-data-dir.
# That wipes localStorage + Firebase Auth IndexedDB on every stop/re-host, so
# anonymous playerId / totalScore look "reset" even though Firestore is fine.
#
# Usage:
#   bash scripts/run-web-chrome.sh
#   AUNTY_WEB_PORT=8080 bash scripts/run-web-chrome.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROFILE="${AUNTY_CHROME_PROFILE:-$HOME/.aunty-chrome-dev-profile}"
PORT="${AUNTY_WEB_PORT:-8080}"
mkdir -p "$PROFILE"

echo "==> Persistent Chrome profile: $PROFILE"
echo "==> Fixed origin:              http://localhost:$PORT"
echo "    Re-host with THIS script to keep the same anonymous player + totalScore."
echo "    (Plain 'flutter run -d chrome' resets identity every launch.)"
echo

exec flutter run -d chrome --release --web-port="$PORT" \
  --web-browser-flag="--user-data-dir=$PROFILE" \
  --web-browser-flag="--no-first-run" \
  --web-browser-flag="--no-default-browser-check"
