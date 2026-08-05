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

    shown: Backlight.available
    // Two glyphs rather than a ladder of five: this is a continuous value, and
    // the number beside it is the precise half of the reading.
    icon: Backlight.percent >= 50 ? "sun" : "sun-dim"
    label: Backlight.percent + "%"

    // One policy step per notch. The facade coalesces the writes underneath, so
    // spinning the wheel ramps rather than queueing a subprocess per notch.
    interactive: true
    onStepped: direction => Backlight.step(direction)

    // A level on the bar is a level that has to be true (#186): sysfs does not
    // announce a change the shell did not make, so the facade re-reads on
    // demand and this is one of the demands.
    //
    // A read on arrival and not a subscription, which is the one place this
    // module differs from the system monitor next door. A bar module is never
    // *not* on screen, so a subscription here would be a timer that runs for
    // the life of the session — and that is measured, not assumed: with this
    // module in the bar and a 1 s poll behind it, tools/idle-budget.sh reports
    // 5.57 context switches/s against a budget of 5, up from 1.9. So the
    // polling subscription belongs to surfaces that come and go — the control
    // centre holds one while it is open — and the readout that is always there
    // reads when it appears, plus whenever the shell itself moves the panel.
    Component.onCompleted: Backlight.refreshIfStale()
}
