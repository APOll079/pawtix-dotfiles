import QtQuick

// Classic 2px bevel drawn inside its bounds (two 1px rings), from Config.colors only.
// raised: light on top/left, outline + dark on bottom/right.
// sunken: dark + outline on top/left, light on bottom/right.
Item {
    id: root

    property bool raised: true
    // 2 = full bevel (frames), 1 = single ring (buttons, bar buttons)
    property int thickness: 2

    readonly property color outerLight: raised ? MenuStyle.bevelLight : MenuStyle.bevelDark
    readonly property color outerDark: thickness === 1 ? (raised ? MenuStyle.bevelDark : MenuStyle.bevelLight) : (raised ? Config.colors.outline : MenuStyle.bevelLight)
    readonly property color innerLight: raised ? MenuStyle.bevelLight : Config.colors.outline
    readonly property color innerDark: raised ? MenuStyle.bevelDark : Config.colors.base

    // light edges first, dark edges drawn over them at the shared corners
    Rectangle { x: 0; y: 0; width: root.width - 1; height: 1; color: root.outerLight }
    Rectangle { x: 0; y: 0; width: 1; height: root.height - 1; color: root.outerLight }
    Rectangle { visible: root.thickness === 2; x: 1; y: 1; width: root.width - 3; height: 1; color: root.innerLight }
    Rectangle { visible: root.thickness === 2; x: 1; y: 1; width: 1; height: root.height - 3; color: root.innerLight }

    Rectangle { x: 0; y: root.height - 1; width: root.width; height: 1; color: root.outerDark }
    Rectangle { x: root.width - 1; y: 0; width: 1; height: root.height; color: root.outerDark }
    Rectangle { visible: root.thickness === 2; x: 1; y: root.height - 2; width: root.width - 2; height: 1; color: root.innerDark }
    Rectangle { visible: root.thickness === 2; x: root.width - 2; y: 1; width: 1; height: root.height - 2; color: root.innerDark }
}
