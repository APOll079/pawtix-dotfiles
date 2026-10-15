pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Launcher memory in Quickshell's state dir (not the repo): how often each app was launched
// (usage ranking), the pinned apps in order and the apps hidden from the launcher.
Singleton {
    id: root

    property alias counts: adapter.counts
    property alias pinned: adapter.pinned
    property alias hidden: adapter.hidden

    function bump(id) {
        const c = Object.assign({}, adapter.counts);
        c[id] = (c[id] || 0) + 1;
        adapter.counts = c;
    }

    function isPinned(id) {
        return adapter.pinned.indexOf(id) !== -1;
    }

    function togglePin(id) {
        adapter.pinned = root.isPinned(id) ? adapter.pinned.filter(p => p !== id) : adapter.pinned.concat([id]);
    }

    function isHidden(id) {
        return adapter.hidden.indexOf(id) !== -1;
    }

    function toggleHidden(id) {
        adapter.hidden = root.isHidden(id) ? adapter.hidden.filter(h => h !== id) : adapter.hidden.concat([id]);
    }

    // Move a pinned app up (-1) or down (+1)
    function move(id, delta) {
        const p = adapter.pinned.slice();
        const i = p.indexOf(id), j = i + delta;
        if (i < 0 || j < 0 || j >= p.length)
            return;
        p[i] = p[j];
        p[j] = id;
        adapter.pinned = p;
    }

    FileView {
        path: Quickshell.statePath("launcher.json")
        // First run has no file yet; onLoadFailed creates it
        printErrors: false
        onAdapterUpdated: writeAdapter()
        onLoadFailed: error => {
            if (error == FileViewError.FileNotFound)
                writeAdapter();
        }
        JsonAdapter {
            id: adapter
            property var counts: ({})
            property var pinned: []
            property var hidden: []
        }
    }
}
