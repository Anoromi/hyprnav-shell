pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Singleton {
    id: root
    property list<var> popups: []          // recently arrived, shown briefly
    readonly property var history: server.trackedNotifications.values.slice().reverse()
    readonly property int unread: history.length

    NotificationServer {
        id: server
        keepOnReload: true
        bodySupported: true
        actionsSupported: true
        imageSupported: true
        persistenceSupported: true
        onNotification: n => {
            n.tracked = true;
            root.popups = root.popups.concat([n]);
            const t = popupTimer.createObject(root, { target: n });
            t.start();
        }
    }
    Component {
        id: popupTimer
        Timer {
            property var target
            interval: target && target.expireTimeout > 0 ? target.expireTimeout : 5000
            onTriggered: { root.dismissPopup(target); destroy(); }
        }
    }
    function dismissPopup(n) { root.popups = root.popups.filter(p => p !== n); }
    function clearAll() { for (const n of server.trackedNotifications.values.slice()) n.dismiss(); root.popups = []; }
    function dismiss(n) { dismissPopup(n); n.dismiss(); }
}
