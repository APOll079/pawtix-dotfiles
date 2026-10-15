# Quickshell: retro desktop shell

Started from the Quickshell frontend of Linux Retroism, since rebuilt for this desktop.

- `shell.qml` is the entry point; `taskbar/Bar.qml` creates the bar and every menu per monitor.
- Colour themes live in `theme/themes.json` (the Themes menu lists them). `theme/apply.py` turns them into colour files for the other apps.
- Other settings: `settings.json`. Named sizes and timings: `MenuStyle.qml`.

For what exists and the rules, read `CLAUDE.md` and `FEATURES.md` in the repo root. For upkeep and fixing things after updates, read `MAINTENANCE.md`.
