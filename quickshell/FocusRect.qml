import QtQuick

// 1px dotted rectangle: the Win95 keyboard-focus marker. Fill its parent (with a margin) and
// set color to contrast with what is under it.
Canvas {
    id: root

    property color color: Config.colors.text

    antialiasing: false
    onColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        ctx.fillStyle = root.color;
        var w = Math.floor(width), h = Math.floor(height);
        for (var x = 0; x < w; x += 2) {
            ctx.fillRect(x, 0, 1, 1);
            ctx.fillRect(x, h - 1, 1, 1);
        }
        for (var y = 0; y < h; y += 2) {
            ctx.fillRect(0, y, 1, 1);
            ctx.fillRect(w - 1, y, 1, 1);
        }
    }
}
