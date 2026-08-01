// The bar's material and its three module clusters.
//
// Everything the window holds lives here rather than in Surfaces/Bar/Bar.qml,
// because this is what auto-hide unloads: the window and its layer surface
// outlive the content by design (#12 §2), so the split between them is exactly
// the split between "exists for the life of the shell" and "exists while you
// are looking at it".
//
// Layout is **registry-driven** (Surfaces/Bar/BarRegistry.qml): three lists of
// module names in settings.json, resolved to three rows of loaded components.
// Reordering the bar is editing an array, and it takes effect on save with no
// reload — the resolution below is a binding on `Config.values`, and the
// clusters are Repeaters over its result.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Core

Item {
    id: root

    required property ShellScreen screen

    readonly property var settings: Config.values.bar

    // Unknown and repeated names are dropped here, with a warning naming each
    // one, so a typo costs one module instead of the bar.
    readonly property var layout: registry.resolve(root.settings.modules)

    BarRegistry { id: registry }

    BarSurface {
        anchors.fill: parent
        settings: root.settings.surface
        radius: root.settings.floating ? root.settings.floatRadius : 0
        hairlineAtBottom: root.settings.position === "top"
        fillOpacity: adaptive.item && adaptive.item.ready
            ? adaptive.item.value
            : root.settings.surface.opacity
    }

    // Adaptive opacity is off by default and costs nothing while off: the
    // wallpaper is not read, not decoded and not quantized, because the Loader
    // holding all of that is inactive. It is also the one part of the bar that
    // depends on a Quickshell type nothing else here uses, so keeping it behind
    // a Loader means a build without that type loses the feature rather than
    // the bar.
    Loader {
        id: adaptive
        active: root.settings.surface.adaptiveOpacity
        source: Qt.resolvedUrl("AdaptiveOpacity.qml")
    }

    // One Repeater over the three clusters rather than three hand-written rows:
    // a cluster differs from its neighbours only in which edge it anchors to.
    Repeater {
        model: registry.clusters

        delegate: Row {
            id: cluster

            required property string modelData

            readonly property bool isCenter: cluster.modelData === "center"

            anchors {
                verticalCenter: parent.verticalCenter
                left: cluster.modelData === "left" ? parent.left : undefined
                right: cluster.modelData === "right" ? parent.right : undefined
                horizontalCenter: cluster.isCenter ? parent.horizontalCenter : undefined
                leftMargin: root.settings.padding
                rightMargin: root.settings.padding
            }

            // The centre cluster reads as one group at a wider rhythm — it is
            // the only one not braced against an edge.
            spacing: cluster.isCenter ? Math.round(root.settings.moduleGap * 1.5)
                                      : root.settings.moduleGap

            Repeater {
                model: root.layout[cluster.modelData]

                delegate: Loader {
                    id: module

                    required property string modelData

                    anchors.verticalCenter: parent.verticalCenter

                    // Synchronous: the bar is on the critical path to the first
                    // frame, and a module that arrives a frame later would show
                    // as the cluster jumping into place.
                    asynchronous: false
                    source: Qt.resolvedUrl("Modules/" + registry.modules[module.modelData].file)

                    onStatusChanged: if (status === Loader.Error)
                        Logger.warn("bar", "module failed to load: " + module.modelData)
                }
            }
        }
    }

    Component.onCompleted: Logger.log("bar", "content ready on " + root.screen.name
        + " (" + root.layout.left.length + "/" + root.layout.center.length
        + "/" + root.layout.right.length + " modules)")
}
