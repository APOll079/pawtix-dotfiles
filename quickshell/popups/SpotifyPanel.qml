import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import ".."

// Spotify panel (Super+S, `qs ipc call spotify_<mon> toggle`): a drawer hanging off the bar on the
// left screen edge, full height, no title bar; only its right and bottom edges get a 1px outline.
// A layer-shell panel (like the bar), not a popup: popups get nudged 4px inside the screen edge.
//
// Top: now playing (cover, seek bar, shuffle / previous / play / next / repeat, like, add to playlist,
// volume). Then Recent (the last 8 albums / playlists / artists you played from). Then the tabs:
// - Library: Spotify's Your Library (pins first) with chips All / Playlists / Artists / Albums;
//   Playlists shows your folders in Spotify's order.
// - Liked: Liked Songs.
// - Lyrics: the whole drawer for synced lyrics, with a slim transport strip at the bottom.
// Lists show as rows or cover tiles (the view button, remembered). A click opens (a folder, an
// album's / your playlist's songs, an artist's albums, Liked Songs); Back returns to where you were.
// The play button (hover / selected, or Shift+Enter) plays without opening.
// Keys: type to filter, arrows move (Left / Right too in the grid), Enter opens, Shift+Enter plays,
// Space plays / pauses (empty filter), Escape steps back, then closes.
// Data and control: SpotifyState.qml + scripts/spotify.py. First run asks for the client ID of your
// Spotify developer app, then logs in through the browser once.
PanelWindow {
    id: root

    property int screenHeight: 0
    property var closeCallback: function () {}

    property string tab: "library"         // library | liked | lyrics
    property string libraryKind: "all"     // Library chip: all | playlist | artist | album
    property var stack: []                 // opened items: { title, uri, kind, items, loading, blocked, fromIndex }
    property bool addMode: false           // picking a playlist for "add to playlist"
    property var addTarget: null           // the song being added: { uri, name }
    property var songMenu: null            // right-clicked song: its action row shows in the status line
    property string note: ""               // short feedback line
    property bool confirmLogout: false
    property bool editClient: false        // setup page: typing a new client ID
    property real openedAt: 0              // when something was last opened (double-click guard)
    property real shownAt: 0               // when the drawer opened (focus-change grace period)

    readonly property bool remote: SpotifyState.player !== null && !SpotifyState.local
    readonly property var lastTrack: SpotifyState.lastPlayed ? SpotifyState.lastPlayed.track : null
    readonly property bool lyricsMode: root.tab === "lyrics" && !root.addMode && root.stack.length === 0
    readonly property var view: root.stack.length > 0 ? root.stack[root.stack.length - 1] : null
    readonly property var likedRow: ({ kind: "liked", uri: "liked", name: "Liked Songs", sub: "Playlist", image: "", openable: true })

    // Pinned URIs from Your Library, so every view (folders too) can show the pin
    readonly property var pinned: {
        const p = {};
        for (const it of (SpotifyState.libraryItems || []))
            if (it.pinned)
                p[it.uri] = true;
        return p;
    }

    readonly property var baseItems: {
        if (root.addMode)
            return (SpotifyState.lists.playlists || []).filter(p => p.openable);
        if (root.view)
            return root.view.kind === "liked" ? (SpotifyState.lists.liked || []) : (root.view.items || []);
        if (root.tab === "library")
            return root.libraryRows();
        if (root.tab === "liked")
            return SpotifyState.lists.liked || [];
        return [];
    }
    readonly property var items: {
        const q = filterInput.text.trim().toLowerCase();
        return root.baseItems
            .filter(i => q === "" || (i.name + " " + i.sub).toLowerCase().includes(q))
            .map(i => root.pinned[i.uri] && !i.pinned ? Object.assign({}, i, { pinned: true }) : i);
    }
    readonly property bool songList: root.items.some(i => i.kind === "track") || (root.view !== null && root.view.kind === "liked") || (!root.view && root.tab === "liked")
    // Covers in a grid (remembered toggle) for anything but song lists and the playlist picker
    readonly property bool useGrid: SpotifyState.grid && !root.addMode && !root.songList
    readonly property bool showViewToggle: !root.addMode && !root.lyricsMode && !root.songList

    anchors {
        left: true
        top: true
        bottom: true
    }
    margins.top: MenuStyle.barHeight
    implicitWidth: MenuStyle.spotifyWidth
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-spotify"
    // On demand, not exclusive: an exclusive drawer could keep the click / focus from reaching
    // other windows. It still takes the keyboard when it opens (the filter box asks for focus).
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    visible: false
    color: "transparent"

    onVisibleChanged: {
        SpotifyState.active = visible;
        Lyrics.fast = visible && root.lyricsMode;
        if (visible && MenuStyle.animOpen > 0)
            openFade.restart();
    }
    // Backup for click-outside: another window getting focus, or a workspace switch, closes the drawer
    Connections {
        target: Hyprland
        // (not in the first moment after opening: Hyprland's window info settling then isn't you clicking away)
        // Only on this drawer's monitor: focus follows the mouse, so just moving onto a window on
        // the other monitor focuses it, and that must not close the drawer (a click there does,
        // through that monitor's click catcher)
        function onActiveToplevelChanged() {
            const t = Hyprland.activeToplevel;
            if (t && t.workspace && t.workspace.monitor && t.workspace.monitor.name === root.screen.name)
                root.focusLeft();
        }
        function onFocusedWorkspaceChanged() {
            const w = Hyprland.focusedWorkspace;
            if (w && w.monitor && w.monitor.name === root.screen.name)
                root.focusLeft();
        }
    }
    // Logging in (or the status check finishing) after the drawer opened: load the tab now
    Connections {
        target: SpotifyState
        function onLoggedInChanged() {
            if (SpotifyState.loggedIn && root.visible)
                root.loadForTab(true);
            root.focusKeys();
        }
    }
    onLyricsModeChanged: {
        Lyrics.fast = root.visible && root.lyricsMode;
        if (root.lyricsMode)
            Qt.callLater(() => lyricsView.currentIndex = Lyrics.index);
        root.focusKeys();
    }
    onTabChanged: listFade.restart()
    onStackChanged: {
        listFade.restart();
        root.songMenu = null;
    }

    // Keys where there's no filter box to type in (Lyrics, the login page): Escape and Space
    Item {
        id: keyCatcher
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                if (!root.goBack())
                    root.closeCallback();
            } else if (event.key === Qt.Key_Space && SpotifyState.loggedIn) {
                SpotifyState.togglePlay();
            } else {
                return;
            }
            event.accepted = true;
        }
    }

    // The drawer: base colour, open towards the bar (top) and the screen edge (left); the right and
    // bottom edges get a flat 1px outline like the bar's own edge (a bevel there fought the bar's)
    Rectangle {
        id: drawer
        anchors.fill: parent
        color: Config.colors.base

        NumberAnimation { id: openFade; target: drawer; property: "opacity"; from: 0; to: 1; duration: MenuStyle.animOpen; easing.type: Easing.OutCubic }

        Rectangle { x: parent.width - 1; y: 0; width: 1; height: parent.height; color: Config.colors.outline }
        Rectangle { x: 0; y: parent.height - 1; width: parent.width; height: 1; color: Config.colors.outline }

        // --- setup: client ID, then login ---
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: MenuStyle.pad
            visible: !SpotifyState.loggedIn
            spacing: MenuStyle.pad

            Text {
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferFullHinting
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                font.family: MenuStyle.bodyFont
                font.pixelSize: MenuStyle.fontSize
                color: Config.colors.text
                text: !SpotifyState.configured || root.editClient
                    ? "One-time setup:\n1. developer.spotify.com > Dashboard > Create app.\n2. Redirect URI: http://127.0.0.1:8898/callback\n3. Tick Web API, save, copy the Client ID here."
                    : "Log in once in the browser. The login is kept in Quickshell's state folder."
            }
            SearchBox {
                id: clientInput
                Layout.fillWidth: true
                implicitHeight: MenuStyle.rowHeight + MenuStyle.gap
                visible: !SpotifyState.configured || root.editClient
                showIcon: false
                placeholder: "Client ID"
                onEscaped: root.closeCallback()
                onKeyPressed: event => {
                    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && clientInput.text.trim() !== "") {
                        root.saveClient();
                        event.accepted = true;
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: MenuStyle.gap
                BevelButton {
                    visible: !SpotifyState.configured || root.editClient
                    text: "Save"
                    enabled: clientInput.text.trim() !== ""
                    focusPolicy: Qt.NoFocus
                    onClicked: root.saveClient()
                }
                BevelButton {
                    visible: SpotifyState.configured && !root.editClient
                    text: SpotifyState.loggingIn ? "Waiting for the browser..." : "Log in"
                    glyph: ""
                    enabled: !SpotifyState.loggingIn
                    focusPolicy: Qt.NoFocus
                    onClicked: SpotifyState.login()
                }
                Item { Layout.fillWidth: true }
                BevelButton {
                    visible: SpotifyState.configured && !root.editClient
                    text: "Change client ID"
                    focusPolicy: Qt.NoFocus
                    onClicked: {
                        root.editClient = true;
                        clientInput.text = "";
                        clientInput.focusInput();
                    }
                }
            }
            Text {
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferFullHinting
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                visible: SpotifyState.error !== ""
                font.family: MenuStyle.bodyFont
                font.pixelSize: MenuStyle.fontSize
                color: Config.colors.urgent
                text: SpotifyState.error
            }
            Item { Layout.fillHeight: true }
        }

        // --- main ---
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: MenuStyle.pad
            visible: SpotifyState.loggedIn
            spacing: MenuStyle.pad

            // Now playing: cover, then title / artist / album and right under it where it plays
            RowLayout {
                Layout.fillWidth: true
                visible: !root.lyricsMode
                Layout.preferredHeight: MenuStyle.spotifyCoverSize
                Layout.maximumHeight: MenuStyle.spotifyCoverSize
                spacing: MenuStyle.pad
                SunkenField {
                    Layout.preferredWidth: MenuStyle.spotifyCoverSize
                    Layout.preferredHeight: MenuStyle.spotifyCoverSize
                    padding: MenuStyle.spotifyInset
                    Image {
                        id: cover
                        anchors.fill: parent
                        source: SpotifyState.track ? SpotifyState.track.image : (root.lastTrack ? root.lastTrack.image : "")
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    Text {
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferFullHinting
                        anchors.centerIn: parent
                        visible: cover.status !== Image.Ready
                        font.family: MenuStyle.iconFont
                        font.pixelSize: MenuStyle.spotifyTileIcon
                        color: MenuStyle.bevelDark
                        text: ""
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 0
                    Repeater {
                        model: SpotifyState.track
                            ? [SpotifyState.track.name, SpotifyState.track.artists, SpotifyState.track.album]
                            : (root.lastTrack
                                ? ["Last played: " + root.lastTrack.name, root.lastTrack.sub, "Play carries on here"]
                                : ["Nothing playing", "Pick something below", ""])
                        Text {
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferFullHinting
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.family: index === 0 ? MenuStyle.titleFont : MenuStyle.bodyFont
                            font.pixelSize: MenuStyle.fontSize
                            font.bold: index === 0
                            color: index === 0 ? Config.colors.text : MenuStyle.bevelDark
                            text: modelData
                        }
                    }
                    // Where it plays; on another device (the phone) a button moves it here
                    RowLayout {
                        Layout.fillWidth: true
                        visible: SpotifyState.player !== null && SpotifyState.player.device !== ""
                        spacing: MenuStyle.gap
                        Text {
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferFullHinting
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.family: MenuStyle.bodyFont
                            font.pixelSize: MenuStyle.fontSize
                            color: MenuStyle.bevelDark
                            text: "on " + root.deviceName()
                        }
                        BevelButton {
                            visible: root.remote
                            text: "Play here"
                            glyph: ""
                            focusPolicy: Qt.NoFocus
                            onClicked: SpotifyState.playHere()
                        }
                    }
                    Item { Layout.fillHeight: true }
                }
            }

            // Seek bar (same height as the volume slider below): click to jump
            RowLayout {
                Layout.fillWidth: true
                visible: !root.lyricsMode
                spacing: MenuStyle.gap
                Text {
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferFullHinting
                    font.family: MenuStyle.bodyFont
                    font.pixelSize: MenuStyle.fontSize
                    color: Config.colors.text
                    text: root.clock(SpotifyState.progress)
                }
                SegmentBar {
                    id: seekBar
                    Layout.fillWidth: true
                    implicitHeight: MenuStyle.rowHeight + MenuStyle.gap
                    value: SpotifyState.track && SpotifyState.track.duration > 0 ? SpotifyState.progress / SpotifyState.track.duration : 0
                    // Glides between the once-a-second ticks instead of jumping
                    Behavior on value {
                        NumberAnimation { duration: MenuStyle.spotifyTickMs }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: SpotifyState.track !== null
                        cursorShape: Qt.PointingHandCursor
                        onReleased: mouse => SpotifyState.seek(Math.max(0, Math.min(1, mouse.x / width)) * SpotifyState.track.duration)
                    }
                }
                Text {
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferFullHinting
                    font.family: MenuStyle.bodyFont
                    font.pixelSize: MenuStyle.fontSize
                    color: Config.colors.text
                    text: root.clock(SpotifyState.track ? SpotifyState.track.duration : 0)
                }
            }

            Transport {
                Layout.fillWidth: true
                visible: !root.lyricsMode
                full: true
            }

            // Like, add to playlist, volume
            RowLayout {
                Layout.fillWidth: true
                visible: !root.lyricsMode
                spacing: MenuStyle.gap
                BevelButton {
                    glyph: SpotifyState.liked ? "" : ""
                    glyphColor: SpotifyState.liked ? MenuStyle.likedColor : "transparent"
                    enabled: SpotifyState.track !== null
                    focusPolicy: Qt.NoFocus
                    onClicked: SpotifyState.toggleLike()
                }
                BevelButton {
                    glyph: ""
                    checked: root.addMode
                    enabled: SpotifyState.track !== null
                    focusPolicy: Qt.NoFocus
                    onClicked: root.toggleAddMode()
                }
                Text {
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferFullHinting
                    font.family: MenuStyle.iconFont
                    font.pixelSize: MenuStyle.iconSize
                    color: Config.colors.text
                    text: ""
                }
                RetroSlider {
                    id: volumeSlider
                    Layout.fillWidth: true
                    from: 0
                    to: 100
                    stepSize: 1
                    enabled: SpotifyState.volume >= 0
                    // Every change (drag, click, release) goes straight to SpotifyState, which decides
                    // where it goes (PipeWire here, Spotify for another device) and what to show
                    onMoved: SpotifyState.setVolume(value)
                    onPressedChanged: {
                        if (!pressed)
                            SpotifyState.setVolume(value);
                    }
                    // Shows SpotifyState.volume, except while your hand is on the knob.
                    // RestoreNone: switching this off must never move the knob.
                    Binding on value {
                        when: !volumeSlider.pressed
                        value: Math.max(0, SpotifyState.volume)
                        restoreMode: Binding.RestoreNone
                    }
                }
            }

            // Spotify's own volume, while it isn't at 100: turning it up only ever happens on a click
            RowLayout {
                Layout.fillWidth: true
                visible: !root.lyricsMode && SpotifyState.ownVolume >= 0 && SpotifyState.ownVolume < 100
                spacing: MenuStyle.gap
                Text {
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferFullHinting
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.family: MenuStyle.bodyFont
                    font.pixelSize: MenuStyle.fontSize
                    color: MenuStyle.bevelDark
                    text: "Spotify's own volume: " + SpotifyState.ownVolume + "%"
                }
                BevelButton {
                    text: "Max"
                    focusPolicy: Qt.NoFocus
                    onClicked: SpotifyState.maxOwnVolume()
                }
            }

            MenuSeparator {
                Layout.fillWidth: true
                visible: !root.lyricsMode && !root.addMode
            }

            // Recent: the same tiles as the library grid, 4 per row; a click opens, the play button plays
            GridLayout {
                Layout.fillWidth: true
                columns: MenuStyle.spotifyGridColumns
                columnSpacing: 0
                rowSpacing: 0
                visible: !root.addMode && !root.lyricsMode && SpotifyState.recent.length > 0
                Repeater {
                    model: SpotifyState.recent
                    CoverTile {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: implicitHeight
                        entry: Object.assign({}, modelData, { pinned: root.pinned[modelData.uri] === true })
                        showSub: false
                        canPlay: true
                        onActivated: root.activate(modelData)
                        onPlayRequested: SpotifyState.play(modelData.kind === "liked" ? "liked" : modelData.uri)
                    }
                }
            }

            MenuSeparator {
                Layout.fillWidth: true
                visible: !root.addMode && !root.lyricsMode
            }

            // Tabs
            RowLayout {
                Layout.fillWidth: true
                spacing: MenuStyle.gap
                visible: !root.addMode && root.stack.length === 0
                Repeater {
                    model: [
                        { key: "library", text: "Library" },
                        { key: "liked", text: "Liked" },
                        { key: "lyrics", text: "Lyrics" }
                    ]
                    BevelButton {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        text: modelData.text
                        checked: root.tab === modelData.key
                        focusPolicy: Qt.NoFocus
                        onClicked: root.showTab(modelData.key)
                    }
                }
            }

            // Library chips, or an opened item's header (Back, title, Play) / the playlist picker's;
            // the view toggle sits at the end of whichever row is showing
            RowLayout {
                Layout.fillWidth: true
                spacing: MenuStyle.gap
                visible: root.addMode || root.stack.length > 0 || root.tab === "library"
                Repeater {
                    model: !root.addMode && root.stack.length === 0 && root.tab === "library" ? [
                        { key: "all", text: "All" },
                        { key: "playlist", text: "Playlists" },
                        { key: "artist", text: "Artists" },
                        { key: "album", text: "Albums" }
                    ] : []
                    BevelButton {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        text: modelData.text
                        checked: root.libraryKind === modelData.key
                        focusPolicy: Qt.NoFocus
                        onClicked: {
                            root.libraryKind = modelData.key;
                            root.setCursor(0);
                            root.focusKeys();
                        }
                    }
                }
                BevelButton {
                    visible: root.addMode || root.stack.length > 0
                    text: root.addMode ? "Cancel" : "Back"
                    glyph: ""
                    focusPolicy: Qt.NoFocus
                    onClicked: {
                        root.goBack();
                        root.focusKeys();
                    }
                }
                Text {
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferFullHinting
                    Layout.fillWidth: true
                    visible: root.addMode || root.stack.length > 0
                    elide: Text.ElideRight
                    font.family: MenuStyle.bodyFont
                    font.pixelSize: MenuStyle.fontSize
                    color: Config.colors.text
                    text: root.addMode ? "Add " + (root.addTarget ? root.addTarget.name : "") + " to:" : (root.view ? root.view.title : "")
                }
                BevelButton {
                    visible: !root.addMode && root.view !== null && root.view.kind !== "folder" && root.view.kind !== "artist"
                    text: "Play"
                    glyph: ""
                    focusPolicy: Qt.NoFocus
                    onClicked: SpotifyState.play(root.view.uri)
                }
                BevelButton {
                    visible: root.showViewToggle
                    glyph: SpotifyState.grid ? "" : ""
                    focusPolicy: Qt.NoFocus
                    onClicked: {
                        SpotifyState.grid = !SpotifyState.grid;
                        root.focusKeys();
                    }
                }
            }

            // An artist: one big Play (their songs in Spotify), then the discography summary
            ColumnLayout {
                Layout.fillWidth: true
                visible: !root.addMode && root.view !== null && root.view.kind === "artist"
                spacing: MenuStyle.gap
                BevelButton {
                    Layout.fillWidth: true
                    text: root.view ? "Play " + root.view.title : ""
                    glyph: "\ue037"
                    focusPolicy: Qt.NoFocus
                    onClicked: SpotifyState.play(root.view.uri)
                }
                Text {
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferFullHinting
                    Layout.fillWidth: true
                    visible: text !== ""
                    elide: Text.ElideRight
                    font.family: MenuStyle.bodyFont
                    font.pixelSize: MenuStyle.fontSize
                    color: MenuStyle.bevelDark
                    text: root.view && root.view.summary ? root.view.summary : ""
                }
            }

            SearchBox {
                id: filterInput
                Layout.fillWidth: true
                implicitHeight: MenuStyle.rowHeight + MenuStyle.gap
                visible: !root.lyricsMode
                placeholder: "Filter"
                onEdited: root.setCursor(0)
                onEscaped: {
                    if (!root.goBack())
                        root.closeCallback();
                }
                // Up / Down (and Left / Right in the grid) move, Enter opens, Shift+Enter plays,
                // Space plays / pauses while the filter is empty
                onKeyPressed: event => {
                    const cols = root.useGrid ? MenuStyle.spotifyGridColumnsLibrary : 1;
                    const empty = filterInput.text === "";
                    const cur = list.currentIndex;
                    if (event.key === Qt.Key_Down) {
                        root.setCursor(Math.min(root.items.length - 1, cur + cols));
                    } else if (event.key === Qt.Key_Up) {
                        root.setCursor(Math.max(0, cur - cols));
                    } else if (root.useGrid && empty && event.key === Qt.Key_Right) {
                        root.setCursor(Math.min(root.items.length - 1, cur + 1));
                    } else if (root.useGrid && empty && event.key === Qt.Key_Left) {
                        root.setCursor(Math.max(0, cur - 1));
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (event.modifiers & Qt.ShiftModifier)
                            root.playItem(root.items[cur]);
                        else
                            root.activate(root.items[cur], true);
                    } else if (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
                        const it = root.items[cur];
                        if (it && it.kind === "track")
                            root.songMenu = it;
                    } else if (event.key === Qt.Key_Space && empty) {
                        SpotifyState.togglePlay();
                    } else {
                        return;
                    }
                    event.accepted = true;
                }
            }

            // The list (or the lyrics)
            SunkenField {
                id: listArea
                Layout.fillWidth: true
                Layout.fillHeight: true
                padding: MenuStyle.spotifyInset
                clip: true

                NumberAnimation { id: listFade; target: listArea; property: "opacity"; from: 0; to: 1; duration: MenuStyle.animFade }

                Text {
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferFullHinting
                    anchors.centerIn: parent
                    width: parent.width - 2 * MenuStyle.pad
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    visible: root.lyricsMode && (Lyrics.lines.length === 0 || root.remote)
                    font.family: MenuStyle.bodyFont
                    font.pixelSize: MenuStyle.fontSize
                    color: MenuStyle.bevelDark
                    text: root.remote ? "Playing on " + root.deviceName() + ". Lyrics show while this PC plays: press Play here below."
                        : (Media.spotify === null ? "Lyrics follow this PC's player (the Spotify app or spotifyd); neither is running." : "No synced lyrics for this song")
                }

                // Lyrics: the current line sits on the accent bar, kept at the reading spot; click a line to jump there
                ListView {
                    id: lyricsView
                    anchors.fill: parent
                    visible: root.lyricsMode && !root.remote
                    model: Lyrics.lines
                    // Set from Lyrics.onIndexChanged below: a plain binding gets overwritten when the
                    // model changes, and then the view stops following the song
                    Connections {
                        target: Lyrics
                        function onIndexChanged() {
                            lyricsView.currentIndex = Lyrics.index;
                        }
                        function onLinesChanged() {
                            lyricsView.currentIndex = Lyrics.index;
                        }
                    }
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    highlightRangeMode: ListView.ApplyRange
                    preferredHighlightBegin: height * MenuStyle.lyricsAnchor - MenuStyle.rowHeight
                    preferredHighlightEnd: height * MenuStyle.lyricsAnchor + MenuStyle.rowHeight
                    highlightMoveDuration: MenuStyle.animScroll
                    highlightFollowsCurrentItem: true
                    // Room above and below so the first and last lines can reach the reading spot too
                    header: Item { width: 1; height: lyricsView.height * MenuStyle.lyricsAnchor - MenuStyle.rowHeight }
                    footer: Item { width: 1; height: lyricsView.height * (1 - MenuStyle.lyricsAnchor) - MenuStyle.rowHeight }
                    delegate: Rectangle {
                        id: lyricRow
                        required property int index
                        required property var modelData
                        readonly property bool current: index === Lyrics.index
                        width: lyricsView.width
                        height: lyricText.implicitHeight + MenuStyle.gap
                        color: current ? MenuStyle.selectBar : Qt.rgba(MenuStyle.selectBar.r, MenuStyle.selectBar.g, MenuStyle.selectBar.b, 0)
                        Behavior on color {
                            ColorAnimation { duration: MenuStyle.animHover }
                        }
                        Text {
                            id: lyricText
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferFullHinting
                            anchors.verticalCenter: parent.verticalCenter
                            x: MenuStyle.pad
                            width: parent.width - 2 * MenuStyle.pad
                            wrapMode: Text.Wrap
                            horizontalAlignment: Text.AlignHCenter
                            font.family: MenuStyle.bodyFont
                            font.pixelSize: MenuStyle.lyricsFontSize
                            color: lyricRow.current ? MenuStyle.selectText : (lyricRow.index < Lyrics.index ? MenuStyle.bevelDark : Config.colors.text)
                            text: lyricRow.modelData.text === "" ? "♪" : lyricRow.modelData.text
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.seekLyric(lyricRow.modelData.t)
                        }
                    }
                }

                Text {
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferFullHinting
                    anchors.centerIn: parent
                    width: parent.width - 2 * MenuStyle.pad
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    visible: !root.lyricsMode && root.items.length === 0
                    font.family: MenuStyle.bodyFont
                    font.pixelSize: MenuStyle.fontSize
                    color: MenuStyle.bevelDark
                    text: root.emptyText()
                }

                // Rows: the accent bar spans the whole row; the play button sits inside it, on hover
                // or when selected (songs play on click, so they have none)
                ListView {
                    id: list
                    anchors.fill: parent
                    visible: !root.lyricsMode && !root.useGrid
                    model: root.items
                    currentIndex: 0
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                    delegate: Item {
                        id: row
                        required property int index
                        required property var modelData
                        readonly property bool isTrack: modelData.kind === "track"
                        readonly property bool sel: index === list.currentIndex
                        readonly property bool showPlay: !root.addMode && !isTrack && modelData.kind !== "folder" && (rowHover.hovered || sel)
                        width: list.width
                        height: MenuStyle.spotifyRowHeight

                        HoverHandler {
                            id: rowHover
                        }
                        // Right-click a song: its actions (queue, add to playlist, like) in the status line
                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            enabled: row.isTrack && !root.addMode
                            onTapped: {
                                root.setCursor(row.index);
                                root.songMenu = row.modelData;
                            }
                        }
                        MenuRow {
                            anchors.fill: parent
                            focusPolicy: Qt.NoFocus
                            rightPadding: row.showPlay ? MenuStyle.pad + playButton.width + MenuStyle.gap : MenuStyle.pad
                            selected: row.sel
                            text: row.modelData.name
                            marked: row.modelData.pinned === true
                            markGlyph: ""
                            subtext: row.isTrack ? row.modelData.sub + "  " + root.clock(row.modelData.duration) : row.modelData.sub
                            iconSource: row.modelData.image || ""
                            glyph: root.kindGlyph(row.modelData.kind)
                            onClicked: {
                                root.setCursor(row.index);
                                root.activate(row.modelData);
                            }
                        }
                        BevelButton {
                            id: playButton
                            anchors.right: parent.right
                            anchors.rightMargin: MenuStyle.pad
                            anchors.verticalCenter: parent.verticalCenter
                            visible: row.showPlay
                            glyph: ""
                            focusPolicy: Qt.NoFocus
                            onClicked: root.playItem(row.modelData)
                        }
                    }
                    ScrollIndicator.vertical: ScrollIndicator {
                        active: list.moving
                    }
                }

                // The same items as cover tiles
                GridView {
                    id: grid
                    anchors.fill: parent
                    visible: !root.lyricsMode && root.useGrid
                    model: root.items
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    cellWidth: width / MenuStyle.spotifyGridColumnsLibrary
                    cellHeight: gridProbe.implicitHeight
                    currentIndex: list.currentIndex
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, GridView.Contain)
                    CoverTile {
                        id: gridProbe
                        visible: false
                        width: grid.cellWidth
                    }
                    delegate: CoverTile {
                        required property int index
                        required property var modelData
                        width: grid.cellWidth
                        height: grid.cellHeight
                        entry: modelData
                        selected: index === list.currentIndex
                        canPlay: !root.addMode && modelData.kind !== "folder"
                        onActivated: {
                            root.setCursor(index);
                            root.activate(modelData);
                        }
                        onPlayRequested: root.playItem(modelData)
                    }
                    ScrollIndicator.vertical: ScrollIndicator {
                        active: grid.moving
                    }
                }
            }

            // Lyrics: a slim transport strip stays, so the drawer is never a dead end
            Transport {
                Layout.fillWidth: true
                visible: root.lyricsMode
                full: false
            }

            // Status: errors / notes, and Log out (with a confirm)
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
                    color: SpotifyState.error !== "" && !root.songMenu ? Config.colors.urgent : (root.songMenu ? Config.colors.text : MenuStyle.bevelDark)
                    text: root.songMenu ? root.songMenu.name
                        : root.confirmLogout ? "Log out of Spotify here?" : (SpotifyState.error !== "" ? SpotifyState.error : root.note)
                }
                BevelButton {
                    visible: root.songMenu !== null
                    text: "Queue"
                    glyph: "\ue03c"
                    focusPolicy: Qt.NoFocus
                    onClicked: {
                        const s = root.songMenu;
                        root.songMenu = null;
                        SpotifyState.queue(s.uri, ok => root.note = ok ? s.name + " plays next" : "Couldn't queue " + s.name);
                    }
                }
                BevelButton {
                    visible: root.songMenu !== null
                    glyph: "\ue03b"
                    focusPolicy: Qt.NoFocus
                    onClicked: {
                        const s = root.songMenu;
                        root.toggleAddMode({ uri: s.uri, name: s.name });
                    }
                }
                BevelButton {
                    visible: root.songMenu !== null
                    glyph: "\ue87d"
                    glyphColor: MenuStyle.likedColor
                    focusPolicy: Qt.NoFocus
                    onClicked: {
                        const s = root.songMenu;
                        root.songMenu = null;
                        SpotifyState.likeSong(s.uri, ok => root.note = ok ? "Liked " + s.name : "Couldn't like " + s.name);
                    }
                }
                BevelButton {
                    visible: root.songMenu !== null
                    glyph: "\ue5cd"
                    focusPolicy: Qt.NoFocus
                    onClicked: root.songMenu = null
                }
                BevelButton {
                    visible: root.confirmLogout && !root.songMenu
                    text: "Yes"
                    focusPolicy: Qt.NoFocus
                    onClicked: {
                        root.confirmLogout = false;
                        SpotifyState.logout();
                    }
                }
                BevelButton {
                    visible: root.confirmLogout && !root.songMenu
                    text: "No"
                    focusPolicy: Qt.NoFocus
                    onClicked: root.confirmLogout = false
                }
                BevelButton {
                    visible: !root.confirmLogout && !root.songMenu
                    text: "Log out"
                    focusPolicy: Qt.NoFocus
                    onClicked: root.confirmLogout = true
                }
            }
        }
    }

    // Previous / play / next (+ shuffle / repeat when full, + Play here on another device)
    component Transport: RowLayout {
        property bool full: true
        spacing: MenuStyle.gap
        BevelButton {
            Layout.fillWidth: true
            visible: parent.full
            glyph: ""
            checked: SpotifyState.player !== null && SpotifyState.player.shuffle
            enabled: SpotifyState.player !== null
            focusPolicy: Qt.NoFocus
            onClicked: SpotifyState.toggleShuffle()
        }
        BevelButton {
            Layout.fillWidth: true
            glyph: ""
            focusPolicy: Qt.NoFocus
            onClicked: SpotifyState.previous()
        }
        BevelButton {
            Layout.fillWidth: true
            glyph: SpotifyState.player && SpotifyState.player.playing ? "" : ""
            focusPolicy: Qt.NoFocus
            onClicked: SpotifyState.togglePlay()
        }
        BevelButton {
            Layout.fillWidth: true
            glyph: ""
            focusPolicy: Qt.NoFocus
            onClicked: SpotifyState.next()
        }
        BevelButton {
            Layout.fillWidth: true
            visible: parent.full
            glyph: SpotifyState.player && SpotifyState.player.repeat === "track" ? "" : ""
            checked: SpotifyState.player !== null && SpotifyState.player.repeat !== "off"
            enabled: SpotifyState.player !== null
            focusPolicy: Qt.NoFocus
            onClicked: SpotifyState.cycleRepeat()
        }
        BevelButton {
            visible: !parent.full && SpotifyState.player !== null && !SpotifyState.local
            text: "Play here"
            glyph: ""
            focusPolicy: Qt.NoFocus
            onClicked: SpotifyState.playHere()
        }
    }

    // --- behaviour ---

    function focusLeft() {
        if (root.visible && Date.now() - root.shownAt > MenuStyle.spotifyClickGuard)
            root.closeCallback();
    }

    function deviceName() {
        if (!SpotifyState.player)
            return "";
        return SpotifyState.local ? "This PC" : SpotifyState.player.device;
    }

    function kindGlyph(kind) {
        switch (kind) {
        case "track": return "";
        case "artist": return "";
        case "album": return "";
        case "folder": return "";
        case "liked": return "";
        default: return "";
        }
    }

    // Lyric click: MPRIS seek when the app runs (instant), else the API
    function seekLyric(seconds) {
        const m = SpotifyState.mpris;
        if (m && m.canSeek)
            m.position = seconds;
        else
            SpotifyState.seek(seconds * 1000);
    }

    function clock(ms) {
        const s = Math.floor((ms || 0) / 1000);
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }

    function emptyText() {
        if (filterInput.text.trim() !== "" && root.baseItems.length > 0)
            return "No matches";
        if (root.addMode)
            return SpotifyState.loading.playlists ? "Loading..." : "No playlists of your own";
        if (root.view) {
            if (root.view.kind === "liked")
                return SpotifyState.loading.liked ? "Loading..." : "No liked songs";
            if (root.view.loading)
                return "Loading...";
            if (root.view.kind === "artist")
                return "Spotify didn't list this artist's albums. Play above still works.";
            if (root.view.blocked)
                return root.view.kind === "folder" ? "Open the Spotify app once (with this panel open) to load what's in this folder."
                    : "Spotify only lists the songs of playlists you own. Press Play to start it.";
            return "Empty";
        }
        if (root.tab === "liked")
            return SpotifyState.loading.liked ? "Loading..." : "No liked songs";
        const need = root.libraryKind === "all" ? ["playlists", "artists", "albums"] : [root.libraryKind + "s"];
        return need.some(k => SpotifyState.loading[k]) ? "Loading..." : "Empty";
    }

    function setCursor(i) {
        list.currentIndex = Math.max(0, i);
    }

    // Keyboard goes to the filter box where there is one, else to the key catcher (Lyrics, login)
    function focusKeys() {
        if (!root.visible)
            return;
        if (SpotifyState.loggedIn && !root.lyricsMode)
            filterInput.focusInput();
        else if (!SpotifyState.loggedIn && clientInput.visible)
            clientInput.focusInput();
        else
            keyCatcher.forceActiveFocus();
    }

    function loadForTab(force) {
        if (root.tab === "library")
            ["playlists", "artists", "albums"].forEach(k => SpotifyState.loadList(k, force));
        else if (root.tab === "liked")
            SpotifyState.loadList("liked", force);
    }

    function showTab(key) {
        root.tab = key;
        root.stack = [];
        filterInput.text = "";
        root.setCursor(0);
        root.loadForTab(false);
        root.focusKeys();
    }

    // Pick a playlist for a song: `target` { uri, name }, or the one playing
    function toggleAddMode(target) {
        if (!root.addMode)
            root.addTarget = target || (SpotifyState.track ? { uri: SpotifyState.track.uri, name: SpotifyState.track.name } : null);
        root.songMenu = null;
        root.addMode = !root.addMode;
        filterInput.text = "";
        root.setCursor(0);
        if (root.addMode)
            SpotifyState.loadList("playlists");
        root.focusKeys();
    }

    function saveClient() {
        SpotifyState.setClient(clientInput.text.trim());
        root.editClient = false;
    }

    // Library tab: Spotify's Your Library (pins first, the app's order) from the extension, else
    // built from the API lists (no pins, no folders). The chip narrows it to one kind.
    function libraryRows() {
        const known = SpotifyState.lists.playlists || [];
        // Playlists: your folders and playlists in Spotify's order (the folder tree), Liked Songs first
        // (with text in the filter box it's the flat list, so the search reaches inside folders)
        if (root.libraryKind === "playlist" && SpotifyState.folderTree && filterInput.text.trim() === "")
            return [root.likedRow].concat(root.folderRows(SpotifyState.folderTree, true));
        let rows;
        if (SpotifyState.libraryItems) {
            rows = SpotifyState.libraryItems.map(it => {
                const kind = it.type === "collection" ? "liked" : it.type;
                const row = { kind: kind, uri: kind === "liked" ? "liked" : it.uri, name: it.name, sub: it.sub, image: it.image, pinned: it.pinned, openable: true };
                if (kind === "playlist") {
                    const k = known.find(p => p.uri === it.uri);
                    row.openable = k ? k.openable : false;
                    if (!row.image && k)
                        row.image = k.image;
                }
                if (kind === "folder")
                    row.children = root.findFolder(SpotifyState.folderTree || [], it.uri);
                return row;
            });
        } else {
            rows = [root.likedRow].concat(known, SpotifyState.lists.artists || [], SpotifyState.lists.albums || []);
        }
        if (root.libraryKind !== "all")
            rows = rows.filter(r => r.kind === root.libraryKind || (root.libraryKind === "playlist" && (r.kind === "folder" || r.kind === "liked")));
        // pins first, otherwise keep Spotify's order
        return rows.filter(r => r.pinned).concat(rows.filter(r => !r.pinned));
    }

    function findFolder(nodes, uri) {
        for (const n of nodes) {
            if (n.type !== "folder")
                continue;
            if (n.uri === uri)
                return n.items;
            const inner = root.findFolder(n.items, uri);
            if (inner)
                return inner;
        }
        return null;
    }

    // Rows for one level of the folder tree. Playlists take their cover / owner / openable from the
    // API list; at the top level, playlists missing from the tree (new ones) are added at the end.
    function folderRows(nodes, top) {
        const known = SpotifyState.lists.playlists || [];
        const rows = [];
        const count = n => n.items.reduce((c, x) => c + (x.type === "folder" ? count(x) : 1), 0);
        for (const n of nodes) {
            if (n.type === "folder")
                rows.push({ kind: "folder", uri: n.uri, name: n.name, sub: "Folder · " + count(n), image: "", openable: true, children: n.items, pinned: root.pinned[n.uri] === true });
            else
                rows.push(known.find(p => p.uri === n.uri) || { kind: "playlist", uri: n.uri, name: n.name, sub: "", image: "", openable: false });
        }
        if (top) {
            const inTree = {};
            const walk = list => list.forEach(x => x.type === "folder" ? walk(x.items) : inTree[x.uri] = true);
            walk(nodes);
            for (const p of known)
                if (!inTree[p.uri])
                    rows.push(p);
        }
        return rows;
    }

    // Play without opening (the play buttons, Shift+Enter)
    function playItem(item) {
        if (!item || item.kind === "folder")
            return;
        SpotifyState.play(item.kind === "liked" ? "liked" : item.uri);
    }

    // Click / Enter on a row or tile. fromKeys: Enter (the double-click guard only applies to clicks)
    function activate(item, fromKeys) {
        if (!item)
            return;
        if (!fromKeys && Date.now() - root.openedAt < MenuStyle.spotifyClickGuard)
            return;
        if (root.addMode) {
            if (!root.addTarget) {
                root.note = "Nothing playing to add";
            } else {
                const name = item.name, song = root.addTarget.name;
                SpotifyState.addToPlaylist(item.uri, root.addTarget.uri, ok => root.note = ok ? "Added " + song + " to " + name : "Couldn't add to " + name);
            }
            root.toggleAddMode();
            return;
        }
        if (item.kind === "track") {
            const ctx = root.view ? root.view.uri : (root.tab === "liked" ? "liked" : "");
            SpotifyState.play(ctx || item.uri, ctx ? item.uri : "");
            return;
        }
        if (item.kind === "folder") {
            root.push({ title: item.name, uri: item.uri, kind: "folder", items: item.children ? root.folderRows(item.children, false) : [], loading: false, blocked: !item.children });
            return;
        }
        if (item.kind === "liked") {
            SpotifyState.loadList("liked");
            root.push({ title: "Liked Songs", uri: "liked", kind: "liked", items: [], loading: false });
            return;
        }
        if (item.openable === false) {
            root.push({ title: item.name, uri: item.uri, kind: item.kind, items: [], loading: false, blocked: true });
            return;
        }
        root.push({ title: item.name, uri: item.uri, kind: item.kind, items: [], loading: true });
        const depth = root.stack.length;
        const uri = item.uri;
        SpotifyState.open(uri, v => {
            // Only fill the view it was opened for (you may have gone back and opened something else)
            if (root.stack.length !== depth || root.stack[depth - 1].uri !== uri)
                return;
            const s = root.stack.slice();
            s[depth - 1] = Object.assign({}, s[depth - 1], { items: v ? v.items : [], summary: v && v.summary ? v.summary : "", loading: false });
            root.stack = s;
        });
    }

    function push(entry) {
        entry.fromIndex = list.currentIndex;
        entry.fromFilter = filterInput.text;
        root.openedAt = Date.now();
        root.stack = root.stack.concat([entry]);
        filterInput.text = "";
        root.setCursor(0);
        root.focusKeys();
    }

    // Back one step (to the row you opened it from); false when there was nothing to go back from
    function goBack() {
        if (root.songMenu) {
            root.songMenu = null;
            return true;
        }
        if (root.addMode) {
            root.toggleAddMode();
            return true;
        }
        if (root.stack.length > 0) {
            const top = root.stack[root.stack.length - 1];
            root.stack = root.stack.slice(0, -1);
            filterInput.text = top.fromFilter || "";
            Qt.callLater(() => root.setCursor(top.fromIndex || 0));
            return true;
        }
        return false;
    }

    function openMenu() {
        root.addMode = false;
        root.stack = [];
        root.note = "";
        root.confirmLogout = false;
        root.editClient = false;
        filterInput.text = "";
        root.shownAt = Date.now();
        root.visible = true;
        root.loadForTab(false);
        root.focusKeys();
    }

    function closeMenu() {
        root.visible = false;
    }
}
