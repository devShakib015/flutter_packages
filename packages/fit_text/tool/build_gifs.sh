#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="doc/frames/fitting"
[ -d "$SRC" ] || { echo "no frames — run the recorder first"; exit 1; }
# Recorded at 50ms; every 2nd frame at -delay 10 plays at real speed.
picked=(); i=0
for f in "$SRC"/*.png; do (( i % 2 == 0 )) && picked+=("$f"); i=$((i+1)); done
magick -delay 10 -loop 0 "${picked[@]}" -resize 460x -colors 64 -layers Optimize doc/fitting.gif
echo "  doc/fitting.gif  $(du -h doc/fitting.gif | cut -f1)  (${#picked[@]} frames)"
