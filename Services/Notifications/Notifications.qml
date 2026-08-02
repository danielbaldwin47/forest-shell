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
//   Notifications.groups           // the same rows, one entry per app (#43)
//   Notifications.knownApps        // every app history remembers (#54, #71)
//   Notifications.unreadCount      // what the bar indicator badges (#43)
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
import qs.Services.System

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

    /// Every app history remembers, sorted — the settings window's per-app
    /// rules tab lists these without the user having to type an app id (#54,
    /// #71). Derived from history rather than kept as a second list, so an app
    /// appears the moment it notifies and the two can never disagree.
    readonly property var knownApps: root.policy.knownApps(root.history)

    /// Do-not-disturb. Situational rather than setup, so it is state and not
    /// config (#21) — this is the property the control centre's DND tile and
    /// the bar indicator both read.
    readonly property bool dnd: ShellState.dnd

    /// Set by the notification center while it is open (#43): a toast on top of
    /// the list the notification is already in is the same thing twice.
    property bool centerOpen: false

    /// History grouped by app, newest app first — the center's model (#43).
    /// Derived rather than maintained, so it cannot disagree with the list.
    readonly property var groups: root.policy.groups(root.history)

    /// When the center was last looked at, in epoch ms, or 0 for "never".
    /// Persisted, because a badge that resets on every shell restart is a badge
    /// that lies about what the user has seen.
    property double seenAt: 0

    /// What the bar indicator counts (#43). Not "unread" in the sense of a
    /// per-row flag — nothing in the shell marks one row read — but "arrived
    /// since the center was last open", which is the only reading this shell
    /// can support honestly. NotificationPolicy holds the argument.
    readonly property int unreadCount: root.policy.unreadSince(root.history, root.seenAt)

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

    /// Clear one app's rows — the center's per-app clear (#43). The rule the
    /// app is under is untouched: clearing what an app has said is not the same
    /// act as deciding what it may say, and conflating the two would silence an
    /// app the user only wanted to tidy up after.
    function clearApp(appKey: string): void {
        const before = root.history.length;
        root.setHistory(root.policy.withoutApp(root.history, appKey));
        Logger.log("notifications", "cleared " + (appKey || "(no app id)") + " — "
                   + (before - root.history.length) + " row(s), " + root.history.length + " left");
    }

    /// Clear everything. Popups on screen are left alone: they are their own
    /// surface with their own dismissal, and a clear-all that also swept the
    /// screen would take away the notification the user is reading right now.
    function clearAll(): void {
        const before = root.history.length;
        root.setHistory([]);
        Logger.log("notifications", "cleared history — " + before + " row(s)");
    }

    /// Drop one row, by the row key (#76). The counter is deliberately not
    /// lowered: `seq` is a high-water mark, and the row that carried the
    /// highest number leaving is exactly the case it exists for.
    function dismiss(key: string): void {
        const before = root.history.length;
        const next = root.policy.withoutRow(root.history, key);
        if (next.length === before) {
            Logger.warn("notifications", "no history row " + key + " to dismiss");
            return;
        }
        root.setHistory(next);
        Logger.log("notifications", "dismissed " + key + ", " + next.length + " row(s) left");
    }

    /// Mark everything remembered as seen — what opening the center means, and
    /// what empties the bar indicator's count.
    ///
    /// Stamped with the clock rather than with the newest row's time, so a
    /// notification that arrives in the same millisecond as the click is not
    /// counted as already-read.
    function markSeen(): void {
        root.seenAt = Date.now();
        persist.restart();
        Logger.log("notifications", "seen (unread " + root.unreadCount + ")");
    }

    // Both edges. Opening the center is the user saying they have looked; the
    // closing edge covers what arrived while it was open, which they were
    // looking at as it landed — the popup was suppressed precisely because the
    // list underneath already had it.
    onCenterOpenChanged: root.markSeen()

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

        // Never downwards. A row remembered before the file arrived has already
        // taken a number out of the counter's range, and the rows just read may
        // carry numbers `readHistory` issued to a hand-edited file.
        root.seq = root.policy.nextSeq(stored, Math.max(root.seq,
                                                        ShellState.values.notifications.seq)) - 1;

        // Never backwards either, and for the same reason: the center may have
        // been opened before the file arrived, and the stamp that says so is
        // newer than anything on disk.
        root.seenAt = Math.max(root.seenAt, ShellState.values.notifications.seenAt);

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

    /// The last sequence number issued to a history row (#76). Persisted beside
    /// the list rather than derived from it, because the list is not a reliable
    /// high-water mark — the center dismisses single rows (#43), and lowering
    /// `historyLimit` truncates it below.
    property int seq: 0

    // The row's identity is the shell's, not the daemon's: `notification.id`
    // comes from a counter that restarts at 1 with every server, and history
    // outlives the server (#76). It is kept as `serverId` for correlating with
    // a live popup.
    function remember(notification: Notification, appKey: string) {
        root.seq = root.policy.nextSeq(root.history, root.seq);
        const entry = root.policy.record({
            serverId: notification.id,
            seq: root.seq,
            time: Date.now(),
            appKey: appKey,
            appName: notification.appName,
            appIcon: notification.appIcon,
            image: notification.image,
            summary: notification.summary,
            body: notification.body,
            urgency: notification.urgency
        });
        root.setHistory(root.policy.remember(root.history, entry,
                                             Config.values.notifications.historyLimit));
        // The row key, in the log, because #76 was a collision nothing rendered
        // and nothing complained about — the ids only stopped being unique.
        Logger.log("notifications", "remembered " + entry.key + " (server id "
                   + entry.serverId + "): " + root.describe(notification, appKey));
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

        // The resolved timeout, in the log, because it is the one number here
        // that no test at the pure seam can prove came off a real
        // `Notification` — #74 was a unit error on exactly that hand-off.
        Logger.log("notifications", "popup (timeout " + toast.timeoutMs + "ms, client "
                   + notification.expireTimeout + "): " + root.describe(notification, ""));
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

    // --- the lock (#71) ------------------------------------------------------
    //
    // The lock shows how many notifications arrived while it was up, as a
    // number and never as contents (#9, #30). The count is written here rather
    // than read there because `SessionLock` is deliberately ignorant of
    // everything but locking — it holds one inbound property and this service
    // is the one object that knows what to put in it.

    // When the current lock went up, or 0 while the session is unlocked. Kept
    // on this side of the seam for the same reason: it is the notification
    // service's window onto history, not a fact about the lock.
    //
    // Not persisted. A shell restarted while the session is locked starts the
    // window again from the restart, which undercounts — and the alternative,
    // trusting a lock timestamp across a shell that was not running, would
    // overcount every notification the previous shell already showed.
    property double lockedAt: 0

    readonly property int lockCount: root.policy.countSince(root.history, root.lockedAt)

    Connections {
        target: SessionLock
        function onLockedChanged() {
            root.lockedAt = SessionLock.locked ? Date.now() : 0;
        }
    }

    // Only while the lock is up, which is the only time the number means
    // anything — and it leaves the property assignable when it is not. That
    // second half is load-bearing: `capture-harness.qml` poses the strip by
    // assigning a count to an unlocked session (`--lock-state notify:3`), and
    // an unconditional binding here would quietly win that assignment and
    // photograph an empty strip.
    Binding {
        target: SessionLock
        property: "notificationCount"
        value: root.lockCount
        when: SessionLock.locked
    }

    // The count in the log, because the strip that renders it is behind a lock
    // and a setting: "the count is wrong" and "the readout is off" look the
    // same from outside, and #81 is what a silent lifecycle costs.
    onLockCountChanged: if (root.lockedAt > 0)
        Logger.log("notifications", "lock count " + root.lockCount);

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

        /// What the bar indicator is showing, as a number — the answer to "is
        /// the badge right", from outside the shell.
        function unread(): int {
            return root.unreadCount;
        }

        /// Empty history. The center's clear-all has a button; this is the same
        /// act for a keybind, and it is what tools/notification-harness.sh
        /// drives the surface-free half of the ticket with.
        function clear(): string {
            const before = root.history.length;
            root.clearAll();
            return String(before) + " cleared";
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

    // The counter goes out with the list it numbers, on the same debounce: the
    // two are one fact, and a list written without its high-water mark is a
    // file that reissues numbers on the next start (#76).
    function writeHistory() {
        ShellState.set("notifications.history", root.history);
        ShellState.set("notifications.seq", root.seq);
        // On the same debounce as the list, because "what is here" and "what
        // has been looked at" are one fact: a list written without its seen
        // stamp comes back with a badge for notifications the user has read.
        ShellState.set("notifications.seenAt", root.seenAt);
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
