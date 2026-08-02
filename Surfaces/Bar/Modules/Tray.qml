// The system tray (#9, #37): the one module whose contents the shell does not
// choose.
//
// Every other module on this bar draws a decision — which glyph, which colour,
// what to hide. Here an application registers an icon over DBus and the bar
// draws it, at whatever colour the application picked, and the only decisions
// left are the ones in Services/System/TrayPolicy.qml: everything registered is
// shown, and what a click means.
//
// **The icons are not tinted.** `Widgets/Icon.qml` recolours a Lucide glyph to
// a theme role, and doing that here would repaint every application's icon in
// text-secondary — a row of identical grey shapes. `IconImage` draws the
// application's own artwork, which is the same argument the launcher's spec
// makes for app icons (#11: "real app icons are never tinted amber"). It is
// also why this is the one module that cannot be judged from an offscreen
// capture: what is on screen is somebody else's PNG, and the theme has no say
// in it.
//
// A tray with nothing in it takes no width and no module gap, which follows
// from the Row being empty rather than from a rule.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Core
import qs.Services.System

Row {
    id: root

    /// The module contract (Surfaces/Bar/BarContent.qml): an empty tray is not
    /// a narrow tray, it is a module that is not there, and the bar is what
    /// takes its gap away.
    property bool shown: SystemTray.count > 0

    /// Tighter than `bar.moduleGap`, like the status cluster: the tray is one
    /// object with internal structure, and the module gap around it is what
    /// says where it ends.
    spacing: Theme.space2

    Repeater {
        // The upstream model object, handed over as-is. Mapping it into a JS
        // array would rebuild every delegate on every change — a new icon
        // arriving would restart the animation on all of them (#75).
        model: SystemTray.items

        delegate: Item {
            id: entry

            required property var modelData

            // The bar's icon size, from BarIndicator: 16px at a 32px bar.
            implicitWidth: 16
            implicitHeight: 16
            anchors.verticalCenter: parent.verticalCenter

            visible: SystemTray.policy.showing(SystemTray.status(entry.modelData))

            IconImage {
                anchors.fill: parent
                // A URL Quickshell's own image provider serves, whether the
                // application named a theme icon or handed over raw pixels.
                source: entry.modelData.icon
                // The tray fills up after the first frame and an icon is a file
                // read; nothing here is on the critical path.
                asynchronous: true
            }

            // The one status worth answering, drawn as a mark rather than a
            // tint — the icon underneath belongs to the application (#8: warm
            // is the shell's attention role, and this is the shell speaking
            // about somebody else's icon).
            Rectangle {
                width: 4
                height: 4
                radius: width / 2
                color: Theme.accentWarm
                visible: SystemTray.attentive(entry.modelData)
                anchors {
                    right: parent.right
                    top: parent.top
                    rightMargin: -1
                    topMargin: -1
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                // The facade decides what each button means and performs the
                // half that needs no window; a menu needs both a window and a
                // position, which only this file has.
                onClicked: mouse => {
                    if (mouse.button === Qt.MiddleButton) {
                        SystemTray.middlePress(entry.modelData);
                        return;
                    }
                    const action = mouse.button === Qt.RightButton
                        ? SystemTray.secondaryPress(entry.modelData)
                        : SystemTray.press(entry.modelData);
                    if (action === "menu")
                        itemMenu.open();
                }

                // Passed through: some items take the wheel for volume, most
                // ignore it. The direction and not the delta, for the reason
                // BarIndicator gives.
                onWheel: wheel => {
                    if (wheel.angleDelta.y !== 0)
                        SystemTray.scroll(entry.modelData, wheel.angleDelta.y > 0 ? 1 : -1);
                }
            }

            // The application's own menu, rendered by Quickshell from the
            // DBusMenu the item exports. Anchored to the icon, and opening away
            // from whichever edge the bar is on — a menu that dropped downwards
            // from a bottom bar would open off the screen.
            QsMenuAnchor {
                id: itemMenu

                menu: entry.modelData.menu
                anchor.item: entry
                anchor.edges: Config.values.bar.position === "top" ? Edges.Bottom : Edges.Top
                anchor.gravity: Config.values.bar.position === "top" ? Edges.Bottom : Edges.Top
            }
        }
    }
}
