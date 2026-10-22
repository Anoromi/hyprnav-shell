pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import "../services" as Services
import ".."
import "tabs.js" as TabsJs

// Environment grid: one roll per leaf environment, one frame per slot. A
// thread's roll carries its worktree's and project's frames too, tagged
// "shared", instead of repeating them as rolls of their own.
//
// Like the switcher, the layer surface stays mapped (transparent, empty input
// region, no keyboard) and opening flips opacity, input and focus. It opens
// from the grid snapshot the service keeps current from compositor and daemon
// events; a fresh one is requested in the background and updates the rolls in
// place. Thumbnails start capturing on open and fill in a frame or two later.
PanelWindow {
    id: win
    required property var modelData
    screen: modelData

    property bool open: false
    onOpenChanged: Services.Hyprnav.gridViewers += open ? 1 : -1
    property string phase: "closed"   // closed | open | activating | closing
    property int selRow: 0
    property int selCol: 0
    // The roll the selection is on, so it stays on that roll when the daemon
    // reorders rows under an open grid (a lock toggle moves the locked roll
    // to the top). Row objects are reused by position and only their envId
    // changes, so `rows` itself does not notify; the order string does.
    property string selEnv: ""
    readonly property string rowOrder: rows.map(r => r.envId).join("\n")
    onRowOrderChanged: {
        const kept = selEnv ? rows.findIndex(r => r.envId === selEnv) : -1;
        if (kept >= 0 && kept !== selRow) { selRow = kept; if (laid) ensureVisible(); }
        selEnv = rows[selRow]?.envId ?? "";
    }
    readonly property var rows: Services.Hyprnav.rows
    readonly property var selectedRow: rows[selRow] ?? null
    readonly property var selectedCell: selectedRow ? (selectedRow.cells[selCol]?.snapshot ?? null) : null

    // Browser tabs, in a column left of the rolls while the browser runs (see
    // services/BrowserTabs.qml). `zone` says which side the keys move on;
    // typing a hint jumps to a tab from either side.
    readonly property bool tabsShown: Services.BrowserTabs.available
    // "/" searches the tab column: letters go to the query instead of the
    // hints, and the column keeps only what matches.
    property bool searching: false
    property string tabQuery: ""
    readonly property var tabsModel: TabsJs.build(Services.BrowserTabs.snapshot, searching ? tabQuery : null, frozenAccess, expandedGroups)
    // Groups show as one header row each; these are the ones opened since
    // the grid did (group id -> true). A search expands its matches itself.
    property var expandedGroups: ({})
    // Open or close a group, the selection on its header unless `stay`.
    function setExpanded(groupId, on, stay) {
        const next = Object.assign({}, expandedGroups);
        if (on) next[groupId] = true; else delete next[groupId];
        expandedGroups = next;
        if (stay) return;
        const i = tabsModel.selectables.findIndex(x => x.key === "g:" + groupId);
        if (i >= 0) { typedLast = false; tabSel = i; }
    }
    // Esc or Backspace while a group's label is typed: drop it, and close
    // the group it opened.
    function clearHint() {
        const g = tabsModel.selectables.find(x => x.kind === "group" && x.expanded && x.base === hintPrefix);
        hintPrefix = "";
        if (g) setExpanded(g.groupId, false);
    }
    // Preview: while the selection is in the tab column, the browser comes
    // forward behind the grid and follows it tab by tab; the rolls and the
    // glass outside the column step aside so it shows. Enter keeps the tab,
    // closing any other way puts back the tab and window it started from.
    readonly property bool previewing: phase === "open" && tabsShown && zone === "tabs"
    // What the window shows: the tab column alone. Unlike `previewing` it
    // holds through the fade out, so closing from the column never brings
    // the rolls back for a frame. The rolls and scrim follow it in a fade
    // only while the grid is up; on open they start in place.
    readonly property bool tabsLook: phase !== "closed" && tabsShown && zone === "tabs"
    property var frozenAccess: null
    property var origin: null          // { tabId, address } at open
    property bool previewed: false
    property string previewKey: ""
    function captureOrigin() {
        const access = {};
        // The shell's recency, as Ctrl+Tab orders them (see tabs/mru.js).
        for (const t of (Services.BrowserTabs.snapshot?.tabs ?? [])) access[t.id] = Services.BrowserTabs.recency(t);
        frozenAccess = access;
        const here = TabsJs.build(Services.BrowserTabs.snapshot, null, access).hereTab;
        const top = Hyprland.activeToplevel;
        origin = { tabId: here, address: top ? addr(top) : "" };
        previewed = false; previewKey = "";
        Services.BrowserTabs.forgetPreviewFocus();
    }
    function undoPreview() {
        if (!previewed || !origin) return;
        previewed = false; previewKey = "";
        Services.BrowserTabs.restore(origin.tabId, origin.address);
    }
    // Previews wait for the selection to rest: a moment after a step or a
    // hover, longer while typing a query, so each keystroke does not switch
    // the browser to a tab the next one will filter away. Enter does not
    // wait: it opens the selection whatever is pending.
    readonly property int previewDelay: 120
    readonly property int previewTypingDelay: 350
    property bool typedLast: false     // the last selection change came from the query
    function schedulePreview() {
        previewTimer.interval = typedLast ? previewTypingDelay : previewDelay;
        previewTimer.restart();
    }
    onSelectedTabChanged: if (previewing) schedulePreview()
    onPreviewingChanged: {
        if (previewing) schedulePreview();
        else { previewTimer.stop(); if (phase === "open") undoPreview(); }   // back to the rolls
    }
    property bool settingQuery: false
    Timer {
        id: previewTimer
        interval: win.previewDelay
        onTriggered: {
            const item = win.selectedTab;
            if (!win.previewing || !item || item.key === win.previewKey) return;
            // Only entries with a tab: not "New tab", a group, or a closed one.
            if (!item.tabId) return;
            win.previewKey = item.key; win.previewed = true;
            Services.BrowserTabs.preview(item);
        }
    }
    function setQuery(q) {
        typedLast = true; settingQuery = true;
        tabQuery = q; tabSel = TabsJs.searchStart(tabsModel.selectables, q);
        settingQuery = false;
        if (previewing) schedulePreview();
    }
    function startSearch() {
        if (!tabsShown) return;
        searching = true; hintPrefix = ""; zone = "tabs"; userMoved = true;
        setQuery("");
    }
    // A member the search found stays in view: its group stays open.
    function stopSearch() {
        const sel = selectedTab;
        if (sel && sel.kind === "entry" && sel.groupId && !expandedGroups[sel.groupId]) setExpanded(sel.groupId, true, true);
        searching = false; tabQuery = "";
    }
    property string zone: "grid"       // grid | tabs
    property int tabSel: 0
    property string hintPrefix: ""
    readonly property var selectedTab: zone === "tabs" ? (tabsModel.selectables[tabSel] ?? null) : null
    onTabsShownChanged: if (!tabsShown) { zone = "grid"; hintPrefix = ""; }
    // Snapshots rebuild the entries; the selection follows its entry, not
    // its position.
    property string tabSelKey: ""
    onTabSelChanged: {
        tabSelKey = tabsModel.selectables[tabSel]?.key ?? "";
        // Anything but the query moving the selection previews at the quick pace.
        if (!settingQuery) typedLast = false;
    }
    onTabsModelChanged: {
        const kept = tabSelKey ? tabsModel.selectables.findIndex(x => x.key === tabSelKey) : -1;
        if (kept >= 0) tabSel = kept;
        else tabSel = Math.max(0, Math.min(tabSel, tabsModel.selectables.length - 1));
    }
    function enterTabs() {
        if (!tabsShown || tabsModel.selectables.length === 0) return;
        typedLast = false;
        tabSel = Math.max(0, Math.min(tabSel, tabsModel.selectables.length - 1));
        zone = "tabs"; userMoved = true;
    }
    // The selection onto an entry by its key, once it moved (pinned, say).
    function followTab(key) {
        const i = tabsModel.selectables.findIndex(x => x.key === key);
        if (i >= 0) tabSel = i;
    }
    function moveTab(d) {
        const n = tabsModel.selectables.length; if (n === 0) return;
        typedLast = false;
        tabSel = Math.max(0, Math.min(n - 1, tabSel + d));
    }
    // A completed hint opens its entry; with Shift it only selects it, for
    // the palette's actions. A group's label opens the group and stays typed,
    // so its members' labels, which continue it, finish the sequence; the
    // label typed again closes the group.
    function typeHint(ch, selectOnly) {
        let res = TabsJs.resolve(tabsModel.selectables, hintPrefix + ch);
        // A letter that leads nowhere after a prefix starts over.
        if (!res.exact && !res.partial && hintPrefix !== "") {
            hintPrefix = "";
            res = TabsJs.resolve(tabsModel.selectables, ch);
        }
        if (res.exact && res.exact.kind === "group") {
            hintPrefix = ""; zone = "tabs"; userMoved = true;
            const opening = !res.exact.expanded;
            setExpanded(res.exact.groupId, opening);
            if (opening) hintPrefix = res.exact.base;
        } else if (res.exact) {
            hintPrefix = ""; typedLast = false;
            tabSel = res.exact.index; zone = "tabs"; userMoved = true;
            if (!selectOnly) activateTab(res.exact);
        } else if (res.partial) hintPrefix += ch;
    }
    function activateTab(item) {
        if (!item || phase !== "open") return;
        if (item.kind === "group") { hintPrefix = ""; setExpanded(item.groupId, !item.expanded); return; }
        previewed = false;   // keep what was previewed: it is the choice
        previewTimer.stop();
        phase = "activating";
        hide();
        afterRelease.run(() => Services.BrowserTabs.open(item));
    }

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "hyprnav-shell-grid"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    mask: open ? null : nowhere
    Region { id: nowhere }
    PerfProbe { id: perf; label: "grid" }
    FocusRelease { id: afterRelease }

    property bool waitingOpen: false
    // The user picked a cell since the open (keys, a moved pointer, the
    // palette): a late snapshot then keeps their choice. Set only by `pick()`.
    property bool userMoved: false
    function pick(r, c) { selRow = r; selCol = c; selEnv = rows[r]?.envId ?? ""; userMoved = true; }
    // The frame the user is looking at. The focused workspace comes from
    // Hyprland's event stream, which is fresher than the snapshot's `active`
    // flags right after a switch. A shared frame shows in several rolls:
    // take the first row (the daemon puts the locked or current environment
    // there), then a locked roll, then the roll that owns the frame, then
    // the one the daemon marked active, then the topmost. Temporary slots are
    // cells like any other. Returns null when no roll shows the workspace.
    function activeCellPos() {
        const rs = Services.Hyprnav.rows;
        const ws = Hyprland.focusedWorkspace?.id ?? Services.Hyprnav.activeCell?.physical_workspace_id ?? null;
        let best = null, bestRank = -1;
        for (let r = 0; r < rs.length; r++) {
            const cells = rs[r].cells;
            for (let c = 0; c < cells.length; c++) {
                const s = cells[c].snapshot;
                if (!(ws !== null ? s.physical_workspace_id === ws : s.active === true)) continue;
                const rank = (r === 0 ? 8 : 0) + (rs[r].locked ? 4 : 0) + ((s.shared ?? s.inherited) ? 0 : 2) + (s.active ? 1 : 0);
                if (rank > bestRank) { best = { r: r, c: c }; bestRank = rank; }
            }
        }
        return best;
    }
    function selectInitial(res) {
        const rs = Services.Hyprnav.rows;
        let pos = activeCellPos();
        if (!pos) {
            // Not a frame of any roll (a stray workspace): the daemon's pick,
            // which is the first roll's first frame.
            const it = res.items[res.initial_index];
            let r = it ? rs.findIndex(x => x.rowIndex === it.row_index) : 0;
            if (r < 0) r = 0;
            pos = { r: r, c: it ? Math.max(0, it.column_index) : 0 };
        }
        selRow = pos.r; selCol = Math.max(0, Math.min(pos.c, (rs[pos.r]?.cells.length ?? 1) - 1));
        selEnv = rs[pos.r]?.envId ?? "";
        zone = "grid"; hintPrefix = ""; searching = false; tabQuery = ""; typedLast = false; expandedGroups = ({});
        userMoved = false;
    }
    // Hover selects only once the pointer has moved since the open (see
    // HoverGate.qml); `hovered` is the cell under the pointer meanwhile, so
    // the first real move can select it without waiting for another enter.
    HoverGate { id: hoverGate; onArmedChanged: if (armed) win.hoverSelect() }
    property var hovered: null
    function hoverEnter(r, c) {
        hovered = { r: r, c: c };
        if (hoverGate.armed && !scrolling) pick(r, c);
    }
    function hoverExit(r, c) { if (hovered && hovered.r === r && hovered.c === c) hovered = null; }
    function hoverSelect() { if (hovered && !scrolling && phase === "open") pick(hovered.r, hovered.c); }
    function present(res) {
        selectInitial(res);
        hoverGate.reset(); hovered = null;
        pendingScroll = true;
        perf.arm("open");
        finish.stop();
        // Into the column before the phase flips, so the window opens showing
        // the column alone instead of fading the rolls in and out again. The
        // current tab needs no preview: it would only pull the browser's
        // workspace in under the column before the user has moved.
        if (tabsOnOpen) {
            tabsOnOpen = false; focusTabs();
            if (selectedTab) previewKey = selectedTab.key;
        }
        phase = "open"; open = true; keys.forceActiveFocus();
        settleScroll();
    }
    // Open with the selection in the tab column, on the current tab. show()
    // may present only once the snapshot arrives, so that happens in present().
    // With the grid open a second press searches the tabs, as / does (from
    // the workspaces too), and a third closes. The key comes as a global
    // shortcut with Ctrl held, so the search field never sees it. A press
    // within repeatGuard of the last is a double fire and does nothing; a
    // quick deliberate double tap is slower than that.
    property bool tabsOnOpen: false
    readonly property int repeatGuard: 80
    property double tabsPressedAt: 0
    function showTabs() {
        const now = Date.now();
        if (now - tabsPressedAt < repeatGuard) return;
        tabsPressedAt = now;
        if (waitingOpen) { tabsOnOpen = true; return; }
        if (phase === "open") {
            if (searching || !tabsShown) close(); else startSearch();
            return;
        }
        tabsOnOpen = true;
        show();
    }
    function focusTabs() {
        if (!tabsShown || tabsModel.selectables.length === 0) return;
        hintPrefix = "";
        if (zone !== "tabs") tabSel = TabsJs.searchStart(tabsModel.selectables, "");
        enterTabs();
    }
    function show() {
        if (phase === "open") return;
        if (perf.enabled) console.info("[perf] grid show() at " + Date.now());
        Services.BrowserTabs.poke();
        captureOrigin();
        // Open from the snapshot in hand; the fresh one only corrects the
        // starting frame if the user has not moved yet.
        const cached = Services.Hyprnav.grid;
        waitingOpen = !(cached && cached.items && cached.items.length > 0);
        if (!waitingOpen) present(cached);
        Services.Hyprnav.refreshGrid(res => {
            if (!res) return;
            if (perf.enabled) console.info("[perf] grid snapshot at " + Date.now());
            if (win.waitingOpen) { win.waitingOpen = false; win.present(res); return; }
            if (win.phase === "open" && !win.userMoved) win.selectInitial(res);
        });
    }
    function toggle() { if (phase === "open") close(); else show(); }
    function showPalette() { palette.actions = paletteActions(); palette.show(); }
    function close() {
        waitingOpen = false; tabsOnOpen = false;
        if (phase !== "open") return;
        const undo = previewed;
        previewTimer.stop();
        phase = "closing"; hide();
        if (undo) afterRelease.run(() => win.undoPreview());
    }
    // Keyboard and input go back at once; the content fades out in tSnap.
    function hide() {
        open = false;
        if (palette.open) palette.hide();
        finish.interval = Theme.tSnap; finish.restart();
    }
    // Left and right walk the roll in reading order, across line breaks; up and
    // down step between lines, and leave the roll only from its first or last
    // line, landing on the nearest column of the neighbouring roll.
    function move(dr, dc) {
        if (rows.length === 0) return;
        if (dr !== 0) moveLine(dr); else moveCell(dc);
    }
    function moveCell(dc) {
        const n = rows[selRow]?.cells.length ?? 0;
        if (n === 0) return;
        pick(selRow, Math.max(0, Math.min(n - 1, selCol + dc)));
    }
    function moveLine(dr) {
        const n = rows[selRow]?.cells.length ?? 0;
        if (n === 0) return;
        const col = selCol % cols;
        const line = Math.floor(selCol / cols) + dr;
        if (line >= 0 && line < linesIn(n)) { pick(selRow, Math.min(n - 1, line * cols + col)); return; }
        const r = selRow + dr;
        if (r < 0 || r >= rows.length) return;
        const m = rows[r].cells.length;
        const target = dr > 0 ? col : (linesIn(m) - 1) * cols + col;
        pick(r, Math.max(0, Math.min(m - 1, target)));
    }
    function activate() {
        if (zone === "tabs") { activateTab(selectedTab); return; }
        const cell = selectedCell; if (!cell || phase !== "open") return;
        phase = "activating";
        hide();
        // Keyboard back first, then switch (see FocusRelease.qml).
        afterRelease.run(() => Services.Hyprnav.gotoSlot(cell.environment_id, cell.slot_index));
    }
    function togglePalette() { if (palette.open) palette.hide(); else showPalette(); }
    function toggleLock() {
        const row = selectedRow; if (!row) return;
        if (row.locked) Services.Hyprnav.unlock(); else Services.Hyprnav.lock(row.envId);
    }
    Timer { id: finish; onTriggered: win.phase = "closed" }
    // Thumbnails capture windows only while the overlay is up or fading out.
    // Keyed to `open` and the fade timer rather than `phase`, so a phase left
    // behind by an interrupted fade can never keep captures running unseen;
    // a capture still bound when its window closes can take the shell's
    // Wayland connection down.
    readonly property bool capturing: open || finish.running
    // A roll can lose frames under the grid; keep the selection on a real cell
    // so the ring and the line arithmetic stay valid.
    onRowsChanged: {
        if (rows.length === 0) return;
        selRow = Math.min(selRow, rows.length - 1);
        selCol = Math.max(0, Math.min(selCol, (rows[selRow]?.cells.length ?? 1) - 1));
        // Rolls that gained or lost a line move everything below them.
        settleScroll();
        if (!laid) return;
        scrollY = clampScroll(scrollY);
        ensureVisible();
    }
    // Temporary slots change on their own (empty timers, releases) and windows
    // open and close under the grid; both reach the service as a `slots` event
    // or a Hyprland event and it re-reads the snapshot on its own, debounced.
    // Agent beats deliberately do not refresh anything here: slot membership
    // cannot change on a beat, and the cells read the agent straight from the
    // pushed registry, so a working agent never disturbs the thumbnails.

    // Geometry
    readonly property int inset: 160
    // With the tab column the rolls start right of it. The column sits flush
    // against the 44 px bar and is as wide as Island's own tab strip, so while
    // previewing it covers the strip and not the page.
    readonly property int panelX: 44
    readonly property int panelW: 244
    readonly property int leftInset: tabsShown ? panelX + panelW + Theme.s32 + Theme.s16 : inset
    readonly property int cellW: 220
    readonly property int cellH: 138
    readonly property int gap: Theme.s16
    readonly property int titleH: 40
    readonly property int nameH: 30
    readonly property int rowGap: Theme.s32
    readonly property int lineGap: Theme.s16
    // A roll wider than the window wraps onto further lines of the same roll,
    // left to right, top to bottom. Every line holds the same number of frames.
    readonly property int availableWidth: width - leftInset - inset
    readonly property int cols: Math.max(1, Math.floor((availableWidth + gap) / (cellW + gap)))
    readonly property int lineH: cellH + nameH + lineGap
    function linesIn(count) { return Math.max(1, Math.ceil(count / cols)); }
    function rowHeight(count) { const n = linesIn(count); return titleH + n * (cellH + nameH) + (n - 1) * lineGap + rowGap; }
    // Prefix sum of row heights: rowTops[r] is the offset of row r below
    // `rowsTop`, rowTops[rows.length] the total height of the stack. It
    // re-evaluates when the rows or the window width change, and the rows'
    // `Behavior on y` animates the result.
    readonly property var rowTops: {
        const tops = [0];
        let y = 0;
        for (let i = 0; i < rows.length; i++) { y += rowHeight(rows[i].cells.length); tops.push(y); }
        return tops;
    }
    readonly property int stackH: rowTops[rows.length] ?? 0
    // Every row carries a trailing `rowGap`; the ink of the stack stops one gap
    // short of `stackH`.
    readonly property int contentH: Math.max(0, stackH - rowGap)
    // The viewport: the window minus the top margin and the room the hint line
    // needs at the bottom.
    readonly property int topInset: 24
    readonly property int bottomInset: 40
    readonly property int viewportH: Math.max(0, height - topInset - bottomInset)
    // Taller than the viewport: pin the stack to the top and scroll it.
    readonly property int rowsTop: Math.max(topInset, Math.round((height - stackH + rowGap) / 2))
    readonly property int maxScroll: Math.max(0, contentH - viewportH)
    // The soft edges are `fadeH` deep, so a selection parked one `rowGap` from
    // the edge would sit under one. Keep the ring clear of both.
    readonly property int fadeH: 28
    readonly property int scrollMargin: Math.max(rowGap, fadeH)
    property real scrollY: 0
    // Animate the slide, except on open, where the grid must appear already
    // scrolled rather than fly to the right place.
    property bool scrollAnimated: true
    readonly property bool canScrollUp: maxScroll > 0 && scrollY > 0.5
    readonly property bool canScrollDown: maxScroll > 0 && scrollY < maxScroll - 0.5
    Behavior on scrollY {
        enabled: !Theme.reducedMotion && win.scrollAnimated
        NumberAnimation { duration: Theme.tSnap; easing.type: Easing.OutCubic }
    }
    // A scroll slides the cells under a resting pointer; let the hover-select
    // settle before it takes the selection away from the keys.
    onScrollYChanged: { scrolling = true; hoverGuard.restart(); indicatorIdle.restart(); }
    property bool scrolling: false
    Timer { id: hoverGuard; interval: 300; onTriggered: win.scrolling = false }
    Timer { id: indicatorIdle; interval: 800; onTriggered: win.indicatorShown = false }
    property bool indicatorShown: false
    onScrollingChanged: if (scrolling) indicatorShown = true

    // Nothing below is meaningful before the window has a size.
    readonly property bool laid: width > 0 && viewportH > 0
    property bool pendingScroll: false
    // Open already scrolled to the selection, measured from the top, so a stack
    // that fits still shows its first roll at the top as it did before.
    function settleScroll() {
        if (!pendingScroll || !laid || rows.length === 0) return;
        pendingScroll = false;
        scrollAnimated = false;
        scrollY = 0;
        ensureVisible();
        Qt.callLater(() => win.scrollAnimated = true);
    }
    onLaidChanged: settleScroll()
    function clampScroll(v) { return Math.max(0, Math.min(maxScroll, v)); }
    function scrollBy(dy) { scrollY = clampScroll(scrollY + dy); }
    // Bring the selected cell's line into the viewport with the smallest move.
    // The first line of a roll carries its title, every line its name labels,
    // and the soft edges must not fall over either.
    function ensureVisible() {
        if (!laid) return;
        if (maxScroll <= 0) { scrollY = 0; return; }
        const r = selRow, c = selCol;
        if (!rows[r]) return;
        const line = Math.floor(c / cols);
        const rowTop = rowsTop + (rowTops[r] ?? 0);
        const top = line === 0 ? rowTop : rowTop + titleH + line * lineH;
        const bottom = rowTop + titleH + line * lineH + cellH + nameH;
        const vTop = scrollY + topInset;
        const vBottom = vTop + viewportH;
        if (top - scrollMargin < vTop) scrollY = clampScroll(top - scrollMargin - topInset);
        else if (bottom + scrollMargin > vBottom) scrollY = clampScroll(bottom + scrollMargin - topInset - viewportH);
    }
    onSelRowChanged: ensureVisible()
    onSelColChanged: ensureVisible()
    // Rows far outside the viewport keep their delegates but stop painting, so
    // ScreencopyView does not capture windows nobody can see.
    function rowVisible(i) {
        if (!laid || maxScroll <= 0) return true;
        const top = rowsTop + (rowTops[i] ?? 0);
        const bottom = top + rowHeight(rows[i]?.cells.length ?? 0);
        return bottom > scrollY + topInset - lineH && top < scrollY + topInset + viewportH + lineH;
    }
    function cellX(c) { return leftInset + (c % cols) * (cellW + gap); }
    // Where the cell sits in the stack, and where it sits on the screen.
    function cellTop(r, c) { return rowsTop + (rowTops[r] ?? 0) + titleH + Math.floor(c / cols) * lineH; }
    function cellY(r, c) { return cellTop(r, c) - scrollY; }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: ev => {
            if (ev.key === Qt.Key_P && (ev.modifiers & Qt.ControlModifier)) { if (palette.open) palette.hide(); else win.showPalette(); ev.accepted = true; return; }
            if (palette.open) return;
            // Hint letters jump to a tab. They include h, so with the column
            // up h no longer moves left; the arrows still do.
            const plain = !(ev.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier));
            if (win.searching) {
                const ctrl = (ev.modifiers & Qt.ControlModifier) !== 0;
                if (ctrl && (ev.key === Qt.Key_Backspace || ev.key === Qt.Key_W)) { win.setQuery(TabsJs.deleteWord(win.tabQuery)); ev.accepted = true; return; }
                if (ctrl && ev.key === Qt.Key_U) { win.setQuery(""); ev.accepted = true; return; }
                switch (ev.key) {
                case Qt.Key_Escape: if (win.tabQuery !== "") win.setQuery(""); else win.stopSearch(); break;
                case Qt.Key_Backspace: win.setQuery(win.tabQuery.slice(0, -1)); break;
                case Qt.Key_Down: case Qt.Key_Tab: win.moveTab(1); break;
                case Qt.Key_Up: case Qt.Key_Backtab: win.moveTab(-1); break;
                case Qt.Key_Return: case Qt.Key_Enter: win.activate(); break;
                default:
                    if (plain && ev.text.length === 1 && ev.text >= " ") win.setQuery(win.tabQuery + ev.text);
                    else return;
                }
                ev.accepted = true; return;
            }
            if (win.tabsShown && plain && ev.text === "/") { win.startSearch(); ev.accepted = true; return; }
            const ch = ev.text.toLowerCase();
            if (win.tabsShown && plain && ch.length === 1 && TabsJs.ALPHABET.indexOf(ch) >= 0) {
                win.typeHint(ch, (ev.modifiers & Qt.ShiftModifier) !== 0);
                ev.accepted = true; return;
            }
            if (win.hintPrefix !== "" && (ev.key === Qt.Key_Escape || ev.key === Qt.Key_Backspace)) {
                win.clearHint(); ev.accepted = true; return;
            }
            if (win.zone === "tabs") {
                perf.key();
                switch (ev.key) {
                case Qt.Key_Down: case Qt.Key_J: case Qt.Key_Tab: win.moveTab(1); break;
                case Qt.Key_Up: case Qt.Key_K: case Qt.Key_Backtab: win.moveTab(-1); break;
                case Qt.Key_Home: win.moveTab(-999); break;
                case Qt.Key_End: win.moveTab(999); break;
                case Qt.Key_Right: case Qt.Key_L: win.zone = "grid"; break;
                case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Space: win.activate(); break;
                case Qt.Key_Escape: win.close(); break;
                // Close the open group the selection is in.
                case Qt.Key_Backspace: {
                    const sel = win.selectedTab;
                    if (sel && sel.groupId && (sel.kind === "entry" || sel.expanded)) win.setExpanded(sel.groupId, false);
                    break;
                }
                default: return;
                }
                ev.accepted = true; return;
            }
            switch (ev.key) {
            case Qt.Key_Right: case Qt.Key_L: win.move(0, 1); break;
            case Qt.Key_Left: case Qt.Key_H:
                // Off the start of a line, into the tab column.
                if (win.tabsShown && win.selCol % win.cols === 0) win.enterTabs(); else win.move(0, -1);
                break;
            case Qt.Key_Down: case Qt.Key_J: win.move(1, 0); break;
            case Qt.Key_Up: case Qt.Key_K: win.move(-1, 0); break;
            case Qt.Key_Tab: win.move(0, 1); break;
            case Qt.Key_End: win.move(0, 99); break;
            case Qt.Key_Home: win.move(0, -99); break;
            case Qt.Key_Backtab: win.move(0, -1); break;
            case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Space: win.activate(); break;
            case Qt.Key_Escape: win.close(); break;
            default:
                if (ev.key >= Qt.Key_1 && ev.key <= Qt.Key_9) {
                    const n = ev.key - Qt.Key_1;
                    const row = win.selectedRow;
                    if (row) { const idx = row.cells.findIndex(c => c.snapshot.slot_index === n + 1); if (idx >= 0) { win.selCol = idx; win.activate(); } }
                } else return;
            }
            ev.accepted = true;
        }
        MouseArea {
            id: backdrop
            anchors.fill: parent; enabled: win.open; onClicked: win.close()
            hoverEnabled: true
            onPositionChanged: mouse => hoverGate.moved(backdrop, mouse.x, mouse.y)
        }
        // Wheel and touchpad scroll the stack and never move the selection.
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: ev => {
                const px = ev.pixelDelta.y !== 0 ? ev.pixelDelta.y : ev.angleDelta.y / 120 * 72;
                win.scrollBy(-px);
            }
        }
    }

    // Everything drawn: one short fade in and out, nothing moves.
    Item {
        id: content
        anchors.fill: parent
        opacity: win.open ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.tSnap } }
        onOpacityChanged: if (opacity === 1 && perf.enabled) console.info("[perf] grid opaque at " + Date.now())
        Rectangle {
            anchors.fill: parent; color: Theme.oScrim
            // Fully clear while previewing: below the glass rule's alpha
            // cut-off, so the browser shows unblurred. The tab column is an
            // opaque sheet of its own and needs no tint behind it.
            opacity: win.tabsLook ? 0 : 1
            Behavior on opacity { enabled: win.open; NumberAnimation { duration: Theme.tSnap } }
        }

        // Alpha mask for the viewport's soft edges (see layer.effect below).
        Item {
            id: edgeMask
            x: 0; y: win.topInset
            width: win.width; height: win.viewportH
            visible: false
            layer.enabled: true
            readonly property real f: height > 0 ? Math.min(0.5, win.fadeH / height) : 0
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(0, 0, 0, win.canScrollUp ? 0 : 1) }
                    GradientStop { position: edgeMask.f; color: "black" }
                    GradientStop { position: 1 - edgeMask.f; color: "black" }
                    GradientStop { position: 1; color: Qt.rgba(0, 0, 0, win.canScrollDown ? 0 : 1) }
                }
            }
        }

        // The viewport: the stack scrolls inside it, the ring travels with it.
        Item {
            id: viewport
            opacity: win.tabsLook ? 0 : 1
            // Hidden rolls build no cells and capture nothing (the rows'
            // Loaders and thumbnails follow their effective visibility).
            visible: opacity > 0
            Behavior on opacity { enabled: win.open; NumberAnimation { duration: Theme.tSnap } }
            x: 0; y: win.topInset
            width: win.width; height: win.viewportH
            clip: true
            // Content fades out to the glass at an edge the stack continues
            // past, instead of a tinted band painted over it.
            layer.enabled: win.maxScroll > 0
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: edgeMask
                maskThresholdMin: 0.0
                maskSpreadAtMin: 1.0
            }

            Item {
                id: scroller
                // Children keep stack coordinates; only this offset moves.
                x: 0; y: -win.topInset - win.scrollY
                width: parent.width

                // Rows
                Repeater {
                    model: win.rows
                    delegate: Item {
                        id: rowItem
                        required property var modelData
                        required property int index
                        visible: win.rowVisible(index)
                        x: win.leftInset
                        y: win.rowsTop + (win.rowTops[index] ?? 0)
                        width: win.availableWidth
                        height: win.rowHeight(modelData.cells.length)
                        // Rolls that gain or lose a line while the grid is up move
                        // the ones below; never on open.
                        Behavior on y { enabled: win.open && content.opacity === 1; NumberAnimation { duration: Theme.tSnap; easing.type: Easing.OutCubic } }

                        // Only rows near the viewport build their title and cells;
                        // with hundreds of rolls, building every one cost seconds
                        // and over a gigabyte. The row itself stays for layout.
                        Loader {
                            anchors.fill: parent
                            active: rowItem.visible
                            sourceComponent: Item {
                                anchors.fill: parent
                                // Title, the ancestors it sits in ("in Proj › main"), then a
                                // lock when any level of the chain is locked.
                                Row {
                                    id: header
                                    spacing: Theme.s12
                                    height: win.titleH
                                    width: parent.width
                                    Text {
                                        style: Text.Outline; styleColor: Theme.oHalo
                                        id: rowTitle
                                        width: Math.min(implicitWidth, header.width * 0.6)
                                        elide: Text.ElideRight
                                        text: rowItem.modelData.title
                                        color: rowItem.index === win.selRow ? Theme.oPaper : Theme.oFixer
                                        font.family: Theme.casual; font.pixelSize: Theme.fs22; font.weight: Font.Medium
                                    }
                                    Text {
                                        style: Text.Outline; styleColor: Theme.oHalo
                                        visible: rowItem.modelData.breadcrumb.length > 0
                                        anchors.baseline: rowTitle.baseline
                                        width: Math.min(implicitWidth, header.width - rowTitle.width - 60)
                                        elide: Text.ElideRight
                                        text: "in " + rowItem.modelData.breadcrumb.join(" › ")
                                        color: Theme.oFixer
                                        font.family: Theme.sans; font.pixelSize: Theme.fs13
                                    }
                                    // Last in the row, so locking or unlocking (Shift+L)
                                    // never slides the breadcrumb sideways.
                                    Glyph {
                                        visible: rowItem.modelData.locked
                                        anchors.verticalCenter: rowTitle.verticalCenter
                                        text: "󰌾"
                                        size: 15
                                        color: Theme.oPencil
                                    }
                                }

                                Repeater {
                                    model: rowItem.modelData.cells
                                    delegate: Item {
                                        id: cellItem
                                        required property var modelData
                                        required property int index
                                        // The GridCell outlives snapshots; only `snapshot` changes.
                                        readonly property var cell: modelData.snapshot
                                        // The agent comes from the pushed registry, so a beat
                                        // updates this row alone and never the whole grid.
                                        readonly property var agent: Services.Hyprnav.agentFor(cell.physical_workspace_id) ?? cell.agent ?? null
                                        readonly property bool isSelected: rowItem.index === win.selRow && index === win.selCol
                                        readonly property bool hasWindows: cell.window_count > 0
                                        readonly property string launchName: {
                                            if (cell.subtitle && cell.subtitle.indexOf("Workspace") !== 0) return cell.subtitle;
                                            return "";
                                        }
                                        x: (index % win.cols) * (win.cellW + win.gap)
                                        y: win.titleH + Math.floor(index / win.cols) * win.lineH
                                        width: win.cellW
                                        height: win.cellH + win.nameH

                                        Rectangle {
                                            id: frame
                                            width: win.cellW; height: win.cellH
                                            radius: Theme.rFrame
                                            color: cellItem.hasWindows ? Theme.oSheet : Theme.oEmulsion
                                            border.width: cellItem.cell.temporary ? 0 : 1
                                            border.color: Qt.rgba(Theme.oPaper.r, Theme.oPaper.g, Theme.oPaper.b, cellItem.hasWindows ? 0.35 : 0.12)
                                            Shape {
                                                anchors.fill: parent
                                                visible: cellItem.cell.temporary === true
                                                ShapePath {
                                                    strokeColor: Qt.rgba(Theme.oPaper.r, Theme.oPaper.g, Theme.oPaper.b, 0.4)
                                                    strokeWidth: 1
                                                    fillColor: "transparent"
                                                    strokeStyle: ShapePath.DashLine
                                                    dashPattern: [4, 4]
                                                    startX: 0.5; startY: 0.5
                                                    PathLine { x: win.cellW - 0.5; y: 0.5 }
                                                    PathLine { x: win.cellW - 0.5; y: win.cellH - 0.5 }
                                                    PathLine { x: 0.5; y: win.cellH - 0.5 }
                                                    PathLine { x: 0.5; y: 0.5 }
                                                }
                                            }
                                            WorkspaceThumb {
                                                anchors.fill: parent; anchors.margins: 3
                                                workspaceId: cellItem.cell.physical_workspace_id
                                                // A hidden row still holds its captures unless
                                                // they are dropped here; with hundreds of rolls
                                                // that ran out of fds and pinned the GPU.
                                                live: win.capturing && rowItem.visible
                                                emptyText: cellItem.hasWindows ? "" : (cellItem.cell.subtitle && cellItem.cell.subtitle.indexOf("Workspace") !== 0 ? "Opens " + cellItem.cell.subtitle : "Empty frame")
                                            }
                                            // Pin: a spawned process tree is stuck to this frame.
                                            Glyph {
                                                anchors.right: parent.right; anchors.top: parent.top
                                                anchors.rightMargin: 8; anchors.topMargin: 6
                                                visible: cellItem.cell.stuck === true
                                                text: "󰐃"
                                                size: 14
                                                color: Theme.oPencil
                                            }
                                            // Frame number, film-edge style. Temporary slots have no
                                            // number: they carry their name in Casual instead.
                                            Rectangle {
                                                x: 6; y: 6
                                                width: Math.min(num.implicitWidth + 10, win.cellW - 36); height: 20
                                                radius: 2
                                                color: cellItem.isSelected ? Theme.oPencil : Theme.oDarkroom
                                                Text {
                                                    id: num
                                                    anchors.centerIn: parent
                                                    width: Math.min(implicitWidth, parent.width - 10)
                                                    elide: Text.ElideRight
                                                    text: cellItem.cell.unnumbered ? cellItem.cell.workspace_name : cellItem.cell.slot_index
                                                    color: cellItem.isSelected ? Theme.oDarkroom : Theme.oPaper
                                                    font.family: cellItem.cell.unnumbered ? Theme.casual : Theme.mono
                                                    font.pixelSize: Theme.fs13; font.weight: Font.Medium
                                                }
                                            }
                                            // Agent status: who is working in this frame and what it did last.
                                            Row {
                                                anchors.left: parent.left; anchors.bottom: parent.bottom
                                                anchors.leftMargin: 6; anchors.bottomMargin: 6
                                                spacing: 6
                                                visible: cellItem.agent !== null && cellItem.agent !== undefined
                                                Rectangle {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 8; height: 8; radius: 4
                                                    color: cellItem.agent && cellItem.agent.state === "waiting_for_user" ? Theme.warn
                                                         : cellItem.agent && cellItem.agent.state === "working" ? Theme.oPencil : Theme.oFixer
                                                    SequentialAnimation on opacity {
                                                        running: cellItem.agent && cellItem.agent.state === "working"; loops: Animation.Infinite
                                                        NumberAnimation { to: 0.3; duration: 500 } NumberAnimation { to: 1; duration: 500 }
                                                    }
                                                }
                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: win.cellW - 40
                                                    elide: Text.ElideRight
                                                    text: {
                                                        const a = cellItem.agent; if (!a) return "";
                                                        if (a.state === "waiting_for_user") return "needs you";
                                                        if (a.state === "finished") return "finished";
                                                        if (a.state === "idle") return "idle";
                                                        return a.last_action ? a.last_action : "working";
                                                    }
                                                    color: Theme.oPaper
                                                    font.family: Theme.sans; font.pixelSize: Theme.fs12
                                                }
                                            }
                                            // Temporary slot empty timer
                                            Row {
                                                anchors.left: parent.left; anchors.bottom: parent.bottom
                                                anchors.leftMargin: 6; anchors.bottomMargin: 6
                                                spacing: 4
                                                visible: cellItem.cell.temporary === true && cellItem.cell.empty_for_ms !== null && cellItem.cell.empty_for_ms !== undefined && !cellItem.agent
                                                Glyph { text: "󰔟"; size: 12; color: Theme.oFixer }
                                                Text {
                                                    width: Math.min(implicitWidth, win.cellW - 32)
                                                    elide: Text.ElideRight
                                                    text: "empty " + Math.round((cellItem.cell.empty_for_ms || 0) / 1000) + " s, gone at 30"
                                                    color: Theme.oFixer
                                                    font.family: Theme.sans; font.pixelSize: Theme.fs12
                                                }
                                            }
                                            MouseArea {
                                                id: cellMouse
                                                anchors.fill: parent
                                                enabled: win.open
                                                hoverEnabled: true
                                                // Neither a pointer resting where it was when the
                                                // grid opened nor cells scrolled under it take the
                                                // selection from the keys (see hoverEnter).
                                                onEntered: win.hoverEnter(rowItem.index, cellItem.index)
                                                onExited: win.hoverExit(rowItem.index, cellItem.index)
                                                onPositionChanged: mouse => hoverGate.moved(cellMouse, mouse.x, mouse.y)
                                                // A click is deliberate: it opens the frame under it.
                                                onClicked: { win.pick(rowItem.index, cellItem.index); win.activate(); }
                                            }
                                        }
                                        Row {
                                            anchors.top: frame.bottom; anchors.topMargin: 7
                                            spacing: Theme.s8
                                            readonly property bool shared: (cellItem.cell.shared ?? cellItem.cell.inherited) === true
                                            Text {
                                                style: Text.Outline; styleColor: Theme.oHalo
                                                width: win.cellW - (cellItem.cell.active ? 50 : 0) - (parent.shared ? sharedTag.implicitWidth + Theme.s8 : 0)
                                                text: cellItem.agent ? ("agent: " + cellItem.agent.client) : cellItem.cell.unnumbered ? ("temporary" + (cellItem.cell.owner ? ", by " + cellItem.cell.owner : "")) : cellItem.cell.slot_display_name
                                                elide: Text.ElideRight
                                                color: cellItem.isSelected ? Theme.oPaper : Theme.oFixer
                                                font.family: Theme.sans; font.pixelSize: Theme.fs13
                                                font.weight: cellItem.isSelected ? Font.Medium : Font.Normal
                                            }
                                            // The same workspace every roll under this ancestor shows.
                                            Text {
                                                style: Text.Outline; styleColor: Theme.oHalo
                                                id: sharedTag
                                                visible: parent.shared
                                                text: "shared"
                                                color: Theme.oFixer
                                                opacity: 0.7
                                                font.family: Theme.sans; font.pixelSize: Theme.fs12
                                            }
                                            Text {
                                                style: Text.Outline; styleColor: Theme.oHalo
                                                visible: cellItem.cell.active
                                                text: "here"
                                                color: Theme.oPencil
                                                font.family: Theme.sans; font.pixelSize: Theme.fs13
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // The ring. It lives in the stack, so a scroll carries it along in one
                // piece; a selection change slides it in tSnap.
                Rectangle {
                    id: ring
                    visible: win.selectedCell !== null && win.zone === "grid"
                    readonly property int pad: 6
                    x: win.cellX(win.selCol) - pad
                    y: win.cellTop(win.selRow, win.selCol) - pad
                    width: win.cellW + pad * 2
                    height: win.cellH + pad * 2
                    radius: Theme.rFrame + pad
                    color: "transparent"
                    border.color: Theme.oPencil
                    border.width: Theme.ringWidth
                    Behavior on x { enabled: win.open && content.opacity === 1; NumberAnimation { duration: Theme.tSnap; easing.type: Easing.OutCubic } }
                    Behavior on y { enabled: win.open && content.opacity === 1; NumberAnimation { duration: Theme.tSnap; easing.type: Easing.OutCubic } }
                }
            }   // scroller

            // Where we are in the stack: a hair on the right edge, gone once the
            // grid has been still for a moment. No scrollbar.
            Rectangle {
                visible: win.maxScroll > 0 && win.phase !== "closed"
                x: parent.width - width
                width: 3
                radius: 1.5
                height: Math.max(40, viewport.height * viewport.height / Math.max(1, win.contentH))
                y: win.maxScroll <= 0 ? 0 : (viewport.height - height) * (win.scrollY / win.maxScroll)
                color: Theme.oFixer
                opacity: win.indicatorShown ? 0.9 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.tSnap } }
            }
        }

        TabsPanel {
            id: tabsPanel
            visible: win.tabsShown
            x: win.panelX; y: Theme.s8
            width: win.panelW; height: win.height - Theme.s8 * 2
            // Only beside the rolls: in the column the hints say it all.
            keyHints: win.zone === "grid" && !win.searching ? "/ search tabs · Ctrl+P actions" : ""
            model: win.tabsModel
            selIndex: win.zone === "tabs" ? win.tabSel : -1
            prefix: win.hintPrefix
            searching: win.searching
            query: win.tabQuery
            live: win.open
            hoverArmed: hoverGate.armed
            onPointerMoved: (item, x, y) => hoverGate.moved(item, x, y)
            onHovered: index => { if (!win.scrolling) { win.typedLast = false; win.tabSel = index; win.zone = "tabs"; win.userMoved = true; } }
            onPicked: item => { win.tabSel = item.index; win.zone = "tabs"; win.activateTab(item); }
        }
    }

    // Command palette
    CommandPalette {
        id: palette
        opacity: content.opacity
        anchors.centerIn: parent
        actions: []
        onRun: (action, text) => win.runAction(action, text)
        onOpenChanged: if (!open) keys.forceActiveFocus()
    }
    readonly property var paletteActions: function() {
        const cell = win.zone === "grid" ? win.selectedCell : null; const row = win.zone === "grid" ? win.selectedRow : null;
        const list = [];
        const tab = win.selectedTab;
        const groupName = tab && tab.groupId ? (Services.BrowserTabs.model.groups.find(g => g.id === tab.groupId) || {}).name || "" : "";
        // Essentials, pinned tabs and group members whose tab went elsewhere.
        function drift(scope) {
            if (!tab.drifted) return;
            list.push({ id: "entry-replace-url", scope: scope, title: "Replace URL with current" });
            list.push({ id: "entry-reset", scope: scope, title: "Reset" });
        }
        if (tab && tab.kind === "tab") {
            list.push({ id: "tab-open", scope: "tab", title: "Open" });
            list.push({ id: "tab-pin", scope: "tab", title: "Pin to Essentials" });
            list.push({ id: "tab-pin-row", scope: "tab", title: "Pin" });
            list.push({ id: "tab-group", scope: "tab", title: "Move to group…", needsText: true, prompt: "Group", defaultText: "" });
            list.push({ id: "tab-close", scope: "tab", title: "Close" });
        } else if (tab && tab.kind === "entry") {
            const pinned = tab.place === "pinned";
            const scope = pinned ? "pinned" : "group";
            list.push({ id: "tab-open", scope: scope, title: "Open" });
            if (tab.open) list.push({ id: "tab-pin", scope: scope, title: "Pin to Essentials" });
            if (!pinned) list.push({ id: "tab-pin-row", scope: scope, title: "Pin" });
            list.push({ id: "tab-group", scope: scope, title: "Move to group…", needsText: true, prompt: "Group", defaultText: "" });
            list.push({ id: "entry-remove", scope: scope, title: pinned ? "Unpin" : "Remove from group" });
            drift(scope);
            if (tab.open) list.push({ id: "tab-close", scope: scope, title: "Close" });
            if (!pinned) list.push({ id: "group-rename", scope: "group", title: "Rename group…", needsText: true, prompt: "Name", defaultText: groupName });
            if (!pinned) list.push({ id: "group-delete", scope: "group", title: "Delete group" });
        } else if (tab && tab.kind === "group") {
            list.push({ id: "tab-open", scope: "group", title: tab.expanded ? "Collapse" : "Expand" });
            list.push({ id: "group-rename", scope: "group", title: "Rename…", needsText: true, prompt: "Name", defaultText: groupName });
            list.push({ id: "group-delete", scope: "group", title: "Delete group" });
        } else if (tab && tab.kind === "essential") {
            list.push({ id: "tab-open", scope: "essential", title: "Open" });
            list.push({ id: "essential-rename", scope: "essential", title: "Rename…", needsText: true, prompt: "Name", defaultText: tab.title });
            list.push({ id: "essential-unpin", scope: "essential", title: "Remove from Essentials" });
            drift("essential");
            if (tab.open) list.push({ id: "tab-close", scope: "essential", title: "Close" });
        }
        if (win.tabsShown) {
            list.push({ id: "browser-new", scope: "browser", title: "Open in new tab…", needsText: true, prompt: "URL or search", defaultText: "" });
            list.push({ id: "browser-pin-active", scope: "browser", title: "Pin current tab to Essentials" });
        }
        if (cell) {
            list.push({ id: "open", scope: "frame", title: "Open frame" });
            list.push({ id: "slot-remove", scope: "frame", title: cell.temporary ? "Remove temporary slot" : "Remove slot" });
            list.push({ id: "slot-rename", scope: "frame", title: "Rename slot", needsText: true, prompt: "New name", defaultText: cell.slot_display_name });
            list.push({ id: "slot-command", scope: "frame", title: "Set launch command", needsText: true, prompt: "Command", defaultText: "" });
            list.push({ id: "slot-command-clear", scope: "frame", title: "Clear launch command" });
            if (cell.stuck) list.push({ id: "stick-release", scope: "frame", title: "Release stuck tree" });
            if (cell.window_count > 0) list.push({ id: "close-all", scope: "frame", title: "Close all windows here" });
            if (cell.window_count > 0) list.push({ id: "move-windows", scope: "frame", title: "Move windows to slot…", needsText: true, prompt: "Slot number or name", defaultText: "" });
        }
        if (row) {
            list.push({ id: "temp-new", scope: "roll", title: "New temporary slot" });
            list.push({ id: "temp-run", scope: "roll", title: "New temporary slot and run…", needsText: true, prompt: "Command", defaultText: "" });
            list.push({ id: "env-rename", scope: "roll", title: "Rename environment", needsText: true, prompt: "Title", defaultText: row.title });
            list.push({ id: "lock", scope: "roll", title: row.locked ? "Unlock environment" : "Lock environment" });
            if (row.cells.every(c => c.snapshot.window_count === 0)) list.push({ id: "env-delete", scope: "roll", title: "Delete environment" });
        }
        list.push({ id: "goto-locked", scope: "everywhere", title: "Go to locked environment" });
        list.push({ id: "refresh", scope: "everywhere", title: "Refresh" });
        return list;
    }
    function windowsOn(workspaceId) {
        return Hyprland.toplevels.values.filter(t => t.workspace && t.workspace.id === workspaceId);
    }
    // Ask the compositor directly which windows sit on a workspace. Quickshell's
    // toplevel cache can lag behind windows the stick manager moved at open.
    function withWindowsOn(workspaceId, cb) {
        const proc = clientsRunner.createObject(win, { command: ["hyprctl", "-j", "clients"], workspaceId: workspaceId, callback: cb });
        proc.running = true;
    }
    Component {
        id: clientsRunner
        Process {
            property int workspaceId: -1
            property var callback: null
            stdout: StdioCollector {
                onStreamFinished: {
                    let list = [];
                    try { list = JSON.parse(text).filter(c => c.workspace && c.workspace.id === workspaceId && c.mapped).map(c => c.address); } catch (e) { console.log("clients parse failed", e); }
                    if (callback) callback(list);
                }
            }
            onExited: destroy()
        }
    }
    // Hyprland wants "address:0x…"; Quickshell reports the hex without the prefix.
    function addr(t) { const a = String(t.address); return "address:" + (a.startsWith("0x") ? a : "0x" + a); }
    // Over Quickshell's Hyprland socket, as BrowserTabs does: Lua dispatcher
    // calls go through, without a hyprctl process per window.
    function dispatch(cmd) { Hyprland.dispatch(cmd); }
    // Slot mutations go to the environment that binds the slot; a shared
    // frame belongs to an ancestor. Going to a frame stays on the row's leaf,
    // which resolves the same workspace and keeps the leaf's launch command.
    function ownerOf(cell) { return cell.owner_environment_id || cell.binding_environment_id || cell.environment_id; }
    function runAction(action, text) {
        const cell = win.selectedCell; const row = win.selectedRow;
        const tab = win.selectedTab;
        const tabs = Services.BrowserTabs;
        switch (action.id) {
        case "tab-open": win.activateTab(tab); break;
        case "tab-pin": if (tab) followTab("e:" + tabs.pin(tab.tabId)); break;
        case "tab-pin-row": if (tab) { if (tab.kind === "entry") { tabs.moveEntry(tab.id, null); followTab("p:" + tab.id); } else followTab("p:" + tabs.pinTab(tab.tabId)); } break;
        case "tab-group": if (tab && text.trim()) { if (tab.kind === "entry") tabs.moveEntry(tab.id, text); else tabs.assign(tab.tabId, text); } break;
        case "entry-remove": if (tab) tabs.removeEntry(tab.id); break;
        case "entry-replace-url": if (tab) tabs.replaceUrl(tab.id); break;
        case "entry-reset": if (tab) tabs.reset(tab.id); break;
        case "tab-close": if (tab) tabs.close(tab.tabId); break;
        case "group-rename": if (tab) tabs.renameGroup(tab.groupId, text); break;
        case "group-delete": if (tab) tabs.deleteGroup(tab.groupId); break;
        case "essential-rename": if (tab) tabs.renameEssential(tab.id, text); break;
        case "essential-unpin": if (tab) tabs.removeEntry(tab.id); break;
        case "browser-new": if (win.phase === "open") { win.phase = "activating"; win.hide(); afterRelease.run(() => tabs.open({ kind: "new", text: text })); } break;
        case "browser-pin-active": tabs.pinFront(); break;
        case "open": win.activate(); break;
        case "slot-remove": if (cell) Services.Hyprnav.slotRemove(win.ownerOf(cell), cell.slot_index); break;
        case "slot-rename": if (cell) Services.Hyprnav.slotRename(win.ownerOf(cell), cell.slot_index, text.trim()); break;
        case "slot-command": if (cell && text.trim()) Services.Hyprnav.slotCommandSet(win.ownerOf(cell), cell.slot_index, Services.Hyprnav.splitArgv(text.trim())); break;
        case "slot-command-clear": if (cell) Services.Hyprnav.slotCommandClear(win.ownerOf(cell), cell.slot_index); break;
        case "stick-release": if (cell) Services.Hyprnav.stickRelease(cell.physical_workspace_id); break;
        case "close-all": if (cell) withWindowsOn(cell.physical_workspace_id, list => { for (const a of list) dispatch("hl.dsp.window.kill({ window = \"address:" + a + "\" })"); }); break;
        case "move-windows": {
            if (!cell || !row) break;
            const q = text.trim().toLowerCase();
            const target = row.cells.map(c => c.snapshot).find(c => String(c.slot_index) === q || (c.slot_display_name || "").toLowerCase() === q);
            if (!target) break;
            withWindowsOn(cell.physical_workspace_id, list => { for (const a of list) dispatch("hl.dsp.window.move({ window = \"address:" + a + "\", workspace = \"" + target.physical_workspace_id + " silent\" })"); });
            break;
        }
        case "temp-new": if (row) Services.Hyprnav.slotTempCreate(row.envId, null); break;
        case "temp-run": if (row && text.trim()) Services.Hyprnav.slotTempCreate(row.envId, null, (res) => { if (res && res.physical_workspace_id) Quickshell.execDetached(["hyprnav", "spawn", "--no-focus", String(res.physical_workspace_id), "--"].concat(Services.Hyprnav.splitArgv(text.trim()))); }); break;
        case "env-rename": if (row && text.trim()) Services.Hyprnav.envTitleSet(row.envId, text.trim()); break;
        case "lock": win.toggleLock(); break;
        case "env-delete": if (row) Services.Hyprnav.envDelete(row.envId); break;
        case "goto-locked": { const lockedRow = win.rows.findIndex(r => r.locked); if (lockedRow >= 0) win.pick(lockedRow, 0); break; }
        case "refresh": Services.Hyprnav.refreshAll(); break;
        }
    }

    // Key hints, bottom left. With the tab column up they live on its sheet.
    Text {
        style: Text.Outline; styleColor: Theme.oHalo
        x: win.inset
        y: win.height - win.bottomInset + Math.round((win.bottomInset - height) / 2)
        text: "Enter opens the frame.  Ctrl+P for actions.  Esc closes.  󰐃 marks a stuck tree."
        color: Theme.oFixer
        font.family: Theme.sans; font.pixelSize: Theme.fs13
        opacity: content.opacity * 0.8
        visible: content.visible && !win.tabsShown
    }
}
