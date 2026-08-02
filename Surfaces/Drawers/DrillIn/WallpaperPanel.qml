// The wallpaper picker (#45): a grid of thumbnails, and a press that persists.
//
// The one panel of the five that is pictures rather than rows, because the thing
// being chosen *is* a picture and a list of filenames is a list you have to open
// each of to use.
//
// ## The decode budget, one directory at a time
//
// Surfaces/Background/Wallpaper.qml measures a full-size decode of a 5824×3264
// JPEG at ~470 ms, which is why the desktop's own wallpaper is bounded with
// `sourceSize`. A grid of them is that cost times the size of somebody's
// wallpaper folder, so every thumbnail here is bounded to its own cell — the
// image loaded is a few tens of kilobytes of pixels rather than the file — and
// loaded asynchronously, which the desktop's cannot be (a wallpaper arriving a
// frame late is a visible flash of empty desktop; a thumbnail arriving a frame
// late is a thumbnail).
//
// It is also why the grid's model is republished only when the folder's
// *contents* change (#75, Surfaces/Background/Wallpapers.qml): a rebuilt
// delegate here is a whole folder decoded again, which is by some distance the
// most expensive rebuild in the shell.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core
import qs.Widgets
import qs.Surfaces.Background
import qs.Surfaces.Drawers

DrillInPanel {
    id: panel

    name: "wallpaper"

    // Names the folder it looked in, always: a picker that says "no wallpapers"
    // and not *where* is one nobody can fix.
    note: Wallpapers.empty ? Wallpapers.policy.emptyLine(Wallpapers.folder)
                           : Wallpapers.folder

    onBackRequested: ControlCenterActions.back("back")

    Grid {
        id: grid

        width: parent ? parent.width : 0
        columns: 2
        spacing: Theme.space2

        readonly property real cellWidth: (grid.width - grid.spacing) / grid.columns

        Repeater {
            model: Wallpapers.entries

            Item {
                id: cell

                required property var modelData

                width: grid.cellWidth
                // 16:9, which is the shape of the thing it is a picture of.
                height: Math.round(grid.cellWidth * 9 / 16) + nameLabel.implicitHeight
                        + Theme.space1

                HoverHandler {
                    id: cellHover
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    onTapped: ControlCenterActions.wallpaper(cell.modelData.path)
                }

                Rectangle {
                    id: frame

                    width: parent.width
                    height: Math.round(grid.cellWidth * 9 / 16)
                    radius: Theme.radiusMd
                    color: Theme.surfaceRaised
                    clip: true
                    // The current wallpaper carries a ring rather than a tick
                    // over the image: a glyph on top of a photograph is a glyph
                    // on an unknown background, and there is no colour that
                    // reads on all of them.
                    border.width: cell.modelData.current ? 2 : Theme.hairline
                    border.color: cell.modelData.current ? Theme.accentPrimary
                                : cellHover.hovered ? Theme.borderStrong
                                                    : Theme.borderSubtle

                    Behavior on border.color {
                        ColorAnimation {
                            duration: Theme.duration(Theme.motionFast)
                            easing.type: Easing.Bezier
                            easing.bezierCurve: Theme.fogEase
                        }
                    }

                    Image {
                        anchors.fill: parent
                        anchors.margins: 2
                        source: Paths.fileUrl(cell.modelData.path)
                        fillMode: Image.PreserveAspectCrop
                        // Bounded to the cell, not to the file — see the header.
                        sourceSize: Qt.size(frame.width * 2, frame.height * 2)
                        // Unlike the desktop's own wallpaper, which cannot be:
                        // a thumbnail arriving a frame late is a thumbnail.
                        asynchronous: true
                        cache: true
                        smooth: true
                        visible: status === Image.Ready

                        onStatusChanged: if (status === Image.Error)
                            Logger.warn("wallpaper",
                                        "could not decode " + cell.modelData.path);
                    }
                }

                Text {
                    id: nameLabel

                    anchors {
                        top: frame.bottom
                        topMargin: Theme.space1
                        left: parent.left
                        right: parent.right
                    }
                    text: cell.modelData.name
                    elide: Text.ElideRight
                    color: cell.modelData.current ? Theme.accentPrimary : Theme.textMuted
                    font.family: Theme.fontUi
                    font.pointSize: Theme.pt(10)
                }
            }
        }
    }
}
