// The status cluster: network, bluetooth, volume and mic as one quiet icon
// group (#9, #36).
//
// One module and not four, because that is how it reads: four separate modules
// would take four module gaps (14px each) and spread the machine's condition
// across a third of the bar. Inside the cluster the gap is tighter than the
// bar's, so the group is one object with internal structure rather than a row
// of unrelated readouts.
//
// **Quiet** is the design rule, and it is what decides visibility. Only two of
// the four are always there: the network, because "am I online" is the question
// the cluster exists for, and the volume, because it is the one thing here the
// bar can change. Bluetooth appears only on a machine that has a radio, and the
// mic only when it is muted — a live mic is the normal state and says nothing,
// while "why can nobody hear me" is a question this glyph answers in one look.
//
// No labels, by the same rule. The words are decided (each service has a
// `label`) and the control centre will show them (#44); on the bar they would
// be four more strings competing with the clock.
import QtQuick
import qs.Core
import qs.Services.Media
import qs.Services.Networking
// Own directory, explicitly: `BarIndicator` lives next door, and a file
// Quickshell loads by URL gets no implicit sibling resolution — see the note in
// Workspaces.qml, and the longer one in BarContent.qml.
import qs.Surfaces.Bar.Modules

Row {
    id: root

    /// Tighter than `bar.moduleGap`: these four belong to each other, and the
    /// module gap around them is what says where the group ends.
    spacing: Theme.space2

    // **The shape carries the state; the colour is reserved for an alarm.**
    //
    // The first draft dimmed an idle or switched-off radio to text-muted, which
    // is the obvious way to make a cluster quiet — and it measures 2.98:1 over
    // the bar's worst-case composite (tools/capture-harness.sh --contrast,
    // brightest pin wallpaper, unblurred), under even WCAG's 3:1 floor for a
    // non-text mark. So it is gone: every glyph here is text-secondary, at
    // 4.93:1, and "off" is said by `wifi-off` and `bluetooth-off` being
    // different shapes — which they unmistakably are, and which reads at a
    // glance in a way a tint never did.
    //
    // The policies still answer in words ("off", "idle", "connected"). Nothing
    // on the bar spends them, and the control centre (#44) will: its rows sit
    // on an opaque surface where a dimmed row is both legible and meaningful.

    // Only where there is a NetworkManager to ask: on a machine running iwd or
    // systemd-networkd alone the facade is inert, and a permanent `wifi-off`
    // there would be the same furniture the bluetooth gate below avoids.
    BarIndicator {
        visible: Networking.available
        icon: Networking.icon
        anchors.verticalCenter: parent.verticalCenter

        interactive: true
        onClicked: SurfaceBus.barIndicator("wifi")
    }

    // Only on a machine with an adapter: a permanently crossed-out glyph on a
    // desktop is furniture nobody can act on.
    BarIndicator {
        visible: Bluetooth.present
        icon: Bluetooth.icon
        anchors.verticalCenter: parent.verticalCenter

        interactive: true
        onClicked: SurfaceBus.barIndicator("bluetooth")
    }

    // The one thing in the cluster the bar can change. Wheel to set, click to
    // open the sound panel.
    //
    // The click was mute until #184, and losing it is a deliberate trade rather
    // than an oversight: the request is that a glyph opens what it is about,
    // and four glyphs where three open a panel and one mutes is the pointer
    // lying about one of them. Mute is still the media key, and still the
    // volume row's own button in the control centre — which is the *root* of
    // the panel this opens and not inside it, so it is one press further than
    // it was, in exchange for the output picker and the per-application mixer
    // being a gesture closer instead of two.
    BarIndicator {
        id: volume

        visible: Audio.hasSink
        // `volume-x` is a crossed-out speaker and says muted on its own — the
        // same rule as the two radios above.
        icon: Audio.icon
        anchors.verticalCenter: parent.verticalCenter

        interactive: true
        onClicked: SurfaceBus.barIndicator("volume")
        onStepped: direction => Audio.stepVolume(direction)
    }

    // The mic is the cluster's one surprise, so it is the one thing here drawn
    // in the attention role: a muted mic is a state the machine is in *against*
    // the user's intention more often than with it, and it is the only glyph on
    // the bar whose absence is the good news.
    //
    // It is warm, which is the shell's rare colour (#8: one lamplight element
    // at a time). A low battery is the other claimant, and the two can be true
    // at once — accepted, because both are then genuinely asking for something,
    // and the alternative is a mute nobody notices.
    BarIndicator {
        visible: Audio.showSource
        icon: Audio.sourceIcon
        tint: Theme.accentWarm
        anchors.verticalCenter: parent.verticalCenter

        // The same panel as the volume glyph: one panel about the machine's
        // sound, which is the rule `panelForSlider` already applies inside the
        // control centre. Its click was `toggleSourceMute` and goes for the
        // reason given above the volume — but this one costs more than that
        // one, and the cost is worth stating rather than discovering. This
        // glyph is on screen *only* when the mic is muted, so its click was an
        // alarm's one-press fix; the sound panel holds outputs and streams and
        // no microphone at all, so unmuting from here is now the panel, then
        // back, then the mic row. #184 chose it anyway, for the consistency the
        // pointer promises across the cluster — if that trade reads wrong on a
        // real session, the fallback is this one indicator keeping
        // `Audio.toggleSourceMute()` — which under #185 costs it no pointer,
        // since every interactive indicator now shows one either way.
        interactive: true
        onClicked: SurfaceBus.barIndicator("mic")
    }
}
