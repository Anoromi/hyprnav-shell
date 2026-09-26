# hyprnav-shell

A Quickshell shell for Hyprland whose centrepiece is hyprnav navigation. The
lab runs the full shell on a headless output. The Nix package runs its
navigation surfaces beside DMS in the live session.

Design direction: a photographer's contact sheet. See [design/DIRECTION.md](design/DIRECTION.md).

## What is in it

- **Switcher**: most-recently-used workspaces as one row of live frames, a
  pencil ring that slides between them, the environment title below.
  Tab / Shift+Tab step, Enter opens, Esc cancels, digits jump. Temporary
  workspaces are left out: they are neither a card nor a stop in the cycling
  order, so Alt-Tab never lands on one.
- **Grid**: every hyprnav environment as a roll, every slot as a frame with a
  live thumbnail. Arrows or hjkl move, Enter opens, Shift+L locks the roll,
  digits open that frame, Esc closes. Inherited slots have a dashed frame.
  A roll wider than the window wraps onto further lines of the same roll;
  left and right walk it in reading order across a line break, up and down
  move between lines and leave the roll only from its first or last line,
  Home and End are the roll's first and last frame. A stack of rolls taller
  than the window scrolls: it opens already scrolled to the current frame,
  every selection change brings the selected line back into view with the
  smallest move, and the wheel scrolls without touching the selection. Soft
  edges mark a side that still has content behind it and a hair on the right
  shows the position. A stack that fits is centred as before. A temporary slot sits at
  the end of the roll of the environment that owns it, and nowhere else: a
  child roll inherits its ancestors' numbered frames but not their temporary
  ones.
- **Bar**: a 44 px column on the left edge of every screen. On top, the
  roll's monogram (the initials of the first two words of the environment
  title that are not "and", "of", "the" and the like, or the first two
  letters of a one-word title; rolls that would share one all get a digit,
  numbered in environment id order) over its frame numbers in slot order,
  the current one under a block that slides between them (each screen's bar
  follows the workspace on that screen). Two looks: following focus, bare
  digits with the monogram in Fixer and the current frame in Pencil; locked
  to this roll, the frames sit on a Pencil rail with a lock at its head, the
  current frame inverts to Darkroom and the monogram turns Pencil (120 ms,
  the digits never move). Hovering the group shows the full title; clicking
  the monogram locks or unlocks the roll (`lock_set` / `lock_clear`),
  clicking another digit goes there, clicking the current one opens the
  grid. Temporary frames are left out. The daemon records the environment of
  every focused workspace as the lock, so the rail is the usual state and
  the bare look shows after an unlock or on a roll the lock is not on. At
  the bottom, on one 28 px rhythm: launcher and
  clipboard buttons (vicinae), the tray (icons drawn flat in Paper), the
  notification bell, the Wi-Fi/Bluetooth/sound/battery cluster that opens
  quick settings, and a stacked clock. Buttons lift onto an Emulsion wash on
  hover and sink on press (120 ms); hovering shows a label beside the bar.
- **Tray**: left click activates (or opens the menu of a menu-only item),
  right click opens the item's menu drawn as a sheet beside the bar (check and
  radio states, submenus with a back row), middle click is the secondary
  action, the wheel scrolls the item. A Pencil dot marks NeedsAttention.
- **Quick settings**: one sheet with quick tiles (night light, do not disturb,
  area and screen screenshots), the power profile (power-profiles-daemon over
  D-Bus), then Wi-Fi (scan, connect, password prompt), Bluetooth (power,
  connect, search), sound (volume, output picker), brightness and battery.
  Night light runs `hyprsunset -t 4000`, or `wlsunset` where hyprsunset is
  missing; one it finds already running is stopped by exact name.
  Screenshots go to `~/Pictures/Screenshots` and the clipboard (grim, slurp,
  wl-copy).
- **Notifications**: popups top right on the focused screen. The bell opens
  the notification centre: this session's notifications in memory, grouped by
  app (three per group, "show more"), clear per group or all, and do not
  disturb, which holds popups back but still fills the centre; critical
  notifications still pop. The server only runs when `popups` or `center` is
  enabled, so a bar beside DMS never takes `org.freedesktop.Notifications`.
- **Sheets**: quick settings, the notification centre and tray menus are
  sheets beside the bar. Their surfaces are created once and stay mapped with
  an empty input region, so opening is a state change, not a new window: the
  sheet rises from the bar edge (180 ms, ease out) and leaves faster
  (110 ms). A press anywhere off the sheets and the bar closes them (a
  transparent catcher surface, `ClickCatcher.qml`), so does Esc, and the bar
  button that opened a sheet toggles it closed. `HNS_REDUCED_MOTION=1` makes
  every transition instant. `HNS_PERF=1` logs open-to-first-frame, GUI-thread
  stalls and frame intervals during slider drags (`PerfProbe.qml`).
- **OSD**: a pill beside the bar for 1.5 s after the default sink's volume or
  mute changes (PipeWire events) or the backlight changes (inotify on the
  sysfs `brightness` file), on the focused screen.
- **Launcher and clipboard**: `vicinae toggle` and
  `vicinae cmd launch clipboard:history`. vicinae keeps its own clipboard
  history, so no cliphist is needed; bind the same commands in Hyprland for
  the keyboard.

## Run

Build the live package with `nix build .#hyprnav-shell`. Its launcher is
`result/bin/hyprnav-shell`; `result/bin/hyprnav-shell ipc call grid toggle`
targets the same packaged shell. The launcher uses the pinned Quickshell,
loads QML and fonts from the Nix store, clears `HNS_SCREEN`, and defaults
`HNS_COMPONENTS` to `switcher,grid,badges,caption`.
On Ubuntu, the Nix config can pass its Quickshell override with
`hyprnav-shell.override { quickshell = ubuntuQuickshell; }` once that override
provides Quickshell 0.3.1 or newer. The flake exports `packages.<system>.quickshell`
from the same pin so DMS and this package can use one Quickshell build.

`HNS_COMPONENTS` is a comma-separated list of `switcher`, `grid`, `badges`,
`caption`, `bar`, `qs` (quick settings), `popups` (notification popups and
the server), `center` (notification centre), and `osd`. The older names
`quick-settings` (= `qs`) and `notifications` (= `popups,center`) still work.
An unset value in a direct `qs -p shell` run enables all components for the
lab. Set it explicitly to select surfaces; the live launcher leaves an
explicit value alone. For the shadow week beside DMS, `bar,qs` gives the bar
and control centre without touching DMS's notifications or OSD.

Nothing in the bar polls. Network, Bluetooth, battery, power profile and tray
follow D-Bus signals through Quickshell's services, volume follows PipeWire,
brightness an inotify watch. One-shot processes run at start (find the
backlight and brightnessctl, find hyprsunset or wlsunset and whether it
runs, find the hyprnav socket) and when quick settings open (the night light
probe). Brightness writes go through brightnessctl if installed, otherwise
logind's `SetBrightness` (no udev rule needed), otherwise sysfs.

```sh
nix-build lab-tools -o lab-tools/result   # once: cage, virtual seat, wtype, wf-recorder
scripts/lab.py up            # disposable Cage + nested Hyprland + hyprnav daemon
scripts/lab.py audio         # optional: private PipeWire with one null sink
scripts/run.sh start         # shell on the lab's TEST output
scripts/run.sh ipc call switcher open
scripts/run.sh ipc call grid toggle
scripts/run.sh ipc call qs toggle
scripts/run.sh ipc call qs section sound   # wifi | bluetooth | sound
scripts/run.sh ipc call center toggle      # notification centre; also clear, dnd true|false, state
scripts/run.sh ipc call osd show volume    # volume | brightness; osd state
scripts/run.sh ipc call caption display "text" 5000   # large caption for recordings
scripts/demo.sh              # scripted walkthrough, recorded to recordings/
scripts/lab.py down
```

Without a lab (`lab/env.json` absent, or `HNS_LIVE=1`), `run.sh` targets the
live session and restricts the shell to the output named in `HNS_SCREEN`
(default `HEADLESS-QS`, create it with `scripts/headless.sh up`).

## Hyprland bindings

`scripts/bindings.example.lua` shows the binds that call the same IPC entry
points. Nothing is installed automatically.

## Layout

```
shell/
  shell.qml            root, per-screen windows, IPC handlers
  Theme.qml            palette, type, spacing, motion tokens, fonts
  WorkspaceThumb.qml   live miniature of a workspace
  Glyph.qml            Nerd Font icon text
  Osd.qml              volume and brightness pill
  ClickCatcher.qml     click-away for the sheets beside the bar
  PerfProbe.qml        HNS_PERF=1 timing probe
  CrossGlyph.qml       glyph that cross-fades when it changes
  services/            Hyprnav (daemon socket client), Audio, Brightness, Notifs, NightLight, Sheets
  bar/                 Bar, SheetWindow (shared sheet surface), QuickSettings, TrayMenu,
                       Pressable (hover/press states), Slider, Toggle
  switcher/  grid/  notifications/
  fonts/               Recursive (OFL), see LICENSE-Recursive.txt
scripts/               lab.py, seed.sh, run.sh, record.sh, demo.sh, headless.sh,
                       grid-wrap-demo.sh, grid-scroll-demo.sh (grid layout clips),
                       sticking-test.sh, sticking-demo.sh (hyprnav hard-sticking checks),
                       agent-demo + agent-demo-app.py (GTK4 demo agent: countdown, then an approval dialog),
                       tray-test.py (a StatusNotifierItem with a menu), bar-demo.sh (bar clip),
                       bar-selector-demo.sh (roll selector: lock and frames),
                       bar-polish-demo.sh (control centre speed, click-away, motion)
lab-tools/             nix expression for the lab compositor tools (self-contained):
                       cage, the virtual seat, hns-lab-scroll (pointer moves,
                       clicks, drags and wheel injection), wtype, wf-recorder
design/                direction and notes
recordings/            mp4 output
```

## Talking to hyprnav

The daemon listens on `$XDG_RUNTIME_DIR/hx/<fnv1a64(instance signature)>/hyprnav.sock`.
Each request is one JSON line tagged with `op`, each reply one JSON line. The
shell keeps one connection and queues requests. It uses `ui_snapshot_grid`,
`ui_snapshot_switcher`, `status_get`, `workspace_goto`,
`workspace_goto_physical`, `lock_set` and `lock_clear`, and refreshes on
Hyprland `workspace`, `openwindow`, `closewindow`, `activewindow` events.

Beside it the daemon opens `events.sock` in the same directory. That one is
multi-client and write-only, so the shell holds a single connection to it for
good and reconnects every 2 s if it drops. It carries `agents` (the whole
registry, on every agent change) and `slots` (a bare "re-read the grid
snapshot" marker), both coalesced to roughly one event per 50 ms. Agent badges
and the grid follow that stream; nothing in the shell polls the daemon.
