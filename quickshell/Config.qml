pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
Singleton {
id: root
// Palettes live in theme/themes.json (one source for quickshell and every themed app).
// Add a theme there and it shows up in the Themes menu. When the theme changes (and once at
// start) theme/apply.py renders the app colour files: kitty, Hyprland borders, hyprlock,
// fastfetch, btop, fish and the emoji picker.
property var colors: themes[settings.currentTheme] || themes["cherry"] || themes[Object.keys(themes)[0]]
// Built-in cherry so the shell still draws if themes.json is missing or broken
readonly property var fallbackThemes: ({
"cherry": {
"base": "#f4c9ef",
"shadow": "#c7a4cc",
"highlight": "#f9d0f7",
"urgent": "#ff936c",
"accent": "#c950bb",
"text": "#321d32",
"outline": "#20091d",
"outlineGradientFade": "#3e233e",
"defaultWallpaperPath": ""
}
})
// themes.json (or the built-in cherry), plus "wallpaper" once a palette was made from a picture
property var baseThemes: fallbackThemes
property var wallTheme: null
readonly property var themes: wallTheme ? Object.assign({}, baseThemes, { "wallpaper": wallTheme }) : baseThemes
// The palette theme/wallcolors.py wrote for the wallpaper browser's "Set + colours" (state dir, not the repo)
readonly property string wallPalette: Quickshell.statePath("wallpaper-theme.json")
function reloadWallTheme() { wallFile.reload() }
FileView {
id: wallFile
path: root.wallPalette
printErrors: false
watchChanges: true
onFileChanged: reload()
onLoaded: {
try {
const p = JSON.parse(text());
// Same check as apply.py: every role the shell draws with must be a #rrggbb string
for (const k of ["base", "shadow", "highlight", "accent", "text", "outline"])
if (typeof p[k] !== "string" || !/^#[0-9a-fA-F]{6}$/.test(p[k]))
throw new Error("missing or bad " + k);
root.wallTheme = p;
} catch (e) {
console.warn("wallpaper-theme.json ignored: " + e);
}
}
}
FileView {
id: themesFile
path: Qt.resolvedUrl("./theme/themes.json")
watchChanges: true
onFileChanged: reload()
onLoaded: {
try {
root.baseThemes = JSON.parse(text());
} catch (e) {
console.warn("theme/themes.json is not valid JSON, keeping the previous palettes: " + e);
}
}
}

// Render the other apps' colours for the current theme: once settings.json has loaded (not
// before, or the built-in default theme would be rendered first), then on every theme change.
// Debounced, so a quick theme switch only runs it once.
property bool settingsLoaded: false
Timer {
id: applyTimer
interval: 300
onTriggered: {
const cmd = root.applyCommand();
if (cmd)
Quickshell.execDetached(cmd);
}
}
// apply.py for the current theme; the wallpaper theme takes its palette file (null until it exists)
function applyCommand() {
const base = ["python3", "-I", Quickshell.shellDir + "/theme/apply.py", root.settings.currentTheme];
if (root.settings.currentTheme !== "wallpaper")
return base;
return root.wallTheme ? base.concat(["--palette", root.wallPalette]) : null;
}
// A new wallpaper palette while "wallpaper" is the theme: render the apps again
onWallThemeChanged: { if (root.settingsLoaded && !Quickshell.env("QS_NO_APPLY") && root.settings.currentTheme === "wallpaper") applyTimer.restart() }
function settingsReady() {
if (root.settingsLoaded)
return;
root.settingsLoaded = true;
// Helper instances (the screen-share picker) share this file but must not re-render the theme files
if (Quickshell.env("QS_NO_APPLY"))
return;
applyTimer.restart();
}
Connections {
target: root.settings
function onCurrentThemeChanged() { if (root.settingsLoaded && !Quickshell.env("QS_NO_APPLY")) applyTimer.restart() }
}
enum SystemPopup {
Startmenu,
ThemePicker,
AppLauncher,
BluetoothMenu,
SysMonMenu,
SessionPanel,
Screenshot,
SidePanel,
Games,
CheatSheet,
Services,
Spotify,
TaskManager,
Wallpapers,
None
}
property alias settings: settingsJsonAdapter.settings
FileView {
path: Qt.resolvedUrl("./settings.json")
// when changes are made on disk, reload the file's content
watchChanges: true
onFileChanged: reload()
// when changes are made to properties in the adapter, save them
onAdapterUpdated: writeAdapter()
onLoaded: root.settingsReady()
onLoadFailed: error => {
if (error == FileViewError.FileNotFound) {
writeAdapter();
}
root.settingsReady();
}
JsonAdapter {
id: settingsJsonAdapter
property JsonObject settings: JsonObject {
property bool militaryTimeClockFormat: true
property string systemProfileImageSource: "/home/username/Pictures/system_profile_picture.png"
property string currentTheme: "default"
property JsonObject execCommands: JsonObject {
property string terminal: "kitty"
property string files: "nemo"
}
property JsonObject systemDetails: JsonObject {
property string osName: "Linux Distro"
property string osVersion: "Distro Version"
property string ram: "Ram"
property string cpu: "CPU Name"
property string gpu: "GPU Name"
}
property JsonObject bar: JsonObject {
property int fontSize: 12
property int trayIconSize: 16
property bool monochromeTrayIcons: true
}
// Toasts: position top-right | top-left | top | bottom-right | bottom-left | bottom;
// maxVisible = stack limit; monitor = output name ("DP-2"), "focused", or "" (compositor default)
property JsonObject notifications: JsonObject {
property bool dnd: false
property string position: "top-right"
property int maxVisible: 4
property string monitor: ""
}
// Which OSDs show
property JsonObject osd: JsonObject {
property bool volume: true
property bool bluetooth: true
}
// Idle: dim, then lock (hyprlock), then screens off; minutes, 0 = off for that step
property JsonObject idle: JsonObject {
property bool enabled: true
property int dimMinutes: 5
property int lockMinutes: 10
property int screenOffMinutes: 15
}
// Weather from wttr.in; location "" = guessed from your IP
property JsonObject weather: JsonObject {
property string location: ""
property bool metric: true
}
// Wallpaper browser (Themes > Wallpapers...): the folder it lists (top level only; ~ allowed)
property JsonObject wallpaper: JsonObject {
property string folder: "~/Pictures/wallpapers"
}
// Session panel: countdown before reboot/shutdown, plus your own actions [{ "name", "icon", "cmd" }]
property JsonObject session: JsonObject {
property int countdownSeconds: 60
property var customActions: []
}
onCurrentThemeChanged: {
console.info("Updated theme to: " + currentTheme);
}
}
}
}
}