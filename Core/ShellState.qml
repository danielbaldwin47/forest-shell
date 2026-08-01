pragma Singleton

// Runtime state, from `state.json` in `Quickshell.stateDir` (#12 §5, #33).
//
// Same engine as Config, opposite lifetime. This is the file the shell writes
// to itself — the tab you had open, the Claude session to resume, whether DND
// is on — and keeping it separate is what lets `settings.json` stay a file you
// can hand-edit, diff and copy to another machine without shell-authored churn
// landing in it (#21).
//
// Read lazily, on purpose: nothing here may be on the path to the first frame.
// Nothing here may be load-bearing either — deleting this file must cost the
// user a re-opened tab and nothing else.
//
//   ShellState.values.dashboard.lastTab
//   ShellState.set("dnd", true)
//
// Named `ShellState` and not `State` because `QtQuick.State` already owns that
// name: every file here imports QtQuick, and a singleton whose name collides
// resolves to the QtQuick type instead — silently, with every property reading
// back `undefined`.
//
// `pragma Singleton` leads the file for the reason spelled out in
// Core/Config.qml.
import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property alias ready: state.ready
    readonly property alias values: state.values

    signal reloaded()
    signal keyChanged(string path, var value, var previous)

    function get(path: string): var { return state.get(path); }
    function set(path: string, value: var): bool { return state.set(path, value); }
    function reset(path: string): bool { return state.reset(path); }

    // Do-not-disturb: the one toggle that is state rather than config, because
    // it is situational rather than part of the setup (#21). Owned by the
    // notification service (#42).
    readonly property bool dnd: state.values.dnd ?? false

    // Not declared inline on `schema` below — see Core/Config.qml.
    readonly property QtObject schema: StateSchema {}

    SpecFile {
        id: state

        label: "state"
        path: Paths.stateFile
        schema: root.schema
        blocking: false

        onReloaded: root.reloaded()
        onKeyChanged: (path, value, previous) => root.keyChanged(path, value, previous)
    }
}
