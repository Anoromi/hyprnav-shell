#!/usr/bin/env bash
# Record the bar's roll selector: following focus versus locked to a roll.
# Hover the initials for the roll's title, click them to lock, step through
# frames, click them again to unlock, go to a frame (the daemon locks the roll
# of the workspace it focuses), move to another roll, then unlock from the
# hyprnav CLI. The full-screen recording is cropped to the top-left corner
# and scaled up, since the bar is 44 px wide.
#
# Needs: `lab.py up`, `scripts/seed.sh`, the shell running (`run.sh start`).
# Pointer positions are for the seeded rolls on a 1920x1080 TEST output.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
eval "$(python3 "$HERE/scripts/lab.py" env)"
P="$HERE/lab-tools/result/bin/hns-lab-scroll"
at() { "$P" --at "$1" "$2" >/dev/null 2>&1; }
click() { "$P" --at "$1" "$2" --click left >/dev/null 2>&1; }
focus() { hyprctl dispatch "hl.dsp.focus({ workspace = $1 })" >/dev/null; }
BAR_X=22
MONO_Y=24                   # the initials
PIP_Y=(0 76 108 140 172)    # frames 1..4 below the rail head

hyprnav goto --env agents --slot 1 >/dev/null; sleep 0.5
hyprnav unlock >/dev/null
at 900 540
sleep 1.5
"$HERE/scripts/record.sh" start hyprnav-bar-selector-raw
sleep 1.2
at $BAR_X $MONO_Y; sleep 1.8              # hover: the roll's full title
click $BAR_X $MONO_Y; sleep 2.2           # lock: the frames go onto the rail
click $BAR_X ${PIP_Y[2]}; sleep 1.0
click $BAR_X ${PIP_Y[4]}; sleep 1.2
click $BAR_X $MONO_Y; sleep 1.8           # unlock: bare frames again
click $BAR_X ${PIP_Y[1]}; sleep 1.8       # going to a frame locks its roll (daemon)
at 900 540
focus 5; sleep 2.6                        # another roll takes the lock with focus
hyprnav unlock >/dev/null; sleep 2.6      # unlocked from the CLI
"$HERE/scripts/record.sh" stop
RAW="$HERE/recordings/hyprnav-bar-selector-raw.mp4"
OUT="$HERE/recordings/hyprnav-bar-selector.mp4"
ffmpeg -v error -y -i "$RAW" -vf "crop=480:270:0:0,scale=1920:1080:flags=neighbor" \
  -c:v libx264 -pix_fmt yuv420p -crf 18 -preset slow -movflags +faststart "$OUT"
rm -f "$RAW"
ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$OUT"
