pragma Singleton
import QtQuick
import Quickshell

// Which sheets beside the bar are open (control centre, notification centre,
// tray menus), for the click catcher: while any is open, a press outside all
// of them closes every one (see ClickCatcher.qml).
Singleton {
    id: root
    property int open: 0
    signal closeAll()
}
