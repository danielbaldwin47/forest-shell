// A config key that is an ordered list of names, edited in place (#54, #55).
//
// Three keys have this exact shape, which is what moved this file up from
// `Tabs/` where it was `BarModuleCluster.qml`: the bar's three module clusters,
// the dashboard's cards, and the control centre's tile and slider grids. In all
// of them **membership is the enable flag** — a name that is in no list is off
// — which is why there is no separate switch per entry and why removing one is
// not destructive: the id goes back to the pool below and can be dropped in
// again.
//
// Reordering is buttons rather than drag-and-drop. The lists are short, the
// order is a rarely-touched setting, and a drag target inside a scrolling
// settings page fights the scroll — arrows say what they do and cost nothing to
// hit.
//
// This is not in a `SettingRow` slot, so it obeys the #80 rule itself: the text
// column is the one on `Layout.fillWidth` and it elides, which keeps the arrows
// and the remove button on screen at any window width.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Core
import qs.Widgets

ColumnLayout {
    id: root

    /// The config key holding the list.
    required property string path

    /// What the list is called, above it. Empty draws no heading, which is what
    /// a tab with one list of its kind wants.
    property string label: ""

    /// Names that are not in *any* list of this kind — the pool this one can
    /// take from. Computed by the tab, because for the bar it spans three keys
    /// and only the tab can see all of them.
    required property var pool

    /// id → what to call it on screen. The identity by default, which is right
    /// for the bar's modules: those ids *are* the vocabulary the user
    /// hand-edits. A dashboard card has a name of its own and passes one.
    property var labelFor: id => id

    /// Whether entries are drawn in the mono face. True where the text on
    /// screen is the literal id in the file, false where it is a title.
    property bool mono: true

    /// What the heading says when the list is empty. A list a user emptied on
    /// purpose is a legal state, and silence would read as a rendering bug.
    property string emptyNote: "empty"

    readonly property var entries: Array.isArray(binding.value) ? binding.value : []

    Layout.fillWidth: true
    spacing: Theme.space2

    ConfigBinding {
        id: binding
        path: root.path
    }

    function move(index: int, delta: int): void {
        const next = root.entries.slice();
        const target = index + delta;
        if (target < 0 || target >= next.length)
            return;
        const moved = next[index];
        next[index] = next[target];
        next[target] = moved;
        binding.commit(next);
    }

    function remove(index: int): void {
        const next = root.entries.slice();
        next.splice(index, 1);
        binding.commit(next);
    }

    function add(id: string): void {
        binding.commit(root.entries.concat([id]));
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space3
        visible: root.label !== "" || root.entries.length === 0

        Text {
            text: root.label
            visible: root.label !== ""
            color: Theme.textSecondary
            font.family: Theme.fontUi
            font.pointSize: Theme.pt(12)
            font.weight: Theme.weightMedium
        }

        Text {
            Layout.fillWidth: true
            text: root.entries.length === 0 ? root.emptyNote : ""
            color: Theme.textMuted
            font.family: Theme.fontUi
            font.pointSize: Theme.pt(11.5)
            elide: Text.ElideRight
        }
    }

    Repeater {
        model: root.entries

        Rectangle {
            id: entryRow

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
                    text: root.labelFor(entryRow.modelData)
                    color: Theme.textPrimary
                    font.family: root.mono ? Theme.fontMono : Theme.fontUi
                    font.pointSize: Theme.pt(11.5)
                    elide: Text.ElideRight
                }

                Repeater {
                    model: [
                        { icon: "arrow-up", delta: -1 },
                        { icon: "arrow-down", delta: 1 }
                    ]

                    IconButton {
                        required property var modelData

                        name: modelData.icon
                        color: Theme.textSecondary
                        possible: {
                            const target = entryRow.index + modelData.delta;
                            return target >= 0 && target < root.entries.length;
                        }
                        onTapped: root.move(entryRow.index, modelData.delta)
                    }
                }

                IconButton {
                    name: "x"
                    hoverColor: Theme.accentEmber
                    onTapped: root.remove(entryRow.index)
                }
            }
        }
    }

    // The pool. Drawn under each list rather than once per tab, so adding an
    // entry is one tap next to where it will land.
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
                        text: root.labelFor(poolChip.modelData)
                        color: Theme.textMuted
                        font.family: root.mono ? Theme.fontMono : Theme.fontUi
                        font.pointSize: Theme.pt(10.5)
                    }
                }

                HoverHandler { id: poolHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.add(poolChip.modelData) }
            }
        }
    }
}
