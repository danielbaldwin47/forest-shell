pragma Singleton

// The notification service (#42): the freedesktop daemon, the live popup list,
// do-not-disturb, and the history the center reads (#43).
//
// `NotificationServer` is a real `org.freedesktop.Notifications` implementation
// — dunst or mako must not be running alongside it, or they contend for the
// same bus name and whichever loses looks broken.
//
// This file is the wiring; every *rule* about an arriving notification is in
// Services/Notifications/NotificationPolicy.qml, which imports nothing but
// QtQuick so tests/ can reach it. The split is the same one Config and Theme
// make, for the same reason.
//
// What one arriving notification meets, in order:
//
//   the per-app rule   — normal / silent (history only) / blocked (nothing).
//                        Enforced here, from `notifications.apps`; the
//                        three-way UI that writes that key lands with the
//                        settings window (#43, #55).
//   history            — everything that is not blocked or `transient` is
//                        remembered, whether or not it pops.
//   suppression        — DND, a fullscreen focus, or an open notification
//                        center stop the popup and nothing else. Critical
//                        urgency breaks through DND, and only DND (#9).
//
// A notification the shell does not pop is never `tracked`, so the server
// closes it and the client is told immediately rather than waiting out a
// timeout for a card nobody saw.
//
// Reading it (#43, the bar indicator and the center):
//
//   Notifications.history          // newest first, [{ appKey, summary, … }]
//   Notifications.apps             // every app that has ever notified
//   Notifications.centerOpen = true
//
// `pragma Singleton` leads the file for the reason Core/Config.qml explains.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import qs.Core
import qs.Services.Compositor

Singleton {
    id: root

    // Held as its own property rather than declared inline where it is used —
    // see Core/Config.qml for what that costs.
    readonly property NotificationPolicy policy: NotificationPolicy {}

    // --- what surfaces read --------------------------------------------------

    /// The popups that exist right now, **newest first** — the model the popup
    /// window renders (Surfaces/Notifications/). Each row's `toast` is a
    /// Services/Notifications/Toast.qml.
    ///
    /// Newest first because the stack is drawn top-down from the top-right
    /// corner: an arriving notification takes the top slot and pushes the rest
    /// down, which is the stack-shift #27 spends the shell's one translate on.
    ///
    /// A ListModel and not an array because the stack-shift is an animation:
    /// a plain JS array model rebuilds every delegate whenever it changes,
    /// which would replay every card's entrance on every arrival and lose the
    /// one translate the shell has (#27).
    readonly property alias popups: live

    ListModel {
        id: live

        // The role holds a QObject. A statically-typed ListModel role is
        // specified for strings, numbers, bools and nested elements; dynamic
        // roles hold the variant as it was given, which is the only documented
        // way to keep an object reference in one. Ten rows at the very most, so
        // the cost of dynamic roles is not a cost.
        dynamicRoles: true
    }

    /// History, newest first. Persisted to state.json, debounced (#42), and
    /// rendered by the center (#43).
    ///
    /// Not readonly only because `setHistory()` below writes it — that is the
    /// one writer, and going through it is what keeps the debounce honest.
    property var history: []

    /// Do-not-disturb. Situational rather than setup, so it is state and not
    /// config (#21) — this is the property the control centre's DND tile and
    /// the bar indicator both read.
    readonly property bool dnd: ShellState.dnd

    /// Set by the notification center while it is open (#43): a toast on top of
    /// the list the notification is already in is the same thing twice.
    property bool centerOpen: false

    /// Why popups are not showing right now, or "" when they are. For the bar
    /// indicator's tooltip, and for anyone asking "where did my notification
    /// go" — the same vocabulary, from the same cascade, as the log lines.
    ///
    /// Asked at normal urgency, because this is a question about the moment
    /// rather than about a notification: a critical one may still get through.
    readonly property string suppression: root.policy.suppressionOf({
        urgency: root.policy.urgencyNormal,
        dnd: root.dnd,
        fullscreen: Compositor.focusedFullscreen,
        centerOpen: root.centerOpen
    })

    // --- do-not-disturb ------------------------------------------------------

    function setDnd(value: bool): bool { return ShellState.set("dnd", value); }
    function toggleDnd(): bool { return root.setDnd(!root.dnd); }

    // --- per-app rules -------------------------------------------------------

    /// The rule in force for an app key, as the center and the settings window
    /// display it.
    function ruleFor(appKey: string): string {
        return root.policy.ruleFor(Config.values.notifications.apps, appKey);
    }

    /// Set — or, for "normal", clear — one app's rule. Normal is deletion and
    /// not a written-out "normal", so the file stays sparse and an app the user
    /// has un-silenced leaves no trace behind (#21).
    function setRule(appKey: string, rule: string): bool {
        if (root.policy.rules.indexOf(rule) < 0) {
            Logger.warn("notifications", rule + " is not a notification rule");
            return false;
        }
        if (!appKey) {
            Logger.warn("notifications", "cannot set a rule for an app with no key");
            return false;
        }

        const current = Config.values.notifications.apps;
        const apps = {};
        for (const key in current)
            // Drop any casing of this app's key; the one below replaces them.
            if (key.trim().toLowerCase() !== appKey)
                apps[key] = current[key];
        if (rule !== "normal")
            apps[appKey] = rule;

        return Config.set("notifications.apps", apps);
    }

    // --- history -------------------------------------------------------------

    function setHistory(next: var) {
        root.history = next;
        persist.restart();
    }

    // Whether the file has been read yet. state.json is lazy and deferred, so
    // this service is constructed — and can be notified — before its own
    // history has arrived.
    property bool loaded: false

    // Read back on the first settle of state.json, and after any genuine
    // outside edit. Our own writes never come back through here: the store
    // dispatches nothing for a reload that resolves to the values it already
    // holds.
    function loadHistory() {
        const stored = root.policy.readHistory(ShellState.values.notifications.history,
                                               Config.values.notifications.historyLimit);

        if (!root.loaded) {
            root.loaded = true;
            // Anything already in hand arrived while the file was still being
            // read, so it is newer than everything in it. Replacing rather than
            // merging here would drop the whole of history the first time a
            // notification beat the state file to the shell — which is exactly
            // what happens when the shell restarts and clients re-post.
            root.setHistory(root.history.concat(stored)
                            .slice(0, Config.values.notifications.historyLimit));
            return;
        }

        if (persist.running)
            return;   // a write of ours is still queued; it is the newer copy
        root.history = stored;
    }

    // --- arrival -------------------------------------------------------------

    function handle(notification: Notification) {
        const settings = Config.values.notifications;
        const appKey = root.policy.appKey(notification.desktopEntry, notification.appName);
        const decision = root.policy.decide({
            rule: root.policy.ruleFor(settings.apps, appKey),
            urgency: notification.urgency,
            transient: notification.transient,
            dnd: root.dnd,
            fullscreen: Compositor.focusedFullscreen,
            centerOpen: root.centerOpen
        });

        if (decision.history)
            root.remember(notification, appKey);

        if (!decision.popup) {
            // Left untracked on purpose: the server closes it now and the
            // client hears about it, instead of waiting out a timeout for a
            // card that was never on screen.
            Logger.log("notifications", "suppressed (" + decision.reason + "): "
                       + root.describe(notification, appKey));
            return;
        }

        // Tracking is what keeps the Notification object alive past this
        // handler. Everything from here holds it: the toast, and the toast's
        // RetainableLock for the length of the exit animation.
        notification.tracked = true;
        root.show(notification, settings);
    }

    function remember(notification: Notification, appKey: string) {
        root.setHistory(root.policy.remember(root.history, root.policy.record({
            id: notification.id,
            time: Date.now(),
            appKey: appKey,
            appName: notification.appName,
            appIcon: notification.appIcon,
            image: notification.image,
            summary: notification.summary,
            body: notification.body,
            urgency: notification.urgency
        }), Config.values.notifications.historyLimit));
    }

    function show(notification: Notification, settings: var) {
        const toast = toastComponent.createObject(root, {
            notification: notification,
            timeoutMs: root.policy.timeoutMs(notification.urgency, notification.expireTimeout,
                                             settings)
        });
        if (!toast) {
            Logger.warn("notifications", "could not create a popup for "
                        + root.describe(notification, ""));
            return;
        }

        toast.finished.connect(() => root.drop(toast));
        live.insert(0, { toast: toast });
        root.capStack(settings.maxVisible);
    }

    // Past the cap the oldest popup leaves early — it is in history, and a
    // stack that grows without limit is a screen a notification storm can fill
    // top to bottom.
    //
    // Counted over the toasts that are not already on their way out: a leaving
    // toast still occupies its row for the length of its exit, and asking it to
    // leave a second time does nothing, so counting those in would be a loop
    // that never gets under the cap.
    //
    // Expired, not dismissed: over D-Bus those are different words, and
    // "dismissed" means the user waved this away. Telling a client that about a
    // notification nobody ever saw is a lie it may act on — several stop
    // re-posting once something has been acknowledged.
    function capStack(maxVisible: int) {
        const showing = [];
        for (let i = 0; i < live.count; i++) {
            const toast = live.get(i).toast;
            if (!toast.leaving)
                showing.push(toast);
        }
        // Newest first, so everything past the cap is at the tail.
        for (let i = Math.max(1, maxVisible); i < showing.length; i++)
            showing[i].expire();
    }

    function drop(toast: Toast) {
        for (let i = 0; i < live.count; i++) {
            if (live.get(i).toast === toast) {
                live.remove(i);
                break;
            }
        }
        toast.destroy();
    }

    /// Send every popup on its way, for the same reason and with the same word
    /// as the cap above: the user did not act on these, the shell took them
    /// down. `includeCritical` is false for DND, which critical urgency is
    /// exempt from (#9), and true for the cases where the shell would be
    /// covering something the user is looking at.
    function clearPopups(includeCritical: bool) {
        for (let i = live.count - 1; i >= 0; i--) {
            const toast = live.get(i).toast;
            if (includeCritical || toast.notification.urgency !== NotificationUrgency.Critical)
                toast.expire();
        }
    }

    function describe(notification: Notification, appKey: string): string {
        return (appKey || notification.appName || "?") + " — " + notification.summary;
    }

    // --- reacting ------------------------------------------------------------

    // A popup already on screen when the reason to suppress arrives goes too.
    // It is in history either way, and the alternative is a card sitting over
    // the fullscreen video the user just started, or over the center they just
    // opened to read it in.
    readonly property bool covered: Compositor.focusedFullscreen || root.centerOpen
    onCoveredChanged: if (root.covered) root.clearPopups(true)
    onDndChanged: if (root.dnd) root.clearPopups(false)

    Connections {
        target: ShellState
        function onReloaded() { root.loadHistory(); }
    }

    Connections {
        target: Config

        function onKeyChanged(path, value, previous) {
            // Lowering the limit has to take effect on what is already kept,
            // not only on what arrives next — otherwise "keep 10" leaves 100
            // notifications on disk until 100 more have gone by.
            if (path === "notifications.historyLimit" && root.history.length > value)
                root.setHistory(root.history.slice(0, Math.max(0, value)));
        }
    }

    Component {
        id: toastComponent
        Toast {}
    }

    // IPC lives with what it controls and there is no central IPC file (#12 §7);
    // the target is named after the surface, lowercase.
    //
    // DND is the one thing here worth a keybind, and it has no control of its
    // own until the control centre's toggle grid (#44). Until then this is how
    // it is reached:
    //
    //   bind = SUPER, N, exec, qs ipc call notifications toggleDnd
    IpcHandler {
        target: "notifications"

        function dnd(): string {
            return root.dnd ? "on" : "off";
        }

        function toggleDnd(): string {
            root.toggleDnd();
            return root.dnd ? "on" : "off";
        }

        function setDnd(enabled: bool): string {
            root.setDnd(enabled);
            return root.dnd ? "on" : "off";
        }
    }

    NotificationServer {
        id: server

        // What the shell tells clients it can do. Honest rather than
        // optimistic: a client that is told it has hyperlinks renders a body
        // that assumes they work.
        bodySupported: true
        bodyMarkupSupported: true      // the card renders StyledText
        bodyHyperlinksSupported: false // rendered, but nothing handles a click
        bodyImagesSupported: false     // no inline <img> in the body
        imageSupported: true           // the icon/image hint, which the card shows
        actionsSupported: true
        actionIconsSupported: false    // the icon kit is Lucide by name (#34)
        inlineReplySupported: false    // post-v1
        persistenceSupported: true     // history survives a restart (#42)

        // Off: a hot reload rebuilds this service and its popup list, and a
        // notification kept across that would be tracked by a server nothing
        // is watching — a card that never leaves, or never appears.
        keepOnReload: false

        onNotification: notification => root.handle(notification)
    }

    // Debounced, because a burst of notifications is one write and because
    // state.json must never be the reason the shell is doing disk I/O in a
    // frame. Longer than the store's own `writeDebounceMs` (Core/SpecFile.qml):
    // this one is about the burst, that one is about the file.
    property int writeDebounceMs: 1000

    function writeHistory() {
        ShellState.set("notifications.history", root.history);
    }

    Timer {
        id: persist
        interval: root.writeDebounceMs
        onTriggered: root.writeHistory()
    }

    // A queued write is the notification list the user just saw; losing it to a
    // shell reload would be the one way history is not history.
    Component.onDestruction: if (persist.running) root.writeHistory()

    Component.onCompleted: {
        if (ShellState.ready)
            root.loadHistory();
        Logger.log("notifications", "server up (history " + root.history.length + " row(s)"
                   + (root.dnd ? ", dnd on" : "") + ")");
    }
}
