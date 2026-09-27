#!/usr/bin/env bash
# Run a T3 Code dev instance inside the lab compositor.
#
# Uses a private HOME (lab/home) so Claude Code reads a lab .claude.json whose
# cua_repl points at the session-inheriting MCP launcher, and a private T3
# home (lab/t3home). Auth files are copied from the real HOME on first run.
#
#   T3CODE_REPO=~/code/stolen/t3code [HNS_HYPRNAV_BIN=...] scripts/t3-lab.sh up [project-dir]
#   scripts/t3-lab.sh down
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="${T3CODE_REPO:-$HOME/code/stolen/t3code-lab}"
HYPRUSE="${HYPRUSE_REPO:-$HOME/code/experiments/hypr-use}"
LABHOME="$HERE/lab/home"
T3HOME="$HERE/lab/t3home"
PIDF="$HERE/lab/t3.pid"
LOG="$HERE/lab/t3.log"

case "${1:-up}" in
  up)
    PROJECT="${2:-$HERE/lab/demo-project}"
    mkdir -p "$LABHOME/.claude" "$T3HOME" "$PROJECT"
    eval "$(python3 "$HERE/scripts/lab.py" env)"
    # Claude Code identity and settings, copied once.
    for f in .credentials.json settings.json; do
      [ -e "$LABHOME/.claude/$f" ] || cp "$HOME/.claude/$f" "$LABHOME/.claude/$f"
    done
    # Lab .claude.json: real onboarding/oauth fields, but MCP servers replaced.
    python3 - "$HOME/.claude.json" "$LABHOME/.claude.json" "$HYPRUSE/mcp/hypr-use-mcp-inherit" <<'PY'
import json, sys
src, dst, launcher = sys.argv[1:]
d = json.load(open(src))
keep = {k: v for k, v in d.items() if k not in ("projects", "mcpServers")}
keep["mcpServers"] = {"cua_repl": {"type": "stdio", "command": launcher, "args": [], "env": {}}}
keep["projects"] = {}
json.dump(keep, open(dst, "w"), indent=2)
PY
    # Toolchain from the live dev session's nix develop shell (pkg-config, libsecret, gcc).
    # The captured env pins the live session's GPU Electron; keep the caller's
    # choice (or the lab's software-rendering wrapper below) instead.
    electron_path="${T3CODE_DESKTOP_ELECTRON_PATH_LAB:-$HERE/lab-tools/electron-nogpu}"
    [ -f "$HERE/lab/t3-buildenv.sh" ] && source "$HERE/lab/t3-buildenv.sh"
    export HOME="$LABHOME"
    export XDG_CONFIG_HOME="$LABHOME/.config" XDG_DATA_HOME="$LABHOME/.local/share" XDG_STATE_HOME="$LABHOME/.local/state" XDG_CACHE_HOME="$LABHOME/.cache"
    mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
    # Keep the hypr-use headless env file reachable for typelib paths.
    mkdir -p "$XDG_DATA_HOME/hypr-use"; cp -n "/home/anoromi/.local/share/hypr-use/headless-env.json" "$XDG_DATA_HOME/hypr-use/" 2>/dev/null || true
    export T3CODE_DEV_INSTANCE="${T3CODE_DEV_INSTANCE:-hns-lab}"
    export T3CODE_DESKTOP_OZONE_PLATFORM=wayland
    export ELECTRON_ENABLE_LOGGING="${ELECTRON_ENABLE_LOGGING:-}"
    export HYPR_USE_HOST_NAME=claude
    # Same Electron and Node the live dev session uses (from its nix develop shell).
    export T3CODE_DESKTOP_ELECTRON_PATH="$electron_path"
    export ELECTRON_SKIP_BINARY_DOWNLOAD=1
    # The nested lab compositor has no GPU; software rendering keeps Electron responsive.
    export ELECTRON_EXTRA_LAUNCH_ARGS="${ELECTRON_EXTRA_LAUNCH_ARGS:---disable-gpu --disable-gpu-compositing}"
    export PATH="/nix/store/g6b693wj5dc8jnd04mpy6i5fyap5l9i5-t3code-electron-43.4.1/bin:/nix/store/lfaydgacdyngci7p60s8wwvgdm74fjkx-nodejs-24.19.0/bin:$PATH"
    # The captured env replaces PATH; a dev hyprnav (HNS_HYPRNAV_BIN, as given
    # to lab.py up) has to come first again, or T3 talks to the lab daemon
    # through the installed CLI.
    if [ -n "${HNS_HYPRNAV_BIN:-}" ]; then export PATH="$(dirname "$(readlink -f "$HNS_HYPRNAV_BIN")"):$PATH"; fi
    # The embedded backend bootstraps the demo project as the first project.
    export T3CODE_DESKTOP_BACKEND_CWD="$PROJECT"
    export T3CODE_AUTO_BOOTSTRAP_PROJECT_FROM_CWD=true
    cd "$REPO"
    nohup node "$REPO/scripts/dev-runner.ts" dev:desktop --home-dir "$T3HOME" --auto-bootstrap-project-from-cwd >"$LOG" 2>&1 &
    echo $! >"$PIDF"
    echo "t3 dev pid $(cat "$PIDF") log $LOG project $PROJECT"
    ;;
  settle)
    # The desktop dev watcher relaunches Electron after its first rebuilds; the
    # old Electron's backend can outlive it and hold the port. Wait for the
    # rebuilds to stop, then kill orphaned lab backends so the live one binds.
    last=$(grep -c 'Rebuilt in' "$LOG"); i=0
    while [ $i -lt 40 ]; do sleep 3; now=$(grep -c 'Rebuilt in' "$LOG"); [ "$now" = "$last" ] && i=$((i+3)) || { last=$now; i=0; }; [ $i -ge 12 ] && break; done
    # An orphaned backend is one whose parent is no longer an Electron process.
    for pid in $(pgrep -f 'bin.mjs --bootstrap-fd'); do
      tr '\0' '\n' < /proc/$pid/environ 2>/dev/null | grep -q "T3CODE_HOME=$T3HOME" || continue
      parent=$(ps -o ppid= -p "$pid" | tr -d ' '); pcomm=$(ps -o comm= -p "$parent" 2>/dev/null)
      case "$pcomm" in *electron*) ;; *) echo "killing orphaned backend $pid (parent $parent $pcomm)"; kill "$pid";; esac
    done
    sleep 4
    eval "$(python3 "$HERE/scripts/lab.py" env)"
    # DevTools shares Electron's pid, so killing its window kills T3 (and the
    # runner relaunches it next to an orphaned backend). Park it instead.
    for a in $(hyprctl clients -j | python3 -c 'import json,sys; [print(c["address"]) for c in json.load(sys.stdin) if c["title"].startswith("Developer Tools")]'); do hyprctl dispatch "hl.dsp.window.move({ workspace = \"99\", follow = false, window = \"address:$a\" })" >/dev/null; done
    A=$(hyprctl clients -j | python3 -c 'import json,sys; l=[c["address"] for c in json.load(sys.stdin) if c["class"]=="t3-code-alpha"]; print(l[0] if l else "")')
    if [ -n "$A" ]; then hyprctl dispatch "hl.dsp.focus({ window = \"address:$A\" })" >/dev/null; sleep 0.5; "$HERE/lab-tools/result/bin/wtype" -M ctrl -k r -m ctrl; fi
    echo settled
    ;;
  down)
    if [ -f "$PIDF" ]; then kill -- -"$(ps -o pgid= "$(cat "$PIDF")" | tr -d ' ')" 2>/dev/null || kill "$(cat "$PIDF")" 2>/dev/null || true; rm -f "$PIDF"; fi
    # Electron detaches from the runner's process group; find every process
    # that carries the lab T3 home in its environment and stop it.
    for pid in $(python3 - "$T3HOME" <<'PY'
import os, sys
home = sys.argv[1].encode()
for pid in os.listdir('/proc'):
    if not pid.isdigit(): continue
    try:
        env = open(f'/proc/{pid}/environ', 'rb').read()
    except Exception:
        continue
    if b'T3CODE_HOME=' + home in env or b'--home-dir' in env and home in env:
        print(pid)
PY
    ); do kill "$pid" 2>/dev/null || true; done
    sleep 1
    echo stopped
    ;;
  log) tail -n "${2:-40}" "$LOG" ;;
esac
