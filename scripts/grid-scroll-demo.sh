#!/usr/bin/env bash
# Record the scrolling grid: a stack of rolls taller than the window, opening
# already scrolled to the current frame, keys walking it with the ring kept in
# view, the wheel scrolling without touching the selection, the soft edges and
# the right-hand indicator, and Enter on a frame in a scrolled position.
# Usage: grid-scroll-demo.sh   (seed the lab first, see seed.sh; the stack must
# exceed the viewport, e.g. a 32-frame roll plus four smaller ones)
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
eval "$(python3 "$HERE/scripts/lab.py" env)"
W="$HERE/lab-tools/result/bin/wtype"
S="$HERE/lab-tools/result/bin/hns-lab-scroll"
ipc() { qs -p "$HERE/shell" ipc call "$@" >/dev/null; }
cap() { ipc caption display "$1" "$2"; }
key() { "$W" -s 120 -k "$1"; sleep "${2:-0.35}"; }
# Wheel clicks with the pointer parked off the frames, so nothing hovers.
wheel() { "$S" --at 1800 500 --delay "${2:-70}" $1 >/dev/null 2>&1; }

ipc grid close || true
sleep 0.6
"$HERE/scripts/record.sh" start grid-scroll
sleep 1.0
cap "A stack of rolls taller than the screen" 3000
sleep 2.0
ipc grid open
sleep 2.2
cap "It opens already scrolled to the frame you are in" 3200
sleep 2.8
cap "Up walks back up the stack and it slides down" 3000
sleep 1.0
for i in 1 2 3 4 5 6; do key Up 0.55; done
sleep 1.0
cap "Down walks on; the ring never leaves the viewport" 3200
sleep 1.0
for i in 1 2 3 4 5 6 7 8 9 10; do key Down 0.45; done
sleep 1.2
# Back into the middle of the stack, where both edges have content.
for i in 1 2 3; do key Up 0.5; done
sleep 0.8
cap "The wheel scrolls it without moving the selection" 3400
sleep 1.2
wheel "-1 -1 -1" 110
sleep 1.6
wheel "1 1" 110
sleep 1.8
cap "Soft edges where the stack continues, a hair on the right for the position" 4200
sleep 1.4
wheel "-1" 110
sleep 2.4
cap "Enter opens the frame from wherever it sits" 3000
sleep 1.4
key Return 2.6
sleep 1.6
"$HERE/scripts/record.sh" stop
OUT="$HERE/recordings/grid-scroll.mp4"
ffmpeg -v error -y -i "$OUT" -c:v libx264 -pix_fmt yuv420p -crf 20 -preset slow -movflags +faststart "$OUT.web.mp4" && mv "$OUT.web.mp4" "$OUT"
ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$OUT"
