#!/usr/bin/env python3
"""Hue-shift the blue icons of RetroismIcons towards the active accent (called by apply.py).

RetroismIcons (linux-retroism, MIT) has fixed blue folders and file icons. This reads the installed
copy and writes a copy next to it as QsRetroIcons, with every blue pixel (hue 180-260 degrees)
rotated so the blue family lands on the accent's hue. Lightness and saturation are kept, so the
chunky shading survives; reds, oranges, greens and greys are left alone. The original is never
touched and none of its files live in this repo.

The copy lists RetroismIcons in `Inherits`, so an icon missing from it still resolves.
"""
import colorsys
import os
import re

from PIL import Image, ImageChops

NAME = "QsRetroIcons"
SOURCE = "RetroismIcons"
BLUE_FROM, BLUE_TO = 180, 260   # degrees: the blue family
BLUE_CENTRE = 225               # where the theme's folders sit; this hue becomes the accent's
MIN_SAT = 40                    # of 255: paler pixels count as grey and stay


def _shift(accent_hex):
    r, g, b = (int(accent_hex[i:i + 2], 16) / 255 for i in (1, 3, 5))
    hue = colorsys.rgb_to_hls(r, g, b)[0] * 360
    return round(((hue - BLUE_CENTRE) % 360) / 360 * 256) % 256


def recolour_png(data, delta):
    import io
    im = Image.open(io.BytesIO(data)).convert("RGBA")
    alpha = im.getchannel("A")
    h, s, v = im.convert("RGB").convert("HSV").split()
    lo, hi = round(BLUE_FROM / 360 * 255), round(BLUE_TO / 360 * 255)
    in_band = ImageChops.multiply(h.point(lambda x: 255 if lo <= x <= hi else 0),
                                  s.point(lambda x: 255 if x >= MIN_SAT else 0))
    shifted = h.point(lambda x: (x + delta) % 256)
    out = Image.merge("HSV", (Image.composite(shifted, h, in_band), s, v)).convert("RGB")
    out.putalpha(alpha)
    buf = io.BytesIO()
    out.save(buf, "PNG", optimize=True)
    return buf.getvalue()


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


def _link(path, target):
    """Make path a symlink to target (the source theme's links are all relative, in the same folder)."""
    if os.path.islink(path):
        if os.readlink(path) == target:
            return False
        os.remove(path)
    elif os.path.lexists(path):
        return False            # a real file of the same name: leave it
    os.makedirs(os.path.dirname(path), exist_ok=True)
    os.symlink(target, path)
    return True


def generate(roles, src, dst):
    """Write the hue-shifted copy of the icon theme in src to dst. Returns how many entries changed."""
    delta = _shift(roles["accent"])
    changed = 0
    for root, dirs, files in os.walk(src):
        dirs.sort()
        for fn in sorted(files):
            if fn.startswith(".") or fn.endswith(".sh"):
                continue
            path = os.path.join(root, fn)
            out = os.path.join(dst, os.path.relpath(path, src))
            if os.path.islink(path):
                changed += _link(out, os.readlink(path))
                continue
            with open(path, "rb") as f:
                data = f.read()
            if fn.lower().endswith(".png"):
                data = recolour_png(data, delta)
            elif fn == "index.theme":
                text = data.decode("utf-8")
                text = re.sub(r"^Name=.*$", "Name=" + NAME, text, count=1, flags=re.M)
                if not re.search(r"^Inherits=", text, flags=re.M):
                    text = re.sub(r"^(Comment=.*)$", r"\1\nInherits=" + SOURCE, text, count=1, flags=re.M)
                data = text.encode("utf-8")
            changed += _write_if_changed(out, data)
    return changed
