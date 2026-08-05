// The notification indicator (#9, #43) — the last of the Standard-14, and the
// door into the notification centre.
//
// Three glyphs, and they answer three different questions:
//
//   bell-off   do-not-disturb is on. It wins over everything, because "why am I
//              not being interrupted" is the only question worth answering from
//              across the room, and the count is still beside it — DND silences
//              the popup and never the record (#9).
//   bell-dot   something has arrived since the centre was last open.
//   bell       nothing waiting.
//
// The number beside it is `Notifications.unreadCount`, which in this shell
// means "arrived since you last looked" — there is no per-row read flag and no
// honest seam at which to put one (Services/Notifications/NotificationPolicy
// .qml has the argument). Opening the centre is what empties it.
//
// Named `notifications` in the registry and in `bar.modules`, like every other
// module id; the *surface* it opens is `notificationcenter` on the bus and on
// IPC, because the notification service already owns the `notifications` IPC
// target for DND (Core/SurfaceBusPolicy.qml).
//
// The file is not `Notifications.qml`: this directory is imported explicitly by
// the bar (see BarContent.qml), and a type of that name here would shadow the
// `Notifications` singleton this very file reads.
import QtQuick
import qs.Core
// Own directory, explicitly — see BarContent.qml for why a URL-loaded file gets
// no siblings for free.
import qs.Surfaces.Bar.Modules
import qs.Services.Notifications

BarIndicator {
    id: root

    readonly property int unread: Notifications.unreadCount

    icon: Notifications.dnd ? "bell-off"
        : root.unread > 0 ? "bell-dot"
        : "bell"

    // Capped and formatted on the far side of the service, where a test can
    // reach it: past 99 the exact number stops being information and starts
    // being a module wide enough to push the clock off centre (#80).
    label: Notifications.policy.countLabel(root.unread)

    // The alarm is the glyph, never the number (BarIndicator.qml): ember fails
    // the bar's own 4.5:1 rule as text over the brightest wallpaper, and a
    // waiting notification is not urgent anyway — warm is "attention" and that
    // is exactly what this is (#8 §2, #79).
    tint: root.unread > 0 && !Notifications.dnd ? Theme.accentWarm : Theme.textSecondary

    interactive: true
    onClicked: SurfaceBus.barClick("notificationcenter")
}
