import Quickshell
import QtQuick
import QtQuick.Layouts

import ".."

PopupWindow {
    id: root
    // The bar window this popup hangs off (set by Bar.qml)
    required property var bar

    property int menuWidth: 0
    property var closeCallback: function () {}
    property var openPowerMenuCallback: function () {}
    property var openServicesCallback: function () {}
    property var openKeysCallback: function () {}
    anchor.window: root.bar
    anchor.rect.x: menuWidth
    anchor.rect.y: MenuStyle.barHeight
    implicitWidth: MenuStyle.widthLarge
    implicitHeight: MenuStyle.chromeHeight + column.implicitHeight
    color: "transparent"

    PopupWindowFrame {
        windowTitle: "Your Computer"
        windowTitleIcon: ""

        ColumnLayout {
            id: column
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: MenuStyle.pad

            RowLayout {
                Layout.fillWidth: true
                spacing: MenuStyle.pad

                SunkenField {
                    Layout.preferredWidth: MenuStyle.avatarSize
                    Layout.preferredHeight: MenuStyle.avatarSize
                    padding: 2
                    Image {
                        anchors.fill: parent
                        asynchronous: true
                        // settings.json may use ~ (QML doesn't expand it)
                        source: {
                            const p = Config.settings.systemProfileImageSource || "";
                            return p.startsWith("~/") ? Quickshell.env("HOME") + p.slice(1) : p;
                        }
                        fillMode: Image.PreserveAspectCrop
                        clip: true
                    }
                }

                SunkenField {
                    Layout.fillWidth: true
                    Layout.preferredHeight: MenuStyle.avatarSize
                    padding: MenuStyle.pad

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0

                        Repeater {
                            model: [
                                { icon: "", value: Config.settings.systemDetails.osName },
                                { icon: "", value: Config.settings.systemDetails.osVersion },
                                { icon: "", value: Config.settings.systemDetails.ram },
                                { icon: "", value: Config.settings.systemDetails.cpu },
                                { icon: "", value: Config.settings.systemDetails.gpu }
                            ]
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: MenuStyle.pad
                                Text {
                                    renderType: Text.NativeRendering
                                    font.hintingPreference: Font.PreferFullHinting
                                    font.family: MenuStyle.iconFont
                                    font.pixelSize: MenuStyle.iconSize
                                    color: Config.colors.text
                                    text: modelData.icon
                                }
                                Text {
                                    renderType: Text.NativeRendering
                                    font.hintingPreference: Font.PreferFullHinting
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    font.family: MenuStyle.bodyFont
                                    font.pixelSize: MenuStyle.fontSize
                                    color: Config.colors.text
                                    text: modelData.value
                                }
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: MenuStyle.pad

                BevelButton {
                    Layout.fillWidth: true
                    text: "Files"
                    glyph: ""
                    onClicked: {
                        Quickshell.execDetached(["sh", "-c", Config.settings.execCommands.files]);
                        root.closeCallback();
                    }
                }
                BevelButton {
                    Layout.fillWidth: true
                    text: "Terminal"
                    glyph: ""
                    onClicked: {
                        Quickshell.execDetached(["sh", "-c", Config.settings.execCommands.terminal]);
                        root.closeCallback();
                    }
                }
                BevelButton {
                    Layout.fillWidth: true
                    text: "Power"
                    glyph: ""
                    onClicked: {
                        root.closeCallback();
                        root.openPowerMenuCallback();
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: MenuStyle.pad

                BevelButton {
                    Layout.fillWidth: true
                    text: "Services"
                    glyph: "\ue8b8"
                    onClicked: {
                        root.closeCallback();
                        root.openServicesCallback();
                    }
                }
                BevelButton {
                    Layout.fillWidth: true
                    text: "Keys"
                    glyph: "\ue312"
                    onClicked: {
                        root.closeCallback();
                        root.openKeysCallback();
                    }
                }
            }
        }
    }

    function openMenu() { openStartMenu() }

    function openStartMenu() {
        root.visible = true;
    }

    function closeMenu() {
        root.visible = false;
    }
}
