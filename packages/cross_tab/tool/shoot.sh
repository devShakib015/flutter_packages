#!/usr/bin/env bash
# Regenerates doc/*.png, so the screenshots on pub.dev are reproducible rather
# than hand-captured.
#
#   packages/cross_tab $ tool/shoot.sh
#
# Builds the example for the web, serves it, drives headless Chrome over the
# DevTools Protocol, and cleans up after itself. Chrome's own --screenshot flag
# is not usable here: it waits for the page to go idle, and cross_tab keeps a
# heartbeat timer running by design, so that page never is.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
EXAMPLE="$HERE/../example"
PORT="${PORT:-8399}"

echo "building the example for the web…"
(cd "$EXAMPLE" && flutter build web --release >/dev/null)

python3 -m http.server "$PORT" --bind 127.0.0.1 \
  --directory "$EXAMPLE/build/web" >/dev/null 2>&1 &
SERVER=$!
trap 'kill "$SERVER" 2>/dev/null || true' EXIT

until curl -s -m 2 -o /dev/null "http://127.0.0.1:$PORT/"; do sleep 0.3; done
echo "shooting from http://127.0.0.1:$PORT"
PORT="$PORT" node "$HERE/shoot.js"
