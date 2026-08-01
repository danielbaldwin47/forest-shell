// What the bar holds: three clusters, filled from the module registry in the
// order `bar.modules` names (#35).
//
// This is the whole of the bar's layout. Everything about *which* modules and
// *where* is config (Core/SettingsSchema.qml → BarSpec.qml), so re-ordering the
// bar never touches QML — and because Config hot-reloads, the list
// re-evaluates and the clusters re-fill while the shell runs.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core

Item {
    id: content

    required property var barScreen
    required property bool vertical

    // Required rather than defaulted: the shipped values are the schema's
    // (`bar.padding`, `bar.moduleGap`), and restating them here would give
    // them two homes.
    required property int padding
    required property int moduleGap

    readonly property QtObject spec: BarSpec {}
    readonly property var layout: content.spec.modules(Config.values.bar.modules)

    // Everything the three clusters share. What is left at each call site is
    // the only thing that actually differs between them: which end they sit
    // at, and which list they draw.
    component Cluster: BarCluster {
        barScreen: content.barScreen
        vertical: content.vertical
        spacing: content.moduleGap

        height: content.vertical ? implicitHeight : content.height
        width: content.vertical ? content.width : implicitWidth
    }

    Cluster {
        moduleIds: content.layout.left

        anchors.left: content.vertical ? undefined : parent.left
        anchors.top: content.vertical ? parent.top : undefined
        anchors.verticalCenter: content.vertical ? undefined : parent.verticalCenter
        anchors.horizontalCenter: content.vertical ? parent.horizontalCenter : undefined
        anchors.margins: content.padding
    }

    Cluster {
        moduleIds: content.layout.center

        anchors.centerIn: parent
    }

    Cluster {
        moduleIds: content.layout.right

        anchors.right: content.vertical ? undefined : parent.right
        anchors.bottom: content.vertical ? parent.bottom : undefined
        anchors.verticalCenter: content.vertical ? undefined : parent.verticalCenter
        anchors.horizontalCenter: content.vertical ? parent.horizontalCenter : undefined
        anchors.margins: content.padding
    }
}
