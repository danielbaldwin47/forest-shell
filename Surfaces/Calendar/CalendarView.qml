// The calendar window: a floating toplevel holding the day, week and month
// views.
//
// ## Why a FloatingWindow and not a layer surface
//
// This is the decision most likely to be "improved" later, so it is written
// down here rather than in a ticket nobody will find.
//
// A layer surface that wants the keyboard has to say how much of it it wants,
// and Hyprland's answer to `keyboardFocus: Exclusive` is not scoped to the
// keyboard at all: an exclusive layer surface captures **pointer** input as
// well, and while one is up, hit-testing among ordinary surfaces stops
// happening. That is #187 — a bar whose buttons were unreachable while a
// drawer was open, where every IPC-driven check passed throughout because the
// verb was never the broken part. `Surfaces/Drawers/DrawerWindow.qml` carries
// the measurement.
//
// This surface is nine parts pointer to one part keyboard: dragging on a grid
// to make an event, dragging a chip to move it, dragging an edge to resize it,
// and three text fields. A focus model that quietly breaks pointer routing is
// the worst possible fit for it.
//
// A `FloatingWindow` is an ordinary toplevel, so it gets ordinary focus and
// ordinary hit-testing, and placement, movement, resizing, tiling and the close
// button stay the compositor's job — the same argument
// `Surfaces/Settings/SettingsView.qml` makes, and it applies harder here.
//
// **If a layer variant is ever wanted, it is `OnDemand`, never `Exclusive`.**
//
// ## What this file is now
//
// The window's chrome and its state, with the body still a placeholder: the
// views land in later pieces, and everything they need — which view, which day,
// what time it is pretending to be, which event is selected — is already a
// property here so they can be dropped in without restructuring this file or
// the harnesses that drive it.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Core

FloatingWindow {
    id: window

    /// `day`, `week` or `month`. Bound from `CalendarWindow` by whoever built
    /// this, so it survives the window being closed and reopened.
    property string view: "week"

    /// The day the view is built around.
    property string anchorDate: ""

    /// What the now-line should believe the time is, as `"2026-08-18T13:40"`,
    /// or `""` for the real clock.
    ///
    /// This exists for tools/capture-harness.sh and it is not a debugging
    /// nicety: a now-line drawn from the wall clock means no two captures of
    /// this surface are ever the same picture, so a diff between two runs is
    /// unreadable. `--cal-now` freezes it, exactly as `--lock-state` poses PAM.
    property string nowOverride: ""

    /// The selected event's id, or `""`.
    property string selectedId: ""

    /// The window wants to go away, and why: `"compositor"` for the close
    /// button or a window-manager kill, `"escape"` for the key. Whoever opened
    /// the window owns tearing it down; this only reports it, and the reason is
    /// what the log line at the other end says.
    signal closeRequested(string reason)

    title: "forest-shell — calendar"
    // Stated rather than assumed: the window exists only while it is open, so
    // it is mapped as soon as it is built, and the assignment the compositor
    // makes when the close button is hit is what `wasShown` below reads.
    visible: true
    implicitWidth: 1180
    implicitHeight: 760
    minimumSize: Qt.size(900, 600)
    color: Theme.bgBase

    // A window that has been shown and is now not is a window that was closed.
    // The flag is what keeps the not-yet-mapped state — visible is false for a
    // moment after construction — from reading as a close.
    property bool wasShown: false
    onVisibleChanged: {
        if (window.visible)
            window.wasShown = true;
        else if (window.wasShown)
            window.closeRequested("compositor");
    }

    Item {
        anchors.fill: parent
        focus: true

        // Escape, from wherever the focus is. An unhandled key walks up the
        // focus chain, so the window needs exactly one handler for it and no
        // control inside needs to know the window can be closed.
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                window.closeRequested("escape");
                event.accepted = true;
            }
        }

        // --- the body ---------------------------------------------------------
        //
        // A placeholder, and deliberately one that names its own state: what it
        // draws is exactly what the harnesses assert over IPC, so a capture of
        // this window and a line in the log say the same thing about it. The
        // grid replaces this wholesale in the next piece.
        Column {
            anchors.centerIn: parent
            spacing: Tokens.space3

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: window.view + " view"
                color: Theme.textPrimary
                font.family: Tokens.fontUi
                font.pointSize: Tokens.pt(22)
                font.weight: Tokens.weightMedium
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: window.anchorDate
                color: Theme.textSecondary
                font.family: Tokens.fontUi
                font.pointSize: Tokens.pt(15)
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: window.nowOverride.length > 0
                text: "now " + window.nowOverride
                color: Theme.textMuted
                font.family: Tokens.fontMono
                font.pointSize: Tokens.pt(12)
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: window.selectedId.length > 0
                text: "selected " + window.selectedId
                color: Theme.textMuted
                font.family: Tokens.fontMono
                font.pointSize: Tokens.pt(12)
            }
        }
    }
}
