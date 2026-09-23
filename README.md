# hyprnav-shell

A Quickshell shell for Hyprland whose centrepiece is hyprnav navigation. The
lab runs the full shell on a headless output. The Nix package runs its
navigation surfaces beside DMS in the live session.

Design direction: a photographer's contact sheet. See [design/DIRECTION.md](design/DIRECTION.md).

## What is in it

- **Switcher**: most-recently-used workspaces as one row of live frames, a
  pencil ring that slides between them, the environment title below.
  Tab / Shift+Tab step, Enter opens, Esc cancels, digits jump.
- **Grid**: every hyprnav environment as a roll, every slot as a frame with a
  live thumbnail. Arrows or hjkl move, Enter opens, Shift+L locks the roll,
  digits open that frame, Esc closes. Inherited slots have a dashed frame.
  A roll wider than the window wraps onto further lines of the same roll;
  left and right walk it in reading order across a line break, up and down
  move between lines and leave the roll only from its first or last line,
  Home and End are the roll's first and last frame.
- **Bar**: a 44 px column on the left edge. Current frame number on top, the
  rest of the roll as clickable digits below it, the environment title running
  along the edge, then tray, notifications, Wi-Fi, Bluetooth, sound, battery,
  and a stacked clock at the bottom.
- **Quick settings**: one sheet with Wi-Fi (scan, connect, password prompt),
  Bluetooth (power, connect, search), sound (volume, output picker),
  brightness, battery, and notification history.
- **Notifications**: popups top right, kept in history.

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
`caption`, `bar`, `quick-settings`, and `notifications`. An unset value in a
direct `qs -p shell` run enables all components for the lab. Set it explicitly
to select surfaces; the live launcher leaves an explicit value alone.

```sh
nix-build lab-tools -o lab-tools/result   # once: cage, virtual seat, wtype, wf-recorder
scripts/lab.py up            # disposable Cage + nested Hyprland + hyprnav daemon
scripts/run.sh start         # shell on the lab's TEST output
scripts/run.sh ipc call switcher open
scripts/run.sh ipc call grid toggle
scripts/run.sh ipc call qs toggle
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
  services/            Hyprnav (daemon socket client), Audio, Brightness, Notifs
  switcher/  grid/  bar/  notifications/
  fonts/               Recursive (OFL), see LICENSE-Recursive.txt
scripts/               lab.py, seed.sh, run.sh, record.sh, demo.sh, headless.sh,
                       sticking-test.sh, sticking-demo.sh (hyprnav hard-sticking checks),
                       agent-demo + agent-demo-app.py (GTK4 demo agent: countdown, then an approval dialog)
lab-tools/             nix expression for the lab compositor tools (self-contained)
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
