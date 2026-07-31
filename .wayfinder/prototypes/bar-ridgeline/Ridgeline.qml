// Workspace indicator as a ridgeline (board brief §6.3): a row of small forms
// whose HEIGHT and OPACITY encode state — active tallest and most opaque,
// neighbours progressively shorter and hazier, empties nearly gone.
//
// Hyprland destroys empty workspaces, so the row is a fixed slot range (1..N)
// unioned with whatever live workspaces exist beyond it.
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import "."

Item {
    id: root

    property int slots: 5
    readonly property int activeId: Vars.mock
        ? Vars.mockActive
        : (Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1)

    // [{ id, occupied }] — union of the fixed slots and live workspaces.
    readonly property var cells: {
        if (Vars.mock) {
            const out = [];
            for (let i = 1; i <= root.slots; i++)
                out.push({ id: i, occupied: Vars.mockOccupied.indexOf(i) !== -1 });
            return out;
        }
        const live = {};
        const ws = Hyprland.workspaces ? Hyprland.workspaces.values : [];
        for (let i = 0; i < ws.length; i++) {
            const w = ws[i];
            if (w.id < 1) continue;  // special/scratchpad workspaces are negative
            const obj = w.lastIpcObject;
            live[w.id] = obj && obj.windows !== undefined ? obj.windows > 0 : true;
        }
        const ids = [];
        for (let i = 1; i <= root.slots; i++) ids.push(i);
        for (const k in live) { const n = parseInt(k); if (ids.indexOf(n) === -1) ids.push(n); }
        ids.sort((a, b) => a - b);
        return ids.map(id => ({ id: id, occupied: live[id] === true }));
    }

    implicitWidth: row.implicitWidth
    implicitHeight: Math.max(Vars.ridgeActiveH + (Vars.ridgeShowNumber ? 11 : 0), 16)

    // The horizon the range sits on — the brief's "horizontal band" device.
    Rectangle {
        visible: Vars.ridgeHorizon
        anchors { left: row.left; right: row.right; bottom: row.bottom }
        height: 1
        color: Theme.borderSubtle
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Vars.ridgeGap

        Repeater {
            model: root.cells

            delegate: Item {
                id: cell
                required property var modelData

                readonly property bool isActive: modelData.id === root.activeId
                readonly property bool occupied: modelData.occupied
                readonly property int distance: Math.abs(modelData.id - root.activeId)

                // Height: active tallest; occupied fall away with distance;
                // empty sit at the vanishing height regardless.
                readonly property int h: isActive
                    ? Vars.ridgeActiveH
                    : occupied
                        ? Math.max(Vars.ridgeMinH, Vars.ridgeOccupiedH - Vars.ridgeFalloff * (distance - 1))
                        : Vars.ridgeEmptyH

                readonly property real haze: isActive
                    ? 1.0
                    : occupied
                        ? Math.max(0.15, Vars.ridgeOccupiedOpacity - Vars.ridgeOpacityFalloff * (distance - 1))
                        : Vars.ridgeEmptyOpacity

                readonly property color tint: isActive
                    ? (Vars.ridgeAmberActive ? Theme.accentWarm : Theme.accentPrimary)
                    : Theme.textSecondary

                width: Vars.ridgeUnitWidth
                height: root.height

                // --- strata: rounded-top bands, the ridge read as strata -----
                Rectangle {
                    visible: Vars.ridgeShape === "strata"
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: label.visible ? label.height : 0
                    width: Vars.ridgeUnitWidth
                    height: cell.h
                    color: cell.tint
                    opacity: cell.haze
                    topLeftRadius: 2
                    topRightRadius: 2

                    Behavior on height { NumberAnimation { duration: Theme.motionStandard; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.fogEase } }
                    Behavior on opacity { NumberAnimation { duration: Theme.motionStandard; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.fogEase } }
                    Behavior on color { ColorAnimation { duration: Theme.motionStandard } }
                }

                // --- peaks: literal mountain silhouettes ---------------------
                Shape {
                    visible: Vars.ridgeShape === "peaks"
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: label.visible ? label.height : 0
                    width: Vars.ridgeUnitWidth
                    height: cell.h
                    opacity: cell.haze
                    preferredRendererType: Shape.CurveRenderer

                    Behavior on height { NumberAnimation { duration: Theme.motionStandard; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.fogEase } }
                    Behavior on opacity { NumberAnimation { duration: Theme.motionStandard; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.fogEase } }

                    ShapePath {
                        fillColor: cell.tint
                        strokeWidth: -1
                        startX: 0; startY: cell.h
                        PathLine { x: cell.width / 2; y: 0 }
                        PathLine { x: cell.width; y: cell.h }
                        PathLine { x: 0; y: cell.h }
                    }
                }

                // --- pills: the conventional idiom, as a control -------------
                Rectangle {
                    visible: Vars.ridgeShape === "pills"
                    anchors.centerIn: parent
                    width: cell.isActive ? Vars.ridgeUnitWidth * 2 : Vars.ridgeUnitWidth * 0.7
                    height: Vars.ridgeUnitWidth * 0.7
                    radius: height / 2
                    color: cell.tint
                    opacity: cell.haze
                    Behavior on width { NumberAnimation { duration: Theme.motionStandard; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.fogEase } }
                }

                Text {
                    id: label
                    visible: Vars.ridgeShowNumber && cell.isActive
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    text: cell.modelData.id
                    color: cell.tint
                    font.family: Theme.fontUi
                    font.pixelSize: 9
                    font.weight: 500
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hyprland.dispatch("workspace " + cell.modelData.id)
                }
            }
        }
    }
}
