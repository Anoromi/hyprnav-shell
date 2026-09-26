# Testing

All checks ran in the lab compositor (`scripts/lab.py up`) on 2026-09-19 with
Hyprland 0.56.2 and Quickshell 0.3.1. The live session was locked during the
work, which is why nothing was verified on the physical output.

| Area | How | Result |
|---|---|---|
| Daemon client | `run.sh ipc call nav ping` | socket found under the lab runtime dir, connected |
| Grid snapshot | debug panel, then grid overlay | rows for agents, shell, shell.docs with correct slots, lock and inheritance |
| Switcher | `ipc call switcher open`, `step`, keyboard Tab/Return via wtype | ring slides, activation switches workspace, title cross-fades |
| Grid | `ipc call grid open`, arrows via wtype, Shift+L, Return, digits | selection moves across rows, lock toggles and refreshes, goto works |
| Thumbnails | grid and switcher on inactive workspaces | live content for ghostty, kitty, Zen, Nautilus, including two-window layout |
| Bar | screenshot | environment, frame number, slot strip, clock, Wi-Fi SSID, Bluetooth, volume, battery |
| Wi-Fi | quick settings, scanner on | real network list with signal, connected marker, lock glyph |
| Bluetooth | quick settings | paired devices listed, search button |
| Sound | `wpctl set-volume` while sheet open | slider follows live, sink listed |
| Brightness | sheet | reads sysfs, write blocked without udev rule and says so |
| Notifications | `notify-send` in lab | popup appears, history fills, clear all empties |
| Recording | `scripts/demo.sh` | 1920x1080 h264 in recordings/, workspace changes visible |

## Bugs found by the first recording (fixed 2026-09-19)

1. The first video showed no workspace switching. The lab compositor used a
   hyprlang config, but the hyprnav daemon dispatches Lua-style calls
   (`hl.dsp.focus({ workspace = N })`), which a non-Lua Hyprland rejects with
   "Invalid dispatcher". The lab now uses a Lua config like the live session.
2. The hyprnav daemon accepts one connection at a time. The shell's client
   held a persistent connection, which blocked every other hyprnav client
   (CLI, `hyprnav trigger`). The client now opens one short connection per
   request, like the Rust CLI does. Verified: `hyprnav goto` works while the
   shell runs, and switcher and grid activation change the active workspace.

Not verified: connecting to a new Wi-Fi network (would change the machine's
connection), Bluetooth connect (no device in range), tray menus (no tray apps
in the lab), multi-monitor.

## Hard sticking (2026-09-19, later the same day)

`scripts/sticking-test.sh` and `scripts/sticking-demo.sh` drive the hyprnav
hard-sticking feature in the lab with dev builds selected through
`HNS_PLUGIN_SO` and `HNS_HYPRNAV_BIN`. Evidence and scenario table live in the
hyprnav repo (`HARD-STICKING-TESTING.md`). Recordings: `recordings/sticking.mp4`,
`recordings/sticking-demo.mp4`.

Shell fix found by that work: `WorkspaceThumb` kept a `ScreencopyView` bound
to a toplevel even while the overlay was hidden. When such a toplevel closed,
the compositor sent an invalid-object error and Quickshell's Wayland
connection died. The capture source is now null unless the overlay is shown.

## Temporary slots and palette (2026-09-20)

`scripts/temp-slots-demo.sh` records `recordings/temp-slots.mp4`: Ctrl+P
palette, "New temporary slot and run…" with kitty, End to reach the new
frame, rename, close all windows, the 30 s empty timer, release. Evidence
table in the hyprnav repo (`TEMP-SLOTS-TESTING.md`).

### Where a temporary slot shows (2026-09-23)

A temporary slot appears at the end of the roll of the environment that owns
it, and nowhere else. Checked in a lab of its own (`lab.py up` with
`HNS_HYPRNAV_BIN` on a fresh daemon build) against `shell` with a temp on
workspace 103 and its child `shell.docs` with a temp on 104:

| Where | What is there |
|---|---|
| `ui_snapshot_grid`, `shell` row | slots 1, 2, 3, then 1000 (`Parent scratch`, ws 103) |
| `ui_snapshot_grid`, `shell.docs` row | slots 1 and 3 inherited from `shell`, its own 2, then its own 1000 (`Docs scratch`, ws 104) — no ws 103 |
| `ui_snapshot_switcher` | six numbered cards; neither ws 103 nor ws 104 |
| Switcher overlay | same six cards, ring cycles through them only |

The daemon does the filtering (`slot_indexes_for_environment` for the grid,
`build_switcher_snapshot` for the MRU list). `Switcher.qml` drops any card
whose grid cell is `unnumbered`/`temporary` as well, which keeps the shell
right when it talks to an older daemon.

Lessons: `Hyprland.dispatch` from Quickshell does not carry Lua dispatcher
calls on 0.56; the grid runs `hyprctl dispatch` as a `Process`. `Palette` is a
Qt type name, so the component is `CommandPalette`. Window actions read
`hyprctl -j clients` rather than Quickshell's toplevel cache, and the plugin
now emits move events so that cache stays right for stuck windows.

## Event-driven agent and slot state (2026-09-20)

The daemon grew a push socket (`events.sock`, see the hyprnav repo's
`EVENTS-TESTING.md` for the protocol evidence) and the shell stopped polling
it. `services/Hyprnav.qml` holds one persistent connection to that socket and
re-exposes it as `agents`, `agentsEvent` and `slotsEvent`; `AgentBadges.qml`
lost its 1 s timer and its per-tick `hyprctl -j clients` run, and `Grid.qml`
lost its 2 s refresh.

| Check | How | Result |
|---|---|---|
| Badge on a driven window | `hyprnav agent register` + `agent beat --target <address>` on a lab kitty | badge and outline appear within a frame of the beat, no timer |
| Badge removal | `hyprnav agent finish` | badge and outline gone |
| Grid follows temporary slots | grid open, `hyprnav slot temp --name evgrid`, then `slot remove` | frame appears and disappears on `slots` events |
| Reconnect | shell started while `events.sock` was missing, daemon restarted afterwards | shell picked the socket up on its own within the 2 s retry |
| No regressions | switcher open/cancel, `run.sh ipc call nav ping`, bar | unchanged |

Idle cost over 20 s with the grid closed, `/proc` CPU jiffies plus a `/proc`
scan for `hyprctl` execs:

| | shell CPU | `hyprctl` runs by the shell |
|---|---|---|
| before, no agents | 0.170 s | 13 |
| before, one live agent | 0.230 s | 19 |
| after, no agents | 0.010 s | 0 |
| after, one live agent | 0.000 s | 0 |

## Wrapped rolls (2026-09-23)

A roll with more frames than the window is wide now wraps. `scripts/lab.py up`,
`scripts/run.sh start`, a 14-slot `fleet` environment and a 3-slot `shell` one,
1920x1080: six frames a line, so the big roll takes three lines and the stack
measures 608 + 240 px and still centres.

| Check | How | Result |
|---|---|---|
| Wrap | grid open, screenshot | frames 1-6, 7-12, 13-14 on three lines, same size and gap |
| Next roll follows | same screenshot | `hyprnav shell` sits below the wrapped roll's real height, not one row down |
| Right across a line break | wtype Right x6 from frame 1 | ring lands on frame 7, first column of the second line |
| Down between lines | wtype Down | frame 7 to frame 13, same column |
| Down out of the roll | wtype Down from the last line | first line of the next roll, nearest column |
| Up back into a roll | wtype Up | last line of the roll above, same column |
| End / Home | wtype End, Home | last frame (14, second column of line three) and frame 1 |
| Enter on a wrapped frame | wtype Return on frame 13 | compositor switches to that workspace, bar shows 13 |
| Overflow | 16 + 4 + 3 frames, 1088 px of rolls | `rowsTop` clamps to 80 and the last roll runs off the bottom; no scrolling yet |

Recording: `recordings/grid-wrap.mp4` (`scripts/grid-wrap-demo.sh`).

## A grid that scrolls (2026-09-23)

The stack of rolls now scrolls inside a viewport of `height − 80 − 80` px
(920 px at 1080). `scripts/lab.py up`, `scripts/run.sh start`, five
environments — a 32-frame `fleet`, then `shell`, `docs`, `lab` and `notes` —
for 2088 px of rolls against a 920 px viewport, with fifteen live windows
spread through them. Wheel input comes from `lab-tools`' new `hns-lab-scroll`,
a wlr-virtual-pointer client that moves the pointer and sends wheel or
touchpad axis events.

| Check | How | Result |
|---|---|---|
| Opens scrolled | active workspace on frame 32, sixth line of the roll; `ipc call grid open` | opens at `scrollY` 240 with the ring 698..847 px down the viewport |
| Ring stays in view | Home, then nine Down presses to the end of the stack, then nine Up presses, screenshot each step | the ring is inside the viewport in all nineteen frames; once it reaches an edge it stays put and the rolls slide under it |
| Stack slides | same walk | `scrollY` moves the minimum needed, animated over `Theme.tRise` |
| Wheel | `hns-lab-scroll` with the pointer parked off the frames | the stack moves, the ring travels with it, the selection does not change |
| Fades | screenshots at the top, middle and end of the stack | the top fade appears only above `scrollY` 0, the bottom only below the maximum |
| Indicator | screenshot 0.12 s after a wheel click and again 2 s later | a 3 px hair on the right edge, 405 px long at the right offset, gone after the 800 ms idle |
| Enter on a scrolled cell | Return on `hyprnav shell` frame 2 near the bottom of a scrolled viewport | compositor switches to workspace 6 |
| Stack that fits | two rolls, 480 px | centred exactly as before, no fades, no indicator |
| No thumbnail blink | 195 frames at 60.3 fps over 3.2 s of continuous wheel scrolling, `signalstats` per frame plus `blackdetect` | no black frame and no single-frame luminance outlier; the montage of 24 consecutive frames shows every thumbnail filled |
| Idle cost | `strace -e connect,execve` over a 2.4 s scroll window | 0 connections to `hyprnav.sock`, 0 `execve` |

Two things did not match the plan. `ensureVisible` leaves the fade depth
(48 px) of margin rather than one `rowGap` (32 px): at 32 px the ring's top
edge sat inside the top fade and was visibly dimmed. And the first check could
not be staged as written — the daemon sorts the environment holding the active
workspace to row 0 regardless of recency or hierarchy, so the current row is
never the last one; the equivalent guarantee, that the grid opens already
scrolled to the current frame, was checked instead.

Recording: `recordings/grid-scroll.mp4` (`scripts/grid-scroll-demo.sh`), 38 s.

## The bar as the daily bar, phase 1 (2026-09-26)

Plan: `BAR-ROLLOUT-PLAN.md`, phase 1. Lab: `scripts/lab.py up`, then
`scripts/lab.py audio` (new: a private PipeWire and WirePlumber with no ALSA,
Bluetooth or camera monitors and one null sink, "Lab speakers", so
`wpctl set-volume` never moves the host's volume or DMS's OSD on the live
output), and the shell started with `HNS_BACKLIGHT=/tmp/hns-bl`, a fake panel:

```sh
mkdir -p /tmp/hns-bl && echo 120 > /tmp/hns-bl/max_brightness && echo 60 > /tmp/hns-bl/brightness
HNS_BACKLIGHT=/tmp/hns-bl scripts/run.sh start
```

hyprsunset is not installed on the host; the lab got it from the flake's
nixpkgs (`nix build --inputs-from . nixpkgs#hyprsunset -o /tmp/hns-hyprsunset`,
prepended to `PATH` in `lab/env.json`). A lab vicinae ran with
`XDG_DATA_HOME=lab/data` so its clipboard history was the lab's own. Pointer
clicks come from `hns-lab-scroll --click left|right|middle` (new).

| Check | How | Result |
|---|---|---|
| Popup and centre entry | `lab.py exec notify-send` x7 across three apps, one critical | 7 popups; after 5 s only the critical one stays; `ipc call center state` lists Calendar 1, Build 5, Mail 1 |
| Centre | bell click, screenshot | groups newest first, three cards per group plus "Show 2 more", per-group Clear, Clear all, DND row; opening marks all seen (bell count gone) |
| Do not disturb | tile click in quick settings, then two notify-sends | normal one: 0 popups, 1 centre entry; critical one: popup shown |
| Tray | `scripts/tray-test.py` (own icon pixmap, dbusmenu) | icon in the bar; left click → `Activate`, middle → `SecondaryActivate`, wheel → `Scroll -120 vertical` and the NeedsAttention dot; right click → menu sheet; "Keep it checked" toggles its check, "Say hello" sends a notification that lands in popups and centre |
| Tray re-registration | shell restart | the item re-registers with the new watcher (the test script watches the name) |
| Volume OSD | `wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.45`, `set-mute 1` | pill beside the bar with 45, then muted glyph and "off"; hides after 1.5 s |
| Brightness OSD | `echo 90 > /tmp/hns-bl/brightness` | pill with the brightness glyph and 75 |
| Night light | tile click | `hyprsunset -t 4000` runs, `hyprctl hyprsunset temperature` answers 4000; click again stops it; one found running after a shell restart is shown as on and stopped with `pkill -x hyprsunset` |
| Power profile | click Saver, then Balanced | `powerprofilesctl get` on the host follows (power-saver, balanced); restored to balanced at once |
| Launcher | bar button | vicinae's root search opens |
| Clipboard | two `wl-copy` in the lab, bar button | vicinae's clipboard history with both entries |
| Multi-monitor | `hyprctl output create headless TEST2`, shell with `HNS_SCREEN` empty | a bar on each output; each shows the frame of its own screen's workspace (1 and 3); popups and OSD only on the focused screen and they follow `focusedmon`; `ipc call qs open` opens on the focused screen |
| Battery, Wi-Fi, Bluetooth glyphs | read-only, host UPower/NetworkManager/BlueZ | battery 92–97 % with the charging and full glyphs; "Plugged in, full" in the sheet; Wi-Fi SSID and connected marker; Bluetooth adapter on, 0 connected |
| Logind brightness path | `busctl call … SetBrightness ssu backlight amdgpu_bl1 <current value>` on the host | exit 0 without root, value unchanged; an inotify watch on the sysfs file saw the write |

Idle cost. The shell ran under `strace -f -tt -e trace=execve` with every
component, the tray test item and the lab vicinae, 15 s to settle, then 70 s
untouched: 0 `execve` in the window. Over the whole run the shell executed
nine processes, all at start: `qs`, the three `sh` one-shots (backlight and
brightnessctl, night-light tool, hyprnav socket) and their `head`, `ls`,
`pgrep`. No `hyprctl`, `nmcli`, `bluetoothctl`, `wpctl` or `brightnessctl`
at any time. CPU over 20 s idle, `/proc` jiffies: 0 with
`switcher,grid,badges,caption`, 0.08–0.09 s with the bar. The bar's share
follows D-Bus signals: the host's UPower sent about 3 `PropertiesChanged` a
second during the run (battery and AC line, with udevd unit changes at the
same time), each one re-evaluating the battery glyph.

Findings fixed on the way:

1. Tray clicks never reached the items: the system cluster's `MouseArea`
   covered the tray column. The tray is now its own group, and its menu
   opened at (0, 0); it now opens beside the item as a sheet.
2. Popups and the OSD showed on every screen; they now follow the focused one.
3. Every bar showed the focused screen's frame; each now shows its own.
4. Plain JS records stored in a `list<var>` or passed as a `var` property are
   copied, so identity comparisons failed and popups never expired.
   Notification records are matched by a key.
5. A click aimed at a quick-settings tile landed on a Wi-Fi row once the scan
   list grew the sheet and opened the password prompt for an unknown network
   (dismissed, nothing connected, `nmcli` showed the same connection). Clicks
   in tests and the demo now open the sound section first; the Wi-Fi view is
   only shown through IPC.

Not verified in the lab: a real battery discharging to the low-battery warn
colour, Wi-Fi or Bluetooth connection changes (not attempted, by rule),
wlsunset (not installed; the command line is untested), brightness keys that
the firmware handles without a userspace write (inotify would not see them),
area screenshots (slurp needs a drag), and a tray app with submenus.

Recording: `recordings/hyprnav-bar.mp4` (`scripts/bar-demo.sh`), 65 s.
