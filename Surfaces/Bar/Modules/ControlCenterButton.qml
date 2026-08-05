// The control-centre button (#9, #37) — the bar's rightmost module.
//
// Outermost on the right, past the battery, because it is the only module on
// that side that is a *door* rather than a reading: everything else in the
// right cluster reports the machine's condition, and this is where you go to
// change it. A target at the screen edge is also the easiest one to hit.
//
// The control centre is #44 and does not exist yet, so this asks
// Core/SurfaceBus.qml and gets a logged no-op until the surface registers —
// see LauncherButton.qml, which is the same button with a different name.
//
// `sliders-horizontal`, because that is what is behind it: three sliders and a
// toggle grid (#9). A gear would be the settings window, which is a different
// surface reached from inside the control centre.
import QtQuick
import qs.Core
// Own directory, explicitly — see BarContent.qml for why a URL-loaded file gets
// no siblings for free.
import qs.Surfaces.Bar.Modules

BarIndicator {
    id: root

    icon: "sliders-horizontal"

    interactive: true
    onClicked: SurfaceBus.barClick("controlcenter")
}
