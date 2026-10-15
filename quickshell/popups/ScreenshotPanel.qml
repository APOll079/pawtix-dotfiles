import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import Qt.labs.folderlistmodel
import ".."

// Screenshot history (History button on the snipping overlay, or `qs ipc call screenshot_<mon>
// history`), centred. Taking shots lives in ScreenshotOverlay.qml.
// - Grid: ~/screenshots newest first. Click selects, Ctrl+click toggles, Shift+click selects a
//   range, Ctrl+A all; arrows move the dotted cursor, Shift+arrows extend. Today / Week / All
//   quick filters, or type a date (typing resets the quick filter to All).
// - Viewer (double-click, Enter, Space): one shot fit to the panel (1:1 and crisp when it fits),
//   Left/Right step through the filtered shots, Escape back to the grid.
// - Actions work on the selection (or the shown shot): Copy (one = the image, several = files as
//   text/uri-list), Open, Delete (to the trash, asks first), Folder.
PanelWindow {
    id: root
    // The bar window this popup hangs off (set by Bar.qml)
    required property var bar

    property int screenHeight: 0
    property var closeCallback: function () {}

    property var selection: []             // selected file paths (reassigned, never mutated)
    property int anchorIndex: -1           // Shift range start
    property bool keyNav: false            // dotted cursor shows after keyboard use
    property int page: 0                   // 0 = grid, 1 = viewer
    property int viewIndex: 0
    property string quick: "all"           // all | today | week
    property bool confirmDelete: false

    readonly property string dir: Quickshell.env("HOME") + "/screenshots"
    readonly property var targets: page === 1 ? (folderModel.count > 0 ? [pathAt(viewIndex)] : []) : selection

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

    FolderListModel {
        id: folderModel
        folder: "file://" + root.dir
        nameFilters: root.filters()
        showDirs: false
        sortField: FolderListModel.Time
        onCountChanged: {
            if (root.viewIndex >= count)
                root.viewIndex = Math.max(0, count - 1);
            if (count === 0)
                root.page = 0;
        }
    }

    // Click outside the frame closes
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: root.closeCallback()
    }

    Item {
        id: frame
        width: Math.round(root.width * MenuStyle.shotHistoryWidthFraction)
        height: Math.round(root.screenHeight * MenuStyle.shotHistoryHeightFraction)
        x: (root.width - width) / 2
        y: root.screenHeight / 2 - height / 2 - MenuStyle.barHeight

        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        PopupWindowFrame {
            windowTitle: root.page === 1 ? "Screenshots - " + (root.viewIndex + 1) + " of " + folderModel.count : "Screenshots"
            windowTitleIcon: ""

            ColumnLayout {
                id: keys
                anchors.fill: parent
                spacing: MenuStyle.pad
                focus: true
                Keys.onPressed: event => root.handleKey(event)

                // Filter row (grid only)
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.page === 0
                    spacing: MenuStyle.gap

                    SearchBox {
                        id: filterInput
                        Layout.fillWidth: true
                        placeholder: "Filter by date, e.g. 20261010"
                        onEdited: {
                            root.quick = "all";
                            root.resetSelection();
                        }
                        // Escape, Down and Enter hand the keys back to the grid
                        onKeyPressed: event => {
                            if (event.key === Qt.Key_Escape || event.key === Qt.Key_Down || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                keys.forceActiveFocus();
                                event.accepted = true;
                            }
                        }
                    }
                    Repeater {
                        model: [
                            { key: "today", text: "Today" },
                            { key: "week", text: "Week" },
                            { key: "all", text: "All" }
                        ]
                        BevelButton {
                            implicitWidth: MenuStyle.shotFilterButtonWidth
                            implicitHeight: MenuStyle.searchHeight
                            text: modelData.text
                            checked: root.quick === modelData.key
                            focusPolicy: Qt.NoFocus
                            onClicked: {
                                root.quick = modelData.key;
                                filterInput.text = "";
                                root.resetSelection();
                                keys.forceActiveFocus();
                            }
                        }
                    }
                }

                StackLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentIndex: root.page

                    // --- Grid ---
                    SunkenField {
                        padding: 2
                        clip: true

                        Text {
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferFullHinting
                            anchors.centerIn: parent
                            visible: folderModel.count === 0
                            font.family: MenuStyle.bodyFont
                            font.pixelSize: MenuStyle.fontSize
                            color: MenuStyle.bevelDark
                            text: "No screenshots"
                        }

                        GridView {
                            id: grid
                            anchors.fill: parent
                            cellWidth: width / MenuStyle.shotGridColumns
                            cellHeight: cellWidth * 9 / 16 + MenuStyle.gap
                            clip: true
                            currentIndex: 0
                            highlightFollowsCurrentItem: false
                            model: folderModel
                            delegate: Item {
                                id: cell
                                required property int index
                                required property string filePath
                                width: grid.cellWidth
                                height: grid.cellHeight
                                readonly property bool isSelected: root.selection.indexOf(filePath) >= 0

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    color: cell.isSelected ? MenuStyle.selectBar : (cellMouse.containsMouse ? Config.colors.shadow : "transparent")
                                    Image {
                                        anchors.fill: parent
                                        anchors.margins: MenuStyle.gap / 2
                                        source: "file://" + cell.filePath
                                        sourceSize.width: MenuStyle.shotThumbWidth
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                    }
                                    FocusRect {
                                        anchors.fill: parent
                                        anchors.margins: 1
                                        visible: root.keyNav && grid.currentIndex === cell.index
                                        color: cell.isSelected ? MenuStyle.selectText : Config.colors.text
                                    }
                                }
                                MouseArea {
                                    id: cellMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: mouse => root.clickCell(cell.index, mouse.modifiers)
                                    onDoubleClicked: root.openViewer(cell.index)
                                }
                            }
                            ScrollIndicator.vertical: ScrollIndicator {
                                active: grid.moving
                            }
                        }
                    }

                    // --- Viewer ---
                    SunkenField {
                        padding: 2
                        clip: true
                        Image {
                            id: viewImage
                            anchors.fill: parent
                            source: root.page === 1 && folderModel.count > 0 ? "file://" + root.pathAt(root.viewIndex) : ""
                            asynchronous: true
                            // 1:1 and pixel-crisp when it fits, scaled down smoothly when it doesn't
                            readonly property bool fits: implicitWidth <= width && implicitHeight <= height
                            fillMode: fits ? Image.Pad : Image.PreserveAspectFit
                            smooth: !fits
                        }
                        MouseArea {
                            anchors.fill: parent
                            onDoubleClicked: root.closeViewer()
                        }
                    }
                }

                // Status + actions
                RowLayout {
                    Layout.fillWidth: true
                    spacing: MenuStyle.gap
                    visible: !root.confirmDelete

                    BevelButton {
                        visible: root.page === 1
                        glyph: ""
                        text: "Grid"
                        focusPolicy: Qt.NoFocus
                        onClicked: root.closeViewer()
                    }
                    BevelButton {
                        visible: root.page === 1
                        glyph: ""
                        enabled: root.viewIndex > 0
                        focusPolicy: Qt.NoFocus
                        onClicked: root.step(-1)
                    }
                    BevelButton {
                        visible: root.page === 1
                        glyph: ""
                        enabled: root.viewIndex < folderModel.count - 1
                        focusPolicy: Qt.NoFocus
                        onClicked: root.step(1)
                    }
                    Text {
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferFullHinting
                        Layout.fillWidth: true
                        elide: Text.ElideMiddle
                        font.family: MenuStyle.bodyFont
                        font.pixelSize: MenuStyle.fontSize
                        color: root.targets.length === 0 ? MenuStyle.bevelDark : Config.colors.text
                        text: root.statusText()
                    }
                    BevelButton {
                        glyph: ""
                        enabled: root.targets.length > 0
                        focusPolicy: Qt.NoFocus
                        onClicked: root.copy(root.targets)
                    }
                    BevelButton {
                        glyph: ""
                        enabled: root.targets.length > 0
                        focusPolicy: Qt.NoFocus
                        onClicked: root.openFiles(root.targets)
                    }
                    BevelButton {
                        glyph: ""
                        enabled: root.targets.length > 0
                        focusPolicy: Qt.NoFocus
                        onClicked: root.confirmDelete = true
                    }
                    BevelButton {
                        visible: root.page === 0
                        glyph: ""
                        focusPolicy: Qt.NoFocus
                        onClicked: Quickshell.execDetached(["xdg-open", root.dir])
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: MenuStyle.gap
                    visible: root.confirmDelete
                    Text {
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferFullHinting
                        Layout.fillWidth: true
                        elide: Text.ElideMiddle
                        font.family: MenuStyle.bodyFont
                        font.pixelSize: MenuStyle.fontSize
                        color: Config.colors.text
                        text: root.targets.length === 1 ? "Move " + root.baseName(root.targets[0]) + " to the trash?" : "Move " + root.targets.length + " shots to the trash?"
                    }
                    BevelButton {
                        text: "Yes"
                        focusPolicy: Qt.NoFocus
                        onClicked: root.trash(root.targets)
                    }
                    BevelButton {
                        text: "Cancel"
                        focusPolicy: Qt.NoFocus
                        onClicked: root.confirmDelete = false
                    }
                }
            }
        }
    }

    // --- model helpers ---

    function pathAt(i) {
        const p = folderModel.get(i, "filePath");
        return p ? p : "";
    }

    function baseName(p) {
        return p.split("/").pop();
    }

    function dayStamp(daysAgo) {
        return Qt.formatDate(new Date(Date.now() - daysAgo * 86400000), "yyyyMMdd");
    }

    // Quick filter (Today / Week) or the typed date fragment
    function filters() {
        if (root.quick === "today" || root.quick === "week") {
            const days = root.quick === "today" ? 1 : 7;
            let out = [];
            for (let d = 0; d < days; d++)
                out.push("*" + root.dayStamp(d) + "*.png", "*" + root.dayStamp(d) + "*.jpg");
            return out;
        }
        const t = filterInput.text.trim();
        return ["*" + t + "*.png", "*" + t + "*.jpg"];
    }

    function formatSize(b) {
        if (b >= 1048576)
            return (b / 1048576).toFixed(1) + " MB";
        return Math.max(1, Math.round(b / 1024)) + " KB";
    }

    function statusText() {
        const t = root.targets;
        if (root.page === 1 && t.length === 1) {
            const i = root.viewIndex;
            const res = viewImage.status === Image.Ready ? viewImage.implicitWidth + "x" + viewImage.implicitHeight + ", " : "";
            return root.baseName(t[0]) + " - " + res + root.formatSize(folderModel.get(i, "fileSize")) + ", " + Qt.formatDateTime(folderModel.get(i, "fileModified"), "yyyy-MM-dd HH:mm");
        }
        if (t.length === 0)
            return folderModel.count + " shots";
        let total = 0;
        for (let i = 0; i < folderModel.count; i++)
            if (t.indexOf(root.pathAt(i)) >= 0)
                total += folderModel.get(i, "fileSize");
        if (t.length === 1)
            return root.baseName(t[0]) + " - " + root.formatSize(total);
        return t.length + " selected - " + root.formatSize(total);
    }

    // --- selection ---

    function resetSelection() {
        root.selection = [];
        root.anchorIndex = -1;
        root.confirmDelete = false;
        grid.currentIndex = 0;
    }

    function selectRange(a, b, add) {
        let out = add ? root.selection.slice() : [];
        for (let i = Math.min(a, b); i <= Math.max(a, b); i++) {
            const p = root.pathAt(i);
            if (p !== "" && out.indexOf(p) < 0)
                out.push(p);
        }
        root.selection = out;
    }

    function clickCell(i, mods) {
        const p = root.pathAt(i);
        root.keyNav = false;
        root.confirmDelete = false;
        if ((mods & Qt.ShiftModifier) && root.anchorIndex >= 0) {
            root.selectRange(root.anchorIndex, i, mods & Qt.ControlModifier);
        } else if (mods & Qt.ControlModifier) {
            const s = root.selection.slice(), at = s.indexOf(p);
            if (at >= 0)
                s.splice(at, 1);
            else
                s.push(p);
            root.selection = s;
            root.anchorIndex = i;
        } else {
            root.selection = [p];
            root.anchorIndex = i;
        }
        grid.currentIndex = i;
        keys.forceActiveFocus();
    }

    function moveCursor(d, extend) {
        if (folderModel.count === 0)
            return;
        const from = grid.currentIndex, to = Math.max(0, Math.min(folderModel.count - 1, from + d));
        root.keyNav = true;
        root.confirmDelete = false;
        if (extend) {
            if (root.anchorIndex < 0)
                root.anchorIndex = from;
            root.selectRange(root.anchorIndex, to, false);
        } else {
            root.selection = [root.pathAt(to)];
            root.anchorIndex = to;
        }
        grid.currentIndex = to;
        grid.positionViewAtIndex(to, GridView.Contain);
    }

    // --- viewer ---

    function openViewer(i) {
        if (folderModel.count === 0)
            return;
        root.viewIndex = Math.max(0, Math.min(folderModel.count - 1, i));
        root.confirmDelete = false;
        root.page = 1;
    }

    function closeViewer() {
        root.page = 0;
        root.confirmDelete = false;
        root.selection = folderModel.count > 0 ? [root.pathAt(root.viewIndex)] : [];
        root.anchorIndex = root.viewIndex;
        grid.currentIndex = root.viewIndex;
        grid.positionViewAtIndex(root.viewIndex, GridView.Contain);
    }

    function step(d) {
        root.viewIndex = Math.max(0, Math.min(folderModel.count - 1, root.viewIndex + d));
        root.confirmDelete = false;
    }

    // --- keys ---

    function handleKey(event) {
        const shift = event.modifiers & Qt.ShiftModifier, ctrl = event.modifiers & Qt.ControlModifier;
        const k = event.key;
        event.accepted = true;
        if (root.confirmDelete) {
            if (k === Qt.Key_Return || k === Qt.Key_Enter)
                root.trash(root.targets);
            else if (k === Qt.Key_Escape)
                root.confirmDelete = false;
            return;
        }
        if (k === Qt.Key_Delete) {
            if (root.targets.length > 0)
                root.confirmDelete = true;
        } else if (root.page === 1) {
            if (k === Qt.Key_Left)
                root.step(-1);
            else if (k === Qt.Key_Right)
                root.step(1);
            else if (k === Qt.Key_Escape || k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space)
                root.closeViewer();
            else
                event.accepted = false;
        } else {
            const cols = MenuStyle.shotGridColumns;
            if (k === Qt.Key_Left)
                root.moveCursor(-1, shift);
            else if (k === Qt.Key_Right)
                root.moveCursor(1, shift);
            else if (k === Qt.Key_Up)
                root.moveCursor(-cols, shift);
            else if (k === Qt.Key_Down)
                root.moveCursor(cols, shift);
            else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space)
                root.openViewer(grid.currentIndex);
            else if (k === Qt.Key_A && ctrl)
                root.selectRange(0, folderModel.count - 1, false);
            else if (k === Qt.Key_Escape) {
                if (root.selection.length > 0)
                    root.resetSelection();
                else
                    root.closeCallback();
            } else
                event.accepted = false;
        }
    }

    // --- actions (paths go in as arguments, never into the script text) ---

    function copy(paths) {
        if (paths.length === 1)
            Quickshell.execDetached(["sh", "-c", 'wl-copy < "$1"', "sh", paths[0]]);
        else
            Quickshell.execDetached(["sh", "-c", 'for f; do printf "file://%s\\n" "$f"; done | wl-copy -t text/uri-list', "sh"].concat(paths));
    }

    function openFiles(paths) {
        for (const p of paths)
            Quickshell.execDetached(["xdg-open", p]);
    }

    function trash(paths) {
        if (paths.length > 0)
            Quickshell.execDetached(["gio", "trash"].concat(paths));
        root.selection = [];
        root.anchorIndex = -1;
        root.confirmDelete = false;
    }

    // --- open / close ---

    function openMenu() {
        root.page = 0;
        root.quick = "all";
        filterInput.text = "";
        root.keyNav = false;
        root.resetSelection();
        root.visible = true;
        keys.forceActiveFocus();
    }

    function closeMenu() {
        root.visible = false;
    }
}
