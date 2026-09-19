#!/usr/bin/env bash
# Seed the lab with demo environments, slots and windows.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
eval "$(python3 "$HERE/scripts/lab.py" env)"
n() { hyprnav "$@" >/dev/null; }
n env ensure --env agents --title "Agent fleet"
n env ensure --env shell --title "hyprnav shell"
n env ensure --env shell.docs --title "Docs and research"
n slot assign --env agents --slot 1 --workspace 1 --name Terminal
n slot assign --env agents --slot 2 --workspace 2 --name Editor
n slot assign --env agents --slot 3 --workspace 3 --name Browser
n slot assign --env agents --slot 4 --managed --name Files
n slot assign --env shell --slot 1 --workspace 5 --name Build
n slot assign --env shell --slot 2 --workspace 6 --name Editor
n slot assign --env shell --slot 3 --managed --name Scratch --launch -- ghostty
n slot assign --env shell.docs --slot 1 --inherit
n slot assign --env shell.docs --slot 2 --workspace 7 --name Wiki
n lock agents
ex() { hyprctl dispatch "hl.dsp.exec_cmd(\"$2\", { workspace = \"$1 silent\" })" >/dev/null; }
mkdir -p /tmp/hns-zen-profile
ex 1 "ghostty -e $HERE/scripts/demo-agent.sh planner"
ex 1 "ghostty -e $HERE/scripts/demo-agent.sh builder"
ex 2 "kitty nvim $HERE/shell/services/Hyprnav.qml"
ex 3 "zen-beta --new-instance --profile /tmp/hns-zen-profile https://wiki.hypr.land/"
ex 5 "ghostty -e $HERE/scripts/demo-agent.sh cargo"
ex 6 "kitty nvim $HERE/design/DIRECTION.md"
ex 101 "nautilus $HERE"
sleep 7
hyprctl clients -j | python3 -c 'import json,sys; [print(c["workspace"]["id"], c["class"]) for c in json.load(sys.stdin)]'
