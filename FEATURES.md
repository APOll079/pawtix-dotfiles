# Features

Style: cherry retro, bevels, no rounding/blur/shadows, Config.colors only. Desktop only (no battery, brightness or wifi).
Item numbers are the ids from the approval list. This file has two halves: **Planned** (what is left) and **Done** (what exists, one line each; details live in CLAUDE.md).

## Planned

### Next up
- fstab fix (waiting for your config; outside the repo, commands only)
- 15. Drag-to-reorder pinned apps (Move up / Move down exists)
- Bluetooth PIN agent: only devices that ask for a PIN need it (blueman's agent works until then)
- 29. hyprlock at boot: autologin on tty1 plus `hl.exec_cmd("hyprlock")` in autostart.lua. The autologin part is a dinit/agetty change outside qs-test (give the commands, don't run them). Also finish and test the hyprlock cherry redesign

### Needs a live test (built, not yet confirmed on the desktop)
- Spotify folders: install the Spicetify extension, open the panel and the Spotify app; folders appear in Lists within a minute
- Menus over a fullscreen video (clicks stay in the menu); Spotify: Play here from the phone, Play with nothing active carries on; Task Manager (Ctrl+Shift+Esc): End task / Kill on your own apps, Performance graphs
- spotifyd: panel plays with the Spotify app closed; lyrics / bar text follow spotifyd. Spotify drawer closes when you click another program (same monitor and the other one)
- Notification upgrades: grouped toasts with a count, progress bars, Reply (inline reply from Vesktop/Discord, if they offer it), grouped history, history kept after a Quickshell restart
- Clean-up pass: every search box (now the shared SearchBox: arrows, Enter, Escape in the launcher, games, cheat sheet, services, screenshots, Spotify), Super+Q / click-outside closing on every menu, Services System actions
- Spotify panel (Super+S): create the developer app, log in, then every control, Recent, library tabs, opening a playlist, Lyrics tab; the new animations (menus, hovers, Hyprland windows / workspaces)
- Launcher Hide / Uninstall (Hidden chip), keybind cheat sheet (Super+F1), Services panel (does `dinitctl --user list` / `--system list` print the format the parser expects? does System need doas to list?), Phone tab in the side panel (needs the KDE Connect app on the phone, same Wi-Fi, firewall ports 1714-1764)
- Bluetooth pairing / trust / forget
- GTK theme: restart Quickshell once (it writes QsRetro), then `gsettings set org.gnome.desktop.interface gtk-theme QsRetro`: Nemo, a GTK 4 app, a theme switch re-colouring open windows (the Adwaita flip), the buttons / checkboxes / selections in every theme
- App themes: each app's one-time setup (CLAUDE.md "App themes"), then a theme switch: do Vesktop's variables, Spotify's colours, VSCodium's extension folder and Zen's @import really take effect?
- Wallpaper colours: "Set + colours" on a real wallpaper, the Themes menu card "wallpaper", plain Set while that theme is active, the palette surviving a restart
- Wallpaper browser: Set on DP-1 / DP-2 / All, each fit mode, the choice coming back after a Quickshell restart and after a reboot (hyprpaper's error text and start-up timing are guesses)
- Snipping overlay: region drag, Screen / All on DP-1, toast thumbnail and click; History multi-select, viewer, multi-copy paste, multi-delete
- Games menu and the launcher's Games / Clipboard tabs: shortcut launch, Add game, hide / remove, filter chips, Ctrl+Tab; Super+Q closing menus; the grouped process monitor (bottom)
- Screen-share picker (start a share from Discord, a browser or OBS; restart the portal first), screen-share icon, idle lock / DPMS timings, per-app volume grouping, Calendar clicks, tray tooltips, Spotify notification `appName` match (a guess), Workspaces.qml click dispatch and centred numbers

### Theming run (LAST, as its own run, after you approve)
- 33b. Qt theme: no Qt config exists yet (qt6ct would be a new package; ask first)

Rules relaxed for the theming run only: CLAUDE.md says not to touch non-cherry themes in themes.json or kitty color0-15; the run may do both once you approve it.

### Theming run: what's left of the original design
- Built: palettes in `quickshell/theme/themes.json`, live reading in Config.qml, templates + `apply.py` for kitty, Hyprland, hyprlock, fastfetch, btop, bottom, fish, hypremoji, the app themes and the GTK theme; wallpaper browser and palettes from a wallpaper.
- Still to do: Qt only.
- Rule relaxed for this run only: the theme manager may touch the non-cherry palettes in themes.json and kitty color0-15, once approved.

### Small open items (from the old AUDIT.md)
- Spotify notification filter: `NotificationDaemon.qml` drops `appName` "spotify" (a guess). If Spotify track toasts still show, use the real app name.
- Portal float rule (`windowrules.lua`, `windowrule-4`) matches `^(xdg-desktop-portal.*)$`: check that a Zen file picker floats.
- `hypr/autostart.lua` starts pipewire and wireplumber with `dinitctl`, which probably duplicates the user dinit services. Harmless, not verified.
- Old files left in the live `~/.config/quickshell` (not in the repo, unused): `popups/MenuFrame.qml`, `popups/NetworkMenu.qml`, `taskbar/TaskbarButton.qml`, `preview.qml`, `fonts/MaterialSymbolsSharp_Filled_36pt-Regular.ttf`. Your sync doesn't delete, so remove them by hand if wanted.

## Done
- **Bar**: gripper, workspaces box, divider, Start / Theme; Spotify lyric line (3); privacy icons (6), caffeine (5), sysmon with popup, ETH, Bluetooth, tray, bell + clock
- **Side panel** (Super+N): power buttons with confirm, now playing, per-app volume, DND (18), notification history, calendar with weather (7)
- **Launcher** (Super+D): tabs Apps / Games (cover grid) / Clipboard (Ctrl+Tab), fuzzy apps, calculator (10), session actions (11), "," window search, Super+V clipboard (4), usage ranking (13), categories, options menu with pin / move (15 partial). Alt+Tab switcher removed
- **Notifications**: toasts with actions (19), position / stack / monitor settings (20), history that keeps the live notification; grouped by app (toasts and history), progress bars, inline reply, history saved across restarts
- **Bluetooth** (2): native BlueZ, connect / trust / forget / pair
- **Screenshots** (21): snipping overlay (Super+Shift+S / Print: Region, Window, Screen, All), toast with thumbnail, History viewer with multi-select; no annotation by choice
- **Games** (34): cover grid with filter chips (All / Recent / Steam / Other / Hidden), as the standalone menu (Super+Shift+G) and as the launcher's Games tab; Steam, Steam shortcuts, own entries; `scripts/games.py` + `GamesState.qml` + `GamesView.qml`
- **Screen share picker**: cherry dialog (Screens / Windows tabs, thumbnails, Remember my choice) replacing the portal's default picker; `sharepicker.qml` + `scripts/share-picker.sh` + `hypr/xdph.conf`. No Region sharing (by choice)
- **Desktop**: idle dim / lock / screens off (22), OSDs (23), session panel (24), HyprEmoji, Super+Q closes an open menu before it closes a window
- **GTK theme** (33): `theme/gtkgen.py` recolours the installed ClassicPlatinumStreamlined into `~/.local/share/themes/QsRetro` from the active palette (CSS + PNG assets), gtk settings files and `install.sh` (gsettings theme, icons, full font hinting) point at it
- **App themes** (32): Vesktop, Spotify (Spicetify), VSCodium, Zen generated from the active palette (`apply.py` + templates; CSS / colour files only). Neovim (not installed) and Steam (needs Millennium) skipped
- **Wallpaper colours** (31): `theme/wallcolors.py` (Pillow) makes a `wallpaper` palette from a picture (hue + colourfulness only, fixed lightness per role); browser button "Set + colours" / Shift+Enter; `apply.py wallpaper --palette FILE`
- **Wallpaper browser** (14): Themes > Wallpapers..., grid of `~/Pictures/wallpapers` (settings.json "wallpaper.folder"), monitor + fit, set live through hyprpaper IPC, re-set at start from the state dir; hyprpaper.conf untouched
- **Theme manager core** (30): `themes.json` + `apply.py` + templates drive kitty, Hyprland borders, hyprlock, fastfetch, btop, bottom (process monitor, grouped by program, Ctrl+Shift+Esc), fish and the emoji picker; `dusty` alongside cherry
- Steam games open on workspace 2
- **Spotify panel** (Super+S): mini player with shuffle / repeat / like / add to playlist / volume, Recent 8, full library, Lyrics tab; `scripts/spotify.py` + `SpotifyState.qml`
- **Task Manager** (Ctrl+Shift+Esc): Apps / Processes / Performance, Win95 style; replaces btm
- **Launcher cleanup**: Hide / Unhide + Hidden (n) chip, Uninstall via pacman / flatpak owner lookup
- **Cheat sheet** (Super+F1), **Services** panel (dinit), **Phone** tab in the side panel (KDE Connect); Services and Keys open from the Start menu
- **Look**: Win95 title bars, etched separators, grippers, dithered meters, dotted focus rect, sunken pressed states

## Removed (built, then taken out)
- Output device switching (1): EasyEffects pins its output to the FiiO DM15, so changing the default sink did nothing
- Taskbar of open windows (8): buggy, not needed
- Caps-lock OSD, Alt+Tab switcher, satty / annotation, bar search button, speaker button
- Sunken wells around the bar groups, title-bar close boxes

## Not wanted
Region sharing in the screen-share picker (monitor or program only), Heroic / Lutris / Bottles / Itch in the Games menu (Steam plus plain wine only), dock, desktop widgets, hot corners, screen-time tracker, dmenu mode / plugin providers, translator, video wallpaper, configurable bar, power profile, dark/light toggle. Nightlight: not now.

Reference projects (read-only, for ideas): end-4/dots-hyprland, JaKooLit/Hyprland-Dots, HyDE-Project/HyDE, mylinuxforwork/dotfiles (ML4W), diinki/linux-retroism.
