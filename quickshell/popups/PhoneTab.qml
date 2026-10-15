import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import ".."

// Phone tab of the side panel (Super+N > Phone): KDE Connect through `kdeconnect-cli`. Lists the phones
// kdeconnectd knows, with Pair / Unpair, Ping, Send clipboard and Send file (a typed path; there is
// no file picker). Phone notifications arrive on their own through the notification daemon, and
// clipboard sync is a per-device plugin switch in the phone app.
// `kdeconnect-cli -l` is expected as "- Name: id (paired and reachable)" per line.
// `active` is true while this tab is showing.
ColumnLayout {
    id: root
    property bool active: false
    spacing: MenuStyle.pad

    property var devices: []               // { id, name, paired, reachable }
    property string selectedId: ""
    property string status: ""

    readonly property var current: root.devices.find(d => d.id === root.selectedId) || root.devices[0] || null
    readonly property bool busy: cmdProc.running

    onActiveChanged: {
        if (active) {
            root.status = "";
            root.refresh();
        }
    }

    SunkenField {
        Layout.fillWidth: true
        implicitHeight: Math.max(MenuStyle.rowHeight * 3, deviceColumn.implicitHeight + 4)
        padding: 2

        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferFullHinting
            anchors.centerIn: parent
            width: parent.width - 2 * MenuStyle.pad
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            visible: root.devices.length === 0
            font.family: MenuStyle.bodyFont
            font.pixelSize: MenuStyle.fontSize
            color: MenuStyle.bevelDark
            text: root.status !== "" ? root.status : "No phone found. Install KDE Connect on it and pair from there."
        }

        ColumnLayout {
            id: deviceColumn
            width: parent.width
            spacing: 0
            Repeater {
                model: root.devices
                MenuRow {
                    Layout.fillWidth: true
                    selected: root.current && modelData.id === root.current.id
                    text: modelData.name
                    trailing: modelData.paired ? (modelData.reachable ? "paired" : "offline") : (modelData.reachable ? "not paired" : "offline")
                    glyph: "\ue324"
                    onClicked: root.selectedId = modelData.id
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: MenuStyle.gap
        BevelButton {
            Layout.fillWidth: true
            text: root.current && root.current.paired ? "Unpair" : "Pair"
            glyph: "\ue157"
            enabled: root.current !== null && !root.busy
            focusPolicy: Qt.NoFocus
            onClicked: root.run([root.current.paired ? "--unpair" : "--pair"], root.current.paired ? "Unpaired" : "Pairing request sent: accept it on the phone")
        }
        BevelButton {
            Layout.fillWidth: true
            text: "Ping"
            glyph: "\ue0b7"
            enabled: root.usable && !root.busy
            focusPolicy: Qt.NoFocus
            onClicked: root.run(["--ping"], "Pinged")
        }
    }
    BevelButton {
        Layout.fillWidth: true
        text: "Send clipboard"
        glyph: "\ue14f"
        enabled: root.usable && !root.busy
        focusPolicy: Qt.NoFocus
        onClicked: {
            clipProc.deviceId = root.current.id;
            clipProc.running = true;
        }
    }

    SunkenField {
        Layout.fillWidth: true
        implicitHeight: MenuStyle.searchHeight
        padding: 4
        TextField {
            id: pathInput
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferFullHinting
            anchors.fill: parent
            placeholderText: "File path, e.g. ~/shot.png"
            placeholderTextColor: MenuStyle.bevelDark
            font.family: MenuStyle.bodyFont
            font.pixelSize: MenuStyle.fontSize
            color: Config.colors.text
            selectionColor: Config.colors.shadow
            padding: 0
            verticalAlignment: Text.AlignVCenter
            background: Item {}
            Keys.onReturnPressed: root.sendFile()
            Keys.onEnterPressed: root.sendFile()
        }
    }
    BevelButton {
        Layout.fillWidth: true
        text: "Send file"
        glyph: "\ue2c6"
        enabled: root.usable && !root.busy && pathInput.text.trim() !== ""
        focusPolicy: Qt.NoFocus
        onClicked: root.sendFile()
    }

    Text {
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferFullHinting
        Layout.fillWidth: true
        elide: Text.ElideRight
        visible: root.devices.length > 0
        font.family: MenuStyle.bodyFont
        font.pixelSize: MenuStyle.fontSize
        color: MenuStyle.bevelDark
        text: root.busy ? "Working..." : root.status
    }

    // Paired and reachable: the actions that need the phone to answer
    readonly property bool usable: root.current !== null && root.current.paired && root.current.reachable

    function parse(text) {
        const out = [];
        for (const line of text.split("\n")) {
            const m = line.match(/^- (.+): (\S+) \((.*)\)\s*$/);
            if (m)
                out.push({ id: m[2], name: m[1], paired: /paired/.test(m[3]) && !/not paired|unpaired/.test(m[3]), reachable: /reachable/.test(m[3]) && !/unreachable/.test(m[3]) });
        }
        return out;
    }

    function refresh() {
        if (!listProc.running)
            listProc.running = true;
    }

    // Run a kdeconnect-cli action on the selected phone; `done` is the message on success
    function run(args, done) {
        if (!root.current || !/^[A-Za-z0-9_]+$/.test(root.current.id))
            return;
        cmdProc.done = done;
        cmdProc.command = ["kdeconnect-cli", "-d", root.current.id].concat(args);
        cmdProc.running = true;
    }

    function sendFile() {
        let p = pathInput.text.trim();
        if (p === "" || !root.usable || root.busy)
            return;
        if (p.startsWith("~/"))
            p = Quickshell.env("HOME") + p.slice(1);
        root.run(["--share", p], "Sent " + p.split("/").pop());
    }

    Process {
        id: listProc
        command: ["kdeconnect-cli", "-l"]
        stdout: StdioCollector {
            onStreamFinished: root.devices = root.parse(text)
        }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim() !== "") root.status = text.trim()
        }
    }

    Process {
        id: cmdProc
        property string done: ""
        stderr: StdioCollector {
            id: cmdErr
        }
        onExited: code => {
            root.status = code === 0 ? cmdProc.done : (cmdErr.text.trim() || "Failed (exit " + code + ")");
            root.refresh();
        }
    }

    // Clipboard text to the phone: read it with wl-paste, then share it as text
    Process {
        id: clipProc
        property string deviceId: ""
        command: ["sh", "-c", "wl-paste -n --type text 2>/dev/null | kdeconnect-cli -d \"$1\" --share-text \"$(cat)\"", "sh", clipProc.deviceId]
        onExited: code => root.status = code === 0 ? "Clipboard sent" : "Could not send the clipboard (is it text?)"
    }
}
