pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Keyboard layout state and switcher for Hyprland.
// Reads the main keyboard's configured layouts and active index via
// `hyprctl -j devices` on startup and on `configreloaded`, tracks live layout
// changes via Hyprland's `activelayout` event with zero idle polling, and
// switches via `hyprctl switchxkblayout all <index|next|prev>`.
Singleton {
    id: root

    property string mainKeyboard: ""
    property var layouts: []            // [{ index, layout, variant, code, label }]
    property int activeIndex: 0
    property string activeKeymap: ""
    readonly property var current: (activeIndex >= 0 && activeIndex < layouts.length)
        ? layouts[activeIndex]
        : { index: 0, layout: "", variant: "", code: _codeFromKeymap(activeKeymap), label: activeKeymap || "Keyboard" }
    readonly property string code: current.code || "--"
    readonly property string label: activeKeymap || current.label || "Keyboard"
    readonly property bool multiple: layouts.length > 1

    property bool _initialized: false
    property var _knownNames: ({})      // index -> exact XKB active_keymap seen from Hyprland

    function init() {
        if (_initialized) return;
        _initialized = true;
        refresh();
    }

    function refresh() {
        if (!reader.running) reader.running = true;
    }

    function setLayout(index) {
        const idx = parseInt(index, 10);
        if (isNaN(idx) || idx < 0 || (layouts.length > 0 && idx >= layouts.length)) return false;
        activeIndex = idx;
        if (layouts[idx]) activeKeymap = _knownNames[idx] || layouts[idx].label;
        Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", String(idx)]);
        settleRefresh.restart();
        return true;
    }

    function next() {
        if (layouts.length > 1) return setLayout((activeIndex + 1) % layouts.length);
        Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", "next"]);
        settleRefresh.restart();
        return true;
    }

    function prev() {
        if (layouts.length > 1) return setLayout((activeIndex - 1 + layouts.length) % layouts.length);
        Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", "prev"]);
        settleRefresh.restart();
        return true;
    }

    function _codeFor(layout, variant) {
        const l = String(layout || "").trim().toLowerCase();
        const v = String(variant || "").trim().toLowerCase();
        if (v.startsWith("dvorak")) return "DV";
        if (v.startsWith("colemak")) return "CM";
        if (v.startsWith("workman")) return "WM";
        if (l.length >= 2) return l.slice(0, 2).toUpperCase();
        return l ? l.toUpperCase() : "--";
    }

    function _codeFromKeymap(keymap) {
        const s = String(keymap || "").toLowerCase();
        if (s.indexOf("dvorak") >= 0) return "DV";
        if (s.indexOf("colemak") >= 0) return "CM";
        if (s.indexOf("ukrainian") >= 0) return "UA";
        if (s.indexOf("russian") >= 0) return "RU";
        if (s.indexOf("english") >= 0) return "US";
        return keymap ? String(keymap).slice(0, 2).toUpperCase() : "--";
    }

    function _labelFor(layout, variant, index) {
        if (_knownNames[index]) return _knownNames[index];
        const l = String(layout || "").trim().toLowerCase();
        const v = String(variant || "").trim();
        const vl = v.toLowerCase();
        const baseNames = {
            us: "English (US)", gb: "English (UK)", ua: "Ukrainian", ru: "Russian",
            de: "German", fr: "French", es: "Spanish", it: "Italian", pt: "Portuguese",
            pl: "Polish", si: "Slovenian", cz: "Czech", sk: "Slovak", nl: "Dutch",
            se: "Swedish", no: "Norwegian", dk: "Danish", fi: "Finnish", jp: "Japanese",
            kr: "Korean", il: "Hebrew", gr: "Greek", tr: "Turkish"
        };
        if (l === "us" && vl === "dvorak") return "English (Dvorak)";
        if (l === "us" && vl === "colemak") return "English (Colemak)";
        if (l === "us" && vl === "intl") return "English (US, intl.)";
        const base = baseNames[l] || (l ? l.toUpperCase() : ("Layout " + (index + 1)));
        if (v && base.indexOf("(") < 0) return base + " (" + v + ")";
        if (v && l === "us") return "English (" + v + ")";
        return base;
    }

    function _pickMainKeyboard(kbs) {
        if (!Array.isArray(kbs) || kbs.length === 0) return null;
        const main = kbs.find(k => k && k.main === true);
        if (main) return main;
        const multi = kbs.find(k => k && String(k.layout || "").indexOf(",") >= 0);
        if (multi) return multi;
        return kbs[0];
    }

    function _parseDevices(text, exitCode) {
        if (exitCode !== 0 || !text || !text.trim()) return;
        let parsed;
        try {
            parsed = JSON.parse(text);
        } catch (e) {
            console.warn("Keyboard: failed to parse hyprctl devices:", e);
            return;
        }
        const kb = _pickMainKeyboard(parsed.keyboards);
        if (!kb) return;

        mainKeyboard = String(kb.name || "");
        const rawLayouts = String(kb.layout || "").split(",");
        const rawVariants = String(kb.variant || "").split(",");
        const idx = Math.max(0, parseInt(kb.active_layout_index, 10) || 0);
        const keymap = String(kb.active_keymap || "");

        if (keymap !== "") {
            const names = Object.assign({}, _knownNames);
            names[idx] = keymap;
            _knownNames = names;
        }

        const list = [];
        for (let i = 0; i < rawLayouts.length; i++) {
            const l = (rawLayouts[i] || "").trim();
            const v = (rawVariants[i] || "").trim();
            if (l === "" && rawLayouts.length === 1) continue;
            list.push({
                index: i,
                layout: l,
                variant: v,
                code: _codeFor(l, v),
                label: _labelFor(l, v, i)
            });
        }
        if (list.length === 0 && keymap !== "") {
            list.push({ index: 0, layout: "", variant: "", code: _codeFromKeymap(keymap), label: keymap });
        }

        layouts = list;
        activeIndex = idx < list.length ? idx : 0;
        activeKeymap = keymap || (list[activeIndex] ? list[activeIndex].label : "");
    }

    function _handleActiveLayoutEvent(data) {
        const s = String(data || "");
        const comma = s.indexOf(",");
        if (comma < 0) return;
        const kbName = s.slice(0, comma);
        const keymap = s.slice(comma + 1);
        // Ignore virtual helper keyboards (e.g. Wispr Flow's QWERTY helper).
        if (mainKeyboard !== "" && kbName !== mainKeyboard) return;
        if (keymap !== "") {
            activeKeymap = keymap;
            // Optimistically match an already-known index for instant badge update.
            const match = layouts.find(l => l.label === keymap || _knownNames[l.index] === keymap);
            if (match) activeIndex = match.index;
        }
        // Confirm exact active_layout_index from Hyprland (handles duplicate names / first visit).
        eventRefresh.restart();
    }

    function stateJson() {
        return JSON.stringify({
            mainKeyboard: mainKeyboard,
            activeIndex: activeIndex,
            activeKeymap: activeKeymap,
            code: code,
            label: label,
            layouts: layouts
        });
    }

    Process {
        id: reader
        command: ["hyprctl", "-j", "devices"]
        stdout: StdioCollector { id: readerOut }
        onExited: code => root._parseDevices(readerOut.text, code)
    }

    Timer { id: eventRefresh; interval: 40; onTriggered: root.refresh() }
    Timer { id: settleRefresh; interval: 80; onTriggered: root.refresh() }

    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            if (!ev) return;
            if (ev.name === "activelayout") root._handleActiveLayoutEvent(ev.data);
            else if (ev.name === "configreloaded") eventRefresh.restart();
        }
    }
}
