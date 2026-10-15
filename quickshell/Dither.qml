import QtQuick

// 1px checkerboard of two colours: the classic pressed / checked button face.
Canvas {
    id: root

    property color color1: Config.colors.base
    property color color2: MenuStyle.bevelLight

    antialiasing: false
    onColor1Changed: requestPaint()
    onColor2Changed: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        ctx.fillStyle = root.color1;
        ctx.fillRect(0, 0, width, height);
        ctx.fillStyle = root.color2;
        for (var y = 0; y < height; y++) {
            for (var x = y % 2; x < width; x += 2)
                ctx.fillRect(x, y, 1, 1);
        }
    }
}
