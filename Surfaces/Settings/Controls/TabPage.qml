// The scaffold every settings tab is built in (#54): a scrolling column with a
// title, a sentence of orientation, and one reset that clears the whole
// section.
//
// Section reset is one call — `Config.reset("bar")` — because per-section and
// whole-file reset are the same operation at a different depth in the config
// engine (#21). It deletes the keys rather than writing today's defaults over
// them, so a tab reset here still lets a future change to a shipped default
// reach the user.
//
// The reset is offered only when the section has something in the file to
// clear, which also means an unbuilt tab never shows one.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Core
import qs.Widgets

Flickable {
    id: root

    required property string title

    /// The config section this tab owns, for the reset. Empty for About, which
    /// configures nothing.
    property string section: ""

    property string blurb: ""

    /// Rows and headers. Anything declared inside the page lands here — in its
    /// own column below the title, rather than in the same one, so that the
    /// header cannot end up ordered after the content it heads.
    default property alias content: body.data

    contentWidth: width
    contentHeight: column.implicitHeight + Theme.space7 * 2
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    // Whether anything in this section is currently written to the file. Reads
    // `Config.values` so that clearing the section makes the affordance go away
    // by itself.
    readonly property bool sectionModified: {
        const values = Config.values;
        if (root.section === "")
            return false;
        for (const path of store.leafPathsUnder(Config.schema.spec, root.section)) {
            const leaf = store.leafAt(Config.schema.spec, path);
            if (!store.equals(store.getPath(values, path), leaf.def))
                return true;
        }
        return false;
    }

    SpecStore { id: store }

    ColumnLayout {
        id: column

        x: Theme.space7
        y: Theme.space7
        width: root.width - Theme.space7 * 2
        spacing: Theme.space5

        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: Theme.space1
            spacing: Theme.space4

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.space2

                Text {
                    text: root.title
                    color: Theme.textPrimary
                    font.family: Theme.fontDisplay
                    font.weight: Theme.weightDisplay
                    font.pointSize: Theme.pt(24)
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.blurb !== ""
                    text: root.blurb
                    color: Theme.textSecondary
                    font.family: Theme.fontUi
                    font.pointSize: Theme.pt(12)
                    lineHeight: Theme.lineHeightBody
                    lineHeightMode: Text.ProportionalHeight
                    wrapMode: Text.WordWrap
                }
            }

            Rectangle {
                Layout.alignment: Qt.AlignTop
                visible: root.sectionModified
                implicitWidth: resetRow.implicitWidth + Theme.space3 * 2
                implicitHeight: 28
                radius: Theme.radiusSm
                color: resetHover.hovered ? Theme.surfaceOverlay : Theme.surfaceRaised
                border.width: Theme.hairline
                border.color: Theme.borderSubtle

                RowLayout {
                    id: resetRow

                    anchors.centerIn: parent
                    spacing: Theme.space2

                    Icon {
                        name: "rotate-ccw"
                        size: 13
                        color: Theme.textSecondary
                    }

                    Text {
                        text: "Reset tab"
                        color: Theme.textSecondary
                        font.family: Theme.fontUi
                        font.pointSize: Theme.pt(11.5)
                    }
                }

                HoverHandler { id: resetHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: Config.reset(root.section) }
            }
        }

        ColumnLayout {
            id: body

            Layout.fillWidth: true
            spacing: Theme.space5
        }
    }
}
