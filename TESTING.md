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

## Control centre speed, click-away and motion (2026-09-26)

The user reported the control centre as "very laggy and slow" on the live
2880x1800 panel. Measured in the lab (1920x1080, `scripts/lab.py up`,
`lab.py audio`, `HNS_BACKLIGHT=/tmp/hns-bl`) against a worktree of
`a5cd160` with the same probe added. `HNS_PERF=1` turns on `PerfProbe.qml`:
time from `show()` to the window's next swapped frame, the longest GUI-thread
stall (a 4 ms timer that notices when it runs late) over the first 1.5 s,
and frame intervals while a slider is dragged. Pointer drags come from
`hns-lab-scroll --drag` (new: press, N moves `--delay` ms apart, release).
The lab compositor now uses the live session's `fade` animation (speed 7).

Root causes, with the evidence:

1. **A new window on every open.** `QuickSettings` (and the centre) set
   `visible: phase !== "closed"`, which destroys the layer surface on close.
   `QSG_INFO=1` showed `Creating QRhi with backend OpenGL for window 0x…` on
   every open, a different window address and render thread each time, a new
   GL context, pipeline cache seeding and a fresh glyph atlas; the first
   frame's sync took 8 ms and the GUI thread sat in `blockedForSync` 17–22 ms.
   The hover tooltip (a `PopupWindow` toggled per hover) and the OSD paid the
   same on every appearance.
2. **The compositor fade.** A freshly mapped layer surface gets Hyprland's
   layer fade; with the live `fade` speed of 7 the sheet reached 90 % of its
   final brightness after 250 ms and settled after 400 ms (60 fps recording
   of a patch on the volume slider). A kept-mapped surface is never re-mapped,
   so only the shell's own 180 ms rise plays.
3. **Scan and rebuild.** Every open turned the Wi-Fi scanner on, even for the
   sound view. The network and Bluetooth lists were sorted inside a binding,
   so each scan result or signal-strength change produced a new array and the
   `Repeater` destroyed and rebuilt every row, hidden sections included.
4. **Smaller:** the night-light probe forked `sh` from the GUI thread on
   every open; the slider thumb waited for PipeWire or the backlight file to
   echo the value before moving; a brightness write while one was running was
   dropped.
5. Not found: no blur or shadow effects anywhere, no fonts or images loaded at
   open (fonts load once in `Theme`), no synchronous process calls (Quickshell
   `Process` is asynchronous; `nmcli`/`bluetoothctl`/`wpctl` are not used).

Fixes: `bar/SheetWindow.qml` keeps the surface mapped and switches the input
region (`mask`), keyboard interactivity and the sheet's opacity/offset; the
tooltip strip and the OSD stay mapped with an empty input region. The Wi-Fi
and Bluetooth lists are refreshed on a 250 ms debounce while the sheet is
open and assigned only when the set or order changes (signal strength sorts
in coarse steps); the scan starts after the Wi-Fi view has been open for 1 s
or from its Scan button, and stops on close. Night light probes at most every
30 s, 400 ms after the rise. Sliders move from a local value while dragged;
brightness keeps one write in flight, at least 40 ms apart, and always writes
the last value.

| Measure | Before (`a5cd160`) | After |
|---|---|---|
| `show()` to first swapped frame, sound view, 6 opens | 19, 26, 33, 41, 45, 191 ms (another run: 28–67, one 265) | 0–2 ms (24 ms on the first open after start) |
| Wi-Fi view, 3 opens | 30–36 ms | 1–3 ms |
| Notification centre, 4 opens | 20–34 ms | 1 ms |
| Longest GUI stall in the first 1.5 s | 32–69 ms | 0 ms at first frame |
| Frames during the open animation (first 300 ms) | 8–12, worst interval up to 76 ms | 12–13, worst 18 ms (one 33 ms) |
| On screen, 90 % / settled (60 fps recording) | 250 / 400 ms | 100 / 133 ms |
| Close, on screen | 67–133 ms | 100 ms |
| Volume drag, 90 moves at 8 ms | 60 fps, GUI stalls 39–137 ms, thumb follows PipeWire | 60 fps (mean 16.6–17.1 ms), GUI stalls 13–15 ms, thumb follows the pointer |
| Brightness drag | 60 fps, one write per pointer event when idle | 60 fps, writes coalesced, last value lands (8/120 for a release at 6.5 %) |
| Hover label | new popup window per hover | no window created |

The lab machine was also running other work; the before numbers varied
between runs, the after ones did not. The live panel is 2880x1800 with DMS
beside the shell, where each window creation also allocated larger buffers;
not measured there (by rule the live session is not touched).

A side finding from the recordings: with the old code a second click on the
cluster without moving the pointer was ignored after the sheet's surface had
just been mapped (Hyprland had not re-targeted pointer focus); with kept
surfaces it toggles every time.

### Click-away

| Tried | Result |
|---|---|
| `HyprlandFocusGrab` on the sheet and the bar | outside press clears the grab and closes; bar clicks still work; but with `WlrKeyboardFocus.Exclusive` the grab is cleared the moment it starts, and with `OnDemand` Esc only works after a click inside |
| Exclusive keyboard for as long as the sheet is open | Esc works; Hyprland then delivers no presses to any other surface, the catcher never sees one |
| **Kept:** `ClickCatcher.qml` (Top layer, whole screen right of the bar, empty input region until a sheet opens) plus Exclusive keyboard for the first 100 ms, then OnDemand | press on the desktop closes (the press is not passed on); Esc closes; press on the clock leaves it open; the cluster button toggles it; same for the centre and the tray menu |

### Motion and polish

Theme tokens: `tHover` 120, `tOpen` 180, `tClose` 110, `tStaggerList` 22,
`riseDistance` 12, one radius (`rSheet`/`rControl` 8). All become 0 with
`HNS_REDUCED_MOTION=1`.

| Element | Check | Result |
|---|---|---|
| Sheets and tray menu | open/close via bar, IPC | rise from the bar edge (12 px, scale 0.97 to 1, fade, OutCubic 180 ms), close InCubic 110 ms |
| Bar buttons | hover, press | Emulsion wash and 1 px lift, press shrinks to 0.96, 120 ms |
| Workspace pips | click 3, 4, 1 | frames stay in slot order, the Pencil block springs between them |
| Tiles | night light, do not disturb | fill, Pencil edge and icon cross-fade |
| Sliders | drag | thumb grows 1.35x, value label turns Pencil and bold; outside changes glide |
| Notification centre | open with four entries in two groups | headers and cards rise 22 ms apart; × slides the card out and closes the gap |
| OSD | `wpctl set-volume`, backlight writes | same rise and faster exit |
| Bar glyphs | screenshot | one family at 16 px, tray icons flattened to Paper (MultiEffect on a 15 px icon), clock in the regular mono cut, date and battery spaced off their glyphs |
| Grid | long temporary names | frame badge and empty timer elide inside the frame |

Recording: `recordings/hyprnav-bar-polish.mp4` (`scripts/bar-polish-demo.sh`
plus a 10 s half-speed before/after), 62 s.

## Switcher and grid speed, hold-to-switch (2026-09-26)

The user asked for a switcher and grid that open at once and for Super+Tab to
switch when Super is released. Lab: `scripts/lab.py up`, output at
1920x1080@120 for the timing runs, live `fade` speed 7. Keys come from the new
`hns-lab-keys` (`lab-tools/keys.c`): one virtual keyboard with the US keymap,
real keycodes and modifier state, printing the epoch time of each event.
`wtype` could not be used: none of its keys triggered any compositor bind.
`HNS_PERF=1` logs the shortcut or IPC arrival, `show()`, the snapshot
arrival, the first swapped frame and the moment the content reaches full
opacity, all as epoch ms. The before build is `a391999` with the same probe
lines plus a probe global shortcut bound next to the old `exec_cmd` bind, so
its log carries the compositor's key time. On-screen timing comes from 120 fps
recordings (per-frame mean luma of a strip of the scrim).

| Stage | Before (`a391999`, 6–10 runs) | After |
|---|---|---|
| (a) key → bind's process running (`exec_cmd`, bash wrapper) | 4–8 ms | none: global shortcut, 0–3 ms key → shell |
| (b) `qs ipc` client start + IPC delivery | 21–33 ms (key → IPC 26–75 ms) | none |
| daemon MRU snapshot (`ui_snapshot_switcher`) awaited before open | 60–233 ms (55–75 ms idle, straight on the socket) | not awaited: opens from a warm snapshot |
| grid snapshot awaited | 36–68 ms | not awaited |
| (c) new window → first frame | 20–108 ms switcher, 24–42 ms grid | 8–11 ms key → first frame (surface kept mapped) |
| (d) Hyprland layer fade on the new surface | 217 ms to 90 %, 342 ms to 98 % (reduced motion, so ours off) | none (never re-mapped) |
| (e) our motion | scrim 120 ms, cards 160 ms rise + 6 px y, ring OutBack scale, spring slide (hidden under (d)) | one 30 ms fade; ring slide 30 ms |
| key → first frame, switcher | 108–416 ms | 8–16 ms |
| **key → fully visible, switcher** (first frame + fade to 98 %) | **~460–770 ms** (90 %: ~320–630 ms) | **41–49 ms** (full-opacity stamp); recording: first change → 98 % in 33–42 ms |
| key → first frame, grid | 89–169 ms | 2–13 ms |
| **key → fully visible, grid** | **~440–520 ms** | **34–44 ms**; thumbnails fill in over the next frames |
| close | 67 ms + unmap | 33 ms |

Why the daemon is slow is the daemon's business (`build_switcher_snapshot`
resolves every card); the shell keeps `Services.Hyprnav.switcher` fresh on
the same debounced compositor events that already refresh the grid (no
timer), opens from it, and when the fresh snapshot for this open arrives it
moves the ring only if the user has not stepped yet.

Behaviour, `/tmp`-scripted with `hns-lab-keys`:

| Check | Result |
|---|---|
| Super+Tab, release | switches to the previous MRU workspace, 8/8 runs, window focused |
| Super+Tab, Tab, Tab, release | third MRU entry |
| Super+Tab, Tab, Shift+Tab, release | back to the second |
| Super+Tab released 10 ms after Tab | still switches (a commit before the first snapshot is kept and applied) |
| Super+Tab, Esc, release | nothing switches |
| bare Super tap, switcher closed | nothing |
| Super+Tab, Return while held | switches once; the release after it is a no-op |
| Tab release while Super held | does not commit (only the Super release does) |
| Super+A, Super+A | grid opens, closes |
| Super+A, Right, Return | switches, window focused |
| both key/modifier event orders (key then modifiers, as Hyprland's `bindr = SUPER, SUPER_L` handling expects, and the reverse) | one commit each |

Findings on the way:

1. **Release binds on a modifier are shadowed** once another bind fires while
   it is held: `hl.bind("Super_L", …, { release = true })` fired for a bare
   Super tap but never after Super+Tab. `transparent = true` keeps it. Bound
   with and without `SUPER +` so either modifier state at release matches.
2. **Global binds from Lua**: `hl.dsp.global("appid:name")`. A release bind
   delivers the shortcut's `released` signal, which is what `switcher-commit`
   acts on; `pressed` from a press bind drives open/step/grid.
3. **Focus hand-back undid the switch** about half the time once the surface
   stayed mapped: when Hyprland processes the layer's keyboard release after
   the workspace switch, it refocuses the window that had focus before, on the
   old workspace. `FocusRelease.qml` now sends the goto only after the frame
   that commits the release (8/8 correct afterwards; holding focus until the
   daemon answered failed 6/6).
4. **Layer rules must match the whole namespace**: `^hyprnav-shell-` matched
   nothing; `^hyprnav-shell-.*$` removes the fade (the old build's switcher
   then reached full opacity on its first visible frame). Kept for the
   surfaces that still map and unmap: captions, agent badges, popups.

Not measurable here: the compositor's cost of two more always-mapped
full-screen transparent overlays (the nested Hyprland spins at 100 % of a core
in the lab regardless). The shell itself stays at 0 jiffies over 10 s idle;
the hidden overlays draw nothing and their thumbnails capture nothing.

Recording: `recordings/fast-switcher.mp4` (`scripts/fast-switcher-demo.sh`), 27 s.

## Control centre lists in fixed boxes (2026-09-26)

The Wi-Fi, Bluetooth and output lists in the control centre and the groups
in the notification centre grew with their rows, so a sheet opened during a
scan jumped in height as results came in. Every list now sits in a box of
fixed height from `Theme` and scrolls inside it (`bar/ScrollList.qml`,
a `ListView` with `clip`, and `bar/ScrollEdges.qml`, the grid's 32 px
fades and 3 px position hair at sheet scale):

| List | Box | Pinned above the box |
|---|---|---|
| Wi-Fi | 7 rows of 40 px, 304 px | the connected network |
| Bluetooth | 5 rows of 40 px, 216 px | connected devices, at most two |
| Outputs (sinks) | 3 rows of 34 px, 110 px | none; the default carries a tick |
| Notification centre | 560 px | none |

The pinned rows take room from the top of the box, so the box keeps its
height whether something is connected or not. An empty box holds a quiet
placeholder: "Scanning…", "Wi-Fi is off.", "No Wi-Fi adapter found.",
"No networks in range.", "Searching…", "No devices.", "No outputs." and the
centre's "Nothing yet…". The Wi-Fi password prompt now covers the bottom of
the box (the list gets a bottom margin so every row can still be reached)
instead of adding 76 px to the sheet. Power profiles are three fixed
segments and were left alone.

Lab: `scripts/lab.py up` (from a worktree with its own `lab/`),
`lab.py audio`, and the shell with fake radios, which are new:
`HNS_FAKE_WIFI=<n>` and `HNS_FAKE_BT=<n>` swap NetworkManager and BlueZ for
`services/FakeRadios.qml`. The fake Wi-Fi device has one connected network
at once, and the other n−1 arrive one by one over 2 s after the scan
starts. The fake adapter has a connected pair of headphones and a paired
keyboard, and the rest arrive over 2 s after a search starts. Signal
strengths wobble every 700 ms. `ipc call qs fakeReset` starts them over. With
the fakes on, every radio control in the sheet drives the fake objects, so
no check scanned, toggled or connected on the host.

| Check | How | Result |
|---|---|---|
| Height while Wi-Fi fills | `HNS_FAKE_WIFI=16`, `ipc call qs section wifi`, screenshots at 0, 0.9, 1.8, 2.7 s | the sheet top stays at the same y in all four: "Scanning…" under the pinned Darkroom row, then rows filling the box |
| Height while Bluetooth fills | `HNS_FAKE_BT=9`, click "Search for devices", screenshots before, at 0.6 s and 3 s | same sheet top; devices arrive under the pinned headphones |
| Centre while notifications arrive | centre open empty, nine `notify-send` 150 ms apart | same sheet top from "Nothing yet…" to nine cards in three groups; the last cards fade under the bottom edge |
| Wheel | `hns-lab-scroll --at 250 900 1` | one click moves 1.5 rows with a 120 ms glide. Before the fix it did nothing: every row's `Pressable` has a `MouseArea` with `onWheel`, which took the event. `ScrollEdges` now catches the wheel above the rows, and presses and hover still reach them |
| Touchpad, drag | `--finger 30 30 30`, `--drag` | follow the pointer 1:1; drag stops at the ends (`StopAtBounds`) |
| Keys | `hns-lab-keys tap:Down tap:End tap:Up` | the visible list has focus on open and on a section change; Up/Down move a row, PageUp/PageDown a box, Home/End the ends; Esc still closes the sheet |
| Fades and hair | screenshots at the top, middle and end | the top fade only when scrolled, the bottom one only while more is below; the hair shows while moving and is gone 800 ms later; rows arriving below do not flash it |
| Delegates kept | `HNS_PERF=1` logs each row's creation; 16 networks, wobbling strengths and reorders, seven wheel scrolls | 16 rows created, one per network. With the `ListView`'s default cache, rows scrolled out and back were created again (23), so the box keeps all rows (`cacheBuffer` 3000, 60 rows at most) |
| Scroll position | scroll one click at 2 s, while networks are still arriving | new rows below leave `contentY` alone. Saved and strong networks sort in above the view, so the top visible row is anchored and held in place (it stayed at the top) |
| Open speed | `HNS_PERF=1`, six opens across wifi/bluetooth/sound, three centre opens | first frame 1–4 ms, 0 ms GUI stall, worst frame interval in the rise 17–18 ms (as before) |
| Without fakes | shell started with `HNS_FAKE_*` unset, sound view only | no QML warnings; lists built from the host's cached data, read only; the Wi-Fi view was not opened, so no scan |

The sheet's height `Behavior` (a 160 ms glide while it is open) is
unchanged. It now only plays when you switch between views, because a view
no longer changes height by itself.

Found on the way: the Wi-Fi rows compared against `WifiSecurityType.None`,
which does not exist (the enum has `Open`). The lock glyph showed on every
network, and an open network asked for a password. They now use `Open`.

Recording: `recordings/hyprnav-cc-lists.mp4` (`scripts/cc-lists-demo.sh`), 27 s.

## Merged rolls for nested environments (2026-09-27)

A thread (`p.x.w.a.t`) resolves slots through its worktree (`p.x.w`) and
project (`p.x`), so the worktree's frames are the same workspaces in every
thread. The grid showed the worktree and each thread as separate rolls with
the same thumbnails twice. The daemon now emits one row per leaf environment
(rule in the hyprnav README, "grid"); the shell draws it with shared frames
tagged, a lock glyph and a breadcrumb. Lab: own worktree and lab instance
(`HNS_HYPRNAV_BIN` = the nix build of the daemon change),
`scripts/grid-merged-demo.sh seed|record`.

| Check | How | Result |
|---|---|---|
| Rows | `ui_snapshot_grid` over the socket after seeding `p.x` "Proj", untitled `p.x.w` with 1–3, `p.x.w.a.t` "Design Hypernav Workspace UI" with 5, 8, `p.x.w.b.t` "Other" with 4 | two rows: `p.x.w.a.t` = 1, 2, 3 shared (owner `p.x.w`), 5, 8 own; `p.x.w.b.t` = 1, 2, 3 shared, 4 own. No `p.x.w` row |
| Header | screenshot | "Design Hypernav Workspace UI", lock glyph, "in Proj"; "Other", lock glyph, "in Proj". The untitled worktree is not in the breadcrumb and no id is shown |
| Lock on an ancestor | `hyprnav lock p.x.w` | both rows carry the lock glyph (`locked_environment_id` = `p.x.w`); the bar's rail lists the worktree's frames 1–3 only (an untitled worktree has no monogram) |
| Cells | screenshot, clip | shared frames are ordinary frames with "shared" after the name, no dashed border; "here" and the ring as before |
| Enter | Enter on "Other" frame 4 | switches to workspace 4 through the leaf |
| Refresh path | unchanged | rows still rebuild from the event-driven snapshot; nothing polls |

Recording: `recordings/grid-merged.mp4`, 15 s.

### A shell crash on a closing window (2026-09-27)

The live shell died at 10:27:31 with `wl_display#1: error 0: invalid object
185`, a fatal Wayland error, about five minutes after it started. Its log
shows six window captures (`screencast>>1,window`) starting together and not
one of them stopping for four minutes, with no workspace or focus event in
between; then Cursor's window closed, its capture stopped, and the connection
died. So the thumbnails were capturing with no overlay in sight, and a
capture still bound to a window that closes is exactly how this error
happens (see "Hard sticking" above).

Fixes:

1. `WorkspaceThumb` drops a window's capture when Hyprland's `closewindow`
   for that address arrives on the IPC socket, which comes before the
   toplevel's `closed` on the Wayland connection.
2. The grid and switcher thumbnails capture while `open || finish.running`
   (open or fading out) instead of `phase !== "closed"`, so a phase left
   behind can no longer keep captures alive unseen.
3. `Switcher.show()` stopped the fade timer before it knew whether it would
   present. If nothing presented (no cached snapshot, and a refresh that was
   superseded or empty), the phase stayed at "activating" or "cancelling"
   for good, with every thumbnail capturing. The timer is now stopped only
   by `present()`.

In the lab, with the grid open, killing two captured kitty windows left the
shell running with each fix in place; the unfixed thumbnail did not crash
either, so the close race does not reproduce on demand and (3) is the likely
cause found by reading, not a reproduced one. Opening and closing the grid
and the switcher starts four captures and stops all four at close.

## The grid opens on the frame you are in (2026-09-27)

Two faults. The grid took its first selection from the daemon's
`initial_index`, which only looks in row 0 and falls back to row 0 col 0, so a
frame in any other roll opened on the wrong cell. And the cell under a resting
pointer took the selection at open: the compositor's pointer enter on the
newly opened surface reached the cells as `entered`, and since any selection
change set `userMoved`, the fresh snapshot could no longer correct it either.

Now the grid picks the cell itself: the focused workspace from Hyprland's
event stream, first row first, then a locked roll, then the roll that owns a
shared frame. Hover goes through `HoverGate.qml`: inert after the open until
the pointer has travelled more than 8 px in window coordinates from the first
position seen, so neither the enter nor cells scrolling under a resting
pointer count. A click still opens the cell under it. The switcher uses the
same gate. `userMoved` is set only by keys, an armed hover and the palette.

`scripts/grid-select-demo.sh seed | record` in the lab (thread roll locked,
a second thread, a temporary slot, a 30-frame roll):

| Check | Before (HEAD e1c1bb7) | After |
|---|---|---|
| a. Active is frame 8, column 4 of row 0 | row 0 col 4 | row 0 col 4 |
| b. Active is the temporary slot (ws 101) | row 0 col 6 | row 0 col 6 |
| c. Pointer resting on the Editor cell (col 2), open | row 0 col 2, stolen | row 0 col 4; moving 14 px selects col 2 |
| d. Active is frame 24 of the long roll | row 0 col 0, not scrolled | row 1 col 23, opened scrolled to it |
| Switcher, pointer resting on card 2 | selected 2 | selected 1 (MRU); moving selects 2 |
| Keys (Right, Left, Down, Up, End, Home, Ctrl+P, Esc) | | unchanged |

Clip `recordings/grid-select.mp4` (30 s); screenshot of check c with the
pointer marked.

## No layout shifts (2026-09-27)

The user reported "too many layout shifts" in the daily bar. Every element
that could change size or place at runtime was checked; each shift found is
either fixed or confined so it moves nothing anchored.

| Shift | Where (before) | Fix |
|---|---|---|
| Locked rail moved when the workspace list grew or shrank | `bar/Bar.qml` `mid.y` = centre of the room below `topView` | the rail's head sits at `midTop`, a function of the bar height only (a four-frame roll centred on the bar; moved up only on a bar too short for it). The list above clips and scrolls at the head |
| Rail moved when its own frame count changed (lock change, roll length) | same, `y` centred on its own height, with a `Behavior on y` | head fixed; the rail grows and shrinks downward only; the appear scale grows from the top (0.96 → 1) instead of the centre |
| Rail moved when a tray icon appeared or left | `selBottom` fed the centring | the rail's anchor ignores the tray; a tray that grows into the rail's room only shortens the rail's scroll box |
| Launcher, clipboard and bell moved up when tray icons appeared | tray group sat between them and the cluster | the tray is now the top group of the bottom stack; the stack hangs from the clock, so the tray grows upward into free space |
| Control centre changed height per view (Wi-Fi 573, Bluetooth 525, sound 515 px; sheet top at y 498/546/556) | `QuickSettings.qml`, sheet height = `content.implicitHeight` | one view area of `Theme.qsViewH` (336 px, the Wi-Fi view's); Bluetooth's list box fills it; sound and brightness scroll inside it (`Flickable` + `ScrollEdges`) |
| "Performance limited" line pushed the tab strip down | under the power profile row | moved to the end of the sound view, inside the fixed area |
| Wi-Fi "Scan"/"Scanning" button changed width | header row | fixed to the width of "Scanning" |
| Lock glyph and names in Wi-Fi/Bluetooth rows slid as the status word changed ("saved" → "connecting" → "connected") | `NetRow`, `BtRow` | status words in a fixed right-aligned column the width of "connecting" |
| Output tick glyph vs blank | sink rows | fixed 16 px glyph column |
| OSD slider moved between volume and brightness glyphs | `Osd.qml` | glyph column fixed at 20 px |
| Popups below an expiring one jumped up | `notifications/Popups.qml` | `move` transition (`Theme.tHover`); the window height follows the gliding cards so none is clipped |
| Grid breadcrumb ("in Proj") slid sideways on Shift+L | `grid/Grid.qml` header: title, lock, breadcrumb | lock glyph moved to the end of the header row (not screenshotted; the grid loads without warnings) |
| Tray delegate warning on removal | `Bar.qml` tray item anchors | `parent ? … : undefined` |

Checked and left as is (no shift, or intentional):

- Clock: hours and minutes are two digits in the mono cut; day and month are
  single centred lines in a fixed column, nothing beside them.
- Battery percent (9 vs 100): mono, centred, nothing beside it. The battery
  column itself shows only when UPower reports a battery (hardware presence).
- Workspace and rail digits: fixed 28 px cells, centred; the current-one
  bold/size change is a `scale` on the text, not layout.
- Notification badge on the bell: an overlay anchored to the button.
- Bar glyphs (Wi-Fi strength, Bluetooth, volume): `CrossGlyph` centred in
  fixed 32×28 cells. Monogram: centred in a fixed 36×24 box.
- Hover and press on `Pressable`: a 1 px lift and a 0.96 scale are
  transforms, neighbours never move (kept, part of the motion language).
- Tab labels (SSID length) and tile sub-labels: elided in fixed tiles.
- Notification centre: fixed box (`Theme.centerListH`); the header's count
  and "Clear all" appear without moving the title. New cards are added at the
  top of the list (newest first), which is the list growing, inside the box.
- Tray menu: grows downward from the item's row; only clamped at the screen
  bottom would a submenu move its top (not seen with the tray now higher).
- Fonts: `FontLoader` on local files is ready before first layout; the Nerd
  Font glyphs come from the installed font.

Lab: `scripts/lab.py up`, `lab.py audio`, envs `agents` (frames 1–4) and
`shell` (5, 6), kitty on 1, 2, 3, 5, 6, shell with `HNS_FAKE_WIFI=12
HNS_FAKE_BT=6` and the fake backlight. The same scripted walk ran on the old
tree (`git archive e1c1bb7`) and the new one, one grim screenshot per state,
then PIL measured positions and diffed crops.

| State change | Before: rail head y | After: rail head y | After: pixel diff of the rail crop (0..44 × 440..640) vs base |
|---|---|---|---|
| base, `agents` locked | 365 | 458 | — |
| +2 workspaces (7, 8) | 397 | 458 | identical |
| +10 workspaces (list overflows) | 525 | 458 | identical (list clips at 14 and scrolls) |
| workspaces removed | 365 | 458 | identical |
| lock `shell` (2 frames) | 397 | 458 | lock row identical; rail ends 64 px higher |
| unlock, relock | 365 | 458 | identical |
| tray icon appears | 343 | 458 | identical; launcher to clock crop identical |
| notification arrives | 343 | 458 | identical; bottom crop differs only in the bell badge |
| tray icon leaves | 365 | 458 | identical |

| Control centre view | Before: sheet top border y | After |
|---|---|---|
| Wi-Fi | 498 | 498 |
| Bluetooth | 546 | 498 |
| Sound | 556 | 498 |
| Wi-Fi again | 498 | 498 |

Notification centre: sheet top 383 before and after 3 more cards (it was
already fixed). No QML warnings in the new run's log (apart from the lab's
missing icon theme).

Artifacts: `~/Artifacts/hyprnav-bar-stable.png` (before and after, side by
side, cyan guides at the rail head and the sheet top) and
`~/Artifacts/hyprnav-bar-stable.mp4` (35 s: lock change, workspaces added and
removed, tray icon, every control centre view, notifications, centre).
