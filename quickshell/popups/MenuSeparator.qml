import QtQuick

import ".."

// Etched divider (dark line, light line next to it) between groups of rows.
// vertical: true for a divider between bar sections.
Item {
    id: root

    property bool vertical: false

    implicitHeight: vertical ? MenuStyle.barButtonHeight : MenuStyle.separatorThickness
    implicitWidth: vertical ? MenuStyle.separatorThickness : 40

    Rectangle { visible: !root.vertical; x: 0; y: 2; width: parent.width; height: 1; color: MenuStyle.bevelDark }
    Rectangle { visible: !root.vertical; x: 0; y: 3; width: parent.width; height: 1; color: MenuStyle.bevelLight }

    Rectangle { visible: root.vertical; x: 2; y: 0; width: 1; height: parent.height; color: MenuStyle.bevelDark }
    Rectangle { visible: root.vertical; x: 3; y: 0; width: 1; height: parent.height; color: MenuStyle.bevelLight }
}
