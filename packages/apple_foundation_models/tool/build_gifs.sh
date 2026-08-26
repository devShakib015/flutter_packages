#!/usr/bin/env bash
# Assembles PNG frames from tool/record_frames.dart into GIFs.
# Frames are 50ms apart, so -delay 5 plays back at the captured real speed.
set -euo pipefail
cd "$(dirname "$0")/.."

build() {
  local scene="$1"
  local dir="doc/frames/$scene"
  [ -d "$dir" ] || { echo "skip $scene (no frames)"; return; }
  echo "building $scene…"
  magick -delay 5 -loop 0 "$dir"/*.png -resize 720x -colors 128 \
    -layers Optimize "doc/$scene.gif"
}

build stream
build structured
build tool

echo
ls -lh doc/*.gif | awk '{print "  " $9 "  " $5}'
