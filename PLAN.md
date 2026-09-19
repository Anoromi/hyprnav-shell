# hyprnav-shell: plan

Date: 2026-09-19. Status: experiment. Lives in `~/code/experiments/hyprnav-shell`.
Does not touch DMS, `/etc/nixos`, or the hyprnav repo unless a step says so.

## Goal

A Quickshell shell whose centrepiece is hyprnav navigation: an MRU workspace
switcher and an environment/slot grid, with live window thumbnails and
deliberate motion. Around it, a bar with the usual quick settings: workspaces,
clock, tray, battery, Wi-Fi, Bluetooth, audio, brightness, notifications.
Developed and recorded on a headless Hyprland output next to the live session.

## Decisions already made

| Topic | Decision |
|---|---|
| Relationship to DMS | Experiment. Runs on a headless output. No swap-in. |
| Nav surfaces | Both MRU switcher and environment grid. |
| Previews | Live thumbnails via `ScreencopyView` (hyprland-toplevel-export), icon fallback. |
| System features | Full bar set: workspaces, clock, tray, battery, Wi-Fi, Bluetooth, audio, brightness, notifications. |
| Aesthetic | Fresh, opinionated direction from the Anthropic `frontend-design` skill, mockup shown before build. |

## Verified facts the plan relies on

- Hyprland 0.56.2, Quickshell 0.3.1 with `Quickshell.Hyprland`, `Wayland`,
  `Bluetooth`, `Networking`, `Services/{Pipewire,Notifications,SystemTray,UPower,Mpris}`.
- hyprnav daemon socket: `$XDG_RUNTIME_DIR/hx/<fnv1a64(instance sig)>/hyprnav.sock`,
  one JSON request per line tagged with `"op"` in snake_case, one JSON response line.
  `ping`, `ui_snapshot_grid`, `ui_snapshot_switcher`, `workspace_goto`,
  `workspace_goto_physical`, `lock_set`, `lock_clear`, `slot_*`, `env_*` all exist.
  Verified live: `{"op":"ui_snapshot_grid","cwd":null}` returns rows and cells.
- `hyprctl output create headless NAME` works; the output appears at 1920x1080.
- gpu-screen-recorder is installed (AMD Strix Halo, VAAPI). grim and ffmpeg exist.
- DMS 1.7 QML source is readable at
  `/nix/store/y50nanjwxbc850cdc0yaigvsdnp7iipj-dms-shell-*/share/quickshell/dms`
  for porting Wi-Fi, Bluetooth, and audio logic.
- hypr-agent-portal plugin is loaded and the `cua_repl` MCP can deliver
  targeted input and screenshots, useful for driving the overlay on the headless output.

## Phases

### Phase 0: tooling (small)

1. Install the Anthropic `frontend-design` skill into `~/.agents/skills/frontend-design`
   (sparse clone of `anthropics/skills`, `skills/frontend-design`). It is symlinked
   into this workspace via `.claude/skills`.
2. Write `scripts/headless.sh`: create/remove output `HEADLESS-QS`, set a fixed
   1920x1080 at scale 1, move a test workspace onto it, and print its name.
3. Write `scripts/record.sh`: gpu-screen-recorder against the headless output
   to `recordings/<name>.mp4`, with a grim+ffmpeg fallback if gpu-screen-recorder
   refuses headless outputs. Verify one 3 second clip before anything else.
4. Write `scripts/run.sh`: `qs -p ./shell -d` restricted to the headless screen
   via an env var so the live eDP-1 is never touched.

Exit: a recorded clip of an empty headless output plays back.

### Phase 1: design direction

1. Run the `frontend-design` skill against this brief: subject is compositor
   workspace navigation for a developer who runs agents in many workspaces.
2. Produce a token file `shell/Theme.qml`: 4 to 6 named colours, one or two
   typefaces (check what fonts are installed first), spacing scale, radius scale,
   and a motion spec (durations, easings, and what moves on open, step, activate, close).
3. Produce a static mockup of the switcher and grid as a rendered image, and show it.

Exit: user approves direction, or asks for one revision.

### Phase 2: hyprnav data layer

1. `shell/services/Hyprnav.qml`: singleton wrapping `Quickshell.Io.Socket`.
   Computes the socket path (FNV-1a of `HYPRLAND_INSTANCE_SIGNATURE`), sends one
   request per connection like the Rust client, parses the response line.
2. Exposes `gridSnapshot`, `switcherSnapshot`, `status`, and actions
   `gotoSlot(env, slot)`, `gotoPhysical(ws)`, `lock(env)`, `unlock()`.
3. Refresh policy: refetch on Hyprland raw events (`workspace`, `openwindow`,
   `closewindow`, `activewindow`) with a 60 ms debounce, plus on overlay open.
4. `shell/services/Previews.qml`: map workspace id to its toplevels via
   `Quickshell.Wayland.ToplevelManager` and `Quickshell.Hyprland` workspace data,
   feed `ScreencopyView` per card. Fallback to app icon via `Quickshell.iconPath`.

Exit: a debug window on the headless output lists live grid rows and thumbnails.

### Phase 3: MRU switcher overlay

1. Layer-shell overlay, keyboard focus exclusive while open, on the focused monitor.
2. IPC: `qs ipc call switcher step`, `stepBack`, `activate`, `cancel` via
   `IpcHandler`. A sample Hyprland binding file is provided but not installed.
3. Behaviour mirrors hyprnav: first call opens with `initial_index`, repeat calls
   step, release or activate calls `workspace_goto`.
4. Motion: one orchestrated open sequence, a selection move that tracks position
   rather than fading, and a close that resolves into the chosen card.

Exit: recording `switcher.mp4` shows open, step, step back, activate.

### Phase 4: environment grid overlay

1. Rows per environment, cells per slot, using `row_index` and `column_index`
   from the snapshot. Locked environment marked. Inherited slots visually quieter.
2. Keyboard: arrows, Enter to go, `l` to lock/unlock, Esc to close. Mouse works too.
3. Empty slots show the stored launch command name when present.

Exit: recording `grid.mp4` shows navigation, lock toggle, go-to.

### Phase 5: bar and quick settings

1. Bar per screen: hyprnav-aware workspace pill (current env title and slot),
   clock, tray (`SystemTray`), battery (`UPower`).
2. Quick settings popup: Wi-Fi (`Quickshell.Networking` if it covers scan and
   connect on 0.3.1, otherwise `nmcli` via `Process` as DMS does), Bluetooth
   (`Quickshell.Bluetooth`: scan, pair, connect, disconnect), audio
   (`Pipewire` sinks and sources, volume, mute), brightness (`brightnessctl` is
   missing, so sysfs `/sys/class/backlight` via `Process`).
3. Notifications: `NotificationServer` popups plus a history list in the popup.
   Note: only one notification daemon can own the DBus name, and DMS holds it.
   On the headless experiment this part is tested with DMS notifications paused
   or skipped and documented as such.

Exit: recording `bar.mp4` with Wi-Fi list, Bluetooth toggle, volume slide.

### Phase 6: verification and recordings

1. Test matrix in `TESTING.md`: each recording, the command that produced it,
   and what to look for.
2. All clips in `recordings/`, published via the `share-artifacts` skill with a
   short index page.
3. Final self-critique pass using the `frontend-design` and `impeccable` skills,
   screenshots compared against the Phase 1 mockup.

## Layout

```
hyprnav-shell/
  PLAN.md  TESTING.md  README.md
  shell/
    shell.qml              root, screen filter, IpcHandler
    Theme.qml              tokens
    services/  Hyprnav.qml Previews.qml Net.qml Bt.qml Audio.qml Brightness.qml
    switcher/  Switcher.qml WorkspaceCard.qml
    grid/      Grid.qml EnvRow.qml SlotCell.qml
    bar/       Bar.qml WorkspacePill.qml Clock.qml Tray.qml Battery.qml QuickSettings.qml
    notifications/ Popups.qml History.qml
  scripts/   headless.sh record.sh run.sh bindings.example.conf
  recordings/
  design/    mockups and notes
```

## Risks and fallbacks

- `ScreencopyView` on a headless output: toplevel export may only render
  windows the compositor has mapped. Fallback is icon cards; thumbnails still
  work on the real output once swapped in.
- gpu-screen-recorder may not list headless outputs. Fallback: grim frame loop
  at 30 fps into ffmpeg, or `nix run nixpkgs#wf-recorder`.
- `Quickshell.Networking` in 0.3.1 may be read-only. Fallback: `nmcli` via
  `Process`, which is what DMS ships.
- Notification daemon conflict with DMS: documented, not solved in this experiment.
- Delivering keyboard input to a layer-shell surface on the headless output:
  `hyprctl dispatch focusmonitor HEADLESS-QS` then the `cua_repl` keyboard path,
  or `qs ipc call` directly, which bypasses the keyboard entirely.

## Out of scope

Modifying the hyprnav daemon or plugin, replacing DMS in the live session,
touching `/etc/nixos`, Firefox/Chromium tab slots (browser targets show as
cards but get no special UI).
