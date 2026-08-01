// Staged startup (#12 §4, #22 §4).
//
//   stage 1, synchronous : Config → Theme → Background. Nothing may be added
//                          here that is not needed to paint the wallpaper.
//   stage 2, deferred    : everything else, chained off the first painted
//                          frame via Qt.callLater + a short timer, so no
//                          service construction can push the frame out.
//
// The fallback timer exists because the chain hangs off a real frame: with zero
// screens attached (lid closed, nothing docked — an explicit #22 test case) no
// frame ever arrives, and the deferred stage must still run.
pragma Singleton
import QtQuick
import Quickshell

Singleton {
    id: root

    // Long enough to let the compositor settle the first frame, short enough to
    // stay inside the 2 s interactive budget.
    readonly property int deferDelayMs: 120

    // Deadline for the no-frame fallback, measured from *process start* rather
    // than from this singleton's construction — otherwise the 900 ms the engine
    // spends starting up is added to the budget and the screenless shell goes
    // interactive at ~2.4 s, past #22 §4's 2 s.
    readonly property int interactiveDeadlineMs: 1800

    property bool firstFramePainted: false
    property bool deferredRan: false
    property bool interactive: false

    // Stage two. Connect anything that is not needed for the first frame.
    signal deferredStage()

    // Called by the first background surface to paint.
    function markFirstFrame() {
        if (root.firstFramePainted)
            return;
        root.firstFramePainted = true;
        Logger.stage("first frame painted");
        Qt.callLater(() => deferTimer.start());
    }

    function runDeferredStage() {
        if (root.deferredRan)
            return;
        root.deferredRan = true;
        deferTimer.stop();
        fallbackTimer.stop();

        Logger.stage("deferred begin");
        root.deferredStage();
        root.interactive = true;
        Logger.stage("interactive");
    }

    Timer {
        id: deferTimer
        interval: root.deferDelayMs
        onTriggered: root.runDeferredStage()
    }

    Timer {
        id: fallbackTimer
        // Evaluated once, at construction: what is left of the deadline.
        interval: Math.max(100, root.interactiveDeadlineMs - Logger.elapsedMs())
        running: true
        onTriggered: {
            if (!root.firstFramePainted)
                Logger.log("startup", "no frame painted yet (no screens?) — running deferred stage anyway");
            root.runDeferredStage();
        }
    }
}
