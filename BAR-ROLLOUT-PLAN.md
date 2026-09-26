# Plan: hyprnav-shell bar replaces the DMS bar

Status: phase 1 (shell work) done in the lab 2026-09-26, see TESTING.md and recordings/hyprnav-bar.mp4;
phases 2-4 not started. Decision (user): the hyprnav bar becomes the daily bar. No
`/etc/nixos` change until a phase is approved.
Phase 1 took the recommended open decisions: session-memory centre, bar on all displays.
Departures: the control centre has area/screen screenshot tiles but no record button (no
wf-recorder or wl-screenrec on the host); clipboard history is vicinae's own, so no cliphist.

## What DMS provides today on the live session

From `dmsSettings` in `anoromi/home.nix` (left sidebar, all displays): launcher button,
workspace switcher, clock, system tray, clipboard history, notification button + centre,
battery, control centre (Wi-Fi, Bluetooth, audio, brightness, night light, power profiles).
Outside the bar: lock screen (PAM, lid-close policy via a systemd inhibitor), idle/dim, OSD
for volume/brightness, notification popups, polkit agent, wallpaper.

## What hyprnav-shell has

`shell/bar/Bar.qml` (left column, 44 px, pins, workspace pips, tray, clock, battery, network
and Bluetooth glyphs), `QuickSettings.qml` (Wi-Fi list + connect, Bluetooth toggle/devices,
audio sink + volume, brightness; tested read-only for connectivity), `notifications/Popups.qml`
+ `NotificationCard.qml` (popups, no history centre), `Caption.qml`. No lock screen, no idle,
no OSD, no clipboard history, no polkit agent, no launcher.

## Gap list and how each is closed

| DMS feature | Plan | Effort |
|---|---|---|
| Bar, clock, battery, tray, workspaces | exists; audit tray (StatusNotifierItem menus, scroll), battery states, multi-monitor | ½ d |
| Control centre | exists as QuickSettings; add power profiles (`power-profiles-daemon` over DBus), night light (`hyprsunset` or `wlsunset` toggle), and a screenshot/record shortcut row | 1 d |
| Notification popups | exists; add do-not-disturb toggle in QuickSettings | ¼ d |
| Notification history | new: `NotificationCenter.qml` panel from the bar button, persisted in memory for the session, grouped by app, clear-all | 1 d |
| Clipboard history | not a shell job: use `cliphist` + a bar button that opens the existing launcher (vicinae) clipboard view; document the keybind | ¼ d |
| Launcher button | bar button runs `vicinae` (already installed); no new launcher | ¼ h |
| OSD (volume/brightness) | new small `Osd.qml`: listens to PipeWire volume and brightness changes, shows a 1.5 s pill near the bar; reuses Slider style | ½ d |
| Lock screen | **not in the shell**: use `hyprlock` (nixpkgs) with a contact-sheet theme + `hypridle` for lid/idle; keep the existing lid inhibitor pattern pointed at hyprlock. This removes the "lockscreen app died" failure mode DMS hit | ½ d |
| Polkit agent | `hyprpolkitagent` (nixpkgs) as a user service | ¼ h |
| Wallpaper | already `hyprpaper` | 0 |

## Rollout phases

1. **Shell work** (≈3.5 d, lab-verified, recorded): gaps above, `HNS_COMPONENTS=bar,qs,popups,
   center,osd` gating, `TESTING.md` checks, and a 60 s clip of the bar/control centre/
   notification centre/OSD. Idle-cost check: no polling of the daemon; network/Bluetooth
   watchers via DBus signals only. Wi-Fi/Bluetooth tests stay read-only except connecting to
   the already-connected network.
2. **Shadow week** (Nix, approved separately): bump `hyprnav-shell` input; set
   `HNS_COMPONENTS` to include the bar; keep DMS running with its bar hidden (`visible = false`
   in `dmsSettings`) so lock, OSD, notification centre and polkit still come from DMS. User
   lives with the hyprnav bar for several days; issues go into `TESTING.md`.
3. **Cut-over** (Nix): enable notification centre + OSD in the shell, add `hyprlock`,
   `hypridle`, `hyprpolkitagent` services, `cliphist`; stop `dms.service` and drop it from the
   config; move the lid inhibitor to hyprlock. `nixos-rebuild test` first, with a fallback
   keybind that starts DMS manually for one generation.
4. **Cleanup**: remove DMS input and settings after two weeks without regressions.

## Verification (each phase)

Lab: testbed L2 extended with bar/control-centre/notification-centre/OSD checks (open,
toggle, close; notification arrives via `notify-send` and appears in popups and centre; OSD
on `wpctl set-volume`; tray item from a test SNI app). Live, read-only: `systemctl --user`
states, no `hyprctl` polling over a minute, screenshot of the bar on both outputs.

## Open decisions

1. Notification centre scope: session memory only (recommended) vs persisted across restarts.
2. Lock: `hyprlock` (recommended) vs keeping DMS only for lock during the shadow week.
3. Bar on all displays (as DMS) vs primary only.
