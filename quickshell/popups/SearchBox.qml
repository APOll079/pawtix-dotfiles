import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

import ".."

// The search / filter box every menu uses: sunken field, an optional magnifier, one-line input.
// Keys: every key press goes to keyPressed(event) first; a host that handles a key sets
// event.accepted = true (arrows into a grid, Enter to launch, ...). Otherwise Escape clears the text,
// and with nothing left to clear emits escaped() (the host steps back or closes); every other key types.
SunkenField {
    id: root

    property alias text: input.text
    property alias input: input
    property string placeholder: ""
    property bool showIcon: true
    property int fontSize: MenuStyle.fontSize

    signal keyPressed(var event)
    signal escaped()
    signal edited()               // the user typed (not a programmatic text change)

    implicitHeight: MenuStyle.searchHeight
    padding: 4

    function focusInput() {
        input.forceActiveFocus();
    }

    RowLayout {
        anchors.fill: parent
        spacing: MenuStyle.pad
        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferFullHinting
            visible: root.showIcon
            font.family: MenuStyle.iconFont
            font.pixelSize: MenuStyle.iconSize
            color: Config.colors.text
            text: ""
        }
        TextField {
            id: input
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferFullHinting
            Layout.fillWidth: true
            Layout.fillHeight: true
            placeholderText: root.placeholder
            placeholderTextColor: MenuStyle.bevelDark
            font.family: MenuStyle.bodyFont
            font.pixelSize: root.fontSize
            color: Config.colors.text
            selectionColor: Config.colors.shadow
            selectByMouse: true
            padding: 0
            verticalAlignment: Text.AlignVCenter
            background: Item {}
            onTextEdited: root.edited()

            Keys.onPressed: event => {
                event.accepted = false;
                root.keyPressed(event);
                if (event.accepted || event.key !== Qt.Key_Escape)
                    return;
                event.accepted = true;
                if (input.text !== "")
                    input.text = "";
                else
                    root.escaped();
            }
        }
    }
}
