pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// CPU load, RAM use and CPU/GPU temperatures, read from /proc and hwmon every few seconds.
// hwmon numbers change between boots, so the sensors are found by driver name at startup:
// k10temp (Ryzen, Tctl) and the amdgpu node that has a junction sensor (the RX 9070 XT;
// the 7800X3D's iGPU is also amdgpu but only reports an edge temperature).
Singleton {
    id: root

    readonly property int interval: MenuStyle.sysMonInterval
    // The SysMon popup is open: also read the GPU temperatures (only shown there)
    property bool detailed: false

    property real cpuLoad: 0          // 0..1
    property real memLoad: 0          // 0..1, used = total - available
    readonly property int memPercent: Math.round(memLoad * 100)
    property real cpuTemp: -1         // °C, -1 = unknown
    property real gpuEdge: -1
    property real gpuJunction: -1
    property real gpuMem: -1

    property string cpuHwmon: ""
    property string gpuHwmon: ""

    // Previous /proc/stat totals, for the load delta
    property real lastIdle: 0
    property real lastTotal: 0

    Process {
        running: true
        command: ["sh", "-c", "for h in /sys/class/hwmon/hwmon*; do echo \"$h $(cat $h/name) $([ -e $h/temp2_input ] && echo multi)\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                for (const line of text.trim().split("\n")) {
                    const parts = line.split(" ");
                    if (parts[1] === "k10temp" && root.cpuHwmon === "")
                        root.cpuHwmon = parts[0];
                    else if (parts[1] === "amdgpu" && parts[2] === "multi" && root.gpuHwmon === "")
                        root.gpuHwmon = parts[0];
                }
            }
        }
    }

    FileView { id: statFile; path: "/proc/stat" }
    FileView { id: memFile; path: "/proc/meminfo" }
    FileView { id: cpuTempFile; path: root.cpuHwmon === "" ? "" : root.cpuHwmon + "/temp1_input" }
    FileView { id: gpuEdgeFile; path: root.gpuHwmon === "" ? "" : root.gpuHwmon + "/temp1_input" }
    FileView { id: gpuJunctionFile; path: root.gpuHwmon === "" ? "" : root.gpuHwmon + "/temp2_input" }
    FileView { id: gpuMemFile; path: root.gpuHwmon === "" ? "" : root.gpuHwmon + "/temp3_input" }

    function readTemp(view) {
        if (view.path === "")
            return -1;
        view.reload();
        const v = parseInt(view.text());
        return isNaN(v) ? -1 : v / 1000;
    }

    function update() {
        statFile.reload();
        const f = statFile.text().split("\n")[0].trim().split(/\s+/).slice(1).map(Number);
        // user nice system idle iowait irq softirq steal
        const idle = f[3] + f[4];
        const total = f.slice(0, 8).reduce((a, b) => a + b, 0);
        if (root.lastTotal > 0 && total > root.lastTotal)
            root.cpuLoad = 1 - (idle - root.lastIdle) / (total - root.lastTotal);
        root.lastIdle = idle;
        root.lastTotal = total;

        memFile.reload();
        const kb = {};
        for (const line of memFile.text().split("\n")) {
            const m = line.match(/^(\w+):\s+(\d+)/);
            if (m)
                kb[m[1]] = Number(m[2]);
        }
        if (kb.MemTotal)
            root.memLoad = (kb.MemTotal - kb.MemAvailable) / kb.MemTotal;

        root.cpuTemp = readTemp(cpuTempFile);
        if (root.detailed) {
            root.gpuEdge = readTemp(gpuEdgeFile);
            root.gpuJunction = readTemp(gpuJunctionFile);
            root.gpuMem = readTemp(gpuMemFile);
        }
    }

    Timer {
        interval: root.interval
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.update()
    }

    function tempText(t) {
        return t < 0 ? "--" : Math.round(t) + "°C";
    }
}
