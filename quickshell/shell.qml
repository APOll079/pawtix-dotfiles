//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

/* NOTE: CHANGE THESE IF YOU WANT TO USE A DIFFERENT ICON THEME:*/
//@ pragma IconTheme RetroismIcons
//@ pragma Env QS_ICON_THEME=RetroismIcons

import QtQuick
import Quickshell

import "taskbar" as Taskbar
import "popups" as Popups

Scope {
    id: root
    Taskbar.Bar {}
    Popups.OsdPopup {}
    Popups.NotificationDaemon {}
    Variants {
        model: Quickshell.screens
        IdleDim {}
    }
}
