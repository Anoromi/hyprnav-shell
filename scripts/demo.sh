#!/usr/bin/env bash
# Scripted walkthrough of hyprnav-shell inside the lab compositor, recorded to
# recordings/<name>.mp4. Keys go through wtype (a virtual keyboard), overlay
# open commands go through `qs ipc`, exactly as Hyprland binds would call them.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
NAME="${1:-hyprnav-shell-demo}"
eval "$(python3 "$HERE/scripts/lab.py" env)"
W="${WTYPE:-$HERE/lab-tools/result/bin/wtype}"
ipc() { qs -p "$HERE/shell" ipc call "$@" >/dev/null; }
key() { "$W" -s 120 -k "$1"; }
pause() { sleep "$1"; }

hyprctl dispatch "hl.dsp.focus({ workspace = 1 })" >/dev/null
hyprctl dispatch "hl.dsp.move_cursor({ x = 1900, y = 1060 })" >/dev/null 2>&1 || true
VOL_BEFORE="$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print $2}')"
"$HERE/scripts/record.sh" start "$NAME"
pause 2.5

# 1. Switcher: open, step twice, choose.
ipc switcher open;   pause 1.6
key Tab;             pause 0.9
key Tab;             pause 0.9
key Return;          pause 2.0

# 2. Switcher again, straight back to the previous frame.
ipc switcher open;   pause 1.3
key Return;          pause 1.8

# 3. Grid: browse rolls, lock one, open a frame.
ipc grid open;       pause 1.8
key Right;           pause 0.7
key Down;            pause 0.7
key Right;           pause 0.7
"$W" -M shift -k l -m shift; pause 1.4     # lock this roll
key Down;            pause 0.7
key Left;            pause 0.7
key Return;          pause 2.0

# 4. Grid again: a digit jumps straight to that frame.
ipc grid open;       pause 1.5
key Up;              pause 0.7
key Up;              pause 0.7
"$W" -M shift -k l -m shift; pause 1.2     # lock Agent fleet again
key 3;               pause 2.0

# 5. Quick settings: Wi-Fi, Bluetooth, sound with a live volume change.
ipc qs open;         pause 3.0
ipc qs section bluetooth; pause 2.0
ipc qs section sound;     pause 1.2
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.45; pause 0.8
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.30; pause 1.0
ipc qs close;        pause 0.8

# 6. Notifications: two arrive, then the history sheet.
notify-send -a cargo "Build finished" "hyprnav 0.1 compiled in 4.2s, 0 warnings"; pause 1.2
notify-send -a planner -u critical "Needs your review" "Slot inheritance change touches 3 files"; pause 2.2
ipc qs section notifications; pause 2.2
ipc qs clearNotifications;    pause 1.0
ipc qs close;        pause 0.8

# 7. Back where we started, through the switcher.
ipc switcher open;   pause 1.3
key Tab;             pause 0.8
key Return;          pause 2.0

wpctl set-volume @DEFAULT_AUDIO_SINK@ "$VOL_BEFORE"
"$HERE/scripts/record.sh" stop
OUT="$HERE/recordings/$NAME.mp4"
ffmpeg -v error -y -i "$OUT" -c:v libx264 -pix_fmt yuv420p -crf 20 -preset slow -movflags +faststart "$HERE/recordings/$NAME.web.mp4"
mv "$HERE/recordings/$NAME.web.mp4" "$OUT"
ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$OUT" | xargs printf "recorded %s seconds -> %s\n" 
echo "$OUT"
