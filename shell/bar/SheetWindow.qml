import QtQuick
import Quickshell
import Quickshell.Wayland
import "../services" as Services
import ".."

// A sheet beside the bar: the control centre, the notification centre and
// tray menus. The layer surface is created once and stays mapped; opening only
// changes the input region, keyboard interactivity and the sheet's opacity
// and offset. Creating the surface on every open cost a new QQuickWindow, a
// render thread and a GL context each time (see TESTING.md, "Control centre
// speed").
//
// Dismissal: on open the sheet claims keyboard focus (Exclusive for 100 ms,
// then OnDemand, see ClickCatcher.qml for why), so Esc closes it at once, and
// ClickCatcher.qml closes it on a press anywhere outside the sheets and the
// bar. The bar stays clickable, so the button that opened a sheet toggles it
// closed.
PanelWindow {
    id: win
    property bool shown: false
    property real sheetHeight: 100          // the sheet's own height
    property real sheetTop: -1              // < 0: sheet sits on the bottom edge
    property int sheetRadius: Theme.rSheet
    property bool fromTop: false            // scale origin for the rise
    default property alias content: sheet.data
    readonly property alias sheet: sheet
    readonly property bool settled: !shown && sheet.opacity === 0
    signal opened()
    signal dismissed()

    function show() { if (shown) return; shown = true; opened(); }
    function close() { if (!shown) return; shown = false; dismissed(); }
    function toggle() { if (shown) close(); else show(); }

    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: !shown ? WlrKeyboardFocus.None : (claiming ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand)
    property bool claiming: false
    onShownChanged: { claiming = shown; if (shown) claim.restart(); Services.Sheets.open += shown ? 1 : -1; }
    Timer { id: claim; interval: 100; onTriggered: win.claiming = false }
    Connections { target: Services.Sheets; function onCloseAll() { win.close(); } }
    // Closed: an empty input region, clicks fall through to whatever is below.
    mask: shown ? onSheet : nowhere
    Region { id: onSheet; item: sheet }
    Region { id: nowhere }

    Rectangle {
        id: sheet
        x: 0
        width: parent.width
        height: Math.min(win.sheetHeight, parent.height)
        y: win.sheetTop < 0 ? parent.height - height : Math.max(0, Math.min(win.sheetTop, parent.height - height))
        radius: win.sheetRadius
        color: Theme.sheet
        border.color: Theme.emulsion
        clip: true
        visible: opacity > 0
        opacity: 0
        scale: 0.97
        transformOrigin: win.fromTop ? Item.TopLeft : Item.BottomLeft
        transform: Translate { id: shift; x: -Theme.riseDistance }
        focus: win.shown
        Keys.onEscapePressed: win.close()

        states: State {
            name: "open"; when: win.shown
            PropertyChanges { sheet.opacity: 1; sheet.scale: 1; shift.x: 0 }
        }
        transitions: [
            Transition {
                to: "open"
                NumberAnimation { targets: [sheet, shift]; properties: "opacity,scale,x"; duration: Theme.tOpen; easing.type: Easing.OutCubic }
            },
            Transition {
                from: "open"
                NumberAnimation { targets: [sheet, shift]; properties: "opacity,scale,x"; duration: Theme.tClose; easing.type: Easing.InCubic }
            }
        ]
        Behavior on height { enabled: win.shown && !Theme.reducedMotion; NumberAnimation { duration: Theme.tRise; easing.type: Easing.OutCubic } }
    }
}
