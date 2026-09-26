pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// Notification server, popups and the session history behind the centre.
//
// The server only exists while `enabled` is true, so a bar running beside
// another notification daemon (DMS in the shadow week) never competes for
// org.freedesktop.Notifications. shell.qml turns it on when `popups` or
// `center` is among the components.
//
// History is session memory: plain records that outlive the Notification
// object. While the sender keeps the notification alive, `live` points at it
// so actions still work and replaced text shows through.
Singleton {
    id: root
    property bool enabled: false
    property bool dnd: false
    property var popups: []                 // records, newest last (plain JS, identity matters)
    property var entries: []                // records, newest first
    property real seenAt: 0                 // entries newer than this are unread
    property int revision: 0                // bumps when a record loses its live notification
    readonly property int count: entries.length
    readonly property int unread: entries.filter(e => e.time > seenAt).length
    readonly property int historyLimit: 200

    // [{ app, icon, entries: [...] }], groups ordered by their newest entry.
    readonly property var groups: {
        const out = [];
        const byApp = {};
        for (const e of entries) {
            const key = e.appName || "Unknown";
            if (!byApp[key]) { byApp[key] = { app: key, icon: e.appIcon, entries: [] }; out.push(byApp[key]); }
            byApp[key].entries.push(e);
        }
        return out;
    }

    LazyLoader {
        active: root.enabled
        NotificationServer {
            keepOnReload: true
            bodySupported: true
            bodyMarkupSupported: true
            actionsSupported: true
            imageSupported: true
            persistenceSupported: true
            onNotification: n => root.receive(n)
        }
    }

    property int _seq: 0
    function receive(n) {
        n.tracked = true;
        const rec = {
            key: ++_seq,
            id: n.id,
            live: n,
            appName: n.appName || "",
            appIcon: n.appIcon || "",
            image: n.image || "",
            summary: n.summary || "",
            body: n.body || "",
            urgency: n.urgency,
            time: Date.now()
        };
        // Keep the text of the last generation once the sender closes it.
        // Records are matched by key: QML property storage may copy them.
        const key = rec.key;
        n.closed.connect(() => {
            const summary = n.summary, body = n.body;
            for (const e of root.entries) if (e.key === key) {
                e.summary = summary || e.summary; e.body = body || e.body; e.live = null;
            }
            root.entries = root.entries.slice();
            root.popups = root.popups.filter(p => p.key !== key);
            root.revision++;
        });
        if (!n.transient) {
            const next = [rec].concat(entries);
            if (next.length > historyLimit) next.length = historyLimit;
            entries = next;
        }
        const critical = n.urgency === NotificationUrgency.Critical;
        if (dnd && !critical) return;
        popups = popups.concat([rec]);
        if (!critical || n.expireTimeout > 0) {
            const t = popupTimer.createObject(root, { key: rec.key, interval: n.expireTimeout > 0 ? n.expireTimeout : 5000 });
            t.start();
        }
    }
    Component {
        id: popupTimer
        Timer {
            property int key
            onTriggered: { root.popups = root.popups.filter(p => p.key !== key); destroy(); }
        }
    }

    function dismissPopup(rec) { popups = popups.filter(p => p.key !== rec.key); }
    function dismiss(rec) {
        const live = liveOf(rec);
        dismissPopup(rec);
        entries = entries.filter(e => e.key !== rec.key);
        if (live) live.dismiss();
    }
    function liveOf(rec) {
        const e = entries.find(x => x.key === rec.key) ?? popups.find(x => x.key === rec.key);
        return e ? e.live : rec.live;
    }
    function clearApp(app) {
        const gone = entries.filter(e => (e.appName || "Unknown") === app);
        const keys = gone.map(e => e.key);
        entries = entries.filter(e => !keys.includes(e.key));
        popups = popups.filter(p => !keys.includes(p.key));
        for (const e of gone) if (e.live) e.live.dismiss();
    }
    function clearAll() {
        const gone = entries;
        entries = [];
        popups = [];
        for (const e of gone) if (e.live) e.live.dismiss();
    }
    function markSeen() { seenAt = Date.now(); }
    function setDnd(on) { dnd = on; if (on) popups = popups.filter(p => p.urgency === NotificationUrgency.Critical); }
}
