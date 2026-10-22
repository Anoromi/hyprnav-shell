pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import ".."

// The grid's browser-tab column: Essentials as tiles, "New tab", each group's
// tabs, then the other tabs. Every entry wears a jump hint; the grid owns the
// keys and tells this column the typed prefix and the selection.
//
// It is one opaque sheet with its own key hints, so it reads the same on the
// glass beside the rolls and over the browser while previewing, where nothing
// behind it may show through.
Item {
    id: panel

    property var model: ({ essentials: [], newTab: null, sections: [], selectables: [] })
    property int selIndex: -1          // into model.selectables; -1 hides the ring
    property string prefix: ""
    property bool searching: false     // hints hide while letters go to the query
    property string query: ""
    property bool live: false          // the grid is open: hover may select
    property bool hoverArmed: false
    property string keyHints: ""
    signal picked(var item)
    signal hovered(int index)
    signal pointerMoved(var item, real x, real y)

    // Boxes (search field, rows, tiles) start `pad` in from the sheet's edge;
    // text inside them and the titles above them start `textX` further in.
    readonly property int pad: Theme.s8
    readonly property int textX: 6
    readonly property int tileGap: 6
    // Essentials are icons only, Arc style: one row that wraps into a grid.
    readonly property int tileSize: 36
    readonly property int rowH: 30
    readonly property color line: Qt.rgba(Theme.oPaper.r, Theme.oPaper.g, Theme.oPaper.b, 0.10)

    // Keep the selection in view; the column scrolls on its own.
    function ensureVisible(item) {
        if (!item) return;
        const top = item.mapToItem(column, 0, 0).y;
        const bottom = top + item.height;
        if (top < flick.contentY + Theme.s8) flick.contentY = Math.max(0, top - Theme.s8);
        else if (bottom > flick.contentY + flick.height - Theme.s8) flick.contentY = Math.min(flick.contentHeight - flick.height, bottom - flick.height + Theme.s8);
    }
    property var _entries: ({})
    onSelIndexChanged: Qt.callLater(() => { const sel = panel.model.selectables[panel.selIndex]; if (sel) panel.ensureVisible(panel._entries[sel.key]); })

    // A hint, with what has been typed of it in Pencil. Hints the prefix rules
    // out fade, so the remaining choices stand out.
    function ruledOut(hint) { return prefix !== "" && (hint || "").indexOf(prefix) !== 0; }
    component Hint: Rectangle {
        id: hintBox
        required property string hint
        property bool selected: false
        readonly property bool matches: !panel.ruledOut(hint)
        visible: hint !== "" && !panel.searching
        width: Math.max(22, label.implicitWidth + 10); height: 20
        radius: 3
        color: selected ? Theme.oPencil : Theme.oEmulsion
        Text {
            id: label
            anchors.centerIn: parent
            textFormat: Text.StyledText
            readonly property int typed: hintBox.matches ? panel.prefix.length : 0
            text: typed > 0
                ? "<font color=\"" + (hintBox.selected ? Theme.oSheet : Theme.oPencil) + "\">" + hintBox.hint.slice(0, typed) + "</font>" + hintBox.hint.slice(typed)
                : hintBox.hint
            color: hintBox.selected ? Theme.oSheet : Theme.oPaper
            font.family: Theme.mono; font.pixelSize: Theme.fs13; font.weight: Font.Medium
        }
    }

    // Site icon, or the site's initial when there is none to load.
    component Favicon: Item {
        id: fav
        required property string icon
        required property string fallback
        property int size: 16
        width: size; height: size
        // Only data the browser handed over: the shell never fetches a site.
        readonly property bool loadable: icon.indexOf("data:") === 0
        Image {
            id: img
            anchors.fill: parent
            source: fav.loadable ? fav.icon : ""
            sourceSize.width: fav.size * 2; sourceSize.height: fav.size * 2
            asynchronous: true
            smooth: true
            fillMode: Image.PreserveAspectFit
        }
        Rectangle {
            anchors.fill: parent
            visible: img.status !== Image.Ready
            radius: 3
            color: Theme.oEmulsion
            Text {
                anchors.centerIn: parent
                text: (fav.fallback || "?").slice(0, 1).toUpperCase()
                color: Theme.oPaper
                font.family: Theme.sans; font.pixelSize: Math.round(fav.size * 0.62); font.weight: Font.Medium
            }
        }
    }

    // The selection: a Pencil ring drawn on the entry's own edge, so rows
    // stacked 2 px apart never overlap their neighbours' rings.
    component Ring: Rectangle {
        property bool on: false
        property int out: 0
        anchors.fill: parent
        anchors.margins: -out
        visible: on
        radius: Theme.rSheet + out
        color: "transparent"
        border.color: Theme.oPencil
        border.width: 2
    }

    // One list entry: hint, icon, title, and on the right what is worth
    // knowing about it ("here", sound, which browser when several run).
    component EntryRow: Item {
        id: entry
        property string hint: ""
        property bool selected: false
        property bool here: false
        property bool audible: false
        property string badge: ""
        property bool muted: false       // "New tab": quieter than a tab
        property string title: ""
        property alias iconItem: iconSlot.data
        width: column.width; height: panel.rowH
        opacity: panel.ruledOut(hint) ? 0.3 : 1
        Behavior on opacity { NumberAnimation { duration: Theme.tSnap } }
        Rectangle {
            anchors.fill: parent
            radius: Theme.rSheet
            visible: entry.selected
            color: Qt.rgba(Theme.oPencil.r, Theme.oPencil.g, Theme.oPencil.b, 0.10)
        }
        Row {
            id: lead
            anchors.verticalCenter: parent.verticalCenter
            x: panel.textX - 2
            spacing: 6
            Hint { anchors.verticalCenter: parent.verticalCenter; hint: entry.hint; selected: entry.selected }
            Item { id: iconSlot; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16 }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            x: lead.x + lead.width + 6
            width: trail.x - x - 6
            elide: Text.ElideRight
            text: entry.title
            color: entry.muted && !entry.selected ? Theme.oFixer : Theme.oPaper
            font.family: Theme.sans; font.pixelSize: Theme.fs13
            font.weight: entry.selected || entry.here ? Font.Medium : Font.Normal
        }
        Row {
            id: trail
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right; anchors.rightMargin: panel.textX + 2
            spacing: Theme.s4
            Glyph {
                anchors.verticalCenter: parent.verticalCenter
                visible: entry.audible
                text: "󰕾"; size: 14; color: Theme.oFixer
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: entry.badge !== ""
                text: entry.badge
                color: Theme.oFixer
                font.family: Theme.sans; font.pixelSize: Theme.fs12
            }
            // The tab showing in the browser, marked as on the grid's frames.
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: entry.here
                text: "here"
                color: Theme.oPencil
                font.family: Theme.sans; font.pixelSize: Theme.fs12; font.weight: Font.Medium
            }
        }
        Ring { on: entry.selected }
    }

    // The "New tab" entry: "New tab", or the query to open. Shown in one
    // place at a time.
    component NewTabRow: EntryRow {
        id: newRow
        property bool shown: true
        readonly property var item: panel.model.newTab
        selected: shown && item !== null && item !== undefined && item.index === panel.selIndex
        visible: shown && item !== null && item !== undefined
        onVisibleChanged: if (visible) panel._entries["new"] = newRow
        Component.onCompleted: if (visible) panel._entries["new"] = newRow
        hint: item ? item.hint : ""
        title: item ? item.title : ""
        muted: true
        iconItem: Glyph { anchors.centerIn: parent; text: "󰐕"; size: 16; color: newRow.selected ? Theme.oPencil : Theme.oFixer }
        MouseArea {
            anchors.fill: parent
            enabled: panel.live
            hoverEnabled: true
            onPositionChanged: mouse => panel.pointerMoved(parent, mouse.x, mouse.y)
            onEntered: if (panel.hoverArmed && newRow.item) panel.hovered(newRow.item.index)
            onClicked: if (newRow.item) panel.picked(newRow.item)
        }
    }

    // The sheet, lifted off whatever is behind it by a soft shadow.
    Rectangle {
        id: sheet
        anchors.fill: parent
        radius: Theme.rSheet + 4
        color: Theme.oSheet
        border.width: 1
        border.color: panel.line
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "black"
            shadowOpacity: Theme.light ? 0.16 : 0.45
            shadowBlur: 0.7
            blurMax: 24
            shadowVerticalOffset: 4
        }
    }

    // The search field; it is always there, so "/" changes what it says and
    // not where everything sits.
    Item {
        id: header
        x: panel.pad; y: panel.pad
        width: parent.width - panel.pad * 2
        height: panel.rowH
        Rectangle {
            width: parent.width; height: panel.rowH
            radius: Theme.rSheet
            color: Theme.oDarkroom
            border.width: panel.searching ? 2 : 1
            border.color: panel.searching ? Theme.oPencil : panel.line
            Glyph {
                id: searchGlyph
                anchors.verticalCenter: parent.verticalCenter
                x: panel.textX
                text: "󰍉"; size: 14
                color: panel.searching ? Theme.oPencil : Theme.oFixer
            }
            Text {
                id: queryText
                anchors.verticalCenter: parent.verticalCenter
                x: searchGlyph.x + searchGlyph.width + Theme.s4 + 2
                width: Math.min(implicitWidth, slashKey.x - x - Theme.s8)
                elide: Text.ElideLeft
                text: panel.query !== "" ? panel.query : "Search"
                color: panel.query !== "" ? Theme.oPaper : Theme.oFixer
                font.family: Theme.sans; font.pixelSize: Theme.fs13
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: queryText.right; anchors.leftMargin: panel.query !== "" ? 2 : -queryText.width
                visible: panel.searching
                width: 2; height: 14
                color: Theme.oPencil
                SequentialAnimation on opacity {
                    running: panel.searching && !Theme.reducedMotion; loops: Animation.Infinite
                    NumberAnimation { to: 0; duration: 500 } NumberAnimation { to: 1; duration: 500 }
                }
            }
            // The key that starts a search, while not searching.
            Rectangle {
                id: slashKey
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right; anchors.rightMargin: panel.textX
                visible: !panel.searching
                width: 18; height: 18; radius: 3
                color: Theme.oEmulsion
                Text {
                    anchors.centerIn: parent
                    text: "/"
                    color: Theme.oPaper
                    font.family: Theme.mono; font.pixelSize: Theme.fs13; font.weight: Font.Medium
                }
            }
        }
    }

    Flickable {
        id: flick
        anchors.top: header.bottom; anchors.topMargin: Theme.s4
        anchors.bottom: footer.top
        width: parent.width
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        Behavior on contentY { enabled: !Theme.reducedMotion; NumberAnimation { duration: Theme.tSnap; easing.type: Easing.OutCubic } }

        Column {
            id: column
            x: panel.pad
            width: panel.width - panel.pad * 2
            spacing: Theme.s8
            // Room for the tiles' outer ring and corner hints.
            topPadding: Theme.s8
            bottomPadding: Theme.s8

            // Essentials: icons in a row that wraps; the selected one's name
            // shows under the row.
            Column {
                width: parent.width
                spacing: Theme.s8
                visible: panel.model.essentials.length > 0
                Flow {
                    width: parent.width
                    spacing: panel.tileGap
                    Repeater {
                        model: panel.model.essentials
                        delegate: Item {
                            id: tile
                            required property var modelData
                            readonly property bool selected: modelData.index === panel.selIndex
                            width: panel.tileSize; height: panel.tileSize
                            opacity: panel.ruledOut(modelData.hint) ? 0.3 : 1
                            Behavior on opacity { NumberAnimation { duration: Theme.tSnap } }
                            Component.onCompleted: panel._entries[modelData.key] = tile
                            Rectangle {
                                anchors.fill: parent
                                radius: Theme.rSheet
                                color: Theme.oDarkroom
                                border.width: 1
                                border.color: Qt.rgba(Theme.oPaper.r, Theme.oPaper.g, Theme.oPaper.b, tile.modelData.open ? 0.28 : 0.08)
                                Favicon {
                                    anchors.centerIn: parent
                                    size: 20
                                    opacity: tile.modelData.open ? 1 : 0.7
                                    icon: tile.modelData.icon || ""
                                    fallback: tile.modelData.title
                                }
                                // The essential whose tab is showing: a Pencil
                                // dot under the icon.
                                Rectangle {
                                    visible: tile.modelData.here === true
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom; anchors.bottomMargin: 4
                                    width: 6; height: 3; radius: 1.5
                                    color: Theme.oPencil
                                }
                            }
                            // The hint rides the corner so it never covers the icon.
                            Hint { x: -6; y: -6; hint: tile.modelData.hint; selected: tile.selected }
                            Ring { on: tile.selected; out: 3 }
                            MouseArea {
                                anchors.fill: parent
                                enabled: panel.live
                                hoverEnabled: true
                                onPositionChanged: mouse => panel.pointerMoved(parent, mouse.x, mouse.y)
                                onEntered: if (panel.hoverArmed) panel.hovered(tile.modelData.index)
                                onClicked: panel.picked(tile.modelData)
                            }
                        }
                    }
                }
                Text {
                    readonly property var sel: panel.model.selectables[panel.selIndex] ?? null
                    visible: sel !== null && sel.kind === "essential"
                    width: parent.width
                    leftPadding: panel.textX
                    elide: Text.ElideRight
                    text: sel ? sel.title + (sel.badge ? " · " + sel.badge : "") : ""
                    color: Theme.oPaper
                    font.family: Theme.sans; font.pixelSize: Theme.fs13; font.weight: Font.Medium
                }
            }

            // New tab; while searching it moves below the matches.
            NewTabRow { shown: !panel.searching }

            // Groups, then the rest
            Repeater {
                model: panel.model.sections
                delegate: Column {
                    id: section
                    required property var modelData
                    width: column.width
                    spacing: 2
                    Text {
                        leftPadding: panel.textX
                        bottomPadding: 2
                        width: column.width
                        elide: Text.ElideRight
                        text: section.modelData.title
                        color: Theme.oFixer
                        font.family: Theme.casual; font.pixelSize: Theme.fs13; font.weight: Font.Medium
                    }
                    Repeater {
                        model: section.modelData.items
                        delegate: EntryRow {
                            id: tabRow
                            required property var modelData
                            selected: modelData.index === panel.selIndex
                            hint: modelData.hint
                            here: modelData.here === true
                            audible: modelData.audible === true
                            badge: modelData.badge || ""
                            title: modelData.title
                            Component.onCompleted: panel._entries[modelData.key] = tabRow
                            iconItem: Favicon {
                                anchors.centerIn: parent
                                icon: tabRow.modelData.icon || ""
                                fallback: tabRow.modelData.host || tabRow.modelData.title
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: panel.live
                                hoverEnabled: true
                                onPositionChanged: mouse => panel.pointerMoved(parent, mouse.x, mouse.y)
                                onEntered: if (panel.hoverArmed) panel.hovered(tabRow.modelData.index)
                                onClicked: panel.picked(tabRow.modelData)
                            }
                        }
                    }
                }
            }

            NewTabRow { shown: panel.searching }
        }
    }

    // The list fades into the sheet at an edge it continues past.
    component EdgeFade: Rectangle {
        property bool atTop: false
        property bool on: false
        x: 1; width: panel.width - 2; height: Theme.s24
        opacity: on ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.tSnap } }
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(Theme.oSheet.r, Theme.oSheet.g, Theme.oSheet.b, atTop ? 1 : 0) }
            GradientStop { position: 1; color: Qt.rgba(Theme.oSheet.r, Theme.oSheet.g, Theme.oSheet.b, atTop ? 0 : 1) }
        }
    }
    EdgeFade { atTop: true; y: flick.y; on: flick.contentY > 1 }
    EdgeFade { y: flick.y + flick.height - height; on: flick.contentY < flick.contentHeight - flick.height - 1 }

    // Key hints for what the keys do right now, on the sheet itself, so
    // nothing is written over the browser.
    Item {
        id: footer
        anchors.bottom: parent.bottom
        width: parent.width
        height: visible ? hintText.implicitHeight + Theme.s8 * 2 : 0
        visible: panel.keyHints !== ""
        Rectangle { x: panel.pad; width: parent.width - panel.pad * 2; height: 1; color: panel.line }
        Text {
            id: hintText
            x: panel.pad + panel.textX; y: Theme.s8
            width: parent.width - x * 2
            elide: Text.ElideRight
            text: panel.keyHints
            color: Theme.oFixer
            font.family: Theme.sans; font.pixelSize: Theme.fs12
        }
    }
}
