// A free-text setting (#54).
//
// Commits on Enter and on losing focus, never per keystroke: a config write per
// character would dispatch a half-typed value to every consumer, and the
// engine's debounce only protects the *file*, not the live shell.
//
// While the field has focus it shows what is being typed; the moment it does
// not, it shows what is configured. That is what makes an external edit to
// `settings.json` appear here without stealing a value out from under someone
// mid-word.
//
// `validate` marks a value the config engine would refuse before it is sent —
// the border goes ember and the commit is skipped. Without it a rejected write
// is silent, and the field reads as broken rather than as wrong.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core

Rectangle {
    id: root

    required property ConfigBinding binding

    /// `(text) -> bool`. Defaults to accepting anything; the engine's coercer is
    /// still the last word.
    property var validate: text => true

    property string placeholder: ""

    /// What committing actually does. Overridden by the one caller that needs a
    /// second meaning for the empty string: clearing a palette override is
    /// *removing* the key, not writing `""` into it.
    property var submit: text => root.binding.commit(text)

    readonly property string configured: root.binding.value === undefined
        ? "" : String(root.binding.value)

    readonly property bool valid: root.validate(field.text)

    implicitWidth: 132
    implicitHeight: 28
    radius: Theme.radiusSm
    color: Theme.bgSunken
    border.width: Theme.hairline
    border.color: !root.valid ? Theme.accentEmber
                              : (field.activeFocus ? Theme.borderStrong : Theme.borderSubtle)

    FogColorBehavior on border.color {}

    function commitText(): void {
        if (root.valid && field.text !== root.configured)
            root.submit(field.text);
    }

    TextInput {
        id: field

        anchors.fill: parent
        anchors.leftMargin: Theme.space3
        anchors.rightMargin: Theme.space3
        verticalAlignment: TextInput.AlignVCenter
        clip: true

        // Rebound rather than assigned: an external edit to the file has to
        // reach the field, and it may not do so while it is being typed into.
        text: root.configured
        onActiveFocusChanged: if (!activeFocus) {
            root.commitText();
            text = Qt.binding(() => root.configured);
        }
        onAccepted: root.commitText()

        color: Theme.textPrimary
        selectionColor: Theme.accentDeep
        selectedTextColor: Theme.textPrimary
        font.family: Theme.fontMono
        font.pointSize: Theme.pt(11.5)

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: field.text === ""
            text: root.placeholder
            color: Theme.textMuted
            font.family: field.font.family
            font.pointSize: field.font.pointSize
        }
    }
}
