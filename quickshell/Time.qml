pragma Singleton

import Quickshell
import QtQuick

Singleton {
    id: root
    readonly property string time: {
        return Qt.formatDateTime(clock.date, Config.settings.militaryTimeClockFormat ? "ddd d MMM | hh:mm" : "ddd d MMM | h:mm AP");
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }
}
