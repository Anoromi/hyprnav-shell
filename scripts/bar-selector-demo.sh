#!/usr/bin/env bash
# Record the bar's workspace selector. Unlocked it lists every workspace on
# the screen; a new workspace is created and filled; going to a roll's
# workspace locks the roll and the rail grows out from behind the current
# frame; frames are switched on the rail, including the roll's managed
# frame; the initials unlock it again, and on a managed workspace the
# unlocked list shows that one under its frame number. The full-screen
# recording is cropped to the top-left corner and scaled up 4x, since the bar
# is 44 px wide.
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
LOCK_Y=52                   # the lock at the rail head
ROW_Y=(76 108 140 172 204 236)
NEW_WS=8

# Start clean: nothing on the demo workspace, agents frame 1, no lock.
hyprctl clients -j | python3 -c "import json,sys; [print(c['pid']) for c in json.load(sys.stdin) if c['workspace']['id']==$NEW_WS]" \
  | while read -r pid; do kill "$pid" 2>/dev/null || true; done
hyprnav goto --env agents --slot 1 >/dev/null; sleep 0.5
hyprnav unlock >/dev/null
at 900 540
sleep 1.5
"$HERE/scripts/record.sh" start hyprnav-bar-selector-raw
sleep 1.6                                   # unlocked: every workspace on the screen
at $BAR_X ${ROW_Y[2]}; sleep 0.8            # hover a workspace
hyprctl dispatch "hl.dsp.exec_cmd(\"kitty\", { workspace = \"$NEW_WS silent\" })" >/dev/null
sleep 1.8                                   # a window opens on a new workspace: its row fades in
focus $NEW_WS; sleep 1.4                    # and focusing it moves the block there
click $BAR_X ${ROW_Y[1]}; sleep 1.8         # go to 2: the daemon locks its roll, the rail grows
click $BAR_X ${ROW_Y[0]}; sleep 1.0         # frames on the rail
click $BAR_X ${ROW_Y[3]}; sleep 1.4         # the managed frame (workspace 101)
click $BAR_X $MONO_Y; sleep 2.0             # unlock: 101 shows as frame 4, last
click $BAR_X ${ROW_Y[0]}; sleep 1.6         # workspace 1 locks again
hyprnav unlock >/dev/null; sleep 1.2        # unlocked from the CLI
click $BAR_X $LOCK_Y; sleep 1.6             # the open lock locks the roll in place
at 900 540; sleep 0.6
"$HERE/scripts/record.sh" stop
RAW="$HERE/recordings/hyprnav-bar-selector-raw.mp4"
OUT="$HERE/recordings/hyprnav-bar-selector-v2.mp4"
ffmpeg -v error -y -i "$RAW" -vf "crop=480:270:0:0,scale=1920:1080:flags=neighbor" \
  -c:v libx264 -pix_fmt yuv420p -crf 18 -preset slow -movflags +faststart "$OUT"
rm -f "$RAW"
ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$OUT"
