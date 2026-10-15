import QtQuick

// Text that goes Win95-style "embossed" (light copy 1px down-right) when disabled.
Item {
    id: root

    property string text: ""
    property color color: Config.colors.text
    property bool disabledLook: false
    property alias font: main.font
    property alias elide: main.elide
    property alias verticalAlignment: main.verticalAlignment

    implicitWidth: main.implicitWidth
    implicitHeight: main.implicitHeight

    Text {
        visible: root.disabledLook
        x: 1
        y: 1
        width: root.width
        height: root.height
        renderType: Text.NativeRendering
        textFormat: Text.PlainText
        font: main.font
        elide: main.elide
        verticalAlignment: main.verticalAlignment
        color: MenuStyle.bevelLight
        text: root.text
    }
    Text {
        id: main
        renderType: Text.NativeRendering
        textFormat: Text.PlainText
        font.hintingPreference: Font.PreferFullHinting
        anchors.fill: parent
        color: root.disabledLook ? MenuStyle.bevelDark : root.color
        text: root.text
    }
}
