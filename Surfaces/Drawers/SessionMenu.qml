// The session drawer (#38) — the shared drawer window's first tenant.
//
// Five rows in a card: lock, log out, suspend, restart, shut down. The card is
// what makes the fog work at all — the launcher prototype measured that the
// pale mist cannot carry text directly, and the fix there and here is the same
// one: nothing sits on bare fog
// (.wayfinder/prototypes/launcher-clearing/findings.md).
//
// Centred rather than anchored. #27 gives each drawer its own anchor and lights
// the bar icon that opened it; the session menu has no bar icon to point a beak
// at, so it takes the launcher's placement — the middle of the screen, settling
// about its own centre.
//
// What each row does is SessionPolicy.qml, which imports nothing but QtQuick so
// `tests/` can check the table and the routing. What is here is the part that
// needs Quickshell: the `Process` that runs a command and the in-process call
// that locks.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Core
import qs.Widgets
import qs.Services.System

FocusScope {
    id: root

    /// Raised when the menu wants the drawer gone — after an action fires,
    /// because a session menu that stays up over the thing it just started is
    /// asking to be pressed twice.
    signal closeRequested(string reason)

    readonly property SessionPolicy policy: SessionPolicy {}
    readonly property var commands: Config.values.system.session.commands

    /// The row the keyboard is on. Opens on the lock, which is the one action
    /// that cannot lose work.
    property int selected: 0

    implicitWidth: card.implicitWidth
    implicitHeight: card.implicitHeight
    focus: true

    function fire(id: string): void {
        if (root.policy.routesToLock(id)) {
            Logger.log("session", root.policy.fired(id, ""));
            root.closeRequested("lock");
            // Out through logind rather than straight at the surface (#30, and
            // the note #47 left for #48): `loginctl lock-session` is what makes
            // logind's own `LockedHint` true, so anything else on the machine
            // that asks whether this session is locked gets the right answer.
            // The bridge falls back to `SessionLock.lock()` when the round trip
            // cannot work, so this is never a lock that quietly did not happen.
            LogindBridge.lockSession("session menu");
            return;
        }

        const command = root.policy.command(id, root.commands);
        if (command === "") {
            Logger.warn("session", root.policy.refused(id));
            return;
        }

        Logger.log("session", root.policy.fired(id, command));
        root.closeRequested(id);
        runner.exec(root.policy.argv(command));
    }

    // One process, reused. Handing a running `Process` a new command kills the
    // run in flight (Services/Compositor/Compositor.qml), which is a real risk
    // here only for the pair of actions nobody presses twice — but the drawer
    // closes on the first press, so the second one cannot happen at all.
    Process { id: runner }

    Keys.onUpPressed: root.selected = Math.max(0, root.selected - 1)
    Keys.onDownPressed: root.selected = Math.min(root.policy.actions.length - 1,
                                                 root.selected + 1)
    Keys.onReturnPressed: root.fire(root.policy.actions[root.selected].id)
    Keys.onEnterPressed: root.fire(root.policy.actions[root.selected].id)

    Rectangle {
        id: card

        implicitWidth: 260
        implicitHeight: rows.implicitHeight + Theme.space2 * 2

        color: Theme.surface
        radius: Theme.radiusLg
        border.width: Theme.hairline
        border.color: Theme.borderSubtle

        // Before the rows, so an action is hit-tested first and this only
        // catches what misses them (#193).
        PressCatcher {}

        ColumnLayout {
            id: rows

            anchors.fill: parent
            anchors.margins: Theme.space2
            spacing: 0

            Repeater {
                model: root.policy.actions

                Rectangle {
                    id: row

                    required property int index
                    required property var modelData

                    readonly property bool active: row.index === root.selected

                    Layout.fillWidth: true
                    implicitHeight: 36

                    radius: Theme.radiusMd
                    // Teal-for-active, the same encoding the ridgeline uses for
                    // the workspace you are on (#27).
                    color: row.active ? Theme.accentDeep : "transparent"

                    // A fill, so it fades — no gate, and the duration is the
                    // in-place step because nothing but this rectangle changes
                    // (Core/EffectsPolicy.qml).
                    Behavior on color {
                        ColorAnimation {
                            duration: Theme.duration(Theme.motionFast)
                            easing.type: Easing.Bezier
                            easing.bezierCurve: Theme.fogEase
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.space3
                        anchors.rightMargin: Theme.space3
                        spacing: Theme.space3

                        Icon {
                            name: row.modelData.icon
                            size: 16
                            color: row.active ? Theme.textPrimary : Theme.textSecondary
                        }

                        Text {
                            Layout.fillWidth: true
                            text: row.modelData.label
                            color: row.active ? Theme.textPrimary : Theme.textSecondary
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.pt(13)
                            font.weight: Theme.weightText
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.selected = row.index
                        onClicked: root.fire(row.modelData.id)
                    }
                }
            }
        }
    }
}
