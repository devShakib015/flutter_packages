#!/usr/bin/env bash
# Assembles the frames recorded by example/lib/record.dart into the README GIF.
#
# Unlike the other packages here, the frames come from a real foregrounded run
# rather than `flutter test`, because Apple refuses image generation to a
# backgrounded app — so the app records itself.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="/private/tmp/claude-501/-Users-devshakib-Projects/422a40fb-c07d-49d0-9ec0-e5bf2bdb790d/scratchpad/ai_frames"
[ -d "$SRC" ] || { echo "no frames at $SRC — run the recorder first"; exit 1; }
mkdir -p doc
# Frames are captured when an image arrives, not on a timer, so there are only
# a handful and each one is a real step in the run. Held for 1.2s apiece.
magick -delay 120 -loop 0 "$SRC"/*.png -resize 460x -colors 64 -layers Optimize doc/streaming.gif
echo "  doc/streaming.gif  $(du -h doc/streaming.gif | cut -f1)  ($(ls "$SRC"/*.png | wc -l | tr -d " ") frames)"
