import QtQuick
import ".."

BarButton {
    // Bell, or bell-off while Do Not Disturb is on
    iconFontValue: Config.settings.notifications.dnd ? "\ue7f6" : "\ue7f4"
    toggledIconFontValue: ""
    label: Time.time

    // Unread marker on the bell
    Rectangle {
        visible: NotificationStore.unread > 0
        x: MenuStyle.unreadDotX
        y: MenuStyle.unreadDotY
        width: MenuStyle.unreadDotSize
        height: MenuStyle.unreadDotSize
        color: Config.colors.urgent
        border.width: 1
        border.color: Config.colors.outline
    }
}
