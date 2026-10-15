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
property var themes: fallbackThemes
FileView {
id: themesFile
path: Qt.resolvedUrl("./theme/themes.json")
watchChanges: true
onFileChanged: reload()
onLoaded: {
try {
root.themes = JSON.parse(text());
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
onTriggered: Quickshell.execDetached(["python3", "-I", Quickshell.shellDir + "/theme/apply.py", root.settings.currentTheme])
}
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