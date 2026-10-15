pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// What is recording right now, from PipeWire node types (no polling):
// - mic: any audio input stream (an app capturing a microphone), except EasyEffects' own
//   processing streams.
// - screen: any video source. This desktop has no camera, so a video source is the portal's
//   screen-share stream. (Camera indicator skipped: no /dev/video* here.)
Singleton {
    id: root

    readonly property var nodes: Pipewire.nodes.values
    readonly property var micStreams: nodes.filter(n => n.type === PwNodeType.AudioInStream && !/^(ee_|easyeffects)/i.test(n.name))
    readonly property bool mic: micStreams.length > 0
    readonly property bool screen: nodes.some(n => n.type === PwNodeType.VideoSource)
}
