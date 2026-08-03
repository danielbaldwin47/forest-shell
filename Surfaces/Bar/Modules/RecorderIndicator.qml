// The optional recording dot (#9, #52): a red dot and an elapsed clock, on the
// bar, while something is being recorded.
//
// Off by default, like every optional module — a module that is off is one no
// cluster names (Surfaces/Bar/BarRegistry.qml). Off by default and *also*
// invisible while idle, which is two layers of the same restraint on purpose:
// the dot is only worth bar space during the minority of a session when it has
// something to say, and a permanently-present grey dot claiming "not recording"
// is a worse answer than nothing.
//
// The file is not `Recorder.qml` for the reason NotificationIndicator.qml is not
// `Notifications.qml`: this directory is imported explicitly (see the import
// note below), and a type named `Recorder` here would shadow the service
// singleton this module reads.
//
// The dot is red and not the theme's accent. It is the one place in this shell
// where a colour is a convention rather than a choice — a red dot means
// recording on every camera anybody has ever held, and a teal one would have to
// be learned.
import QtQuick
import qs.Core
import qs.Services.Recorder
// Own directory, explicitly — `BarIndicator` is a sibling, and a file
// Quickshell loads by URL gets no implicit sibling resolution (see
// BarContent.qml).
import qs.Surfaces.Bar.Modules

BarIndicator {
    id: root

    icon: "circle-dot"

    label: Recorder.policy.barLabel(Recorder.active, Recorder.elapsedMs)

    /// Absent unless something is recording — see the header.
    shown: Recorder.active

    tint: root.recordingRed
    labelTint: Theme.textSecondary

    /// A press stops the recording, because the dot is the thing you look at
    /// when you want it to stop. It never *starts* one: a bar module that began
    /// recording on a stray click would be a surprise with a file attached.
    interactive: true
    onClicked: Recorder.stop("bar")

    readonly property color recordingRed: "#e0524f"

    /// The blink, which is the other half of the convention. Slow — a two
    /// second cycle rather than the half second a notification badge would use
    /// — because this runs for the whole length of a recording and anything
    /// faster reads as an alarm rather than as a state.
    SequentialAnimation on opacity {
        running: root.shown
        loops: Animation.Infinite
        NumberAnimation { to: 0.45; duration: 1000; easing.type: Easing.InOutQuad }
        NumberAnimation { to: 1.0; duration: 1000; easing.type: Easing.InOutQuad }
    }

    // Left where the animation stopped otherwise: the animation only runs while
    // `shown`, and an indicator that came back at 0.45 after its second
    // recording would look half-disabled.
    onShownChanged: if (!root.shown) root.opacity = 1.0
}
