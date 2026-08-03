// One drawer's contents, arriving and leaving (#38).
//
// The window holds up to two of these at once, which is the whole reason the
// slot is a thing rather than a `Loader` with a `Behavior` on it: #27's
// cross-drawer transition (variant A) overlaps an outgoing drawer with an
// incoming one by about 40 ms, so for that moment both exist and each is
// running a different duration. Variant B — take one down, then put the other
// up — was rejected there for popping the compositor blur off and back on in
// the gap.
//
// Timings, all from #27:
//
//   open     enter 320 (`motionSlow`), because the scrim comes with it and the
//            whole screen changes meaning
//   close    exit 240, the step below (`Theme.exitDuration`)
//   switch   out 140, in 240 beginning at +100 ms — the scrim is untouched, so
//            this is one surface leaving and one arriving, not a fog event
//
// The entrance is opacity plus a 1% scale settle. The exit is opacity alone,
// and an entrance interrupted by an exit *freezes* its scale where it got to
// rather than reversing — #27 says so, and it is also the only reading that
// does not look like the drawer bouncing.
//
// ## Why the animations are explicit
//
// Every property here was a binding with a `Behavior` on it first, and the
// entrance did not animate at all: **a `Behavior` does not run during component
// creation**, and a slot is created already `shown` — it exists because its
// drawer just opened. So the initial binding evaluated straight to 1 and the
// card appeared at full opacity while the fog behind it faded in over 320 ms.
// The +100 ms of variant A had the same problem one level down: the incoming
// slot is a fresh delegate, so the `PauseAnimation` guarding its entrance never
// ran either and there was no crossfade, only a cut.
//
// Explicit animations, started from `enter()` and `leave()`, are what make the
// first frame of a slot's life the same as every later one. It is also what
// makes "an interrupted entrance freezes its transform" true rather than
// aspirational: stopping the entrance leaves the scale where it stood, where a
// binding would have animated it back down.
import QtQuick
import qs.Core
// Nothing here names a type from `Cards/`, and the import still has to be in
// *this* file rather than only in the one that needs it. Quickshell turns a
// directory into a `qs.` module while it scans the directory above it, and the
// scan reads the imports of every file except the one whose compilation is
// asking — so `Surfaces/Drawers/Dashboard.qml` cannot register its own
// subdirectory by importing it, and fails with "module qs.Surfaces.Drawers.Cards
// is not installed" (measured against 0.3.0; the sibling case is the half of #73
// the bar's `Modules/` never hit, because BarContent.qml is a sibling of the bar
// window rather than the file the window names).
//
// This line is that sibling. The dashboard imports the directory again for the
// reader's sake, and the cards import it a third time because a file loaded by
// URL gets no implicit sibling resolution at all.
import qs.Surfaces.Drawers.Cards

Item {
    id: slot

    required property string name
    required property DrawerPolicy policy

    /// Whether this is the drawer that is open. False the moment another one
    /// takes over, which is what starts the exit.
    required property bool shown

    /// Whether another drawer is on screen at the same time — the cross-drawer
    /// case, which runs at its own two durations.
    required property bool switching

    /// Raised once the exit has finished and there is nothing left to draw.
    /// The window drops the slot on this rather than on `shown`, so the
    /// outgoing drawer survives long enough to fade.
    signal retired

    anchors.fill: parent

    // Both already through the ladder, so a call site never has to remember
    // which of the two still owes it a `Theme.duration`.
    readonly property int enterMs: Theme.duration(slot.switching ? Theme.motionStandard
                                                                 : Theme.motionSlow)
    readonly property int exitMs: slot.switching
                                  ? Theme.duration(Theme.motionFast)
                                  : Theme.exitDuration(Theme.motionSlow)

    /// The head start the outgoing drawer gets. `Theme.stagger` is the rung
    /// that takes it away under reduced effects; the 100 is the drawer's.
    readonly property int enterDelay: slot.switching
                                      ? Theme.stagger(slot.policy.crossfadeDelayMs)
                                      : 0

    // Arrives invisible and is animated in, rather than bound to `shown` — see
    // the header for what that cost the first time round.
    opacity: 0

    /// Start arriving. Cancels an exit, because a drawer toggled back on while
    /// it is still fading out is one surface changing its mind, not two.
    function enter(): void {
        exit.stop();
        body.scale = slot.policy.entryScale(Theme.animateTransforms);
        entrance.restart();
    }

    /// Start leaving. The entrance is stopped rather than reversed, so an
    /// interrupted one keeps the scale it reached.
    function leave(): void {
        entrance.stop();
        exit.restart();
    }

    SequentialAnimation {
        id: entrance

        PauseAnimation { duration: slot.enterDelay }

        ParallelAnimation {
            NumberAnimation {
                target: slot
                property: "opacity"
                to: 1
                duration: slot.enterMs
                easing.type: Easing.Bezier
                easing.bezierCurve: Theme.fogEase
            }

            // Reduced, `entryScale` already handed back 1, so this animates
            // nothing — which is rung 3's "the property snaps" arriving as an
            // absence of movement rather than as a branch here.
            NumberAnimation {
                target: body
                property: "scale"
                to: 1.0
                duration: slot.enterMs
                easing.type: Easing.Bezier
                easing.bezierCurve: Theme.fogEase
            }
        }
    }

    NumberAnimation {
        id: exit

        target: slot
        property: "opacity"
        to: 0
        duration: slot.exitMs
        easing.type: Easing.Bezier
        easing.bezierCurve: Theme.fogEase

        onFinished: slot.retired()
    }

    onShownChanged: slot.shown ? slot.enter() : slot.leave()

    // A slot is created already `shown` — it exists because its drawer just
    // opened — so `onShownChanged` never fires for the first one.
    Component.onCompleted: if (slot.shown) slot.enter();

    Loader {
        id: body

        anchors.centerIn: parent

        // Centred, and so scaled about its own centre. #27 gives anchored
        // panels — the notification centre under its bar indicator (#43), the
        // control centre under its button (#44) — an origin at their anchor
        // instead, which for a tenant that fills the slot means the corner it
        // hangs from: scaling a screen-sized item about its top-right leaves
        // that corner still and grows the panel out of the icon above it.
        // The dashboard is the third anchored tenant and the only one anchored
        // to the *middle* of the bar: the clock is in the centre cluster, so the
        // panel hangs from the top edge with its own centre under it and grows
        // out of the time (#27, "each drawer is anchored to what opened it").
        transformOrigin: slot.name === "notificationcenter"
                         || slot.name === "controlcenter" ? Item.TopRight
                       : slot.name === "dashboard" ? Item.Top
                                                   : Item.Center

        sourceComponent: slot.name === "session" ? sessionMenu
                       : slot.name === "launcher" ? launcher
                       : slot.name === "notificationcenter" ? notificationCenter
                       : slot.name === "controlcenter" ? controlCenter
                       : slot.name === "dashboard" ? dashboard
                       : null
    }

    Component {
        id: sessionMenu
        SessionMenu {
            onCloseRequested: reason => Drawers.close(reason)
        }
    }

    // The launcher is the one tenant that is not a panel: it is a clearing, and
    // its card sits at a fraction of the *screen* height rather than in the
    // middle of it (#39, #11 §6). So it is handed the whole slot to lay itself
    // out in — centring an item that is already the full size is a no-op, and
    // the 1% settle then scales the clearing about the screen's centre, which
    // is where the card is anchored from anyway.
    Component {
        id: launcher
        Launcher {
            implicitWidth: slot.width
            implicitHeight: slot.height
            onCloseRequested: reason => Drawers.close(reason)
        }
    }

    // The centre is the second tenant that is not centred: it hangs from the
    // top-right corner, under the bar indicator that opens it, which is #27's
    // "each drawer is anchored to what opened it". So it takes the whole slot
    // to place itself in, like the launcher — and, unlike the launcher, moves
    // its transform origin to that corner, so the 1% settle grows out of the
    // icon rather than out of the middle of the screen.
    Component {
        id: notificationCenter
        NotificationCenter {
            implicitWidth: slot.width
            implicitHeight: slot.height
            onCloseRequested: reason => Drawers.close(reason)
        }
    }

    // The dashboard (#49), which takes the whole slot for the same reason the
    // three above it do — it places itself against the top edge under the
    // clock, and an item centred in the slot cannot be told to hang from an
    // edge instead.
    Component {
        id: dashboard
        Dashboard {
            implicitWidth: slot.width
            implicitHeight: slot.height
            onCloseRequested: reason => Drawers.close(reason)
        }
    }

    // The centre's twin on the other corner of the same bar (#44): the same
    // placement argument, the same whole-slot handoff, and the same transform
    // origin — the panel grows out of the button that opened it rather than out
    // of the middle of the screen.
    Component {
        id: controlCenter
        ControlCenter {
            implicitWidth: slot.width
            implicitHeight: slot.height
            onCloseRequested: reason => Drawers.close(reason)
        }
    }
}
