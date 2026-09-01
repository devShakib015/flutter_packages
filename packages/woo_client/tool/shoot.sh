#!/usr/bin/env bash
# Regenerates doc/storefront.png from the demo in storefront/, so the
# screenshot on pub.dev is reproducible rather than captured by hand.
#
#   packages/woo_client $ tool/shoot.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HERE/../storefront"
PORT="${PORT:-8401}"

echo "building the storefront for the web…"
(cd "$APP" && flutter build web --release >/dev/null)

python3 -m http.server "$PORT" --bind 127.0.0.1 \
  --directory "$APP/build/web" >/dev/null 2>&1 &
SERVER=$!
trap 'kill "$SERVER" 2>/dev/null || true' EXIT

until curl -s -m 2 -o /dev/null "http://127.0.0.1:$PORT/"; do sleep 0.3; done
echo "shooting from http://127.0.0.1:$PORT"
PORT="$PORT" node "$HERE/shoot.js"
