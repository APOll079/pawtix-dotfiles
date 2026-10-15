import Quickshell
import QtQuick
import QtQuick.Layouts
import ".."

// CPU, RAM and temperatures. Opens from the sysmon bar button; data comes from SysMon.qml.
PopupWindow {
    id: root
    // The bar window this popup hangs off (set by Bar.qml)
    required property var bar
    property var closeCallback: function() {}
    property var openTaskManager: function() {}

    anchor.window: root.bar
    anchor.rect.y: MenuStyle.barHeight
    implicitWidth: MenuStyle.widthSmall
    implicitHeight: MenuStyle.chromeHeight + column.implicitHeight
    color: "transparent"

    PopupWindowFrame {
        windowTitle: "System"
        windowTitleIcon: ""

        ColumnLayout {
            id: column
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: MenuStyle.gap

            StatRow {
                name: "CPU"
                value: Math.round(SysMon.cpuLoad * 100) + "%  " + SysMon.tempText(SysMon.cpuTemp)
            }
            SegmentBar {
                Layout.fillWidth: true
                implicitHeight: MenuStyle.rowHeight
                value: SysMon.cpuLoad
            }

            StatRow {
                name: "RAM"
                value: SysMon.memPercent + "%"
            }
            SegmentBar {
                Layout.fillWidth: true
                implicitHeight: MenuStyle.rowHeight
                value: SysMon.memLoad
            }

            MenuSeparator { Layout.fillWidth: true }

            StatRow { name: "GPU edge"; value: SysMon.tempText(SysMon.gpuEdge) }
            StatRow { name: "GPU hotspot"; value: SysMon.tempText(SysMon.gpuJunction) }
            StatRow { name: "GPU memory"; value: SysMon.tempText(SysMon.gpuMem) }

            BevelButton {
                Layout.fillWidth: true
                text: "Task Manager..."
                glyph: "\ue1db"
                onClicked: {
                    root.closeCallback();
                    root.openTaskManager();
                }
            }
        }
    }

    // Name on the left, value on the right, one row high
    component StatRow: RowLayout {
        property string name: ""
        property string value: ""
        Layout.fillWidth: true
        implicitHeight: MenuStyle.rowHeight
        spacing: MenuStyle.pad
        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferFullHinting
            Layout.fillWidth: true
            font.family: MenuStyle.titleFont
            font.pixelSize: MenuStyle.fontSize
            color: Config.colors.text
            text: parent.name
        }
        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferFullHinting
            horizontalAlignment: Text.AlignRight
            font.family: MenuStyle.bodyFont
            font.pixelSize: MenuStyle.fontSize
            color: Config.colors.text
            text: parent.value
        }
    }

    onVisibleChanged: {
        SysMon.detailed = visible;
        if (visible)
            SysMon.update();
    }

    function openMenu() { root.visible = true }
    function closeMenu() { root.visible = false }
}
