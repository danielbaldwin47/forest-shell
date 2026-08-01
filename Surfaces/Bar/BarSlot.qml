// One placed module (#35).
//
// The indirection exists so the cluster below can be a plain repeater over
// strings: this turns an id into a live module and hands it the two things
// every module may want to know — which screen it is on, and which way the bar
// runs.
//
// Context is assigned once, on load, rather than bound. A Loader cannot supply
// initial values for required properties, and neither value changes over a
// window's life: a bar window is created per screen and never moved between
// outputs (#22 §1), and the axis is fixed at construction. The `in` guard means
// a module only receives what it actually declares.
pragma ComponentBehavior: Bound
import QtQuick

Loader {
    id: slot

    required property string moduleId
    required property var barScreen
    required property bool vertical

    sourceComponent: ModuleRegistry.componentFor(slot.moduleId)

    onLoaded: {
        if ("screen" in item)
            item.screen = slot.barScreen;
        if ("vertical" in item)
            item.vertical = slot.vertical;
    }
}
