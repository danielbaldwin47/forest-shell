// Content lifetime for windows that outlive their visibility.
//
// The window discipline (#12 §2, #22 §5): a layer-shell window is never
// destroyed to hide it — destroying and recreating surfaces is the compositor
// crash class the reference-shell survey found. The window stays alive with
// `visible: false` and drops its *content* instead, after a debounce so a
// reopen inside the delay costs nothing and unmapped windows still contribute
// zero wakeups.
//
// Dumb by contract: no Services, no Config, no Theme — the caller drives
// `shown`.
import QtQuick

Loader {
    id: root

    // Whether the content should exist. Usually bound to window visibility.
    required property bool shown

    // How long content survives after `shown` goes false.
    property int unloadDelayMs: 2000

    active: false
    asynchronous: false

    onShownChanged: {
        if (shown) {
            unloadTimer.stop();
            active = true;
        } else if (active) {
            unloadTimer.restart();
        }
    }

    Component.onCompleted: if (shown) active = true

    Timer {
        id: unloadTimer
        interval: root.unloadDelayMs
        onTriggered: if (!root.shown) root.active = false
    }
}
