#!/usr/bin/env bash
# Record the wrapped grid: a roll of 14 frames on three lines, keys walking
# across a line break and between lines, Home/End, and Enter on a wrapped
# frame. Usage: grid-wrap-demo.sh  (seed the lab first, see seed.sh)
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
eval "$(python3 "$HERE/scripts/lab.py" env)"
W="$HERE/lab-tools/result/bin/wtype"
ipc() { qs -p "$HERE/shell" ipc "$@" >/dev/null; }
cap() { ipc call caption display "$1" "$2"; }
key() { "$W" -k "$1"; sleep "${2:-0.35}"; }

ipc call grid close || true
"$HERE/scripts/record.sh" start grid-wrap
sleep 1.2
cap "A roll wider than the screen wraps onto more lines" 3400
sleep 1.2
ipc call grid open
sleep 2.4
cap "Right walks the roll, across the line break" 3200
sleep 0.6
for i in 1 2 3 4 5 6 7; do key Right; done
sleep 1.0
cap "Up and Down step between lines of the same roll" 3200
sleep 0.6
key Down 0.7; key Down 0.7; key Up 0.7
sleep 0.8
cap "Down again leaves the roll for the next one" 3000
sleep 0.5
key Down 0.9; key Up 0.9
sleep 0.8
cap "End is the last frame, Home the first" 3000
sleep 0.5
key End 1.0; key Home 1.0
sleep 0.8
cap "Enter opens a wrapped frame" 2600
sleep 0.5
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do key Right 0.2; done
sleep 0.8
key Return 2.6
sleep 2.0
"$HERE/scripts/record.sh" stop
