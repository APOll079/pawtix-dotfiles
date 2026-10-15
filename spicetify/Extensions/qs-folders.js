// qs-folders: hands your Spotify library to the quickshell Spotify panel (Super+S).
// Spotify's Web API has no folders and no pins; the app does. This reads
// - Spicetify.Platform.LibraryAPI.getContents(): "Your Library" (pins, folders, playlists, artists,
//   albums, in Spotify's order), and
// - Spicetify.Platform.RootlistAPI.getContents(): what's inside each folder,
// and POSTs both as small JSON (names, Spotify URIs, cover URLs, pinned) to the panel's helper on
// this computer (http://127.0.0.1:8899/folders and /library, only listening while the panel is open).
// It re-reads every minute and sends only what changed; a failed send (panel closed) is retried next
// round.
//
// Built to never get in Spotify's way: it waits for Spotify to finish starting, every step is
// wrapped so an error only logs a "[qs-folders]" line (DevTools console), it gives up quietly when
// the APIs it needs don't exist, and it never touches the page itself.
//
// Install: ~/.config/spicetify/Extensions/qs-folders.js, then
//   spicetify config extensions qs-folders.js && spicetify apply
(function qsFolders() {
    const BASE = "http://127.0.0.1:8899";
    const EVERY_MS = 60 * 1000;
    const START_DELAY_MS = 15 * 1000;   // let Spotify finish loading first
    const WAIT_LIMIT_MS = 120 * 1000;   // stop waiting for the APIs after this
    const PAGE = 50;
    const tag = "[qs-folders]";

    function log() {
        try {
            console.debug.apply(console, [tag].concat(Array.from(arguments)));
        } catch (e) {}
    }

    function platform() {
        return (window.Spicetify && Spicetify.Platform) || null;
    }

    // --- folders (RootlistAPI) ---

    function children(node) {
        if (!node || typeof node !== "object")
            return [];
        const c = node.items || node.rows || node.children;
        return Array.isArray(c) ? c : [];
    }

    function reduceTree(node, depth) {
        const out = [];
        if (depth > 8)
            return out;
        for (const c of children(node)) {
            const uri = String((c && c.uri) || "");
            if (c.type === "folder")
                out.push({ type: "folder", uri: uri, name: String(c.name || ""), items: reduceTree(c, depth + 1) });
            else if (c.type === "playlist" || /:playlist:/i.test(uri))
                out.push({ type: "playlist", uri: uri, name: String(c.name || "") });
        }
        return out;
    }

    // --- library (LibraryAPI, undocumented: read whatever fields exist) ---

    function imageOf(it) {
        let url = "";
        const imgs = it.images || (it.album && it.album.images) || [];
        if (Array.isArray(imgs) && imgs.length) {
            // smallest image that is still at least 64 px, else the first
            const fit = imgs.filter(i => i && (i.width || 0) >= 64).sort((a, b) => (a.width || 0) - (b.width || 0));
            url = String((fit[0] || imgs[0]).url || "");
        }
        url = url || String(it.imageUrl || it.image || "");
        const m = url.match(/^spotify:image:([0-9a-f]+)$/i);
        if (m)
            url = "https://i.scdn.co/image/" + m[1];
        return url.startsWith("https://") ? url : "";
    }

    function subOf(it, type) {
        if (type === "artist")
            return "Artist";
        if (type === "album")
            return (Array.isArray(it.artists) && it.artists[0] && it.artists[0].name) ? String(it.artists[0].name) : "Album";
        if (type === "folder") {
            const n = it.numberOfPlaylists !== undefined ? it.numberOfPlaylists : (it.totalLength !== undefined ? it.totalLength : null);
            return n !== null ? n + " playlists" : "Folder";
        }
        if (type === "collection")
            return "Playlist";
        const owner = it.owner && (it.owner.name || it.owner.displayName);
        return owner ? "Playlist · " + owner : "Playlist";
    }

    function typeOf(it) {
        const t = String(it.type || "").toLowerCase();
        if (t)
            return t;
        const parts = String(it.uri || "").split(":");
        return parts.length >= 2 ? (parts[parts.length - 1] === "collection" ? "collection" : parts[parts.length - 2]) : "";
    }

    async function readLibrary(p) {
        const api = p.LibraryAPI;
        if (!api || typeof api.getContents !== "function")
            return null;
        const items = [];
        let shapeLogged = false;
        for (let offset = 0; offset < 5000; offset += PAGE) {
            const res = await api.getContents({ offset: offset, limit: PAGE });
            const page = (res && (res.items || res.rows)) || [];
            if (!shapeLogged && page.length) {
                log("library item fields:", Object.keys(page[0]).join(","));
                shapeLogged = true;
            }
            for (const it of page) {
                if (!it || !it.uri)
                    continue;
                const type = typeOf(it);
                items.push({ type: type, uri: String(it.uri), name: String(it.name || ""), sub: subOf(it, type), pinned: it.pinned === true, image: imageOf(it) });
            }
            const total = res && (res.totalLength || res.total);
            if (page.length < PAGE || (total && offset + PAGE >= total))
                break;
        }
        return items;
    }

    // --- sending ---

    // Plain no-cors POST (text/plain, no preflight): the same way the folders already arrived.
    // A refused connection (panel closed) rejects and is retried next round.
    async function post(kind, items) {
        try {
            await fetch(BASE + "/" + kind, { method: "POST", mode: "no-cors", headers: { "Content-Type": "text/plain" }, body: JSON.stringify({ items: items }) });
            return true;
        } catch (e) {
            return false;
        }
    }

    const lastSent = { folders: "", library: "" };
    let busy = false;

    async function push(kind, items) {
        if (!items || items.length === 0)
            return;
        const body = JSON.stringify(items);
        if (body === lastSent[kind])
            return;
        if (await post(kind, items)) {
            lastSent[kind] = body;
            log("sent", kind, items.length);
        }
    }

    async function sync() {
        if (busy)
            return;
        busy = true;
        try {
            const p = platform();
            if (!p)
                return;
            try {
                if (p.RootlistAPI && typeof p.RootlistAPI.getContents === "function")
                    await push("folders", reduceTree(await p.RootlistAPI.getContents(), 0));
            } catch (e) {
                log("folders skipped", e && e.message);
            }
            try {
                await push("library", await readLibrary(p));
            } catch (e) {
                log("library skipped", e && e.message);
            }
        } finally {
            busy = false;
        }
    }

    // Wait (without blocking anything) until the APIs exist, then sync now and every minute
    const started = Date.now();
    function waitForApi() {
        try {
            const p = platform();
            if (p && (p.RootlistAPI || p.LibraryAPI)) {
                sync();
                setInterval(sync, EVERY_MS);
                return;
            }
        } catch (e) {}
        if (Date.now() - started > WAIT_LIMIT_MS) {
            log("Spicetify.Platform APIs not found; nothing will be sent on this Spotify version");
            return;
        }
        setTimeout(waitForApi, 1000);
    }

    setTimeout(waitForApi, START_DELAY_MS);
})();
