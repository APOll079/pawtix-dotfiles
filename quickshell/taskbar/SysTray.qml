import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.SystemTray
import QtQuick.Effects

import ".."

RowLayout {
    id: sysTrayRow
    spacing: MenuStyle.traySpacing
    property bool clockToggled: false
    signal clockClicked(var item)

    Repeater {
        id: sysTray
        model: SystemTray.items

        MouseArea {
            id: trayItem
            property SystemTrayItem item: modelData
            implicitWidth: Config.settings.bar.trayIconSize
            implicitHeight: Config.settings.bar.trayIconSize

            onClicked: event => {
                switch (event.button) {
                case Qt.LeftButton:
                    if (item.hasMenu) {
                        menu.open();
                    }
                    break;
                case Qt.RightButton:
                    if (item.hasMenu) {
                        menu.open();
                    }
                    break;
                }

                event.accepted = true;
            }

            // TODO: Create a bespoke menu design instead of using QsMenu.
            // Anchor the menu directly under its own icon, in taskbar-window
            // coordinates. trayItem.x is a dependency so this re-evaluates when
            // the tray relayouts. (Old calc double-counted clockWidget.width,
            // which is already inside sysTrayRow, so menus drifted left by the
            // clock's width and further with each tray item.)
            QsMenuAnchor {
                id: menu

                menu: trayItem.item.menu
                anchor.window: taskbar

                anchor.rect.x: sysTrayRow.mapToItem(null, trayItem.x, 0).x
                anchor.rect.y: taskbar.height

                anchor.rect.width: trayItem.width
                anchor.rect.height: trayItem.height
                anchor.edges: Edges.Bottom
            }

            IconImage {
                id: trayIcon
                source: trayItem.item.icon
                anchors.centerIn: parent
                width: parent.width
                height: parent.height
                visible: false
            }
            Loader {
                anchors.fill: trayIcon
                sourceComponent: MultiEffect {
                    source: trayIcon
                    saturation: Config.settings.bar.monochromeTrayIcons ? -1.0 : 0
                    contrast: Config.settings.bar.monochromeTrayIcons ? 0.7 : 0.0
                    opacity: mouse.hovered || menu.visible ? 1 : 0.7
                    blurEnabled: false
                }
            }
            HoverHandler {
                id: mouse
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                cursorShape: Qt.PointingHandCursor
            }

            // Tooltip after a short hover (not while the right-click menu is open)
            Timer {
                id: tipTimer
                interval: 500
                running: mouse.hovered && !menu.visible
                onTriggered: tip.shown = true
            }
            PopupWindow {
                id: tip
                property bool shown: false
                property string title: trayItem.item.tooltipTitle !== "" ? trayItem.item.tooltipTitle : trayItem.item.title
                property string description: trayItem.item.tooltipDescription
                visible: shown && mouse.hovered && !menu.visible && (title !== "" || description !== "")
                onVisibleChanged: if (!visible) shown = false
                anchor.window: taskbar
                anchor.rect.x: Math.max(4, Math.min(sysTrayRow.mapToItem(null, trayItem.x, 0).x + trayItem.width / 2 - width / 2, taskbar.width - width - 4))
                anchor.rect.y: taskbar.height
                implicitWidth: tipColumn.implicitWidth + 2 * MenuStyle.pad
                implicitHeight: tipColumn.implicitHeight + 2 * MenuStyle.gap + 2
                color: "transparent"
                Rectangle {
                    anchors.fill: parent
                    color: Config.colors.base
                    border.width: 1
                    border.color: Config.colors.outline
                    Column {
                        id: tipColumn
                        anchors.centerIn: parent
                        Text {
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferFullHinting
                            font.family: MenuStyle.bodyFont
                            font.pixelSize: MenuStyle.fontSize
                            font.bold: true
                            color: Config.colors.text
                            text: tip.title
                            visible: text !== ""
                        }
                        Text {
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferFullHinting
                            font.family: MenuStyle.bodyFont
                            font.pixelSize: MenuStyle.fontSize
                            color: Config.colors.text
                            text: tip.description
                            visible: text !== ""
                        }
                    }
                }
            }
        }
    }

    ClockWidget {
        id: clockWidget
        isToggled: sysTrayRow.clockToggled
        onClicked: sysTrayRow.clockClicked(clockWidget)
    }
}