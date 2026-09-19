#!/usr/bin/env bash
# Hard-sticking scenarios in the lab compositor. Requires the lab to be up
# with HNS_PLUGIN_SO and HNS_HYPRNAV_BIN pointing at dev builds:
#   HNS_PLUGIN_SO=... HNS_HYPRNAV_BIN=... scripts/lab.py up
# Usage: sticking-test.sh [record]
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
eval "$(python3 "$HERE/scripts/lab.py" env)"
W="$HERE/lab-tools/result/bin/wtype"
PASS=0; FAIL=0
ok()   { echo "  PASS  $*"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL  $*"; FAIL=$((FAIL+1)); }
ws()   { hyprctl activeworkspace -j | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])'; }
wsof() { hyprctl clients -j | python3 -c "import json,sys; cs=[c for c in json.load(sys.stdin) if c['class']=='$1']; print(','.join(sorted(str(c['workspace']['id']) for c in cs)))"; }
pidsof(){ hyprctl clients -j | python3 -c "import json,sys; print(' '.join(str(c['pid']) for c in json.load(sys.stdin) if c['class']=='$1'))"; }
count(){ hyprctl clients -j | python3 -c "import json,sys; print(len([c for c in json.load(sys.stdin) if c['class']=='$1']))"; }
focus1(){ hyprctl dispatch 'hl.dsp.focus({ workspace = 1 })' >/dev/null; }
closeall(){ hyprctl clients -j | python3 -c 'import json,sys; [print(c["address"]) for c in json.load(sys.stdin)]' | while read a; do hyprctl dispatch "hl.dsp.window.close({ window = \"address:$a\" })" >/dev/null 2>&1 || hyprctl dispatch closewindow "address:$a" >/dev/null 2>&1; done; sleep 1; }
waitfor(){ for i in $(seq 1 60); do [ "$(count "$1")" -ge "$2" ] && return 0; sleep 0.25; done; return 1; }

if [ "${1:-}" = record ]; then "$HERE/scripts/record.sh" start sticking; sleep 1; fi

echo "== setup: user works on workspace 1 (kitty)"
hyprctl dispatch 'hl.dsp.exec_cmd("kitty", { workspace = "1 silent" })' >/dev/null; waitfor kitty 1; focus1
echo "plugin: $(hyprctl plugin list | grep -c hyprnav-plugin)  sticks: $(hyprnav status | python3 -c 'import json,sys; print(json.load(sys.stdin).get("sticks"))')"

echo "== 1. spawned ghostty on 105 stays there, focus stays on 1"
hyprnav spawn --no-focus 105 -- ghostty >/dev/null 2>&1 &
waitfor com.mitchellh.ghostty 1; sleep 0.5
[ "$(wsof com.mitchellh.ghostty)" = 105 ] && ok "ghostty on 105" || bad "ghostty on $(wsof com.mitchellh.ghostty)"
[ "$(ws)" = 1 ] && ok "focus stayed on 1" || bad "focus moved to $(ws)"

echo "== 2. second window from the same tree after the spawn CLI is long gone"
GPID=$(pidsof com.mitchellh.ghostty | awk '{print $1}')
hyprctl dispatch "hl.dsp.focus({ workspace = 105 })" >/dev/null; sleep 0.4
"$W" -M ctrl -M shift -k n -m shift -m ctrl; sleep 0.3      # ghostty: new window
focus1; waitfor com.mitchellh.ghostty 2
[ "$(wsof com.mitchellh.ghostty)" = 105,105 ] && ok "second ghostty window on 105" || bad "ghostty windows on $(wsof com.mitchellh.ghostty)"
[ "$(ws)" = 1 ] && ok "focus stayed on 1" || bad "focus moved to $(ws)"

echo "== 3. child process of the tree (kitty launched from the spawned ghostty) sticks"
hyprctl dispatch "hl.dsp.focus({ workspace = 105 })" >/dev/null; sleep 0.4
"$W" -s 40 "kitty &"; "$W" -k Return; sleep 0.2
focus1; waitfor kitty 2
[ "$(wsof kitty)" = 1,105 ] && ok "child kitty on 105" || bad "kitty windows on $(wsof kitty)"
[ "$(ws)" = 1 ] && ok "focus stayed on 1" || bad "focus moved to $(ws)"

echo "== 4. GTK file chooser opened from a stuck window lands on 105"
GTK_PIDS_BEFORE=$(count org.gnome.Nautilus)
hyprctl dispatch "hl.dsp.focus({ workspace = 105 })" >/dev/null; sleep 0.4
"$W" -s 40 "nautilus --new-window . &"; "$W" -k Return; sleep 0.2
focus1; waitfor org.gnome.Nautilus 1
[ "$(wsof org.gnome.Nautilus)" = 105 ] && ok "nautilus (child) on 105" || bad "nautilus on $(wsof org.gnome.Nautilus)"
pkill -f '^nautilus --new-window' 2>/dev/null; sleep 0.8   # give the terminal focus back on 105

echo "== 5. daemon restart keeps the stick"
NAVPID=$(pgrep -f "hyprnav daemon" | head -1); kill "$NAVPID"; sleep 0.5
( hyprnav daemon >/dev/null 2>&1 & ); sleep 2.5
hyprctl dispatch "hl.dsp.focus({ workspace = 105 })" >/dev/null; sleep 0.4
"$W" -s 40 "kitty &"; "$W" -k Return; sleep 0.2
focus1; waitfor kitty 3
[ "$(wsof kitty)" = 1,105,105 ] && ok "kitty after daemon restart on 105" || bad "kitty windows on $(wsof kitty)"

echo "== 6. plugin reload: sticks replayed, new tree window still sticks"
SO=$(hyprctl plugin list -j 2>/dev/null | python3 -c 'import json,sys; print([p for p in json.load(sys.stdin) if p["name"]=="hyprnav-plugin"][0]["path"])' 2>/dev/null || echo "${HNS_PLUGIN_SO:-}")
hyprctl plugin unload "$SO" >/dev/null; sleep 0.5; hyprctl plugin load "$SO" >/dev/null; sleep 3
hyprctl dispatch "hl.dsp.focus({ workspace = 105 })" >/dev/null; sleep 0.4
"$W" -s 40 "kitty &"; "$W" -k Return; sleep 0.2
focus1; waitfor kitty 4
[ "$(wsof kitty)" = 1,105,105,105 ] && ok "kitty after plugin reload on 105" || bad "kitty windows on $(wsof kitty)"

echo "== 7. --no-stick: watch ends with the CLI, later windows follow stock placement"
hyprnav spawn --no-focus --no-stick 106 -- sh -c 'ghostty --class=nostick.test & sleep 1' >/dev/null 2>&1
sleep 1
waitfor nostick.test 1
[ "$(wsof nostick.test)" = 106 ] && ok "no-stick first window on 106" || bad "no-stick first window on $(wsof nostick.test)"

echo "== 8. status and list"
hyprnav stick list | head -30
echo "sticks in status: $(hyprnav status | python3 -c 'import json,sys; print(json.load(sys.stdin).get("sticks"))')"

if [ "${1:-}" = record ]; then sleep 1; "$HERE/scripts/record.sh" stop; fi
echo; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
