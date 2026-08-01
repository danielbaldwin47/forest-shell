// One app's notification rule (#54, for #43).
//
// Three states, and the first of them is the absence of a rule: `normal` is what
// every app does, so choosing it *removes* the key rather than writing
// `"normal"` into the file. That keeps `notifications.appRules` a list of the
// apps the user has actually done something about, which is what makes it worth
// reading by hand — and it is why this row is not a plain `SettingChoice`, which
// would have nothing to highlight when the value is absent.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Core
import qs.Widgets
import qs.Surfaces.Settings.Controls

RowLayout {
    id: root

    required property string app

    /// Emitted for an app that has no rule and is not known to the notification
    /// service either — a row that exists only because it was typed in. Nothing
    /// to reset, so the row offers removal instead.
    signal dismissed()

    property bool dismissable: false

    readonly property string rule: root.binding.value === undefined
        ? "normal" : String(root.binding.value)

    readonly property ConfigBinding binding: ConfigBinding {
        path: "notifications.appRules"
        knob: root.app
    }

    Layout.fillWidth: true
    spacing: Theme.space4

    Icon {
        name: root.rule === "blocked" ? "circle-slash"
                                      : (root.rule === "silent" ? "bell-off" : "bell")
        size: 15
        color: root.rule === "blocked" ? Theme.accentEmber
                                       : (root.rule === "silent" ? Theme.textMuted
                                                                 : Theme.textSecondary)
    }

    Text {
        Layout.fillWidth: true
        text: root.app
        color: Theme.textPrimary
        font.family: Theme.fontMono
        font.pointSize: Theme.pt(11.5)
        elide: Text.ElideMiddle
    }

    RowLayout {
        spacing: Theme.space1

        Repeater {
            model: [
                { value: "normal", label: "Normal" },
                { value: "silent", label: "Silent" },
                { value: "blocked", label: "Blocked" }
            ]

            Chip {
                required property var modelData

                label: modelData.label
                selected: root.rule === modelData.value
                onTapped: modelData.value === "normal"
                    ? root.binding.removeKnob()
                    : root.binding.commit(modelData.value)
            }
        }
    }

    IconButton {
        name: "x"
        hoverColor: Theme.accentEmber
        visible: root.dismissable && root.rule === "normal"
        onTapped: root.dismissed()
    }
}
