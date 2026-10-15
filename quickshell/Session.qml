pragma Singleton
import QtQuick
import Quickshell

// Session actions, shared by the side panel power row, the launcher and the session panel.
// Every built-in asks for confirmation; reboot and shutdown can also run through the session
// panel's countdown (settings.json "session": countdownSeconds, customActions).
Singleton {
    id: root

    readonly property var builtins: [
        { name: "Suspend", icon: "", cmd: "loginctl suspend", confirm: true, countdown: false },
        { name: "Lock", icon: "", cmd: "pidof hyprlock || hyprlock", confirm: true, countdown: false },
        { name: "Log out", icon: "", cmd: "hyprctl dispatch 'hl.dsp.exit()'", confirm: true, countdown: false },
        { name: "Reboot", icon: "", cmd: "loginctl reboot", confirm: true, countdown: true },
        { name: "Shutdown", icon: "", cmd: "loginctl poweroff", confirm: true, countdown: true }
    ]

    // Your own actions from settings.json: [{ "name", "icon" (glyph, optional), "cmd" }]
    readonly property var custom: (Config.settings.session.customActions || []).map(a => ({
        name: a.name, icon: a.icon || "", cmd: a.cmd, confirm: false, countdown: false
    }))

    readonly property var all: builtins.concat(custom)

    function run(action) {
        Quickshell.execDetached(["sh", "-c", action.cmd]);
    }
}
