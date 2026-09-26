#!/usr/bin/env bash
# Record the control centre's fixed list boxes: the sheet opens before the
# Wi-Fi scan finishes and keeps its height while fake networks arrive, the
# list scrolls by wheel, drag and keys with the connected network pinned,
# then Bluetooth and the notification centre do the same.
#
# Needs: `lab.py up`, `lab.py audio`, and the shell started with fake radios:
#   HNS_FAKE_WIFI=16 HNS_FAKE_BT=9 scripts/run.sh start
# Nothing here touches the host's radios: with the fakes on, every Wi-Fi and
# Bluetooth control in the sheet drives services/FakeRadios.qml.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
eval "$(python3 "$HERE/scripts/lab.py" env)"
P="$HERE/lab-tools/result/bin/hns-lab-scroll"
K="$HERE/lab-tools/result/bin/hns-lab-keys"
WF="$HERE/lab-tools/result/bin/wf-recorder"
OUT="$HERE/recordings/hyprnav-cc-lists.mp4"
ipc() { qs -p "$HERE/shell" ipc call "$@" >/dev/null; }
cap() { ipc caption display "$1" "$2"; }
at() { "$P" --at "$1" "$2" >/dev/null 2>&1; }
wheel() { "$P" --at "$1" "$2" "${@:3}" >/dev/null 2>&1; }
click() { "$P" --at "$1" "$2" --click left >/dev/null 2>&1; }
drag() { "$P" --at "$1" "$2" --drag "$3" "$4" "$5" --delay 14 >/dev/null 2>&1; }
keys() { "$K" "$@" >/dev/null; }

ipc qs close; ipc center close; ipc center clear; ipc center dnd true; ipc qs fakeReset
at 1300 500
sleep 1.2
mkdir -p "$HERE/recordings"
"$WF" -o "${HNS_SCREEN:-TEST}" -f "$OUT.raw.mp4" -y -r 60 -c libx264 -p crf=18 -p preset=veryfast >/tmp/hns-cc-record.log 2>&1 &
REC=$!
sleep 0.8

cap "Wi-Fi: the sheet opens before the scan; its height never moves" 4600
ipc qs section wifi; sleep 4.2
cap "Rows scroll inside a fixed box; the connected network stays pinned" 5200
at 250 900; sleep 0.4
wheel 250 900 1; sleep 0.7
wheel 250 900 1; sleep 0.7
wheel 250 900 2; sleep 1.0
drag 250 880 250 1000 24; sleep 0.9
cap "Keys while the list has focus: Down, End, Home" 3600
keys tap:Down; sleep 0.5; keys tap:Down; sleep 0.6; keys tap:End; sleep 0.9; keys tap:Home; sleep 1.0

cap "Bluetooth: devices arrive while searching; same box, same height" 4800
ipc qs section bluetooth; sleep 0.9
at 200 1043; sleep 0.3; click 200 1043; sleep 3.2
wheel 250 900 2; sleep 1.2
ipc qs close; sleep 0.6

cap "Notification centre: a fixed box too, filling while open" 5000
ipc center open; sleep 0.8
for i in 1 2 3 4 5 6 7 8 9; do
  case $((i % 3)) in 0) a=Build; s="cargo check finished"; b="rujit: 0 errors, $i warnings";; 1) a=Mail; s="Anna"; b="Lunch at $((i % 3 + 12))?";; 2) a=Calendar; s="Standup in 5 minutes"; b="Room 4B";; esac
  notify-send -a "$a" "$s" "$b"; sleep 0.28
done
sleep 0.8
wheel 250 700 2; sleep 0.9; wheel 250 700 -2; sleep 1.0
ipc center close; sleep 0.8

kill -INT "$REC"; wait "$REC" 2>/dev/null || true
ipc center dnd false
ffmpeg -v error -y -i "$OUT.raw.mp4" -c:v libx264 -pix_fmt yuv420p -crf 20 -preset slow -movflags +faststart "$OUT" && rm -f "$OUT.raw.mp4"
ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$OUT"
