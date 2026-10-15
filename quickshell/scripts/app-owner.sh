#!/bin/sh
# Which package owns a launcher entry? Usage: app-owner.sh <desktop-entry-id>
# Prints "pacman:<package>" or "flatpak:<app id>"; prints nothing when unknown.
id="$1"
case "$id" in ''|*/*|*..*) exit 0 ;; esac
for d in /usr/share/applications "$HOME/.local/share/applications" \
         /var/lib/flatpak/exports/share/applications "$HOME/.local/share/flatpak/exports/share/applications"; do
    f="$d/$id.desktop"
    [ -f "$f" ] || continue
    case "$d" in
        *flatpak*) echo "flatpak:$id"; exit 0 ;;
    esac
    pkg=$(pacman -Qoq "$f" 2>/dev/null | head -n 1)
    [ -n "$pkg" ] && { echo "pacman:$pkg"; exit 0; }
done
