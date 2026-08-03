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
// Nothing below names a type from `Modules/`, and the import still has to be
// here. Quickshell turns a directory into a `qs.` module only when it walks an
// import naming it, and that walk happens once, before any Loader runs — so a
// directory reached exclusively by URL, as `Modules/` is by the Loader further
// down, never becomes a module at all. A module that loads a sibling then finds
// its own directory does not exist and drops out of the bar with a warning.
// This line is what puts `Modules/` in front of the scanner (#73).
import qs.Surfaces.Bar.Modules

Item {
    id: root

    required property ShellScreen screen

    readonly property var settings: Config.values.bar

    // Unknown and repeated names are dropped here, with a warning naming each
    // one, so a typo costs one module instead of the bar.
    readonly property var layout: registry.resolve(root.settings.modules)

    /// Whether the wallpaper behind the bar has been read and the legibility
    /// floor (#79) is in force. False for the first moment of a bar's life and
    /// after every wallpaper change — the bar paints at the plain setting until
    /// then. Exposed because a capture taken before it is true is a picture of
    /// a fill the shell does not ship (capture-harness.qml).
    readonly property bool legibilityReady: legibility.item ? legibility.item.ready : false

    /// Whether the fill has finished fading to the floor as well as being told
    /// it. The clamp arrives after the first frame and lands on the fog curve,
    /// so `legibilityReady` is true for ~140ms before the bar looks the way it
    /// is going to — long enough for a capture to come back with a colour the
    /// shell never settles on (capture-harness.qml).
    readonly property bool legibilitySettled: root.legibilityReady
        && Math.abs(surface.paintedOpacity - surface.fillOpacity) < 0.002

    BarRegistry { id: registry }

    SurfaceOpacity { id: opacityPolicy }

    BarSurface {
        id: surface

        anchors.fill: parent
        settings: root.settings.surface
        radius: root.settings.floating ? root.settings.floatRadius : 0
        hairlineAtBottom: root.settings.position === "top"
        // The setting is what the user asked for; the floor is what the
        // wallpaper in front of it will allow (#79). The greater of the two is
        // what gets painted, so the slider is never overruled downwards and the
        // text is never left under 4.5:1.
        fillOpacity: opacityPolicy.effectiveOpacity(
            root.settings.surface.opacity,
            legibility.item ? legibility.item.floor : NaN)
    }

    // The legibility floor is not optional and is not a setting, so this Loader
    // is no longer an off switch — it is here because this is the one part of
    // the bar that depends on `ColorQuantizer`, and a runtime without that type
    // should lose the clamp rather than the bar. Losing it means the bar paints
    // at the setting, which is exactly what shipped before #79.
    Loader {
        id: legibility

        Component.onCompleted: setSource(Qt.resolvedUrl("BarLegibility.qml"),
                                         { screen: root.screen })

        // Losing this is a *quiet* degradation — the bar goes on painting at
        // the setting and looks entirely correct on the dark wallpaper the
        // author happens to have — so it says so. Without the line, a runtime
        // with no `ColorQuantizer` is indistinguishable from a working clamp
        // that had nothing to do.
        onStatusChanged: {
            if (status === Loader.Error)
                Logger.warn("bar", "legibility clamp unavailable, the fill will paint at "
                            + "the setting whatever the wallpaper does: " + source);
        }
    }

    // One Repeater over the three clusters rather than three hand-written rows:
    // a cluster differs from its neighbours only in which edge it anchors to.
    Repeater {
        model: registry.clusters

        delegate: Row {
            id: cluster

            required property string modelData

            anchors {
                verticalCenter: parent.verticalCenter
                left: cluster.modelData === "left" ? parent.left : undefined
                right: cluster.modelData === "right" ? parent.right : undefined
                horizontalCenter: cluster.modelData === "center" ? parent.horizontalCenter : undefined
                leftMargin: root.settings.padding
                rightMargin: root.settings.padding
            }

            // One gap everywhere. The prototype ran the centre cluster at 1.5x
            // for rhythm, but #10's table settled "12px inner horizontal, 14px
            // between modules" flat — and a second, wider gap that no setting
            // reaches is a taste call nobody measured.
            spacing: root.settings.moduleGap

            Repeater {
                model: root.layout[cluster.modelData]

                delegate: Loader {
                    id: module

                    required property string modelData

                    anchors.verticalCenter: parent.verticalCenter

                    // A module that hides itself must take its gap with it. A
                    // `Row` skips invisible children entirely but still puts
                    // `spacing` around a visible one of zero width, so without
                    // this the three self-hiding modules #37 adds — media with
                    // nothing playing, the keyboard layout on a single-layout
                    // machine, the window title on an empty workspace — would
                    // each leave a 14px hole in the bar where they are not.
                    //
                    // **`shown` and not `visible`**, which is the module
                    // contract and not a synonym: a module that can be absent
                    // declares `shown`, and this reads it. Asking the item
                    // about `visible` instead deadlocks — Qt forces every
                    // child of an invisible item to read `visible: false`, so
                    // a Loader that starts hidden (its item does not exist for
                    // the first evaluation) would hide the module it then
                    // loaded, forever. Measured: it emptied the whole bar.
                    //
                    // A module with no `shown` is always on the bar, which is
                    // most of them — the clock does not have a case for being
                    // absent.
                    visible: module.item !== null && module.item.shown !== false

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
