# pawtix dotfiles

A retro, Win95 / classic-Mac flavoured Hyprland desktop for **Artix Linux (dinit)**.
Bevels, solid title bars, dense rows, chunky icons: everything you see besides app windows is
[Quickshell](https://quickshell.org) (QML).

- **Bar**: workspaces, Start / Themes menus, a Spotify lyric line, system monitor, Bluetooth, tray, clock.
- **Launcher** (Super+D): apps, calculator, session actions, window search, Games tab, clipboard history.
- **Spotify panel** (Super+S): player, Recent, your whole library with folders and pins, lyrics.
  Works with the Spotify app or headless through `spotifyd`.
- **Task Manager** (Ctrl+Shift+Esc), snipping tool (Super+Shift+S), notifications with history,
  screen-share picker, cheat sheet (Super+F1), Bluetooth, KDE Connect, dinit services panel.
- **Theme manager**: one palette file (`quickshell/theme/themes.json`) recolours kitty, Hyprland,
  hyprlock, fish, btop, bottom, fastfetch and the emoji picker in one go.

## Install (fresh Artix + dinit)

```sh
git clone https://github.com/APOll079/pawtix-dotfiles.git
cd pawtix-dotfiles
bash install.sh --dry-run   # read what it would do first
bash install.sh
```

`install.sh` is safe to re-run and never deletes anything. It:

1. installs the package lists in `packages/` (pacman, then the AUR with `yay`, then Flatpak);
2. copies the configs to `~/.config` (files it overwrites are backed up to `~/config-backup-<date>/`);
3. enables the dinit services listed in `packages/services-dinit.txt`;
4. stops mako and dunst from grabbing notifications (Quickshell owns them);
5. checks the locale is UTF-8.

It asks first before installing Flatpak apps, linking the GTK theme, and setting up autologin with
greetd plus locking at login (default **no**: test `hyprlock` from a second TTY first).

The lists in `packages/` are plain text: comment a line out with `#` to skip it. Each file has a
separate "apps I use" section you can trim.

## Deploy changes

After editing this folder, copy it over again: `bash install.sh` (it only copies what changed),
then `hyprctl reload` and restart Quickshell (`pkill quickshell; quickshell &`).

## Fonts you have to get yourself

These are proprietary, so they are not in this repo:

- **Monaco**: put `Monaco.ttf` in `~/.config/quickshell/fonts/` *and* `~/.local/share/fonts/`
  (kitty and hyprlock use it too).
- **Charcoal**: put `Charcoal.ttf` in `~/.config/quickshell/fonts/` (menu titles).

Bundled here: Liberation Sans (with its licence) and Material Symbols (the icons).

## Themes and icons

The look is inspired by [linux-retroism](https://github.com/diinki/linux-retroism) by diinki.

The GTK theme **ClassicPlatinumStreamlined** and the icon theme **RetroismIcons** are not in this
repo. Install them yourself into `~/.local/share/themes/` and `~/.local/share/icons/`.
The installer only links the GTK 4 files.

## Also outside this repo

- **Spotify panel**: needs Spotify Premium and your own Spotify developer app (free). Super+S
  walks you through it once. For folders and pins, also enable the Spicetify extension:
  `spicetify config extensions qs-folders.js && spicetify apply`.
- Wallpaper and profile picture: `~/Pictures/wallpaper.png` and `~/Pictures/profile.PNG`.

## Docs

- `MAINTENANCE.md`: plain-English upkeep guide (updates, what to check when something breaks).
- `FEATURES.md`: what exists and what's planned.
- `CLAUDE.md`: the design rules and a detailed map of everything.
