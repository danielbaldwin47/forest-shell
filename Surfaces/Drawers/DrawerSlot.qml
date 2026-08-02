// One drawer's contents, arriving and leaving (#38).
//
// The window holds up to two of these at once, which is the whole reason the
// slot is a thing rather than a `Loader` with a `Behavior` on it: #27's
// cross-drawer transition (variant A) overlaps an outgoing drawer with an
// incoming one by about 40 ms, so for that moment both exist and each is
// running a different duration at a different anchor. Variant B — take one
// down, then put the other up — was rejected there for popping the compositor
// blur off and back on in the gap.
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
// does not look like the drawer bouncing. That is why the settle is an explicit
// animation rather than a `Behavior` on a bound property: a binding would
// animate the scale back down on the way out.
import QtQuick
import qs.Core

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

    readonly property int enterMs: slot.switching ? Theme.motionStandard : Theme.motionSlow
    readonly property int exitMs: slot.switching ? Theme.duration(Theme.motionFast)
                                                 : Theme.exitDuration(Theme.motionSlow)

    /// The +100 ms head start the outgoing drawer gets. Reduced, there is none:
    /// a delay is a stagger and rung 3 of the ladder has no staggers. Reading
    /// `Theme.reducedEffects` here is asking the ladder a question — the policy
    /// function *is* the rung — rather than branching on the knob.
    readonly property int enterDelay: slot.switching
                                      ? slot.policy.crossfadeDelay(Theme.reducedEffects)
                                      : 0

    opacity: slot.shown ? 1 : 0

    Behavior on opacity {
        SequentialAnimation {
            PauseAnimation { duration: slot.shown ? slot.enterDelay : 0 }
            NumberAnimation {
                duration: slot.shown ? Theme.duration(slot.enterMs) : slot.exitMs
                easing.type: Easing.Bezier
                easing.bezierCurve: Theme.fogEase
            }
        }
    }

    onOpacityChanged: if (!slot.shown && slot.opacity === 0) slot.retired()

    Loader {
        id: body

        anchors.centerIn: parent

        // Centred, and so scaled about its own centre. #27 gives anchored
        // panels — the control centre under its bar icon (#44) — an origin at
        // their anchor instead; the tenant that needs that sets it, because
        // only the tenant knows where its beak points.
        transformOrigin: Item.Center

        sourceComponent: slot.name === "session" ? sessionMenu : null
    }

    Component {
        id: sessionMenu
        SessionMenu {
            onCloseRequested: reason => Drawers.close(reason)
        }
    }

    // The 1% settle. Explicit, and only ever run upwards — see the header.
    NumberAnimation {
        id: settle

        target: body
        property: "scale"
        to: 1.0
        duration: Theme.duration(slot.enterMs)
        easing.type: Easing.Bezier
        easing.bezierCurve: Theme.fogEase
    }

    function enter(): void {
        if (!Theme.animateTransforms) {
            body.scale = 1.0;
            return;
        }
        body.scale = slot.policy.entryScale(true);
        settle.start();
    }

    onShownChanged: if (slot.shown) slot.enter();

    // A slot is created already `shown` — it exists because its drawer just
    // opened — so `onShownChanged` never fires for the first one. Deferred by a
    // frame so the starting scale is on screen before the settle begins.
    Component.onCompleted: if (slot.shown) Qt.callLater(slot.enter);
}
