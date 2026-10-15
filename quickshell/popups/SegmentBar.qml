import QtQuick

import ".."

// Level meter in a sunken field: a 1px dithered empty track with one solid fill from the left.
// value is 0..1; dim shows it empty (muted).
SunkenField {
    id: root

    property real value: 0
    property bool dim: false

    padding: 3

    Item {
        anchors.fill: parent
        Dither {
            anchors.fill: parent
            color1: Config.colors.base
            color2: Config.colors.highlight
        }
        Rectangle {
            width: root.dim ? 0 : Math.round(parent.width * Math.max(0, Math.min(1, root.value)))
            height: parent.height
            color: MenuStyle.selectBar
        }
    }
}
