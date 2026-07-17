#!/usr/bin/env bash
# Build Flutter web at site root + attach Privacy page for Vercel.
# Main page IS the game (loading → Tap to Play). No separate marketing landing.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Vercel (and some CI) may not have Flutter on PATH — install a shallow SDK.
ensure_flutter() {
  if command -v flutter >/dev/null 2>&1; then
    return 0
  fi
  local FLUTTER_DIR="${FLUTTER_HOME:-$HOME/flutter}"
  echo "==> Flutter not found — cloning stable SDK to $FLUTTER_DIR"
  if [[ ! -x "$FLUTTER_DIR/bin/flutter" ]]; then
    git clone https://github.com/flutter/flutter.git \
      -b stable --depth 1 "$FLUTTER_DIR"
  fi
  export PATH="$FLUTTER_DIR/bin:$PATH"
  flutter config --no-analytics >/dev/null 2>&1 || true
  flutter precache --web
}

ensure_flutter

echo "==> Flutter deps"
flutter pub get
flutter config --enable-web >/dev/null 2>&1 || true

echo "==> Flutter web (site root /)"
flutter build web --release \
  --optimization-level=4 \
  --web-resources-cdn \
  --pwa-strategy=offline-first \
  -o "$ROOT/build/web"

# Fail the deploy if Firebase web plugins were not registered (causes
# PlatformException channel-error / dead Offer+Winner streams on live).
REGISTRANT="$(find "$ROOT/.dart_tool/flutter_build" -name web_plugin_registrant.dart 2>/dev/null | head -1 || true)"
if [[ -z "$REGISTRANT" ]] || ! grep -q 'firebase_core_web' "$REGISTRANT"; then
  echo "ERROR: firebase_core_web missing from web_plugin_registrant.dart"
  echo "       path: ${REGISTRANT:-<not found>}"
  exit 1
fi
echo "==> Web plugin registrant OK (Firebase included)"

echo "==> Attach legal page"
cp "$ROOT/site/privacy.html" "$ROOT/build/web/privacy.html"
if [[ -f "$ROOT/site/robots.txt" ]]; then
  cp "$ROOT/site/robots.txt" "$ROOT/build/web/robots.txt"
fi
if [[ -f "$ROOT/site/sitemap.xml" ]]; then
  cp "$ROOT/site/sitemap.xml" "$ROOT/build/web/sitemap.xml"
fi

echo "==> Done: build/web (game on / + privacy.html)"
