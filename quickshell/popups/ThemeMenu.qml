import Quickshell
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

import ".."
// Qt Controls has its own MenuSeparator; ours is reached through Local
import "." as Local

PopupWindow {
    id: root
    // The bar window this popup hangs off (set by Bar.qml)
    required property var bar

    property int menuWidth: 0
    // Opens the wallpaper browser (set by Bar.qml)
    property var openWallpapers: function () {}
    anchor.window: root.bar
    anchor.rect.x: menuWidth
    anchor.rect.y: MenuStyle.barHeight
    implicitWidth: MenuStyle.widthLarge
    implicitHeight: MenuStyle.chromeHeight + content.implicitHeight
    color: "transparent"

    PopupWindowFrame {
        windowTitle: "Themes"
        windowTitleIcon: ""

        Column {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: MenuStyle.pad

            Flow {
                id: flow
                width: parent.width
                spacing: MenuStyle.pad

                Repeater {
                    model: Object.keys(Config.themes)
                    Button {
                        id: card
                        property string themeName: modelData
                        readonly property bool current: Config.settings.currentTheme === themeName

                        width: MenuStyle.cardWidth
                        height: MenuStyle.cardHeight
                        padding: 0
                        hoverEnabled: true
                        onClicked: {
                            Config.settings.currentTheme = themeName;
                            root.closeMenu();
                        }

                        background: Rectangle {
                            color: Config.colors.base
                            border.width: 1
                            border.color: Config.colors.outline
                            Bevel {
                                anchors.fill: parent
                                anchors.margins: 1
                                thickness: 1
                                raised: !(card.current || card.down)
                            }
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 3
                                visible: card.hovered
                                color: "transparent"
                                border.width: 1
                                border.color: MenuStyle.selectBar
                            }
                        }

                        contentItem: Item {
                            Column {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: (card.current || card.down) ? 1 : 0
                                anchors.horizontalCenterOffset: (card.current || card.down) ? 1 : 0
                                spacing: 4

                                // Palette preview: base, accent, highlight, shadow, text
                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    Repeater {
                                        model: ["base", "accent", "highlight", "shadow", "text"]
                                        Rectangle {
                                            width: MenuStyle.swatchWidth
                                            height: MenuStyle.swatchHeight
                                            color: Config.themes[card.themeName][modelData]
                                            border.width: 1
                                            border.color: Config.colors.outline
                                        }
                                    }
                                }
                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    spacing: 2
                                    Text {
                                        renderType: Text.NativeRendering
                                        font.hintingPreference: Font.PreferFullHinting
                                        visible: card.current
                                        font.family: MenuStyle.iconFont
                                        font.pixelSize: MenuStyle.iconSize - 2
                                        color: Config.colors.accent
                                        text: ""
                                    }
                                    Text {
                                        renderType: Text.NativeRendering
                                        font.hintingPreference: Font.PreferFullHinting
                                        font.family: MenuStyle.bodyFont
                                        font.pixelSize: MenuStyle.fontSize
                                        color: Config.colors.text
                                        text: card.themeName
                                    }
                                }
                            }
                        }

                        HoverHandler {
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            cursorShape: Qt.PointingHandCursor
                        }
                    }
                }
            }

            Local.MenuSeparator {
                width: parent.width
            }

            BevelButton {
                width: parent.width
                text: "Wallpapers..."
                glyph: "\ue1bc"
                onClicked: root.openWallpapers()
            }
        }
    }

    function openMenu() { openThemeMenu() }

    function openThemeMenu() {
        root.visible = true;
    }

    function closeMenu() {
        root.visible = false;
    }
}
