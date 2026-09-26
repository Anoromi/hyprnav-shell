import QtQuick
import Quickshell
import Quickshell.Wayland
import "services" as Services

// Click-away for the sheets beside the bar. A transparent surface on the Top
// layer covering the screen right of the bar. It stays mapped; while no sheet
// is open its input region is empty and every click falls through. While one
// is open the region covers it, so a press anywhere off the sheets and off
// the bar closes them all (that press is not passed on to the window below).
// The bar stays outside the region, so its buttons toggle their own sheet.
//
// What was tried on Hyprland 0.56 (lab, virtual pointer and keyboard):
// - HyprlandFocusGrab (hyprland_focus_grab_v1) on the sheet and the bar
//   dismisses on an outside press, but the compositor clears the grab as
//   soon as the sheet takes exclusive keyboard focus, and without that focus
//   Esc only reaches the sheet after it has been clicked.
// - Exclusive keyboard focus held while open: Esc works, but Hyprland then
//   sends no presses to any other surface, this catcher included.
// - Kept: this catcher, and the sheet claims keyboard focus as Exclusive for
//   its first 100 ms, then drops to OnDemand; the focus stays on the sheet
//   (Esc works) and pointer presses reach the catcher again.
PanelWindow {
    id: win
    required property var modelData
    screen: modelData
    readonly property bool active: Services.Sheets.open > 0
    anchors { top: true; bottom: true; left: true; right: true }
    margins { left: 44 }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "hyprnav-shell-click-catcher"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: win.active ? everywhere : nowhere
    Region { id: everywhere; item: catcher }
    Region { id: nowhere }
    MouseArea {
        id: catcher
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: Services.Sheets.closeAll()
        onWheel: w => w.accepted = true
    }
}
