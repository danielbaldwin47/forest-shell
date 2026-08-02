// The focused window's title (#9, #37).
//
// The left cluster's third module, after the workspace ridgeline, because the
// two answer one question together: which workspace you are on, and what is in
// front of you on it.
//
// Text only — no icon. The application's own icon is what a glyph here would
// have to be, and the tray is already a row of application icons on the same
// bar; a second one that changes as you alt-tab would read as another tray. The
// title is the information.
//
// Capped and elided at `bar.windowMaxWidth`, because a window title is
// arbitrary text from another application and an uncapped one walks across the
// bar (the #80 class of overflow). The front of a title is the part worth
// keeping, so it elides from the right.
import QtQuick
import qs.Core
import qs.Services.Compositor
// Own directory, explicitly — see BarContent.qml for why a URL-loaded file gets
// no siblings for free.
import qs.Surfaces.Bar.Modules

BarIndicator {
    id: root

    // An empty workspace has no focused window and the module goes with it
    // rather than showing a placeholder — the rule is in ActiveWindowPolicy.
    shown: Compositor.hasActiveWindow
    label: Compositor.activeWindow
    labelMaxWidth: Config.values.bar.windowMaxWidth
}
