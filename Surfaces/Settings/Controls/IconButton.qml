// A bare icon that does something (#54): reset a row, clear an override, nudge
// a module up the list, drop one out of it.
//
// No frame and no fill — these sit inside rows that already have a shape, and
// giving each one a button of its own would turn a settings tab into a field of
// buttons. The hit target is larger than the glyph for the obvious reason.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core
import qs.Widgets

Item {
    id: root

    required property string name

    property int size: 13
    property color color: Theme.textMuted

    /// Where it goes on hover. Ember for anything that removes something,
    /// accent for everything else.
    property color hoverColor: Theme.accentPrimary

    /// Possible right now — the up arrow on the first row is not. Kept in place
    /// and faded rather than removed, so the row does not reflow as it moves.
    property bool possible: true

    signal tapped()

    implicitWidth: 20
    implicitHeight: 20
    opacity: root.possible ? 1 : 0.25

    Icon {
        anchors.centerIn: parent
        name: root.name
        size: root.size
        color: hover.hovered ? root.hoverColor : root.color
    }

    HoverHandler {
        id: hover
        enabled: root.possible
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        enabled: root.possible
        onTapped: root.tapped()
    }

    // A button that cannot act — the up arrow on the first module — is not a
    // focus stop either (#77).
    activeFocusOnTab: root.possible

    Keys.onPressed: event => {
        if (root.possible && keys.isActivate(event.key)) {
            root.tapped();
            event.accepted = true;
        }
    }

    KeyPolicy { id: keys }

    FocusRing {}
}
