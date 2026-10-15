import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import ".."

// dinit services (Start > Services, `qs ipc call services_<mon> toggle`), centred like the Games
// menu. Lists `dinitctl list` with state; Start / Stop / Restart act on the selected service.
// Two scopes: "User" (your own dinit instance: pipewire, wireplumber, ...) runs straight away;
// "System" (the machine's dinit) runs `doas dinitctl ...` in a terminal, so the password prompt is
// the real one and nothing is stored. The panel refreshes after each action.
// Type to filter, Up / Down select, Escape clears the search, then closes.
// `dinitctl list` is expected as "[{+}     ] name (pid: 123)" per line; if your dinit prints it
// differently, parse() below is the one place to adjust.
PanelWindow {
    id: root
    // The bar window this popup hangs off (set by Bar.qml)
    required property var bar

    property int screenHeight: 0
    property var closeCallback: function () {}

    property var services: []              // { name, state: running|stopped|other, failed, info }
    property string filter: "all"          // all | running | stopped
    property string scope: "user"          // user | system
    property string error: ""
    property int cursor: 0

    readonly property var shown: {
        const q = searchInput.text.trim().toLowerCase();
        return root.services.filter(s => (root.filter === "all" || s.state === root.filter) && (q === "" || s.name.toLowerCase().includes(q)));
    }
    readonly property var current: root.shown[root.cursor] || null
    readonly property bool busy: actProc.running

    onShownChanged: root.cursor = Math.max(0, Math.min(root.cursor, root.shown.length - 1))

    // An Overlay-layer panel, not a popup of the bar: the bar sits below fullscreen windows, so a
    // popup over a fullscreen video showed but its clicks went to the video
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    margins.top: MenuStyle.barHeight
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-menu"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    visible: false
    color: "transparent"

    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: root.closeCallback()
    }

    Item {
        id: frame
        width: MenuStyle.launcherWidth
        height: MenuStyle.launcherHeight
        x: (root.width - width) / 2
        y: root.screenHeight / 2 - height / 2 - MenuStyle.barHeight

        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        PopupWindowFrame {
            windowTitle: "Services"
            windowTitleIcon: ""

            ColumnLayout {
                anchors.fill: parent
                spacing: MenuStyle.pad

                SearchBox {
                    id: searchInput
                    Layout.fillWidth: true
                    placeholder: "Filter services"
                    onEscaped: root.closeCallback()
                    onKeyPressed: event => {
                        if (event.key === Qt.Key_Down) {
                            root.move(1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up) {
                            root.move(-1);
                            event.accepted = true;
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: MenuStyle.gap
                    Repeater {
                        model: [
                            { key: "all", text: "All" },
                            { key: "running", text: "Running" },
                            { key: "stopped", text: "Stopped" }
                        ]
                        BevelButton {
                            text: modelData.text
                            checked: root.filter === modelData.key
                            focusPolicy: Qt.NoFocus
                            onClicked: {
                                root.filter = modelData.key;
                                searchInput.focusInput();
                            }
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Repeater {
                        model: [
                            { key: "user", text: "User" },
                            { key: "system", text: "System" }
                        ]
                        BevelButton {
                            text: modelData.text
                            checked: root.scope === modelData.key
                            focusPolicy: Qt.NoFocus
                            onClicked: {
                                root.scope = modelData.key;
                                root.services = [];
                                root.error = "";
                                root.refresh();
                                searchInput.focusInput();
                            }
                        }
                    }
                    BevelButton {
                        text: "Refresh"
                        glyph: ""
                        focusPolicy: Qt.NoFocus
                        onClicked: {
                            root.refresh();
                            searchInput.focusInput();
                        }
                    }
                }

                SunkenField {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    padding: 2
                    clip: true

                    Text {
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferFullHinting
                        anchors.centerIn: parent
                        width: parent.width - 2 * MenuStyle.pad
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        visible: root.shown.length === 0
                        font.family: MenuStyle.bodyFont
                        font.pixelSize: MenuStyle.fontSize
                        color: MenuStyle.bevelDark
                        text: root.error !== "" ? root.error : (root.services.length === 0 ? "No services listed" : "No matches")
                    }

                    ListView {
                        id: list
                        anchors.fill: parent
                        model: root.shown
                        currentIndex: root.cursor
                        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true
                        delegate: MenuRow {
                            required property int index
                            required property var modelData
                            width: list.width
                            selected: index === root.cursor
                            text: modelData.name
                            subtext: modelData.info
                            trailing: modelData.failed ? "failed" : modelData.state
                            glyph: modelData.failed ? "" : modelData.state === "running" ? "" : ""
                            onClicked: {
                                root.cursor = index;
                                searchInput.focusInput();
                            }
                        }
                        ScrollIndicator.vertical: ScrollIndicator {
                            active: list.moving
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: MenuStyle.gap
                    Text {
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferFullHinting
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        font.family: MenuStyle.bodyFont
                        font.pixelSize: MenuStyle.fontSize
                        color: MenuStyle.bevelDark
                        text: root.busy ? "Working..." : (root.current ? root.current.name + (root.scope === "system" ? " (asks for doas in a terminal)" : "") : "")
                    }
                    BevelButton {
                        text: "Start"
                        glyph: ""
                        enabled: root.current !== null && !root.busy
                        focusPolicy: Qt.NoFocus
                        onClicked: root.act("start")
                    }
                    BevelButton {
                        text: "Stop"
                        glyph: ""
                        enabled: root.current !== null && !root.busy
                        focusPolicy: Qt.NoFocus
                        onClicked: root.act("stop")
                    }
                    BevelButton {
                        text: "Restart"
                        glyph: ""
                        enabled: root.current !== null && !root.busy
                        focusPolicy: Qt.NoFocus
                        onClicked: root.act("restart")
                    }
                }
            }
        }
    }

    // --- data ---

    function move(d) {
        if (root.shown.length === 0)
            return;
        root.cursor = Math.max(0, Math.min(root.shown.length - 1, root.cursor + d));
    }

    function parse(text) {
        const out = [];
        for (const line of text.split("\n")) {
            if (line.length < 11 || line[0] !== "[")
                continue;
            const flags = line.slice(1, 9);
            const rest = line.slice(10).trim();
            const sp = rest.search(/\s/);
            const name = sp < 0 ? rest : rest.slice(0, sp);
            const info = sp < 0 ? "" : rest.slice(sp).trim().replace(/^\(|\)$/g, "");
            if (name === "")
                continue;
            out.push({
                name: name,
                state: flags.includes("+") ? "running" : flags.includes("-") ? "stopped" : "other",
                failed: /fail|exit status/i.test(info),
                info: info
            });
        }
        return out.sort((a, b) => a.name.localeCompare(b.name));
    }

    function refresh() {
        if (!listProc.running)
            listProc.running = true;
    }

    // Start / Stop / Restart. User services run directly; system services open a terminal where
    // doas asks for the password. That terminal stays open until you close it, so it is detached
    // (a second action meanwhile still works) and the list refreshes a little later.
    function act(verb) {
        const s = root.current;
        if (!s || !/^[A-Za-z0-9@._:+-]+$/.test(s.name))
            return;
        if (root.scope === "system") {
            Quickshell.execDetached([Config.settings.execCommands.terminal, "fish", "-c", "doas dinitctl --system " + verb + " " + s.name + "; echo; read -P 'Press Enter to close'"]);
            refreshLater.restart();
        } else {
            actProc.command = ["dinitctl", "--user", verb, s.name];
            actProc.running = true;
        }
    }

    Timer {
        id: refreshLater
        interval: MenuStyle.servicesRefreshDelay
        onTriggered: root.refresh()
    }

    Process {
        id: listProc
        command: ["dinitctl", root.scope === "system" ? "--system" : "--user", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.services = root.parse(text);
                if (root.services.length > 0)
                    root.error = "";
            }
        }
        stderr: StdioCollector {
            onStreamFinished: root.error = text.trim() !== "" ? text.trim() : ""
        }
        onExited: code => {
            if (code !== 0 && root.error === "")
                root.error = "dinitctl list failed (exit " + code + ")";
        }
    }

    Process {
        id: actProc
        stderr: StdioCollector {
            id: actErr
        }
        onExited: code => {
            if (code !== 0 && actErr.text.trim() !== "")
                root.error = actErr.text.trim();
            root.refresh();
        }
    }

    function openMenu() {
        searchInput.text = "";
        root.filter = "all";
        root.cursor = 0;
        root.refresh();
        root.visible = true;
        searchInput.focusInput();
    }

    function closeMenu() {
        root.visible = false;
    }
}
