# Keeping this desktop alive

Written for you, in plain English, for the day nobody is helping with it. Skim "Where to look" and "When an update breaks something" first.

## How it fits together

- **This folder is a working copy.** Your deploy script copies it into `~/.config`. Nothing here changes your desktop until you copy it over and reload (`hyprctl reload` for Hyprland, restart Quickshell for the shell).
- **Hyprland** (`hypr/*.lua`): window manager, keybinds, window rules, monitors. Lua, not the old config language.
- **Quickshell** (`quickshell/`): everything you see besides windows: the bar, menus, launcher, notifications, side panel, screenshots, games. QML files. `shell.qml` is the entry point, `taskbar/Bar.qml` creates one bar plus its popups per monitor.
- **Theme**: `quickshell/theme/themes.json` holds the palettes. `quickshell/theme/apply.py` turns them into colour files for kitty, Hyprland, hyprlock, fastfetch, btop, bottom (`btm`, the process monitor), fish and the emoji picker (it writes into `~/.config`, never into this folder). Quickshell runs it when you pick a theme and at start. You can also run it by hand: `python3 ~/.config/quickshell/theme/apply.py dusty`.
- **Helpers** in `quickshell/scripts/` (plain Python / sh, standard tools only): `games.py` (lists games), `spotify.py` (Spotify login and API), `binds.py` (cheat sheet), `procs.py` (Task Manager), `app-owner.sh` (launcher Uninstall), `share-picker.sh` (screen-share dialog, started by the portal).
- **Docs for the next assistant**: `CLAUDE.md` (rules and what exists) and `FEATURES.md` (feature list). Any AI assistant can read them; paste them in first.

## Where to look when something is wrong

| Symptom | Open |
|---|---|
| Keybind does nothing | `hypr/binds.lua` |
| Window opens in the wrong place / floats wrongly | `hypr/windowrules.lua` |
| Monitors, scaling | `hypr/monitors.lua` |
| Something not starting at login | `hypr/autostart.lua` |
| A menu looks broken or is missing | the file in `quickshell/popups/` with its name |
| Bar items | `quickshell/taskbar/Bar.qml` and the file named after the item |
| Sizes and spacing | `quickshell/MenuStyle.qml` (all named sizes live here) |
| Colours wrong in one app | `quickshell/theme/templates/` for that app, then run `apply.py` |
| Notifications | `quickshell/popups/NotificationDaemon.qml`, `NotificationStore.qml` |
| Games menu empty | `quickshell/scripts/games.py` (run it, see "Games" below) |
| Games grid / chips / Add game look or act wrong (menu and launcher tab) | `quickshell/popups/GamesView.qml` (shared); the windows around it are `GamesMenu.qml` and `AppLauncher.qml` |
| Share picker looks wrong or never appears | `quickshell/sharepicker.qml`, `quickshell/scripts/share-picker.sh`, `hypr/xdph.conf` (restart the portal after changes: `pkill xdg-desktop-portal-hyprland`). If it never appears, check the script is executable and run it by hand. If it asks several times, `cat $XDG_RUNTIME_DIR/sharepicker/log` shows how many requests came in (an answer is reused for 8 s: `REUSE_SECONDS` in the script) |
| Cheat sheet empty or wrong labels | `quickshell/scripts/binds.py` (run it by hand on `hypr/binds.lua`); labels are the `-- help: Group \| Label` comments in `hypr/binds.lua` / `inputs.lua` |
| Services panel empty or garbled | run `dinitctl --user list` and `dinitctl --system list` in a terminal; if the format differs, fix `parse()` in `quickshell/popups/ServicesPanel.qml` |
| Phone panel empty | `kdeconnect-cli -l`; is `kdeconnectd` running? `quickshell/popups/PhoneTab.qml` |
| Launcher Uninstall finds nothing | `sh quickshell/scripts/app-owner.sh <desktop-id>` |
| Spotify panel errors / stops working | Run `python3 ~/.config/quickshell/scripts/spotify.py --state ~/.local/state/quickshell/by-shell/*/spotify state` and read the error. "Not logged in": log in again from the panel. A 403/404 after a Spotify change: the endpoint list is at the top of `scripts/spotify.py`, fix it there. To start over, delete the `spotify` folder in Quickshell's state dir |
| Spotify panel says no device / spotifyd silent | `dinitctl --user status spotifyd`; run `spotifyd --no-daemon` in a terminal to see its errors; log in again with `spotifyd authenticate`. Config: `~/.config/spotifyd/spotifyd.conf` (option names: `spotifyd --help`) |
| Task Manager empty / wrong numbers | `python3 ~/.config/quickshell/scripts/procs.py --once` prints one sample; `quickshell/popups/TaskManager.qml` |
| Spotify folders / Library tab missing or stale | The Spicetify extension `~/.config/spicetify/Extensions/qs-folders.js` only sends while the Spotify app runs and the panel is open (a plain POST to 127.0.0.1:8899). If a Spotify update ever starts blocking that (Chromium's Local Network Access), adding `--disable-features=LocalNetworkAccessChecks` to `~/.config/spotify-flags.conf` is the known workaround. After a Spotify update run `spicetify apply` again. To see errors: `spicetify enable-devtools`, then Ctrl+Shift+J in Spotify. The saved tree: `folders.json` in the panel's state dir |
| Spotify black after an update or a Spicetify change | Spicetify's backup is from an older Spotify, so `spicetify restore` puts old interface files into the new Spotify. Fix: `yay -S spotify` (fresh, matching files), check it opens, then `spicetify backup apply`. After every Spotify update use exactly that, never `spicetify restore backup apply` on an old backup |
| Launcher / clipboard | `quickshell/popups/AppLauncher.qml` |
| Super+Q closes a menu instead of a window / stops doing so | `hypr/binds.lua` (the `closeMenuOrWindow` line) and the `menus_` block in `quickshell/taskbar/Bar.qml` |

## The debug loop (works for almost everything)

1. Open a terminal and run `qs` (this starts the shell with its log on screen). If Quickshell is already running, stop it first (`pkill quickshell`).
2. Do the thing that breaks. Errors name the **file and line**, for example `@popups/GamesMenu.qml[465:14]: Illegal method name`.
3. Open that file at that line. Most breakages after an update are a renamed or removed property: search Quickshell's docs (quickshell.org) for the new name.
4. For Hyprland, run `hyprctl reload`: it shows an error bar with the file and line of a bad Lua line. The Lua API reference is `/usr/share/hypr/stubs/hl.meta.lua`.
5. One broken QML file usually breaks only its own menu. A broken `Bar.qml` or `shell.qml` breaks everything, so keep a copy of the last working version (see "Safety net").

## What is most likely to break on updates

1. **Hyprland's Lua API** (new, still changing). Symptom: error bar on reload, or a bind that does nothing. Read the release notes before updating Hyprland: github.com/hyprwm/Hyprland/releases.
2. **Quickshell** (version 0.x, can rename or remove things between minor versions). Symptom: a popup missing, errors in the `qs` log. Changelog: github.com/quickshell-mirror/quickshell (CHANGELOG.md), docs at quickshell.org.
3. **Steam's file layout** (cover art folder, shortcuts file). Symptom: games show as letter tiles or some are missing. Only `scripts/games.py` needs fixing.
4. **hyprlock** config syntax. Symptom: lock screen looks wrong. It falls back to built-in colours if the generated colour file is missing; test from a second TTY, not your only session.

Stable and unlikely to break: the Python scripts, grim, wl-copy, cliphist, PipeWire, BlueZ, the fonts.

## Safe update routine

1. Don't update Hyprland and Quickshell in the same go. Do one, log out and in, check the bar, menus and binds, then do the other.
2. Keep old packages: don't clean the pacman cache (`/var/cache/pacman/pkg`) right before an update.
3. If an update breaks things, downgrade just that package: `doas pacman -U /var/cache/pacman/pkg/<old-package-file>`, then add it to `IgnorePkg` in `/etc/pacman.conf` until you have time to fix it properly.
4. Update with `yay -Syu`, not blind partial upgrades.

## Safety net

- **Before changing anything**, copy the whole folder: `cp -r ~/qs-test ~/qs-test.bak`. Better: `cd ~/qs-test && git init && git add -A && git commit -m "working"`. With git, `git diff` shows what you changed and `git checkout <file>` undoes it. (Not set up yet.)
- The deployed copy in `~/.config` is a second backup of your last good state.

## Games

- Run the helper by hand to see exactly what the menu sees: `python3 -I ~/.config/quickshell/scripts/games.py --custom ~/.local/state/quickshell/by-shell/*/games.json` (the exact state folder name differs; look under `~/.local/state/quickshell`). It prints one JSON list. Empty list means it found nothing.
- Steam games and Steam shortcuts launch through Steam. Your own entries are in `games.json` in Quickshell's state dir; you can edit that file directly.

## Removing things

Every feature is its own file(s). To remove a menu: delete its `popups/` file, its line in `popups/qmldir`, its instance and IPC block in `taskbar/Bar.qml`, and its entry in `Config.qml`'s `SystemPopup` list. `FEATURES.md` lists what exists.

## Getting help

Quickshell: quickshell.org and its Discord/Matrix. Hyprland: wiki.hypr.land and its Discord. Hand any assistant `CLAUDE.md`, `FEATURES.md` and the failing file plus the error line.
