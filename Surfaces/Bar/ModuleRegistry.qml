pragma Singleton

// Module id → component (#35).
//
// The bar does not know what a clock is. It reads a list of ids from
// `bar.modules`, asks here for each one, and places whatever comes back — so
// ordering, enabling and disabling are a config edit rather than a QML edit,
// and they hot-reload for free (#35: module order/enable from settings.json).
//
// Adding a module is two lines: an id in `BarSpec.moduleIds`, and its component
// here. The two lists are checked against each other on construction, because
// an id in the spec with no component is a module that silently never appears.
//
// `pragma Singleton` leads this file for the reason Core/Config.qml explains at
// length: Quickshell's scan for it gives up at the first line that looks like
// the start of an object body, comment or not.
import QtQuick
import Quickshell
import qs.Core

Singleton {
    id: root

    // Held only for the consistency check below — the registry is an id →
    // component map, and callers that want the spec instantiate their own
    // rather than reaching through this one for knobs it has nothing to do
    // with.
    readonly property QtObject spec: BarSpec {}

    readonly property var components: ({
        workspaces: root.workspacesModule,
        clock: root.clockModule
    })

    /// The component for an id, or null. Null is a normal answer — BarSpec has
    /// already dropped ids it does not know, so this only returns null for a
    /// registry that has fallen out of step with the spec, which the check
    /// below reports on startup.
    function componentFor(id: string): Component {
        return root.components[id] ?? null;
    }

    readonly property Component workspacesModule: Component { Workspaces {} }
    readonly property Component clockModule: Component { Clock {} }

    Component.onCompleted: {
        for (const id of root.spec.moduleIds)
            if (root.components[id] === undefined)
                Logger.warn("bar", "module '" + id + "' is in the spec with no component");
        for (const id in root.components)
            if (root.spec.moduleIds.indexOf(id) < 0)
                Logger.warn("bar", "module '" + id + "' has a component but is not in the spec");
    }
}
