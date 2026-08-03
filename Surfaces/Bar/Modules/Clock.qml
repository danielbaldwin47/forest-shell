// The clock.
//
// The one place the display serif appears (brief §4: Newsreader, "clock only,
// once, never twice"). Everything else on the bar is Plex Sans, so the clock
// reads as the bar's one considered object rather than as another readout —
// and at Light it is quiet enough not to shout about it.
//
// It ticks once a minute, on the minute, from the shell-wide clock
// (Core/Time.qml). Seconds are deliberately not shown: at 60 wakeups a minute
// to redraw a glyph nobody is watching, they would cost most of the idle budget
// (#22 §5) on their own.
//
// The format is fixed here rather than in settings.json because the clock
// format key belongs to the weather & time ticket (#50), along with the
// 12/24-hour choice and the locale question underneath it. Naming it now would
// commit a key that ticket would have to migrate away from. #93 is the other
// half of that: this module and the lock screen still answer the question
// differently, and Core/ClockFormat.qml is where the single answer now lives —
// the dashboard reads it, and #93 is what moves these two onto it.
//
// **It is also a door** (#49). The clock is what opens the dashboard, which is
// why that surface has no bar module of its own: the time is the thing you look
// at when you want to know what today is, and #9 hangs the day's panel off it.
// Dispatched through Core/SurfaceBus.qml like the launcher and control-centre
// buttons, so the module holds no reference to a surface that may not have
// loaded yet.
import QtQuick
import qs.Core

Text {
    id: clock

    text: Qt.formatDateTime(Time.now, "ddd d MMM   HH:mm")

    // Lit under the pointer, which is the whole of "this is pressable" on a
    // module that must not grow a button's chrome — the clock is the bar's one
    // considered object, and a hover fill around it would make it a control
    // among controls.
    color: hover.hovered ? Theme.accentPrimary : Theme.textSecondary
    font.family: Theme.fontDisplay
    font.weight: Theme.weightDisplay
    // pointSize, not pixelSize: the type scale has half-pixel steps and
    // `font.pixelSize` is an int (measured in #10, the hard way).
    font.pointSize: Theme.pt(13)

    Behavior on color {
        ColorAnimation {
            duration: Theme.duration(Theme.motionFast)
            easing.type: Easing.Bezier
            easing.bezierCurve: Theme.fogEase
        }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        onTapped: SurfaceBus.toggle("dashboard")
    }
}
