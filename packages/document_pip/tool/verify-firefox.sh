#!/usr/bin/env bash
# Re-runs the Firefox verification behind this package's browser-support claim.
#
#   packages/document_pip $ tool/verify-firefox.sh          # current stable
#   packages/document_pip $ tool/verify-firefox.sh 151.0    # the declared floor
#
# Firefox is not installed by this script into /Applications: the build is
# downloaded to ~/.cache/firefox-verify and run from there, with a throwaway
# profile, so nothing on the machine changes.
#
# Firefox speaks WebDriver BiDi rather than the DevTools Protocol, so this
# shares nothing with tool/shoot.sh beyond the idea.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-latest}"
PORT="${PORT:-8399}"
CACHE="$HOME/.cache/firefox-verify"
mkdir -p "$CACHE"

if [ "$VERSION" = "latest" ]; then
  URL="https://download.mozilla.org/?product=firefox-latest-ssl&os=osx&lang=en-US"
  VERSION=$(curl -sIL -o /dev/null -w '%{url_effective}' "$URL" \
            | sed -n 's|.*/releases/\([^/]*\)/mac/.*|\1|p')
  echo "latest stable is $VERSION"
fi
APP="$CACHE/$VERSION/Firefox.app"

if [ ! -d "$APP" ]; then
  DMG="$CACHE/ff-$VERSION.dmg"
  [ -f "$DMG" ] || {
    echo "downloading Firefox $VERSION…"
    curl -sfL --max-time 900 -o "$DMG" \
      "https://ftp.mozilla.org/pub/firefox/releases/$VERSION/mac/en-US/Firefox%20$VERSION.dmg"
  }
  echo "extracting…"
  MP=$(hdiutil attach -nobrowse -readonly -mountrandom /tmp "$DMG" \
       | grep -o '/tmp/dmg\.[^ ]*' | tail -1)
  mkdir -p "$CACHE/$VERSION"
  cp -R "$MP/Firefox.app" "$CACHE/$VERSION/"
  hdiutil detach "$MP" -quiet
fi

echo "building the example for the web…"
(cd example && flutter build web --release >/dev/null 2>&1)

python3 -m http.server "$PORT" --bind 127.0.0.1 \
  --directory example/build/web >/dev/null 2>&1 &
SERVER=$!
trap 'kill "$SERVER" 2>/dev/null || true' EXIT
until curl -s -m 2 -o /dev/null "http://127.0.0.1:$PORT/"; do sleep 0.3; done

FIREFOX_APP="$APP" APP_URL="http://127.0.0.1:$PORT/" node tool/verify-firefox.mjs
