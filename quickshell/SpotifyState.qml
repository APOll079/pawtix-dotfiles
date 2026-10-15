pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Spotify Web API state for the Spotify panel (popups/SpotifyPanel.qml). Everything goes through
// scripts/spotify.py (login, tokens, requests); tokens and the client ID live in Quickshell's state
// dir ("spotify/"). While the panel is open the player state is polled
// every MenuStyle.spotifyPollMs; the progress bar ticks locally in between. Play / pause / next /
// previous go through MPRIS (Media.spotify) when the Spotify app runs: instant and no API call.
Singleton {
    id: root

    readonly property string stateDir: Quickshell.statePath("spotify")
    property bool active: false            // the panel is open

    property bool configured: false
    property bool loggedIn: false
    property bool loggingIn: false
    property string error: ""

    property var player: null              // spotify.py `state`: playing, shuffle, repeat, volume, track, ...
    property real progress: 0              // ms, ticks locally between polls
    property bool liked: false
    property string likedUri: ""

    property var recent: []
    property var lists: ({})               // playlists / artists / albums / liked: arrays, cached per session
    property var loading: ({})

    readonly property var track: root.player ? root.player.track : null
    // This PC (the app or spotifyd) is the one playing: MPRIS controls it directly. Otherwise
    // (the phone, another device) every control goes through the API to that device.
    readonly property bool local: root.player !== null && root.player.local === true
    readonly property var mpris: root.local ? Media.spotify : null
    property var lastPlayed: null          // { track, context } while nothing plays anywhere

    // --- running the helper ---

    Component {
        id: runner
        Process {
            id: proc
            property var callback: null
            property bool handled: false
            function finish(text) {
                if (proc.handled)
                    return;
                proc.handled = true;
                let value = null;
                try {
                    value = JSON.parse(text);
                } catch (e) {
                    value = { error: "spotify.py gave no answer" };
                }
                if (value && value.error !== undefined) {
                    root.error = value.error;
                    if (value.status === 401)
                        root.loggedIn = false;
                    if (proc.callback)
                        proc.callback(null, value.error);
                } else if (proc.callback) {
                    proc.callback(value, "");
                }
                Qt.callLater(proc.destroy);
            }
            // Only the output stream decides: it always finishes (empty if the helper crashed), and
            // big answers (the playlist list) can arrive after the process has already exited
            stdout: StdioCollector {
                onStreamFinished: proc.finish(text)
            }
        }
    }

    // Every command goes down the long-running helper while it runs (no process start, one open
    // connection: instant); login, and anything before the helper is up, runs as a one-off process.
    function run(args, callback) {
        if (serverReady && args[0] !== "login") {
            root.serveId += 1;
            root.pending[root.serveId] = callback || null;
            server.write(JSON.stringify({ id: root.serveId, cmd: args[0], args: args.slice(1) }) + "\n");
            return;
        }
        const p = runner.createObject(root, { callback: callback || null });
        p.command = ["python3", "-I", Quickshell.shellDir + "/scripts/spotify.py", "--state", root.stateDir].concat(args);
        p.running = true;
    }

    // --- account ---

    function checkStatus() {
        root.run(["status"], (v, err) => {
            if (!v)
                return;
            root.configured = v.configured;
            root.loggedIn = v.loggedIn;
            if (root.loggedIn && root.active)
                root.refreshAll();
        });
    }

    function setClient(id) {
        root.error = "";
        root.run(["set-client", id], v => {
            if (v)
                root.checkStatus();
        });
    }

    function login() {
        root.error = "";
        root.loggingIn = true;
        root.run(["login"], v => {
            root.loggingIn = false;
            if (v)
                root.checkStatus();
        });
    }

    function logout() {
        root.run(["logout"], () => {
            root.player = null;
            root.recent = [];
            root.lists = {};
            root.checkStatus();
        });
    }

    // --- data ---

    function refreshAll() {
        root.error = "";
        root.refreshState();
        root.run(["last"], v => root.lastPlayed = v);
        root.run(["recent"], v => {
            if (v)
                root.recent = v;
        });
    }

    function refreshState() {
        if (!root.loggedIn)
            return;
        root.run(["state"], v => {
            root.player = v;
            root.progress = v ? v.progress : 0;
            const uri = v && v.track ? v.track.uri : "";
            if (uri !== root.likedUri) {
                root.likedUri = uri;
                root.liked = false;
                if (uri !== "")
                    root.run(["liked", uri], l => root.liked = l === true);
            }
        });
    }

    // playlists | artists | albums | liked
    function loadList(kind, force) {
        if ((root.lists[kind] && !force) || root.loading[kind])
            return;
        root.setLoading(kind, true);
        root.run([kind === "liked" ? "liked-tracks" : kind], v => {
            root.setLoading(kind, false);
            if (!v)
                return;
            const l = Object.assign({}, root.lists);
            l[kind] = v;
            root.lists = l;
        });
    }

    function setLoading(kind, on) {
        const l = Object.assign({}, root.loading);
        l[kind] = on;
        root.loading = l;
    }

    function open(uri, callback) {
        root.run(["open", uri], v => callback(v));
    }

    // --- control ---

    function after(args) {
        root.run(args, () => refreshSoon.restart());
    }

    function play(context, trackUri) {
        root.after(["play", context].concat(trackUri ? [trackUri] : []));
    }

    // Move playback from the phone / another device to this PC; the song carries on where it was
    function playHere() {
        root.after(["transfer"]);
    }

    function togglePlay() {
        const m = root.mpris;
        if (m && m.canTogglePlaying) {
            m.togglePlaying();
            if (root.player)
                root.player = Object.assign({}, root.player, { playing: !root.player.playing });
            refreshSoon.restart();
        } else {
            root.after([root.player && root.player.playing ? "pause" : "resume"]);
        }
    }

    function next() {
        const m = root.mpris;
        if (m && m.canGoNext) {
            m.next();
            refreshSoon.restart();
        } else {
            root.after(["next"]);
        }
    }

    function previous() {
        const m = root.mpris;
        if (m && m.canGoPrevious) {
            m.previous();
            refreshSoon.restart();
        } else {
            root.after(["prev"]);
        }
    }

    function seek(ms) {
        root.progress = ms;
        root.after(["seek", String(Math.round(ms))]);
    }

    function toggleShuffle() {
        if (!root.player)
            return;
        const on = !root.player.shuffle;
        root.player = Object.assign({}, root.player, { shuffle: on });
        root.after(["shuffle", on ? "on" : "off"]);
    }

    // off -> context (all) -> track (one) -> off
    function cycleRepeat() {
        if (!root.player)
            return;
        const nxt = { off: "context", context: "track", track: "off" }[root.player.repeat] || "off";
        root.player = Object.assign({}, root.player, { repeat: nxt });
        root.after(["repeat", nxt]);
    }

    // --- Your Library (from the Spicetify extension) ---
    // Spotify's "Your Library" in the app's order with pins, sent by qs-folders.js and saved by
    // `spotify.py serve` as library.json. Null until the extension ever delivered.
    property var libraryItems: null
    FileView {
        id: libraryFile
        path: root.stateDir + "/library.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const t = JSON.parse(text());
                root.libraryItems = Array.isArray(t.items) && t.items.length > 0 ? t.items : null;
            } catch (e) {
                root.libraryItems = null;
            }
        }
    }

    // Grid or rows in the library tabs, remembered
    property alias grid: viewAdapter.grid
    FileView {
        path: Quickshell.statePath("spotify-view.json")
        printErrors: false
        onAdapterUpdated: writeAdapter()
        onLoadFailed: error => {
            if (error == FileViewError.FileNotFound)
                writeAdapter();
        }
        JsonAdapter {
            id: viewAdapter
            property bool grid: false
        }
    }

    // --- playlist folders ---
    // Spotify's API has no folders; the Spicetify extension qs-folders.js sends the app's folder
    // tree to `spotify.py serve`, which saves it as folders.json here. Null until it ever did.
    property var folderTree: null
    FileView {
        id: folderFile
        path: root.stateDir + "/folders.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const t = JSON.parse(text());
                root.folderTree = Array.isArray(t.items) && t.items.length > 0 ? t.items : null;
            } catch (e) {
                root.folderTree = null;
            }
        }
    }

    // --- volume ---
    // Two different volumes, picked by where it plays:
    // - this PC (spotifyd or the app): the player's own PipeWire stream, like the per-app rows in
    //   the side panel. Instant, no network, and it reads back from PipeWire.
    // - another device (the phone): Spotify Connect volume, sent down the long-running helper
    //   (`spotify.py serve`, one open connection) at most every spotifyVolumeStep ms while dragging.
    // `volume` is what the slider shows: your value while you change it and until the source
    // reports the same number back (or the hold runs out), else the source's value.

    // This PC's player stream in PipeWire (spotifyd / the Spotify app)
    // (Never with the test fixture: a scratch run must not touch the real audio streams.)
    readonly property bool testMode: (Quickshell.env("SPOTIFY_FIXTURE") || "") !== ""
    // Only the stream of the player that is actually playing: spotifyd's when spotifyd plays,
    // the app's otherwise (both may be running)
    readonly property bool daemonPlays: root.player !== null && root.player.device === "Desktop (spotifyd)"
    readonly property var localStreams: root.testMode ? [] : Pipewire.nodes.values.filter(n => {
        if (!n.isStream || !n.properties || n.properties["media.class"] !== "Stream/Output/Audio")
            return false;
        const bin = (n.properties["application.process.binary"] || "").toLowerCase();
        return root.daemonPlays ? bin === "spotifyd" : (bin === "spotify" || (bin !== "spotifyd" && /^spotify/i.test(n.properties["application.name"] || "")));
    })
    readonly property var localStream: root.localStreams.find(n => n.audio) || null
    readonly property bool localVolume: root.local && root.localStream !== null

    PwObjectTracker {
        objects: Pipewire.nodes.values.filter(n => n.isStream)
    }

    readonly property int sourceVolume: root.localVolume
        ? Math.round(root.localStream.audio.volume * 100)
        : (root.player && root.player.volume !== null && root.player.volume !== undefined ? root.player.volume : -1)
    property int pendingVolume: -1         // set by the slider, cleared once the source agrees
    readonly property int volume: root.pendingVolume >= 0 ? root.pendingVolume : root.sourceVolume

    onSourceVolumeChanged: {
        if (root.pendingVolume >= 0 && root.sourceVolume === root.pendingVolume && !volumeHold.running)
            root.pendingVolume = -1;
    }

    // Spotify's own volume stage (the app's slider / spotifyd's), shown under our slider while this PC
    // plays and it isn't at 100. The panel never changes it by itself (an automatic merge made
    // things louder once): only the Max button does, because you clicked it.
    readonly property int ownVolume: root.localVolume && root.player.volume !== null && root.player.volume !== undefined ? root.player.volume : -1
    function maxOwnVolume() {
        root.serve("volume", [100]);
        if (root.player)
            root.player = Object.assign({}, root.player, { volume: 100 });
    }

    function setVolume(pct) {
        const v = Math.max(0, Math.min(100, Math.round(pct)));
        root.pendingVolume = v;
        volumeHold.restart();
        if (root.localVolume) {
            for (const n of root.localStreams)
                if (n.audio)
                    n.audio.volume = v / 100;
            return;
        }
        volumeThrottle.value = v;
        if (!volumeThrottle.running) {
            volumeThrottle.sent = v;
            root.serve("volume", [v]);
            volumeThrottle.start();
        }
    }

    // --- the long-running helper ---
    property int serveId: 0
    property var pending: ({})             // request id -> callback
    property bool serverReady: false
    function serve(cmd, args) {
        root.run([cmd].concat(args || []));
    }

    // An answer from the helper: same handling as a one-off run (errors, 401 = logged out)
    function answer(r) {
        const cb = root.pending[r.id];
        delete root.pending[r.id];
        if (r.error !== undefined) {
            root.error = r.error;
            if (r.status === 401)
                root.loggedIn = false;
            if (cb)
                cb(null, r.error);
        } else if (cb) {
            cb(r.result, "");
        }
    }

    Process {
        id: server
        command: ["python3", "-I", Quickshell.shellDir + "/scripts/spotify.py", "--state", root.stateDir, "serve"]
        running: root.active && root.loggedIn
        stdinEnabled: true
        onStarted: root.serverReady = true
        // Stopped (panel closed / crash): answer whatever was still waiting, so nothing stays "Loading..."
        onExited: {
            root.serverReady = false;
            const waiting = root.pending;
            root.pending = {};
            for (const id in waiting)
                if (waiting[id])
                    waiting[id](null, "helper stopped");
        }
        stdout: SplitParser {
            onRead: line => {
                let r = null;
                try {
                    r = JSON.parse(line);
                } catch (e) {
                    return;
                }
                if (r.event === "folders")
                    folderFile.reload();
                else if (r.event === "library")
                    libraryFile.reload();
                else if (r.id !== undefined)
                    root.answer(r);
            }
        }
    }

    function toggleLike() {
        if (!root.track)
            return;
        const on = !root.liked;
        root.liked = on;
        root.run([on ? "like" : "unlike", root.track.uri], v => {
            if (!v)
                root.liked = !on;
            const l = Object.assign({}, root.lists);
            delete l.liked;
            root.lists = l;
        });
    }

    // Add a song (default: the one playing) to one of your playlists
    function addToPlaylist(playlistUri, trackUri, callback) {
        const uri = trackUri || (root.track ? root.track.uri : "");
        if (!uri)
            return;
        root.run(["add", playlistUri, uri], v => callback(v !== null));
    }

    // Put a song in the queue (plays next)
    function queue(uri, callback) {
        root.run(["queue", uri], v => callback && callback(v !== null));
    }

    // Like any song (the heart button likes the one playing)
    function likeSong(uri, callback) {
        root.run(["like", uri], v => {
            if (v !== null && root.track && root.track.uri === uri)
                root.liked = true;
            const l = Object.assign({}, root.lists);
            delete l.liked;
            root.lists = l;
            if (callback)
                callback(v !== null);
        });
    }

    // --- timers ---

    onActiveChanged: {
        if (active) {
            root.checkStatus();
            // The files may have appeared since (a watch only sees files that existed)
            folderFile.reload();
            libraryFile.reload();
        }
    }

    Timer {
        interval: MenuStyle.spotifyPollMs
        running: root.active && root.loggedIn
        repeat: true
        onTriggered: root.refreshState()
    }

    Timer {
        interval: MenuStyle.spotifyTickMs
        running: root.active && root.player !== null && root.player.playing
        repeat: true
        onTriggered: {
            if (root.track)
                root.progress = Math.min(root.track.duration, root.progress + MenuStyle.spotifyTickMs);
        }
    }

    Timer {
        id: refreshSoon
        interval: 400
        onTriggered: root.refreshState()
    }

    // After the last change, the slider keeps your value at least this long
    Timer {
        id: volumeHold
        interval: MenuStyle.spotifyVolumeHold
        onTriggered: {
            if (root.sourceVolume === root.pendingVolume || root.sourceVolume < 0)
                root.pendingVolume = -1;
            else
                giveUp.restart();
        }
    }

    // The source never agreed (e.g. the device refused): show its real value again
    Timer {
        id: giveUp
        interval: MenuStyle.spotifyVolumeHold
        onTriggered: root.pendingVolume = -1
    }

    Timer {
        id: volumeThrottle
        property int value: 0
        property int sent: -1
        interval: MenuStyle.spotifyVolumeStep
        onTriggered: {
            if (value !== sent) {
                sent = value;
                root.serve("volume", [value]);
                start();
            }
        }
    }
}
