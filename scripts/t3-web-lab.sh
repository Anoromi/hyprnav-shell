#!/usr/bin/env bash
# Run T3 Code's web build inside the lab: the server and the Vite dev server
# from the lab worktree, opened in the lab's Zen browser. No Electron.
#
#   scripts/t3-web-lab.sh up [project-dir]     scripts/t3-web-lab.sh down
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="${T3CODE_REPO:-$HOME/code/stolen/t3code-lab}"
HYPRUSE="${HYPRUSE_REPO:-$HOME/code/experiments/hypr-use}"
LABHOME="$HERE/lab/home"
T3HOME="$HERE/lab/t3home"
SERVER_PORT="${T3_LAB_SERVER_PORT:-16492}"
WEB_PORT="${T3_LAB_WEB_PORT:-8452}"
PIDF="$HERE/lab/t3web.pids"
LOG="$HERE/lab/t3web.log"

# When this script runs from inside a Claude Code session, the child Claude
# that T3 spawns would treat itself as a child session and inherit the parent's
# MCP servers. Drop every trace of the parent session first.
unset_claude_session() {
  for v in $(env | grep -oE '^(CLAUDE[A-Z_]*|CLAUDECODE|MCP_[A-Z_]*|ANTHROPIC_[A-Z_]*)='); do unset "${v%=}"; done
}
unset_claude_session

case "${1:-up}" in
  up)
    PROJECT="${2:-$HERE/lab/demo-project}"
    mkdir -p "$LABHOME/.claude" "$T3HOME" "$PROJECT"
    eval "$(python3 "$HERE/scripts/lab.py" env)"
    [ -f "$HERE/lab/t3-buildenv.sh" ] && source "$HERE/lab/t3-buildenv.sh"
    # The build env replaced PATH; put the lab's hyprnav (dev build) back in front.
    HNB="${HNS_HYPRNAV_BIN:-/tmp/hns-hyprnav-result/bin/hyprnav}"
    [ -x "$HNB" ] && export PATH="$(dirname "$(readlink -f "$HNB")"):$PATH"
    for f in .credentials.json settings.json; do
      [ -e "$LABHOME/.claude/$f" ] || cp "$HOME/.claude/$f" "$LABHOME/.claude/$f"
    done
    python3 - "$HOME/.claude.json" "$LABHOME/.claude.json" "$HYPRUSE/mcp/hypr-use-mcp-inherit" <<'PY'
import json, sys
src, dst, launcher = sys.argv[1:]
d = json.load(open(src))
keep = {k: v for k, v in d.items() if k not in ("projects", "mcpServers")}
keep["mcpServers"] = {"cua_repl": {"type": "stdio", "command": launcher, "args": [], "env": {}}}
keep["projects"] = {}
json.dump(keep, open(dst, "w"), indent=2)
PY
    export HOME="$LABHOME"
    export XDG_CONFIG_HOME="$LABHOME/.config" XDG_DATA_HOME="$LABHOME/.local/share" XDG_STATE_HOME="$LABHOME/.local/state" XDG_CACHE_HOME="$LABHOME/.cache"
    mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME/hypr-use"
    cp -n /home/anoromi/.local/share/hypr-use/headless-env.json "$XDG_DATA_HOME/hypr-use/" 2>/dev/null || true
    export HYPR_USE_HOST_NAME=claude
    # Whatever MCP launcher Claude resolves, target this session's compositor.
    export HYPR_USE_SESSION=inherit
    export T3CODE_HOME="$T3HOME"
    : >"$LOG"
    # Server: web runtime mode, bootstraps the demo project from its cwd argument.
    ( cd "$REPO/apps/server" && nohup node src/bin.ts "$PROJECT" --mode web --port "$SERVER_PORT" --base-dir "$T3HOME" --no-browser --auto-bootstrap-project-from-cwd >>"$LOG" 2>&1 & echo $! >"$PIDF" )
    # Web: single-origin dev server proxying /api and /ws to the backend.
    ( cd "$REPO/apps/web" && PORT="$WEB_PORT" T3CODE_PORT="$SERVER_PORT" T3CODE_SINGLE_ORIGIN_DEV=1 nohup vp dev >>"$LOG" 2>&1 & echo $! >>"$PIDF" )
    echo "server :$SERVER_PORT web :$WEB_PORT log $LOG"
    ;;
  open)
    # Mint a one-time pairing token and open the web app already paired.
    eval "$(python3 "$HERE/scripts/lab.py" env)"
    [ -f "$HERE/lab/t3-buildenv.sh" ] && source "$HERE/lab/t3-buildenv.sh"
    export HOME="$LABHOME" T3CODE_HOME="$T3HOME"
    TOKEN=$(cd "$REPO/apps/server" && node src/bin.ts pair --base-dir "$T3HOME" 2>/dev/null | grep -oE 'token=[A-Za-z0-9_-]+' | head -1 | cut -d= -f2)
    URL="http://localhost:$WEB_PORT/pair#token=$TOKEN"
    [ -z "$TOKEN" ] && URL="http://localhost:$WEB_PORT/"
    # Dedicated Zen profile: cloned from the onboarded lab profile, with session
    # restore stripped so exactly one window opens.
    ZP=/tmp/hns-zen-t3
    if [ ! -d "$ZP" ]; then cp -r /tmp/hns-zen-profile "$ZP"; fi
    rm -rf "$ZP"/sessionstore-backups "$ZP"/sessionstore.jsonlz4 "$ZP"/sessionCheckpoints.json 2>/dev/null || true
    # Screen share without the browser's own permission doorhanger: the source is
    # chosen by the portal, where hyprnav's picker answers.
    cat >"$ZP/user.js" <<'PREFS'
user_pref("media.navigator.permission.disabled", true);
user_pref("media.getdisplaymedia.enabled", true);
user_pref("media.webrtc.capture.allow-pipewire", true);
user_pref("media.navigator.permission.fake", false);
user_pref("privacy.webrtc.legacyGlobalIndicator", false);
user_pref("privacy.webrtc.hideGlobalIndicator", true);
PREFS
    for pid in $(pgrep -f "zen-beta.*--profile $ZP" 2>/dev/null); do kill "$pid" 2>/dev/null || true; done; sleep 1
    hyprctl dispatch "hl.dsp.focus({ workspace = ${2:-2} })" >/dev/null; sleep 0.3
    hyprctl dispatch "hl.dsp.exec_cmd(\"zen-beta --new-instance --profile $ZP $URL\", { workspace = \"${2:-2} silent\" })" >/dev/null
    echo "opened $URL"
    ;;
  down)
    [ -f "$PIDF" ] && while read -r pid; do kill -- -"$(ps -o pgid= "$pid" 2>/dev/null | tr -d ' ')" 2>/dev/null || kill "$pid" 2>/dev/null || true; done <"$PIDF"; rm -f "$PIDF"
    pkill -f "src/bin.ts $HERE/lab/demo-project" 2>/dev/null || true
    echo stopped
    ;;
  log) tail -n "${2:-40}" "$LOG" ;;
esac
