import Quickshell
import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import ".."

// Bluetooth, straight from BlueZ through Quickshell.Bluetooth (no bluetoothctl polling).
// - Power and scan toggles.
// - Paired devices: click to connect / disconnect; Trust (= BlueZ lets it auto-reconnect) and
//   Forget (asks first) per row; battery when the device reports it.
// - While scanning, unpaired devices show under "Available": click pairs, then trusts and
//   connects. Headphones and speakers pair without a PIN; PIN devices need an agent (not here).
PopupWindow {
    id: root
    // The bar window this popup hangs off (set by Bar.qml)
    required property var bar
    property var closeCallback: function() {}
    property var forgetting: null     // device waiting for "Forget?" confirm

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool powered: adapter !== null && adapter.enabled
    readonly property var devices: Bluetooth.devices.values
    readonly property var paired: devices.filter(d => d.paired).sort((a, b) => (b.connected - a.connected) || root.label(a).localeCompare(root.label(b)))
    readonly property var available: devices.filter(d => !d.paired && (d.name !== "" || d.deviceName !== "")).sort((a, b) => root.label(a).localeCompare(root.label(b)))

    anchor.window: root.bar
    anchor.rect.y: MenuStyle.barHeight
    implicitWidth: MenuStyle.widthMedium
    implicitHeight: MenuStyle.chromeHeight + column.implicitHeight
    color: "transparent"

    function label(d) {
        return d.name || d.deviceName || d.address;
    }

    function status(d) {
        if (d.pairing)
            return "Pairing...";
        if (d.state === BluetoothDeviceState.Connecting)
            return "Connecting...";
        if (d.state === BluetoothDeviceState.Disconnecting)
            return "Disconnecting...";
        if (d.connected)
            return d.batteryAvailable ? Math.round(d.battery * 100) + "%" : "Connected";
        return "";
    }

    // Pair, then trust (auto-reconnect) and connect once BlueZ reports it paired
    function pairDevice(d) {
        d.pair();
        pairWatch.device = d;
    }

    Connections {
        id: pairWatch
        property var device: null
        target: device
        function onPairedChanged() {
            if (pairWatch.device && pairWatch.device.paired) {
                pairWatch.device.trusted = true;
                pairWatch.device.connect();
                pairWatch.device = null;
            }
        }
    }

    // Scanning stops on its own after a while
    Timer {
        id: scanStop
        interval: MenuStyle.bluetoothScanTime
        onTriggered: if (root.adapter) root.adapter.discovering = false
    }

    PopupWindowFrame {
        windowTitle: "Bluetooth"
        windowTitleIcon: ""

        ColumnLayout {
            id: column
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: MenuStyle.pad

            RowLayout {
                Layout.fillWidth: true
                spacing: MenuStyle.pad
                BevelButton {
                    Layout.fillWidth: true
                    enabled: root.adapter !== null
                    text: root.powered ? "Turn Bluetooth Off" : "Turn Bluetooth On"
                    onClicked: root.adapter.enabled = !root.adapter.enabled
                }
                BevelButton {
                    implicitWidth: MenuStyle.rowHeight + MenuStyle.gap
                    enabled: root.powered
                    glyph: ""
                    checked: root.adapter !== null && root.adapter.discovering
                    onClicked: {
                        root.adapter.discovering = !root.adapter.discovering;
                        if (root.adapter.discovering)
                            scanStop.restart();
                    }
                }
            }

            // Forget confirm
            RowLayout {
                Layout.fillWidth: true
                visible: root.forgetting !== null
                spacing: MenuStyle.gap
                Text {
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferFullHinting
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.family: MenuStyle.bodyFont
                    font.pixelSize: MenuStyle.fontSize
                    color: Config.colors.text
                    text: root.forgetting ? "Forget " + root.label(root.forgetting) + "?" : ""
                }
                BevelButton {
                    text: "Yes"
                    onClicked: {
                        root.forgetting.forget();
                        root.forgetting = null;
                    }
                }
                BevelButton {
                    text: "Cancel"
                    onClicked: root.forgetting = null
                }
            }

            Text {
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferFullHinting
                visible: root.powered
                font.family: MenuStyle.titleFont
                font.pixelSize: MenuStyle.fontSize
                color: Config.colors.text
                text: "Paired"
            }

            SunkenField {
                Layout.fillWidth: true
                visible: root.powered
                Layout.preferredHeight: Math.max(1, Math.min(root.paired.length, MenuStyle.bluetoothListRows)) * MenuStyle.rowHeight + 2 * padding
                padding: 2
                clip: true

                Text {
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferFullHinting
                    anchors.centerIn: parent
                    visible: root.paired.length === 0
                    font.family: MenuStyle.bodyFont
                    font.pixelSize: MenuStyle.fontSize
                    color: MenuStyle.bevelDark
                    text: "No paired devices"
                }

                ListView {
                    id: pairedList
                    anchors.fill: parent
                    model: root.paired
                    delegate: RowLayout {
                        width: pairedList.width
                        spacing: MenuStyle.gap
                        MenuRow {
                            Layout.fillWidth: true
                            glyph: modelData.connected ? "" : ""
                            text: root.label(modelData)
                            marked: modelData.connected
                            trailing: root.status(modelData)
                            onClicked: modelData.connected ? modelData.disconnect() : modelData.connect()
                        }
                        // Trust: sunken = BlueZ may auto-reconnect it
                        BevelButton {
                            implicitWidth: MenuStyle.rowHeight
                            implicitHeight: MenuStyle.rowHeight
                            glyph: ""
                            checked: modelData.trusted
                            onClicked: modelData.trusted = !modelData.trusted
                        }
                        BevelButton {
                            implicitWidth: MenuStyle.rowHeight
                            implicitHeight: MenuStyle.rowHeight
                            glyph: ""
                            onClicked: root.forgetting = modelData
                        }
                    }
                }
            }

            Text {
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferFullHinting
                visible: root.powered && (root.adapter.discovering || root.available.length > 0)
                font.family: MenuStyle.titleFont
                font.pixelSize: MenuStyle.fontSize
                color: Config.colors.text
                text: root.adapter && root.adapter.discovering ? "Available (scanning...)" : "Available"
            }

            SunkenField {
                Layout.fillWidth: true
                visible: root.powered && (root.adapter.discovering || root.available.length > 0)
                Layout.preferredHeight: Math.max(1, Math.min(root.available.length, MenuStyle.bluetoothListRows)) * MenuStyle.rowHeight + 2 * padding
                padding: 2
                clip: true

                Text {
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferFullHinting
                    anchors.centerIn: parent
                    visible: root.available.length === 0
                    font.family: MenuStyle.bodyFont
                    font.pixelSize: MenuStyle.fontSize
                    color: MenuStyle.bevelDark
                    text: "Looking for devices..."
                }

                ListView {
                    id: availableList
                    anchors.fill: parent
                    model: root.available
                    delegate: MenuRow {
                        width: availableList.width
                        glyph: ""
                        text: root.label(modelData)
                        trailing: modelData.pairing ? "Cancel" : "Pair"
                        onClicked: modelData.pairing ? modelData.cancelPair() : root.pairDevice(modelData)
                    }
                }
            }
        }
    }

    function openMenu() {
        root.forgetting = null;
        root.visible = true;
    }

    function closeMenu() {
        root.forgetting = null;
        if (root.adapter && root.adapter.discovering)
            root.adapter.discovering = false;
        root.visible = false;
    }
}
