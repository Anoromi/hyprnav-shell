#!/usr/bin/env bash
# Record the fast switcher: Super+Tab opens on the next frame through a
# global shortcut, Tabs step, the Super release switches; Esc cancels; the
# grid toggles on Super+A. Keys come from hns-lab-keys (real keycodes and
# modifier state, so the compositor binds fire as for a physical keyboard).
#
# Needs: `lab.py up` (its config carries the global binds) and the shell
# running (`scripts/run.sh start`), with a few workspaces holding windows.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
eval "$(python3 "$HERE/scripts/lab.py" env)"
K="$HERE/lab-tools/result/bin/hns-lab-keys"
cap() { qs -p "$HERE/shell" ipc call caption display "$1" "$2" >/dev/null; }
keys() { "$K" "$@" >/dev/null; }

sleep 1
"$HERE/scripts/record.sh" start "${1:-fast-switcher}"
sleep 1.0
cap "Hold Super, tap Tab: the switcher is up ~45 ms after the key" 3800
sleep 0.8
keys down:Super_L sleep:60 tap:Tab sleep:1400
cap "More Tabs step through recent workspaces" 2600
keys tap:Tab sleep:800 tap:Tab sleep:1100
cap "Let go of Super: that workspace is focused" 2600
keys up:Super_L; sleep 2.2
cap "A quick Super+Tab flips back to the previous one" 2600
sleep 0.6
keys down:Super_L sleep:40 tap:Tab sleep:60 up:Super_L; sleep 1.4
keys down:Super_L sleep:40 tap:Tab sleep:60 up:Super_L; sleep 1.6
cap "Esc cancels; letting go of Super afterwards does nothing" 3400
sleep 0.4
keys down:Super_L sleep:60 tap:Tab sleep:700 tap:Tab sleep:900 tap:Escape sleep:900 up:Super_L; sleep 1.6
cap "Super+A: the grid, same kept surface, thumbnails fill in after" 3600
sleep 0.4
keys down:Super_L tap:a up:Super_L sleep:1400 tap:Right sleep:500 tap:Down sleep:900
keys down:Super_L tap:a up:Super_L; sleep 1.2
keys down:Super_L tap:a up:Super_L sleep:1200 tap:Right sleep:700 tap:Return; sleep 2.0
"$HERE/scripts/record.sh" stop
