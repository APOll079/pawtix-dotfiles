import Quickshell
import QtQuick
import QtQuick.Layouts
import ".."

// Session panel (Start menu > Power, or `qs ipc call session_<monitor> toggle`): every
// Session.qml action plus your custom ones. Reboot and shutdown count down first
// (settings.json "session.countdownSeconds") with Now / Cancel; the others ask Yes / Cancel.
PopupWindow {
    id: root
    // The bar window this popup hangs off (set by Bar.qml)
    required property var bar
    property var closeCallback: function() {}
    property var pending: null       // action waiting for Yes
    property var counting: null      // action counting down
    property int remaining: 0

    anchor.window: root.bar
    anchor.rect.y: MenuStyle.barHeight
    implicitWidth: MenuStyle.widthSmall
    implicitHeight: MenuStyle.chromeHeight + column.implicitHeight
    color: "transparent"

    readonly property int total: Math.max(1, Config.settings.session.countdownSeconds)

    PopupWindowFrame {
        windowTitle: "Session"
        windowTitleIcon: ""

        ColumnLayout {
            id: column
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: MenuStyle.pad

            // Action list
            ColumnLayout {
                Layout.fillWidth: true
                visible: !root.pending && !root.counting
                spacing: 0
                Repeater {
                    model: Session.all
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        // Custom actions sit under a divider
                        MenuSeparator {
                            Layout.fillWidth: true
                            visible: index === Session.builtins.length
                        }
                        MenuRow {
                            Layout.fillWidth: true
                            text: modelData.name
                            glyph: modelData.icon
                            trailing: modelData.countdown ? root.total + " s" : ""
                            onClicked: {
                                if (modelData.countdown)
                                    root.startCountdown(modelData);
                                else if (modelData.confirm)
                                    root.pending = modelData;
                                else
                                    root.run(modelData);
                            }
                        }
                    }
                }
            }

            // Confirm
            ColumnLayout {
                Layout.fillWidth: true
                visible: !!root.pending
                spacing: MenuStyle.pad
                Text {
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferFullHinting
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    font.family: MenuStyle.bodyFont
                    font.pixelSize: MenuStyle.fontSize
                    color: Config.colors.text
                    text: root.pending ? root.pending.name + "?" : ""
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: MenuStyle.pad
                    BevelButton {
                        Layout.fillWidth: true
                        text: "Yes"
                        onClicked: root.run(root.pending)
                    }
                    BevelButton {
                        Layout.fillWidth: true
                        text: "Cancel"
                        onClicked: root.pending = null
                    }
                }
            }

            // Countdown
            ColumnLayout {
                Layout.fillWidth: true
                visible: !!root.counting
                spacing: MenuStyle.pad
                Text {
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferFullHinting
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    font.family: MenuStyle.bodyFont
                    font.pixelSize: MenuStyle.fontSize
                    color: Config.colors.text
                    text: root.counting ? root.counting.name + " in " + root.remaining + " s" : ""
                }
                SegmentBar {
                    Layout.fillWidth: true
                    implicitHeight: MenuStyle.rowHeight
                    value: root.remaining / root.total
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: MenuStyle.pad
                    BevelButton {
                        Layout.fillWidth: true
                        text: "Now"
                        onClicked: root.run(root.counting)
                    }
                    BevelButton {
                        Layout.fillWidth: true
                        text: "Cancel"
                        onClicked: root.cancel()
                    }
                }
            }
        }
    }

    Timer {
        id: tick
        interval: 1000
        repeat: true
        onTriggered: {
            root.remaining -= 1;
            if (root.remaining <= 0)
                root.run(root.counting);
        }
    }

    function startCountdown(action) {
        root.counting = action;
        root.remaining = root.total;
        tick.restart();
    }

    function cancel() {
        tick.stop();
        root.counting = null;
        root.pending = null;
    }

    function run(action) {
        tick.stop();
        root.counting = null;
        root.pending = null;
        Session.run(action);
        root.closeCallback();
    }

    function openMenu() { root.cancel(); root.visible = true }
    // Closing the panel also cancels a running countdown
    function closeMenu() { root.cancel(); root.visible = false }
}
