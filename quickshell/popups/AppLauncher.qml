import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import Quickshell.Hyprland
import Quickshell.Io
import ".."
import "../utils" as Utils

// Launcher (Super+D). One result list fed by providers:
// - apps: fuzzy search, usage-ranked, pinned first when empty, category filter row
// - calculator: "2+2*3", "10 km to mi" -> top row, Enter copies the result
// - session: type lock / logout / reboot / suspend / shutdown (or a custom action's name)
// - windows: start with "," to search open windows
// - clipboard: Super+V opens the cliphist history; Enter copies the entry back
// Tabs along the top switch between Apps, Games (cover grid, GamesView.qml, shared with the
// standalone Games menu) and Clipboard; Ctrl+Tab cycles them.
// Right-click an app (or Shift+Enter) for its options: launch, pin/unpin, move pinned up/down, hide
// (the "Hidden (n)" chip lists hidden apps) and uninstall (owner found by scripts/app-owner.sh, then
// `yay -Rns` / `flatpak uninstall` in a terminal after a confirm).
PanelWindow {
    id: root
    // The bar window this popup hangs off (set by Bar.qml)
    required property var bar

    property int screenHeight: 0
    property var closeCallback: function () {}

    property string mode: "apps"          // apps | windows | games | clipboard
    property string category: "all"
    property var results: []
    property var optionsFor: null         // DesktopEntry whose options are showing
    property string confirmKey: ""        // session action waiting for a second Enter
    property var uninstallFor: null       // { name, kind, pkg }: uninstall waiting for its confirm
    readonly property int hiddenCount: Array.from(Utils.AppSearch.list).filter(e => LauncherState.isHidden(e.id)).length

    property var clipLines: []

    // Category filter: glyph + freedesktop categories it matches
    readonly property var categories: [
        { key: "all", glyph: "", cats: [] },
        { key: "web", glyph: "", cats: ["Network", "WebBrowser", "Email", "Chat"] },
        { key: "media", glyph: "", cats: ["AudioVideo", "Audio", "Video", "Music", "Player"] },
        { key: "dev", glyph: "", cats: ["Development", "IDE"] },
        { key: "graphics", glyph: "", cats: ["Graphics", "Photography"] },
        { key: "office", glyph: "", cats: ["Office", "TextEditor"] },
        { key: "system", glyph: "", cats: ["System", "Settings", "Monitor"] },
        { key: "utility", glyph: "", cats: ["Utility", "Accessories"] }
    ]

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

    // Clicks outside the frame close the launcher (behind the frame, so it never eats its clicks)
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: root.closeCallback()
    }

    // The frame sits in the middle of the screen. The popup itself starts under the bar and is
    // as wide as the screen, so y subtracts the bar. Every tab has the same size.
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
            windowTitle: root.mode === "windows" ? "Windows" : root.mode === "clipboard" ? "Clipboard" : root.mode === "games" ? "Games" : "Search"
            windowTitleIcon: root.mode === "windows" ? "" : root.mode === "clipboard" ? "" : ""

            ColumnLayout {
                anchors.fill: parent
                spacing: MenuStyle.pad

                // Tabs
                RowLayout {
                    Layout.fillWidth: true
                    spacing: MenuStyle.gap
                    Repeater {
                        model: root.tabs
                        BevelButton {
                            Layout.fillWidth: true
                            text: modelData.text
                            glyph: modelData.glyph
                            checked: root.tabOf(root.mode) === modelData.key
                            focusPolicy: Qt.NoFocus
                            onClicked: {
                                if (root.tabOf(root.mode) !== modelData.key)
                                    root.open(modelData.key);
                                searchInput.focusInput();
                            }
                        }
                    }
                }

                SearchBox {
                    id: searchInput
                    Layout.fillWidth: true
                    visible: !(root.mode === "games" && gamesView.addMode)
                    fontSize: MenuStyle.searchFontSize
                    onTextChanged: {
                        root.confirmKey = "";
                        root.rebuild();
                    }
                    Component.onCompleted: searchInput.focusInput()
                    onKeyPressed: event => root.handleKey(event)
                }

                // Category filter (apps only)
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.mode === "apps" && !root.optionsFor && !searchInput.text.startsWith(",")
                    spacing: MenuStyle.gap
                    Repeater {
                        model: root.categories
                        BevelButton {
                            Layout.fillWidth: true
                            glyph: modelData.glyph
                            checked: root.category === modelData.key
                            focusPolicy: Qt.NoFocus
                            onClicked: {
                                root.category = modelData.key;
                                root.rebuild();
                                searchInput.focusInput();
                            }
                        }
                    }
                    BevelButton {
                        visible: root.hiddenCount > 0
                        text: "Hidden (" + root.hiddenCount + ")"
                        checked: root.category === "hidden"
                        focusPolicy: Qt.NoFocus
                        onClicked: {
                            root.category = root.category === "hidden" ? "all" : "hidden";
                            root.rebuild();
                            searchInput.focusInput();
                        }
                    }
                }

                // Games tab: the cover grid
                GamesView {
                    id: gamesView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.mode === "games"
                    query: root.mode === "games" ? searchInput.text.trim() : ""
                    closeCallback: root.closeCallback
                    onFocusSearch: searchInput.focusInput()
                }

                // Results; in clipboard mode a preview pane sits on the left of the list
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.mode !== "games"
                    spacing: MenuStyle.pad

                    SunkenField {
                        id: preview
                        visible: root.mode === "clipboard"
                        Layout.fillHeight: true
                        Layout.preferredWidth: parent.width * MenuStyle.clipPreviewFraction
                        padding: MenuStyle.pad
                        clip: true

                        Image {
                            anchors.fill: parent
                            visible: root.previewImage !== ""
                            source: root.previewImage === "" ? "" : "file://" + root.previewImage
                            sourceSize.width: preview.width * 2
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            cache: false
                        }

                        Flickable {
                            anchors.fill: parent
                            visible: root.previewImage === ""
                            contentHeight: previewLabel.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds
                            clip: true
                            Text {
                                id: previewLabel
                                renderType: Text.NativeRendering
                                font.hintingPreference: Font.PreferFullHinting
                                width: parent.width
                                wrapMode: Text.WrapAnywhere
                                font.family: MenuStyle.bodyFont
                                font.pixelSize: MenuStyle.fontSize
                                color: root.previewText === "" ? MenuStyle.bevelDark : Config.colors.text
                                text: root.previewText === "" ? "Nothing selected" : root.previewText
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
                            visible: root.results.length === 0
                            font.family: MenuStyle.bodyFont
                            font.pixelSize: MenuStyle.fontSize
                            color: MenuStyle.bevelDark
                            text: root.mode === "clipboard" ? "Clipboard history is empty" : "No matches"
                        }

                        ListView {
                            id: appsView
                            anchors.fill: parent
                            model: root.results
                            currentIndex: 0
                            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                            flickableDirection: Flickable.VerticalFlick
                            boundsBehavior: Flickable.DragOverBounds
                            maximumFlickVelocity: 3500
                            clip: true

                            delegate: MenuRow {
                                width: appsView.width
                                selected: index === appsView.currentIndex
                                text: modelData.title
                                subtext: modelData.sub || ""
                                trailing: modelData.trailing || ""
                                glyph: modelData.glyph || ""
                                iconSource: modelData.icon || ""
                                marked: !!modelData.pinned
                                onClicked: root.activate(index)
                                // Clipboard: the preview follows the pointer too
                                onHoveredChanged: if (hovered && root.mode === "clipboard") appsView.currentIndex = index

                                // Right-click: the app's options
                                TapHandler {
                                    acceptedButtons: Qt.RightButton
                                    onTapped: root.openOptionsAt(index)
                                }
                            }

                            ScrollIndicator.vertical: ScrollIndicator {
                                active: appsView.moving
                            }
                        }
                    }
                }
            }
        }
    }

    // Keys from the search box. Escape: games step back / clear / close; options close; else close.
    // Up / Down (and Left / Right in the games grid) move, Ctrl+Tab cycles the tabs, plain Tab
    // steps, Enter activates (Shift+Enter: the app's options). Everything else types.
    function handleKey(event) {
        const games = root.mode === "games";
        const ctrl = event.modifiers & Qt.ControlModifier;
        let handled = true;
        switch (event.key) {
        case Qt.Key_Escape:
            if (games) {
                if (gamesView.goBack())
                    break;
                if (searchInput.text !== "")
                    searchInput.text = "";
                else
                    root.closeCallback();
            } else if (root.optionsFor) {
                root.closeOptions();
            } else {
                root.closeCallback();
            }
            break;
        case Qt.Key_Down:
            games ? gamesView.move(MenuStyle.gamesGridColumns) : root.step(1);
            break;
        case Qt.Key_Up:
            games ? gamesView.move(-MenuStyle.gamesGridColumns) : root.step(-1);
            break;
        case Qt.Key_Left:
        case Qt.Key_Right:
            if (games)
                gamesView.move(event.key === Qt.Key_Left ? -1 : 1);
            else
                handled = false;        // caret movement in the search text
            break;
        case Qt.Key_Tab:
            ctrl ? root.cycleTab(1) : (games ? gamesView.move(1) : root.step(1));
            break;
        case Qt.Key_Backtab:
            ctrl ? root.cycleTab(-1) : (games ? gamesView.move(-1) : root.step(-1));
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (games)
                gamesView.activateKey(event);
            else if (event.key === Qt.Key_Return && (event.modifiers & Qt.ShiftModifier))
                root.openOptionsAt(appsView.currentIndex);
            else
                root.activate(appsView.currentIndex);
            break;
        default:
            handled = false;
        }
        event.accepted = handled;
    }

    // --- results ---

    function step(d) {
        if (root.results.length === 0)
            return;
        appsView.currentIndex = (appsView.currentIndex + d + root.results.length) % root.results.length;
    }

    readonly property var tabs: [
        { key: "apps", text: "Apps", glyph: "\ue5c3" },
        { key: "games", text: "Games", glyph: "\ue338" },
        { key: "clipboard", text: "Clipboard", glyph: "\ue14f" }
    ]

    // "windows" (the "," search) lives on the Apps tab
    function tabOf(m) {
        return m === "windows" ? "apps" : m;
    }

    function cycleTab(d) {
        const i = root.tabs.findIndex(t => t.key === root.tabOf(root.mode));
        root.open(root.tabs[(i + d + root.tabs.length) % root.tabs.length].key);
    }

    function setResults(list, index) {
        root.results = list;
        appsView.currentIndex = Math.max(0, Math.min(index || 0, list.length - 1));
    }

    function rebuild() {
        if (root.mode === "games")
            return;
        if (root.optionsFor)
            return root.setResults(root.optionsItems(root.optionsFor), 0);
        const q = searchInput.text.trim();
        if (root.mode === "windows" || q.startsWith(","))
            return root.setResults(root.windowItems(root.mode === "windows" ? q : q.slice(1).trim()), root.mode === "windows" && q === "" ? 1 : 0);
        if (root.mode === "clipboard")
            return root.setResults(root.clipItems(q), 0);

        const items = [];
        const calc = Utils.Calc.evaluate(q);
        if (calc !== "")
            items.push({ title: "= " + calc, sub: "Enter copies the result", glyph: "", run: () => root.copy(calc.replace(/ [a-z/]+$/, "")) });
        for (const s of root.sessionItems(q))
            items.push(s);
        root.setResults(items.concat(root.appItems(q)), 0);
    }

    function inCategory(entry) {
        const hidden = LauncherState.isHidden(entry.id);
        if (root.category === "hidden")
            return hidden;
        if (hidden)
            return false;
        const c = root.categories.find(x => x.key === root.category);
        if (!c || c.cats.length === 0)
            return true;
        const ec = entry.categories || [];
        return c.cats.some(x => ec.indexOf(x) !== -1);
    }

    function appItem(entry) {
        return {
            title: entry.name,
            glyph: "",
            icon: Utils.AppSearch.getIcon(entry.icon),
            pinned: LauncherState.isPinned(entry.id),
            entry: entry,
            run: () => {
                LauncherState.bump(entry.id);
                entry.execute();
                root.closeCallback();
            }
        };
    }

    // Usage nudges the order a little (up to +0.1 on fuzzysort's 0..1 score)
    function usageBonus(entry) {
        const n = LauncherState.counts[entry.id] || 0;
        return Math.min(0.1, Math.log(1 + n) / Math.log(10) * 0.05);
    }

    function appItems(q) {
        if (q === "") {
            const all = Array.from(Utils.AppSearch.list).filter(e => root.inCategory(e));
            const pinned = LauncherState.pinned.map(id => all.find(e => e.id === id)).filter(e => e);
            const rest = all.filter(e => !LauncherState.isPinned(e.id))
                .sort((a, b) => (LauncherState.counts[b.id] || 0) - (LauncherState.counts[a.id] || 0) || a.name.localeCompare(b.name));
            return pinned.concat(rest).map(e => root.appItem(e));
        }
        return Utils.AppSearch.scoredQuery(q)
            .filter(r => root.inCategory(r.entry))
            .map(r => ({ entry: r.entry, rank: r.score + root.usageBonus(r.entry) }))
            .sort((a, b) => b.rank - a.rank)
            .map(r => root.appItem(r.entry));
    }

    // Session actions by name or a common synonym; a second Enter confirms
    readonly property var sessionWords: ({ sleep: "Suspend", restart: "Reboot", poweroff: "Shutdown", "power off": "Shutdown", logout: "Log out", quit: "Log out" })
    function sessionItems(q) {
        const l = q.toLowerCase();
        if (l.length < 2)
            return [];
        return Session.all.filter(a => a.name.toLowerCase().startsWith(l)
                || Object.keys(root.sessionWords).some(w => w.startsWith(l) && root.sessionWords[w] === a.name))
            .map(a => ({
                title: root.confirmKey === a.name ? a.name + "? Press Enter again" : a.name,
                sub: a.confirm ? "Session" : "Custom action",
                glyph: a.icon,
                key: a.name,
                run: () => {
                    if (a.confirm && root.confirmKey !== a.name) {
                        root.confirmKey = a.name;
                        const i = appsView.currentIndex;
                        root.rebuild();
                        appsView.currentIndex = i;
                        return;
                    }
                    Session.run(a);
                    root.closeCallback();
                }
            }));
    }

    function windowItems(q) {
        Hyprland.refreshToplevels();
        const l = q.toLowerCase();
        const focusOrder = t => t.lastIpcObject && t.lastIpcObject.focusHistoryID !== undefined ? t.lastIpcObject.focusHistoryID : 999;
        return Hyprland.toplevels.values
            .filter(t => t.title !== "" && (l === "" || t.title.toLowerCase().includes(l)
                || (t.lastIpcObject && String(t.lastIpcObject.class).toLowerCase().includes(l))))
            .sort((a, b) => focusOrder(a) - focusOrder(b))
            .map(t => ({
                title: t.title,
                trailing: t.workspace ? t.workspace.name.replace("special:", "*") : "",
                glyph: "",
                icon: t.wayland ? Utils.AppSearch.getIcon(t.wayland.appId) : "",
                run: () => {
                    Hyprland.dispatch("hl.dsp.focus({ window = \"address:0x" + t.address + "\" })");
                    root.closeCallback();
                }
            }));
    }

    function clipItems(q) {
        const l = q.toLowerCase();
        return root.clipLines
            .filter(c => l === "" || c.text.toLowerCase().includes(l))
            .map(c => ({
                // Images list as "png 1920x1141  3 MiB"; the picture shows in the preview pane
                title: c.ext ? c.info : c.text,
                glyph: c.ext ? "\ue3f4" : "\ue14f",
                clip: c,
                run: () => {
                    Quickshell.execDetached(["sh", "-c", "cliphist decode \"$1\" | wl-copy", "sh", c.id]);
                    root.closeCallback();
                }
            }));
    }

    function optionsItems(entry) {
        if (root.uninstallFor)
            return root.uninstallItems();
        const pinned = LauncherState.isPinned(entry.id);
        const items = [
            { title: "Launch " + entry.name, glyph: "", run: () => root.appItem(entry).run() },
            { title: pinned ? "Unpin" : "Pin to the top", glyph: "", run: () => { LauncherState.togglePin(entry.id); root.closeOptions(); } }
        ];
        if (pinned) {
            items.push({ title: "Move up", glyph: "", run: () => { LauncherState.move(entry.id, -1); root.rebuild(); } });
            items.push({ title: "Move down", glyph: "", run: () => { LauncherState.move(entry.id, 1); root.rebuild(); } });
        }
        const hidden = LauncherState.isHidden(entry.id);
        items.push({ title: hidden ? "Unhide" : "Hide from the launcher", glyph: hidden ? "\ue8f4" : "\ue8f5", run: () => {
            LauncherState.toggleHidden(entry.id);
            if (root.hiddenCount === 0)
                root.category = "all";
            root.closeOptions();
        } });
        items.push({ title: "Uninstall...", glyph: "\ue872", run: () => {
            ownerProc.entryName = entry.name;
            ownerProc.command = ["sh", Quickshell.shellDir + "/scripts/app-owner.sh", entry.id];
            ownerProc.running = true;
        } });
        items.push({ title: "Back", glyph: "", run: () => root.closeOptions() });
        return items;
    }

    // Confirm step: names the package, then runs the removal in a terminal so you see the prompts
    function uninstallItems() {
        const u = root.uninstallFor;
        if (u.kind === "none")
            return [
                { title: "No package owns " + u.name, sub: "Only Hide is possible", glyph: "\ue002", run: () => root.closeOptions() },
                { title: "Back", glyph: "", run: () => root.closeOptions() }
            ];
        return [
            { title: "Remove " + u.pkg + "?", sub: u.kind === "flatpak" ? "flatpak uninstall" : "yay -Rns", glyph: "\ue872", run: () => {
                const cmd = u.kind === "flatpak" ? "flatpak uninstall " + u.pkg : "yay -Rns " + u.pkg;
                Quickshell.execDetached([Config.settings.execCommands.terminal, "fish", "-c", cmd + "; echo; read -P 'Press Enter to close'"]);
                root.closeCallback();
            } },
            { title: "Cancel", glyph: "", run: () => root.closeOptions() }
        ];
    }

    Process {
        id: ownerProc
        property string entryName: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.trim().match(/^(pacman|flatpak):([A-Za-z0-9@._+-]+)$/);
                root.uninstallFor = { name: ownerProc.entryName, kind: m ? m[1] : "none", pkg: m ? m[2] : "" };
                root.rebuild();
            }
        }
    }

    function openOptionsAt(i) {
        const r = root.results[i];
        if (!r || !r.entry)
            return;
        root.optionsFor = r.entry;
        root.rebuild();
    }

    function closeOptions() {
        root.optionsFor = null;
        root.uninstallFor = null;
        root.rebuild();
    }

    function activate(i) {
        const r = root.results[i];
        if (r && r.run)
            r.run();
    }

    function copy(text) {
        Quickshell.execDetached(["wl-copy", "--", text]);
        root.closeCallback();
    }

    // Desktop entries load asynchronously: refresh the list when they arrive
    Connections {
        target: Utils.AppSearch
        function onListChanged() {
            if (root.visible)
                root.rebuild();
        }
    }

    // cliphist list: "<id>\t<preview>" per line, newest first
    Process {
        id: clipProc
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.clipLines = text.split("\n").filter(l => l.includes("\t")).map(l => {
                    const tab = l.indexOf("\t");
                    const t = l.slice(tab + 1);
                    // "[[ binary data 3 MiB png 1920x1141 ]]"
                    const m = t.match(/^\[\[ binary data (\S+ \S+) (png|jpe?g|gif|webp|bmp) (\d+x\d+) \]\]$/i);
                    return { id: l.slice(0, tab), text: t, ext: m ? m[2].toLowerCase() : "", info: m ? m[2].toLowerCase() + " " + m[3] + "  " + m[1] : "" };
                });
                root.rebuild();
            }
        }
    }

    // --- clipboard preview ---
    // The highlighted entry, decoded on demand: images into Quickshell's cache dir (kept for
    // next time), text straight from `cliphist decode` (first 4000 bytes).
    readonly property string clipCacheDir: Quickshell.cachePath("clipboard")
    readonly property var previewClip: root.mode === "clipboard" && root.results[appsView.currentIndex] ? (root.results[appsView.currentIndex].clip || null) : null
    property string previewImage: ""
    property string previewText: ""
    onPreviewClipChanged: root.loadPreview()

    function loadPreview() {
        const c = root.previewClip;
        root.previewImage = "";
        root.previewText = c && !c.ext ? c.text : "";
        if (!c || previewProc.running)
            return;
        previewProc.clipId = c.id;
        if (c.ext) {
            previewProc.path = root.clipCacheDir + "/" + c.id + "." + c.ext;
            previewProc.command = ["sh", "-c", "mkdir -p \"$(dirname \"$2\")\"; [ -s \"$2\" ] || cliphist decode \"$1\" > \"$2\"", "sh", c.id, previewProc.path];
        } else {
            previewProc.path = "";
            previewProc.command = ["sh", "-c", "cliphist decode \"$1\" | head -c 4000", "sh", c.id];
        }
        previewProc.running = true;
    }

    Process {
        id: previewProc
        property string clipId: ""
        property string path: ""
        stdout: StdioCollector {
            onStreamFinished: {
                if (previewProc.path === "" && root.previewClip && root.previewClip.id === previewProc.clipId)
                    root.previewText = text;
            }
        }
        onExited: {
            if (root.previewClip && root.previewClip.id === previewProc.clipId) {
                if (previewProc.path !== "")
                    root.previewImage = previewProc.path;
            } else {
                // The highlight moved while this ran: load the current one
                Qt.callLater(root.loadPreview);
            }
        }
    }

    // --- open / close ---

    function openMenu() { openAppLauncher() }

    function openAppLauncher() {
        root.open("apps");
    }

    function open(mode) {
        root.mode = mode;
        root.category = "all";
        root.optionsFor = null;
        root.uninstallFor = null;
        root.confirmKey = "";
        root.visible = true;
        searchInput.text = "";
        if (mode === "clipboard") {
            root.clipLines = [];
            clipProc.running = true;
        }
        if (mode === "games")
            gamesView.reset();
        root.rebuild();
        searchInput.focusInput();
    }

    function closeMenu() {
        root.visible = false;
    }
}
