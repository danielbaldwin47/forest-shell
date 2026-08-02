// A boolean setting (#54). Writes through its binding on every tap.
//
// The knob does not move until the config engine has taken the value: what is
// drawn is `binding.value`, never a local bool, so a write the engine refuses —
// an unreadable `settings.json` while the user is mid-edit — leaves the switch
// showing what is actually configured instead of a lie that survives until the
// next reload.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core

Rectangle {
    id: root

    required property ConfigBinding binding

    readonly property bool checked: root.binding.value === true

    implicitWidth: 40
    implicitHeight: 22
    radius: Theme.radiusFull

    color: root.checked ? Theme.accentDeep : Theme.bgSunken
    border.width: Theme.hairline
    border.color: root.checked ? Theme.accentDeep
                               : (hover.hovered ? Theme.borderStrong : Theme.borderSubtle)

    FogColorBehavior on color {}

    Rectangle {
        id: dot

        width: 16
        height: 16
        radius: Theme.radiusFull
        anchors.verticalCenter: parent.verticalCenter
        x: root.checked ? parent.width - width - 3 : 3
        color: root.checked ? Theme.textPrimary : Theme.textMuted

        // The knob travelling is movement, so reduced effects has it change
        // ends instead (#69). The colour under it still crossfades, which is
        // what keeps the control legible as a toggle rather than a jump.
        Behavior on x {
            enabled: Theme.animateTransforms
            NumberAnimation {
                duration: Theme.duration(Theme.motionFast)
                easing.type: Easing.Bezier
                easing.bezierCurve: Theme.fogEase
            }
        }

        FogColorBehavior on color {}
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: root.binding.commit(!root.checked) }

    // Space and Enter do what a tap does, through the same commit — so the
    // knob's refusal to move until the engine has taken the value is true of
    // the keyboard too (#77).
    activeFocusOnTab: true

    Keys.onPressed: event => {
        if (keys.isActivate(event.key)) {
            root.binding.commit(!root.checked);
            event.accepted = true;
        }
    }

    KeyPolicy { id: keys }

    FocusRing {}
}
