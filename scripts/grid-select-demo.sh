#!/usr/bin/env bash
# The grid opens on the frame you are in, and a resting pointer does not take
# the selection from it. Seeds a locked thread roll, a second thread, and a
# long roll that scrolls; the active frame is in the middle of a roll, then on
# a temporary slot, then deep in the long roll.
# Usage: grid-select-demo.sh seed | record
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
eval "$(python3 "$HERE/scripts/lab.py" env)"
S="$HERE/lab-tools/result/bin/hns-lab-scroll"
n() { hyprnav "$@" >/dev/null; }
ipc() { qs -p "$HERE/shell" ipc "$@" >/dev/null; }
cap() { ipc call caption display "$1" "$2"; }
ex() { hyprctl dispatch "hl.dsp.exec_cmd(\"$2\", { workspace = \"$1 silent\" })" >/dev/null; }
focus() { hyprctl dispatch "hl.dsp.focus({ workspace = $1 })" >/dev/null; sleep 0.6; }
# Pointer moves go through the lab's virtual pointer; never outside the lab.
at() { "$S" --at "$1" "$2" >/dev/null 2>&1; }
# Workspace of the thread's temporary slot.
temp_ws() { hyprnav slot temps | python3 -c 'import json,sys; print([t["workspace_id"] for t in json.load(sys.stdin) if t["env_id"] == "p.x.w.a.t"][0])'; }

case "${1:-record}" in
seed)
  n env ensure --env p.x --title "Proj"
  n env ensure --env p.x.w
  n env ensure --env p.x.w.a.t --title "Design Hypernav Workspace UI"
  n env ensure --env p.x.w.b.t --title "Other"
  n env ensure --env long --title "Long roll"
  n slot assign --env p.x.w --slot 1 --workspace 1 --name Terminal
  n slot assign --env p.x.w --slot 2 --workspace 2 --name T3code
  n slot assign --env p.x.w --slot 3 --workspace 3 --name Editor
  n slot assign --env p.x.w.a.t --slot 5 --workspace 5 --name "testing terminal"
  n slot assign --env p.x.w.a.t --slot 8 --workspace 8 --name Corkdiff
  n slot assign --env p.x.w.a.t --slot 9 --workspace 9 --name Notes
  n slot assign --env p.x.w.b.t --slot 4 --workspace 4 --name Notes
  for i in $(seq 1 30); do n slot assign --env long --slot "$i" --workspace $((19 + i)) --name "Frame $i"; done
  ex 1 "ghostty -e $HERE/scripts/demo-agent.sh builder"
  ex 2 "kitty nvim $HERE/shell/grid/Grid.qml"
  ex 5 "ghostty -e $HERE/scripts/demo-agent.sh cargo"
  ex 8 "kitty nvim $HERE/shell/HoverGate.qml"
  ex 4 "kitty nvim $HERE/design/DIRECTION.md"
  ex 43 "kitty nvim $HERE/GRID-LAYOUT-PLAN.md"
  n slot temp --env p.x.w.a.t --name Scratch --no-focus
  ex "$(temp_ws)" kitty
  sleep 4
  n lock p.x.w.a.t
  ;;
record)
  ipc call grid close || true
  focus 8; n lock p.x.w.a.t
  at 1800 1040
  "$HERE/scripts/record.sh" start grid-select
  sleep 0.8
  cap "Frame 8 of the locked roll is on screen" 2200
  sleep 2.0
  ipc call grid open
  sleep 0.4
  cap "The grid opens on it, mid-roll, not on the first frame" 3000
  sleep 3.2
  ipc call grid close; sleep 0.6
  focus "$(temp_ws)"; n lock p.x.w.a.t
  cap "Now a temporary slot is on screen" 2200
  sleep 2.0
  ipc call grid open
  sleep 0.4
  cap "The ring starts on the temporary cell" 2800
  sleep 3.0
  ipc call grid close; sleep 0.6
  focus 8; n lock p.x.w.a.t
  # Park the pointer on another frame: the shared Editor frame, row 0.
  at 740 190
  cap "The pointer rests on another frame" 2200
  sleep 2.0
  ipc call grid open
  sleep 0.4
  cap "Reopened: the ring stays on the frame you are in" 3000
  sleep 2.0
  grim -c -o "$HNS_SCREEN" /tmp/hns-grid-select-c.png 2>/dev/null || true
  sleep 1.0
  cap "Move the pointer a few pixels and hover selects again" 3000
  sleep 1.0
  at 746 194; sleep 0.2; at 754 200
  sleep 2.6
  ipc call grid close; sleep 0.6
  at 1800 1040
  focus 43
  cap "Frame 24 of the long roll, far down the stack" 2400
  sleep 2.0
  ipc call grid open
  sleep 0.4
  cap "The grid opens already scrolled to it" 3000
  sleep 3.4
  ipc call grid close
  sleep 1.0
  "$HERE/scripts/record.sh" stop
  ;;
esac
