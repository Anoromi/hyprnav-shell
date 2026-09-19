#!/usr/bin/env bash
# Temporary slots and the grid palette, recorded in the lab.
# Requires: lab up with the dev daemon, seed.sh applied, shell running.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
eval "$(python3 "$HERE/scripts/lab.py" env)"
W="$HERE/lab-tools/result/bin/wtype"
say()  { qs -p "$HERE/shell" ipc call caption display "$1" "${2:-5000}" >/dev/null; }
ipc()  { qs -p "$HERE/shell" ipc call "$@" >/dev/null; }
key()  { "$W" -s 120 -k "$1"; }
typ()  { "$W" -d 45 -- "$1"; }
ctrlp(){ "$W" -M ctrl -k p -m ctrl; }
temps(){ hyprnav slot temps | python3 -c 'import json,sys; print("   ", [(t["env_id"], t["slot"], t["workspace_id"], t["empty_since"] is not None) for t in json.load(sys.stdin)])'; }

hyprctl dispatch 'hl.dsp.focus({ workspace = 1 })' >/dev/null
"$HERE/scripts/record.sh" start temp-slots
sleep 1.5
say "Temporary slots: frames without a number that clean themselves up." 6000
sleep 2
ipc grid open; sleep 1.6
say "Ctrl+P opens the palette for the selected frame and its roll." 5000
ctrlp; sleep 1.6
typ "run"; sleep 1.0
key Return; sleep 0.8
say "A temporary slot and a command to run in it." 4500
typ "kitty --title scratch-notes"; sleep 0.8
key Return; sleep 3.0
say "A new frame with no digit. The window stuck to it, the frame took its title." 6500
sleep 3
key End; sleep 1.2
say "Frame actions: rename it." 4000
ctrlp; sleep 1.0; typ "rename"; sleep 0.6; key Return; sleep 0.8
"$W" -M ctrl -k a -m ctrl; typ "Scratch"; sleep 0.4; key Return; sleep 2.5
say "Close its window. An empty temporary frame starts a 30 second timer." 6000
ctrlp; sleep 1.0; typ "close all"; sleep 0.6; key Return; sleep 3
echo "temps after close:"; temps
say "The timer shows on the frame. Nothing else to do." 5000
sleep 10
say "Still waiting..." 3000
# Wait for the reaper (30 s after the workspace emptied), up to 50 s.
for i in $(seq 1 50); do
  n=$(hyprnav slot temps | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')
  [ "$n" = 0 ] && break
  sleep 1
done
say "Gone. The workspace went back to the pool." 5000
sleep 5
echo "temps at end:"; temps
key Escape; sleep 1
"$HERE/scripts/record.sh" stop
OUT="$HERE/recordings/temp-slots.mp4"
ffmpeg -v error -y -i "$OUT" -c:v libx264 -pix_fmt yuv420p -crf 20 -preset slow -movflags +faststart "$OUT.web.mp4" && mv "$OUT.web.mp4" "$OUT"
ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$OUT"
