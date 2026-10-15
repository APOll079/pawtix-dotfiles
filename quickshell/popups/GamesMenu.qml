import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import ".."

// Games (Super+Shift+G, `qs ipc call games_<mon> toggle`), centred: a grid of cover
// art for every installed Steam game, Steam shortcut (non-Steam games added through Steam) and the
// user's own entries (Add game). The content is GamesView.qml, shared with the launcher's Games tab.
// Type to search; arrows move the cursor (Left/Right too, so the search box has no caret
// movement); Enter or double-click launches; a click (or Shift+Enter) shows the game's buttons;
// Escape steps back (buttons, filter), then clears the search, then closes.
PanelWindow {
    id: root
    // The bar window this popup hangs off (set by Bar.qml)
    required property var bar

    property int screenHeight: 0
    property var closeCallback: function () {}

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

    // Click outside the frame closes
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
            windowTitle: view.filter === "hidden" ? "Games - hidden" : "Games"
            windowTitleIcon: ""

            ColumnLayout {
                anchors.fill: parent
                spacing: MenuStyle.pad

                // Search
                SearchBox {
                    id: searchInput
                    Layout.fillWidth: true
                    visible: !view.addMode
                    placeholder: "Search games"
                    onEscaped: root.closeCallback()
                    // Arrows move through the cover grid (so no caret movement), Enter launches,
                    // Escape first steps back (the game's buttons, a filter), then clears, then closes
                    onKeyPressed: event => {
                        const steps = { [Qt.Key_Left]: -1, [Qt.Key_Right]: 1, [Qt.Key_Up]: -MenuStyle.gamesGridColumns, [Qt.Key_Down]: MenuStyle.gamesGridColumns };
                        if (event.key in steps) {
                            view.move(steps[event.key]);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            view.activateKey(event);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape && view.goBack()) {
                            event.accepted = true;
                        }
                    }
                }

                GamesView {
                    id: view
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    query: searchInput.text.trim()
                    closeCallback: root.closeCallback
                    onFocusSearch: searchInput.focusInput()
                }
            }
        }
    }

    // --- open / close ---

    function openMenu() {
        searchInput.text = "";
        view.reset();
        root.visible = true;
        searchInput.focusInput();
    }

    function closeMenu() {
        root.visible = false;
    }
}
