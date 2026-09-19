#!/usr/bin/env bash
# Hard sticking, told with a purpose-built "agent worker" app.
#
# Frame 1 (workspace 1): the user types notes. Frame 4 (workspace 4): a
# background agent that opens an approval dialog after 10 seconds.
# Part 1 launches the agent the usual way: the dialog lands on the notes.
# Part 2 launches it through `hyprnav spawn`: the dialog stays on frame 4, the
# user visits it through the grid, approves, and comes back.
#
# Requires the lab up with dev plugin and daemon, and the shell running.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
eval "$(python3 "$HERE/scripts/lab.py" env)"
W="$HERE/lab-tools/result/bin/wtype"
AGENT="$HERE/scripts/agent-demo --delay 10 --name planner"

say()   { qs -p "$HERE/shell" ipc call caption display "$1" "${2:-5000}" >/dev/null; }
ipc()   { qs -p "$HERE/shell" ipc call "$@" >/dev/null; }
key()   { "$W" -s 120 -k "$1"; }
type_slow() { "$W" -d 55 -- "$1"; }
focus() { hyprctl dispatch "hl.dsp.focus({ workspace = $1 })" >/dev/null; }
focus_title() { hyprctl dispatch "hl.dsp.focus({ window = \"title:$1\" })" >/dev/null 2>&1 || hyprctl dispatch focuswindow "title:$1" >/dev/null 2>&1; }
kill_agent() {
  for pid in $(hyprctl clients -j | python3 -c 'import json,sys; print(" ".join(str(c["pid"]) for c in json.load(sys.stdin) if c["title"].startswith("Agent") or c["title"]=="Approval needed"))'); do kill "$pid" 2>/dev/null; done
  sleep 1
}
clients() { hyprctl clients -j | python3 -c 'import json,sys; [print("   ", c["workspace"]["id"], "|", c["title"]) for c in json.load(sys.stdin)]'; }

# Fresh start: only the notes window on 1.
kill_agent
hyprctl clients -j | python3 -c 'import json,sys; [print(c["pid"]) for c in json.load(sys.stdin) if c["title"]!="notes"]' | xargs -r kill 2>/dev/null; sleep 0.5
if ! hyprctl clients -j | grep -q '"title": "notes"'; then
  hyprctl dispatch 'hl.dsp.exec_cmd("kitty --title notes -o font_size=19", { workspace = "1 silent" })' >/dev/null; sleep 2
fi
focus 1; focus_title notes; sleep 0.3
type_slow "clear"; key Return; sleep 0.3

"$HERE/scripts/record.sh" start sticking-demo
sleep 1.5
say "Frame 1 is my notes. Frame 4 runs a background agent that will ask for approval in 10 seconds." 7000
type_slow "# I am writing notes on frame 1. An agent works on frame 4."; key Return
sleep 3.5

# ---------------------------------------------------------------- part 1
say "Part 1 of 2: the agent launched the usual way, onto frame 4." 6000
hyprctl dispatch "hl.dsp.exec_cmd(\"$AGENT\", { workspace = \"4 silent\" })" >/dev/null
sleep 1.5
focus_title notes
type_slow "# The agent counts down. I keep typing..."; key Return
sleep 2
type_slow "# ...thinking about the next paragraph"
sleep 3.6                                             # dialog appears at t+10
say "Its dialog just landed on my workspace. Stock Hyprland opens new windows where the focus is." 7000
sleep 1
type_slow "and now my keys go into that dialog"    # lands in the dialog, harmless letters
sleep 4
echo "part 1 windows:"; clients
say "Enough. Closing that agent." 3500
kill_agent
focus_title notes; type_slow ""; key Return
sleep 1.5

# ---------------------------------------------------------------- part 2
say "Part 2 of 2: the same agent, launched with hyprnav spawn --no-focus 4" 7000
type_slow "hyprnav spawn --no-focus 4 -- ./scripts/agent-demo --delay 10 --name planner &"; key Return
sleep 2
type_slow "# Frame 4 now carries a pin in the bar: its tree is stuck."; key Return
sleep 2
type_slow "# Counting down again. I keep typing, undisturbed..."
sleep 5.5                                             # dialog opens at t+10, on frame 4
type_slow " still here."; key Return
say "The dialog opened on frame 4, not here. Nothing moved, nothing took my focus." 7000
sleep 4
echo "part 2 windows:"; clients

# Visit frame 4 through the grid, approve, come back.
say "Let me go and see it: grid, frame 4." 5000
ipc grid open; sleep 1.8
key Right; sleep 0.6; key Right; sleep 0.6; key Right; sleep 1.2
key Return; sleep 2.5
focus_title "Approval needed"; sleep 0.8
key Return                                            # Approve has focus
sleep 1.8
say "Approved. Back to my notes." 4500
ipc switcher open; sleep 1.4; key Return; sleep 2
focus_title notes; type_slow "# Back on frame 1. Nothing ever covered this window."; key Return
sleep 3

"$HERE/scripts/record.sh" stop
OUT="$HERE/recordings/sticking-demo.mp4"
ffmpeg -v error -y -i "$OUT" -c:v libx264 -pix_fmt yuv420p -crf 20 -preset slow -movflags +faststart "$OUT.web.mp4" && mv "$OUT.web.mp4" "$OUT"
ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$OUT"
