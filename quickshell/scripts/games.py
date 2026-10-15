#!/usr/bin/env python3
"""List installed games as one JSON array for the Games menu (popups/GamesMenu.qml).

    python3 -I games.py [--steam-root DIR] [--custom FILE]

Sources:
  steam     installed games from every Steam library folder's appmanifest files
  shortcut  non-Steam games added through Steam (userdata/*/config/shortcuts.vdf)
  custom    the user's own entries from the "custom" list in --custom (games.json in
            Quickshell's state dir, written by the menu's Add game form)

Each item: {id, title, source, launch: [argv], cwd, dir, art, lastPlayed}.
Steam and shortcut games launch through `steam steam://rungameid/<id>`, so Steam (and Proton
for shortcuts) does the work. Missing files are skipped quietly; this never raises on bad data,
it just lists less. Steam's file formats are not documented by Valve: if art or a source stops
showing up after a Steam update, this file is the place to look (see MAINTENANCE.md).
"""
import argparse
import json
import os
import re
import struct

HOME = os.path.expanduser("~")
STEAM_ROOTS = [
    os.path.join(HOME, ".local/share/Steam"),
    os.path.join(HOME, ".steam/steam"),
    os.path.join(HOME, ".var/app/com.valvesoftware.Steam/.local/share/Steam"),
]
# Steam's own tools show up as installed "apps"; they are not games
TOOL_NAME = re.compile(r"^(Proton\b|Steam Linux Runtime|Steamworks Common)", re.I)
ART_NAMES = ["library_600x900.jpg", "library_capsule.jpg", "header.jpg", "library_header.jpg"]
ART_EXTS = [".png", ".jpg", ".jpeg", ".webp"]


# --- Steam text VDF (appmanifest_*.acf, libraryfolders.vdf) ---

def unescape(s):
    return re.sub(r"\\(.)", lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), s)


def parse_vdf(text):
    """Nested dict from Valve's text KeyValues format."""
    tokens = re.findall(r'"((?:[^"\\]|\\.)*)"|([{}])', text)
    pos = 0

    def block():
        nonlocal pos
        out = {}
        while pos < len(tokens):
            s, brace = tokens[pos]
            pos += 1
            if brace == "}":
                return out
            key = unescape(s)
            if pos >= len(tokens):
                break
            s2, brace2 = tokens[pos]
            pos += 1
            if brace2 == "{":
                out[key] = block()
            else:
                out[key] = unescape(s2)
        return out

    return block()


def read_text(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


# --- Steam binary VDF (shortcuts.vdf) ---

def parse_binary_vdf(data):
    """Nested dict from the binary KeyValues format: 0 map, 1 string, 2 int32, 8 end."""
    pos = 0

    def cstr():
        nonlocal pos
        end = data.index(b"\x00", pos)
        s = data[pos:end].decode("utf-8", errors="replace")
        pos = end + 1
        return s

    def block():
        nonlocal pos
        out = {}
        while pos < len(data):
            t = data[pos]
            pos += 1
            if t == 8:
                return out
            key = cstr()
            if t == 0:
                out[key] = block()
            elif t == 1:
                out[key] = cstr()
            elif t == 2:
                out[key] = struct.unpack_from("<I", data, pos)[0]
                pos += 4
            else:
                raise ValueError("unknown type %d" % t)
        return out

    return block()


def find_art_in(folder):
    """First cover found in a Steam librarycache/<appid> folder, directly or one level down
    (Steam changed the layout over time)."""
    try:
        entries = list(os.scandir(folder))
    except OSError:
        return ""
    dirs = [folder] + [e.path for e in entries if e.is_dir()]
    for name in ART_NAMES:
        for d in dirs:
            p = os.path.join(d, name)
            if os.path.isfile(p):
                return p
    return ""


# --- sources ---

def steam_roots(override):
    if override:
        return [override]
    seen, out = set(), []
    for r in STEAM_ROOTS:
        real = os.path.realpath(r)
        if os.path.isdir(real) and real not in seen:
            seen.add(real)
            out.append(real)
    return out


def steam_games(root):
    libs = {root}
    lf = parse_vdf(read_text(os.path.join(root, "steamapps", "libraryfolders.vdf")))
    for entry in (lf.get("libraryfolders") or lf).values():
        if isinstance(entry, dict) and entry.get("path"):
            libs.add(entry["path"])
    games = []
    for lib in sorted(libs):
        apps = os.path.join(lib, "steamapps")
        try:
            names = sorted(os.listdir(apps))
        except OSError:
            continue
        for fn in names:
            if not (fn.startswith("appmanifest_") and fn.endswith(".acf")):
                continue
            st = parse_vdf(read_text(os.path.join(apps, fn))).get("AppState")
            if not st:
                continue
            try:
                appid = int(st["appid"])
                installed = int(st.get("StateFlags", "0")) & 4
            except (KeyError, ValueError):
                continue
            title = st.get("name", "")
            if not installed or not title or TOOL_NAME.search(title):
                continue
            games.append({
                "id": "steam:%d" % appid,
                "title": title,
                "source": "steam",
                "launch": ["steam", "steam://rungameid/%d" % appid],
                "cwd": "",
                "dir": os.path.join(apps, "common", st.get("installdir", "")),
                "art": find_art_in(os.path.join(root, "appcache", "librarycache", str(appid))),
                "lastPlayed": int(st.get("LastPlayed", "0") or 0),
            })
    return games


def grid_art(config_dir, appid):
    """Art set for a shortcut in Steam's UI: userdata/<uid>/config/grid/<appid>p.<ext>."""
    for stem in ("%dp" % appid, "%d" % appid):
        for ext in ART_EXTS:
            p = os.path.join(config_dir, "grid", stem + ext)
            if os.path.isfile(p):
                return p
    return ""


def shortcut_games(root):
    games = []
    userdata = os.path.join(root, "userdata")
    try:
        users = sorted(os.listdir(userdata))
    except OSError:
        return games
    for uid in users:
        cfg = os.path.join(userdata, uid, "config")
        try:
            with open(os.path.join(cfg, "shortcuts.vdf"), "rb") as f:
                data = parse_binary_vdf(f.read())
        except (OSError, ValueError, IndexError, struct.error):
            continue
        for sc in (data.get("shortcuts") or {}).values():
            if not isinstance(sc, dict):
                continue
            # keys differ in case between Steam versions
            sc = {k.lower(): v for k, v in sc.items()}
            title, appid = sc.get("appname", ""), sc.get("appid")
            if not title or not isinstance(appid, int):
                continue
            gameid = (appid << 32) | 0x02000000
            games.append({
                "id": "shortcut:%d" % gameid,
                "title": title,
                "source": "shortcut",
                "launch": ["steam", "steam://rungameid/%d" % gameid],
                "cwd": "",
                "dir": (sc.get("startdir") or "").strip('"'),
                "art": grid_art(cfg, appid) or (sc.get("icon") if sc.get("icon") and os.path.isfile(sc["icon"]) else ""),
                "lastPlayed": int(sc.get("lastplaytime") or 0),
            })
    return games


def custom_games(path):
    if not path:
        return []
    try:
        entries = json.loads(read_text(path) or "{}").get("custom") or []
    except ValueError:
        return []
    games = []
    for i, e in enumerate(entries):
        if not isinstance(e, dict) or not e.get("name") or not e.get("command"):
            continue
        cover = os.path.expanduser(e.get("cover") or "")
        games.append({
            "id": "custom:%s" % e["name"],
            "title": e["name"],
            "source": "custom",
            "launch": ["sh", "-c", e["command"]],
            "cwd": os.path.expanduser(e.get("dir") or ""),
            "dir": os.path.expanduser(e.get("dir") or ""),
            "art": cover if os.path.isfile(cover) else "",
            "lastPlayed": int(e.get("lastPlayed") or 0),
        })
    return games


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--steam-root")
    ap.add_argument("--custom")
    args = ap.parse_args()
    games, seen = [], set()
    for root in steam_roots(args.steam_root):
        for g in steam_games(root) + shortcut_games(root):
            if g["id"] not in seen:
                seen.add(g["id"])
                games.append(g)
    games += [g for g in custom_games(args.custom) if g["id"] not in seen]
    games.sort(key=lambda g: (-g["lastPlayed"], g["title"].lower()))
    print(json.dumps(games))


if __name__ == "__main__":
    main()
