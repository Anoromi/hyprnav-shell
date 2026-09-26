//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "services" as Services
import "switcher"
import "grid"
import "bar"
import "notifications"
import Quickshell.Services.UPower

ShellRoot {
    id: root
    readonly property string targetScreen: Quickshell.env("HNS_SCREEN") || ""
    readonly property var screens: Quickshell.screens.filter(s => root.targetScreen === "" || s.name === root.targetScreen)
    // An unset value keeps the full lab shell. The packaged live launcher sets
    // only the surfaces that can coexist with DMS. Names: switcher, grid,
    // badges, caption, bar, qs, popups, center, osd. The older names
    // `quick-settings` (= qs) and `notifications` (= popups,center) still work.
    readonly property string components: Quickshell.env("HNS_COMPONENTS") || ""
    readonly property var aliases: ({ "quick-settings": ["qs"], "notifications": ["popups", "center"] })
    readonly property var enabledComponents: {
        const out = [];
        for (const raw of components.split(",")) {
            const part = raw.trim();
            if (part === "") continue;
            out.push(part);
            for (const a of (aliases[part] ?? [])) out.push(a);
        }
        return out;
    }
    function hasComponent(name) {
        return components === "" || enabledComponents.includes(name);
    }
    // The notification server only runs when something shows notifications,
    // so a bar beside DMS never takes org.freedesktop.Notifications from it.
    Component.onCompleted: Services.Notifs.enabled = hasComponent("popups") || hasComponent("center")

    // Popups, the OSD and IPC-opened sheets go to the focused screen.
    readonly property string focusedName: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    function isPrimary(screen) {
        const names = screens.map(s => s.name);
        return screen.name === (names.includes(focusedName) ? focusedName : names[0]);
    }
    function focused(variants) {
        return variants.instances.find(w => isPrimary(w.screen)) ?? variants.instances[0] ?? null;
    }
    // Quick settings and the centre share the space beside the bar: opening
    // one closes the other on that screen.
    function closeOthers(screen, except) {
        for (const w of Array.from(quick.instances).concat(Array.from(centers.instances)))
            if (w !== except && w.screen === screen) w.close();
    }

    Variants {
        id: switchers
        model: root.hasComponent("switcher") ? root.screens : []
        Switcher {}
    }
    function switcherWin() { return switchers.instances[0] ?? null; }
    Variants {
        id: grids
        model: root.hasComponent("grid") ? root.screens : []
        Grid {}
    }
    function gridWin() { return grids.instances[0] ?? null; }
    Variants {
        id: quick
        model: root.hasComponent("qs") ? root.screens : []
        QuickSettings { id: q; onOpened: root.closeOthers(q.screen, q) }
    }
    Variants {
        id: centers
        model: root.hasComponent("center") ? root.screens : []
        NotificationCenter { id: c; onOpened: root.closeOthers(c.screen, c) }
    }
    Variants {
        model: root.hasComponent("bar") ? root.screens : []
        Bar {
            quickSettings: quick.instances.find(q => q.screen === screen) ?? null
            center: centers.instances.find(c => c.screen === screen) ?? null
        }
    }
    Variants {
        model: root.hasComponent("popups") ? root.screens : []
        Popups {
            primary: root.isPrimary(screen)
            suppressed: Array.from(quick.instances).concat(Array.from(centers.instances)).some(w => w.shown && w.screen === screen)
        }
    }
    Variants {
        id: osds
        model: root.hasComponent("osd") ? root.screens : []
        Osd {
            primary: root.isPrimary(screen)
            suppressed: quick.instances.some(w => w.shown && w.screen === screen && w.section === "sound")
        }
    }
    Variants {
        id: captions
        model: root.hasComponent("caption") ? root.screens : []
        Caption {}
    }
    Variants {
        model: root.hasComponent("badges") ? root.screens : []
        AgentBadges {}
    }
    IpcHandler {
        target: "caption"
        function display(text: string, ms: int): void { captions.instances[0]?.show(text, ms); }
        function hide(): void { captions.instances[0]?.hide(); }
    }
    IpcHandler {
        target: "qs"
        function toggle(): void { root.focused(quick)?.toggle(); }
        function open(): void { root.focused(quick)?.show(); }
        function close(): void { for (const q of quick.instances) q.close(); }
        function section(name: string): void {
            if (name === "notifications") { root.focused(centers)?.show(); return; }
            const q = root.focused(quick); if (q) { q.section = name; q.show(); }
        }
        function clearNotifications(): void { Services.Notifs.clearAll(); }
        function nightLight(): void { Services.NightLight.toggle(); }
        function state(): string {
            return JSON.stringify({ shown: quick.instances.filter(q => q.shown).map(q => q.screen.name),
                nightLight: Services.NightLight.active, nightLightTool: Services.NightLight.tool,
                powerProfile: PowerProfile.toString(PowerProfiles.profile) });
        }
    }
    IpcHandler {
        target: "center"
        function toggle(): void { root.focused(centers)?.toggle(); }
        function open(): void { root.focused(centers)?.show(); }
        function close(): void { for (const c of centers.instances) c.close(); }
        function clear(): void { Services.Notifs.clearAll(); }
        function dnd(on: bool): void { Services.Notifs.setDnd(on); }
        function state(): string {
            return JSON.stringify({ shown: centers.instances.filter(c => c.shown).map(c => c.screen.name),
                dnd: Services.Notifs.dnd, count: Services.Notifs.count, unread: Services.Notifs.unread,
                popups: Services.Notifs.popups.length,
                groups: Services.Notifs.groups.map(g => ({ app: g.app, count: g.entries.length })) });
        }
    }
    IpcHandler {
        target: "osd"
        function show(kind: string): void { root.focused(osds)?.show(kind); }
        function state(): string {
            return JSON.stringify(osds.instances.map(o => ({ screen: o.screen.name, primary: o.primary, shown: o.shown, kind: o.kind })));
        }
    }
    IpcHandler {
        target: "grid"
        function open(): void { root.gridWin()?.show(); }
        function toggle(): void { root.gridWin()?.toggle(); }
        function close(): void { root.gridWin()?.close(); }
        function activate(): void { root.gridWin()?.activate(); }
        function lock(): void { root.gridWin()?.toggleLock(); }
        function move(dr: int, dc: int): void { root.gridWin()?.move(dr, dc); }
        function action(id: string, text: string): void { root.gridWin()?.runAction({ id: id }, text); }
        function palette(): void { root.gridWin()?.togglePalette(); }
        function windows(ws: int): string { const g = root.gridWin(); if (!g) return "[]"; return JSON.stringify(g.windowsOn(ws).map(t => ({ address: String(t.address), ws: t.workspace ? t.workspace.id : null, title: t.title }))); }
        function toplevels(): string { return JSON.stringify(Hyprland.toplevels.values.map(t => ({ address: String(t.address), ws: t.workspace ? t.workspace.id : null, title: t.title }))); }
        function dispatch(cmd: string): void { root.gridWin()?.dispatch(cmd); }
        function state(): string { const g = root.gridWin(); return g ? JSON.stringify({ phase: g.phase, row: g.selRow, col: g.selCol }) : "none"; }
    }

    IpcHandler {
        target: "nav"
        function ping(): string { return "pong " + Services.Hyprnav.socketPath + " connected=" + Services.Hyprnav.connected; }
        function refresh(): void { Services.Hyprnav.refreshAll(); }
    }
    IpcHandler {
        target: "switcher"
        function open(): void { root.switcherWin()?.show(false); }
        function back(): void { root.switcherWin()?.show(true); }
        function step(): void { root.switcherWin()?.step(1); }
        function stepBack(): void { root.switcherWin()?.step(-1); }
        function activate(): void { root.switcherWin()?.activate(); }
        function cancel(): void { root.switcherWin()?.cancel(); }
    }
}
