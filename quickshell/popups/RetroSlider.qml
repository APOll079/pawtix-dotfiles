import QtQuick
import QtQuick.Controls.Basic

import ".."

// Horizontal slider: SegmentBar track with a raised bevel knob the height of the track.
// dim: draw the track empty (muted).
Slider {
    id: root

    property bool dim: false

    implicitHeight: MenuStyle.rowHeight + MenuStyle.gap
    hoverEnabled: true

    background: SegmentBar {
        value: root.visualPosition
        dim: root.dim
    }

    handle: Rectangle {
        x: root.leftPadding + root.visualPosition * (root.availableWidth - width)
        y: root.topPadding + root.availableHeight / 2 - height / 2
        implicitWidth: MenuStyle.sliderKnobWidth
        implicitHeight: root.implicitHeight
        color: Config.colors.base
        border.width: 1
        border.color: Config.colors.outline
        Bevel {
            anchors.fill: parent
            anchors.margins: 1
            thickness: 1
            raised: !root.pressed
        }
    }
}
