// The keyboard layout (#9, #37): two letters, and only where they mean
// something.
//
// **It is not on the bar on a single-layout machine**, which is most of them
// and both of the ones this shell is calibrated on. A machine with one layout
// can never be in the wrong one, so a permanent `US` is a module gap spent on a
// constant — the same rule that keeps bluetooth off a desktop with no radio.
//
// The code and not the name: `DE` rather than "German", because the code is
// what every other bar shows, what the compositor config spells, and a quarter
// of the width.
import QtQuick
import qs.Core
import qs.Services.Compositor
// Own directory, explicitly — see BarContent.qml for why a URL-loaded file gets
// no siblings for free.
import qs.Surfaces.Bar.Modules

BarIndicator {
    id: root

    shown: Compositor.keyboardSwitchable
    // No glyph: a keyboard icon beside two letters that are unmistakably a
    // layout code is a glyph doing nothing. The status cluster's rule the other
    // way round — icons with no labels — is the same rule.
    label: Compositor.keyboardLayout

    // Click to cycle. Hyprland owns the order, so this is `next` and not an
    // index (KeyboardPolicy). No wheel: a scroll that landed on two letters at
    // the edge of the bar and silently changed what typing does is the worst
    // gesture on this bar.
    interactive: true
    onClicked: Compositor.cycleKeyboardLayout()
}
