import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import ".."

// Snipping overlay (Super+Shift+S, Print): freezes this screen, dims it, and shows a toolbar at
// the top. Region: drag a box, let go to shoot. Window: hover highlights a window, click shoots
// it (on a shown special workspace, its windows). Screen (this monitor) and All (both) shoot
// right away. Escape or X cancels.
// When the shot is taken the overlay drops the dim, toolbar and box and shows only the frozen
// frame, so grim captures exactly what was on screen when it opened (the hyprshot --freeze trick).
// Every shot lands in ~/screenshots, goes to the clipboard, and pops a toast with the image;
// clicking the toast opens it.
PanelWindow {
    id: root

    property var historyCallback: function() {}

    property string mode: "region"        // region | window | screen | all
    property bool capturing: false
    // The dim and the toolbar only appear once the frozen frame is in: the capture is taken of the
    // screen as it is, and an overlay already drawn by then (the dim covers everything until a
    // selection exists) would be baked into the "frozen" frame and into every shot
    readonly property bool chromeVisible: frozen.hasContent && !root.capturing
    property bool dragging: false
    property point anchorPos: Qt.point(0, 0)
    property rect sel: Qt.rect(0, 0, 0, 0)
    property var hoverWin: null           // { x, y, w, h } in local coords, window mode

    visible: false
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-screenshot"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // The highlighted area: the drag box, the hovered window, or the whole screen
    readonly property rect focusRect: {
        if (root.mode === "region")
            return root.sel;
        if (root.mode === "window")
            return root.hoverWin ? Qt.rect(root.hoverWin.x, root.hoverWin.y, root.hoverWin.w, root.hoverWin.h) : Qt.rect(0, 0, 0, 0);
        return Qt.rect(0, 0, width, height);
    }

    // Frozen frame of this screen, captured once when the overlay opens
    ScreencopyView {
        id: frozen
        anchors.fill: parent
        live: false
        captureSource: root.visible ? root.screen : null
    }

    // Dim everything outside the highlighted area (four strips)
    Item {
        anchors.fill: parent
        visible: root.chromeVisible
        readonly property rect r: root.focusRect
        readonly property color dimColor: Config.colors.outline
        Rectangle { x: 0; y: 0; width: parent.width; height: parent.r.y; color: parent.dimColor; opacity: MenuStyle.shotDimOpacity }
        Rectangle { x: 0; y: parent.r.y + parent.r.height; width: parent.width; height: parent.height - y; color: parent.dimColor; opacity: MenuStyle.shotDimOpacity }
        Rectangle { x: 0; y: parent.r.y; width: parent.r.x; height: parent.r.height; color: parent.dimColor; opacity: MenuStyle.shotDimOpacity }
        Rectangle { x: parent.r.x + parent.r.width; y: parent.r.y; width: parent.width - x; height: parent.r.height; color: parent.dimColor; opacity: MenuStyle.shotDimOpacity }

        // Box around the highlight, and its size
        Rectangle {
            visible: parent.r.width > 0 && parent.r.height > 0 && root.mode !== "screen" && root.mode !== "all"
            x: parent.r.x - 1
            y: parent.r.y - 1
            width: parent.r.width + 2
            height: parent.r.height + 2
            color: "transparent"
            border.width: 1
            border.color: MenuStyle.selectBar
        }
        Rectangle {
            visible: parent.r.width > 0 && parent.r.height > 0 && root.mode === "region"
            x: parent.r.x
            y: parent.r.y + parent.r.height + MenuStyle.gap
            width: sizeLabel.implicitWidth + 2 * MenuStyle.pad
            height: MenuStyle.rowHeight
            color: MenuStyle.selectBar
            Text {
                id: sizeLabel
                anchors.centerIn: parent
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferFullHinting
                font.family: MenuStyle.bodyFont
                font.pixelSize: MenuStyle.fontSize
                color: MenuStyle.selectText
                text: Math.round(root.sel.width) + " x " + Math.round(root.sel.height)
            }
        }
    }

    // Pointer: drag (region), hover + click (window), click (screen / all)
    MouseArea {
        anchors.fill: parent
        enabled: !root.capturing
        hoverEnabled: true
        cursorShape: root.mode === "region" ? Qt.CrossCursor : Qt.PointingHandCursor
        onPressed: mouse => {
            if (root.mode !== "region")
                return;
            root.dragging = true;
            root.anchorPos = Qt.point(mouse.x, mouse.y);
            root.sel = Qt.rect(mouse.x, mouse.y, 0, 0);
        }
        onPositionChanged: mouse => {
            if (root.mode === "region" && root.dragging) {
                const x = Math.min(mouse.x, root.anchorPos.x), y = Math.min(mouse.y, root.anchorPos.y);
                root.sel = Qt.rect(x, y, Math.abs(mouse.x - root.anchorPos.x), Math.abs(mouse.y - root.anchorPos.y));
            } else if (root.mode === "window") {
                root.hoverWin = root.windowAt(mouse.x, mouse.y);
            }
        }
        onReleased: {
            if (root.mode === "region") {
                root.dragging = false;
                if (root.sel.width >= MenuStyle.shotMinSize && root.sel.height >= MenuStyle.shotMinSize)
                    root.shoot();
                else
                    root.sel = Qt.rect(0, 0, 0, 0);
            } else if (root.mode === "window") {
                if (root.hoverWin)
                    root.shoot();
            } else {
                root.shoot();
            }
        }
    }

    // Toolbar: sits exactly over the bar's centre (where the lyrics are), so it covers little of the screen
    Rectangle {
        id: toolbar
        visible: root.chromeVisible
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: toolRow.implicitWidth + 2 * MenuStyle.pad
        height: MenuStyle.barHeight
        color: Config.colors.base
        border.width: 1
        border.color: Config.colors.outline
        Bevel {
            anchors.fill: parent
            anchors.margins: 1
            raised: true
        }
        // Clicks on the toolbar never start a drag
        MouseArea {
            anchors.fill: parent
            onPressed: {}
        }

        RowLayout {
            id: toolRow
            anchors.centerIn: parent
            spacing: MenuStyle.gap

            Repeater {
                model: [
                    { key: "region", text: "Region", glyph: "" },
                    { key: "window", text: "Window", glyph: "" },
                    { key: "screen", text: "Screen", glyph: "" },
                    { key: "all", text: "All", glyph: "" }
                ]
                BevelButton {
                    text: modelData.text
                    glyph: modelData.glyph
                    checked: root.mode === modelData.key
                    focusPolicy: Qt.NoFocus
                    onClicked: root.pick(modelData.key)
                }
            }
            MenuSeparator {
                vertical: true
                Layout.preferredHeight: MenuStyle.rowHeight
            }
            BevelButton {
                text: "History"
                glyph: ""
                focusPolicy: Qt.NoFocus
                onClicked: {
                    root.close();
                    root.historyCallback();
                }
            }
            BevelButton {
                glyph: ""
                focusPolicy: Qt.NoFocus
                onClicked: root.close()
            }
        }
    }

    // Keys: Escape cancels, Enter shoots (screen / all / a finished region), 1-4 pick a mode
    Item {
        id: keys
        focus: true
        Keys.onEscapePressed: root.close()
        Keys.onReturnPressed: if (root.mode === "screen" || root.mode === "all") root.shoot()
        Keys.onPressed: event => {
            const i = ["1", "2", "3", "4"].indexOf(event.text);
            if (i >= 0)
                root.pick(["region", "window", "screen", "all"][i]);
        }
    }

    function setMode(m) {
        root.mode = m;
        root.sel = Qt.rect(0, 0, 0, 0);
        root.hoverWin = null;
        if (m === "window") {
            Hyprland.refreshMonitors();
            Hyprland.refreshToplevels();
        }
    }

    // Toolbar buttons and keys 1-4: Screen and All shoot straight away
    function pick(m) {
        root.setMode(m);
        if (m === "screen" || m === "all")
            root.shoot();
    }

    // Topmost window under the pointer (floating first). A shown special workspace covers the
    // normal one, so then only its windows count. Matched by IPC name/id, not object identity.
    function windowAt(px, py) {
        const mon = Hyprland.monitorFor(root.screen);
        const mo = mon ? mon.lastIpcObject : null;
        if (!mo || !mo.activeWorkspace)
            return null;
        const special = mo.specialWorkspace && mo.specialWorkspace.name ? mo.specialWorkspace.name : "";
        let best = null;
        for (const t of Hyprland.toplevels.values) {
            const o = t.lastIpcObject;
            if (!o || !o.at || !o.size || !o.workspace || o.hidden)
                continue;
            if (special !== "" ? o.workspace.name !== special : o.workspace.id !== mo.activeWorkspace.id)
                continue;
            const x = o.at[0] - root.screen.x, y = o.at[1] - root.screen.y, w = o.size[0], h = o.size[1];
            if (px < x || py < y || px > x + w || py > y + h)
                continue;
            const score = (o.floating ? 0 : 1e9) + w * h;
            if (!best || score < best.score)
                best = { x: x, y: y, w: w, h: h, score: score };
        }
        return best;
    }

    // --- shoot ---

    Timer {
        id: shotDelay
        interval: MenuStyle.shotSettle
        onTriggered: root.runShot()
    }

    function shoot() {
        // Drop the overlay chrome first; only the frozen frame stays on screen for grim
        root.capturing = true;
        shotDelay.restart();
    }

    function runShot() {
        const r = root.focusRect;
        let args;
        if (root.mode === "all")
            args = [];
        else if (root.mode === "screen")
            args = ["-o", root.screen.name];
        else
            args = ["-g", Math.round(r.x + root.screen.x) + "," + Math.round(r.y + root.screen.y) + " " + Math.round(r.width) + "x" + Math.round(r.height)];
        // $1 dir, then the grim arguments
        const script = [
            'dir="$1"; shift; mkdir -p "$dir"; f="$dir/screenshot_$(date +%Y%m%d_%H%M%S).png"',
            'grim "$@" "$f" || exit 1',
            'wl-copy < "$f"',
            'a=$(notify-send -a Screenshot -h "string:image-path:$f" -A default=Open "Screenshot saved" "$(basename "$f")")',
            '[ "$a" = default ] && xdg-open "$f"'
        ].join("\n");
        Quickshell.execDetached(["sh", "-c", script, "sh", Quickshell.env("HOME") + "/screenshots"].concat(args));
        closeTimer.restart();
    }

    // Give grim a moment to read the frozen frame before the overlay goes away
    Timer {
        id: closeTimer
        interval: MenuStyle.shotSettle
        onTriggered: root.close()
    }

    // --- open / close ---

    function open() {
        root.capturing = false;
        root.dragging = false;
        root.setMode("region");
        root.visible = true;
        keys.forceActiveFocus();
    }

    function close() {
        shotDelay.stop();
        root.visible = false;
        root.capturing = false;
        root.dragging = false;
    }
}
