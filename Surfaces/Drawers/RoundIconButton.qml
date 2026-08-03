// The small round icon button every drawer surface is made of (#44, #49).
//
// A hover disc, a glyph, and a `pressed` signal. It exists as a file because it
// is the third caller that makes a component shared and there are now four: the
// control centre's strip (the settings gear, the power button and the three
// transport controls), the dashboard's calendar header and its media card. Two
// of those were literal copies of the first, comment included.
//
// **Here rather than in `Widgets/`**, which is the line that decides where a
// component lives: `Widgets/` is dumb by contract — no Services, no Config, no
// Theme, colour passed in by the caller (Widgets/README.md). This reads three
// tokens and the motion ladder, because "what a hover looks like in a drawer"
// is a decision about *these surfaces* rather than a widget. `RoundIconButton`
// and not `IconButton`, because Surfaces/Settings/Controls/IconButton.qml
// already owns that name and Surfaces/Drawers/ControlCenter.qml imports both
// directories.
//
// The two sizes are the two jobs: a strip control sits in a row of text and is
// 28px, a transport control is something you reach for and is bigger. Both are
// component dimensions rather than tokens (#8) — a hit target is a fact about
// fingers, not a step on a spacing scale.
import QtQuick
import qs.Core
import qs.Widgets

Item {
    id: button

    /// The Lucide name, as Widgets/Icon.qml takes it.
    required property string glyph

    /// The glyph's size; the disc around it is `diameter`.
    property int size: 16
    property int diameter: 28

    /// Drawn, but not available. Dimmed rather than hidden: a player that will
    /// not skip is worth showing as a player that will not skip, and a control
    /// that vanished would move everything beside it (#44).
    ///
    /// It does *not* gate the signal — the refusal belongs to the service that
    /// knows why (Services/Media/Mpris.qml logs one), and a button that
    /// swallowed the press would be #81's silence again.
    property bool dimmed: false

    signal pressed

    implicitWidth: button.diameter
    implicitHeight: button.diameter

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        onTapped: button.pressed()
    }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: hover.hovered ? Theme.surfaceOverlay : "transparent"

        Behavior on color {
            ColorAnimation {
                duration: Theme.duration(Theme.motionFast)
                easing.type: Easing.Bezier
                easing.bezierCurve: Theme.fogEase
            }
        }
    }

    Icon {
        anchors.centerIn: parent
        name: button.glyph
        size: button.size
        color: button.dimmed ? Theme.textMuted
             : hover.hovered ? Theme.accentPrimary : Theme.textSecondary
    }
}
