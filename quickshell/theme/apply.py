#!/usr/bin/env python3
"""Render the theme templates for one theme and reload the apps that changed.

    python3 ~/.config/quickshell/theme/apply.py dusty
    python3 ~/.config/quickshell/theme/apply.py dusty --no-reload   (write files only)

Reads themes.json next to this file, fills every template in templates/ and writes the
results into $XDG_CONFIG_HOME (default ~/.config). Quickshell runs this when the theme changes
in the Themes menu and once at start; it also works from a terminal with nothing else running.
Only files whose content changed are rewritten, and only their apps are reloaded.

Placeholders: {{role}} = #rrggbb, {{role.hex}} = rrggbb, {{role.rgba}} = rrggbbaa,
{{role.rgb}} = r;g;b, {{theme}} = the theme name. Roles are the palette keys plus the
derived light/dark bevel tones and select_bar/select_text (same rules as MenuStyle.qml).
"""
import colorsys
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

REQUIRED = ("base", "shadow", "highlight", "accent", "text", "outline")
RELOAD_TIMEOUT = 10  # seconds per reload command
USAGE = "usage: apply.py <theme> [--no-reload]"

HERE = os.path.dirname(os.path.abspath(__file__))
CONFIG = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")

# template -> (output path under CONFIG, app to reload when it changed)
OUTPUTS = {
    "kitty-colors.conf": ("kitty/theme-colors.conf", "kitty"),
    "hypr-theme_colors.lua": ("hypr/theme_colors.lua", "hyprland"),
    "hyprlock-colors.conf": ("hypr/hyprlock-colors.conf", None),
    "fastfetch.jsonc": ("fastfetch/config.jsonc", None),
    "btop.theme": ("btop/themes/current.theme", None),
    "fish-colors.fish": ("fish/conf.d/theme-colors.fish", "fish"),
    "hypremoji.css": ("hypremoji/style.css", None),
    "bottom.toml": ("bottom/bottom.toml", None),
}


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def hexs(c):
    return "#%02x%02x%02x" % tuple(max(0, min(255, round(v))) for v in c)


def luminance(h):
    def ch(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = rgb(h)
    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def darker(h, f):
    # Qt.darker: HSV value divided by the factor
    r, g, b = (v / 255 for v in rgb(h))
    hh, s, v = colorsys.rgb_to_hsv(r, g, b)
    return hexs(c * 255 for c in colorsys.hsv_to_rgb(hh, s, v / f))


def derive(p, name):
    missing = [k for k in REQUIRED if not (isinstance(p.get(k), str) and re.fullmatch(r"#[0-9a-fA-F]{6}", p[k]))]
    if missing:
        sys.exit(f"theme {name!r} is missing colour(s): {', '.join(missing)} (each needs #rrggbb in themes.json)")
    roles = {k: v.lower() for k, v in p.items() if isinstance(v, str) and re.fullmatch(r"#[0-9a-fA-F]{6}", v)}
    # MenuStyle.bevelLight = Qt.tint(base, 70% white), bevelDark = Qt.darker(shadow, 1.7)
    roles["light"] = hexs(c * 0.3 + 255 * 0.7 for c in rgb(roles["base"]))
    roles["dark"] = darker(roles["shadow"], 1.7)
    # MenuStyle.selectPair: the accent with the best of base/text/outline, else darken the accent
    acc = roles["accent"]
    best = max((roles[k] for k in ("base", "text", "outline")), key=lambda c: contrast(c, acc))
    if contrast(best, acc) >= 4.5:
        roles["select_bar"], roles["select_text"] = acc, best
    else:
        f = 1.0
        while f < 2.0 and contrast(roles["base"], darker(acc, f)) < 4.5:
            f += 0.05
        roles["select_bar"], roles["select_text"] = darker(acc, f), roles["base"]
    return roles


def render(text, roles, name):
    def sub(m):
        key, fmt = m.group(1), m.group(2)
        if key == "theme":
            return name
        if key not in roles:
            raise KeyError(f"unknown placeholder {{{{{m.group(0)[2:-2]}}}}}")
        h = roles[key]
        return {None: h, "hex": h[1:], "rgba": h[1:] + "ff", "rgb": ";".join(map(str, rgb(h)))}[fmt]
    return re.sub(r"\{\{(\w+)(?:\.(hex|rgba|rgb))?\}\}", sub, text)


def run(cmd, **kw):
    """Run a reload command; never hang or crash the theme switch."""
    try:
        return subprocess.run(cmd, timeout=RELOAD_TIMEOUT, **kw).returncode
    except (OSError, subprocess.TimeoutExpired):
        return -1


def reload(app, path):
    if app == "kitty":
        if run(["pkill", "-USR1", "-x", "kitty"]) == 0:
            return "kitty reloaded (SIGUSR1)"
        return "kitty not running"
    if app == "hyprland":
        if os.environ.get("HYPRLAND_INSTANCE_SIGNATURE") and shutil.which("hyprctl"):
            run(["hyprctl", "reload"], stdout=subprocess.DEVNULL)
            return "hyprctl reload"
        return "Hyprland not running"
    if app == "fish":
        if shutil.which("fish"):
            # Universal variables: running shells pick them up right away
            run(["fish", "--no-config", path])
            return "fish universal colours set"
        return "fish not installed"
    return None


def write(path, text):
    """Atomic write through a unique temp file in the same folder (two runs at once can't clash)."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix="." + os.path.basename(path) + ".")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.remove(tmp)
        except OSError:
            pass
        raise


def main():
    argv = sys.argv[1:]
    if any(a in ("-h", "--help") for a in argv):
        print(__doc__.strip())
        print("\n" + USAGE)
        return
    flags = [a for a in argv if a.startswith("-")]
    unknown = [a for a in flags if a != "--no-reload"]
    if unknown:
        sys.exit(f"unknown option {unknown[0]}\n{USAGE}")
    args = [a for a in argv if not a.startswith("-")]
    no_reload = "--no-reload" in flags
    if len(args) != 1:
        sys.exit(USAGE)
    name = args[0]
    with open(os.path.join(HERE, "themes.json"), encoding="utf-8") as f:
        themes = json.load(f)
    if name not in themes:
        sys.exit(f"unknown theme {name!r}; known: {', '.join(themes)}")
    roles = derive(themes[name], name)

    # Render everything first: a broken template stops the run before any file is touched,
    # so apps are never left half on the old theme and half on the new one
    rendered = []
    for tpl, (rel, app) in OUTPUTS.items():
        try:
            with open(os.path.join(HERE, "templates", tpl), encoding="utf-8") as f:
                out = render(f.read(), roles, name)
        except (OSError, KeyError) as e:
            sys.exit(f"template {tpl}: {e}")
        rendered.append((os.path.join(CONFIG, rel), out, app))

    print(f"theme {name}")
    for path, out, app in rendered:
        try:
            with open(path, encoding="utf-8") as f:
                same = f.read() == out
        except (FileNotFoundError, UnicodeDecodeError):
            same = False
        if same:
            print(f"  unchanged  {path}")
            continue
        write(path, out)
        print(f"  wrote      {path}")
        msg = None if no_reload else reload(app, path)
        if msg:
            print(f"  reload     {msg}")

if __name__ == "__main__":
    main()
