#!/usr/bin/env python3
"""List the Hyprland keybinds for the cheat sheet (popups/CheatSheet.qml).

Usage: binds.py <file.lua> [<file.lua> ...]
Reads every `hl.bind(<keys>, ...)` call and prints a JSON list of {keys, group, label}.
The text comes from a trailing comment on the line of the bind:

    hl.bind(mainMod .. " + " .. "Q", ...)  -- help: Windows | Close menu or window

"Windows" is the group, "Close menu or window" the label; the group is optional. A bind without
a help comment is listed under "Other" with a label made from its dispatcher.
A `for i = 1, 4 do` loop around a bind turns `i` into "1-4".
Plain Python, standard library only.
"""
import json
import re
import sys

MAIN_MOD = "SUPER"
KEY_NAMES = {
    "super": "Super", "shift": "Shift", "ctrl": "Ctrl", "control": "Ctrl", "alt": "Alt",
    "return": "Enter", "enter": "Enter", "space": "Space", "escape": "Esc", "period": ".",
    "comma": ",", "left": "Left", "right": "Right", "up": "Up", "down": "Down",
    "print": "Print", "mouse_down": "Scroll down", "mouse_up": "Scroll up",
    "mouse:272": "Left drag", "mouse:273": "Right drag", "mouse:275": "Side button 1", "mouse:276": "Side button 2",
}
GROUP_ORDER = ["Apps", "Windows", "Workspaces", "Screen", "Desktop", "Mouse", "Media"]
HELP = re.compile(r"--\s*help:\s*(?:([^|]+?)\s*\|\s*)?(.+?)\s*$")
FOR = re.compile(r"^\s*for\s+(\w+)\s*=\s*(\d+)\s*,\s*(\d+)\s+do\b")


def first_arg(text):
    """The first argument of a call: text after `(` up to the top-level comma."""
    depth, quote, i = 0, None, 0
    while i < len(text):
        c = text[i]
        if quote:
            if c == "\\":
                i += 1
            elif c == quote:
                quote = None
        elif c in "\"'":
            quote = c
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            if depth == 0:
                return text[:i]
            depth -= 1
        elif c == "," and depth == 0:
            return text[:i]
        i += 1
    return text


def evaluate(expr, loop):
    out = ""
    for part in expr.split(".."):
        part = part.strip()
        if part == "mainMod":
            out += MAIN_MOD
        elif len(part) >= 2 and part[0] in "\"'" and part[-1] == part[0]:
            out += part[1:-1]
        elif loop and part == loop[0]:
            out += "%s-%s" % (loop[1], loop[2])
        else:
            out += part
    return out


def pretty(keys):
    names = []
    for k in (p.strip() for p in keys.split("+")):
        k = k.strip()
        low = k.lower()
        if low in KEY_NAMES:
            names.append(KEY_NAMES[low])
        elif re.fullmatch(r"[A-Za-z]", k):
            names.append(k.upper())
        else:
            names.append(k if re.search(r"\d|XF86|^F\d+$", k) else k.capitalize())
    return "+".join(names)


def dispatcher_label(rest):
    m = re.search(r"hl\.dsp\.([\w.]+)", rest)
    return m.group(1).replace(".", " ").replace("_", " ") if m else "custom action"


def parse(path):
    binds, loop = [], None
    for line in open(path, encoding="utf-8"):
        m = FOR.match(line)
        if m:
            loop = (m.group(1), m.group(2), m.group(3))
            continue
        if re.match(r"^end\b", line):
            loop = None
            continue
        m = re.search(r"\bhl\.bind\(", line)
        if not m or line.lstrip().startswith("--"):
            continue
        rest = line[m.end():]
        keys = pretty(evaluate(first_arg(rest), loop))
        h = HELP.search(line)
        group, label = ("Other", dispatcher_label(rest)) if not h else (h.group(1) or "Other", h.group(2))
        binds.append({"keys": keys, "group": group, "label": label})
    return binds


if __name__ == "__main__":
    result = []
    for p in sys.argv[1:]:
        try:
            result += parse(p)
        except OSError:
            pass
    rank = lambda b: GROUP_ORDER.index(b["group"]) if b["group"] in GROUP_ORDER else len(GROUP_ORDER)
    result.sort(key=rank)  # stable: file order inside a group
    print(json.dumps(result))
