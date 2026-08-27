#!/usr/bin/env bash
# Assembles the PNG frames written by tool/record_frames.dart into GIFs.
#
#   flutter test tool/record_frames.dart   # writes doc/frames/<scene>/*.png
#   ./tool/build_gifs.sh                   # writes doc/<scene>.gif
#
# Frames are recorded at 50ms. Taking every Nth and multiplying the delay by N
# keeps playback at real speed while cutting the file by roughly N.
set -euo pipefail
cd "$(dirname "$0")/.."

build() {
  local scene="$1" width="$2" colors="$3" every="$4"
  local dir="doc/frames/$scene"
  [ -d "$dir" ] || { echo "skip $scene (no frames)"; return; }
  echo "building $scene…"
  local picked=()
  local i=0
  for f in "$dir"/*.png; do
    if (( i % every == 0 )); then picked+=("$f"); fi
    i=$((i + 1))
  done
  magick -delay $((5 * every)) -loop 0 "${picked[@]}" \
    -resize "${width}x" -colors "$colors" -layers Optimize "doc/$scene.gif"
  echo "  doc/$scene.gif  $(du -h "doc/$scene.gif" | cut -f1)  (${#picked[@]} frames)"
}

build jump 460 48 4

echo
ls -lh doc/*.gif | awk '{print "  " $9 "  " $5}'
