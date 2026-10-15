import Quickshell
import QtQuick
import Quickshell.Services.Notifications
import QtQuick.Layouts
import QtQuick.Controls.Basic
import ".."

// Notification history for the Home tab of the side panel. `active` is true while Home is showing.
ColumnLayout {
    id: root
    property bool active: false
    spacing: MenuStyle.pad

    onActiveChanged: {
        if (active) NotificationStore.unread = 0
    }

    // Anything that arrives while this tab is showing counts as read
    Connections {
        target: NotificationStore
        function onUnreadChanged() {
            if (root.active && NotificationStore.unread > 0) NotificationStore.unread = 0
        }
    }

    function timeText(t) {
        return Qt.formatDateTime(t, "hh:mm");
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: MenuStyle.pad
        Text {
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferFullHinting
            Layout.fillWidth: true
            font.family: MenuStyle.titleFont
            font.pixelSize: MenuStyle.fontSize
            color: Config.colors.text
            text: NotificationStore.items.length === 0 ? "No notifications" : NotificationStore.items.length + (NotificationStore.items.length === 1 ? " notification" : " notifications")
        }
        // Do Not Disturb: notifications still land here, they just don't pop up
        BevelButton {
            text: "DND"
            glyph: Config.settings.notifications.dnd ? "\ue7f6" : "\ue7f4"
            checked: Config.settings.notifications.dnd
            onClicked: Config.settings.notifications.dnd = !Config.settings.notifications.dnd
        }
        BevelButton {
            text: "Clear all"
            visible: NotificationStore.items.length > 0
            onClicked: NotificationStore.clear()
        }
    }

    // Rows: one per app group. A group of one is the notification itself; a bigger group is a
    // header ("App · 3", newest summary) that a click expands into its notifications.
    property var expanded: ({})
    property var replyTo: null           // history entry whose reply box is open
    readonly property var rows: {
        const groups = [];
        const byApp = {};
        for (const e of NotificationStore.items) {
            const app = e.appName || "Unknown";
            if (!(app in byApp)) {
                byApp[app] = { app: app, entries: [] };
                groups.push(byApp[app]);
            }
            byApp[app].entries.push(e);
        }
        const out = [];
        for (const g of groups) {
            if (g.entries.length === 1) {
                out.push({ kind: "entry", entry: g.entries[0], nested: false });
                continue;
            }
            const open = !!root.expanded[g.app];
            out.push({ kind: "group", app: g.app, count: g.entries.length, newest: g.entries[0], open: open });
            if (open)
                for (const e of g.entries)
                    out.push({ kind: "entry", entry: e, nested: true });
        }
        return out;
    }

    function toggleGroup(app) {
        const x = Object.assign({}, root.expanded);
        x[app] = !x[app];
        root.expanded = x;
    }

    function iconFor(e) {
        if (e.image)
            return e.image;
        return e.appIcon ? Quickshell.iconPath(e.appIcon, true) : "";
    }

    // Only as tall as its rows (rows are 1.5 rows high), up to notificationListRows, then it scrolls
    SunkenField {
        Layout.fillWidth: true
        visible: root.rows.length > 0
        Layout.preferredHeight: Math.min(root.rows.length, MenuStyle.notificationListRows) * MenuStyle.rowHeight * 3 / 2 + 2 * padding
        padding: 2
        clip: true

        ListView {
            id: list
            anchors.fill: parent
            model: root.rows
            delegate: Item {
                id: row
                required property var modelData
                readonly property var entry: modelData.kind === "entry" ? modelData.entry : null
                readonly property bool canReply: entry !== null && entry.notif !== null && entry.notif.hasInlineReply
                readonly property real progress: entry ? NotificationStore.progressOf(entry.notif) : -1
                width: list.width
                height: MenuStyle.rowHeight * 3 / 2

                MenuRow {
                    anchors.left: parent.left
                    anchors.leftMargin: row.modelData.nested ? MenuStyle.iconSize : 0
                    anchors.right: replyButton.visible ? replyButton.left : parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    iconSource: row.modelData.kind === "group" ? root.iconFor(row.modelData.newest) : root.iconFor(row.entry)
                    glyph: row.modelData.kind === "group" ? (row.modelData.open ? "\ue5cf" : "\ue5cc") : (row.entry.urgency === NotificationUrgency.Critical ? "\ue000" : "\ue7f4")
                    text: row.modelData.kind === "group" ? row.modelData.app + " \u00b7 " + row.modelData.count : row.entry.summary
                    subtext: row.modelData.kind === "group" ? row.modelData.newest.summary : row.entry.body.replace(/\n/g, " ")
                    trailing: row.modelData.kind === "group" ? root.timeText(row.modelData.newest.time) : (row.progress >= 0 ? Math.round(row.progress) + "%" : root.timeText(row.entry.time))
                    // A group toggles; a notification opens in its app (default action) while it is alive
                    onClicked: row.modelData.kind === "group" ? root.toggleGroup(row.modelData.app) : NotificationStore.open(row.entry.key)
                }
                BevelButton {
                    id: replyButton
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: row.canReply
                    glyph: "\ue15e"
                    focusPolicy: Qt.NoFocus
                    onClicked: {
                        root.replyTo = row.entry;
                        historyReply.text = "";
                        historyReply.focusInput();
                    }
                }
            }
        }
    }

    // Reply to a history notification (apps that offer it); Enter sends, Escape cancels
    SearchBox {
        id: historyReply
        Layout.fillWidth: true
        visible: root.replyTo !== null && root.replyTo.notif !== null
        showIcon: false
        placeholder: root.replyTo ? "Reply to " + root.replyTo.summary : ""
        onEscaped: root.replyTo = null
        onKeyPressed: event => {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                NotificationStore.reply(root.replyTo.notif, historyReply.text);
                root.replyTo = null;
                event.accepted = true;
            }
        }
    }
}
