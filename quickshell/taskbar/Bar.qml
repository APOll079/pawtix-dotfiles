import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import "../popups" as Popups
import ".."

Scope {
Variants {
model: Quickshell.screens
Item {
id: root
required property var modelData
property int currentPopup: Config.SystemPopup.None
onCurrentPopupChanged: MenuState.setOpen(root.modelData.name, root.currentPopup != Config.SystemPopup.None)
// A click on any monitor's click catcher closes the menus of every bar
Connections {
target: MenuState
function onCloseAll() {
if (root.currentPopup != Config.SystemPopup.None)
taskbar.closeAllPopups();
}
}

PanelWindow {
id: taskbar
screen: root.modelData
WlrLayershell.layer: WlrLayer.Bottom
WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
anchors {
top: true
left: true
right: true
}
implicitHeight: MenuStyle.barHeight

color: Config.colors.base

// Caffeine: keeps the idle timers (dim, lock, screens off) from firing while on
IdleInhibitor {
window: taskbar
enabled: Idle.caffeine
}
Item {
id: taskbarBackground
anchors.fill: parent
NewBorder {
commonBorderWidth: 4
commonBorder: false
lBorderwidth: 10
rBorderwidth: 1
tBorderwidth: 10
bBorderwidth: 1
borderColor: Config.colors.shadow
}
NewBorder {
commonBorderWidth: 4
commonBorder: false
lBorderwidth: 10
rBorderwidth: 10
tBorderwidth: 1
bBorderwidth: 10
borderColor: Config.colors.highlight
}
Rectangle {
id: barBackground
anchors {
fill: parent
margins: 0
}
color: "transparent"
radius: 0
border.width: 1
border.color: Config.colors.outline
}
}

// Left section: gripper, workspaces box, etched divider before Start/Theme
Gripper {
id: leftGripper
anchors.verticalCenter: parent.verticalCenter
anchors.left: parent.left
anchors.leftMargin: 8
}
Item {
id: workspacesBox
anchors.verticalCenter: parent.verticalCenter
anchors.left: leftGripper.right
anchors.leftMargin: MenuStyle.gap
height: MenuStyle.barButtonHeight + 4
width: workspaces.width + 6
Rectangle {
anchors.fill: parent
color: Config.colors.base
border.width: 1
border.color: Config.colors.outline
}
Workspaces {
id: workspaces
anchors.leftMargin: 3
anchors.rightMargin: 0
}
}
Popups.MenuSeparator {
id: leftDivider
vertical: true
anchors.verticalCenter: parent.verticalCenter
anchors.left: workspacesBox.right
anchors.leftMargin: MenuStyle.gap
}

Popups.StartMenu {
id: startMenu
bar: taskbar
menuWidth: startmenuButton.x
closeCallback: taskbar.closeAllPopups
openPowerMenuCallback: function() { taskbar.toggleMenu(sessionPanel, Config.SystemPopup.SessionPanel, startmenuButton, "left") }
openServicesCallback: function() { taskbar.toggleMenu(servicesPanel, Config.SystemPopup.Services, null, "keep") }
openKeysCallback: function() { taskbar.toggleMenu(cheatSheet, Config.SystemPopup.CheatSheet, null, "keep") }
}
Popups.ThemeMenu {
id: themeMenu
bar: taskbar
menuWidth: themeMenuButton.x
}
// ThemeMenu has no closeCallback; when it closes itself (picking a theme), reset the shared state.
Connections {
target: themeMenu
function onVisibleChanged() {
if (!themeMenu.visible && root.currentPopup == Config.SystemPopup.ThemePicker) {
root.currentPopup = Config.SystemPopup.None;
}
}
}
Popups.AppLauncher {
id: appLauncher
bar: taskbar
screen: root.modelData
closeCallback: taskbar.closeAllPopups
screenHeight: modelData.height
}

Popups.BluetoothMenu { bar: taskbar; id: bluetoothMenu; closeCallback: taskbar.closeAllPopups }
Popups.SysMonMenu { bar: taskbar; id: sysMonMenu; closeCallback: taskbar.closeAllPopups; openTaskManager: function() { taskbar.toggleMenu(taskManager, Config.SystemPopup.TaskManager, null, "keep") } }
Popups.TaskManager { screen: root.modelData; bar: taskbar; id: taskManager; closeCallback: taskbar.closeAllPopups; screenHeight: modelData.height }
Popups.SessionPanel { bar: taskbar; id: sessionPanel; closeCallback: taskbar.closeAllPopups }
Popups.ScreenshotPanel { screen: root.modelData; bar: taskbar; id: screenshotPanel; closeCallback: taskbar.closeAllPopups; screenHeight: modelData.height }
Popups.ScreenshotOverlay {
id: screenshotOverlay
screen: modelData
historyCallback: function() { taskbar.toggleMenu(screenshotPanel, Config.SystemPopup.Screenshot, null, "keep"); }
}
Popups.GamesMenu { screen: root.modelData; bar: taskbar; id: gamesMenu; closeCallback: taskbar.closeAllPopups; screenHeight: modelData.height }
Popups.CheatSheet { screen: root.modelData; bar: taskbar; id: cheatSheet; closeCallback: taskbar.closeAllPopups; screenHeight: modelData.height }
Popups.ServicesPanel { screen: root.modelData; bar: taskbar; id: servicesPanel; closeCallback: taskbar.closeAllPopups; screenHeight: modelData.height }
Popups.SpotifyPanel { id: spotifyPanel; screen: root.modelData; closeCallback: taskbar.closeAllPopups; screenHeight: modelData.height }
Popups.SidePanel { screen: root.modelData; bar: taskbar; id: sidePanel; closeCallback: taskbar.closeAllPopups }

// Every menu this bar owns; each has closeMenu()
readonly property var menus: [startMenu, themeMenu, appLauncher, bluetoothMenu, sysMonMenu, sessionPanel, screenshotPanel, gamesMenu, cheatSheet, servicesPanel, spotifyPanel, taskManager, sidePanel]

function closeAllPopups() {
for (var m of taskbar.menus)
if (m.visible)
m.closeMenu();
root.currentPopup = Config.SystemPopup.None;
}

// Open a menu under `item`, or close it if it is already open.
// align: "center" (default, centred on the item, kept on screen), "left" (left edge of the
// item), "right" (flush with the right screen edge) or "keep" (the menu positions itself,
// e.g. the centred launcher).
function toggleMenu(menu, popup, item, align) {
if (menu.visible) {
taskbar.closeAllPopups();
return;
}
// Popups are placed under their bar item; layer-shell panels (launcher, side panel, Spotify
// drawer, ...) place themselves and have no anchor
if (menu.anchor) {
if (align === "right") {
menu.anchor.rect.x = taskbar.width - menu.implicitWidth - 4;
} else if (align !== "keep") {
var pos = item.mapToItem(taskbar.contentItem, 0, 0);
if (align === "left") {
menu.anchor.rect.x = pos.x;
} else {
var x = pos.x + item.width / 2 - menu.implicitWidth / 2;
menu.anchor.rect.x = Math.max(4, Math.min(x, taskbar.width - menu.implicitWidth - 4));
}
}
menu.anchor.rect.y = taskbar.implicitHeight;
}
taskbar.closeAllPopups();
root.currentPopup = popup;
menu.openMenu();
}

// Open the launcher in another mode (clipboard, windows); toggles it off if already there
function openLauncherMode(mode) {
if (appLauncher.visible && appLauncher.mode === mode) {
taskbar.closeAllPopups();
return;
}
taskbar.closeAllPopups();
root.currentPopup = Config.SystemPopup.AppLauncher;
appLauncher.open(mode);
}

// Toggle the side panel; when it opens, it opens on `tab`.
function openSidePanel(tab, item) {
if (!sidePanel.visible) {
sidePanel.tab = tab;
}
taskbar.toggleMenu(sidePanel, Config.SystemPopup.SidePanel, item, "right");
}

BarButton {
id: startmenuButton
isToggled: root.currentPopup == Config.SystemPopup.Startmenu
anchors.left: leftDivider.right
anchors.verticalCenter: parent.verticalCenter
anchors.leftMargin: MenuStyle.gap
onClicked: taskbar.toggleMenu(startMenu, Config.SystemPopup.Startmenu, startmenuButton, "left")
}
BarButton {
id: themeMenuButton
isToggled: root.currentPopup == Config.SystemPopup.ThemePicker
iconFontValue: "\ue3ae"
anchors.left: startmenuButton.right
anchors.verticalCenter: parent.verticalCenter
anchors.leftMargin: 4
onClicked: taskbar.toggleMenu(themeMenu, Config.SystemPopup.ThemePicker, themeMenuButton, "left")
}
// Bar middle: the current Spotify lyric line (Lyrics.qml), else "Artist - Title"; dimmed while
// paused; nothing at all when Spotify is closed or another player is active.
BarButton {
id: nowPlaying
visible: Media.text !== ""
anchors.centerIn: parent
iconFontValue: ""
interactive: false
tucked: true
strong: true
dim: Media.paused
label: Lyrics.line !== "" && !Media.paused ? Lyrics.line : Media.text
maxLabelWidth: MenuStyle.barMediaMaxWidth
}

IpcHandler {
target: "appLauncher_" + taskbar.screen.name
function toggleAppLauncher() {
taskbar.toggleMenu(appLauncher, Config.SystemPopup.AppLauncher, null, "keep");
}
// Super+V: clipboard history in the launcher
function clipboard() {
taskbar.openLauncherMode("clipboard");
}
}

// Super+Q: close an open menu (or the snipping overlay) instead of the window behind it.
// Answers "true" when it closed something, so the bind knows not to close the window.
IpcHandler {
target: "taskmanager_" + taskbar.screen.name
function toggle() {
taskbar.toggleMenu(taskManager, Config.SystemPopup.TaskManager, null, "keep");
}
}

IpcHandler {
target: "menus_" + taskbar.screen.name
function closeAny(): string {
if (screenshotOverlay.visible) {
screenshotOverlay.close();
return "true";
}
if (!taskbar.menus.some(function(m) { return m.visible; }))
return "false";
taskbar.closeAllPopups();
return "true";
}
}

IpcHandler {
target: "screenshot_" + taskbar.screen.name
// Snipping overlay (Super+Shift+S, Print)
function toggle() {
if (screenshotOverlay.visible) {
screenshotOverlay.close();
return;
}
// Open menus stay open, so they end up in the frozen frame
screenshotOverlay.open();
}
// History grid
function history() {
taskbar.toggleMenu(screenshotPanel, Config.SystemPopup.Screenshot, null, "keep");
}
}

IpcHandler {
target: "games_" + taskbar.screen.name
function toggle() {
taskbar.toggleMenu(gamesMenu, Config.SystemPopup.Games, null, "keep");
}
}

IpcHandler {
target: "cheatsheet_" + taskbar.screen.name
function toggle() {
taskbar.toggleMenu(cheatSheet, Config.SystemPopup.CheatSheet, null, "keep");
}
}

IpcHandler {
target: "spotify_" + taskbar.screen.name
function toggle() {
taskbar.toggleMenu(spotifyPanel, Config.SystemPopup.Spotify, null, "keep");
}
}

IpcHandler {
target: "services_" + taskbar.screen.name
function toggle() {
taskbar.toggleMenu(servicesPanel, Config.SystemPopup.Services, null, "keep");
}
}

IpcHandler {
target: "session_" + taskbar.screen.name
function toggle() {
taskbar.toggleMenu(sessionPanel, Config.SystemPopup.SessionPanel, startmenuButton, "left");
}
}

IpcHandler {
target: "notifications_" + taskbar.screen.name
function toggle() {
taskbar.openSidePanel(0, null);
}
}

// Right section: gripper, then raised buttons (sysmon, ETH, Bluetooth), tray, bell/clock
Gripper {
anchors.verticalCenter: parent.verticalCenter
anchors.right: laptopControls.left
anchors.rightMargin: MenuStyle.gap
}
LaptopControls {
id: laptopControls
anchors.verticalCenter: parent.verticalCenter
anchors.right: sysTray.left
anchors.rightMargin: 8
currentPopup: root.currentPopup
toggleMenu: taskbar.toggleMenu
bluetoothMenuRef: bluetoothMenu
sysMonMenuRef: sysMonMenu
}

/*=== System tray + clock ===*/
SysTray {
id: sysTray
anchors.right: parent.right
anchors.verticalCenter: parent.verticalCenter
anchors.rightMargin: 8
clockToggled: root.currentPopup == Config.SystemPopup.SidePanel
onClockClicked: item => taskbar.openSidePanel(0, item)
}
}

PanelWindow {
id: overlay
screen: root.modelData
color: "transparent"
anchors {
top: true
bottom: true
left: true
right: true
}
// Shown on every monitor while any bar has a menu open, so a click on either screen closes it
visible: root.currentPopup != Config.SystemPopup.None || MenuState.anyOpen
exclusionMode: ExclusionMode.Ignore
// Leave the bar itself uncovered so its buttons keep their hover and clicks while a menu is open
margins.top: MenuStyle.barHeight
MouseArea {
id: popupArea
anchors.fill: parent
onClicked: MenuState.closeAll()
}
}
}
}
}