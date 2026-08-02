// What the tray shows and what a click on it means, as pure functions (#37).
//
// Split out of Services/System/SystemTray.qml so tests/ can reach it — the
// facade next door imports the StatusNotifier client and is unreachable from
// there.
//
// The tray is the one module whose contents the shell does not choose: an
// application registers an icon and the bar draws it. So the decisions here are
// narrow, and two of them are about not making the tray a second notification
// system:
//
//   - **Everything registered is shown.** The SNI spec has a `Passive` status
//     meaning "hide me if space is tight", and honouring it loses icons from
//     applications that report `Passive` and never change it — which, measured
//     across real desktops, is a great many of them. A tray that silently drops
//     an icon is indistinguishable from a tray that is broken.
//   - **`NeedsAttention` is a tint, not a popup.** It is the one status worth
//     answering, and the shell already has a role for it (#8: warm is
//     attention). It is deliberately not a badge, a bounce or a notification.
import QtQuick

QtObject {
    id: policy

    /// The SNI status values, spelled here rather than imported: the upstream
    /// enum lives behind a Quickshell import, and this file's whole point is
    /// that it has none. The facade maps its enum onto these strings, which is
    /// one small translation in a file that has a compositor, against a policy
    /// that stays checkable without one.
    readonly property string passive: "passive"
    readonly property string active: "active"
    readonly property string attention: "attention"

    /// Whether this item is asking for something. The only status that changes
    /// how the icon is drawn.
    function attentive(status: var): bool {
        return status === policy.attention;
    }

    /// What a left click does: `"activate"` calls the application's primary
    /// action, `"menu"` opens its menu.
    ///
    /// `onlyMenu` is the application saying it has no primary action — its
    /// `Activate` call does nothing at all, so a left click that made it would
    /// read as a dead icon. An item with neither an action nor a menu answers
    /// `"none"`, and the facade logs the click rather than swallowing it.
    function primaryAction(onlyMenu: bool, hasMenu: bool): string {
        if (onlyMenu)
            return hasMenu ? "menu" : "none";
        return "activate";
    }

    /// What a right click does. Always the menu where there is one — this is
    /// the gesture every tray has had for thirty years, and an item with no
    /// menu does nothing rather than falling back to activating, which would
    /// make right-click mean two different things depending on the app.
    function secondaryAction(hasMenu: bool): string {
        return hasMenu ? "menu" : "none";
    }
}
