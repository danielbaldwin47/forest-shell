// The brightness module (#9, #36) — shipped in the registry, in no default
// list.
//
// Off by default because the laptop this shell is built on has brightness keys
// that already work, and a bar slot spent restating what F5 and F6 do is a slot
// not spent on something you cannot otherwise see. It exists because a machine
// whose keys are not wired — an external panel, a keyboard without the row — is
// exactly the machine that needs it, and because the wheel gesture is finer
// than the keys are.
//
// It also hides itself where there is nothing to drive: a desktop, or a laptop
// whose panel answers to DDC rather than to the kernel's backlight class (#4 —
// `ddcutil` is the same facade's other backend, and post-v1).
import QtQuick
import qs.Services.Hardware
// Own directory, explicitly — see BarContent.qml for why a URL-loaded file gets
// no siblings for free.
import qs.Surfaces.Bar.Modules

BarIndicator {
    id: root

    visible: Backlight.available
    // Two glyphs rather than a ladder of five: this is a continuous value, and
    // the number beside it is the precise half of the reading.
    icon: Backlight.percent >= 50 ? "sun" : "sun-dim"
    label: Backlight.percent + "%"

    // One policy step per notch. The facade coalesces the writes underneath, so
    // spinning the wheel ramps rather than queueing a subprocess per notch.
    interactive: true
    onStepped: direction => Backlight.step(direction)
}
