// The theme list on the Appearance tab (#56): save the skin, apply one, undo,
// delete.
//
// In `Tabs/` and not `Controls/` for the reason the README next to it gives —
// this is one tab's editor for one thing, and nothing else in the window has
// this shape. Every decision it draws is in Core/ThemePolicy.qml; every file it
// touches is Core/Themes.qml's. What is left here is the list, the name field
// and the four presses.
//
// The two built-in rows are not files and are drawn as what they are: "Forest
// (default)" applies the shipped look by *deleting* the flagged keys, and
// "Previous settings" is the undo slot, snapshotted before every apply. Both go
// through the same verb as a saved theme, because to the user they are the same
// act.
//
// This is not inside a `SettingRow` slot, so it obeys the #80 rule itself: the
// name is the column on `Layout.fillWidth` and it elides, so the buttons beside
// it stay on screen at any window width.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Core
import qs.Widgets
import qs.Surfaces.Settings.Controls

ColumnLayout {
    id: root

    /// The rows, built-ins included, in the order they are drawn. The shipped
    /// look first because it is where everyone starts and what a lost user
    /// wants; the undo slot last because it is the only row whose meaning
    /// depends on what just happened.
    readonly property var rows: {
        const out = [{
            name: Themes.policy.defaultName,
            icon: "leaf",
            // The shipped look is a row like any other: it is what the shell is
            // wearing when nothing else has been applied, and a knob moved
            // afterwards drifts *from* it exactly as it would from a preset.
            applied: Themes.applied === Themes.policy.defaultName,
            drifted: Themes.applied === Themes.policy.defaultName && Themes.drifted,
            removable: false,
            note: "The shipped forest palette — applying it clears every themed key."
        }];

        for (const row of Themes.entries)
            out.push({
                name: row.name,
                icon: "palette",
                applied: row.applied,
                drifted: row.drifted,
                removable: true,
                note: ""
            });

        if (Themes.canUndo)
            out.push({
                name: Themes.policy.undoName,
                icon: "undo-2",
                applied: false,
                drifted: false,
                removable: false,
                note: "The skin as it was just before the last apply."
            });
        return out;
    }

    /// What is typed into the name field. Held here rather than read off the
    /// field so the Save button and the refusal line see the same string.
    property string typedName: ""

    readonly property string refusal: root.typedName.trim() === ""
        ? "" : Themes.policy.refusal(root.typedName)

    readonly property bool exists:
        Themes.entries.some(row => row.name === root.typedName.trim())

    Layout.fillWidth: true
    spacing: Theme.space2

    Repeater {
        model: root.rows

        Rectangle {
            id: themeRow

            required property var modelData

            readonly property bool ticked:
                themeRow.modelData.applied && !themeRow.modelData.drifted

            Layout.fillWidth: true
            implicitHeight: rowBody.implicitHeight + Theme.space3 * 2
            radius: Theme.radiusSm
            color: rowHover.hovered ? Theme.surfaceOverlay : Theme.surfaceRaised
            border.width: Theme.hairline
            border.color: themeRow.ticked ? Theme.accentDeep : Theme.borderSubtle

            FogColorBehavior on border.color {}

            HoverHandler { id: rowHover }

            RowLayout {
                id: rowBody

                anchors.fill: parent
                anchors.leftMargin: Theme.space3
                anchors.rightMargin: Theme.space2
                anchors.topMargin: Theme.space3
                anchors.bottomMargin: Theme.space3
                spacing: Theme.space3

                Icon {
                    Layout.alignment: Qt.AlignTop
                    name: themeRow.modelData.icon
                    size: 14
                    color: themeRow.ticked ? Theme.accentPrimary : Theme.textMuted
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space1

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space2

                        Text {
                            Layout.fillWidth: true
                            text: themeRow.modelData.name
                            color: Theme.textPrimary
                            font.family: Theme.fontUi
                            font.pointSize: Theme.pt(11.5)
                            font.weight: themeRow.ticked ? Theme.weightMedium
                                                         : Theme.weightRegular
                            elide: Text.ElideRight
                        }

                        // The honest half of the breadcrumb: this theme was
                        // applied, and the settings have moved since. Applying
                        // is a copy and never a link, so a knob nudged
                        // afterwards is not part of the theme (#56).
                        Text {
                            visible: themeRow.modelData.drifted
                            text: "modified since"
                            color: Theme.textMuted
                            font.family: Theme.fontUi
                            font.pointSize: Theme.pt(11)
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: themeRow.modelData.note !== ""
                        text: themeRow.modelData.note
                        color: Theme.textMuted
                        font.family: Theme.fontUi
                        font.pointSize: Theme.pt(11)
                        wrapMode: Text.WordWrap
                    }
                }

                Chip {
                    Layout.alignment: Qt.AlignTop
                    label: "Apply"
                    onTapped: Themes.apply(themeRow.modelData.name)
                }

                IconButton {
                    Layout.alignment: Qt.AlignTop
                    name: "trash-2"
                    hoverColor: Theme.accentEmber
                    visible: themeRow.modelData.removable
                    onTapped: Themes.remove(themeRow.modelData.name)
                }
            }
        }
    }

    // --- save as --------------------------------------------------------------

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Theme.space2
        spacing: Theme.space3

        Text {
            text: "Save the current skin as"
            color: Theme.textSecondary
            font.family: Theme.fontUi
            font.pointSize: Theme.pt(11.5)
        }

        // The one free-text field in the window that is not a config key, so it
        // is here rather than a `SettingText`: that control's whole contract is
        // that it is a binding on a path (Controls/ConfigBinding.qml), and a
        // theme name is not in the file at all.
        Rectangle {
            id: nameField

            Layout.fillWidth: true
            implicitHeight: 28
            radius: Theme.radiusSm
            color: Theme.bgSunken
            border.width: Theme.hairline
            border.color: root.refusal !== "" ? Theme.accentEmber
                                              : (field.activeFocus ? Theme.borderStrong
                                                                   : Theme.borderSubtle)

            FogColorBehavior on border.color {}

            TextInput {
                id: field

                activeFocusOnTab: true
                anchors.fill: parent
                anchors.leftMargin: Theme.space3
                anchors.rightMargin: Theme.space3
                verticalAlignment: TextInput.AlignVCenter
                clip: true

                onTextChanged: root.typedName = field.text
                onAccepted: root.saveTyped()

                color: Theme.textPrimary
                selectionColor: Theme.accentDeep
                selectedTextColor: Theme.textPrimary
                font.family: Theme.fontUi
                font.pointSize: Theme.pt(11.5)

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: field.text === ""
                    text: "a name"
                    color: Theme.textMuted
                    font.family: field.font.family
                    font.pointSize: field.font.pointSize
                }
            }
        }

        Chip {
            // A name already in the list is an overwrite, and says so before it
            // is pressed rather than after.
            label: root.exists ? "Overwrite" : "Save"
            available: root.typedName.trim() !== "" && root.refusal === ""
            onTapped: root.saveTyped()
        }
    }

    // Why a name will not be taken, next to the field that will not take it. The
    // config engine's refusals are warnings on stderr; this one is the user's,
    // so it is on screen (#78).
    Text {
        Layout.fillWidth: true
        visible: root.refusal !== ""
        text: root.refusal
        color: Theme.accentEmber
        font.family: Theme.fontUi
        font.pointSize: Theme.pt(11)
        wrapMode: Text.WordWrap
    }

    function saveTyped(): void {
        if (!Themes.save(root.typedName))
            return;
        field.text = "";
        root.typedName = "";
    }
}
