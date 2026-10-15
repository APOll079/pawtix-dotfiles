#!/usr/bin/env python3
"""Build a theme palette from a wallpaper: only the hue and the colourfulness come from the image.

The lightness of every role is fixed (the same ladder cherry and dusty use), so bevels keep their
contrast and text stays readable on any picture. The result has the same keys as an entry in
themes.json (base, shadow, highlight, accent, text, outline, urgent, ...) and is meant for
`apply.py <name> --palette FILE`.

  wallcolors.py IMAGE            print the palette as JSON
  wallcolors.py IMAGE --out FILE write it to FILE (atomically)
"""
import colorsys
import json
import math
import os
import sys
import tempfile

from PIL import Image

Image.MAX_IMAGE_PIXELS = 200_000_000
USAGE = "usage: wallcolors.py IMAGE [--out FILE]"
FALLBACK_HUE = 307      # cherry's hue, used when the picture has no colour at all
MIN_WEIGHT = 8.0        # below this the picture counts as grey


def lum(rgb):
    ch = [v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4 for v in rgb]
    return 0.2126 * ch[0] + 0.7152 * ch[1] + 0.0722 * ch[2]


def contrast(a, b):
    la, lb = lum(a), lum(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def hsl_rgb(h, s, l):
    return colorsys.hls_to_rgb((h % 360) / 360.0, max(0.0, min(1.0, l)), max(0.0, min(1.0, s)))


def hexs(rgb):
    return "#" + "".join(f"{round(max(0.0, min(1.0, c)) * 255):02x}" for c in rgb)


def dominant(path):
    """(hue in degrees, colourfulness 0..1) of the picture, or (None, 0) when it is grey."""
    img = Image.open(path)
    img.draft("RGB", (256, 256))
    img = img.convert("RGB")
    img.thumbnail((96, 96))
    hsv = img.convert("HSV")
    pixels = hsv.get_flattened_data() if hasattr(hsv, "get_flattened_data") else hsv.getdata()
    # (hue bin, hue angle, weight, saturation) of every pixel with real colour and not near black
    cols = []
    for h, s, v in pixels:
        sf, vf = s / 255.0, v / 255.0
        if sf >= 0.12 and vf >= 0.15:
            cols.append((int(h / 256.0 * 36) % 36, h / 256.0 * 2 * math.pi, sf * vf, sf))
    bins = [0.0] * 36
    for b, _, w, _ in cols:
        bins[b] += w
    if sum(bins) < MIN_WEIGHT:
        return None, 0.0
    # Smooth over the neighbouring bins (the hue wraps), take the strongest
    smooth = [bins[i - 1] + 2 * bins[i] + bins[(i + 1) % 36] for i in range(36)]
    peak = max(range(36), key=lambda i: smooth[i])
    # Circular weighted mean of the hues within one bin either side of the peak
    x = y = wsum = ssum = 0.0
    for b, ang, w, sf in cols:
        if min((b - peak) % 36, (peak - b) % 36) <= 1:
            x += w * math.cos(ang)
            y += w * math.sin(ang)
            wsum += w
            ssum += w * sf
    return math.degrees(math.atan2(y, x)) % 360, ssum / wsum


def palette(hue, colour):
    """The role ladder. colour (0..1) scales the saturation of every role a little."""
    if hue is None:
        hue, colour = 220.0, 0.0
    c = max(0.0, min(1.0, colour))
    base = hsl_rgb(hue, 0.20 + 0.45 * c, 0.85)
    highlight = hsl_rgb(hue, 0.30 + 0.45 * c, 0.92)
    shadow = hsl_rgb(hue, 0.10 + 0.20 * c, 0.68)
    text = hsl_rgb(hue, 0.10 + 0.20 * c, 0.13)
    outline = hsl_rgb(hue, 0.15 + 0.40 * c, 0.08)
    fade = hsl_rgb(hue, 0.10 + 0.20 * c, 0.19)
    # Accent: as close to lightness 0.55 as the selection bar can use. Dark outline text or light
    # base text must reach 5:1 on it, and it must stand out from the base.
    sat = 0.30 + 0.35 * c
    accent = None
    for step in range(0, 30):
        for sign in (1, -1):
            l = 0.55 + sign * step * 0.01
            a = hsl_rgb(hue, sat, l)
            if max(contrast(outline, a), contrast(base, a)) >= 5.0 and contrast(base, a) >= 1.8:
                accent = a
                break
        if accent:
            break
    if accent is None:
        accent = hsl_rgb(hue, sat, 0.45)
    # Red-ish pictures would make urgent blend into the accent: use a plain red there
    near_red = min((hue - 16) % 360, (16 - hue) % 360) < 25
    urgent = "#e83939" if near_red else "#ff936c"
    return {
        "base": hexs(base),
        "shadow": hexs(shadow),
        "highlight": hexs(highlight),
        "urgent": urgent,
        "accent": hexs(accent),
        "text": hexs(text),
        "outline": hexs(outline),
        "outlineGradientFade": hexs(fade),
        "defaultWallpaperPath": "",
    }


def main():
    argv = sys.argv[1:]
    out = None
    if "--out" in argv:
        i = argv.index("--out")
        if i + 1 >= len(argv):
            sys.exit(USAGE)
        out = argv[i + 1]
        del argv[i:i + 2]
    if len(argv) != 1 or argv[0].startswith("-"):
        sys.exit(USAGE)
    try:
        hue, colour = dominant(argv[0])
    except (OSError, ValueError, Image.DecompressionBombError) as e:
        sys.exit(f"{argv[0]}: cannot read the image ({e})")
    pal = palette(hue, colour)
    text = json.dumps(pal, indent=4) + "\n"
    if out is None:
        print(text, end="")
        return
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(out)), prefix=".wallcolors.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        os.replace(tmp, out)
    except BaseException:
        try:
            os.remove(tmp)
        except OSError:
            pass
        raise
    print(f"hue {hue if hue is None else round(hue)} colour {colour:.2f} -> {out}")


if __name__ == "__main__":
    main()
