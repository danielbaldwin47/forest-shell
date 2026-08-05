// The launcher button (#9, #37) — the bar's leftmost module.
//
// The launcher itself is #39 and does not exist yet, so this is a button that
// asks for a surface nobody has built. It asks through Core/SurfaceBus.qml,
// which answers with a line in the log until the surface registers itself —
// that is this ticket's acceptance criterion and the #81 lesson: a button that
// does nothing quietly is indistinguishable from one that is broken.
//
// The button stays on the bar in the meantime rather than hiding until its
// surface exists. A module that appeared partway through startup would be a bar
// that jumps, and the same button will be there either way — what changes is
// whether pressing it opens anything.
//
// `search` and not a logo: this shell has no mark, and the launcher is a search
// field with a list under it (#11). Super+Space is the other way in, and the
// one the shell-switch contract binds.
import QtQuick
import qs.Core
// Own directory, explicitly — see BarContent.qml for why a URL-loaded file gets
// no siblings for free.
import qs.Surfaces.Bar.Modules

BarIndicator {
    id: root

    icon: "search"

    interactive: true
    // `barClick` and not `toggle`, like every other door on this bar (#187):
    // what a bar click means depends on what is already open — the same button
    // opens, closes and swaps — and that table has one home
    // (Surfaces/Drawers/DrawerPolicy.qml). It reaches `toggle` from there.
    onClicked: SurfaceBus.barClick("launcher")
}
