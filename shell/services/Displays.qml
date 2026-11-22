pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Display configuration for Hyprland (Lua config): lists connected outputs via
// `hyprctl -j monitors all`, toggles and configures them via `hyprctl eval`,
// persists layouts per connected-monitor combination in displays.json, and
// writes a guarded hyprnav-outputs.lua for Hyprland startup/reload.
//
// Zero polling at idle: refreshes only on startup, Hyprland monitor hotplug
// events, and when Quick Settings opens the Displays view.
Singleton {
    id: root

    property var monitors: []
    readonly property int connectedCount: monitors.length
    readonly property int activeCount: {
        let n = 0;
        for (const m of monitors) if (m.enabled) n++;
        return n;
    }
    readonly property bool hasBuiltin: monitors.some(m => m.isBuiltin)
    readonly property bool hasExternal: monitors.some(m => !m.isBuiltin)
    readonly property string comboKey: {
        if (monitors.length === 0) return "";
        return monitors.map(m => m.id).slice().sort().join(" | ");
    }
    readonly property string activePreset: {
        if (!hasBuiltin || !hasExternal) return "";
        const builtins = monitors.filter(m => m.isBuiltin);
        const externals = monitors.filter(m => !m.isBuiltin);
        const bOn = builtins.some(m => m.enabled);
        const eOn = externals.some(m => m.enabled);
        const allEOn = externals.every(m => m.enabled);
        if (!bOn && allEOn) return "external";
        if (bOn && !eOn) return "builtin";
        if (bOn && eOn) return "extend";
        return "";
    }

    property var store: ({ version: 1, profiles: {} })
    property bool profileSaved: false
    property string statusNote: ""
    property string error: ""
    property bool busy: false

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string storePath: configHome + "/hyprnav-shell/displays.json"
    readonly property string outputsLuaPath: configHome + "/hypr/hyprnav-outputs.lua"

    property bool _initialized: false
    property bool _storeLoaded: false
    property string _lastComboKey: ""
    property var _lastKnown: ({})
    property bool _pendingAutoApply: false
    property bool _refreshQueued: false
    property bool _refreshQueuedAuto: false
    property int _recoveryAttempt: 0

    function init() {
        if (_initialized) return;
        _initialized = true;
        if (!_storeLoaded) {
            // FileView with blockLoading loads synchronously once its path is
            // set; fall back cleanly if the file does not exist yet.
            try {
                const txt = storeFile.text();
                _parseStore(txt);
            } catch (_) {
                _parseStore("");
            }
        }
        refresh(true);
    }

    FileView {
        id: storeFile
        path: root.storePath
        blockLoading: true
        printErrors: false
        onLoaded: root._parseStore(text())
        onLoadFailed: root._parseStore("")
    }

    function _parseStore(text) {
        root._storeLoaded = true;
        if (!text || !text.trim()) {
            root.store = { version: 1, profiles: {} };
            return;
        }
        try {
            const parsed = JSON.parse(text);
            if (parsed && typeof parsed === "object" && parsed.profiles && typeof parsed.profiles === "object") {
                root.store = { version: parsed.version || 1, profiles: parsed.profiles };
                // Seed _lastKnown from any previously saved monitor settings.
                const known = Object.assign({}, root._lastKnown);
                for (const k in parsed.profiles) {
                    const prof = parsed.profiles[k];
                    if (!prof || !prof.monitors) continue;
                    for (const mid in prof.monitors) {
                        if (!known[mid]) known[mid] = Object.assign({}, prof.monitors[mid]);
                    }
                }
                root._lastKnown = known;
                return;
            }
        } catch (e) {
            console.warn("Displays: failed to parse displays.json:", e);
        }
        root.store = { version: 1, profiles: {} };
    }

    function _isBuiltinName(name) {
        return /^(eDP|LVDS|DSI)-/i.test(name || "");
    }

    function _formatHz(hz) {
        const rounded = Math.round(hz);
        if (Math.abs(hz - rounded) < 0.08) return String(rounded);
        return (Math.round(hz * 100) / 100).toFixed(2).replace(/0$/, "");
    }

    function _modeStr(w, h, hz) {
        const hzStr = (Math.round(hz * 100) / 100).toFixed(2);
        return w + "x" + h + "@" + hzStr;
    }

    function _parseModes(rawList, curW, curH, curHz) {
        const byKey = {};
        const resMap = {};
        const add = (w, h, hz) => {
            if (!w || !h || !hz) return;
            const hz10 = Math.round(hz * 10);
            const key = w + "x" + h + "@" + hz10;
            if (byKey[key]) return;
            byKey[key] = true;
            const resKey = w + "x" + h;
            if (!resMap[resKey]) {
                resMap[resKey] = { w: w, h: h, label: w + "×" + h, rates: [] };
            }
            resMap[resKey].rates.push({
                hz: hz,
                label: _formatHz(hz) + " Hz",
                modeStr: _modeStr(w, h, hz)
            });
        };

        if (Array.isArray(rawList)) {
            for (const s of rawList) {
                const m = /^(\d+)x(\d+)@([0-9.]+)Hz$/i.exec(String(s).trim());
                if (m) add(parseInt(m[1], 10), parseInt(m[2], 10), parseFloat(m[3]));
            }
        }
        if (curW > 0 && curH > 0 && curHz > 0) add(curW, curH, curHz);

        const resolutions = Object.keys(resMap).map(k => {
            const entry = resMap[k];
            entry.rates.sort((a, b) => b.hz - a.hz);
            entry.maxHz = entry.rates[0].hz;
            return entry;
        });
        resolutions.sort((a, b) => (b.w * b.h) - (a.w * a.h) || (b.w - a.w));
        return resolutions;
    }

    function _logicalSize(w, h, scale, transform) {
        const s = (scale && scale > 0) ? scale : 1;
        const rot = ((transform || 0) % 2) === 1;
        const lw = rot ? h : w;
        const lh = rot ? w : h;
        return {
            w: Math.max(1, Math.round(lw / s)),
            h: Math.max(1, Math.round(lh / s))
        };
    }

    function _parseModeDims(modeStr, fallbackW, fallbackH, fallbackHz) {
        const m = /^(\d+)x(\d+)(?:@([0-9.]+))?$/.exec(String(modeStr || "").trim());
        if (m) {
            return {
                w: parseInt(m[1], 10),
                h: parseInt(m[2], 10),
                hz: m[3] ? parseFloat(m[3]) : (fallbackHz || 60)
            };
        }
        return { w: fallbackW || 1920, h: fallbackH || 1080, hz: fallbackHz || 60 };
    }

    function _normalizeMonitors(rawList) {
        if (!Array.isArray(rawList)) return [];
        // Hyprland spawns a synthetic "FALLBACK" output whenever every real
        // monitor is disabled or unplugged; ignore it so zero-active recovery
        // and combo keys see only real displays.
        const real = rawList.filter(r => r && String(r.name || "") !== "FALLBACK");
        // Count non-empty descriptions so duplicate descriptions fall back to connector name.
        const descCounts = {};
        for (const r of real) {
            const d = String(r.description || "").trim();
            if (d) descCounts[d] = (descCounts[d] || 0) + 1;
        }
        const out = real.map(r => {
            const name = String(r.name || "");
            const desc = String(r.description || "").trim();
            const make = String(r.make || "").trim();
            const model = String(r.model || "").trim();
            const serial = String(r.serial || "").trim();
            const id = (desc && descCounts[desc] === 1) ? desc : name;
            const isBuiltin = _isBuiltinName(name);
            let label = name;
            if (isBuiltin) label = "Laptop";
            else if (model && model !== name) label = model;
            else if (make && model) label = make + " " + model;
            else if (desc) label = desc;

            const enabled = !r.disabled;
            const w = r.width || 0;
            const h = r.height || 0;
            const hz = r.refreshRate || 60;
            const scale = (r.scale && r.scale > 0) ? Math.round(r.scale * 100) / 100 : 1;
            const transform = r.transform || 0;
            const x = r.x || 0;
            const y = r.y || 0;
            const resolutions = _parseModes(r.availableModes, w, h, hz);
            const logical = _logicalSize(w, h, scale, transform);
            const mode = (w > 0 && h > 0) ? _modeStr(w, h, hz) : "preferred";
            return {
                name: name,
                id: id,
                description: desc,
                make: make,
                model: model,
                serial: serial,
                isBuiltin: isBuiltin,
                label: label,
                enabled: enabled,
                focused: !!r.focused,
                width: w,
                height: h,
                refreshRate: hz,
                hzLabel: _formatHz(hz) + " Hz",
                mode: mode,
                scale: scale,
                transform: transform,
                x: x,
                y: y,
                logicalWidth: logical.w,
                logicalHeight: logical.h,
                resolutions: resolutions
            };
        });
        // Stable ordering: built-in first, then external sorted by connector name.
        out.sort((a, b) => (b.isBuiltin - a.isBuiltin) || a.name.localeCompare(b.name));
        return out;
    }

    function _savedMonitorConfig(id, combo) {
        const prof = store.profiles && combo ? store.profiles[combo] : null;
        if (prof && prof.monitors && prof.monitors[id]) return prof.monitors[id];
        if (_lastKnown[id]) return _lastKnown[id];
        return null;
    }

    function _planFromCurrent() {
        const combo = comboKey;
        return monitors.map(m => {
            const saved = !m.enabled ? _savedMonitorConfig(m.id, combo) : null;
            const mode = m.enabled ? m.mode : ((saved && saved.mode) || (m.resolutions.length > 0 ? m.resolutions[0].rates[0].modeStr : "preferred"));
            const scale = m.enabled ? m.scale : ((saved && saved.scale) || 1.6);
            const transform = m.enabled ? m.transform : ((saved && saved.transform !== undefined) ? saved.transform : 0);
            const x = m.enabled ? m.x : ((saved && saved.x !== undefined) ? saved.x : 0);
            const y = m.enabled ? m.y : ((saved && saved.y !== undefined) ? saved.y : 0);
            const dims = _parseModeDims(mode, m.width, m.height, m.refreshRate);
            const logical = _logicalSize(dims.w, dims.h, scale, transform);
            return {
                name: m.name,
                id: m.id,
                isBuiltin: m.isBuiltin,
                enabled: m.enabled,
                mode: mode,
                scale: scale,
                transform: transform,
                x: x,
                y: y,
                logicalWidth: logical.w,
                logicalHeight: logical.h
            };
        });
    }

    function _recomputeLogical(entry, mon) {
        const dims = _parseModeDims(entry.mode, mon ? mon.width : 1920, mon ? mon.height : 1080, mon ? mon.refreshRate : 60);
        const l = _logicalSize(dims.w, dims.h, entry.scale, entry.transform);
        entry.logicalWidth = l.w;
        entry.logicalHeight = l.h;
    }

    function _normalizePositions(plan) {
        const active = plan.filter(e => e.enabled);
        if (active.length === 0) return;
        if (active.length === 1) {
            active[0].x = 0;
            active[0].y = 0;
            return;
        }
        let minX = Infinity, minY = Infinity;
        for (const e of active) {
            if (e.x < minX) minX = e.x;
            if (e.y < minY) minY = e.y;
        }
        for (const e of active) {
            e.x = Math.round(e.x - minX);
            e.y = Math.round(e.y - minY);
        }
    }

    function _snapAdjacentIfSideBySide(plan, changedName) {
        const active = plan.filter(e => e.enabled);
        if (active.length < 2) {
            _normalizePositions(plan);
            return;
        }
        if (active.length === 2) {
            const a = active[0], b = active[1];
            const dx = Math.abs(a.x - b.x);
            const dy = Math.abs(a.y - b.y);
            if (dx >= dy) {
                // Horizontal arrangement: preserve left-to-right order and abut cleanly.
                const left = a.x <= b.x ? a : b;
                const right = left === a ? b : a;
                left.x = 0; left.y = 0;
                right.x = left.logicalWidth; right.y = 0;
            } else {
                // Vertical arrangement: preserve top-to-bottom order and abut cleanly.
                const top = a.y <= b.y ? a : b;
                const bottom = top === a ? b : a;
                top.x = 0; top.y = 0;
                bottom.x = 0; bottom.y = top.logicalHeight;
            }
            return;
        }
        _normalizePositions(plan);
    }

    function _overlapsAny(entry, others) {
        for (const o of others) {
            if (entry.x < o.x + o.logicalWidth && entry.x + entry.logicalWidth > o.x &&
                entry.y < o.y + o.logicalHeight && entry.y + entry.logicalHeight > o.y) {
                return true;
            }
        }
        return false;
    }

    function _luaQuote(s) {
        return "\"" + String(s).replace(/\\/g, "\\\\").replace(/"/g, "\\\"") + "\"";
    }

    function _monitorLuaLine(e) {
        if (!e.enabled) {
            return "hl.monitor({ output = " + _luaQuote(e.name) + ", disabled = true })";
        }
        let parts = [
            "output = " + _luaQuote(e.name),
            "disabled = false",
            "mode = " + _luaQuote(e.mode || "preferred"),
            "position = " + _luaQuote(Math.round(e.x) + "x" + Math.round(e.y)),
            "scale = " + (Math.round(e.scale * 100) / 100)
        ];
        if (e.transform && e.transform !== 0) {
            parts.push("transform = " + e.transform);
        }
        return "hl.monitor({ " + parts.join(", ") + " })";
    }

    function _buildEvalLua(plan) {
        // Always enable active displays BEFORE disabling any display so Hyprland
        // never transitions through zero active outputs.
        const lines = [];
        for (const e of plan) if (e.enabled) lines.push(_monitorLuaLine(e));
        for (const e of plan) if (!e.enabled) lines.push(_monitorLuaLine(e));
        return lines.join("\n");
    }

    function _buildOutputsLua(plan) {
        const enabled = plan.filter(e => e.enabled);
        const disabled = plan.filter(e => !e.enabled);
        const lines = [
            "-- Managed by hyprnav-shell (Displays). Do not edit manually.",
            "local function is_connected(name)",
            "    for card = 0, 9 do",
            "        local f = io.open(\"/sys/class/drm/card\" .. card .. \"-\" .. name .. \"/status\", \"r\")",
            "        if f then",
            "            local s = f:read(\"*l\")",
            "            f:close()",
            "            if s == \"connected\" then return true end",
            "        end",
            "    end",
            "    return false",
            "end",
            "",
            "-- Safe fallback for any newly connected monitor.",
            "hl.monitor({ output = \"\", mode = \"preferred\", position = \"auto\", scale = 1.6 })",
            ""
        ];
        for (const e of enabled) {
            lines.push(_monitorLuaLine(e));
        }
        if (disabled.length > 0 && enabled.length > 0) {
            const cond = enabled.map(e => "is_connected(" + _luaQuote(e.name) + ")").join(" or ");
            lines.push("");
            lines.push("-- Only disable when a companion display from this layout is physically connected.");
            lines.push("if " + cond + " then");
            for (const d of disabled) {
                lines.push("    " + _monitorLuaLine(d));
            }
            lines.push("else");
            for (const d of disabled) {
                const fallback = Object.assign({}, d, { enabled: true, x: 0, y: 0 });
                lines.push("    " + _monitorLuaLine(fallback));
            }
            lines.push("end");
        }
        return lines.join("\n") + "\n";
    }

    function _persistFiles(plan, saveToProfiles) {
        let jsonStr = "";
        if (saveToProfiles && comboKey !== "") {
            const profiles = Object.assign({}, store.profiles || {});
            const monMap = {};
            for (const e of plan) {
                monMap[e.id] = {
                    enabled: !!e.enabled,
                    mode: e.mode || "preferred",
                    scale: Math.round((e.scale || 1) * 100) / 100,
                    x: Math.round(e.x || 0),
                    y: Math.round(e.y || 0),
                    transform: e.transform || 0
                };
            }
            profiles[comboKey] = { monitors: monMap };
            store = { version: 1, profiles: profiles };
            profileSaved = true;
            jsonStr = JSON.stringify(store, null, 2) + "\n";
        }
        const luaStr = _buildOutputsLua(plan);
        const writeLua = Quickshell.env("HNS_NO_OUTPUTS_LUA") !== "1";

        if (!jsonStr && !writeLua) return;

        // Atomic write via temp files in target dirs.
        const script =
            'set -e\n' +
            'if [ -n "$JSON_DATA" ]; then\n' +
            '  mkdir -p "$(dirname "$STORE_PATH")"\n' +
            '  tmp="$(mktemp "$STORE_PATH.XXXXXX")"\n' +
            '  printf "%s" "$JSON_DATA" > "$tmp"\n' +
            '  mv "$tmp" "$STORE_PATH"\n' +
            'fi\n' +
            'if [ "$WRITE_LUA" = "1" ] && [ -d "$(dirname "$LUA_PATH")" ]; then\n' +
            '  tmp="$(mktemp "$LUA_PATH.XXXXXX")"\n' +
            '  printf "%s" "$LUA_DATA" > "$tmp"\n' +
            '  mv "$tmp" "$LUA_PATH"\n' +
            'fi\n';

        Quickshell.execDetached({
            command: ["sh", "-c", script],
            environment: {
                STORE_PATH: root.storePath,
                JSON_DATA: jsonStr,
                LUA_PATH: root.outputsLuaPath,
                LUA_DATA: luaStr,
                WRITE_LUA: writeLua ? "1" : "0"
            }
        });
    }

    function _planMatchesLive(plan) {
        const byName = {};
        for (const m of monitors) byName[m.name] = m;
        for (const e of plan) {
            const m = byName[e.name];
            if (!m) return false;
            if (m.enabled !== e.enabled) return false;
            if (!e.enabled) continue;
            if (Math.abs(m.x - Math.round(e.x)) > 1 || Math.abs(m.y - Math.round(e.y)) > 1) return false;
            if (Math.abs(m.scale - e.scale) > 0.02) return false;
            if ((m.transform || 0) !== (e.transform || 0)) return false;
            if (e.mode && e.mode !== "preferred") {
                const d = _parseModeDims(e.mode, m.width, m.height, m.refreshRate);
                if (m.width !== d.w || m.height !== d.h || Math.abs(m.refreshRate - d.hz) > 0.5) return false;
            }
        }
        return true;
    }

    function _applyPlan(plan, saveProfile, note) {
        const active = plan.filter(e => e.enabled);
        if (active.length === 0) {
            error = "At least one display must stay on.";
            return false;
        }
        error = "";
        busy = true;
        if (note) {
            statusNote = note;
            noteClear.restart();
        }
        // Update _lastKnown for all monitors in the plan.
        const known = Object.assign({}, _lastKnown);
        for (const e of plan) {
            known[e.id] = {
                enabled: e.enabled,
                mode: e.mode,
                scale: e.scale,
                x: e.x,
                y: e.y,
                transform: e.transform
            };
        }
        _lastKnown = known;

        if (comboKey) _lastComboKey = comboKey;
        _persistFiles(plan, saveProfile);

        const lua = _buildEvalLua(plan);
        applier.command = ["hyprctl", "eval", lua];
        applier.running = true;
        return true;
    }

    // --- Public actions (UI & IPC) ---

    function refresh(allowAutoApply) {
        if (reader.running) {
            _refreshQueued = true;
            _refreshQueuedAuto = _refreshQueuedAuto || !!allowAutoApply;
            return;
        }
        _pendingAutoApply = !!allowAutoApply;
        reader.running = true;
    }

    function setEnabled(name, enabled) {
        const plan = _planFromCurrent();
        const target = plan.find(e => e.name === name);
        if (!target || target.enabled === enabled) return false;
        if (!enabled && plan.filter(e => e.enabled).length <= 1) {
            error = "At least one display must stay on.";
            return false;
        }
        target.enabled = enabled;
        if (enabled) {
            const others = plan.filter(e => e.enabled && e.name !== name);
            if (others.length > 0 && _overlapsAny(target, others)) {
                let maxR = 0;
                for (const o of others) maxR = Math.max(maxR, o.x + o.logicalWidth);
                target.x = maxR;
                target.y = 0;
            }
        }
        _normalizePositions(plan);
        return _applyPlan(plan, true, enabled ? (name + " enabled") : (name + " disabled"));
    }

    function toggle(name) {
        const m = monitors.find(x => x.name === name);
        if (!m) return false;
        return setEnabled(name, !m.enabled);
    }

    function applyPreset(preset) {
        if (!hasBuiltin || !hasExternal) return false;
        const plan = _planFromCurrent();
        if (preset === "external") {
            let x = 0;
            for (const e of plan) {
                if (e.isBuiltin) {
                    e.enabled = false;
                } else {
                    e.enabled = true;
                    e.x = x;
                    e.y = 0;
                    x += e.logicalWidth;
                }
            }
            _normalizePositions(plan);
            return _applyPlan(plan, true, "External display only");
        }
        if (preset === "builtin") {
            for (const e of plan) {
                e.enabled = e.isBuiltin;
                if (e.isBuiltin) { e.x = 0; e.y = 0; }
            }
            _normalizePositions(plan);
            return _applyPlan(plan, true, "Laptop display only");
        }
        if (preset === "extend") {
            let x = 0;
            for (const e of plan) {
                e.enabled = true;
                e.x = x;
                e.y = 0;
                x += e.logicalWidth;
            }
            _normalizePositions(plan);
            return _applyPlan(plan, true, "Extended displays");
        }
        return false;
    }

    function setMode(name, modeStr) {
        const plan = _planFromCurrent();
        const target = plan.find(e => e.name === name);
        const mon = monitors.find(m => m.name === name);
        if (!target || !mon) return false;
        target.mode = modeStr;
        _recomputeLogical(target, mon);
        _snapAdjacentIfSideBySide(plan, name);
        return _applyPlan(plan, true, "Updated resolution");
    }

    function setScale(name, scale) {
        const s = Math.round(Number(scale) * 100) / 100;
        if (!s || s < 0.5 || s > 4) return false;
        const plan = _planFromCurrent();
        const target = plan.find(e => e.name === name);
        const mon = monitors.find(m => m.name === name);
        if (!target || !mon) return false;
        target.scale = s;
        _recomputeLogical(target, mon);
        _snapAdjacentIfSideBySide(plan, name);
        return _applyPlan(plan, true, "Scale " + s + "×");
    }

    function setTransform(name, transform) {
        const t = parseInt(transform, 10);
        if (isNaN(t) || t < 0 || t > 7) return false;
        const plan = _planFromCurrent();
        const target = plan.find(e => e.name === name);
        const mon = monitors.find(m => m.name === name);
        if (!target || !mon) return false;
        target.transform = t;
        _recomputeLogical(target, mon);
        _snapAdjacentIfSideBySide(plan, name);
        return _applyPlan(plan, true, "Rotated");
    }

    function relativePlacement(name) {
        const m = monitors.find(x => x.name === name && x.enabled);
        const others = monitors.filter(x => x.name !== name && x.enabled);
        if (!m || others.length === 0) return "";
        let oMinX = Infinity, oMaxX = -Infinity, oMinY = Infinity, oMaxY = -Infinity;
        for (const o of others) {
            oMinX = Math.min(oMinX, o.x);
            oMaxX = Math.max(oMaxX, o.x + o.logicalWidth);
            oMinY = Math.min(oMinY, o.y);
            oMaxY = Math.max(oMaxY, o.y + o.logicalHeight);
        }
        const mCx = m.x + m.logicalWidth / 2;
        const mCy = m.y + m.logicalHeight / 2;
        const oCx = (oMinX + oMaxX) / 2;
        const oCy = (oMinY + oMaxY) / 2;
        const dx = mCx - oCx;
        const dy = mCy - oCy;
        if (Math.abs(dx) >= Math.abs(dy)) return dx < 0 ? "left" : "right";
        return dy < 0 ? "above" : "below";
    }

    function setPlacement(name, side) {
        const plan = _planFromCurrent();
        const target = plan.find(e => e.name === name && e.enabled);
        const others = plan.filter(e => e.name !== name && e.enabled);
        if (!target || others.length === 0) return false;
        let oMinX = Infinity, oMaxX = -Infinity, oMinY = Infinity, oMaxY = -Infinity;
        for (const o of others) {
            oMinX = Math.min(oMinX, o.x);
            oMaxX = Math.max(oMaxX, o.x + o.logicalWidth);
            oMinY = Math.min(oMinY, o.y);
            oMaxY = Math.max(oMaxY, o.y + o.logicalHeight);
        }
        if (side === "left") {
            target.x = oMinX - target.logicalWidth;
            target.y = oMinY;
        } else if (side === "right") {
            target.x = oMaxX;
            target.y = oMinY;
        } else if (side === "above") {
            target.x = oMinX;
            target.y = oMinY - target.logicalHeight;
        } else if (side === "below") {
            target.x = oMinX;
            target.y = oMaxY;
        } else {
            return false;
        }
        _normalizePositions(plan);
        return _applyPlan(plan, true, "Moved " + side);
    }

    function _planFromSavedProfile(prof) {
        if (!prof || !prof.monitors) return null;
        const plan = monitors.map(m => {
            const cfg = prof.monitors[m.id] || _lastKnown[m.id] || null;
            const enabled = cfg ? !!cfg.enabled : m.enabled;
            const mode = (cfg && cfg.mode) || m.mode || "preferred";
            const scale = (cfg && cfg.scale) || m.scale || 1.6;
            const transform = (cfg && cfg.transform !== undefined) ? cfg.transform : (m.transform || 0);
            const x = (cfg && cfg.x !== undefined) ? cfg.x : m.x;
            const y = (cfg && cfg.y !== undefined) ? cfg.y : m.y;
            const dims = _parseModeDims(mode, m.width, m.height, m.refreshRate);
            const logical = _logicalSize(dims.w, dims.h, scale, transform);
            return {
                name: m.name,
                id: m.id,
                isBuiltin: m.isBuiltin,
                enabled: enabled,
                mode: mode,
                scale: scale,
                transform: transform,
                x: x,
                y: y,
                logicalWidth: logical.w,
                logicalHeight: logical.h
            };
        });
        if (!plan.some(e => e.enabled)) return null;
        _normalizePositions(plan);
        return plan;
    }

    function _handleMonitorsLoaded(text, exitCode) {
        const allowAuto = _pendingAutoApply;
        _pendingAutoApply = false;
        if (exitCode !== 0 || !text || !text.trim()) {
            if (_refreshQueued) {
                const qa = _refreshQueuedAuto;
                _refreshQueued = false; _refreshQueuedAuto = false;
                refresh(qa);
            }
            return;
        }
        let parsed;
        try {
            parsed = JSON.parse(text);
        } catch (e) {
            console.warn("Displays: failed to parse hyprctl monitors:", e);
            return;
        }
        const list = _normalizeMonitors(parsed);
        monitors = list;

        const key = comboKey;
        const savedProf = (store.profiles && key) ? (store.profiles[key] || null) : null;
        profileSaved = savedProf !== null;

        // Record live enabled settings in _lastKnown so re-enabling preserves them.
        const known = Object.assign({}, _lastKnown);
        for (const m of list) {
            if (m.enabled) {
                known[m.id] = {
                    enabled: true,
                    mode: m.mode,
                    scale: m.scale,
                    x: m.x,
                    y: m.y,
                    transform: m.transform
                };
            }
        }
        _lastKnown = known;

        // Emergency safety recovery: connected displays exist, none are enabled
        // (e.g., the sole external monitor was unplugged while eDP-1 was off).
        if (list.length > 0 && activeCount === 0) {
            const plan = _planFromSavedProfile(savedProf) || _planFromCurrent();
            if (!plan.some(e => e.enabled)) {
                const fallback = plan.find(e => e.isBuiltin) || plan[0];
                fallback.enabled = true;
                fallback.x = 0;
                fallback.y = 0;
                _normalizePositions(plan);
            }
            _lastComboKey = key;
            _applyPlan(plan, false, "Recovered display");
            if (_recoveryAttempt < 3) {
                _recoveryAttempt++;
                recoveryRetry.interval = _recoveryAttempt * 1000;
                recoveryRetry.restart();
            }
        } else {
            _recoveryAttempt = 0;
            recoveryRetry.stop();
            // Auto-apply saved profile when the connected monitor set changes
            // (startup or plug/unplug).
            if (allowAuto && key !== "" && key !== _lastComboKey) {
                _lastComboKey = key;
                if (savedProf) {
                    const plan = _planFromSavedProfile(savedProf);
                    if (plan && !_planMatchesLive(plan)) {
                        _applyPlan(plan, false, "Restored saved layout");
                    }
                }
            } else if (_lastComboKey === "" && key !== "") {
                _lastComboKey = key;
            }
        }

        if (_refreshQueued) {
            const qa = _refreshQueuedAuto;
            _refreshQueued = false; _refreshQueuedAuto = false;
            refresh(qa);
        }
    }

    function stateJson() {
        return JSON.stringify({
            comboKey: comboKey,
            profileSaved: profileSaved,
            activePreset: activePreset,
            activeCount: activeCount,
            connectedCount: connectedCount,
            error: error,
            statusNote: statusNote,
            monitors: monitors.map(m => ({
                name: m.name,
                id: m.id,
                label: m.label,
                isBuiltin: m.isBuiltin,
                enabled: m.enabled,
                focused: m.focused,
                mode: m.mode,
                width: m.width,
                height: m.height,
                refreshRate: m.refreshRate,
                scale: m.scale,
                x: m.x,
                y: m.y,
                transform: m.transform
            }))
        });
    }

    Process {
        id: reader
        command: ["hyprctl", "-j", "monitors", "all"]
        stdout: StdioCollector { id: readerOut }
        onExited: code => root._handleMonitorsLoaded(readerOut.text, code)
    }

    Process {
        id: applier
        stderr: StdioCollector { id: applyErr }
        stdout: StdioCollector { id: applyOut }
        onExited: code => {
            root.busy = false;
            const out = (applyOut.text || "").trim();
            const err = (applyErr.text || "").trim();
            if (code !== 0 || (out !== "" && out !== "ok")) {
                root.error = err || out || ("hyprctl exited with " + code);
            }
            settleRefresh.restart();
        }
    }

    Timer { id: settleRefresh; interval: 250; onTriggered: root.refresh(false) }
    Timer { id: hotplugDebounce; interval: 350; onTriggered: root.refresh(true) }
    Timer { id: recoveryRetry; interval: 1000; onTriggered: if (root.activeCount === 0) root.refresh(true) }
    Timer { id: noteClear; interval: 3500; onTriggered: root.statusNote = "" }

    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            if (!ev) return;
            const n = ev.name;
            if (n === "monitoradded" || n === "monitoraddedv2" ||
                n === "monitorremoved" || n === "monitorremovedv2" ||
                n === "configreloaded") {
                hotplugDebounce.restart();
            }
        }
    }
}
