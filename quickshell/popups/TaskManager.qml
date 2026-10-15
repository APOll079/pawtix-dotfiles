import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import ".."

// Task Manager (Ctrl+Shift+Esc, SysMon popup > Task Manager, `qs ipc call taskmanager_<mon> toggle`),
// Win95 style, centred like the launcher. Tabs:
// - Apps: open windows (Hyprland). Switch to, End task (SIGTERM to the window's process), Kill (SIGKILL).
// - Processes: grouped by program (scripts/procs.py), sortable columns, filter, Mine / All, End task / Kill
//   for your own processes (others are listed only).
// - Performance: CPU, RAM, GPU and VRAM history graphs plus temperatures (SysMon.qml).
// Ending things always goes through a confirm row, and only ever signals the pids of the row you picked.
// The data helper runs only while the window is open.
PanelWindow {
    id: root

    required property var bar
    property int screenHeight: 0
    property var closeCallback: function () {}

    // An Overlay-layer panel (like the launcher), so it also works over fullscreen windows
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

    property string tab: "processes"     // apps | processes | performance
    property var sample: null            // the last procs.py line
    property var cpuHist: []
    property var memHist: []
    property var gpuHist: []
    property var vramHist: []

    property string sortKey: "cpu"       // name | cpu | mem | count
    property bool sortDesc: true
    property bool mineOnly: true
    property string selectedName: ""     // process group, kept across refreshes
    property int appIndex: 0
    property var confirm: null           // { text, pids, signal }

    readonly property var groups: {
        if (!root.sample)
            return [];
        const q = filter.text.trim().toLowerCase();
        const list = root.sample.groups.filter(g => (!root.mineOnly || g.mine) && (q === "" || g.name.toLowerCase().includes(q)));
        const k = root.sortKey, dir = root.sortDesc ? -1 : 1;
        return list.sort((a, b) => (k === "name" ? a.name.localeCompare(b.name) : a[k] - b[k]) * dir);
    }
    readonly property var selectedGroup: root.groups.find(g => g.name === root.selectedName) || null
    readonly property var apps: Hyprland.toplevels.values.filter(t => t.title !== "" && t.lastIpcObject && t.lastIpcObject.pid > 0)
    readonly property var selectedApp: root.apps[root.appIndex] || null

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

        // Keys for the tabs without a text field (Apps, Performance)
        Item {
            id: keys
            focus: true
            Keys.onEscapePressed: root.cancelOrClose()
            Keys.onUpPressed: root.appIndex = Math.max(0, root.appIndex - 1)
            Keys.onDownPressed: root.appIndex = Math.min(root.apps.length - 1, root.appIndex + 1)
            Keys.onReturnPressed: root.switchToApp()
            Keys.onTabPressed: event => {
                if (event.modifiers & Qt.ControlModifier)
                    root.cycleTab(1);
            }
        }

        PopupWindowFrame {
            windowTitle: "Task Manager"
            windowTitleIcon: ""

            ColumnLayout {
                anchors.fill: parent
                spacing: MenuStyle.pad

                RowLayout {
                    Layout.fillWidth: true
                    spacing: MenuStyle.gap
                    Repeater {
                        model: [
                            { key: "apps", text: "Apps", glyph: "" },
                            { key: "processes", text: "Processes", glyph: "" },
                            { key: "performance", text: "Performance", glyph: "" }
                        ]
                        BevelButton {
                            Layout.fillWidth: true
                            text: modelData.text
                            glyph: modelData.glyph
                            checked: root.tab === modelData.key
                            focusPolicy: Qt.NoFocus
                            onClicked: root.showTab(modelData.key)
                        }
                    }
                }

                // --- Apps ---
                SunkenField {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.tab === "apps"
                    padding: 2
                    clip: true
                    Text {
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferFullHinting
                        anchors.centerIn: parent
                        visible: root.apps.length === 0
                        font.family: MenuStyle.bodyFont
                        font.pixelSize: MenuStyle.fontSize
                        color: MenuStyle.bevelDark
                        text: "No open windows"
                    }
                    ListView {
                        id: appList
                        anchors.fill: parent
                        model: root.apps
                        currentIndex: root.appIndex
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                        delegate: MenuRow {
                            required property int index
                            required property var modelData
                            width: appList.width
                            selected: index === root.appIndex
                            iconSource: Quickshell.iconPath(String(modelData.lastIpcObject.class || "").toLowerCase(), true)
                            glyph: ""
                            text: modelData.title
                            subtext: (modelData.lastIpcObject.class || "") + "  ·  pid " + modelData.lastIpcObject.pid
                            trailing: modelData.workspace ? modelData.workspace.name.replace("special:", "*") : ""
                            onClicked: root.appIndex = index
                            onDoubleClicked: {
                                root.appIndex = index;
                                root.switchToApp();
                            }
                        }
                    }
                }

                // --- Processes ---
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.tab === "processes"
                    spacing: MenuStyle.gap
                    SearchBox {
                        id: filter
                        Layout.fillWidth: true
                        placeholder: "Filter programs"
                        onEscaped: root.cancelOrClose()
                        onKeyPressed: event => {
                            const i = root.groups.findIndex(g => g.name === root.selectedName);
                            if (event.key === Qt.Key_Down) {
                                root.selectAt(Math.min(root.groups.length - 1, i + 1));
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Up) {
                                root.selectAt(Math.max(0, i - 1));
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Delete) {
                                root.askEnd(false);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Tab && (event.modifiers & Qt.ControlModifier)) {
                                root.cycleTab(1);
                                event.accepted = true;
                            }
                        }
                    }
                    BevelButton {
                        text: root.mineOnly ? "Mine" : "All"
                        glyph: root.mineOnly ? "" : ""
                        focusPolicy: Qt.NoFocus
                        onClicked: root.mineOnly = !root.mineOnly
                    }
                }

                // Column headers: click to sort, click again to flip
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.tab === "processes"
                    spacing: MenuStyle.gap
                    Repeater {
                        model: [
                            { key: "name", text: "Program", wide: true },
                            { key: "cpu", text: "CPU", wide: false },
                            { key: "mem", text: "Memory", wide: false },
                            { key: "count", text: "Procs", wide: false }
                        ]
                        BevelButton {
                            Layout.fillWidth: modelData.wide
                            Layout.preferredWidth: modelData.wide ? -1 : MenuStyle.taskColumnWidth
                            text: modelData.text + (root.sortKey === modelData.key ? (root.sortDesc ? " ▾" : " ▴") : "")
                            checked: root.sortKey === modelData.key
                            focusPolicy: Qt.NoFocus
                            onClicked: {
                                if (root.sortKey === modelData.key)
                                    root.sortDesc = !root.sortDesc;
                                else {
                                    root.sortKey = modelData.key;
                                    root.sortDesc = modelData.key !== "name";
                                }
                            }
                        }
                    }
                }

                SunkenField {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.tab === "processes"
                    padding: 2
                    clip: true
                    Text {
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferFullHinting
                        anchors.centerIn: parent
                        visible: root.groups.length === 0
                        font.family: MenuStyle.bodyFont
                        font.pixelSize: MenuStyle.fontSize
                        color: MenuStyle.bevelDark
                        text: root.sample ? "No matches" : "Reading processes..."
                    }
                    ListView {
                        id: procList
                        anchors.fill: parent
                        model: root.groups
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        delegate: Rectangle {
                            id: procRow
                            required property int index
                            required property var modelData
                            readonly property bool sel: modelData.name === root.selectedName
                            width: procList.width
                            height: MenuStyle.rowHeight
                            color: sel ? MenuStyle.selectBar : (rowMouse.containsMouse ? Config.colors.highlight : "transparent")
                            readonly property color ink: sel ? MenuStyle.selectText : (modelData.mine ? Config.colors.text : Config.colors.shadow)
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: MenuStyle.pad
                                anchors.rightMargin: MenuStyle.pad
                                spacing: MenuStyle.gap
                                Text {
                                    renderType: Text.NativeRendering
                                    font.hintingPreference: Font.PreferFullHinting
                                    textFormat: Text.PlainText
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    font.family: MenuStyle.bodyFont
                                    font.pixelSize: MenuStyle.fontSize
                                    color: procRow.ink
                                    text: procRow.modelData.name
                                }
                                Repeater {
                                    model: [procRow.modelData.cpu.toFixed(1) + "%", root.bytes(procRow.modelData.mem), String(procRow.modelData.count)]
                                    Text {
                                        renderType: Text.NativeRendering
                                        font.hintingPreference: Font.PreferFullHinting
                                        Layout.preferredWidth: MenuStyle.taskColumnWidth
                                        horizontalAlignment: Text.AlignRight
                                        font.family: MenuStyle.bodyFont
                                        font.pixelSize: MenuStyle.fontSize
                                        color: procRow.ink
                                        text: modelData
                                    }
                                }
                            }
                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.selectedName = procRow.modelData.name
                            }
                        }
                        ScrollIndicator.vertical: ScrollIndicator {
                            active: procList.moving
                        }
                    }
                }

                // --- Performance ---
                GridLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.tab === "performance"
                    columns: 2
                    columnSpacing: MenuStyle.pad
                    rowSpacing: MenuStyle.pad
                    Graph {
                        title: "CPU"
                        value: root.sample ? root.sample.cpu.toFixed(0) + "%  ·  " + SysMon.tempText(SysMon.cpuTemp) : ""
                        history: root.cpuHist
                    }
                    Graph {
                        title: "Memory"
                        value: root.sample ? root.bytes(root.sample.mem.used) + " / " + root.bytes(root.sample.mem.total) : ""
                        history: root.memHist
                    }
                    Graph {
                        title: "GPU"
                        value: root.sample && root.sample.gpu ? root.sample.gpu.busy + "%  ·  " + SysMon.tempText(SysMon.gpuJunction) : "no data"
                        history: root.gpuHist
                    }
                    Graph {
                        title: "Video memory"
                        value: root.sample && root.sample.gpu ? root.bytes(root.sample.gpu.vramUsed) + " / " + root.bytes(root.sample.gpu.vramTotal) : "no data"
                        history: root.vramHist
                    }
                }

                // --- Actions / confirm ---
                RowLayout {
                    Layout.fillWidth: true
                    spacing: MenuStyle.gap
                    Text {
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferFullHinting
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        font.family: MenuStyle.bodyFont
                        font.pixelSize: MenuStyle.fontSize
                        color: root.confirm ? Config.colors.text : MenuStyle.bevelDark
                        text: root.confirm ? root.confirm.text : root.statusText()
                    }
                    BevelButton {
                        visible: root.confirm !== null
                        text: "Yes"
                        focusPolicy: Qt.NoFocus
                        onClicked: root.doConfirm()
                    }
                    BevelButton {
                        visible: root.confirm !== null
                        text: "No"
                        focusPolicy: Qt.NoFocus
                        onClicked: root.confirm = null
                    }
                    BevelButton {
                        visible: !root.confirm && root.tab === "apps"
                        text: "Switch to"
                        enabled: root.selectedApp !== null
                        focusPolicy: Qt.NoFocus
                        onClicked: root.switchToApp()
                    }
                    BevelButton {
                        visible: !root.confirm && root.tab !== "performance"
                        text: "End task"
                        enabled: root.tab === "apps" ? root.selectedApp !== null : (root.selectedGroup !== null && root.selectedGroup.mine)
                        focusPolicy: Qt.NoFocus
                        onClicked: root.askEnd(false)
                    }
                    BevelButton {
                        visible: !root.confirm && root.tab !== "performance"
                        text: "Kill"
                        enabled: root.tab === "apps" ? root.selectedApp !== null : (root.selectedGroup !== null && root.selectedGroup.mine)
                        focusPolicy: Qt.NoFocus
                        onClicked: root.askEnd(true)
                    }
                }
            }
        }
    }

    // A labelled history graph: one solid bar per sample on the dithered track, newest on the right
    component Graph: ColumnLayout {
        id: graph
        property string title: ""
        property string value: ""
        property var history: []
        Layout.fillWidth: true
        Layout.fillHeight: true
        // Equal columns and rows, whatever the value text says
        Layout.preferredWidth: 1
        Layout.preferredHeight: 1
        spacing: MenuStyle.gap
        RowLayout {
            Layout.fillWidth: true
            Text {
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferFullHinting
                Layout.fillWidth: true
                font.family: MenuStyle.titleFont
                font.pixelSize: MenuStyle.fontSize
                font.bold: true
                color: Config.colors.text
                text: graph.title
            }
            Text {
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferFullHinting
                font.family: MenuStyle.bodyFont
                font.pixelSize: MenuStyle.fontSize
                color: Config.colors.text
                text: graph.value
            }
        }
        SunkenField {
            Layout.fillWidth: true
            Layout.fillHeight: true
            padding: 2
            Dither {
                anchors.fill: parent
                color1: Config.colors.base
                color2: Config.colors.highlight
            }
            Row {
                id: bars
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: parent.height
                spacing: 1
                readonly property real barWidth: Math.max(1, Math.floor((parent.width - (MenuStyle.taskHistory - 1)) / MenuStyle.taskHistory))
                Repeater {
                    model: graph.history
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: bars.barWidth
                        height: Math.round(bars.height * Math.max(0, Math.min(1, modelData)))
                        color: MenuStyle.selectBar
                    }
                }
            }
        }
    }

    // --- data ---

    Process {
        id: feed
        command: ["python3", "-I", Quickshell.shellDir + "/scripts/procs.py", "--interval", String(MenuStyle.taskInterval / 1000)]
        running: root.visible
        stdout: SplitParser {
            onRead: data => root.take(data)
        }
    }

    function take(line) {
        let s = null;
        try {
            s = JSON.parse(line);
        } catch (e) {
            return;
        }
        root.sample = s;
        const push = (arr, v) => arr.concat([v]).slice(-MenuStyle.taskHistory);
        root.cpuHist = push(root.cpuHist, s.cpu / 100);
        root.memHist = push(root.memHist, s.mem.total > 0 ? s.mem.used / s.mem.total : 0);
        root.gpuHist = push(root.gpuHist, s.gpu ? s.gpu.busy / 100 : 0);
        root.vramHist = push(root.vramHist, s.gpu && s.gpu.vramTotal > 0 ? s.gpu.vramUsed / s.gpu.vramTotal : 0);
        if (root.selectedName === "" && root.groups.length > 0)
            root.selectedName = root.groups[0].name;
    }

    function bytes(b) {
        if (b >= 1073741824)
            return (b / 1073741824).toFixed(1) + " GB";
        if (b >= 1048576)
            return Math.round(b / 1048576) + " MB";
        return Math.round(b / 1024) + " KB";
    }

    function statusText() {
        if (!root.sample)
            return "";
        const memPct = root.sample.mem.total > 0 ? Math.round(100 * root.sample.mem.used / root.sample.mem.total) : 0;
        return root.sample.count + " processes  ·  CPU " + Math.round(root.sample.cpu) + "%  ·  RAM " + memPct + "%";
    }

    function selectAt(i) {
        const g = root.groups[i];
        if (g) {
            root.selectedName = g.name;
            procList.positionViewAtIndex(i, ListView.Contain);
        }
    }

    // --- actions (only ever signal the pids of the row you picked) ---

    function switchToApp() {
        const t = root.selectedApp;
        if (!t)
            return;
        Hyprland.dispatch("hl.dsp.focus({ window = \"address:0x" + t.address + "\" })");
        root.closeCallback();
    }

    function askEnd(force) {
        if (root.tab === "apps") {
            const t = root.selectedApp;
            if (!t)
                return;
            root.confirm = { text: (force ? "Kill " : "End ") + t.title + "?", pids: [t.lastIpcObject.pid], signal: force ? "KILL" : "TERM" };
        } else if (root.tab === "processes") {
            const g = root.selectedGroup;
            if (!g || !g.mine)
                return;
            root.confirm = { text: (force ? "Kill " : "End ") + g.name + (g.count > 1 ? " (" + g.count + " processes)" : "") + "?", pids: g.pids, signal: force ? "KILL" : "TERM" };
        }
    }

    function doConfirm() {
        const c = root.confirm;
        root.confirm = null;
        if (!c || c.pids.length === 0)
            return;
        Quickshell.execDetached(["kill", "-" + c.signal].concat(c.pids.map(p => String(p))));
    }

    function cancelOrClose() {
        if (root.confirm)
            root.confirm = null;
        else
            root.closeCallback();
    }

    function showTab(key) {
        root.tab = key;
        root.confirm = null;
        if (key === "processes")
            filter.focusInput();
        else
            keys.forceActiveFocus();
    }

    function cycleTab(d) {
        const tabs = ["apps", "processes", "performance"];
        root.showTab(tabs[(tabs.indexOf(root.tab) + d + tabs.length) % tabs.length]);
    }

    onVisibleChanged: {
        SysMon.detailed = visible;
        if (!visible) {
            root.sample = null;
            root.cpuHist = [];
            root.memHist = [];
            root.gpuHist = [];
            root.vramHist = [];
        }
    }

    function openMenu() {
        root.confirm = null;
        filter.text = "";
        Hyprland.refreshToplevels();
        root.visible = true;
        root.showTab(root.tab);
    }

    function closeMenu() {
        root.visible = false;
    }
}
