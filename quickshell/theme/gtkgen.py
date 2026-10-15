#!/usr/bin/env python3
"""Recolour the installed GTK theme with the active palette (called by apply.py).

ClassicPlatinumStreamlined (linux-retroism, MIT) is plain CSS: a few literal greys, one blue for
selections, and small PNG assets (arrows, check boxes, sliders). This reads the installed copy and
writes a recoloured copy next to it as QsRetro. The original is never touched and none of its
files live in this repo.

  grey ramp (by brightness):  0 -> outline, .35 -> dark, .69 -> shadow, .86 -> base, 1 -> paper (base mixed 90% towards white)
  the blue selection colour:  select_bar (its text: select_text), light blues tint towards it
  black text (`color: #000`): text
  red / orange / green (errors, warnings, success) stay as they are
"""
import colorsys
import io
import os
import re

from PIL import Image

NAME = "QsRetro"
SOURCE = "ClassicPlatinumStreamlined"
SKIP = {"README.md", "thumbnail.png"}


def _rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def _hex(c):
    return "#%02x%02x%02x" % tuple(max(0, min(255, round(v))) for v in c)


def _lerp(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


class Recolour:
    def __init__(self, roles):
        r = {k: _rgb(roles[k]) for k in ("outline", "dark", "shadow", "base", "light", "text", "select_bar", "select_text")}
        # "Paper": the white of content areas (file lists, text fields). Only a trace of the theme's
        # base colour, so it reads as white and the tinted chrome around it has something to stand against
        r["paper"] = _lerp(r["base"], (255, 255, 255), 0.9)
        self.r = r
        self.ramp = [(0.0, r["outline"]), (0.35, r["dark"]), (0.69, r["shadow"]), (0.86, r["base"]), (1.0, r["paper"])]
        self.cache = {}

    def grey(self, g):
        for (g0, c0), (g1, c1) in zip(self.ramp, self.ramp[1:]):
            if g <= g1:
                return _lerp(c0, c1, (g - g0) / (g1 - g0))
        return self.ramp[-1][1]

    def colour(self, rgb):
        """Map one source colour (0..255 tuple) to the palette."""
        key = tuple(rgb)
        if key in self.cache:
            return self.cache[key]
        mx, mn = max(rgb), min(rgb)
        if (mx - mn) / 255 < 0.08:
            out = self.grey(sum(rgb) / 3 / 255)
        else:
            h, l, _ = colorsys.rgb_to_hls(*(v / 255 for v in rgb))
            if 0.55 <= h <= 0.75:      # the blue selection family: #9999ff down to its light tints
                t = max(0.0, min(1.0, (l - 0.8) / 0.14))
                out = _lerp(self.r["select_bar"], _lerp(self.r["paper"], self.r["select_bar"], 0.15), t)
            else:
                out = rgb
        self.cache[key] = out
        return out


TOKEN = re.compile(
    r"(?P<text>(?<![\w-])color\s*:\s*)#000(?:000)?\b"                  # black text colour
    r"|(?P<selfg>(?<![\w-])color\s*:\s*)#fff(?:fff)?\b"                # white text (selection text inside a selected block)
    r"|#(?P<hex>[0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b"
    r"|rgba?\(\s*(?P<r>\d+)\s*,\s*(?P<g>\d+)\s*,\s*(?P<b>\d+)\s*(?:,\s*(?P<a>[\d.]+)\s*)?\)",
    re.I,
)
BLOCK = re.compile(r"([^{}]*)\{([^{}]*)\}")
DEFINE = re.compile(r"@define-color\s+(\w+)\s+([^;]+);")


def _colour_css(text, rc, selected_block):
    def sub(m):
        if m.group("text"):
            return m.group("text") + _hex(rc.r["text"])
        if m.group("selfg"):
            if selected_block:
                return m.group("selfg") + _hex(rc.r["select_text"])
            return m.group("selfg") + _hex(rc.colour((255, 255, 255)))
        if m.group("hex"):
            h = m.group("hex")
            if len(h) == 3:
                h = "".join(c * 2 for c in h)
            return _hex(rc.colour(_rgb(h)))
        rgb = (int(m.group("r")), int(m.group("g")), int(m.group("b")))
        out = rc.colour(rgb)
        a = m.group("a")
        if a is None:
            return "rgb(%d, %d, %d)" % tuple(round(v) for v in out)
        return "rgba(%d, %d, %d, %s)" % (*(round(v) for v in out), a)
    return TOKEN.sub(sub, text)


def recolour_css(css, rc):
    # @define-color lines first (named colours the theme and apps use)
    def define(m):
        name, val = m.group(1), m.group(2)
        if "selected_fg" in name:
            return "@define-color %s %s;" % (name, _hex(rc.r["select_text"]))
        if re.search(r"(fg|text)_color$", name) and "insensitive" not in name:
            return "@define-color %s %s;" % (name, _hex(rc.r["text"]))
        return "@define-color %s %s;" % (name, _colour_css(val, rc, False))
    css = DEFINE.sub(define, css)

    def block(m):
        sel, body = m.group(1), m.group(2)
        if sel.lstrip().startswith("@define-color"):
            return m.group(0)
        selected = "9999ff" in body.lower()
        return sel + "{" + _colour_css(body, rc, selected) + "}"
    return BLOCK.sub(block, css)


def recolour_png(data, rc):
    img = Image.open(io.BytesIO(data)).convert("RGBA")
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if a:
                px[x, y] = (*(round(v) for v in rc.colour((r, g, b))), a)
    out = io.BytesIO()
    img.save(out, "PNG", optimize=True)
    return out.getvalue()


def _write_if_changed(path, data):
    try:
        with open(path, "rb") as f:
            if f.read() == data:
                return False
    except FileNotFoundError:
        pass
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "wb") as f:
        f.write(data)
    os.replace(tmp, path)
    return True


def generate(roles, src, dst):
    """Write the recoloured copy of the theme in src to dst. Returns how many files changed."""
    rc = Recolour(roles)
    changed = 0
    for root, dirs, files in os.walk(src):
        dirs.sort()
        for fn in sorted(files):
            if fn in SKIP:
                continue
            path = os.path.join(root, fn)
            rel = os.path.relpath(path, src)
            with open(path, "rb") as f:
                data = f.read()
            if fn == "gtk.css":
                data = recolour_css(data.decode("utf-8"), rc).encode("utf-8")
            elif fn.lower().endswith(".png"):
                data = recolour_png(data, rc)
            elif fn == "index.theme":
                data = data.decode("utf-8")
                data = re.sub(r"^Name=.*$", "Name=" + NAME, data, flags=re.M)
                data = re.sub(r"=Mac OS 9 Classic", "=" + NAME, data).encode("utf-8")
            if _write_if_changed(os.path.join(dst, rel), data):
                changed += 1
    return changed
