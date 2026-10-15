import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

import ".."

// One clickable row. Hover (or keyboard focus) fills it with the accent color, like a Win95 menu.
Button {
    id: root

    property string glyph: ""
    property url iconSource: ""
    property string trailing: ""
    property string subtext: ""
    property int subtextSize: MenuStyle.fontSize
    property bool marked: false
    property string markGlyph: "\ue5ca"     // the sign shown when marked (default: a check)
    property bool selected: false
    readonly property bool lit: hover.hovered || hovered || visualFocus || down || selected

    implicitHeight: subtext !== "" ? MenuStyle.rowHeight * 3 / 2 : MenuStyle.rowHeight
    implicitWidth: 160
    hoverEnabled: true
    leftPadding: MenuStyle.pad
    rightPadding: MenuStyle.pad
    topPadding: 0
    bottomPadding: 0

    background: Rectangle {
        color: root.lit ? MenuStyle.selectBar : Qt.rgba(MenuStyle.selectBar.r, MenuStyle.selectBar.g, MenuStyle.selectBar.b, 0)
        Behavior on color {
            ColorAnimation { duration: MenuStyle.animHover }
        }
        // Keyboard selection gets the dotted focus marker on top of the accent bar
        FocusRect {
            anchors.fill: parent
            anchors.margins: 1
            visible: root.selected || root.visualFocus
            color: MenuStyle.selectText
        }
    }

    contentItem: RowLayout {
        spacing: MenuStyle.pad
        Item {
            Layout.preferredWidth: MenuStyle.iconSize
            Layout.preferredHeight: MenuStyle.iconSize
            visible: root.glyph !== "" || root.iconSource != ""
            Image {
                id: appIcon
                anchors.fill: parent
                asynchronous: true
                smooth: false
                source: root.iconSource
                sourceSize: Qt.size(MenuStyle.iconSize * 2, MenuStyle.iconSize * 2)
                visible: status === Image.Ready
            }
            Text {
                renderType: Text.NativeRendering
                textFormat: Text.PlainText
                font.hintingPreference: Font.PreferFullHinting
                anchors.centerIn: parent
                visible: !appIcon.visible
                font.family: MenuStyle.iconFont
                font.pixelSize: MenuStyle.iconSize
                color: !root.enabled ? Config.colors.shadow : (root.lit ? MenuStyle.selectText : Config.colors.text)
                text: root.glyph
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            RetroText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
                font.family: MenuStyle.bodyFont
                font.pixelSize: MenuStyle.fontSize
                disabledLook: !root.enabled
                color: root.lit ? MenuStyle.selectText : Config.colors.text
                text: root.text
            }
            Text {
                renderType: Text.NativeRendering
                textFormat: Text.PlainText
                font.hintingPreference: Font.PreferFullHinting
                Layout.fillWidth: true
                visible: root.subtext !== ""
                elide: Text.ElideRight
                font.family: MenuStyle.bodyFont
                font.pixelSize: root.subtextSize
                color: root.lit ? MenuStyle.selectText : Config.colors.shadow
                text: root.subtext
            }
        }
        Text {
            renderType: Text.NativeRendering
            textFormat: Text.PlainText
            font.hintingPreference: Font.PreferFullHinting
            visible: root.trailing !== ""
            font.family: MenuStyle.bodyFont
            font.pixelSize: MenuStyle.fontSize
            color: !root.enabled ? Config.colors.shadow : (root.lit ? MenuStyle.selectText : Config.colors.text)
            text: root.trailing
        }
        Text {
            renderType: Text.NativeRendering
            textFormat: Text.PlainText
            font.hintingPreference: Font.PreferFullHinting
            visible: root.marked
            font.family: MenuStyle.iconFont
            font.pixelSize: MenuStyle.iconSize
            color: !root.enabled ? Config.colors.shadow : (root.lit ? MenuStyle.selectText : Config.colors.text)
            text: root.markGlyph
        }
    }

    HoverHandler {
        id: hover
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        cursorShape: Qt.PointingHandCursor
    }
}
