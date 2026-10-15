pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Io

// Notifications, newest first.
// - items: the history (side panel). Each entry keeps the live notification (`notif`) so a
//   click can still run the app's "default" action (e.g. jump to the Discord conversation).
//   The text part is saved to notifications.json in Quickshell's state dir and restored at start;
//   restored entries have no `notif` (the app's notification is gone), so they are text-only.
// - toasts: the notifications currently shown as toasts, at most one per app: a new one from the
//   same app replaces it, and toastCounts[appName] counts how many arrived meanwhile. A toast
//   timing out only hides it; the notification stays alive for the history.
Singleton {
    id: root

    readonly property int maxItems: 50
    property var items: []
    property var toasts: []
    property int nextId: 1
    // Notifications that arrived since the panel last showed the Notifications tab
    property int unread: 0
    property var toastCounts: ({})
    property bool restored: false

    function add(n) {
        var entry = {
            key: root.nextId++,
            notif: n,
            vesktop: root.isVesktop(n),
            appName: n.appName,
            summary: n.summary,
            body: n.body,
            urgency: n.urgency,
            appIcon: n.appIcon,
            image: n.image,
            time: new Date()
        };
        // The app (or the server) closed it: keep the history text, drop the dead reference
        n.closed.connect(function () {
            root.forget(n);
        });
        var list = [entry].concat(root.items);
        for (var old of list.slice(root.maxItems))
            if (old.notif)
                old.notif.dismiss();
        root.items = list.slice(0, root.maxItems);
        // Do Not Disturb: straight to the history, no toast
        if (!Config.settings.notifications.dnd) {
            const sameApp = root.toasts.some(t => t.appName === n.appName);
            const c = Object.assign({}, root.toastCounts);
            c[n.appName] = sameApp ? (c[n.appName] || 1) + 1 : 1;
            root.toastCounts = c;
            root.toasts = [n].concat(root.toasts.filter(t => t.appName !== n.appName));
        }
        root.unread += 1;
    }

    function forget(n) {
        for (var e of root.items)
            if (e.notif === n)
                e.notif = null;
        root.items = root.items.slice();
        root.hideToast(n);
    }

    function hideToast(n) {
        root.toasts = root.toasts.filter(t => t !== n);
        if (n && !root.toasts.some(t => t.appName === n.appName)) {
            const c = Object.assign({}, root.toastCounts);
            delete c[n.appName];
            root.toastCounts = c;
        }
    }

    // Progress (the "value" hint, 0-100) of a live notification, or -1
    function progressOf(n) {
        if (!n || !n.hints)
            return -1;
        const v = Number(n.hints.value);
        return isNaN(v) ? -1 : Math.max(0, Math.min(100, v));
    }

    // Send a typed reply (apps that offer one, e.g. chat apps); the toast goes away
    function reply(n, text) {
        if (!n || !n.hasInlineReply || text.trim() === "")
            return;
        n.sendInlineReply(text);
        root.hideToast(n);
    }

    // --- saved history ---

    onItemsChanged: {
        if (root.restored)
            saveTimer.restart();
    }

    Timer {
        id: saveTimer
        interval: 1000
        onTriggered: {
            historyAdapter.items = root.items.map(e => ({
                appName: e.appName,
                summary: e.summary,
                body: e.body,
                urgency: e.urgency,
                appIcon: e.appIcon,
                // Only real files survive a restart (in-memory images are gone)
                image: /^(\/|file:)/.test(e.image || "") ? e.image : "",
                time: e.time.toISOString()
            }));
            historyFile.writeAdapter();
        }
    }

    function restore() {
        if (root.restored)
            return;
        const old = (historyAdapter.items || []).map(e => ({
            key: root.nextId++,
            notif: null,
            vesktop: /vesktop|discord/i.test(e.appName || ""),
            appName: e.appName || "",
            summary: e.summary || "",
            body: e.body || "",
            urgency: e.urgency || 0,
            appIcon: e.appIcon || "",
            image: e.image || "",
            time: new Date(e.time)
        }));
        root.items = root.items.concat(old).slice(0, root.maxItems);
        root.restored = true;
    }

    FileView {
        id: historyFile
        path: Quickshell.statePath("notifications.json")
        printErrors: false
        onLoaded: root.restore()
        onLoadFailed: root.restore()
        JsonAdapter {
            id: historyAdapter
            property var items: []
        }
    }

    // Run the app's default action if it has one (that also closes the notification),
    // else just close it. Removes it from the toasts and the history.
    function activate(n) {
        if (!n)
            return;
        var vesktop = root.isVesktop(n);
        var invoked = false;
        for (var a of n.actions) {
            if (a.identifier === "default") {
                a.invoke();
                invoked = true;
                break;
            }
        }
        if (!invoked)
            n.dismiss();
        if (vesktop)
            root.raiseVesktop(invoked);
        root.hideToast(n);
        root.items = root.items.filter(e => e.notif !== n);
    }

    // --- Vesktop (Discord) ---
    // Vesktop sits in the tray with no window and maps it on demand; the window rule then puts
    // it on the hidden special:spotifyspace, so a click seemed to do nothing. After the default
    // action (Vesktop shows the chat) or, without one, a second `vesktop` launch (Electron hands
    // it to the running instance, which shows its window), focus the window by class: focusing
    // a window on a hidden special workspace reveals it. Other apps are left alone.
    function isVesktop(n) {
        return /vesktop|discord/i.test(n.desktopEntry + " " + n.appName);
    }

    function raiseVesktop(invoked) {
        if (!invoked)
            Quickshell.execDetached(["vesktop"]);
        vesktopFocus.tries = 0;
        vesktopFocus.restart();
    }

    // Poll until the window exists (it may take a moment to map), then focus it
    Timer {
        id: vesktopFocus
        property int tries: 0
        interval: 250
        repeat: true
        onTriggered: {
            tries += 1;
            const win = ToplevelManager.toplevels.values.find(t => /^vesktop$/i.test(t.appId));
            if (win) {
                Hyprland.dispatch("hl.dsp.focus({ window = \"class:^([Vv]esktop)$\" })");
                if (win.activated || tries >= 12)
                    stop();
            } else if (tries >= 12) {
                stop();
            }
        }
    }

    // An action button on a toast (not the default click)
    function runAction(n, action) {
        action.invoke();
        if (root.isVesktop(n))
            root.raiseVesktop(true);
        root.hideToast(n);
        root.items = root.items.filter(e => e.notif !== n);
    }

    // History click: open it if the notification is still alive, otherwise just drop the entry
    function open(key) {
        var entry = root.items.find(e => e.key === key);
        if (entry && entry.notif) {
            root.activate(entry.notif);
        } else {
            // Already closed by the app: for Vesktop still bring the window forward
            if (entry && entry.vesktop)
                root.raiseVesktop(false);
            root.items = root.items.filter(e => e.key !== key);
        }
    }

    function clear() {
        for (var e of root.items)
            if (e.notif)
                e.notif.dismiss();
        root.items = [];
    }
}
