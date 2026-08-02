pragma Singleton

// The system tray facade (#37, #12 §3): the only place in the shell that knows
// what a StatusNotifierItem is.
//
//     SystemTray.items      // the model the bar's Repeater draws
//     SystemTray.count
//     SystemTray.status(item)   // "passive" | "active" | "attention"
//     SystemTray.press(item)    // a left click, as the item itself defines it
//     SystemTray.middlePress(item)
//     SystemTray.scroll(item, 1)
//
// It carries the upstream singleton's name and imports it under an alias, which
// is the rule Services/README.md added in #36: `Sni.` here always means
// upstream's. The name is spent this way round on purpose — the bar module is
// `Surfaces/Bar/Modules/Tray.qml`, and the module and its service may not both
// be `Tray` (the same trade `Backlight` made for `Brightness`).
//
// Native — `Quickshell.Services.SystemTray` is a real StatusNotifierHost
// (#4 §2.5), so nothing here runs a watcher of its own.
//
// **The host is registered by this file existing.** The upstream singleton is
// lazy: nothing takes the `org.kde.StatusNotifierWatcher` name until something
// in QML first touches it, and an application that registered its icon before
// that has to be restarted to get it back. So this facade is named in
// Core/ServiceInit.qml's deferred list, which is what makes the tray fill up at
// startup rather than when the bar happens to carry the module.
//
// `items` is passed through as the upstream model object, not copied into an
// array: the bar renders one delegate per item, and reassigning a model rebuilds
// every delegate and kills the animation on all of them (#75). What can be
// decided without a bus — which items show, what a click means — is in
// Services/System/TrayPolicy.qml, which imports nothing but QtQuick so tests/
// can reach it.
//
// The one thing this file cannot do for its caller is *open a menu*: a menu is
// anchored to a window and an item on screen, and this singleton has neither.
// `press()` answers what the click meant and the bar module opens the anchor —
// see Surfaces/Bar/Modules/Tray.qml.
//
// `pragma Singleton` leads the file for the reason Core/Config.qml explains.
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray as Sni
import qs.Core

Singleton {
    id: root

    readonly property TrayPolicy policy: TrayPolicy {}

    /// The live item model — an `ObjectModel`, handed to a Repeater as-is.
    readonly property var items: Sni.SystemTray.items

    readonly property int count: Sni.SystemTray.items ? Sni.SystemTray.items.values.length : 0

    /// An item's status as the policy spells it. The one place the upstream
    /// enum is translated: the policy has no Quickshell import to read it with,
    /// and a policy that took an integer would be a policy nobody can read.
    function status(item: var): string {
        if (!item)
            return root.policy.passive;
        switch (item.status) {
        case Sni.Status.NeedsAttention: return root.policy.attention;
        case Sni.Status.Active: return root.policy.active;
        }
        return root.policy.passive;
    }

    function attentive(item: var): bool {
        return root.policy.attentive(root.status(item));
    }

    /// What a left click on this item means: `"activate"`, `"menu"` or
    /// `"none"`. Activation is performed here; a menu is the caller's to open,
    /// because a menu needs a window and a position and this file has neither.
    function press(item: var): string {
        if (!item)
            return "none";
        const action = root.policy.primaryAction(item.onlyMenu, item.hasMenu);
        if (action === "activate") {
            Logger.log("tray", "activate " + item.id);
            item.activate();
        } else if (action === "none") {
            // #81's rule: a click that does nothing must say so, or "the icon
            // is dead" and "the application offers nothing" look identical.
            Logger.warn("tray", item.id + " has no primary action and no menu");
        }
        return action;
    }

    /// A right click. Always the menu where there is one — see the policy.
    function secondaryPress(item: var): string {
        if (!item)
            return "none";
        const action = root.policy.secondaryAction(item.hasMenu);
        if (action === "none")
            Logger.warn("tray", item.id + " has no menu");
        return action;
    }

    /// A middle click — the item's secondary action, which is conventionally
    /// "open a new window" and is whatever the application says it is.
    function middlePress(item: var) {
        if (!item)
            return;
        Logger.log("tray", "secondary activate " + item.id);
        item.secondaryActivate();
    }

    /// The wheel, passed through: some items use it for volume, most ignore it.
    /// The direction and not the delta, for the reason
    /// Surfaces/Bar/Modules/BarIndicator.qml gives — a high-resolution wheel
    /// sends many small deltas.
    function scroll(item: var, direction: int) {
        if (!item)
            return;
        item.scroll(direction, false);
    }

    // --- what a harness reads ------------------------------------------------
    //
    // The tray is a list that fills up asynchronously after the host registers,
    // so "how many items" is the state change worth a line: an empty tray and a
    // tray that never registered look the same on screen.

    onCountChanged: Logger.log("tray", root.count + " item(s)")

    Component.onCompleted: Logger.log("tray",
        "statusnotifier host registered (" + root.count + " item(s) so far)")
}
