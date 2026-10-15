#!/usr/bin/env python3
"""Spotify Web API helper for the Spotify panel (popups/SpotifyPanel.qml, SpotifyState.qml).

Usage: spotify.py --state <dir> <command> [args]
Every command prints one JSON value on stdout. Errors print {"error": "...", "status": <http code>}
and exit 1. Standard library only.

Login: PKCE (no client secret). `set-client <id>` stores the client ID of your Spotify developer app,
`login` opens the browser and catches the redirect on REDIRECT_URI (add exactly that URI to the
app in the Spotify dashboard). Tokens are kept in <dir>/token.json (mode 600), never in the repo.

Commands
  status                      {configured, loggedIn}
  set-client <id> | login | logout
  state                       now playing, shuffle, repeat, volume, device (null when nothing plays)
  liked <uri>                 true / false
  like <uri> | unlike <uri>
  recent                      last 8 distinct albums / playlists / artists you played from
  playlists | artists | albums | liked-tracks
  open <uri>                  tracks of an album or of your own playlist; albums of an artist
  play [<context-uri>|liked] [<track-uri>]   start a context (optionally at a track), or a single track
  resume                      play; with nothing active, carry on here (transfer) or start the last song
  transfer                    move playback to this PC (the app if open, else spotifyd), keep playing
  last                        the last played track and its context
  pause | next | prev | seek <ms> | shuffle on|off | repeat off|context|track | volume <0-100>
  add <playlist-uri> <track-uri>
  queue <track-uri>           add a song to the queue (plays next)
  serve                       keep running: JSON requests on stdin, answers on stdout (see serve()),
                              plus the folder listener for the Spicetify extension (folder_listener())

Endpoints used (Spotify's development-mode API after the February 2026 changes): /me, /me/player*,
/me/player/recently-played, /me/playlists, /me/following, /me/albums, /me/tracks, /me/library
(PUT, DELETE, /contains), /playlists/{id} (+ /items, own playlists only), /albums/{id}/tracks,
/artists/{id}, /artists/{id}/albums. If Spotify changes one, this file is the only place to fix.

Testing: SPOTIFY_FIXTURE=<file.json> answers requests from a {"METHOD /path": response} map instead
of the network (the query string is ignored), and login is skipped. A value {"__error": msg,
"status": n} makes that request fail.
"""
import base64
import fcntl
import hashlib
import http.client
import json
import os
import re
import threading
import secrets
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

API = "https://api.spotify.com/v1"
AUTH_URL = "https://accounts.spotify.com/authorize"
TOKEN_URL = "https://accounts.spotify.com/api/token"
PORT = 8898
REDIRECT_URI = "http://127.0.0.1:%d/callback" % PORT
SCOPES = " ".join([
    "user-read-playback-state", "user-modify-playback-state", "user-read-currently-playing",
    "user-read-recently-played", "user-library-read", "user-library-modify", "user-follow-read",
    "playlist-read-private", "playlist-read-collaborative", "playlist-modify-public", "playlist-modify-private",
])
LIKED_LIMIT = 1000        # Liked Songs: first N tracks (50 per request)
LOGIN_TIMEOUT = 180       # seconds to finish the browser login


class ApiError(Exception):
    def __init__(self, message, status=0):
        super().__init__(message)
        self.status = status


STATE = ""
FIXTURE = os.environ.get("SPOTIFY_FIXTURE", "")


def path(name):
    return os.path.join(STATE, name)


def read_json(name, default=None):
    try:
        with open(path(name), encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def write_private(name, data):
    os.makedirs(STATE, mode=0o700, exist_ok=True)
    tmp = path(name + ".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f)
    os.replace(tmp, path(name))


def out(value):
    print(json.dumps(value))


# --- auth ---

def client_id():
    cid = (read_json("config.json", {}) or {}).get("client_id", "")
    if not cid:
        raise ApiError("No client ID set", 0)
    return cid


def post_form(url, fields):
    data = urllib.parse.urlencode(fields).encode()
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/x-www-form-urlencoded"})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        raise ApiError("Login failed: " + e.read().decode(errors="replace")[:200], e.code)
    except urllib.error.URLError as e:
        raise ApiError("No connection: %s" % e.reason, 0)


def save_token(tok, old=None):
    write_private("token.json", {
        "access_token": tok["access_token"],
        # Spotify may or may not rotate the refresh token
        "refresh_token": tok.get("refresh_token") or (old or {}).get("refresh_token", ""),
        "expires_at": int(time.time()) + int(tok.get("expires_in", 3600)) - 60,
    })


def access_token():
    if FIXTURE:
        return "fixture"
    tok = read_json("token.json")
    if not tok or not tok.get("refresh_token"):
        raise ApiError("Not logged in", 401)
    if tok.get("expires_at", 0) > time.time():
        return tok["access_token"]
    # Several helper runs can start at once: refresh under a lock, then re-read
    os.makedirs(STATE, mode=0o700, exist_ok=True)
    with open(path("token.lock"), "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        tok = read_json("token.json") or tok
        if tok.get("expires_at", 0) > time.time():
            return tok["access_token"]
        new = post_form(TOKEN_URL, {"grant_type": "refresh_token", "refresh_token": tok["refresh_token"], "client_id": client_id()})
        save_token(new, tok)
        return new["access_token"]


def login():
    cid = client_id()
    verifier = secrets.token_urlsafe(64)[:96]
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip("=")
    state = secrets.token_urlsafe(16)
    url = AUTH_URL + "?" + urllib.parse.urlencode({
        "client_id": cid, "response_type": "code", "redirect_uri": REDIRECT_URI, "scope": SCOPES,
        "code_challenge_method": "S256", "code_challenge": challenge, "state": state,
    })
    result = {}

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            if urllib.parse.urlparse(self.path).path != "/callback":
                self.send_response(404)
                self.end_headers()
                return
            if q.get("state", [""])[0] == state:
                result["code"] = q.get("code", [""])[0]
                result["error"] = q.get("error", [""])[0]
            ok = bool(result.get("code"))
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(("Logged in. You can close this tab." if ok else "Login failed. Try again from the panel.").encode())

        def log_message(self, *args):
            pass

    server = HTTPServer(("127.0.0.1", PORT), Handler)
    server.timeout = 1
    subprocess.Popen(["xdg-open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.time() + LOGIN_TIMEOUT
    while "code" not in result and time.time() < deadline:
        server.handle_request()
    server.server_close()
    if not result.get("code"):
        raise ApiError("Login " + (result.get("error") or "timed out"), 0)
    tok = post_form(TOKEN_URL, {
        "grant_type": "authorization_code", "code": result["code"], "redirect_uri": REDIRECT_URI,
        "client_id": cid, "code_verifier": verifier,
    })
    save_token(tok)
    return {"ok": True}


# --- requests ---

def api(method, endpoint, query=None, body=None, allow_empty=True):
    if FIXTURE:
        with open(FIXTURE, encoding="utf-8") as f:
            table = json.load(f)
        key = method + " " + endpoint.split("?")[0]
        if key not in table:
            if method != "GET":
                return None
            raise ApiError("fixture has no " + key, 404)
        if isinstance(table[key], dict) and "__error" in table[key]:
            raise ApiError(table[key]["__error"], table[key].get("status", 400))
        return table[key]
    url = endpoint if endpoint.startswith("http") else API + endpoint
    if query:
        url += ("&" if "?" in url else "?") + urllib.parse.urlencode(query)
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Authorization": "Bearer " + access_token()}
    if data is not None:
        headers["Content-Type"] = "application/json"
    elif method in ("PUT", "POST"):
        headers["Content-Length"] = "0"
    status, raw = send(method, url, data, headers)
    if status >= 400:
        text = raw.decode(errors="replace")
        try:
            err = json.loads(text).get("error", {})
            msg = err.get("message", text) if isinstance(err, dict) else str(err)
            reason = err.get("reason", "") if isinstance(err, dict) else ""
        except ValueError:
            msg, reason = text[:200], ""
        raise ApiError(reason or msg or ("HTTP %d" % status), status)
    return json.loads(raw) if raw else None


# serve mode keeps one HTTPS connection open (no new handshake per request)
KEEPALIVE = False
_LOCAL = threading.local()          # one kept-alive connection per serve() thread


def send(method, url, data, headers):
    """One HTTP request -> (status, body bytes)."""
    if not KEEPALIVE:
        req = urllib.request.Request(url, data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=15) as r:
                return r.status, r.read()
        except urllib.error.HTTPError as e:
            return e.code, e.read()
        except urllib.error.URLError as e:
            raise ApiError("No connection: %s" % e.reason, 0)
    u = urllib.parse.urlparse(url)
    target = u.path + ("?" + u.query if u.query else "")
    for attempt in (1, 2):
        conn = getattr(_LOCAL, "conn", None)
        try:
            if conn is None:
                conn = _LOCAL.conn = http.client.HTTPSConnection(u.netloc, timeout=15)
            conn.request(method, target, body=data, headers=headers)
            r = conn.getresponse()
            return r.status, r.read()
        except (http.client.HTTPException, OSError) as e:
            # The server closed the idle connection: reconnect once
            if conn is not None:
                conn.close()
            _LOCAL.conn = None
            if attempt == 2:
                raise ApiError("No connection: %s" % e, 0)


FOLDERS_PORT = 8899                    # the Spicetify extension qs-folders.js posts here
FOLDERS_MAX = 1024 * 1024              # bytes
URI_RE = re.compile(r"^spotify:[A-Za-z0-9:._-]{1,200}$")


def clean_tree(items, depth=0, count=None):
    """Validate the folder tree from qs-folders.js and keep only known fields; None if it's junk."""
    count = count if count is not None else [0]
    if not isinstance(items, list) or depth > 8:
        return None
    out = []
    for it in items:
        count[0] += 1
        if count[0] > 5000 or not isinstance(it, dict):
            return None
        uri, name = it.get("uri"), it.get("name", "")
        if not isinstance(uri, str) or not URI_RE.match(uri) or not isinstance(name, str):
            return None
        if it.get("type") == "folder":
            sub = clean_tree(it.get("items", []), depth + 1, count)
            if sub is None:
                return None
            out.append({"type": "folder", "uri": uri, "name": name[:300], "items": sub})
        elif it.get("type") == "playlist":
            out.append({"type": "playlist", "uri": uri, "name": name[:300]})
    return out


LIB_TYPES = {"playlist", "artist", "album", "folder", "collection", "show", "episode", "audiobook"}


def clean_library(items):
    """Validate the library list from qs-folders.js (Spotify's Your Library); None if it's junk."""
    if not isinstance(items, list) or len(items) > 10000:
        return None
    out = []
    for it in items:
        if not isinstance(it, dict):
            return None
        t, uri = it.get("type"), it.get("uri")
        if t not in LIB_TYPES or not isinstance(uri, str) or not URI_RE.match(uri):
            continue
        img = it.get("image", "")
        out.append({
            "type": t, "uri": uri,
            "name": str(it.get("name", ""))[:300],
            "sub": str(it.get("sub", ""))[:300],
            "pinned": it.get("pinned") is True,
            "image": img if isinstance(img, str) and img.startswith("https://") and len(img) < 600 else "",
        })
    return out


def take_message(text):
    """One message from the extension: {"kind": "folders" | "library", "items": [...]}."""
    try:
        msg = json.loads(text)
    except ValueError:
        return False
    if not isinstance(msg, dict):
        return False
    kind = msg.get("kind", "folders")
    if kind == "folders":
        data = clean_tree(msg.get("items"))
        name = "folders.json"
    elif kind == "library":
        data = clean_library(msg.get("items"))
        name = "library.json"
    else:
        return False
    if data is None:
        return False
    write_private(name, {"items": data, "time": int(time.time())})
    # Tell the panel (its stdout reader) to re-read the file
    print(json.dumps({"event": kind}), flush=True)
    return True


def folder_listener():
    """Background listener on 127.0.0.1 for the Spicetify extension (qs-folders.js): POST /folders
    saves folders.json, POST /library saves library.json (validated), then the panel re-reads it.
    Plain HTTP (the extension uses a no-cors fetch; verified working from Spotify). Localhost only,
    while the panel is open."""
    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            ok = False
            try:
                size = int(self.headers.get("Content-Length") or 0)
                kind = {"/folders": "folders", "/library": "library"}.get(self.path)
                if kind and 0 < size <= FOLDERS_MAX:
                    body = json.loads(self.rfile.read(size))
                    if isinstance(body, dict):
                        ok = take_message(json.dumps({"kind": kind, "items": body.get("items")}))
            except (ValueError, OSError):
                ok = False
            self.send_response(204 if ok else 400)
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()

        def log_message(self, *args):
            pass

    try:
        server = HTTPServer(("127.0.0.1", FOLDERS_PORT), Handler)
    except OSError:
        return  # port taken (another panel instance): that one listens
    threading.Thread(target=server.serve_forever, daemon=True).start()


_PRINT = threading.Lock()


def answer(obj):
    with _PRINT:
        print(json.dumps(obj), flush=True)


def handle(req):
    rid, cmd, args = req.get("id"), req.get("cmd"), req.get("args") or []
    try:
        if cmd in ("login", "serve"):
            raise ApiError(cmd + " can't run inside serve", 400)
        answer({"id": rid, "result": dispatch(cmd, args)})
    except ApiError as e:
        answer({"id": rid, "error": str(e), "status": e.status})
    except (IndexError, ValueError) as e:
        answer({"id": rid, "error": "bad arguments: %s" % e, "status": 400})


def serve():
    """Long-running mode for the panel: one JSON request per stdin line,
    {"id": n, "cmd": <any command but login>, "args": [...]}, one JSON answer per stdout line,
    {"id": n, "result": ...} or {"id": n, "error": msg, "status": code}. Ends when stdin closes.
    Every request runs in its own thread with its own kept-alive HTTPS connection, so a slow one
    (the library) never holds up play / pause. Queued volume requests collapse to the newest, so a
    fast drag never builds a backlog. Also runs the folder / library listener."""
    global KEEPALIVE
    KEEPALIVE = True
    folder_listener()
    import select
    while True:
        line = sys.stdin.readline()
        if not line:
            return
        # Drain what is already waiting; keep only the last volume request
        batch = [line]
        while select.select([sys.stdin], [], [], 0)[0]:
            more = sys.stdin.readline()
            if not more:
                break
            batch.append(more)
        reqs = []
        for l in batch:
            try:
                reqs.append(json.loads(l))
            except ValueError:
                pass
        vols = [r for r in reqs if r.get("cmd") == "volume"]
        for req in [r for r in reqs if r.get("cmd") != "volume"] + vols[-1:]:
            threading.Thread(target=handle, args=(req,), daemon=True).start()


ARTIST_PAGE = 10        # max page size Spotify allows on /artists/{id}/albums (development mode, 2026)
ARTIST_ALBUMS = 30
ARTIST_SINGLES = 20


def paged(endpoint, query, limit=None, key=None):
    """Follow `next` links; `key` digs into a wrapper object (e.g. "artists" for /me/following)."""
    items, page = [], api("GET", endpoint, query)
    while page:
        if key:
            page = page.get(key, {})
        items += page.get("items", [])
        if limit and len(items) >= limit:
            return items[:limit]
        nxt = page.get("next")
        page = api("GET", nxt) if nxt and not FIXTURE else None
    return items


def image(images, want=64):
    """The smallest image at least `want` px wide (Spotify lists them largest first)."""
    images = images or []
    fit = [i for i in images if (i.get("width") or 0) >= want]
    pick = fit[-1] if fit else (images[0] if images else None)
    return pick["url"] if pick else ""


def uri_id(uri):
    return uri.rsplit(":", 1)[-1]


def me_id():
    cached = read_json("me.json")
    if cached and cached.get("id"):
        return cached["id"]
    me = api("GET", "/me") or {}
    write_private("me.json", {"id": me.get("id", "")})
    return me.get("id", "")


def track_item(t):
    if not t:
        return None
    album = t.get("album") or {}
    return {
        "kind": "track", "uri": t.get("uri", ""), "name": t.get("name", ""),
        "sub": ", ".join(a.get("name", "") for a in t.get("artists", [])),
        "image": image(album.get("images")), "duration": t.get("duration_ms", 0),
    }


# --- commands ---

def cmd_state():
    p = api("GET", "/me/player", {"additional_types": "track,episode"})
    if not p:
        return None
    t = p.get("item") or {}
    album = t.get("album") or {}
    dev = p.get("device") or {}
    return {
        "playing": bool(p.get("is_playing")), "shuffle": bool(p.get("shuffle_state")),
        "repeat": p.get("repeat_state", "off"), "progress": p.get("progress_ms") or 0,
        "volume": dev.get("volume_percent"), "device": dev.get("name", ""),
        # This PC (the app or spotifyd) plays: MPRIS can control it directly
        "local": is_local(dev),
        "context": (p.get("context") or {}).get("uri", ""),
        "track": {
            "uri": t.get("uri", ""), "name": t.get("name", ""),
            "artists": ", ".join(a.get("name", "") for a in t.get("artists", [])),
            "album": album.get("name", ""), "image": image(album.get("images"), 300),
            "duration": t.get("duration_ms", 0),
        } if t else None,
    }


def cmd_liked(uri):
    r = api("GET", "/me/library/contains", {"uris": uri})
    return bool(r and r[0])


def cmd_recent():
    plays = api("GET", "/me/player/recently-played", {"limit": 50}) or {}
    seen, out_items = set(), []
    uid = None
    for p in plays.get("items", []):
        t = p.get("track") or {}
        ctx = p.get("context") or {}
        uri, kind = ctx.get("uri", ""), ctx.get("type", "")
        if not uri:                       # played without a context: use the album
            album = t.get("album") or {}
            uri, kind = album.get("uri", ""), "album"
        if not uri or uri in seen:
            continue
        seen.add(uri)
        entry = {"kind": kind, "uri": uri, "name": "", "sub": "", "image": ""}
        try:
            if kind == "album":
                album = t.get("album") or {}
                if album.get("uri") != uri:
                    album = api("GET", "/albums/" + uri_id(uri)) or {}
                entry.update(name=album.get("name", ""), sub="Album", image=image(album.get("images"), 120))
            elif kind == "playlist":
                pl = api("GET", "/playlists/" + uri_id(uri), {"fields": "name,images,owner(id)"}) or {}
                entry.update(name=pl.get("name", ""), sub="Playlist", image=image(pl.get("images"), 120))
            elif kind == "artist":
                ar = api("GET", "/artists/" + uri_id(uri)) or {}
                entry.update(name=ar.get("name", ""), sub="Artist", image=image(ar.get("images"), 120))
            elif kind == "collection" or uri.endswith(":collection"):
                uid = uid or me_id()
                entry.update(kind="liked", uri="spotify:user:%s:collection" % uid, name="Liked Songs", sub="Playlist")
            else:
                continue
        except ApiError:
            continue
        if entry["name"]:
            out_items.append(entry)
        if len(out_items) == 8:
            break
    return out_items


def cmd_playlists():
    uid = me_id()
    res = []
    for p in paged("/me/playlists", {"limit": 50}):
        if not p:
            continue
        own = (p.get("owner") or {}).get("id") == uid or bool(p.get("collaborative"))
        count = (p.get("items") or p.get("tracks") or {}).get("total", 0)
        res.append({"kind": "playlist", "uri": p.get("uri", ""), "name": p.get("name", ""),
                    "sub": ("%d songs" % count) if own else "by " + ((p.get("owner") or {}).get("display_name") or "someone else"),
                    "image": image(p.get("images")), "openable": own})
    return res


def cmd_artists():
    res = []
    for a in paged("/me/following", {"type": "artist", "limit": 50}, key="artists"):
        res.append({"kind": "artist", "uri": a.get("uri", ""), "name": a.get("name", ""), "sub": "Artist",
                    "image": image(a.get("images")), "openable": True})
    return res


def cmd_albums():
    res = []
    for s in paged("/me/albums", {"limit": 50}):
        a = s.get("album") or {}
        res.append({"kind": "album", "uri": a.get("uri", ""), "name": a.get("name", ""),
                    "sub": ", ".join(x.get("name", "") for x in a.get("artists", [])),
                    "image": image(a.get("images")), "openable": True})
    return res


def cmd_liked_tracks():
    return [x for x in (track_item(s.get("track")) for s in paged("/me/tracks", {"limit": 50}, LIKED_LIMIT)) if x]


def cmd_open(uri):
    kind = uri.split(":")[1] if uri.count(":") >= 2 else ""
    if kind == "album":
        album = api("GET", "/albums/" + uri_id(uri)) or {}
        img = image(album.get("images"))
        tracks = []
        for t in paged("/albums/%s/tracks" % uri_id(uri), {"limit": 50}):
            item = track_item(t)
            item["image"] = img
            tracks.append(item)
        return {"kind": "tracks", "items": tracks}
    if kind == "playlist":
        items = paged("/playlists/%s/items" % uri_id(uri), {"limit": 50})
        return {"kind": "tracks", "items": [x for x in (track_item(i.get("item") or i.get("track")) for i in items) if x]}
    if kind == "artist":
        # Since 2026, development-mode apps get "Invalid limit" above ARTIST_PAGE on this endpoint:
        # page 10 at a time, albums and singles as separate groups (a long album list can't hide
        # the latest singles), newest first
        def group(name, cap):
            got = paged("/artists/%s/albums" % uri_id(uri), {"include_groups": name, "limit": ARTIST_PAGE}, cap)
            got.sort(key=lambda a: a.get("release_date") or "", reverse=True)
            return got
        albums, singles = group("album", ARTIST_ALBUMS), group("single", ARTIST_SINGLES)

        def row(a, label):
            year = (a.get("release_date") or "")[:4]
            return {"kind": "album", "uri": a.get("uri", ""), "name": a.get("name", ""),
                    "sub": (year + " \u00b7 " if year else "") + label, "image": image(a.get("images")), "openable": True}
        plural = lambda n, w: "%d %s%s" % (n, w, "" if n == 1 else "s")
        return {"kind": "albums", "summary": plural(len(albums), "album") + " \u00b7 " + plural(len(singles), "single"),
                "items": [row(a, "Album") for a in albums] + [row(a, "Single") for a in singles]}
    if uri.endswith(":collection"):
        return {"kind": "tracks", "items": cmd_liked_tracks()}
    raise ApiError("Can't open " + uri, 400)


SPOTIFYD_NAME = "Desktop (spotifyd)"   # device_name in spotifyd/spotifyd.conf
RESUME_CHECK = 1.5                     # seconds to wait before checking that a transfer started playing


def is_local(dev):
    """The Spotify app on this computer (Spotify names it after the host) or spotifyd."""
    name = (dev or {}).get("name", "")
    return name == SPOTIFYD_NAME or name.lower() == socket.gethostname().lower()


def local_device(devs):
    """Where 'this PC' plays: the Spotify app when it is open, else spotifyd."""
    app = next((d for d in devs if d.get("name") != SPOTIFYD_NAME and is_local(d)), None) \
        or next((d for d in devs if d.get("type") == "Computer" and d.get("name") != SPOTIFYD_NAME), None)
    daemon = next((d for d in devs if d.get("name") == SPOTIFYD_NAME), None)
    return app or daemon


def ensure_device():
    """If nothing is active, pick where to play: this PC (app, else spotifyd), else any device."""
    devs = (api("GET", "/me/player/devices") or {}).get("devices", [])
    if any(d.get("is_active") for d in devs):
        return None
    if not devs:
        raise ApiError("No Spotify device: start spotifyd (dinitctl --user start spotifyd) or open Spotify", 404)
    pick = local_device(devs) or devs[0]
    return pick.get("id")


def last_played():
    items = (api("GET", "/me/player/recently-played", {"limit": 1}) or {}).get("items", [])
    if not items:
        return None
    t = items[0].get("track") or {}
    return {"track": track_item(t), "context": (items[0].get("context") or {}).get("uri", "")}


def transfer_here():
    """Spotify Connect transfer to this PC: the same song carries on where it was."""
    devs = (api("GET", "/me/player/devices") or {}).get("devices", [])
    dev = local_device(devs)
    if not dev:
        raise ApiError("This PC isn't a Spotify device: start spotifyd (dinitctl --user start spotifyd) or open Spotify", 404)
    api("PUT", "/me/player", body={"device_ids": [dev["id"]], "play": True})
    return dev["id"]


def cmd_resume():
    """Play: resume where it is; with nothing active anywhere, carry on here from where Spotify
    (phone, app, panel) last stopped, else start the last played song in its playlist / album."""
    try:
        api("PUT", "/me/player/play")
        return {"ok": True}
    except ApiError as e:
        if e.status != 404:
            raise
    dev = transfer_here()
    if not FIXTURE:
        time.sleep(RESUME_CHECK)
    state = api("GET", "/me/player")
    if state and state.get("is_playing"):
        return {"ok": True, "how": "transfer"}
    last = last_played()
    if not last or not last["track"]:
        return {"ok": True, "how": "transfer"}
    body = {"context_uri": last["context"], "offset": {"uri": last["track"]["uri"]}} if last["context"] \
        else {"uris": [last["track"]["uri"]]}
    api("PUT", "/me/player/play", {"device_id": dev}, body)
    return {"ok": True, "how": "last"}


def player(method, endpoint, query=None, body=None):
    try:
        return api(method, endpoint, query, body)
    except ApiError as e:
        if e.status != 404:
            raise
        dev = ensure_device()
        if not dev:
            raise
        q = dict(query or {})
        q["device_id"] = dev
        return api(method, endpoint, q, body)


def cmd_play(args):
    body = {}
    ctx = args[0] if args else ""
    if ctx == "liked":                    # Liked Songs as a context
        ctx = "spotify:user:%s:collection" % me_id()
    track = args[1] if len(args) > 1 else ""
    if ctx.startswith("spotify:track:"):
        body["uris"] = [ctx]
    elif ctx:
        body["context_uri"] = ctx
        if track:
            body["offset"] = {"uri": track}
    player("PUT", "/me/player/play", body=body or None)
    return {"ok": True}


SIMPLE = {
    "pause": ("PUT", "/me/player/pause"),
    "next": ("POST", "/me/player/next"), "prev": ("POST", "/me/player/previous"),
}


def dispatch(cmd, args):
    """Run one command and return its JSON value (raises ApiError). Used by the one-shot command
    line and by serve(), so both speak exactly the same commands."""
    ok = {"ok": True}
    if cmd == "status":
        cfg = read_json("config.json", {}) or {}
        tok = read_json("token.json", {}) or {}
        return {"configured": bool(cfg.get("client_id")) or bool(FIXTURE), "loggedIn": bool(tok.get("refresh_token")) or bool(FIXTURE)}
    if cmd == "set-client":
        cid = (args[0] if args else "").strip()
        if not cid.isalnum():
            raise ApiError("That doesn't look like a client ID", 400)
        write_private("config.json", {"client_id": cid})
        return ok
    if cmd == "login":
        return login()
    if cmd == "logout":
        for name in ("token.json", "me.json"):
            try:
                os.remove(path(name))
            except OSError:
                pass
        return ok
    if cmd == "state":
        return cmd_state()
    if cmd == "liked":
        return cmd_liked(args[0])
    if cmd in ("like", "unlike"):
        api("PUT" if cmd == "like" else "DELETE", "/me/library", {"uris": args[0]})
        return ok
    if cmd == "recent":
        return cmd_recent()
    if cmd == "playlists":
        return cmd_playlists()
    if cmd == "artists":
        return cmd_artists()
    if cmd == "albums":
        return cmd_albums()
    if cmd == "liked-tracks":
        return cmd_liked_tracks()
    if cmd == "open":
        return cmd_open(args[0])
    if cmd == "play":
        return cmd_play(args)
    if cmd == "resume":
        return cmd_resume()
    if cmd == "transfer":
        transfer_here()
        return ok
    if cmd == "last":
        return last_played()
    if cmd in SIMPLE:
        player(*SIMPLE[cmd])
        return ok
    if cmd == "seek":
        player("PUT", "/me/player/seek", {"position_ms": int(args[0])})
        return ok
    if cmd == "shuffle":
        player("PUT", "/me/player/shuffle", {"state": "true" if args[0] == "on" else "false"})
        return ok
    if cmd == "repeat":
        if args[0] not in ("off", "context", "track"):
            raise ApiError("repeat: off, context or track", 400)
        player("PUT", "/me/player/repeat", {"state": args[0]})
        return ok
    if cmd == "volume":
        player("PUT", "/me/player/volume", {"volume_percent": max(0, min(100, int(args[0])))})
        return ok
    if cmd == "add":
        api("POST", "/playlists/%s/items" % uri_id(args[0]), body={"uris": [args[1]]})
        return ok
    if cmd == "queue":
        player("POST", "/me/player/queue", {"uri": args[0]})
        return ok
    raise ApiError("unknown command " + cmd, 400)


def main(argv):
    global STATE
    if len(argv) < 3 or argv[0] != "--state":
        out({"error": "usage: spotify.py --state <dir> <command> [args]"})
        return 2
    STATE, cmd, args = argv[1], argv[2], argv[3:]
    if cmd == "serve":
        serve()
        return 0
    try:
        out(dispatch(cmd, args))
    except ApiError as e:
        out({"error": str(e), "status": e.status})
        return 1
    except (IndexError, ValueError) as e:
        out({"error": "bad arguments: %s" % e, "status": 400})
        return 1
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
