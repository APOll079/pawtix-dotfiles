import QtQuick
import Quickshell
import Quickshell.Wayland

// Dims one screen while Idle.dimmed. Input passes straight through (empty mask), and any
// input ends idle, which removes the dim.
PanelWindow {
    id: root

    required property var modelData
    screen: modelData
    visible: Idle.dimmed
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    Rectangle {
        anchors.fill: parent
        color: Config.colors.outline
        opacity: MenuStyle.idleDimOpacity
    }
}
