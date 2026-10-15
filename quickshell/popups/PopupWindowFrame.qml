import QtQuick
import QtQuick.Layouts

import ".."

// Window chrome shared by every menu: solid 1px outline, raised 2px bevel and a Win95 title bar.
// Active (menus): solid accent bar, base-coloured title. Inactive (toasts, OSD): flat muted bar,
// text-coloured title. No close box: clicking the bar or outside closes menus.
// Children go into the body area below the title bar (see MenuStyle).
Rectangle {
    id: root

    anchors.fill: parent

    property string windowTitle: "Window Title"
    property string windowTitleIcon: ""
    property bool active: true
    // Title bar fill override (transparent = the active/inactive default); critical toasts use urgent
    property color titleColor: "transparent"
    readonly property color barColor: root.titleColor.a > 0 ? root.titleColor : (root.active ? MenuStyle.selectBar : Config.colors.shadow)
    property color titleTextColor: root.active && root.titleColor.a === 0 ? MenuStyle.selectText : Config.colors.text

    default property alias content: body.data

    color: Config.colors.base

    // Menus (active frames) fade in and slide down a few px when their window opens; toasts and
    // OSDs (inactive frames) keep their own behaviour. Closing stays instant.
    transform: Translate { id: openSlide }
    Connections {
        target: root.Window.window
        function onVisibleChanged() {
            if (root.active && root.Window.window && root.Window.window.visible && MenuStyle.animOpen > 0)
                openAnim.restart();
        }
    }
    ParallelAnimation {
        id: openAnim
        NumberAnimation { target: root; property: "opacity"; from: 0; to: 1; duration: MenuStyle.animOpen; easing.type: Easing.OutCubic }
        NumberAnimation { target: openSlide; property: "y"; from: -MenuStyle.animSlide; to: 0; duration: MenuStyle.animOpen; easing.type: Easing.OutCubic }
    }

    Bevel {
        anchors.fill: parent
        anchors.margins: 1
        raised: true
    }
    NewBorder {
        commonBorderWidth: 1
        commonBorder: false
        lBorderwidth: 0
        rBorderwidth: 0
        tBorderwidth: 0
        bBorderwidth: 0
        zValue: 1
        borderColor: Config.colors.outline
    }

    Rectangle {
        id: titleBar
        x: MenuStyle.frameInset
        y: MenuStyle.frameInset
        width: root.width - 2 * MenuStyle.frameInset
        height: MenuStyle.titleHeight
        color: root.barColor

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 2
            anchors.rightMargin: 2
            spacing: MenuStyle.titleSpacing

            Item { Layout.fillWidth: true }

            Row {
                spacing: MenuStyle.titleIconGap
                Text {
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferFullHinting
                    visible: root.windowTitleIcon !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: MenuStyle.iconFont
                    font.pixelSize: MenuStyle.iconSize
                    color: root.titleTextColor
                    text: root.windowTitleIcon
                }
                Text {
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferFullHinting
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: MenuStyle.titleFont
                    font.pixelSize: MenuStyle.fontSize
                    font.bold: true
                    color: root.titleTextColor
                    text: root.windowTitle
                }
            }

            Item { Layout.fillWidth: true }
        }
    }

    // Second frame: 1px outlined box around the content, like the original theme
    Rectangle {
        x: MenuStyle.frameInset
        y: MenuStyle.frameInset + MenuStyle.titleHeight + MenuStyle.boxGap
        width: root.width - 2 * MenuStyle.frameInset
        height: root.height - y - MenuStyle.frameInset
        color: "transparent"
        border.width: 1
        border.color: Config.colors.outline
    }

    Item {
        id: body
        x: MenuStyle.frameInset + 1 + MenuStyle.boxPadH
        y: MenuStyle.chromeTop
        width: root.width - 2 * (MenuStyle.frameInset + 1 + MenuStyle.boxPadH)
        height: root.height - MenuStyle.chromeTop - MenuStyle.chromeBottom
    }
}
