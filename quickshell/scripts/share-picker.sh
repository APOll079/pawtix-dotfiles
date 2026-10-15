#!/bin/sh
# Screen-share picker for xdg-desktop-portal-hyprland (custom_picker_binary in hypr/xdph.conf).
# Runs the Quickshell picker (quickshell/sharepicker.qml) and prints its choice on stdout in the
# format the portal expects, e.g. "[SELECTION]r/screen:DP-1" or "[SELECTION]/window:123456".
# Printing nothing means cancelled. The portal passes XDPH_WINDOW_SHARING_LIST and
# XDPH_OUTPUT_SHARING_LIST in the environment, and --allow-token when "remember" is the default.
#
# Apps like Discord ask the portal for the same share several times in a row, and the portal
# starts one picker per request. So: only one picker runs at a time (the others wait on a lock),
# and an answer given less than REUSE_SECONDS ago is handed to the next request as it is, so one
# click is enough. A cancel is reused as well. Events go to $SHAREPICKER_STATE/log (kept short).

REUSE_SECONDS=8

# The portal may start us with a thin environment, so fill in what Quickshell needs.
export PATH="${PATH:-/usr/local/bin:/usr/bin:/bin}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export HOME="${HOME:-$(getent passwd "$(id -u)" | cut -d: -f6)}"
export QS_NO_APPLY=1
for arg in "$@"; do
    [ "$arg" = "--allow-token" ] && export SHAREPICKER_REMEMBER=1
done

state="${SHAREPICKER_STATE:-$XDG_RUNTIME_DIR/sharepicker}"
mkdir -p "$state" || exit 1
log="$state/log"
last="$state/last"
note() { printf '%s %s %s\n' "$(date +%T)" "$$" "$*" >> "$log"; }

# One picker at a time: later requests queue here until the earlier one has answered
exec 9>"$state/lock"
command -v flock >/dev/null 2>&1 && flock 9

if [ -f "$last" ]; then
    age=$(( $(date +%s) - $(stat -c %Y "$last") ))
    if [ "$age" -le "$REUSE_SECONDS" ]; then
        note "replay (answered ${age}s ago)"
        cat "$last"
        exit 0
    fi
fi

here=$(cd "$(dirname "$0")" && pwd)
out=$(mktemp "$state/out.XXXXXX") || exit 1
trap 'rm -f "$out"' EXIT
note start
SHAREPICKER_OUT="$out" qs -p "$here/../sharepicker.qml" >/dev/null 2>&1
cp "$out" "$last"
result=$(tr -d '\n' < "$out")
note "result: ${result:-cancelled}"
# keep the log short
tail -n 60 "$log" > "$log.tmp" && mv "$log.tmp" "$log"
cat "$last"
