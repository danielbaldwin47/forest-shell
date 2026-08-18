// One shortcut, printed as keycaps.
//
// Shared by the command menu's rows and the shortcuts sheet's table, which is
// the whole reason it is a file: two places drawing `Ctrl+N` slightly
// differently is exactly the sort of drift nobody notices until both are on
// screen at once, and the shortcuts sheet exists to put them on screen at once.
//
// It draws and decides nothing: what a shortcut string breaks into is
// `KeyNavPolicy.keyCaps`, at the first seam, where `/` meaning "or" and `+`
// meaning "at the same time" are checked rather than assumed. This file turns
// that list into rectangles.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core

Row {
    id: keycaps

    /// `KeyNavPolicy.keyCaps(...)` output — `[{kind: "key"|"sep", text}]`.
    property var caps: []

    /// The cap face, one step **up** from the card it sits on
    /// (`surfaceOverlay` over `surfaceRaised`).
    ///
    /// It used to be `bgSunken`, on a recessed-keycap metaphor. Measured, that
    /// metaphor cost the thing badges are for: near-black on a dark card, a cap
    /// reads as a hole, and on a *selected* row — whose band is lighter than the
    /// card — the same hole reads as an inverted chip, so the one row the eye is
    /// already on gains a second, louder mark. A face one step lighter is the
    /// same cap on every row: 1.30:1 on the card, 1.45:1 the other way under the
    /// selection band, and the glyph clears 6.6:1 on it either way.
    property color faceColor: Theme.surfaceOverlay
    property color textColor: Theme.textSecondary

    spacing: Theme.space1

    Repeater {
        model: keycaps.caps

        delegate: Item {
            id: cap

            required property var modelData

            readonly property bool isKey: !!cap.modelData && cap.modelData.kind === "key"

            /// The chord mark. Narrower and quieter than the `/` between two
            /// alternatives, because it binds its neighbours together where the
            /// slash holds them apart — same reason it is set tighter than the
            /// row's own spacing.
            readonly property bool isChord: !cap.isKey
                                          && !!cap.modelData
                                          && String(cap.modelData.text) === "+"

            // 22 wide minimum so `D` and `W` are the same size as each other
            // rather than the width of their own glyph — a row of badges that
            // jitters by letter reads as a bug in the type.
            implicitWidth: cap.isKey
                         ? Math.max(22, glyph.implicitWidth + Theme.space2 * 2)
                         : cap.isChord ? glyph.implicitWidth - Theme.space1
                                       : glyph.implicitWidth
            implicitHeight: 20

            Rectangle {
                anchors.fill: parent
                visible: cap.isKey
                radius: 4
                color: keycaps.faceColor
                // `borderStrong`, not `borderSubtle`: the face is now only
                // 1.30:1 on the card, so the edge is what makes it a cap rather
                // than a smudge, and on the selection band it is the only thing
                // that does.
                border.width: 1
                border.color: Theme.borderStrong
            }

            Text {
                id: glyph

                anchors.centerIn: parent
                text: cap.modelData ? String(cap.modelData.text) : ""
                color: keycaps.textColor
                // Mono on the cap, the UI face on the slash between two of
                // them: the slash is prose, not a key.
                font.family: cap.isKey ? Theme.fontMono : Theme.fontUi
                font.pointSize: Theme.pt(cap.isChord ? 9.5 : 10.5)
                font.weight: Theme.weightMedium
                opacity: cap.isKey ? 1 : (cap.isChord ? 0.55 : 0.7)
            }
        }
    }
}
