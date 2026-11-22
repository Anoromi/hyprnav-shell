pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../services" as Services
import ".."

// Displays section inside QuickSettings: quick laptop/external presets, a
// proportional arrangement preview, and per-monitor cards with power toggle
// plus expandable scale, resolution, refresh rate, position and rotation.
Item {
    id: view
    property string selectedName: ""

    readonly property var scaleChoices: [1, 1.25, 1.5, 1.6, 1.75, 2]
    readonly property var rotationChoices: [
        { t: 0, label: "0°" },
        { t: 1, label: "90°" },
        { t: 2, label: "180°" },
        { t: 3, label: "270°" }
    ]

    function ensureSelection() {
        const mons = Services.Displays.monitors;
        if (mons.length === 0) { selectedName = ""; return; }
        if (selectedName !== "" && mons.some(m => m.name === selectedName)) return;
        // When only one display is connected, open its settings directly; with
        // multiple displays, keep cards compact until the user clicks one.
        if (mons.length === 1) selectedName = mons[0].name;
    }

    Connections {
        target: Services.Displays
        function onMonitorsChanged() { view.ensureSelection(); }
    }
    Component.onCompleted: ensureSelection()

    function scaleListFor(curScale) {
        const list = scaleChoices.slice();
        const rounded = Math.round(curScale * 100) / 100;
        if (!list.some(v => Math.abs(v - rounded) < 0.015)) {
            list.push(rounded);
            list.sort((a, b) => a - b);
        }
        return list;
    }

    function currentRatesFor(m) {
        if (!m || !m.resolutions) return [];
        const match = m.resolutions.find(r => r.w === m.width && r.h === m.height);
        return match ? match.rates : [];
    }

    function topResolutionsFor(m) {
        if (!m || !m.resolutions) return [];
        const maxShow = 6;
        const list = m.resolutions.slice(0, maxShow);
        if (!list.some(r => r.w === m.width && r.h === m.height)) {
            const cur = m.resolutions.find(r => r.w === m.width && r.h === m.height);
            if (cur) list.push(cur);
        }
        return list;
    }

    component Heading: Text {
        color: Theme.paper; font.family: Theme.casual; font.pixelSize: Theme.fs18; font.weight: Font.Medium
    }
    component Meta: Text {
        color: Theme.fixer; font.family: Theme.sans; font.pixelSize: Theme.fs12
    }
    component Pill: Pressable {
        id: pill
        property string text: ""
        property bool mono: false
        implicitWidth: pillLbl.implicitWidth + Theme.s12 + 4
        implicitHeight: 24
        outlined: true
        Text {
            id: pillLbl
            anchors.centerIn: parent
            text: pill.text
            color: pill.active ? Theme.paper : Theme.fixer
            font.family: pill.mono ? Theme.mono : Theme.sans
            font.pixelSize: Theme.fs12
            font.weight: pill.active ? Font.Medium : Font.Normal
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col
            width: flick.width
            spacing: Theme.s8

            // Header row
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.qsHeaderH
                spacing: Theme.s8
                Heading { text: "Displays"; Layout.fillWidth: true }
                Meta {
                    visible: Services.Displays.statusNote !== "" || Services.Displays.profileSaved
                    text: Services.Displays.statusNote !== "" ? Services.Displays.statusNote : "Saved"
                    color: Services.Displays.statusNote !== "" ? Theme.pencil : Theme.good
                }
                Pressable {
                    implicitWidth: 24; implicitHeight: 24
                    Glyph { anchors.centerIn: parent; text: "󰑐"; size: 14; color: parent.hovered ? Theme.paper : Theme.fixer }
                    onClicked: Services.Displays.refresh(false)
                }
            }

            // Quick laptop/external presets (one click for the common desk workflow)
            RowLayout {
                visible: Services.Displays.hasBuiltin && Services.Displays.hasExternal
                Layout.fillWidth: true
                spacing: Theme.s4
                Repeater {
                    model: [
                        { id: "external", glyph: "󰍹", label: "External" },
                        { id: "extend", glyph: "󰍺", label: "Extend" },
                        { id: "builtin", glyph: "󰌢", label: "Laptop" }
                    ]
                    Pressable {
                        id: presetBtn
                        required property var modelData
                        readonly property bool on: Services.Displays.activePreset === modelData.id
                        Layout.fillWidth: true
                        implicitHeight: 32
                        active: on
                        outlined: true
                        Row {
                            anchors.centerIn: parent; spacing: 6
                            CrossGlyph { anchors.verticalCenter: parent.verticalCenter; text: presetBtn.modelData.glyph; size: 15; color: presetBtn.on ? Theme.pencil : Theme.paper }
                            Text { text: presetBtn.modelData.label; color: presetBtn.on ? Theme.paper : Theme.fixer; font.family: Theme.sans; font.pixelSize: Theme.fs13; anchors.verticalCenter: parent.verticalCenter }
                        }
                        onClicked: Services.Displays.applyPreset(presetBtn.modelData.id)
                    }
                }
            }

            // Proportional layout preview when 2+ monitors are connected
            Rectangle {
                id: previewBox
                visible: Services.Displays.connectedCount >= 2
                Layout.fillWidth: true
                implicitHeight: 68
                radius: Theme.rControl
                color: Theme.darkroom
                border.color: Theme.emulsion

                readonly property var activeMons: Services.Displays.monitors.filter(m => m.enabled)
                readonly property var disabledMons: Services.Displays.monitors.filter(m => !m.enabled)
                readonly property var bounds: {
                    const list = activeMons;
                    if (list.length === 0) return { minX: 0, minY: 0, w: 1, h: 1 };
                    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
                    for (const m of list) {
                        minX = Math.min(minX, m.x);
                        minY = Math.min(minY, m.y);
                        maxX = Math.max(maxX, m.x + m.logicalWidth);
                        maxY = Math.max(maxY, m.y + m.logicalHeight);
                    }
                    return { minX: minX, minY: minY, w: Math.max(1, maxX - minX), h: Math.max(1, maxY - minY) };
                }
                readonly property real pad: 10
                readonly property real fitScale: Math.min((width - pad * 2) / bounds.w, (height - pad * 2) / bounds.h)
                readonly property real offX: (width - bounds.w * fitScale) / 2
                readonly property real offY: (height - bounds.h * fitScale) / 2

                Repeater {
                    model: previewBox.activeMons
                    Rectangle {
                        id: monBox
                        required property var modelData
                        readonly property bool sel: view.selectedName === modelData.name
                        x: Math.round(previewBox.offX + (modelData.x - previewBox.bounds.minX) * previewBox.fitScale) + 1
                        y: Math.round(previewBox.offY + (modelData.y - previewBox.bounds.minY) * previewBox.fitScale) + 1
                        width: Math.max(24, Math.round(modelData.logicalWidth * previewBox.fitScale) - 2)
                        height: Math.max(18, Math.round(modelData.logicalHeight * previewBox.fitScale) - 2)
                        radius: Theme.rFrame
                        color: sel ? Theme.emulsion : Theme.sheet
                        border.width: sel || modelData.focused ? 1.5 : 1
                        border.color: sel ? Theme.pencil : (modelData.focused ? Theme.pencilDim : Theme.fixer)
                        Text {
                            anchors.centerIn: parent
                            width: parent.width - 6
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: monBox.modelData.label
                            color: monBox.sel ? Theme.paper : Theme.fixer
                            font.family: Theme.sans
                            font.pixelSize: 10
                            font.weight: monBox.sel ? Font.Medium : Font.Normal
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: view.selectedName = (view.selectedName === monBox.modelData.name ? "" : monBox.modelData.name)
                        }
                    }
                }

                // Dimmed badge for any disabled monitor(s)
                Row {
                    visible: previewBox.disabledMons.length > 0
                    anchors { right: parent.right; bottom: parent.bottom; margins: 6 }
                    spacing: 4
                    Repeater {
                        model: previewBox.disabledMons
                        Rectangle {
                            id: offChip
                            required property var modelData
                            height: 18
                            width: offLbl.implicitWidth + 10
                            radius: 4
                            color: Theme.sheet
                            border.color: Theme.emulsion
                            opacity: 0.75
                            Text {
                                id: offLbl
                                anchors.centerIn: parent
                                text: offChip.modelData.label + " off"
                                color: Theme.fixer
                                font.family: Theme.sans
                                font.pixelSize: 10
                            }
                        }
                    }
                }
            }

            // Per-monitor cards
            Repeater {
                model: Services.Displays.monitors
                Rectangle {
                    id: card
                    required property var modelData
                    readonly property var mon: modelData
                    readonly property bool expanded: view.selectedName === mon.name && mon.enabled
                    readonly property bool canDisable: !mon.enabled || Services.Displays.activeCount > 1

                    Layout.fillWidth: true
                    implicitHeight: cardCol.implicitHeight + Theme.s8 * 2
                    radius: Theme.rControl
                    color: expanded ? Qt.rgba(0.227, 0.216, 0.200, 0.35) : "transparent"
                    border.width: 1
                    border.color: expanded ? Theme.pencilDim : Theme.emulsion

                    ColumnLayout {
                        id: cardCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.s8 }
                        spacing: Theme.s8

                        // Monitor summary row
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.s8

                            Pressable {
                                Layout.fillWidth: true
                                implicitHeight: 36
                                interactive: card.mon.enabled
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.s4; anchors.rightMargin: Theme.s4
                                    spacing: Theme.s8
                                    Glyph {
                                        text: card.mon.isBuiltin ? "󰌢" : "󰍹"
                                        size: 16
                                        color: card.expanded ? Theme.pencil : (card.mon.enabled ? Theme.paper : Theme.fixer)
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6
                                            Text {
                                                text: card.mon.label
                                                color: card.mon.enabled ? Theme.paper : Theme.fixer
                                                font.family: Theme.sans
                                                font.pixelSize: Theme.fs13
                                                font.weight: card.mon.enabled ? Font.Medium : Font.Normal
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Glyph {
                                                visible: card.mon.enabled
                                                text: card.expanded ? "󰅃" : "󰅀"
                                                size: 14
                                                color: Theme.fixer
                                            }
                                        }
                                        Text {
                                            text: card.mon.enabled
                                                ? (card.mon.name + " · " + card.mon.width + "×" + card.mon.height + " · " + card.mon.hzLabel + " · " + card.mon.scale + "×")
                                                : (card.mon.name + " · Off")
                                            color: Theme.fixer
                                            font.family: Theme.mono
                                            font.pixelSize: 11
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }
                                }
                                onClicked: {
                                    if (!card.mon.enabled) return;
                                    view.selectedName = card.expanded ? "" : card.mon.name;
                                }
                            }

                            Toggle {
                                on: card.mon.enabled
                                opacity: card.canDisable ? 1 : 0.4
                                onToggled: {
                                    if (!card.canDisable) return;
                                    Services.Displays.setEnabled(card.mon.name, !card.mon.enabled);
                                }
                            }
                        }

                        // Expanded monitor settings
                        ColumnLayout {
                            visible: card.expanded
                            Layout.fillWidth: true
                            Layout.leftMargin: Theme.s4
                            Layout.rightMargin: Theme.s4
                            spacing: Theme.s8

                            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.emulsion }

                            // Scale
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: Theme.s4
                                Meta { text: "Scale" }
                                Flow {
                                    Layout.fillWidth: true; spacing: Theme.s4
                                    Repeater {
                                        model: view.scaleListFor(card.mon.scale)
                                        Pill {
                                            required property real modelData
                                            mono: true
                                            text: modelData + "×"
                                            active: Math.abs(card.mon.scale - modelData) < 0.015
                                            onClicked: Services.Displays.setScale(card.mon.name, modelData)
                                        }
                                    }
                                }
                            }

                            // Resolution
                            ColumnLayout {
                                visible: card.mon.resolutions && card.mon.resolutions.length > 0
                                Layout.fillWidth: true; spacing: Theme.s4
                                Meta { text: "Resolution" }
                                Flow {
                                    Layout.fillWidth: true; spacing: Theme.s4
                                    Repeater {
                                        model: view.topResolutionsFor(card.mon)
                                        Pill {
                                            required property var modelData
                                            mono: true
                                            text: modelData.label
                                            active: card.mon.width === modelData.w && card.mon.height === modelData.h
                                            onClicked: Services.Displays.setMode(card.mon.name, modelData.rates[0].modeStr)
                                        }
                                    }
                                }
                            }

                            // Refresh rate (only shown when current resolution offers 2+ rates)
                            ColumnLayout {
                                id: rateSection
                                readonly property var rates: view.currentRatesFor(card.mon)
                                visible: rates.length > 1
                                Layout.fillWidth: true; spacing: Theme.s4
                                Meta { text: "Refresh rate" }
                                Flow {
                                    Layout.fillWidth: true; spacing: Theme.s4
                                    Repeater {
                                        model: rateSection.rates
                                        Pill {
                                            required property var modelData
                                            mono: true
                                            text: modelData.label
                                            active: Math.abs(card.mon.refreshRate - modelData.hz) < 0.5
                                            onClicked: Services.Displays.setMode(card.mon.name, modelData.modeStr)
                                        }
                                    }
                                }
                            }

                            // Relative position (when 2+ monitors are active)
                            ColumnLayout {
                                visible: Services.Displays.activeCount >= 2
                                Layout.fillWidth: true; spacing: Theme.s4
                                RowLayout {
                                    Layout.fillWidth: true
                                    Meta { text: "Position"; Layout.fillWidth: true }
                                    Text {
                                        text: card.mon.x + ", " + card.mon.y
                                        color: Theme.fixer; font.family: Theme.mono; font.pixelSize: 11
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true; spacing: Theme.s4
                                    Repeater {
                                        model: [
                                            { id: "left", label: "Left" },
                                            { id: "right", label: "Right" },
                                            { id: "above", label: "Above" },
                                            { id: "below", label: "Below" }
                                        ]
                                        Pill {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            text: modelData.label
                                            active: Services.Displays.relativePlacement(card.mon.name) === modelData.id
                                            onClicked: Services.Displays.setPlacement(card.mon.name, modelData.id)
                                        }
                                    }
                                }
                            }

                            // Rotation
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: Theme.s4
                                Meta { text: "Rotation" }
                                RowLayout {
                                    Layout.fillWidth: true; spacing: Theme.s4
                                    Repeater {
                                        model: view.rotationChoices
                                        Pill {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            mono: true
                                            text: modelData.label
                                            active: (card.mon.transform % 4) === modelData.t
                                            onClicked: Services.Displays.setTransform(card.mon.name, modelData.t)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Text {
                visible: Services.Displays.monitors.length === 0
                text: "No displays detected."
                color: Theme.fixer; font.family: Theme.sans; font.pixelSize: Theme.fs13
            }

            Text {
                visible: Services.Displays.error !== ""
                text: Services.Displays.error
                color: Theme.warn; font.family: Theme.sans; font.pixelSize: Theme.fs12
                wrapMode: Text.Wrap; Layout.fillWidth: true
            }

            Meta {
                visible: Services.Displays.connectedCount > 0
                Layout.topMargin: Theme.s4
                text: "Changes are remembered per display combination."
                wrapMode: Text.Wrap; Layout.fillWidth: true
            }
        }
    }

    ScrollEdges { anchors.fill: flick; flick: flick; step: Theme.rowH }
}
