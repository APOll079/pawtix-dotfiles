import QtQuick
import QtQuick.Controls.Basic

import ".."

// One cover in a Spotify panel grid (the Recent row and the library grid share it): a sunken square
// cover (or an icon by type when there's no art), the name and, if showSub, a type line with the
// pin icon. Hover / selected = the accent bar with inverted text, the keyboard cursor adds the dotted
// focus rect, like MenuRow. A play button appears on hover or when selected (not for folders).
Item {
    id: root

    property var entry: ({})
    property bool selected: false
    property bool showSub: true
    property bool canPlay: entry.kind !== "folder"
    signal activated()
    signal playRequested()

    // Hover from a HoverHandler: it stays hovered over the play button, where a MouseArea would lose
    // the pointer to the button, hide it, get the pointer back and show it again (flicker)
    readonly property bool lit: hover.hovered || root.selected
    readonly property int coverSize: width - 2 * MenuStyle.gap

    implicitHeight: MenuStyle.gap + coverSize + MenuStyle.spotifyInset + MenuStyle.rowHeight * (showSub ? 2 : 1)

    Rectangle {
        anchors.fill: parent
        color: root.lit ? MenuStyle.selectBar : "transparent"
        FocusRect {
            anchors.fill: parent
            anchors.margins: 1
            visible: root.selected
            color: MenuStyle.selectText
        }
    }

    SunkenField {
        id: cover
        x: MenuStyle.gap
        y: MenuStyle.gap
        width: root.coverSize
        height: width
        padding: MenuStyle.spotifyInset
        Image {
            id: img
            anchors.fill: parent
            source: root.entry.image || ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferFullHinting
            anchors.centerIn: parent
            visible: img.status !== Image.Ready
            font.family: MenuStyle.iconFont
            font.pixelSize: MenuStyle.spotifyTileIcon
            color: MenuStyle.bevelDark
            text: {
                switch (root.entry.kind) {
                case "folder": return "";
                case "artist": return "";
                case "album": return "";
                case "liked": return "";
                case "track": return "";
                default: return "";
                }
            }
        }
    }

    Column {
        x: MenuStyle.gap
        anchors.top: cover.bottom
        anchors.topMargin: MenuStyle.spotifyInset
        width: root.coverSize
        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferFullHinting
            textFormat: Text.PlainText
            width: parent.width
            height: MenuStyle.rowHeight
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            font.family: MenuStyle.bodyFont
            font.pixelSize: MenuStyle.fontSize
            color: root.lit ? MenuStyle.selectText : Config.colors.text
            text: root.entry.name || ""
        }
        // Pin (pinned in Spotify) + the type line
        Row {
            visible: root.showSub
            width: parent.width
            height: MenuStyle.rowHeight
            spacing: MenuStyle.spotifyInset
            Text {
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferFullHinting
                anchors.verticalCenter: parent.verticalCenter
                visible: root.entry.pinned === true
                font.family: MenuStyle.iconFont
                font.pixelSize: MenuStyle.iconSize
                color: root.lit ? MenuStyle.selectText : Config.colors.text
                text: ""
            }
            Text {
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferFullHinting
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - (root.entry.pinned === true ? MenuStyle.iconSize + MenuStyle.spotifyInset : 0)
                elide: Text.ElideRight
                font.family: MenuStyle.bodyFont
                font.pixelSize: MenuStyle.fontSize
                color: root.lit ? MenuStyle.selectText : MenuStyle.bevelDark
                text: root.entry.sub || ""
            }
        }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }
    MouseArea {
        anchors.fill: parent
        onClicked: root.activated()
    }

    BevelButton {
        anchors.right: cover.right
        anchors.bottom: cover.bottom
        anchors.margins: MenuStyle.gap
        visible: root.lit && root.canPlay
        glyph: ""
        focusPolicy: Qt.NoFocus
        onClicked: root.playRequested()
    }
}
