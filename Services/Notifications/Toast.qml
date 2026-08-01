// One notification while it is on screen (#42).
//
// A popup outlives the notification it shows, by exactly one exit animation.
// The client can close a notification at any moment — a chat that was read on
// the phone, a progress bar reaching 100% — and without the `RetainableLock`
// below the object would be destroyed under the card, which would vanish
// mid-frame instead of fading. Retaining it is what makes the exit a motion
// rather than a disappearance (#27: the toast condenses in and fades out).
//
// So the object's life has three phases, and the card reads all of them:
//
//   showing   — `leaving` false, the lifetime timer running;
//   leaving   — `leaving` true, the notification possibly already closed as far
//               as its client is concerned, the card playing its 140ms exit;
//   finished  — the signal that tells the service to drop and destroy this.
//
// Not visual, and not a surface: this is the *state* of a popup. What it looks
// like is Surfaces/Notifications/NotificationCard.qml.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import qs.Core

Scope {
    id: toast

    required property Notification notification

    /// How long this stays up, in ms — 0 for "until it is dismissed".
    /// Resolved by NotificationPolicy from the urgency table before the toast
    /// is created, so nothing here reads Config.
    required property int timeoutMs

    /// Set by the card while the pointer is over it. A notification must not
    /// vanish out from under someone who is reading it.
    property bool held: false

    /// True from the moment this is on its way out, and never false again. The
    /// card animates on it; every entry point below is a no-op once it is set,
    /// so a client close racing a user dismiss cannot start two exits — and it
    /// does not flick back at the end of the exit, which would re-show a card
    /// in the frame before the service destroys it.
    property bool leaving: false

    /// Ready to be dropped from the popup list and destroyed.
    signal finished()

    /// Dismissed by the user — the close button, or a click that is not on an
    /// action. Tells the client the notification was seen and waved off, which
    /// is a different thing from having timed out.
    function dismiss() {
        if (toast.leaving)
            return;
        toast.notification.dismiss();
        toast.leave();
    }

    /// Ran out of time. Reported as expiry rather than dismissal so a client
    /// that re-posts unacknowledged notifications can tell the difference.
    function expire() {
        if (toast.leaving)
            return;
        toast.notification.expire();
        toast.leave();
    }

    /// Invoke one of the notification's actions.
    ///
    /// A notification that is not `resident` is done once an action is taken —
    /// that is the freedesktop convention, and leaving the card up after the
    /// user has answered it reads as a failed click.
    function invoke(action: NotificationAction) {
        action.invoke();
        if (!toast.notification.resident)
            toast.dismiss();
    }

    // Starts the exit. Called by every path out, including the one where the
    // client closed the notification without asking us.
    function leave() {
        if (toast.leaving)
            return;
        toast.leaving = true;
        exit.start();
    }

    // The client closed it — remotely, or because we just did. The object is
    // still alive because of the lock; this is the last moment it is, so the
    // exit has to be started from here rather than assumed to be running.
    RetainableLock {
        object: toast.notification
        locked: true
        onDropped: toast.leave()
    }

    Timer {
        id: life

        // Hovering stops the clock rather than pausing it: a Timer cannot be
        // resumed part-way, and restarting the full timeout when the pointer
        // leaves is the behaviour you want anyway — reading a card should buy
        // it a fresh moment on screen, not the two seconds it had left.
        interval: Math.max(1, toast.timeoutMs)
        running: toast.timeoutMs > 0 && !toast.held && !toast.leaving
        onTriggered: toast.expire()
    }

    // The exit is a timer and not an animation because the animation lives on
    // the card, which may not exist: popups render on the focused screen only
    // (#22 §1), so a toast on any other screen has no card to fade. Its life
    // still has to end on time.
    Timer {
        id: exit
        interval: Theme.exitDuration(Theme.motionStandard)   // 140ms (#27)
        onTriggered: toast.finished()
    }
}
