#!/usr/bin/env bash
# Record the bar polish pass: an instant control centre, a smooth slider,
# click-away and Esc, the tray menu and notification centre rising from the
# bar, the sliding workspace pip and the OSD.
#
# Needs: `lab.py up`, `lab.py audio`, the shell started with
# HNS_BACKLIGHT=/tmp/hns-bl (see TESTING.md) and scripts/tray-test.py
# running. Pointer positions are for 1920x1080 with one tray item and four
# frames in the current roll. Nothing here touches networking: the Wi-Fi view
# is only looked at.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
eval "$(python3 "$HERE/scripts/lab.py" env)"
W="$HERE/lab-tools/result/bin/wtype"
P="$HERE/lab-tools/result/bin/hns-lab-scroll"
ipc() { qs -p "$HERE/shell" ipc call "$@" >/dev/null; }
cap() { ipc caption display "$1" "$2"; }
at() { "$P" --at "$1" "$2" >/dev/null 2>&1; }
click() { "$P" --at "$1" "$2" --click "${3:-left}" >/dev/null 2>&1; }
drag() { "$P" --at "$1" "$2" --drag "$3" "$4" "$5" --delay 12 >/dev/null 2>&1; }
BAR_X=22
TRAY_Y=${TRAY_Y:-768}
BELL_Y=${BELL_Y:-812}
CLUSTER_Y=${CLUSTER_Y:-900}
VOL_Y=${VOL_Y:-901}
BRIGHT_Y=${BRIGHT_Y:-1018}
PIP_Y=(0 24 58 90 122)

ipc qs close; ipc center close; ipc center clear; ipc center dnd false
ipc qs section sound; sleep 0.3; ipc qs close
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.45; wpctl set-mute @DEFAULT_AUDIO_SINK@ 0
echo 70 > /tmp/hns-bl/brightness
at 1200 400
sleep 1.5
"$HERE/scripts/record.sh" start hyprnav-bar-polish
sleep 0.8
cap "Control centre: opens on the next frame (0–3 ms, was 19–265 ms)" 4200
sleep 1.0
click $BAR_X $CLUSTER_Y; sleep 1.4
click $BAR_X $CLUSTER_Y; sleep 0.9
click $BAR_X $CLUSTER_Y; sleep 1.2

cap "Sliders follow the pointer 1:1 at 60 fps; the value turns Pencil" 4200
drag 300 $VOL_Y 390 $VOL_Y 60; sleep 0.3
drag 390 $VOL_Y 150 $VOL_Y 90; sleep 0.3
drag 150 $VOL_Y 320 $VOL_Y 60; sleep 0.4
drag 330 $BRIGHT_Y 180 $BRIGHT_Y 60; sleep 0.3
drag 180 $BRIGHT_Y 360 $BRIGHT_Y 60; sleep 0.8

cap "Wi-Fi shows the cached list at once; the scan waits a second" 3600
ipc qs section wifi; sleep 2.6
ipc qs section sound; sleep 0.6

cap "Click anywhere else and it closes" 3400
sleep 0.6
at 1100 520; sleep 0.5; click 1100 520; sleep 1.4
cap "Esc closes it too; the bar button toggles it" 3400
click $BAR_X $CLUSTER_Y; sleep 1.0
"$W" -k Escape; sleep 1.0
click $BAR_X $CLUSTER_Y; sleep 1.0
click $BAR_X $CLUSTER_Y; sleep 1.2

cap "Tray menu: the same rise, the same click-away" 3400
at $BAR_X $TRAY_Y; sleep 0.6
click $BAR_X $TRAY_Y right; sleep 1.3
click 1100 400; sleep 1.2

cap "Notification centre: entries rise in turn, a dismissed one slides out" 4600
notify-send -a Build "cargo check finished" "rujit: 0 errors, 2 warnings"; sleep 0.25
notify-send -a Build "Tests passed" "412 passed in 38 s"; sleep 0.25
notify-send -a Build "Bench done" "warm check 1.8 s faster than stock"; sleep 0.25
notify-send -a Mail "Anna" "Lunch at 1?"; sleep 5.6
at $BAR_X $BELL_Y; sleep 0.4
click $BAR_X $BELL_Y; sleep 1.6
at 428 972; sleep 0.6; click 428 972; sleep 1.4
click 1100 400; sleep 0.6
click $BAR_X $BELL_Y; sleep 1.4
click $BAR_X $BELL_Y; sleep 0.8

cap "Workspace pip: the Pencil block slides between frames" 4200
at 30 300; sleep 0.4
click $BAR_X ${PIP_Y[3]}; sleep 1.2
click $BAR_X ${PIP_Y[4]}; sleep 1.2
click $BAR_X ${PIP_Y[1]}; sleep 1.4

cap "OSD: the same rise from the bar edge, and a faster exit" 4000
at 1200 400; sleep 0.4
for v in 0.5 0.55 0.6 0.65 0.7; do wpctl set-volume @DEFAULT_AUDIO_SINK@ $v; sleep 0.2; done
sleep 2.2
for b in 80 90 100 110; do echo $b > /tmp/hns-bl/brightness; sleep 0.2; done
sleep 2.4
"$HERE/scripts/record.sh" stop
OUT="$HERE/recordings/hyprnav-bar-polish.mp4"
ffmpeg -v error -y -i "$OUT" -c:v libx264 -pix_fmt yuv420p -crf 20 -preset slow -movflags +faststart "$OUT.web.mp4" && mv "$OUT.web.mp4" "$OUT"
ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$OUT"
