// The chrome every control-centre detail view wears (#45): a back arrow, a
// title, a note, and a scrolling body under them.
//
// Five panels share it so that the way *out* is in the same place in all five.
// That is the whole argument for a shared component rather than five headers:
// the navigation is one level deep with no breadcrumb, so the back arrow is the
// only affordance carrying it — and an affordance that moves between screens is
// one people stop trusting.
//
// The body scrolls and the panel does not grow: the control centre is already
// sized to the screen it hangs on (`maxPanelHeight`), and a detail view is
// allowed to be longer than that — a scan can turn up thirty access points.
// What must not happen is the card changing size as rows arrive, which would
// make it twitch under the pointer every time a network appeared. So the body
// takes the height it is given and scrolls inside it.
//
// ## Why the chrome is assigned to `data` explicitly
//
// Because `default property alias body` below would otherwise swallow it. A
// default property declared on a root object applies to children declared in
// *this* file too, not only to what a caller writes — so the title bar and the
// `Flickable` would both be reparented into the `Column` inside the `Flickable`,
// which is the `Flickable` being made a child of itself. An explicit `data`
// assignment is what keeps the file's own children out of the alias.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Core
import qs.Widgets
// The navigation's own decisions live one directory up, beside the grid that
// opens these panels — a title that disagreed with the name the navigation
// knows is the one inconsistency the user can see.
import qs.Surfaces.Drawers

ColumnLayout {
    id: panel

    /// The panel's name, as DrillInPolicy knows it — the title and the glyph
    /// come off it rather than being passed separately, so a panel cannot be
    /// titled one thing and navigated as another.
    required property string name

    // Held as its own property rather than declared inline — see Core/Config.qml.
    readonly property DrillInPolicy policy: DrillInPolicy {}

    /// A line under the title when there is something to say — the empty state,
    /// a failure, what the panel is waiting for. Empty means absent, not blank:
    /// a reserved line that is usually empty is a gap the eye has to learn to
    /// ignore.
    property string note: ""

    /// Whether that note is a problem rather than an aside. Only the colour
    /// changes: a failure that shouted would be louder than the thing it is
    /// about.
    property bool noteIsProblem: false

    /// Something is happening that the user is waiting for — a scan, a join.
    /// Drawn as a word beside the title and never as a spinner: a spinner is a
    /// repaint every frame for as long as it is visible, against an idle budget
    /// of one wakeup a minute (#22 §5).
    property string activity: ""

    /// Where a panel's rows go.
    default property alias body: bodyColumn.data

    /// Back. Raised rather than handled here, because the panel does not own
    /// the navigation — Surfaces/Drawers/ControlCenterActions.qml does, and
    /// that is also where the IPC door lands.
    signal backRequested

    spacing: Theme.space2

    data: [
        // --- the title bar ---------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space2

            // The one control every panel has in the same place.
            Rectangle {
                implicitWidth: 28
                implicitHeight: 28
                radius: width / 2
                color: backHover.hovered ? Theme.surfaceOverlay : "transparent"

                Behavior on color {
                    ColorAnimation {
                        duration: Theme.duration(Theme.motionFast)
                        easing.type: Easing.Bezier
                        easing.bezierCurve: Theme.fogEase
                    }
                }

                HoverHandler {
                    id: backHover
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    onTapped: panel.backRequested()
                }

                Icon {
                    anchors.centerIn: parent
                    name: "chevron-left"
                    size: 18
                    color: backHover.hovered ? Theme.accentPrimary : Theme.textSecondary
                }
            }

            Icon {
                Layout.alignment: Qt.AlignVCenter
                name: panel.policy.icon(panel.name)
                size: 16
                color: Theme.textSecondary
            }

            Text {
                Layout.fillWidth: true
                text: panel.policy.title(panel.name)
                color: Theme.textPrimary
                elide: Text.ElideRight
                font.family: Theme.fontUi
                font.pointSize: Theme.pt(12)
                font.weight: Theme.weightMedium
            }

            Text {
                visible: panel.activity !== ""
                text: panel.activity
                color: Theme.textMuted
                font.family: Theme.fontUi
                font.pointSize: Theme.pt(10.5)
            }
        },

        // --- the note --------------------------------------------------------
        Text {
            Layout.fillWidth: true
            visible: panel.note !== ""
            text: panel.note
            // `accentEmber` is the shell's "this went wrong" (#8); an aside
            // keeps the muted role, which is the pairing the bottom strip uses
            // and the one seam 3 has already measured against the panel fill.
            color: panel.noteIsProblem ? Theme.accentEmber : Theme.textMuted
            wrapMode: Text.Wrap
            font.family: Theme.fontUi
            font.pointSize: Theme.pt(10.5)
        },

        // --- the body --------------------------------------------------------
        Flickable {
            id: scroll

            Layout.fillWidth: true
            Layout.fillHeight: true
            // Sized from the content and then bounded by what the layout gives
            // it: a short list draws short, a long one scrolls rather than
            // stretching the card it is in.
            Layout.preferredHeight: bodyColumn.implicitHeight

            contentWidth: width
            contentHeight: bodyColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: bodyColumn

                width: scroll.width
                spacing: Theme.space1
            }
        }
    ]
}
