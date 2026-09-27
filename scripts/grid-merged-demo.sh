#!/usr/bin/env bash
# Seed a project -> worktree -> two threads chain and record the merged grid:
# each thread is one roll carrying the worktree's frames tagged "shared".
# Usage: grid-merged-demo.sh seed | record
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
eval "$(python3 "$HERE/scripts/lab.py" env)"
W="$HERE/lab-tools/result/bin/wtype"
n() { hyprnav "$@" >/dev/null; }
ipc() { qs -p "$HERE/shell" ipc "$@" >/dev/null; }
cap() { ipc call caption display "$1" "$2"; }
key() { "$W" -k "$1"; sleep "${2:-0.45}"; }
ex() { hyprctl dispatch "hl.dsp.exec_cmd(\"$2\", { workspace = \"$1 silent\" })" >/dev/null; }

case "${1:-record}" in
seed)
  n env ensure --env p.x --title "Proj"
  n env ensure --env p.x.w
  n env ensure --env p.x.w.a.t --title "Design Hypernav Workspace UI"
  n env ensure --env p.x.w.b.t --title "Other"
  n slot assign --env p.x.w --slot 1 --workspace 1 --name Terminal
  n slot assign --env p.x.w --slot 2 --workspace 2 --name T3code
  n slot assign --env p.x.w --slot 3 --workspace 3 --name Editor
  n slot assign --env p.x.w.a.t --slot 5 --workspace 5 --name "testing terminal"
  n slot assign --env p.x.w.a.t --slot 8 --workspace 8 --name Corkdiff
  n slot assign --env p.x.w.b.t --slot 4 --workspace 4 --name Notes
  ex 1 "ghostty -e $HERE/scripts/demo-agent.sh builder"
  ex 2 "kitty nvim $HERE/shell/grid/Grid.qml"
  ex 5 "ghostty -e $HERE/scripts/demo-agent.sh cargo"
  ex 4 "kitty nvim $HERE/design/DIRECTION.md"
  sleep 4
  hyprctl dispatch 'hl.dsp.focus({ workspace = 5 })' >/dev/null
  sleep 0.5
  # Lock the worktree last: focusing a frame can move the lock.
  n lock p.x.w
  ;;
record)
  ipc call grid close || true
  "$HERE/scripts/record.sh" start grid-merged
  sleep 0.8
  ipc call grid open
  sleep 2.2
  cap "One roll per thread; the worktree's frames 1-3 are shared" 3400
  sleep 0.4
  key Home 0.7; key Right 0.7; key Right 0.7
  cap "Own frames follow the shared ones" 2600
  key Right 0.8; key Right 0.8
  sleep 0.4
  cap "The other thread shows the same shared frames" 2800
  key Down 0.9; key Left 0.6; key Left 0.6; key Left 0.8
  key Right 0.5; key Right 0.5; key Right 0.8
  sleep 0.5
  cap "Enter opens the frame" 2000
  key Return 2.4
  sleep 1.2
  "$HERE/scripts/record.sh" stop
  ;;
esac
