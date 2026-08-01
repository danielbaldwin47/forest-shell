// What the bar holds: three clusters, filled from the module registry in the
// order `bar.modules` names (#35).
//
// This is the whole of the bar's layout. Everything about *which* modules and
// *where* is config (Core/SettingsSchema.qml → Surfaces/Bar/BarSpec.qml), so
// re-ordering the bar never touches QML — and because Config hot-reloads, the
// list re-evaluates and the clusters re-fill while the shell runs.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core

Item {
    id: content

    required property var barScreen
    required property bool vertical

    property int padding: 12
    property int moduleGap: 14

    readonly property var layout: ModuleRegistry.spec.modules(Config.values.bar.modules)

    BarCluster {
        id: leading

        moduleIds: content.layout.left
        barScreen: content.barScreen
        vertical: content.vertical
        spacing: content.moduleGap

        anchors.left: content.vertical ? undefined : parent.left
        anchors.top: content.vertical ? parent.top : undefined
        anchors.verticalCenter: content.vertical ? undefined : parent.verticalCenter
        anchors.horizontalCenter: content.vertical ? parent.horizontalCenter : undefined
        anchors.margins: content.padding

        height: content.vertical ? implicitHeight : parent.height
        width: content.vertical ? parent.width : implicitWidth
    }

    BarCluster {
        id: middle

        moduleIds: content.layout.center
        barScreen: content.barScreen
        vertical: content.vertical
        spacing: content.moduleGap

        anchors.centerIn: parent

        height: content.vertical ? implicitHeight : parent.height
        width: content.vertical ? parent.width : implicitWidth
    }

    BarCluster {
        id: trailing

        moduleIds: content.layout.right
        barScreen: content.barScreen
        vertical: content.vertical
        spacing: content.moduleGap

        anchors.right: content.vertical ? undefined : parent.right
        anchors.bottom: content.vertical ? parent.bottom : undefined
        anchors.verticalCenter: content.vertical ? undefined : parent.verticalCenter
        anchors.horizontalCenter: content.vertical ? parent.horizontalCenter : undefined
        anchors.margins: content.padding

        height: content.vertical ? implicitHeight : parent.height
        width: content.vertical ? parent.width : implicitWidth
    }
}
