import QtQuick
import QtQuick.Controls.Basic
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth

Item {
    id: root

    property int currentPopup: Config.SystemPopup.None
    property var toggleMenu: function(menu, popup, item) {}
    property var bluetoothMenuRef: null
    property var sysMonMenuRef: null


    property string netText: "OFF"
    property string netIconVal: "\ue63d"
    // Bluetooth from BlueZ directly: OFF, ON, or ON with the connected icon
    readonly property bool btOn: Bluetooth.defaultAdapter !== null && Bluetooth.defaultAdapter.enabled
    readonly property bool btConnected: Bluetooth.devices.values.some(d => d.connected)
    readonly property string btText: btOn ? "ON" : "OFF"
    readonly property string btIconVal: !btOn ? "\ue1a9" : (btConnected ? "\ue1a8" : "\ue1a7")

    implicitWidth: (privacyRow.width > 0 ? privacyRow.width + MenuStyle.gap : 0) + caffeineBtn.width + MenuStyle.gap + sysBtn.width + MenuStyle.gap + ethLabel.width + MenuStyle.gap + btBtn.width
    implicitHeight: MenuStyle.barButtonHeight

    // Privacy: mic / screen-share icons in the urgent colour, only while something records
    Row {
        id: privacyRow
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: MenuStyle.gap
        BarButton {
            visible: Privacy.mic
            anchors.verticalCenter: parent.verticalCenter
            interactive: false
            tucked: true
            urgent: true
            iconFontValue: "\ue029"
        }
        BarButton {
            visible: Privacy.screen
            anchors.verticalCenter: parent.verticalCenter
            interactive: false
            tucked: true
            urgent: true
            iconFontValue: "\ue0e2"
        }
    }

    // Caffeine: sunken while on (idle dim/lock/screens-off paused)
    BarButton {
        id: caffeineBtn
        anchors.left: privacyRow.width > 0 ? privacyRow.right : parent.left
        anchors.leftMargin: privacyRow.width > 0 ? MenuStyle.gap : 0
        anchors.verticalCenter: parent.verticalCenter
        iconFontValue: "\uefef"
        isToggled: Idle.caffeine
        onClicked: Idle.caffeine = !Idle.caffeine
    }

    // CPU load, CPU temperature and RAM use; click opens the full sysmon popup (no hover-open)
    BarButton {
        id: sysBtn
        anchors.left: caffeineBtn.right
        anchors.leftMargin: MenuStyle.gap
        anchors.verticalCenter: parent.verticalCenter
        // No icon: the CPU/RAM labels say what it is (BarButton defaults to the Start grid icon)
        iconFontValue: ""
        label: "CPU " + Math.round(SysMon.cpuLoad * 100) + "% " + SysMon.tempText(SysMon.cpuTemp) + " RAM " + SysMon.memPercent + "%"
        minWidth: MenuStyle.barSysMonWidth
        isToggled: root.currentPopup === Config.SystemPopup.SysMonMenu
        onClicked: root.toggleMenu(root.sysMonMenuRef, Config.SystemPopup.SysMonMenu, sysBtn)
    }

    // Network: a status indicator (the desktop is wired), not a button
    BarButton {
        id: ethLabel
        anchors.left: sysBtn.right
        anchors.leftMargin: MenuStyle.gap
        anchors.verticalCenter: parent.verticalCenter
        iconFontValue: root.netIconVal
        toggledIconFontValue: ""
        label: root.netText
        // Its own quiet box (no hover, dim text) so it sits in rhythm with its boxed neighbours
        interactive: false
        dim: true
    }

    // Bluetooth: a normal bar button next to the ETH label
    BarButton {
        id: btBtn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        iconFontValue: root.btIconVal
        toggledIconFontValue: ""
        label: root.btText
        minWidth: MenuStyle.barLabelButtonWidth
        isToggled: root.currentPopup === Config.SystemPopup.BluetoothMenu
        onClicked: root.toggleMenu(root.bluetoothMenuRef, Config.SystemPopup.BluetoothMenu, btBtn)
    }

    Process {
        id: netProc
        command: ["nmcli", "-t", "-f", "STATE", "g"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var state = text.trim()
                // Wired desktop: connected means Ethernet
                if (state === "connected") {
                    root.netIconVal = "\ue627"
                    root.netText = "ETH"
                } else {
                    root.netIconVal = "\ue63d"
                    root.netText = "OFF"
                }
            }
        }
    }

    // Wired desktop: the network state barely changes, so poll it slowly
    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: netProc.running = true
    }
}
