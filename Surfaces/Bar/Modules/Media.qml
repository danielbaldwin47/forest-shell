// The media pill (#9, #37): what is playing, and one click to stop it.
//
// The centre cluster's second module, beside the clock — which is where #9 put
// it, and it is the right place: the pill is the one thing on the bar that is
// about what you are *doing* rather than about the machine's condition, and the
// two clusters either side of it are all condition.
//
// It is not on the bar when nothing is playing. That is the same rule the mic
// glyph follows in the status cluster: a permanent empty slot would be furniture
// that says nothing, and here it would be furniture 180px wide.
//
// The title is capped and elided, because it is arbitrary text from another
// application: an uncapped one pushes the clock off the centre of the bar, which
// is the #80 class of overflow. `bar.mediaMaxWidth` is the ceiling.
import QtQuick
import qs.Core
import qs.Services.Media
// Own directory, explicitly — `BarIndicator` is a sibling, and a file
// Quickshell loads by URL gets no implicit sibling resolution (see
// BarContent.qml).
import qs.Surfaces.Bar.Modules

BarIndicator {
    id: root

    shown: Mpris.showing

    /// The glyph says what a click does rather than what is happening — the
    /// argument is in MprisPolicy, and it is the reason this module needs no
    /// second glyph for state.
    icon: Mpris.icon
    label: Mpris.label
    labelMaxWidth: Config.values.bar.mediaMaxWidth

    // Click to play or pause, and nothing on the wheel. Skipping a track is the
    // one media gesture that cannot be undone by repeating it, and a wheel that
    // skipped would fire on a scroll aimed at the window underneath the bar.
    interactive: true
    onClicked: Mpris.togglePlaying()
}
