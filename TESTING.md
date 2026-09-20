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
