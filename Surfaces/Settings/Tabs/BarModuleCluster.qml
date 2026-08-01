// One cluster of the bar's module registry (#54, for #35).
//
// The registry is three ordered lists — left, centre, right — and membership is
// the enable flag: a module that is in no cluster is off. That is why there is
// no separate switch per module, and why removing one here is not destructive:
// the id goes back to the pool below and can be dropped into any cluster.
//
// Reordering is buttons rather than drag-and-drop. The list is short, the order
// is a rarely-touched setting, and a drag target inside a scrolling settings
// page fights the scroll — arrows say what they do and cost nothing to hit.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Core
import qs.Widgets
import qs.Surfaces.Settings.Controls

ColumnLayout {
    id: root

    /// `left`, `center` or `right`.
    required property string cluster

    required property string label

    /// Module ids that are in no cluster at all — the pool this one can take
    /// from. Computed by the tab, because it spans all three lists.
    required property var pool

    readonly property var modules: Array.isArray(binding.value) ? binding.value : []

    Layout.fillWidth: true
    spacing: Theme.space2

    ConfigBinding {
        id: binding
        path: "bar.modules." + root.cluster
    }

    function move(index: int, delta: int): void {
        const next = root.modules.slice();
        const target = index + delta;
        if (target < 0 || target >= next.length)
            return;
        const moved = next[index];
        next[index] = next[target];
        next[target] = moved;
        binding.commit(next);
    }

    function remove(index: int): void {
        const next = root.modules.slice();
        next.splice(index, 1);
        binding.commit(next);
    }

    function add(id: string): void {
        binding.commit(root.modules.concat([id]));
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space3

        Text {
            text: root.label
            color: Theme.textSecondary
            font.family: Theme.fontUi
            font.pointSize: Theme.pt(12)
            font.weight: Theme.weightMedium
        }

        Text {
            Layout.fillWidth: true
            text: root.modules.length === 0 ? "empty" : ""
            color: Theme.textMuted
            font.family: Theme.fontUi
            font.pointSize: Theme.pt(11.5)
        }
    }

    Repeater {
        model: root.modules

        Rectangle {
            id: moduleRow

            required property string modelData
            required property int index

            Layout.fillWidth: true
            implicitHeight: 32
            radius: Theme.radiusSm
            color: rowHover.hovered ? Theme.surfaceOverlay : Theme.surfaceRaised

            HoverHandler { id: rowHover }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.space3
                anchors.rightMargin: Theme.space2
                spacing: Theme.space3

                Icon {
                    name: "grip-vertical"
                    size: 13
                    color: Theme.textMuted
                }

                Text {
                    Layout.fillWidth: true
                    text: moduleRow.modelData
                    color: Theme.textPrimary
                    font.family: Theme.fontMono
                    font.pointSize: Theme.pt(11.5)
                    elide: Text.ElideRight
                }

                Repeater {
                    model: [
                        { icon: "arrow-up", delta: -1 },
                        { icon: "arrow-down", delta: 1 }
                    ]

                    Item {
                        id: nudge

                        required property var modelData

                        readonly property bool possible: {
                            const target = moduleRow.index + nudge.modelData.delta;
                            return target >= 0 && target < root.modules.length;
                        }

                        implicitWidth: 22
                        implicitHeight: 22
                        opacity: nudge.possible ? 1 : 0.25

                        Icon {
                            anchors.centerIn: parent
                            name: nudge.modelData.icon
                            size: 13
                            color: nudgeHover.hovered ? Theme.accentPrimary : Theme.textSecondary
                        }

                        HoverHandler {
                            id: nudgeHover
                            enabled: nudge.possible
                            cursorShape: Qt.PointingHandCursor
                        }

                        TapHandler {
                            enabled: nudge.possible
                            onTapped: root.move(moduleRow.index, nudge.modelData.delta)
                        }
                    }
                }

                Item {
                    implicitWidth: 22
                    implicitHeight: 22

                    Icon {
                        anchors.centerIn: parent
                        name: "x"
                        size: 13
                        color: removeHover.hovered ? Theme.accentEmber : Theme.textMuted
                    }

                    HoverHandler { id: removeHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.remove(moduleRow.index) }
                }
            }
        }
    }

    // The pool. Present on every cluster rather than once per tab, so adding a
    // module is one tap next to where it will land.
    Flow {
        Layout.fillWidth: true
        Layout.topMargin: Theme.space1
        spacing: Theme.space1
        visible: root.pool.length > 0

        Repeater {
            model: root.pool

            Rectangle {
                id: poolChip

                required property string modelData

                implicitWidth: poolRow.implicitWidth + Theme.space3 * 2
                implicitHeight: 24
                radius: Theme.radiusSm
                color: poolHover.hovered ? Theme.surfaceOverlay : "transparent"
                border.width: Theme.hairline
                border.color: Theme.borderSubtle

                RowLayout {
                    id: poolRow

                    anchors.centerIn: parent
                    spacing: Theme.space1

                    Icon {
                        name: "plus"
                        size: 11
                        color: Theme.textMuted
                    }

                    Text {
                        text: poolChip.modelData
                        color: Theme.textMuted
                        font.family: Theme.fontMono
                        font.pointSize: Theme.pt(10.5)
                    }
                }

                HoverHandler { id: poolHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.add(poolChip.modelData) }
            }
        }
    }
}
