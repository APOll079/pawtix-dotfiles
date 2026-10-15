pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Synced lyrics for the current Spotify track, from LRCLIB (lrclib.net, free, no key).
// Looks up the exact track first (artist, title, album, duration), then falls back to a search.
// `line` is the lyric at Spotify's current MPRIS position, or "" (no lyrics, a gap, paused).
Singleton {
    id: root

    readonly property var player: Media.spotify
    readonly property string key: player && player.trackTitle !== "" ? player.trackArtist + "\n" + player.trackTitle : ""

    property var lines: []        // [{ t: seconds, text }], sorted
    property string line: ""
    property bool fast: false     // the Spotify panel shows the lyrics: tick faster
    property int index: -1        // position of `line` in `lines` (-1 before the first line)
    property var cache: ({})      // key -> lines ([] = none found)

    onKeyChanged: load()
    Component.onCompleted: load()

    function load() {
        root.lines = [];
        root.line = "";
        root.index = -1;
        if (root.key === "")
            return;
        if (root.key in root.cache) {
            root.lines = root.cache[root.key];
            return;
        }
        // One request at a time; when it finishes, onExited picks up the newer track
        if (fetch.running)
            return;
        fetch.pendingKey = root.key;
        fetch.stage = "get";
        const q = "artist_name=" + encodeURIComponent(root.player.trackArtist)
            + "&track_name=" + encodeURIComponent(root.player.trackTitle)
            + "&album_name=" + encodeURIComponent(root.player.trackAlbum)
            + "&duration=" + Math.round(root.player.length);
        fetch.run("https://lrclib.net/api/get?" + q);
    }

    // "[mm:ss.xx] text" lines -> [{ t, text }]
    function parse(lrc) {
        const out = [];
        for (const raw of lrc.split("\n")) {
            const m = raw.match(/^\[(\d+):(\d+(?:\.\d+)?)\]\s?(.*)$/);
            if (m)
                out.push({ t: Number(m[1]) * 60 + Number(m[2]), text: m[3].trim() });
        }
        return out.sort((a, b) => a.t - b.t);
    }

    function done(found) {
        root.cache[fetch.pendingKey] = found;
        if (fetch.pendingKey === root.key)
            root.lines = found;
    }

    Process {
        id: fetch
        property string pendingKey: ""
        property string stage: "get"
        property bool searchNext: false
        function run(url) {
            command = ["curl", "-s", "--max-time", "8", "-A", "qs-test lyrics (quickshell)", url];
            running = true;
        }
        function searchUrl() {
            const p = root.player;
            return "https://lrclib.net/api/search?artist_name=" + encodeURIComponent(p.trackArtist)
                + "&track_name=" + encodeURIComponent(p.trackTitle);
        }
        stdout: StdioCollector {
            onStreamFinished: {
                let data = null;
                try { data = JSON.parse(text); } catch (e) { data = null; }
                if (fetch.stage === "get") {
                    if (data && data.syncedLyrics)
                        root.done(root.parse(data.syncedLyrics));
                    else
                        fetch.searchNext = true; // no exact match: search once this process exits
                    return;
                }
                // Search: first result with synced lyrics and a similar length
                const len = root.player ? root.player.length : 0;
                const hit = Array.isArray(data) ? data.find(r => r.syncedLyrics && (len <= 0 || Math.abs(r.duration - len) < 5)) : null;
                root.done(hit ? root.parse(hit.syncedLyrics) : []);
            }
        }
        onExited: code => {
            if (code !== 0) {
                // Network failure: remember "none" for this track rather than retrying
                fetch.searchNext = false;
                root.done([]);
            } else if (fetch.searchNext) {
                fetch.searchNext = false;
                if (fetch.pendingKey === root.key && root.player) {
                    fetch.stage = "search";
                    Qt.callLater(() => fetch.run(fetch.searchUrl()));
                    return;
                }
            }
            // The track changed while this request ran: fetch the current one
            if (fetch.pendingKey !== root.key)
                Qt.callLater(root.load);
        }
    }

    // MPRIS position doesn't update on its own; read it a few times a second while playing
    Timer {
        interval: root.fast ? MenuStyle.lyricsFastTick : MenuStyle.lyricsTick
        repeat: true
        running: root.lines.length > 0 && root.player !== null && root.player.isPlaying
        onTriggered: {
            const pos = root.player.position;
            let cur = "", idx = -1;
            for (let i = 0; i < root.lines.length; i++) {
                if (root.lines[i].t > pos)
                    break;
                cur = root.lines[i].text;
                idx = i;
            }
            root.line = cur;
            root.index = idx;
        }
    }
}
