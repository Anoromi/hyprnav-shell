#!/usr/bin/env bash
# Record the headless output. Usage: record.sh start <name> | stop
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
if [ -f "$HERE/lab/env.json" ] && [ -z "${HNS_LIVE:-}" ]; then
  eval "$(python3 "$HERE/scripts/lab.py" env)"
fi
SCREEN="${HNS_SCREEN:-HEADLESS-QS}"
WF="${WF_RECORDER:-$HERE/lab-tools/result/bin/wf-recorder}"
PIDF=/tmp/hns-record.pid
case "${1:-}" in
  start)
    OUT="$HERE/recordings/${2:-clip}.mp4"
    "$WF" -o "$SCREEN" -f "$OUT" -y -r 60 -c libx264 -p crf=18 -p preset=veryfast >/tmp/hns-record.log 2>&1 &
    echo $! >"$PIDF"; echo "recording $OUT"
    ;;
  stop)
    kill -INT "$(cat "$PIDF")" 2>/dev/null || true
    for i in $(seq 1 40); do kill -0 "$(cat "$PIDF")" 2>/dev/null || break; sleep 0.1; done
    rm -f "$PIDF"; echo stopped
    ;;
esac
