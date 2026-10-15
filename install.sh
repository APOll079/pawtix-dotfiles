#!/usr/bin/env bash
# install.sh - set up this rice (pawtix dotfiles) on Artix with dinit.
#
#   bash install.sh --dry-run    print every step and command, change nothing (start here)
#   bash install.sh              do it
#
# Idempotent: run it as often as you like. It never deletes anything: files it would overwrite in
# ~/.config are copied to ~/config-backup-<date>/ first, system files get a .bak-<date> copy.
# Uses doas (not sudo) and yay. Asks yes/no before the risky steps (Flatpak apps, GTK theme,
# autologin + lock at boot); everything else runs without asking.
#
# Package lists (plain text, edit by hand): packages/pacman.txt, aur.txt, flatpak.txt,
# services-dinit.txt. A "#" starts a comment; comment a line out to skip that package.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
STAMP="$(date +%F-%H%M%S)"
BACKUP="$HOME/config-backup-$STAMP"
DRY=0
TMPDIR_RUN="$(mktemp -d)"          # scratch for filled-in templates; removed on exit (our own temp only)
trap 'rm -rf "$TMPDIR_RUN"' EXIT

# Folders of this repo that go to ~/.config/<name> (plus hyfetch.json)
DEPLOY_DIRS=(hypr quickshell kitty fish btop gtk-3.0 gtk-4.0 nwg-look xsettingsd spotifyd spicetify dinit.d)

for arg in "$@"; do
    case "$arg" in
        -n|--dry-run) DRY=1 ;;
        -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
        *) echo "unknown option: $arg (try --help)" >&2; exit 2 ;;
    esac
done

# --- helpers ---

say()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
note() { printf '   %s\n' "$*"; }
warn() { printf '   \033[33m! %s\033[0m\n' "$*"; }

# Run a command, or only print it in --dry-run
run() {
    if (( DRY )); then
        printf '   [dry-run] %s\n' "$*"
    else
        "$@"
    fi
}

# Write stdin to a file (as root with "root" first), or only print it in --dry-run
write_file() {
    local asroot=0
    if [[ "$1" == root ]]; then asroot=1; shift; fi
    local dest="$1" body
    body="$(cat)"
    if (( DRY )); then
        printf '   [dry-run] write %s:\n' "$dest"
        printf '%s\n' "$body" | sed 's/^/      | /'
        return
    fi
    if (( asroot )); then
        printf '%s\n' "$body" | doas tee "$dest" >/dev/null
    else
        mkdir -p "$(dirname "$dest")"
        printf '%s\n' "$body" > "$dest"
    fi
}

# yes/no question; the default is the capital letter. --dry-run shows the "yes" path.
ask() {
    local question="$1" default="${2:-n}" reply
    if (( DRY )); then
        note "would ask: $question  (dry-run shows what 'yes' does)"
        return 0
    fi
    local hint="[y/N]"; [[ "$default" == y ]] && hint="[Y/n]"
    read -r -p "   $question $hint " reply
    reply="${reply:-$default}"
    [[ "$reply" =~ ^[Yy] ]]
}

# Package names from a list file: first word of each line, comments and blanks skipped
read_list() {
    sed -e 's/#.*//' -e 's/^[[:space:]]*//' "$1" | awk 'NF { print $1 }'
}

have() { command -v "$1" >/dev/null 2>&1; }

# --- init detection + services ---

detect_init() {
    if have dinitctl && [[ -d /etc/dinit.d ]]; then
        echo dinit
    elif have systemctl && [[ -d /run/systemd/system ]]; then
        echo systemd
    else
        echo unknown
    fi
}
INIT="$(detect_init)"

# enable_service <system|user> <name>
enable_service() {
    local scope="$1" name="$2"
    case "$INIT" in
        dinit)
            if [[ "$scope" == system ]]; then
                if [[ -e "/etc/dinit.d/boot.d/$name" ]]; then
                    note "system $name: already enabled"
                elif [[ ! -e "/etc/dinit.d/$name" ]]; then
                    warn "system $name: no service file in /etc/dinit.d (is its -dinit package installed?)"
                else
                    run doas dinitctl enable "$name"
                fi
            else
                if [[ -e "$CONFIG/dinit.d/boot.d/$name" ]]; then
                    note "user $name: already enabled"
                else
                    run dinitctl --user enable "$name"
                fi
            fi
            ;;
        systemd)
            # Stub for later: the service names differ (pipewire.socket, bluetooth, ...)
            warn "systemd: not implemented yet; would enable $scope service $name"
            ;;
        *)
            warn "unknown init system; enable $scope service $name yourself"
            ;;
    esac
}

# --- steps ---

preflight() {
    say "Checks"
    if [[ $EUID -eq 0 ]]; then
        echo "Run this as your normal user, not root (it uses doas where needed)." >&2
        exit 1
    fi
    have pacman || { echo "pacman not found: this script is for Artix / Arch." >&2; exit 1; }
    have doas || { echo "doas not found: install opendoas and set up /etc/doas.conf first." >&2; exit 1; }
    note "repo:   $REPO"
    note "config: $CONFIG"
    note "init:   $INIT"
    (( DRY )) && note "DRY RUN: nothing will be changed"
    [[ "$INIT" == dinit ]] || warn "this rice is made for dinit; services will need manual work"
}

install_pacman() {
    say "Repo packages (pacman)"
    local pkgs missing svcpkgs
    # services-dinit.txt: the package is the third column
    mapfile -t svcpkgs < <(sed -e 's/#.*//' "$REPO/packages/services-dinit.txt" | awk 'NF >= 3 && $3 != "-" { print $3 }')
    mapfile -t pkgs < <(read_list "$REPO/packages/pacman.txt")
    pkgs+=("${svcpkgs[@]}")
    mapfile -t missing < <(pacman -T "${pkgs[@]}" 2>/dev/null)
    if (( ${#missing[@]} == 0 )); then
        note "all ${#pkgs[@]} installed"
        return
    fi
    note "missing: ${missing[*]}"
    run doas pacman -S --needed "${missing[@]}"
}

ensure_yay() {
    have yay && return 0
    say "yay (AUR helper) is missing: building it from the AUR"
    local tmp
    tmp="$(mktemp -d)"
    run doas pacman -S --needed git base-devel
    run git clone https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
    if (( DRY )); then
        note "[dry-run] (cd $tmp/yay-bin && makepkg -si)"
    else
        (cd "$tmp/yay-bin" && makepkg -si)
    fi
}

install_aur() {
    say "AUR packages (yay)"
    local pkgs missing
    mapfile -t pkgs < <(read_list "$REPO/packages/aur.txt")
    mapfile -t missing < <(pacman -T "${pkgs[@]}" 2>/dev/null)
    if (( ${#missing[@]} == 0 )); then
        note "all ${#pkgs[@]} installed"
        return
    fi
    # Repo first: whatever an official repo has (e.g. zen-browser-bin on CachyOS) comes from pacman
    local inrepo=() fromaur=() p
    for p in "${missing[@]}"; do
        if pacman -Si "$p" >/dev/null 2>&1; then inrepo+=("$p"); else fromaur+=("$p"); fi
    done
    if (( ${#inrepo[@]} )); then
        note "from the repos: ${inrepo[*]}"
        run doas pacman -S --needed "${inrepo[@]}"
    fi
    if (( ${#fromaur[@]} )); then
        note "from the AUR: ${fromaur[*]}"
        ensure_yay
        run yay -S --needed "${fromaur[@]}"
    fi
}

install_flatpak() {
    say "Flatpak apps"
    have flatpak || { warn "flatpak not installed (it's in pacman.txt); skipping"; return; }
    local ids missing=()
    mapfile -t ids < <(read_list "$REPO/packages/flatpak.txt")
    for id in "${ids[@]}"; do
        flatpak info "$id" >/dev/null 2>&1 || missing+=("$id")
    done
    if (( ${#missing[@]} == 0 )); then
        note "all ${#ids[@]} installed"
        return
    fi
    note "missing: ${missing[*]}"
    ask "Install these Flatpak apps (per user, from Flathub)?" n || { note "skipped"; return; }
    run flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    run flatpak install --user -y flathub "${missing[@]}"
}

# Copy one repo file to ~/.config, backing up the old file first if it differs
deploy_file() {
    local src="$1" dest="$2" rel="$3"
    if [[ -f "$dest" ]] && cmp -s "$src" "$dest"; then
        return 1
    fi
    if [[ -e "$dest" ]]; then
        run mkdir -p "$(dirname "$BACKUP/$rel")"
        run cp -a "$dest" "$BACKUP/$rel"
    fi
    run mkdir -p "$(dirname "$dest")"
    run cp -a "$src" "$dest"
    return 0
}

deploy() {
    say "Deploy configs to $CONFIG (changed files are backed up to $BACKUP)"
    local changed=0 d f rel
    for d in "${DEPLOY_DIRS[@]}"; do
        [[ -d "$REPO/$d" ]] || continue
        while IFS= read -r -d '' f; do
            rel="${f#"$REPO"/}"
            # xdph.conf needs an absolute path to the share picker: the repo has @HOME@; compare
            # and copy the filled-in version, so an unchanged file stays unchanged
            if [[ "$rel" == hypr/xdph.conf ]]; then
                sed "s#@HOME@#$HOME#g" "$f" > "$TMPDIR_RUN/xdph.conf"
                f="$TMPDIR_RUN/xdph.conf"
            fi
            deploy_file "$f" "$CONFIG/$rel" "$rel" && { changed=$((changed + 1)); note "updated $rel"; }
        done < <(find "$REPO/$d" -type f -not -path '*/__pycache__/*' -print0)
    done
    if [[ -f "$REPO/hyfetch.json" ]]; then
        deploy_file "$REPO/hyfetch.json" "$CONFIG/hyfetch.json" "hyfetch.json" && { changed=$((changed + 1)); note "updated hyfetch.json"; }
    fi
    note "$changed file(s) updated"

    run chmod +x "$CONFIG/quickshell/scripts/share-picker.sh" "$CONFIG/quickshell/scripts/app-owner.sh"

    # Fonts that can't be in the repo (see README)
    local font
    for font in Monaco.ttf Charcoal.ttf; do
        [[ -f "$CONFIG/quickshell/fonts/$font" ]] || warn "missing font $font: put it in $CONFIG/quickshell/fonts/ (see README)"
    done
}

enable_services() {
    say "Services ($INIT)"
    local scope name pkg
    while read -r scope name pkg; do
        # greetd is the login manager: only the autologin step (which asks) turns it on
        [[ "$name" == greetd ]] && continue
        enable_service "$scope" "$name"
    done < <(sed -e 's/#.*//' "$REPO/packages/services-dinit.txt" | awk 'NF >= 2')
}

notification_overrides() {
    say "Notifications: stop mako and dunst from taking the D-Bus name (quickshell owns it)"
    local dir="$HOME/.local/share/dbus-1/services" name file
    for name in fr.emersion.mako org.knopwob.dunst; do
        file="$dir/$name.service"
        local body=$'[D-BUS Service]\nName=org.freedesktop.Notifications\nExec=/bin/false'
        if [[ -f "$file" ]] && [[ "$(cat "$file")" == "$body" ]]; then
            note "$name: already blocked"
        else
            [[ -e "$file" ]] && run cp -a "$file" "$file.bak-$STAMP"
            printf '%s\n' "$body" | write_file "$file"
        fi
    done
}

check_locale() {
    say "Locale"
    local lang="${LANG:-}"
    if [[ "$lang" == *UTF-8* || "$lang" == *utf8* ]]; then
        note "LANG=$lang (fine)"
    else
        warn "LANG is '${lang:-unset}', not UTF-8. Qt (quickshell) needs a UTF-8 locale. To fix:"
        warn "  doas nano /etc/locale.gen    (uncomment en_US.UTF-8 UTF-8)"
        warn "  doas locale-gen && echo 'LANG=en_US.UTF-8' | doas tee /etc/locale.conf"
    fi
}

gtk_theme() {
    say "GTK theme (ClassicPlatinumStreamlined) and icons (RetroismIcons)"
    ask "Link the GTK 4 theme files into ~/.config/gtk-4.0?" n || { note "skipped"; return; }
    local theme="$HOME/.local/share/themes/ClassicPlatinumStreamlined"
    if [[ ! -d "$theme" ]]; then
        warn "theme not found at $theme. Install ClassicPlatinumStreamlined there first, then run this again."
        return
    fi
    local f
    for f in gtk.css assets; do
        if [[ -e "$CONFIG/gtk-4.0/$f" || -L "$CONFIG/gtk-4.0/$f" ]]; then
            note "gtk-4.0/$f exists already, left as is"
        else
            run mkdir -p "$CONFIG/gtk-4.0"
            run ln -s "$theme/gtk-4.0/$f" "$CONFIG/gtk-4.0/$f"
        fi
    done
    [[ -d "$HOME/.local/share/icons/RetroismIcons" || -d /usr/share/icons/RetroismIcons ]] \
        || warn "icon theme RetroismIcons not found (quickshell and xsettingsd use it)"
}

autologin() {
    say "Autologin (greetd) + lock at login (hyprlock)"
    warn "This changes how you log in. The hyprlock design is UNTESTED: test it first with"
    warn "'hyprlock' from a second TTY (Ctrl+Alt+F2) and make sure you can unlock."
    ask "Set up autologin with greetd and lock the session at login?" n || { note "skipped"; return; }

    # greetd: start Hyprland as you on tty1, no greeter
    local conf=/etc/greetd/config.toml user
    user="$(id -un)"
    if [[ -f "$conf" ]] && grep -q "command = \"Hyprland\"" "$conf" && grep -q "user = \"$user\"" "$conf"; then
        note "greetd already starts Hyprland as $user"
    else
        [[ -f "$conf" ]] && run doas cp -a "$conf" "$conf.bak-$STAMP"
        write_file root "$conf" <<EOF
[terminal]
vt = 1

[default_session]
command = "Hyprland"
user = "$user"
EOF
    fi
    enable_service system greetd
    have ly && warn "ly is installed too; only one login manager should run (check /etc/dinit.d/boot.d)"

    # Lock at login: only once hyprlock can't lock you out with missing colours
    local lockconf="$CONFIG/hypr/hyprlock.conf" colours="$CONFIG/hypr/hyprlock-colors.conf"
    if ! have hyprlock || { [[ ! -f "$lockconf" ]] && (( ! DRY )); }; then
        warn "hyprlock or $lockconf missing: not turning on lock at login"
        return
    fi
    if [[ ! -f "$colours" ]]; then
        # hyprlock.conf sets cherry colours before it sources this file, so it works without it,
        # but generate it anyway so the lock screen matches the theme
        note "generating $colours"
        run python3 -I "$CONFIG/quickshell/theme/apply.py" "$(theme_name)" --no-reload
    fi
    if (( ! DRY )) && ! grep -q '^\$' "$lockconf"; then
        warn "$lockconf has no fallback colour variables; not turning on lock at login"
        return
    fi
    if [[ -e "$CONFIG/hypr/lock-at-login" ]]; then
        note "lock at login already on"
    else
        run touch "$CONFIG/hypr/lock-at-login"
        note "lock at login on (delete $CONFIG/hypr/lock-at-login to turn it off)"
    fi
}

# The active theme from quickshell's settings.json (cherry if unknown)
theme_name() {
    local t
    t="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["settings"]["currentTheme"])' "$CONFIG/quickshell/settings.json" 2>/dev/null)"
    echo "${t:-cherry}"
}

summary() {
    say "Done"
    (( DRY )) && note "That was a dry run: nothing changed. Run without --dry-run to do it."
    note "Backups of overwritten configs (if any): $BACKUP"
    note "Next: log out and back in (or reboot), then check the bar, Super+D and Super+S."
    note "Spotify panel: Super+S asks for your Spotify client ID once (see README)."
}

main() {
    preflight
    install_pacman
    install_aur
    install_flatpak
    deploy
    enable_services
    notification_overrides
    check_locale
    gtk_theme
    autologin
    summary
}

main
