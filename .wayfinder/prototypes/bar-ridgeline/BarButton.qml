import QtQuick
import "."

Item {
    id: root
    property string icon
    property string tooltip: ""
    property int iconSize: 16

    implicitWidth: iconSize + Theme.space2
    implicitHeight: iconSize + Theme.space2

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSm
        color: Theme.surfaceOverlay
        opacity: hover.hovered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.motionFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.fogEase } }
    }

    Icon {
        anchors.centerIn: parent
        name: root.icon
        size: root.iconSize
        color: hover.hovered ? Theme.textPrimary : Theme.textSecondary
    }

    HoverHandler { id: hover }
}
