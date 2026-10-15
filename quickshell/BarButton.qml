import QtQuick
import QtQuick.Controls.Basic

// The one bar button style: same height, bevel and padding everywhere.
// Raised normally; toggled (menu open) or pressed = sunken bevel, solid face, content shifted 1px.
// interactive: false keeps the box but not the hover/press behaviour (status indicators).
// tucked: no box at all, small and dim - a status label tucked beside the buttons.
// dim: the dim text colour (on by default for tucked labels; the now-playing text turns it off).
Button {
    id: root

    property bool isToggled: false
    property bool urgent: false
    property bool interactive: true
    property bool tucked: false
    property bool dim: tucked
    // strong: one size up from the bar text (the now-playing / lyrics line)
    property bool strong: false
    // 0 = no limit; longer labels are elided
    property int maxLabelWidth: 0
    property string iconFontValue: ""
    property string toggledIconFontValue: ""
    property string label: ""
    property int minWidth: MenuStyle.barButtonHeight

    readonly property bool lit: interactive && hovered
    readonly property bool sunken: interactive && (isToggled || down)
    readonly property color contentColor: lit ? MenuStyle.selectText : urgent ? Config.colors.urgent : (dim ? MenuStyle.bevelDark : Config.colors.text)
    readonly property string currentGlyph: (isToggled && toggledIconFontValue !== "") ? toggledIconFontValue : iconFontValue

    implicitHeight: MenuStyle.barButtonHeight
    implicitWidth: tucked ? content.implicitWidth + MenuStyle.gap * 2 : (label === "" ? minWidth : Math.max(minWidth, content.implicitWidth + 12))
    padding: 0
    hoverEnabled: interactive

    background: Rectangle {
        visible: !root.tucked
        color: root.lit ? MenuStyle.selectBar : Config.colors.base
        border.width: 1
        border.color: Config.colors.outline
        Bevel {
            anchors.fill: parent
            anchors.margins: 1
            thickness: 1
            raised: !root.sunken
        }
    }

    contentItem: Item {
        Row {
            id: content
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: root.sunken ? 1 : 0
            anchors.verticalCenterOffset: root.sunken ? 1 : 0
            spacing: 4
            Text {
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferFullHinting
                visible: root.currentGlyph !== ""
                anchors.verticalCenter: parent.verticalCenter
                font.family: MenuStyle.iconFont
                font.pixelSize: root.tucked ? MenuStyle.barStatusIconSize : MenuStyle.iconSize
                color: root.contentColor
                text: root.currentGlyph
            }
            Text {
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferFullHinting
                visible: root.label !== ""
                anchors.verticalCenter: parent.verticalCenter
                font.family: root.strong ? MenuStyle.barStrongFont : MenuStyle.bodyFont
                font.pixelSize: root.strong ? MenuStyle.barStrongFontSize : (root.tucked ? MenuStyle.barStatusFontSize : Config.settings.bar.fontSize)
                color: root.contentColor
                elide: Text.ElideRight
                width: root.maxLabelWidth > 0 ? Math.min(implicitWidth, root.maxLabelWidth) : implicitWidth
                text: root.label
            }
        }
    }

    HoverHandler {
        enabled: root.interactive
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        cursorShape: Qt.PointingHandCursor
    }
}
