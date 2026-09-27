pragma Singleton
import QtQuick
import Quickshell

Singleton {
    id: theme

    // Palette: a photographer's contact sheet.
    readonly property color darkroom: "#1A1917"
    readonly property color sheet: "#262421"
    readonly property color emulsion: "#3A3733"
    readonly property color paper: "#EDE6DA"
    readonly property color pencil: "#F2C14E"
    readonly property color fixer: "#9A938A"
    readonly property color good: "#8FBF7F"
    readonly property color warn: "#E06C4B"
    readonly property color scrim: Qt.rgba(0.102, 0.098, 0.090, 0.9)

    // Icon lookup that never asks for an empty name.
    function appIcon(cls) {
        if (!cls) return Quickshell.iconPath("application-x-executable");
        const entry = DesktopEntries.heuristicLookup(cls);
        if (entry && entry.icon) return Quickshell.iconPath(entry.icon, "application-x-executable");
        return Quickshell.iconPath(cls, "application-x-executable");
    }

    FontLoader { id: sansRegular; source: Qt.resolvedUrl("fonts/RecursiveSansLnrSt-Regular.ttf") }
    FontLoader { id: sansMed; source: Qt.resolvedUrl("fonts/RecursiveSansLnrSt-Med.ttf") }
    FontLoader { id: sansSemi; source: Qt.resolvedUrl("fonts/RecursiveSansLnrSt-SemiBold.ttf") }
    FontLoader { id: sansBold; source: Qt.resolvedUrl("fonts/RecursiveSansLnrSt-Bold.ttf") }
    FontLoader { id: cslMed; source: Qt.resolvedUrl("fonts/RecursiveSansCslSt-Med.ttf") }
    FontLoader { id: cslBold; source: Qt.resolvedUrl("fonts/RecursiveSansCslSt-Bold.ttf") }
    FontLoader { id: monoRegular; source: Qt.resolvedUrl("fonts/RecursiveMonoLnrSt-Regular.ttf") }
    FontLoader { id: monoMed; source: Qt.resolvedUrl("fonts/RecursiveMonoLnrSt-Med.ttf") }
    FontLoader { id: monoBold; source: Qt.resolvedUrl("fonts/RecursiveMonoLnrSt-Bold.ttf") }

    readonly property string sans: sansRegular.status === FontLoader.Ready ? sansRegular.name : "sans-serif"
    readonly property string casual: cslMed.status === FontLoader.Ready ? cslMed.name : sans
    readonly property string mono: monoMed.status === FontLoader.Ready ? monoMed.name : "monospace"

    // Type scale
    readonly property int fs12: 12
    readonly property int fs13: 13
    readonly property int fs15: 15
    readonly property int fs18: 18
    readonly property int fs22: 22
    readonly property int fs40: 40

    // Space and shape
    readonly property int s4: 4
    readonly property int s8: 8
    readonly property int s12: 12
    readonly property int s16: 16
    readonly property int s24: 24
    readonly property int s32: 32
    readonly property int rFrame: 3      // thumbnails: nearly square, like a print
    readonly property int rSheet: 8      // panels, tiles, rows, buttons: one radius
    readonly property int rControl: 8
    readonly property int ringWidth: 3

    // Lists in sheets (Wi-Fi, Bluetooth, outputs, notifications) live in boxes
    // of a fixed height, so a sheet is the same size from its first frame
    // however many rows a scan brings in. Rows scroll inside the box.
    readonly property int rowH: 40               // Wi-Fi and Bluetooth rows
    readonly property int rowCompactH: 34        // output (sink) rows
    readonly property int listGap: 4
    function listBox(rows, rowHeight) { return rows * rowHeight + (rows - 1) * listGap; }
    readonly property int wifiListH: listBox(7, rowH)          // 304
    readonly property int sinkListH: listBox(3, rowCompactH)   // 110
    readonly property int centerListH: 560                     // about eight compact cards
    // The control centre's view area (Wi-Fi, Bluetooth, sound and brightness)
    // is one fixed height, the tallest view's: the Wi-Fi header and its list.
    // Switching views never resizes the sheet; a view with more content
    // scrolls inside the area.
    readonly property int qsHeaderH: 28
    readonly property int qsViewH: qsHeaderH + s4 + wifiListH  // 336
    readonly property int listFadeH: 32

    // Motion
    readonly property bool reducedMotion: Quickshell.env("HNS_REDUCED_MOTION") === "1"
    readonly property int tFast: reducedMotion ? 0 : 90
    readonly property int tScrim: reducedMotion ? 0 : 120
    readonly property int tRise: reducedMotion ? 0 : 160
    // Bar selector: the locked roll fading and growing in the middle.
    readonly property int tLock: reducedMotion ? 0 : 160
    readonly property int tStagger: reducedMotion ? 0 : 12
    // Switcher and grid: they sit on the path from a key press to the next
    // window, so they appear and leave in one short fade and nothing travels.
    readonly property int tSnap: reducedMotion ? 0 : 30
    // Bar and sheets: hover and press states, sheets rising from the bar edge
    // (open slower than close, so a dismissal never feels sticky).
    readonly property int tHover: reducedMotion ? 0 : 120
    readonly property int tOpen: reducedMotion ? 0 : 180
    readonly property int tClose: reducedMotion ? 0 : 110
    readonly property int tStaggerList: reducedMotion ? 0 : 22
    readonly property int riseDistance: reducedMotion ? 0 : 12
    readonly property color hover: Qt.rgba(0.227, 0.216, 0.200, 0.7)   // emulsion, 70 %
    readonly property real springStiffness: 320
    readonly property real springDamping: 26
}
