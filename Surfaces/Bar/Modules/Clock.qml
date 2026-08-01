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
// commit a key that ticket would have to migrate away from.
import QtQuick
import qs.Core

Text {
    text: Qt.formatDateTime(Time.now, "ddd d MMM   HH:mm")

    color: Theme.textSecondary
    font.family: Theme.fontDisplay
    font.weight: Theme.weightDisplay
    // pointSize, not pixelSize: the type scale has half-pixel steps and
    // `font.pixelSize` is an int (measured in #10, the hard way).
    font.pointSize: Theme.pt(13)
}
