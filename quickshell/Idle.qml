pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// Idle handling (settings.json "idle"): dim, then lock with hyprlock, then screens off.
// All three respect idle inhibitors, so caffeine (or a fullscreen video that inhibits) pauses
// them. A step with 0 minutes is off.
Singleton {
    id: root

    readonly property var cfg: Config.settings.idle
    // Caffeine: Bar.qml holds an IdleInhibitor bound to this
    property bool caffeine: false

    readonly property bool dimmed: cfg.enabled && cfg.dimMinutes > 0 && dimMonitor.isIdle

    IdleMonitor {
        id: dimMonitor
        enabled: root.cfg.enabled && root.cfg.dimMinutes > 0
        respectInhibitors: true
        timeout: root.cfg.dimMinutes * 60
    }

    IdleMonitor {
        id: lockMonitor
        enabled: root.cfg.enabled && root.cfg.lockMinutes > 0
        respectInhibitors: true
        timeout: root.cfg.lockMinutes * 60
        onIsIdleChanged: {
            if (isIdle)
                Quickshell.execDetached(["sh", "-c", "pidof hyprlock || hyprlock"]);
        }
    }

    IdleMonitor {
        id: screenMonitor
        enabled: root.cfg.enabled && root.cfg.screenOffMinutes > 0
        respectInhibitors: true
        timeout: root.cfg.screenOffMinutes * 60
        onIsIdleChanged: Hyprland.dispatch(isIdle ? "hl.dsp.dpms({ action = \"disable\" })" : "hl.dsp.dpms({ action = \"enable\" })")
    }
}
