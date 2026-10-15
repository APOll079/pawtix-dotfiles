import QtQuick

// Toolbar gripper: two etched dotted columns (dark dot, light dot 1px down-right) at the start
// of a bar section.
Canvas {
    id: root

    implicitWidth: MenuStyle.gripperWidth
    implicitHeight: MenuStyle.barButtonHeight

    property color darkColor: MenuStyle.bevelDark
    property color lightColor: MenuStyle.bevelLight

    antialiasing: false
    onDarkColorChanged: requestPaint()
    onLightColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        for (var x = 0; x + 1 < width; x += 2) {
            for (var y = 0; y + 1 < height; y += 2) {
                ctx.fillStyle = root.darkColor;
                ctx.fillRect(x, y, 1, 1);
                ctx.fillStyle = root.lightColor;
                ctx.fillRect(x + 1, y + 1, 1, 1);
            }
        }
    }
}
