// The picture beside a remembered notification (#43).
//
// The same fallback chain the popup card uses — the notification's own image,
// then its app icon out of the icon theme, then a Lucide bell — but over a
// *history row* rather than a live `Notification`, which is the one difference
// that matters: a row is plain data off state.json, so every field may be
// missing and the image is only ever a path. Inline pixmap data lives in
// Quickshell's own image provider keyed by a notification that no longer
// exists, and `NotificationPolicy.persistableImage` drops it on the way to disk
// rather than persisting a URL that is permanently broken.
//
// A file of its own because the centre draws one per group *and* the shell will
// draw them per row the moment the dashboard shows recent notifications (#49) —
// and because a badge that silently draws nothing is exactly the kind of hole
// that reads as a broken panel.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Core
import qs.Widgets

Item {
    id: badge

    /// One history row, as `NotificationPolicy.record()` writes them. Null is
    /// allowed and draws the bell: a group whose rows all just left still gets
    /// one frame with nothing in it.
    required property var row

    /// The side, in px. The glyph inside is sized from it rather than fixed, so
    /// one number moves the whole badge.
    property int size: 22

    implicitWidth: badge.size
    implicitHeight: badge.size

    readonly property string source: {
        if (!badge.row)
            return "";
        if (badge.row.image)
            return Paths.fileUrl(badge.row.image);
        if (badge.row.appIcon)
            return Quickshell.iconPath(badge.row.appIcon, true);
        return "";
    }

    Image {
        id: image

        anchors.fill: parent
        source: badge.source
        // 2× for the 1.5-scale panel (#22), the same as the popup card's.
        sourceSize: Qt.size(badge.size * 2, badge.size * 2)
        fillMode: Image.PreserveAspectFit
        visible: status === Image.Ready
    }

    Icon {
        anchors.centerIn: parent
        visible: !image.visible
        name: "bell"
        size: Math.round(badge.size * 0.8)
        color: Theme.textSecondary
    }
}
