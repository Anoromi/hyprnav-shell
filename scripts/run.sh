#!/usr/bin/env bash
# Run the shell restricted to the headless screen. Usage: run.sh [start|stop|restart|log|ipc ...]
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
if [ -f "$HERE/lab/env.json" ] && [ -z "${HNS_LIVE:-}" ]; then
  eval "$(python3 "$HERE/scripts/lab.py" env)"
fi
export HNS_SCREEN="${HNS_SCREEN:-HEADLESS-QS}"
LOG=/tmp/hyprnav-shell.log
case "${1:-start}" in
  start)
    pkill -f "quickshell -p $HERE/shell" 2>/dev/null || true
    sleep 0.2
    nohup qs -p "$HERE/shell" >"$LOG" 2>&1 &
    echo "started pid $! log $LOG"
    ;;
  stop) pkill -f "quickshell -p $HERE/shell" || true ;;
  restart) "$0" stop; sleep 0.3; "$0" start ;;
  log) tail -n "${2:-40}" "$LOG" ;;
  ipc) shift; qs -p "$HERE/shell" ipc "$@" ;;
  shot) grim -o "$HNS_SCREEN" "${2:-/tmp/hns-shot.png}" && echo "${2:-/tmp/hns-shot.png}" ;;
esac
