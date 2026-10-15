import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import ".."

// Wallpaper browser (Themes > Wallpapers...), centred, the launcher's size. The content is
// WallpaperView.qml. Type to filter; arrows move; Enter or double-click sets the wallpaper on the
// chosen monitor(s); Escape clears the search, then closes.
PanelWindow {
    id: root
    // The bar window this popup hangs off (set by Bar.qml)
    required property var bar

    property int screenHeight: 0
    property var closeCallback: function () {}

    // Overlay-layer panel like the Games menu, so it works over fullscreen windows too
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
            windowTitle: "Wallpapers"
            windowTitleIcon: ""

            ColumnLayout {
                anchors.fill: parent
                spacing: MenuStyle.pad

                SearchBox {
                    id: searchInput
                    Layout.fillWidth: true
                    placeholder: "Search wallpapers"
                    onEscaped: root.closeCallback()
                    onKeyPressed: event => {
                        const steps = { [Qt.Key_Left]: -1, [Qt.Key_Right]: 1, [Qt.Key_Up]: -MenuStyle.wallGridColumns, [Qt.Key_Down]: MenuStyle.wallGridColumns };
                        if (event.key in steps) {
                            view.move(steps[event.key]);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            view.activateKey(event);
                            event.accepted = true;
                        }
                    }
                }

                WallpaperView {
                    id: view
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    query: searchInput.text.trim()
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
