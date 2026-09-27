#!/usr/bin/env bash
# Layout-stability walk for the bar's three groups (TESTING.md, "No layout
# shifts"): top list hanging from the top edge, the middle group centred,
# the locked roll standing on a baseline above the clock. Walks lock change,
# lock cleared, relock, 2 and 10 workspaces added and removed, a tray icon
# arriving and leaving and a notification, with one screenshot per state,
# records the walk, then measures and diffs the screenshots with PIL.
#
# Needs: `lab.py up`, `lab.py audio`, the shell running in the lab
# (`HNS_FAKE_WIFI=12 HNS_FAKE_BT=6 qs -p shell`), and a Python with Pillow in
# HNS_PIL_PYTHON (default /tmp/hns-pypil/bin/python3; build one with
#   nix build --impure --expr 'let p = (builtins.getFlake "nixpkgs").legacyPackages.x86_64-linux;
#     in p.python3.withPackages (ps: [ ps.pillow ])' -o /tmp/hns-pypil ).
# Sets up its own environments: `agents` (frames 1-5 on workspaces 1-5) and
# `shell` (frames 1-2 on 6-7), kitty on 1, 2, 3, 5, 6. Output in
# /tmp/hns-stable/ (shots, report) and recordings/hyprnav-bar-v4.mp4.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
eval "$(python3 "$HERE/scripts/lab.py" env)"
PY="${HNS_PIL_PYTHON:-/tmp/hns-pypil/bin/python3}"
OUTDIR=/tmp/hns-stable
# `--analyse`: only measure the shots of the last walk.
if [ "${1:-}" != "--analyse" ]; then
rm -rf "$OUTDIR"; mkdir -p "$OUTDIR"
n() { hyprnav "$@" >/dev/null; }
ex() { hyprctl dispatch "hl.dsp.exec_cmd(\"kitty\", { workspace = \"$1 silent\" })" >/dev/null; }
focus() { hyprctl dispatch "hl.dsp.focus({ workspace = $1 })" >/dev/null; }
clients() { hyprctl clients -j | python3 -c "import json,sys; print(len(json.load(sys.stdin)))"; }
wait_clients() { for _ in $(seq 1 60); do [ "$(clients)" -ge "$1" ] && return; sleep 0.2; done; }
# Pids of the kitty windows on workspaces >= $1.
pids_from() { hyprctl clients -j | python3 -c "import json,sys; print(' '.join(str(c['pid']) for c in json.load(sys.stdin) if c['workspace']['id'] >= $1))"; }

n env ensure --env agents --title "Agent fleet"
n env ensure --env shell --title "hyprnav shell"
for i in 1 2 3 4 5; do n slot assign --env agents --slot "$i" --workspace "$i"; done
n slot assign --env shell --slot 1 --workspace 6
n slot assign --env shell --slot 2 --workspace 7
for w in 1 2 3 5 6; do
  hyprctl clients -j | python3 -c "import json,sys; sys.exit(0 if any(c['workspace']['id']==$w for c in json.load(sys.stdin)) else 1)" || ex "$w"
done
wait_clients 5
qs -p "$HERE/shell" ipc call center clear >/dev/null 2>&1 || true
focus 2; n lock agents
"$HERE/lab-tools/result/bin/hns-lab-scroll" --at 900 540 >/dev/null 2>&1 || true
sleep 1.5

LOG="$OUTDIR/states.tsv"
"$HERE/scripts/record.sh" start hyprnav-bar-v4-raw >/dev/null
T0=$(date +%s.%N)
sleep 0.6
state() {   # state <name> <caption>: log the caption's start
  printf '%s\t%s\t%s\n' "$(python3 -c "print(round($(date +%s.%N) - $T0, 2))")" "$1" "$2" >>"$LOG"
}
shot() { sleep "${2:-2.2}"; grim -o "$HNS_SCREEN" "$OUTDIR/$1.png"; sleep 0.5; }

state base "Locked roll: 5 frames, standing above the clock"; shot base 2.6
state lock2 "Lock another roll (2 frames): only its top moves"; n lock shell; shot lock2
state unlock "Lock cleared: the space stays empty"; n unlock; shot unlock
state relock "Locked again"; n lock agents; shot relock
state ws2 "Two workspaces added at the top"; ex 8; ex 9; wait_clients 7; shot ws2
state ws12 "Ten more: the list scrolls above the middle"
for w in 10 11 12 13 14 15 16 17 18 19; do ex "$w"; done; wait_clients 17; shot ws12 1.6
state wsdel "Workspaces removed"; kill $(pids_from 8); shot wsdel
state tray "A tray icon takes a reserved slot"
"$HERE/lab-tools/result/bin/python3" "$HERE/scripts/tray-test.py" >"$OUTDIR/tray.log" 2>&1 &
TRAY=$!; shot tray
state notif "A notification: only the bell changes"
notify-send -a Build "cargo check finished" "0 errors"; shot notif
state trayoff "The tray icon leaves"; kill "$TRAY"; shot trayoff
sleep 0.6
"$HERE/scripts/record.sh" stop >/dev/null
qs -p "$HERE/shell" ipc call center clear >/dev/null 2>&1 || true

# The clip: the bar and 436 px of desktop at 2x, with the state captions.
FONT="$HERE/shell/fonts/RecursiveSansLnrSt-Med.ttf"
FILTER=$(python3 - "$LOG" "$FONT" <<'EOF'
import sys
rows = [l.rstrip("\n").split("\t") for l in open(sys.argv[1])]
font = sys.argv[2]
parts = ["crop=480:1080:0:0", "scale=960:2160:flags=neighbor"]
for i, (t, _, cap) in enumerate(rows):
    end = rows[i + 1][0] if i + 1 < len(rows) else "999"
    cap = cap.replace(":", r"\:").replace("'", "")
    parts.append(f"drawtext=fontfile={font}:text='{cap}':x=120:y=150:fontsize=30:fontcolor=0xEDE6DA:"
                 f"box=1:boxcolor=0x1A1917E6:boxborderw=14:enable='between(t,{t},{end})'")
print(",".join(parts))
EOF
)
RAW="$HERE/recordings/hyprnav-bar-v4-raw.mp4"
ffmpeg -v error -y -i "$RAW" -vf "$FILTER" -c:v libx264 -pix_fmt yuv420p -crf 18 -preset slow -movflags +faststart "$HERE/recordings/hyprnav-bar-v4.mp4"
rm -f "$RAW"
ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$HERE/recordings/hyprnav-bar-v4.mp4"
fi

# Measurements.
"$PY" - "$OUTDIR" <<'EOF'
import sys, os
from PIL import Image, ImageChops
d = sys.argv[1]
names = [l.split("\t")[1] for l in open(os.path.join(d, "states.tsv"))]
shots = {n: Image.open(os.path.join(d, n + ".png")).convert("RGB").crop((0, 0, 43, 1080)) for n in names}
H = 1080
SHEET = (0x26, 0x24, 0x21)
def ink(im, y0, y1, x0=0, x1=43):
    rows = [y for y in range(y0, y1) if any(max(abs(a - b) for a, b in zip(im.getpixel((x, y)), SHEET)) > 24 for x in range(x0, x1))]
    return (rows[0], rows[-1]) if rows else None
base = shots["base"]
# Middle group: its ink in the base state (no tray) lies between the top
# list (ends near y 170) and the roll (starts near y 775).
mt, mb = ink(base, 230, 740)
MID = (mt - 8, mb + 8 + 1 + 8 + 124 + 4)          # plus hairline and the four tray slots
# Clock: the ink below the roll's baseline (the roll ends near y 968).
ct, cb = ink(base, 978, H)
def rule_bottom(im):   # the roll's Pencil rule at x 4..5
    ys = [y for y in range(MID[1], ct) if im.getpixel((4, y))[0] > 120 and im.getpixel((4, y))[2] < 90]
    return (ys[0], ys[-1]) if ys else None
def bbox(a, b, box):
    return ImageChops.difference(a.crop(box), b.crop(box)).getbbox()
# The middle group's cells, from its ink runs in the base state (glyphs made
# of separate parts merged), split halfway between neighbours.
runs = []
for y in range(mt, mb + 1):
    if ink(base, y, y + 1):
        if runs and y - runs[-1][1] <= 6: runs[-1][1] = y
        else: runs.append([y, y])
names_mid = ["launcher", "clipboard", "bell", "wifi", "bluetooth", "volume", "battery", "battery %"]
if len(runs) != len(names_mid): names_mid = [f"cell{i}" for i in range(len(runs))]
cells = []
for i, (r0, r1) in enumerate(runs):
    top = MID[0] if i == 0 else (runs[i - 1][1] + r0) // 2
    bot = (r1 + runs[i + 1][0]) // 2 if i + 1 < len(runs) else r1 + 6
    cells.append((names_mid[i], top, bot))
cells.append(("tray slots", cells[-1][2], MID[1]))
out = []
out.append(f"middle group region y {MID[0]}..{MID[1]} (ink {mt}..{mb}); clock ink y {ct}..{cb}")
out.append("cells: " + ", ".join(f"{n} {a}..{b}" for n, a, b in cells))
out.append("state\ttop pip 1 (y 12..40)\tmiddle cells differing from base\troll rule y\tclock ink y\tclock crop")
for n in names:
    im = shots[n]
    pip = "identical" if bbox(base, im, (0, 12, 43, 40)) is None else f"DIFF {bbox(base, im, (0, 12, 43, 40))}"
    diff = [c for c, a, b in cells if bbox(base, im, (0, a, 43, b)) is not None]
    mid = "identical" if not diff else "differ: " + ", ".join(diff)
    rb = rule_bottom(im)
    rb = "no roll" if rb is None else f"{rb[0]}..{rb[1]}"
    c = ink(im, 978, H)
    cc = "identical" if bbox(base, im, (0, 978, 43, H)) is None else "differs (minute tick)"
    out.append(f"{n}\t{pip}\t{mid}\t{rb}\t{c[0]}..{c[1]}\t{cc}")
rep = "\n".join(out)
print(rep)
open(os.path.join(d, "report.txt"), "w").write(rep + "\n")
EOF
