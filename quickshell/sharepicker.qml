//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma IconTheme RetroismIcons
//@ pragma Env QS_ICON_THEME=RetroismIcons

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "popups" as Popups

// Screen-share picker for xdg-desktop-portal-hyprland: its own small Quickshell instance, started
// by scripts/share-picker.sh (hypr/xdph.conf: custom_picker_binary) whenever an app asks to share
// the screen. Shows the monitors and windows as cards; Enter / Share writes
//   [SELECTION]<r or nothing>/screen:<name>    or    .../window:<handle>
// to $SHAREPICKER_OUT (the wrapper prints it on stdout). Escape / Cancel writes nothing, which the
// portal treats as cancelled. Region sharing is not offered (the default picker has it).
// XDPH hands the window list over in XDPH_WINDOW_SHARING_LIST as
//   handle[HC>]class[HT>]title[HE>]mapping[HA>]   per window.
Scope {
    id: root

    property string tab: "screens"          // screens | windows
    property int cursor: 0
    property bool remember: Quickshell.env("SHAREPICKER_REMEMBER") === "1"
    // Test hook: no screen / window capture (thumbnails would show the live desktop)
    readonly property bool capture: Quickshell.env("SHAREPICKER_NOCAPTURE") !== "1"

    readonly property var focusedScreen: Quickshell.screens.find(s => Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name) || Quickshell.screens[0]

    readonly property var windows: root.parseWindows(Quickshell.env("XDPH_WINDOW_SHARING_LIST") || "")
    readonly property var screens: Quickshell.screens.map(s => ({ kind: "screen", payload: s.name, title: s.name, sub: s.width + " x " + s.height, screen: s, toplevel: null, icon: "" }))
    readonly property var shareWindows: root.windows.map(w => ({ kind: "window", payload: w.handle, title: w.title !== "" ? w.title : w.cls, sub: w.cls, screen: null, toplevel: root.matchToplevel(w), icon: Quickshell.iconPath(w.cls.toLowerCase(), true) }))
    readonly property var items: root.tab === "screens" ? root.screens : root.shareWindows
    readonly property var current: root.items[root.cursor] || null

    onTabChanged: root.cursor = 0

    // --- parsing ---

    function parseWindows(s) {
        const out = [];
        for (const rec of s.split("[HA>]")) {
            if (rec === "")
                continue;
            const c = rec.indexOf("[HC>]"), t = rec.indexOf("[HT>]"), e = rec.indexOf("[HE>]");
            if (c < 0 || t < 0 || e < 0)
                continue;
            out.push({ handle: rec.slice(0, c), cls: rec.slice(c + 5, t), title: rec.slice(t + 5, e), mapping: rec.slice(e + 5) });
        }
        return out;
    }

    // XDPH blanks quotes, $ and backticks in class and title; do the same to ours before comparing
    function sanitize(s) {
        return (s || "").replace(/['"$`]/g, " ").replace(/>\]/g, "> ").toLowerCase();
    }

    // The live window behind a card, for the thumbnail: same class, same title (or the only one of that class)
    function matchToplevel(w) {
        if (!root.capture)
            return null;
        const all = ToplevelManager.toplevels.values.filter(t => root.sanitize(t.appId) === root.sanitize(w.cls));
        return all.find(t => root.sanitize(t.title) === root.sanitize(w.title)) || (all.length === 1 ? all[0] : null);
    }

    // --- result ---

    function share() {
        if (!root.current)
            return;
        const line = "[SELECTION]" + (root.remember ? "r" : "") + "/" + root.current.kind + ":" + root.current.payload;
        const out = Quickshell.env("SHAREPICKER_OUT");
        if (out) {
            writer.command = ["sh", "-c", 'printf "%s\\n" "$1" > "$2"', "sh", line, out];
            writer.running = true;
        } else {
            console.log(line);
            Qt.quit();
        }
    }

    function cancel() {
        Qt.quit();
    }

    Process {
        id: writer
        onExited: Qt.quit()
    }

    function move(d) {
        if (root.items.length === 0)
            return;
        root.cursor = Math.max(0, Math.min(root.items.length - 1, root.cursor + d));
        grid.positionViewAtIndex(root.cursor, GridView.Contain);
    }

    PanelWindow {
        id: win
        screen: root.focusedScreen
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qs-share-picker"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        // Backdrop: dims the screen; a click outside the dialog cancels
        Rectangle {
            anchors.fill: parent
            color: Config.colors.outline
            opacity: MenuStyle.shareDimOpacity
            MouseArea {
                anchors.fill: parent
                onClicked: root.cancel()
            }
        }

        Item {
            id: frame
            width: MenuStyle.launcherWidth
            height: MenuStyle.launcherHeight
            anchors.centerIn: parent
            focus: true

            Keys.onEscapePressed: root.cancel()
            Keys.onLeftPressed: root.move(-1)
            Keys.onRightPressed: root.move(1)
            Keys.onUpPressed: root.move(-MenuStyle.shareGridColumns)
            Keys.onDownPressed: root.move(MenuStyle.shareGridColumns)
            Keys.onReturnPressed: root.share()
            Keys.onEnterPressed: root.share()
            Keys.onTabPressed: root.tab = root.tab === "screens" ? "windows" : "screens"
            Keys.onBacktabPressed: root.tab = root.tab === "screens" ? "windows" : "screens"

            MouseArea {
                anchors.fill: parent
                onClicked: {}
            }

            Popups.PopupWindowFrame {
                windowTitle: "Share your screen"
                windowTitleIcon: ""

                ColumnLayout {
                    anchors.fill: parent
                    spacing: MenuStyle.pad

                    // Tabs
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: MenuStyle.gap
                        Repeater {
                            model: [
                                { key: "screens", text: "Screens", glyph: "" },
                                { key: "windows", text: "Windows", glyph: "" }
                            ]
                            Popups.BevelButton {
                                Layout.fillWidth: true
                                text: modelData.text
                                glyph: modelData.glyph
                                checked: root.tab === modelData.key
                                focusPolicy: Qt.NoFocus
                                onClicked: root.tab = modelData.key
                            }
                        }
                    }

                    // Cards
                    Popups.SunkenField {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        padding: 2
                        clip: true

                        Text {
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferFullHinting
                            anchors.centerIn: parent
                            visible: root.items.length === 0
                            font.family: MenuStyle.bodyFont
                            font.pixelSize: MenuStyle.fontSize
                            color: MenuStyle.bevelDark
                            text: root.tab === "windows" ? "No windows to share" : "No screens found"
                        }

                        GridView {
                            id: grid
                            anchors.fill: parent
                            cellWidth: width / MenuStyle.shareGridColumns
                            cellHeight: (cellWidth - 2 * MenuStyle.gap) * 9 / 16 + MenuStyle.shareLabelHeight + 2 * MenuStyle.gap
                            clip: true
                            currentIndex: root.cursor
                            highlightFollowsCurrentItem: false
                            model: root.items
                            delegate: Item {
                                id: card
                                required property int index
                                required property var modelData
                                width: grid.cellWidth
                                height: grid.cellHeight
                                readonly property bool isCurrent: root.cursor === index

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    color: card.isCurrent ? MenuStyle.selectBar : (cardMouse.containsMouse ? Config.colors.shadow : "transparent")

                                    // Thumbnail, or a letter tile when there is nothing to capture
                                    Rectangle {
                                        id: thumb
                                        x: MenuStyle.gap
                                        y: MenuStyle.gap
                                        width: parent.width - 2 * MenuStyle.gap
                                        height: width * 9 / 16
                                        color: Config.colors.outline
                                        clip: true

                                        ScreencopyView {
                                            id: shot
                                            anchors.centerIn: parent
                                            constraintSize: Qt.size(thumb.width, thumb.height)
                                            captureSource: !root.capture ? null : (card.modelData.kind === "screen" ? card.modelData.screen : card.modelData.toplevel)
                                        }
                                        Rectangle {
                                            anchors.fill: parent
                                            visible: !shot.hasContent
                                            color: card.isCurrent ? Config.colors.base : MenuStyle.selectBar
                                            Image {
                                                anchors.centerIn: parent
                                                width: MenuStyle.shareIconSize
                                                height: width
                                                visible: card.modelData.icon !== ""
                                                source: card.modelData.icon
                                                fillMode: Image.PreserveAspectFit
                                                asynchronous: true
                                            }
                                            Text {
                                                renderType: Text.NativeRendering
                                                font.hintingPreference: Font.PreferFullHinting
                                                anchors.centerIn: parent
                                                visible: card.modelData.icon === ""
                                                font.family: MenuStyle.titleFont
                                                font.pixelSize: parent.height / 2
                                                color: card.isCurrent ? Config.colors.text : MenuStyle.selectText
                                                text: card.modelData.title.charAt(0).toUpperCase()
                                            }
                                        }
                                    }
                                    Column {
                                        x: MenuStyle.gap
                                        y: thumb.y + thumb.height + MenuStyle.gap
                                        width: parent.width - 2 * MenuStyle.gap
                                        spacing: 0
                                        Text {
                                            renderType: Text.NativeRendering
                                            font.hintingPreference: Font.PreferFullHinting
                                            width: parent.width
                                            elide: Text.ElideRight
                                            horizontalAlignment: Text.AlignHCenter
                                            font.family: MenuStyle.bodyFont
                                            font.pixelSize: MenuStyle.fontSize
                                            color: card.isCurrent ? MenuStyle.selectText : Config.colors.text
                                            text: card.modelData.title
                                        }
                                        Text {
                                            renderType: Text.NativeRendering
                                            font.hintingPreference: Font.PreferFullHinting
                                            width: parent.width
                                            elide: Text.ElideRight
                                            horizontalAlignment: Text.AlignHCenter
                                            font.family: MenuStyle.bodyFont
                                            font.pixelSize: MenuStyle.fontSize
                                            color: card.isCurrent ? MenuStyle.selectText : MenuStyle.bevelDark
                                            text: card.modelData.sub
                                        }
                                    }
                                    FocusRect {
                                        anchors.fill: parent
                                        anchors.margins: 1
                                        visible: card.isCurrent
                                        color: MenuStyle.selectText
                                    }
                                }
                                MouseArea {
                                    id: cardMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.cursor = card.index
                                    onDoubleClicked: {
                                        root.cursor = card.index;
                                        root.share();
                                    }
                                }
                            }
                        }
                    }

                    // Footer
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: MenuStyle.gap

                        Popups.BevelButton {
                            text: "Remember my choice"
                            glyph: root.remember ? "" : ""
                            checked: root.remember
                            focusPolicy: Qt.NoFocus
                            onClicked: root.remember = !root.remember
                        }
                        Item { Layout.fillWidth: true }
                        Popups.BevelButton {
                            text: "Share"
                            glyph: ""
                            enabled: root.current !== null
                            focusPolicy: Qt.NoFocus
                            onClicked: root.share()
                        }
                        Popups.BevelButton {
                            text: "Cancel"
                            focusPolicy: Qt.NoFocus
                            onClicked: root.cancel()
                        }
                    }
                }
            }
        }
    }
}
