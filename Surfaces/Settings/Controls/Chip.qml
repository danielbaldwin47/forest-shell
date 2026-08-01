// The settings window's one selectable pill (#54).
//
// Three controls are made of these — one-of-a-closed-list, many-of-a-closed-list
// and the per-app notification rule — and they differ in what selection *means*,
// not in what a selected chip looks like. So the look is here and the meaning
// stays with each control.
//
// Dumb, like the kit in Widgets/: it takes `selected` and reports `tapped`. It
// does read Theme, which is why it is not in Widgets/ — see the README next to
// this file.
//
// Focusable, and Space or Enter reports `tapped` exactly as a tap does (#77) —
// one signal, so a chip cannot mean two different things depending on how it was
// pressed. Which chip an arrow key moves to belongs to the control that owns the
// row (`SettingChoice`), not here: a chip does not know what its neighbours mean.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core

Rectangle {
    id: root

    required property string label

    property bool selected: false

    /// Present but not choosable — a theming mode whose service has not landed.
    /// Greyed and inert rather than hidden, so nothing appears from nowhere
    /// later.
    property bool available: true

    /// The label is the value for a tool name and prose for a mode, so the two
    /// type treatments live here rather than in three call sites.
    property bool mono: false

    signal tapped()

    implicitWidth: label_.implicitWidth + Theme.space3 * 2
    implicitHeight: 26
    radius: Theme.radiusSm
    opacity: root.available ? 1 : Theme.opacityInert

    color: root.selected ? Theme.accentDeep
                         : (hover.hovered && root.available ? Theme.surfaceOverlay
                                                            : Theme.surfaceRaised)
    border.width: Theme.hairline
    border.color: root.selected ? Theme.accentDeep : Theme.borderSubtle

    FogColorBehavior on color {}

    Text {
        id: label_

        anchors.centerIn: parent
        text: root.label
        color: root.selected ? Theme.textPrimary
                             : (root.mono ? Theme.textMuted : Theme.textSecondary)
        font.family: root.mono ? Theme.fontMono : Theme.fontUi
        font.pointSize: Theme.pt(root.mono ? 11 : 11.5)
        font.weight: root.selected && !root.mono ? Theme.weightMedium : Theme.weightRegular
    }

    HoverHandler {
        id: hover
        enabled: root.available
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        enabled: root.available
        onTapped: root.tapped()
    }

    // A chip that is present but not choosable is skipped by Tab as well as by
    // the pointer, rather than being a focus stop that does nothing.
    activeFocusOnTab: root.available

    Keys.onPressed: event => {
        if (keys.isActivate(event.key)) {
            root.tapped();
            event.accepted = true;
        }
    }

    KeyPolicy { id: keys }

    FocusRing {}
}
