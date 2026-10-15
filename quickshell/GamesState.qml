pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Games for the Games menu. The list comes from scripts/games.py (Steam library, Steam shortcuts,
// and the "custom" entries below); the user's own entries and the hidden ids live in
// games.json in Quickshell's state dir (not the repo). The helper re-runs on open and whenever
// that file is saved, so adding or removing an entry shows up at once.
Singleton {
    id: root

    property var games: []                 // [{ id, title, source, launch, cwd, dir, art, lastPlayed }]
    property bool loaded: false
    property bool rerun: false

    readonly property var hidden: adapter.hidden
    readonly property var custom: adapter.custom
    readonly property string file: Quickshell.statePath("games.json")

    function refresh() {
        if (proc.running)
            root.rerun = true;
        else
            proc.running = true;
    }

    function isHidden(id) {
        return adapter.hidden.indexOf(id) !== -1;
    }

    function setHidden(id, hide) {
        const rest = adapter.hidden.filter(h => h !== id);
        adapter.hidden = hide ? rest.concat([id]) : rest;
    }

    // Add (or replace, by name) an entry of the user's own: { name, command, dir, cover }
    function addCustom(entry) {
        const rest = adapter.custom.filter(e => e.name !== entry.name);
        adapter.custom = rest.concat([Object.assign({ lastPlayed: 0 }, entry)]);
    }

    function removeCustom(name) {
        adapter.custom = adapter.custom.filter(e => e.name !== name);
    }

    function launch(game) {
        const spec = { command: game.launch };
        if (game.cwd)
            spec.workingDirectory = game.cwd;
        Quickshell.execDetached(spec);
        // Own entries remember when they were last started (Steam keeps its own record)
        if (game.source === "custom")
            adapter.custom = adapter.custom.map(e => e.name === game.title ? Object.assign({}, e, { lastPlayed: Math.floor(Date.now() / 1000) }) : e);
    }

    Process {
        id: proc
        command: ["python3", "-I", Quickshell.shellDir + "/scripts/games.py", "--custom", root.file]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.games = JSON.parse(text);
                } catch (e) {
                    console.warn("scripts/games.py gave no valid JSON: " + e);
                }
                root.loaded = true;
                if (root.rerun) {
                    root.rerun = false;
                    proc.running = true;
                }
            }
        }
    }

    FileView {
        path: root.file
        printErrors: false
        onAdapterUpdated: writeAdapter()
        onSaved: root.refresh()
        onLoadFailed: error => {
            if (error == FileViewError.FileNotFound)
                writeAdapter();
        }
        JsonAdapter {
            id: adapter
            property var custom: []
            property var hidden: []
        }
    }
}
