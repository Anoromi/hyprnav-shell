#!/usr/bin/env bash
# Record the bar's workspace selector: both groups at once. It starts on a
# plain workspace with no lock, so only the workspace list shows at the top;
# right-clicking a roll's workspace locks that roll and its rail fades and
# grows in the middle; frames are switched on the rail (the frame and its
# workspace are marked in both groups); a plain workspace is picked from the
# top; clicking the monogram unlocks and the rail goes. The full-screen
# recording is cropped to the top-left of the screen and scaled up 3x.
#
# Needs: `lab.py up`, `scripts/seed.sh`, the shell running (`run.sh start`),
# and workspaces 1, 2, 5, 6 and 8 on the screen (seed.sh fills all but 8,
# which this script fills). Pointer positions are for that set on a
# 1920x1080 TEST output with the shell roll (3 frames) locked.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
eval "$(python3 "$HERE/scripts/lab.py" env)"
P="$HERE/lab-tools/result/bin/hns-lab-scroll"
at() { "$P" --at "$1" "$2" >/dev/null 2>&1; }
click() { "$P" --at "$1" "$2" --click "${3:-left}" >/dev/null 2>&1; }
focus() { hyprctl dispatch "hl.dsp.focus({ workspace = $1 })" >/dev/null; }
BAR_X=22
TOP_Y=(26 58 90 122 154)    # workspaces 1 2 5 6 8
MONO_Y=361                  # the locked roll's initials
RAIL_Y=(413 445 477)        # its frames 1 2 3

# Start on workspace 8 (no roll) with no lock.
if ! hyprctl clients -j | python3 -c "import json,sys; sys.exit(0 if any(c['workspace']['id']==8 for c in json.load(sys.stdin)) else 1)"; then
  hyprctl dispatch 'hl.dsp.exec_cmd("kitty", { workspace = "8 silent" })' >/dev/null; sleep 1.5
fi
focus 8; sleep 0.4
hyprnav unlock >/dev/null
at 900 540
sleep 1.5
"$HERE/scripts/record.sh" start hyprnav-bar-selector-raw
sleep 1.8                                   # no lock: the workspace list only
at $BAR_X ${TOP_Y[2]}; sleep 1.2            # hover 5: it is a frame of "hyprnav shell"
click $BAR_X ${TOP_Y[2]} right; sleep 2.0   # right-click locks that roll: the rail grows in the middle
click $BAR_X ${RAIL_Y[0]}; sleep 1.8        # frame 1 is workspace 5: marked in both groups
click $BAR_X ${RAIL_Y[1]}; sleep 1.8        # frame 2 is workspace 6
click $BAR_X ${TOP_Y[4]}; sleep 1.8         # workspace 8 is in no roll: marked at the top only
click $BAR_X ${TOP_Y[3]}; sleep 1.8         # workspace 6 from the top: frame 2 is marked again
click $BAR_X $MONO_Y; sleep 2.0             # the initials unlock: the rail goes, the list stays
at 900 540; sleep 0.8
"$HERE/scripts/record.sh" stop
RAW="$HERE/recordings/hyprnav-bar-selector-raw.mp4"
OUT="$HERE/recordings/hyprnav-bar-selector-v3.mp4"
ffmpeg -v error -y -i "$RAW" -vf "crop=320:540:0:0,scale=960:1620:flags=neighbor" \
  -c:v libx264 -pix_fmt yuv420p -crf 18 -preset slow -movflags +faststart "$OUT"
rm -f "$RAW"
ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$OUT"
