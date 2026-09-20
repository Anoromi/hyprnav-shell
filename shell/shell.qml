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

ShellRoot {
    id: root
    readonly property string targetScreen: Quickshell.env("HNS_SCREEN") || ""
    readonly property var screens: Quickshell.screens.filter(s => root.targetScreen === "" || s.name === root.targetScreen)

    Variants {
        id: switchers
        model: root.screens
        Switcher {}
    }
    function switcherWin() { return switchers.instances[0] ?? null; }
    Variants {
        id: grids
        model: root.screens
        Grid {}
    }
    function gridWin() { return grids.instances[0] ?? null; }
    Variants {
        id: quick
        model: root.screens
        QuickSettings {}
    }
    Variants {
        model: root.screens
        Bar { quickSettings: quick.instances.find(q => q.screen === screen) ?? null }
    }
    Variants {
        model: root.screens
        Popups { suppressed: quick.instances[0]?.shown ?? false }
    }
    Variants {
        id: captions
        model: root.screens
        Caption {}
    }
    Variants {
        model: root.screens
        AgentBadges {}
    }
    IpcHandler {
        target: "caption"
        function display(text: string, ms: int): void { captions.instances[0]?.show(text, ms); }
        function hide(): void { captions.instances[0]?.hide(); }
    }
    IpcHandler {
        target: "qs"
        function toggle(): void { quick.instances[0]?.toggle(); }
        function open(): void { quick.instances[0]?.show(); }
        function close(): void { quick.instances[0]?.close(); }
        function section(name: string): void { const q = quick.instances[0]; if (q) { q.section = name; q.show(); } }
        function clearNotifications(): void { Services.Notifs.clearAll(); }
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
