#!/usr/bin/env python3
"""Render the theme templates for one theme and reload the apps that changed.

    python3 ~/.config/quickshell/theme/apply.py dusty
    python3 ~/.config/quickshell/theme/apply.py dusty --no-reload   (write files only)
    python3 ~/.config/quickshell/theme/apply.py wallpaper --palette FILE   (palette from wallcolors.py)

Reads themes.json next to this file (or, with --palette FILE, the one palette in FILE, a JSON
object like an entry of themes.json; the theme name is only used for {{theme}}), fills every template in templates/ and writes the
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
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # -I leaves the script's folder off sys.path
import gtkgen  # noqa: E402

REQUIRED = ("base", "shadow", "highlight", "accent", "text", "outline")
RELOAD_TIMEOUT = 10  # seconds per reload command
USAGE = "usage: apply.py <theme> [--no-reload] [--palette FILE]"

HERE = os.path.dirname(os.path.abspath(__file__))
CONFIG = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")

# template -> (output path, app to reload when it changed[, folder that must exist]).
# Paths are under CONFIG, or under the home folder when they start with "~/". Third item: other
# apps' files are only written when the app has its folder (an app that isn't installed gets nothing).
OUTPUTS = {
    "kitty-colors.conf": ("kitty/theme-colors.conf", "kitty"),
    "hypr-theme_colors.lua": ("hypr/theme_colors.lua", "hyprland"),
    "hyprlock-colors.conf": ("hypr/hyprlock-colors.conf", None),
    "fastfetch.jsonc": ("fastfetch/config.jsonc", None),
    "btop.theme": ("btop/themes/current.theme", None),
    "fish-colors.fish": ("fish/conf.d/theme-colors.fish", "fish"),
    "hypremoji.css": ("hypremoji/style.css", None),
    "bottom.toml": ("bottom/bottom.toml", None),
    # App themes (CSS / colour files only, never a profile folder). Each is a guess at what the app
    # reads until it was tried live; see CLAUDE.md "App themes".
    "vesktop.css": ("vesktop/themes/qs-retro.css", None, "vesktop"),
    "spicetify-color.ini": ("spicetify/Themes/QsRetro/color.ini", None, "spicetify"),
    "spicetify-user.css": ("spicetify/Themes/QsRetro/user.css", None, "spicetify"),
    "vscodium-package.json": ("~/.vscode-oss/extensions/qs.qs-retro-theme-1.0.0/package.json", None, "~/.vscode-oss/extensions"),
    "vscodium-theme.json": ("~/.vscode-oss/extensions/qs.qs-retro-theme-1.0.0/themes/qs-retro-color-theme.json", None, "~/.vscode-oss/extensions"),
    "zen.css": ("zen-qs/theme.css", None, "~/.zen"),
}


def out_path(rel):
    return os.path.expanduser(rel) if rel.startswith("~/") else os.path.join(CONFIG, rel)


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
    # Syntax colours for editor themes (VSCodium): the accent's hue turned around the wheel, each
    # moved in lightness until it reads (4.5:1) on the lightest background (highlight)
    roles.update(syntax_roles(roles))
    return roles


def readable(hue, sat, bg):
    """A colour of this hue that reads on bg: darker on light backgrounds, lighter on dark ones."""
    light_bg = luminance(bg) > 0.4
    ls = [i / 100 for i in range(45, 14, -1)] if light_bg else [i / 100 for i in range(60, 91)]
    last = None
    for l in ls:
        r, g, b = colorsys.hls_to_rgb((hue % 360) / 360, l, sat)
        last = hexs((r * 255, g * 255, b * 255))
        if contrast(last, bg) >= 4.5:
            break
    return last


def syntax_roles(roles):
    hh, _, _ = colorsys.rgb_to_hls(*(v / 255 for v in rgb(roles["accent"])))
    hue = hh * 360
    bg = roles["highlight"]
    out = {}
    for name, off in (("keyword", 0), ("string", 120), ("number", 60), ("function", 200), ("type", -60)):
        out["syn_" + name] = readable(hue + off, 0.55, bg)
    # Comments: the text colour pulled towards the base until it is just readable
    t, b = rgb(roles["text"]), rgb(roles["base"])
    comment = roles["text"]
    for i in range(0, 101, 5):
        c = hexs(t[k] * (1 - i / 100) + b[k] * (i / 100) for k in range(3))
        if contrast(c, bg) < 4.5:
            break
        comment = c
    out["syn_comment"] = comment
    return out


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
    palette_file = None
    if "--palette" in argv:
        i = argv.index("--palette")
        if i + 1 >= len(argv):
            sys.exit(USAGE)
        palette_file = argv[i + 1]
        del argv[i:i + 2]
    flags = [a for a in argv if a.startswith("-")]
    unknown = [a for a in flags if a != "--no-reload"]
    if unknown:
        sys.exit(f"unknown option {unknown[0]}\n{USAGE}")
    args = [a for a in argv if not a.startswith("-")]
    no_reload = "--no-reload" in flags
    if len(args) != 1:
        sys.exit(USAGE)
    name = args[0]
    if palette_file:
        try:
            with open(palette_file, encoding="utf-8") as f:
                themes = {name: json.load(f)}
        except (OSError, ValueError) as e:
            sys.exit(f"palette {palette_file}: {e}")
        if not isinstance(themes[name], dict):
            sys.exit(f"palette {palette_file}: expected a JSON object")
    else:
        with open(os.path.join(HERE, "themes.json"), encoding="utf-8") as f:
            themes = json.load(f)
    if name not in themes:
        sys.exit(f"unknown theme {name!r}; known: {', '.join(themes)}")
    roles = derive(themes[name], name)

    # Render everything first: a broken template stops the run before any file is touched,
    # so apps are never left half on the old theme and half on the new one
    rendered = []
    for tpl, (rel, app, *rest) in OUTPUTS.items():
        try:
            with open(os.path.join(HERE, "templates", tpl), encoding="utf-8") as f:
                out = render(f.read(), roles, name)
        except (OSError, KeyError) as e:
            sys.exit(f"template {tpl}: {e}")
        needs = rest[0] if rest else None
        rendered.append((out_path(rel), out, app, needs))

    print(f"theme {name}")
    for path, out, app, needs in rendered:
        if needs and not os.path.isdir(out_path(needs)):
            print(f"  skipped    {path} ({needs} not found)")
            continue
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
    gtk_theme(roles, no_reload)


def gtk_theme(roles, no_reload):
    """The recoloured GTK theme (gtkgen.py): a new QsRetro folder next to the installed original."""
    themes = os.path.expanduser("~/.local/share/themes")
    src = os.path.join(themes, gtkgen.SOURCE)
    dst = os.path.join(themes, gtkgen.NAME)
    if not os.path.isdir(src):
        print(f"  skipped    {dst} ({gtkgen.SOURCE} not installed)")
        return
    try:
        changed = gtkgen.generate(roles, src, dst)
    except (OSError, ValueError) as e:
        print(f"  gtk theme failed: {e}", file=sys.stderr)
        return
    print(f"  {'wrote' if changed else 'unchanged'}     {dst}" + (f" ({changed} files)" if changed else ""))
    # libadwaita / GTK 4 apps read ~/.config/gtk-4.0 itself: keep its links on the generated theme,
    # but only replace a link that points into one of the two themes (never a real file of yours)
    for name in ("gtk.css", "assets"):
        link = os.path.join(CONFIG, "gtk-4.0", name)
        want = os.path.join(dst, "gtk-4.0", name)
        if os.path.islink(link):
            old = os.readlink(link)
            if old == want or not any(os.sep + t + os.sep in old for t in (gtkgen.SOURCE, gtkgen.NAME)):
                continue
            os.remove(link)
        elif os.path.lexists(link):
            continue
        os.makedirs(os.path.dirname(link), exist_ok=True)
        os.symlink(want, link)
        print(f"  linked     {link}")
    if changed and not no_reload:
        reload_gtk()


def reload_gtk():
    """Running GTK apps only re-read a theme when its name changes: flip it away and back."""
    gs = shutil.which("gsettings")
    if not gs:
        return
    try:
        cur = subprocess.run([gs, "get", "org.gnome.desktop.interface", "gtk-theme"], capture_output=True, text=True, timeout=RELOAD_TIMEOUT).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return
    if cur != f"'{gtkgen.NAME}'":
        return
    run([gs, "set", "org.gnome.desktop.interface", "gtk-theme", "Adwaita"])
    time.sleep(0.4)
    run([gs, "set", "org.gnome.desktop.interface", "gtk-theme", gtkgen.NAME])
    print("  reload     GTK theme (gsettings flip)")


if __name__ == "__main__":
    main()
