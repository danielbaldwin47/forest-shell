// A paragraph under a section heading (#54) — where a number came from, why a
// range stops where it does, what a mode will do once it works.
//
// The settings window carries more prose than any other surface in the shell,
// on purpose: most of these values were settled by measurement, and a slider
// with the reason next to it is the difference between a knob and a decision.
// One type so the seven of them are one type treatment.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Core

Text {
    required property string note

    Layout.fillWidth: true
    text: note
    color: Theme.textMuted
    font.family: Theme.fontUi
    font.pointSize: Theme.pt(11.5)
    lineHeight: Theme.lineHeightBody
    lineHeightMode: Text.ProportionalHeight
    wrapMode: Text.WordWrap
}
