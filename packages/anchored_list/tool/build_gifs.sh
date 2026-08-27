#!/usr/bin/env bash
# Assembles the PNG frames written by tool/record_frames.dart into GIFs.
#
#   flutter test tool/record_frames.dart   # writes doc/frames/<scene>/*.png
#   ./tool/build_gifs.sh                   # writes doc/<scene>.gif
#
# Frames are recorded at 50ms, so -delay 5 (hundredths) plays back at real speed.
set -euo pipefail
cd "$(dirname "$0")/.."

build() {
  local scene="$1" width="$2" colors="$3"
  local dir="doc/frames/$scene"
  [ -d "$dir" ] || { echo "skip $scene (no frames)"; return; }
  echo "building $scene…"
  magick -delay 5 -loop 0 "$dir"/*.png \
    -resize "${width}x" \
    -colors "$colors" \
    -layers Optimize \
    "doc/$scene.gif"
  echo "  doc/$scene.gif  $(du -h "doc/$scene.gif" | cut -f1)"
}

build jump   460 128
build scroll 460 128

echo
echo "done:"
ls -lh doc/*.gif | awk '{print "  " $9 "  " $5}'
