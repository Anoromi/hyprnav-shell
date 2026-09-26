#!/usr/bin/env bash
# Record the bar as the daily bar: tray with its menu, notification popups and
# the centre (groups, do not disturb), the control centre (night light, power
# profile, sections), the volume and brightness OSD, and the launcher and
# clipboard buttons.
#
# Needs: `lab.py up`, `lab.py audio` (private PipeWire), the shell started with
# HNS_BACKLIGHT pointing at a fake panel (/tmp/hns-bl, see TESTING.md), a lab
# vicinae server, and scripts/tray-test.py running. Pointer positions below
# are for 1920x1080 with two tray items (vicinae's and the test item).
#
# Changes the host's power profile for about two seconds and restores it; the
# volume, brightness, clipboard and notifications are all the lab's own.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
eval "$(python3 "$HERE/scripts/lab.py" env)"
W="$HERE/lab-tools/result/bin/wtype"
P="$HERE/lab-tools/result/bin/hns-lab-scroll"
ipc() { qs -p "$HERE/shell" ipc call "$@" >/dev/null; }
cap() { ipc caption display "$1" "$2"; }
at() { "$P" --at "$1" "$2" >/dev/null 2>&1; }
click() { "$P" --at "$1" "$2" --click "${3:-left}" >/dev/null 2>&1; }
note() { notify-send -a "$1" "$2" "$3"; }
BAR_X=22
# Bar rows (y) from the bottom stack; see TESTING.md for how they were read.
LAUNCHER_Y=${LAUNCHER_Y:-692}
CLIP_Y=${CLIP_Y:-725}
TRAY_Y=${TRAY_Y:-767}
BELL_Y=${BELL_Y:-840}
CLUSTER_Y=${CLUSTER_Y:-920}

profile_before=$(powerprofilesctl get)
trap 'powerprofilesctl set "$profile_before" >/dev/null 2>&1 || true' EXIT

ipc qs close; ipc center close; ipc center clear; ipc center dnd false
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.4; wpctl set-mute @DEFAULT_AUDIO_SINK@ 0
echo 60 > /tmp/hns-bl/brightness
at 900 540
sleep 1.6
"$HERE/scripts/record.sh" start hyprnav-bar
sleep 1.0
cap "The hyprnav bar, ready to replace the DMS bar" 3200
sleep 1.2
at $BAR_X 40; sleep 1.0; at $BAR_X 70; sleep 1.2
at $BAR_X $LAUNCHER_Y; sleep 0.9; at $BAR_X $CLIP_Y; sleep 0.9

cap "Tray: StatusNotifierItem menus, drawn on the sheet" 3400
at $BAR_X $TRAY_Y; sleep 1.0
click $BAR_X $TRAY_Y right; sleep 1.4
click 120 $((TRAY_Y + 35)); sleep 0.8          # "Keep it checked"
click $BAR_X $TRAY_Y right; sleep 1.4
click 120 $((TRAY_Y + 8)); sleep 1.6           # "Say hello" sends a notification

cap "Popups top right; each one also lands in the centre" 3400
note Build "cargo check finished" "rujit: 0 errors, 2 warnings"; sleep 0.5
note Build "Tests passed" "412 passed in 38 s"; sleep 0.5
note Build "Bench done" "warm check 1.8 s faster than stock"; sleep 0.5
note Build "Clippy" "3 suggestions in cache.rs"; sleep 0.5
notify-send -a Mail "Anna" "Lunch at 1?"; sleep 0.4
notify-send -a Calendar -u critical "Standup in 5 min" "Room 3"
sleep 3.2

cap "The bell opens the notification centre, grouped by app" 3600
at $BAR_X $BELL_Y; sleep 0.6
click $BAR_X $BELL_Y; sleep 2.6
ipc caption hide
# "Show 1 more" under the Build group, then clear the Mail group.
ipc center state >/dev/null
sleep 1.0
cap "Do not disturb holds popups back; the centre still fills" 3800
sleep 0.6
ipc center dnd true; sleep 1.2
note Build "Quiet one" "arrives without a popup"; sleep 2.0
ipc center dnd false; sleep 0.8
click $BAR_X $BELL_Y; sleep 0.8

cap "Control centre: night light, power profile, network, sound" 3800
ipc qs section sound; sleep 1.8
click 110 685; sleep 1.6                       # night light on (hyprsunset)
click 125 743; sleep 1.4                       # power saver
click 250 743; sleep 1.2                       # balanced
powerprofilesctl set "$profile_before" >/dev/null 2>&1 || true
ipc qs section wifi; sleep 1.8                 # read-only view
ipc qs section bluetooth; sleep 1.6
ipc qs section sound; sleep 1.2
click 110 685; sleep 0.8                       # night light off
ipc qs close; sleep 0.8

cap "OSD: PipeWire volume and backlight changes, beside the bar" 3800
sleep 0.8
for v in 0.45 0.5 0.55 0.6 0.65; do wpctl set-volume @DEFAULT_AUDIO_SINK@ $v; sleep 0.18; done
sleep 1.8
wpctl set-mute @DEFAULT_AUDIO_SINK@ 1; sleep 1.4; wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; sleep 1.9
for b in 70 80 90 100; do echo $b > /tmp/hns-bl/brightness; sleep 0.2; done
sleep 2.2

cap "Launcher and clipboard history: vicinae" 3400
click $BAR_X $LAUNCHER_Y; sleep 2.2
"$W" -k Escape; sleep 0.8
click $BAR_X $CLIP_Y; sleep 2.6
"$W" -k Escape; sleep 0.8
cap "No polling: DBus signals, PipeWire events and file watches" 3600
sleep 4.0
"$HERE/scripts/record.sh" stop
OUT="$HERE/recordings/hyprnav-bar.mp4"
ffmpeg -v error -y -i "$OUT" -c:v libx264 -pix_fmt yuv420p -crf 20 -preset slow -movflags +faststart "$OUT.web.mp4" && mv "$OUT.web.mp4" "$OUT"
ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$OUT"
