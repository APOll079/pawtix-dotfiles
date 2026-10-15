import Quickshell
import QtQuick
import Quickshell.Services.Notifications
import QtQuick.Layouts
import QtQuick.Controls.Basic
import ".."

// Calendar tab of the side panel. `active` is true while this tab is showing.
ColumnLayout {
    id: root
    property bool active: false
    spacing: MenuStyle.pad

    property int viewMonth: new Date().getMonth()
    property int viewYear: new Date().getFullYear()
    readonly property var monthNames: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

    onActiveChanged: {
        if (active) {
            var now = new Date()
            root.viewMonth = now.getMonth()
            root.viewYear = now.getFullYear()
        }
    }

    // Weather (Weather.qml): now, then the next days
    SunkenField {
        Layout.fillWidth: true
        visible: Weather.ok
        implicitHeight: weatherCol.implicitHeight + 2 * padding
        ColumnLayout {
            id: weatherCol
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: MenuStyle.gap
            RowLayout {
                Layout.fillWidth: true
                spacing: MenuStyle.pad
                Text {
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferFullHinting
                    font.family: MenuStyle.iconFont
                    font.pixelSize: MenuStyle.iconSize
                    color: Config.colors.text
                    text: Weather.icon
                }
                Text {
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferFullHinting
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.family: MenuStyle.titleFont
                    font.pixelSize: MenuStyle.fontSize
                    color: Config.colors.text
                    text: Weather.temp + Weather.unit + "  " + Weather.desc
                }
                Text {
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferFullHinting
                    font.family: MenuStyle.bodyFont
                    font.pixelSize: MenuStyle.fontSize
                    color: Config.colors.text
                    text: Weather.place
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: MenuStyle.pad
                Repeater {
                    model: Weather.days
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: MenuStyle.gap
                        Text {
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferFullHinting
                            font.family: MenuStyle.iconFont
                            font.pixelSize: MenuStyle.iconSize
                            color: Config.colors.text
                            text: modelData.icon
                        }
                        Text {
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferFullHinting
                            Layout.fillWidth: true
                            font.family: MenuStyle.bodyFont
                            font.pixelSize: MenuStyle.fontSize
                            color: Config.colors.text
                            text: modelData.name + " " + modelData.lo + "/" + modelData.hi + "°"
                        }
                    }
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: MenuStyle.pad
        BevelButton {
            implicitWidth: MenuStyle.rowHeight + MenuStyle.gap
            glyph: "\ue5cb"
            onClicked: root.shiftMonth(-1)
        }
        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferFullHinting
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            font.family: MenuStyle.titleFont
            font.pixelSize: MenuStyle.fontSize
            color: Config.colors.text
            text: root.monthNames[root.viewMonth] + " " + root.viewYear
        }
        BevelButton {
            implicitWidth: MenuStyle.rowHeight + MenuStyle.gap
            glyph: "\ue5cc"
            onClicked: root.shiftMonth(1)
        }
    }

    SunkenField {
        Layout.fillWidth: true
        implicitHeight: dayRow.implicitHeight + grid.implicitHeight + 2 * padding
        padding: 4

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            DayOfWeekRow {
                id: dayRow
                Layout.fillWidth: true
                locale: Qt.locale("en_GB")
                delegate: Item {
                    implicitWidth: MenuStyle.calendarCell
                    implicitHeight: dayLabel.implicitHeight + 2
                    Text {
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferFullHinting
                        id: dayLabel
                        anchors.centerIn: parent
                        font.family: MenuStyle.titleFont
                        font.pixelSize: MenuStyle.fontSize
                        color: Config.colors.text
                        text: model.shortName
                    }
                }
            }

            MonthGrid {
                id: grid
                Layout.fillWidth: true
                Layout.fillHeight: true
                month: root.viewMonth
                year: root.viewYear
                locale: Qt.locale("en_GB")
                delegate: Item {
                    implicitWidth: MenuStyle.calendarCell
                    implicitHeight: MenuStyle.rowHeight - 2
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        color: model.today ? Config.colors.accent : "transparent"
                    }
                    Text {
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferFullHinting
                        anchors.centerIn: parent
                        font.family: MenuStyle.bodyFont
                        font.pixelSize: MenuStyle.fontSize
                        color: model.today ? Config.colors.base : (model.month === grid.month ? Config.colors.text : Config.colors.shadow)
                        text: model.day
                    }
                }
            }
        }
    }

    function shiftMonth(delta) {
        var m = root.viewMonth + delta
        var y = root.viewYear
        if (m < 0) { m = 11; y -= 1 }
        else if (m > 11) { m = 0; y += 1 }
        root.viewMonth = m
        root.viewYear = y
    }

    Item { Layout.fillHeight: true }
}
