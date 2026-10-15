import Quickshell
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import Quickshell.Services.Pipewire
import ".."

// Audio section of the Home tab: now playing with controls, and per-app volume (the overall volume is on the DAC). `active` is true while Home is showing.
ColumnLayout {
    id: root
    property bool active: false
    spacing: MenuStyle.pad

    // === NOW PLAYING ===
    SunkenField {
        Layout.fillWidth: true
        implicitHeight: trackLabel.implicitHeight + 2 * padding + 4
        Text {
            id: trackLabel
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferFullHinting
            width: parent.width
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            font.family: MenuStyle.bodyFont
            font.pixelSize: MenuStyle.fontSize
            color: Config.colors.text
            text: Media.label
        }
    }

    // Previous / play-pause / next: Spotify if it is running, else whatever plays (Media.player)
    RowLayout {
        Layout.fillWidth: true
        spacing: MenuStyle.pad
        BevelButton {
            Layout.fillWidth: true
            glyph: "\ue045"
            enabled: Media.player !== null && Media.player.canGoPrevious
            onClicked: Media.player.previous()
        }
        BevelButton {
            Layout.fillWidth: true
            glyph: Media.playing ? "\ue034" : "\ue037"
            enabled: Media.player !== null && Media.player.canTogglePlaying
            onClicked: Media.player.togglePlaying()
        }
        BevelButton {
            Layout.fillWidth: true
            glyph: "\ue044"
            enabled: Media.player !== null && Media.player.canGoNext
            onClicked: Media.player.next()
        }
    }

    // === PER-APP VOLUME ===
    // Node properties are only filled in once a node is tracked, so track every stream first
    // and pick the playback ones ("Stream/Output/Audio") after that.
    readonly property var allStreams: Pipewire.nodes.values.filter(n => n.isStream)
    readonly property var streamNodes: allStreams.filter(n => n.properties && n.properties["media.class"] === "Stream/Output/Audio")

    // One row per app: browsers open a stream per tab, so group streams by application name
    readonly property var appGroups: {
        var groups = [];
        var byName = {};
        for (var n of root.streamNodes) {
            var name = n.properties["application.name"] || n.description || n.nickname || "Unknown";
            if (!(name in byName)) {
                byName[name] = { name: name, nodes: [] };
                groups.push(byName[name]);
            }
            byName[name].nodes.push(n);
        }
        return groups;
    }

    PwObjectTracker {
        objects: root.allStreams
    }

    Text {
        renderType: Text.NativeRendering
        font.hintingPreference: Font.PreferFullHinting
        visible: root.streamNodes.length > 0
        font.family: MenuStyle.titleFont
        font.pixelSize: MenuStyle.fontSize
        color: Config.colors.text
        text: "Applications"
    }

    Repeater {
        model: root.appGroups

        ColumnLayout {
            id: streamRow
            required property var modelData
            // The first stream speaks for the app; changes go to all of its streams
            readonly property var lead: modelData.nodes[0]
            readonly property real vol: lead.audio ? lead.audio.volume : 0
            readonly property bool muted: lead.audio ? lead.audio.muted : false
            function setVolume(v) {
                for (var n of modelData.nodes) if (n.audio) n.audio.volume = v;
            }
            function setMuted(m) {
                for (var n of modelData.nodes) if (n.audio) n.audio.muted = m;
            }
            Layout.fillWidth: true
            spacing: 2

            Text {
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferFullHinting
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.family: MenuStyle.bodyFont
                font.pixelSize: MenuStyle.fontSize
                color: Config.colors.text
                text: streamRow.modelData.name
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: MenuStyle.pad

                BevelButton {
                    implicitWidth: MenuStyle.rowHeight + MenuStyle.gap
                    glyph: streamRow.muted ? "\ue04f" : "\ue050"
                    onClicked: streamRow.setMuted(!streamRow.muted)
                }

                RetroSlider {
                    Layout.fillWidth: true
                    from: 0
                    to: 100
                    value: streamRow.vol * 100
                    dim: streamRow.muted
                    onMoved: streamRow.setVolume(value / 100)
                }

                Text {
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferFullHinting
                    Layout.preferredWidth: MenuStyle.valueLabelWidth
                    horizontalAlignment: Text.AlignRight
                    font.family: MenuStyle.bodyFont
                    font.pixelSize: MenuStyle.fontSize
                    color: Config.colors.text
                    text: streamRow.muted ? "MUTE" : Math.round(streamRow.vol * 100) + "%"
                }
            }
        }
    }
}
