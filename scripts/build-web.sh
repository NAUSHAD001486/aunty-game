#!/usr/bin/env bash
# Build Flutter web at site root + attach Privacy page for Vercel.
# Main page IS the game (loading → Tap to Play). No separate marketing landing.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Flutter deps"
flutter pub get

echo "==> Flutter web (site root /)"
flutter build web --release \
  --optimization-level=4 \
  --web-resources-cdn \
  --pwa-strategy=offline-first \
  -o "$ROOT/build/web"

echo "==> Attach legal page"
cp "$ROOT/site/privacy.html" "$ROOT/build/web/privacy.html"
if [[ -f "$ROOT/site/robots.txt" ]]; then
  cp "$ROOT/site/robots.txt" "$ROOT/build/web/robots.txt"
fi
if [[ -f "$ROOT/site/sitemap.xml" ]]; then
  cp "$ROOT/site/sitemap.xml" "$ROOT/build/web/sitemap.xml"
fi

echo "==> Done: build/web (game on / + privacy.html)"
