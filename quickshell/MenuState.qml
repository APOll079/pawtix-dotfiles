pragma Singleton
import QtQuick
import Quickshell

// Which monitors have a bar menu open, shared by every bar. While any menu is open, each monitor
// shows its invisible click catcher (Bar.qml `overlay`), so a click on either screen closes it.
Singleton {
    id: root

    property var openOn: ({})            // screen name -> true while that bar has a menu open
    readonly property bool anyOpen: Object.keys(root.openOn).some(k => root.openOn[k])

    signal closeAll()

    function setOpen(screen, open) {
        if (!!root.openOn[screen] === open)
            return;
        const o = Object.assign({}, root.openOn);
        o[screen] = open;
        root.openOn = o;
    }
}
