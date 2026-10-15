pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// Media state for the bar and the side panel, read straight from MPRIS (no playerctl).
// - spotify: the Spotify player, or null. The bar centre only ever shows Spotify.
// - player: what the panel controls act on: whatever is playing (Spotify wins if it plays),
//   else a paused Spotify (so play resumes it), else null. Pausing a video while Spotify sits
//   paused hits the video, not Spotify.
// Lyrics (later) hook in here: spotify.position / spotify.length plus the current track.
Singleton {
    id: root

    // The Spotify app or spotifyd (the background player the Spotify panel uses without the app)
    function isSpotify(p) {
        return /^spotifyd?$/i.test(p.desktopEntry) || /^spotifyd?/i.test(p.identity);
    }

    function trackOf(p) {
        if (!p || p.trackTitle === "")
            return "";
        return p.trackArtist === "" ? p.trackTitle : p.trackArtist + " - " + p.trackTitle;
    }

    // Both may run at once: the one that plays wins
    readonly property var spotify: Mpris.players.values.find(p => root.isSpotify(p) && p.isPlaying)
        || Mpris.players.values.find(p => root.isSpotify(p)) || null
    readonly property var player: (spotify && spotify.isPlaying ? spotify : null)
        || Mpris.players.values.find(p => p.isPlaying)
        || spotify
        || null

    // --- Panel (controls follow `player`) ---
    readonly property bool playing: player !== null && player.isPlaying
    readonly property string label: {
        const t = root.trackOf(root.player);
        if (t === "")
            return root.player ? "Nothing playing" : "No player running";
        return root.playing ? t : t + " (paused)";
    }

    // --- Bar centre (Spotify only) ---
    // Shown while Spotify has a track, dimmed when paused. Spotify briefly reports an empty
    // title between tracks, so going empty waits barHideDelay before the text disappears.
    readonly property string spotifyTrack: trackOf(spotify)
    readonly property bool spotifyPaused: spotify !== null && !spotify.isPlaying
    property string text: ""
    property bool paused: false

    onSpotifyTrackChanged: sync()
    onSpotifyPausedChanged: sync()
    Component.onCompleted: sync()

    function sync() {
        if (root.spotifyTrack !== "") {
            hideTimer.stop();
            root.text = root.spotifyTrack;
            root.paused = root.spotifyPaused;
        } else {
            hideTimer.restart();
        }
    }

    Timer {
        id: hideTimer
        interval: MenuStyle.barHideDelay
        onTriggered: {
            root.text = "";
            root.paused = false;
        }
    }
}
