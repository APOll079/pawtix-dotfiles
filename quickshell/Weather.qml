pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Weather from wttr.in (no key). settings.json "weather": location ("" = guessed from your IP),
// metric. Refreshes every 30 minutes; shown in the side panel's Calendar tab.
Singleton {
    id: root

    readonly property var cfg: Config.settings.weather
    property bool ok: false
    property string place: ""
    property int temp: 0
    property int feels: 0
    property string desc: ""
    property string icon: ""
    property var days: []         // [{ name: "Sat", lo, hi, icon, desc }]

    // wttr.in weather codes -> Material Symbols glyphs
    function glyph(code) {
        const c = Number(code);
        if (c === 113) return "";                                  // wb_sunny
        if (c === 116) return "";                                  // partly_cloudy_day
        if (c === 119 || c === 122) return "";                     // cloud
        if ([143, 248, 260].includes(c)) return "";                // foggy
        if ([200, 386, 389, 392, 395].includes(c)) return "";      // thunderstorm
        if ([179, 182, 185, 227, 230, 317, 320, 323, 326, 329, 332, 335, 338, 350, 362, 365, 368, 371, 374, 377].includes(c))
            return "";                                             // weather_snowy
        return "";                                                 // rainy (drizzle, rain, showers)
    }

    function refresh() {
        const loc = encodeURIComponent(root.cfg.location);
        fetch.command = ["curl", "-s", "--max-time", "10", "-A", "curl", "https://wttr.in/" + loc + "?format=j1"];
        fetch.running = true;
    }

    Process {
        id: fetch
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null;
                try { d = JSON.parse(text); } catch (e) { d = null; }
                if (!d || !d.current_condition) {
                    root.ok = false;
                    return;
                }
                const metric = root.cfg.metric;
                const c = d.current_condition[0];
                const a = d.nearest_area ? d.nearest_area[0] : null;
                root.place = root.cfg.location !== "" ? root.cfg.location : (a ? a.areaName[0].value : "");
                root.temp = Number(metric ? c.temp_C : c.temp_F);
                root.feels = Number(metric ? c.FeelsLikeC : c.FeelsLikeF);
                root.desc = c.weatherDesc[0].value;
                root.icon = root.glyph(c.weatherCode);
                root.days = d.weather.map(w => ({
                    name: Qt.formatDate(new Date(w.date + "T12:00:00"), "ddd"),
                    lo: Number(metric ? w.mintempC : w.mintempF),
                    hi: Number(metric ? w.maxtempC : w.maxtempF),
                    icon: root.glyph(w.hourly[4].weatherCode),
                    desc: w.hourly[4].weatherDesc[0].value
                }));
                root.ok = true;
            }
        }
    }

    Timer {
        interval: MenuStyle.weatherRefresh
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Connections {
        target: root.cfg
        function onLocationChanged() { root.refresh() }
        function onMetricChanged() { root.refresh() }
    }

    readonly property string unit: cfg.metric ? "°C" : "°F"
}
