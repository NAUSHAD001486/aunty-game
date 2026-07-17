#!/usr/bin/env bash
set -euo pipefail
export PATH="$PATH:$HOME/.pub-cache/bin:/usr/local/bin"
cd "$(dirname "$0")/.."

if ! firebase login:list 2>/dev/null | grep -q '@'; then
  echo ">>> Opening Firebase login (complete in browser)..."
  firebase login
fi

echo ">>> Configuring FlutterFire for aunty-b7c60..."
flutterfire configure --project=aunty-b7c60 --yes --platforms=android,ios,web,macos
echo ">>> Done. Check lib/firebase_options.dart"
