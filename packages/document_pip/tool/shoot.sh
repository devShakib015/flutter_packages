#!/usr/bin/env bash
# Regenerates doc/popout.png, the pub.dev screenshot, so it is reproducible
# rather than hand-made.
#
#   packages/document_pip $ tool/shoot.sh
#
# Builds the example for the web, serves it, drives a real Chrome over the
# DevTools Protocol, and composites the two windows into one picture.
#
# Both halves are unretouched screenshots of the two live windows, taken with
# the example's shared clock paused so they show the same instant. See the note
# at the top of tool/shoot.js for why they cannot be captured simultaneously.
set -euo pipefail
cd "$(dirname "$0")/.."

PORT="${PORT:-8398}"
FRAMES=doc/frames/popout
RADIUS=18       # the pop-out's corners, in device pixels
MARGIN=64       # how far it sits from the page's bottom-right corner

echo "building the example for the web…"
(cd example && flutter build web --release >/dev/null 2>&1)

python3 -m http.server "$PORT" --bind 127.0.0.1 \
  --directory example/build/web >/dev/null 2>&1 &
SERVER=$!
trap 'kill "$SERVER" 2>/dev/null || true' EXIT
until curl -s -m 2 -o /dev/null "http://127.0.0.1:$PORT/"; do sleep 0.3; done

echo "capturing from http://127.0.0.1:$PORT …"
PORT="$PORT" node tool/shoot.js

echo "compositing…"
# Plain command substitution, not `read < <(...)`: magick's -format output has
# no trailing newline, so read returns non-zero at EOF and `set -e` kills the
# script right here — silently, because the failure looks like a clean exit.
PW=$(magick identify -format "%w" "$FRAMES/page.png")
PH=$(magick identify -format "%h" "$FRAMES/page.png")
QW=$(magick identify -format "%w" "$FRAMES/pip.png")
QH=$(magick identify -format "%h" "$FRAMES/pip.png")
echo "  page ${PW}x${PH}, pop-out ${QW}x${QH}"

# Round the pop-out's corners and give it a real shadow, so a dark window over a
# dark page still reads as a window in front rather than a pasted rectangle.
magick "$FRAMES/pip.png" \
  \( -size "${QW}x${QH}" xc:none -fill white \
     -draw "roundrectangle 0,0,$((QW-1)),$((QH-1)),$RADIUS,$RADIUS" \) \
  -alpha set -compose DstIn -composite \
  -compose Over \
  -bordercolor none -border 1 \
  -stroke '#ffffff30' -strokewidth 2 -fill none \
  -draw "roundrectangle 1,1,$((QW)),$((QH)),$RADIUS,$RADIUS" \
  \( +clone -background black -shadow 75x30+0+20 \) +swap \
  -background none -layers merge +repage -strip \
  "$FRAMES/pip-shadow.png"

# Place using the SHADOWED image's size, not the raw pop-out's: the shadow adds
# ~56px a side, and using the raw width pushed it off the right edge.
SW=$(magick identify -format "%w" "$FRAMES/pip-shadow.png")
SH_=$(magick identify -format "%h" "$FRAMES/pip-shadow.png")
# The example centres its column, so a window tall enough to hold the pop-out
# leaves dead space above it. Chop that rather than shrinking the window, which
# would push the pop-out over the content.
magick "$FRAMES/page.png" "$FRAMES/pip-shadow.png" \
  -geometry "+$((PW - SW - MARGIN))+$((PH - SH_ - MARGIN))" -composite \
  -gravity north -chop 0x150 \
  -resize 1200x -strip doc/popout.png

echo
echo "done:"
ls -lh doc/popout.png | awk '{print "  " $9 "  " $5}'
magick identify -format "  %wx%h\n" doc/popout.png
