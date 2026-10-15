import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

import ".."

// Raised push button; pressing it flips the bevel to sunken and nudges the content.
Button {
    id: root

    property string glyph: ""
    // Optional colour for the glyph (e.g. the green liked heart); transparent = normal text colour
    property color glyphColor: "transparent"
    hoverEnabled: true

    implicitHeight: MenuStyle.rowHeight + MenuStyle.gap
    // Icon-only buttons are square (the glyph centred); text buttons are at least three rows wide
    implicitWidth: root.text === "" ? implicitHeight : Math.max(MenuStyle.rowHeight * 3, implicitContentWidth + leftPadding + rightPadding)
    leftPadding: root.text === "" ? 0 : MenuStyle.pad + 3
    rightPadding: root.text === "" ? 0 : MenuStyle.pad + 3
    topPadding: 0
    bottomPadding: 0

    background: Rectangle {
        color: Config.colors.base
        border.width: 1
        border.color: Config.colors.outline
        Bevel {
            anchors.fill: parent
            anchors.margins: 1
            thickness: 1
            raised: !(root.down || root.checked)
        }
        FocusRect {
            anchors.fill: parent
            anchors.margins: 3
            visible: root.visualFocus
            color: Config.colors.text
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: 3
            opacity: root.hovered && root.enabled && !root.visualFocus ? 1 : 0
            color: "transparent"
            border.width: 1
            border.color: MenuStyle.selectBar
            Behavior on opacity {
                NumberAnimation { duration: MenuStyle.animHover }
            }
        }
    }

    contentItem: Item {
        implicitWidth: row.implicitWidth
        implicitHeight: row.implicitHeight
        RowLayout {
            id: row
            anchors.fill: parent
            anchors.topMargin: (root.down || root.checked) ? 1 : 0
            anchors.leftMargin: (root.down || root.checked) ? 1 : 0
            spacing: MenuStyle.gap
            Item { Layout.fillWidth: true }
            RetroText {
                visible: root.glyph !== ""
                color: root.glyphColor.a > 0 && root.enabled ? root.glyphColor : Config.colors.text
                font.family: MenuStyle.iconFont
                font.pixelSize: MenuStyle.iconSize
                disabledLook: !root.enabled
                text: root.glyph
            }
            RetroText {
                visible: root.text !== ""
                font.family: MenuStyle.bodyFont
                font.pixelSize: MenuStyle.fontSize
                disabledLook: !root.enabled
                text: root.text
            }
            Item { Layout.fillWidth: true }
        }
    }

    HoverHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        cursorShape: Qt.PointingHandCursor
    }
}
