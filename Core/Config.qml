pragma Singleton

// User settings, from `~/.config/forest-shell/settings.json` (#12 §5, #33).
//
// This file is deliberately almost empty: the schema is data
// (Core/SettingsSchema.qml), the file behaviour is one component
// (Core/SpecFile.qml), and what is left here is the singleton consumers name.
//
// The contract, unchanged since the skeleton (#32): reading is *synchronous*
// because it is stage one of startup and the background surface needs the
// configured wallpaper for the very first frame; `Config.ready` is the gate
// every surface waits on (#12 §4 — no defaults-flash-then-snap); defaults sit
// under user values; and a file the shell cannot understand leaves the last
// good config in place, untouched on disk.
//
// Reading a setting:
//
//   Config.values.bar.height          // typed, complete, never undefined
//   Config.get("bar.height")          // the same, by dotted path
//
// Writing one (the settings GUI, #54, and any shell-side toggle):
//
//   Config.set("appearance.darkMode", false)
//
// Reacting to one — for anything that cannot be expressed in the schema's own
// `onChange`, which is most things, since the schema has no Quickshell imports:
//
//   Connections {
//       target: Config
//       function onKeyChanged(path, value, previous) { ... }
//   }
//
// `pragma Singleton` leads this file, and every other singleton in the repo,
// rather than following the header comment: Quickshell's scan for it gives up
// at the first line that looks like the start of an object body, and does not
// notice that the `Connections {` above is inside a comment. A singleton it
// misses becomes a plain type — every property and function on it reads back
// `undefined`, with nothing logged, anywhere. This is the one file that
// explains it; the others just do it.
import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property alias ready: settings.ready
    readonly property alias values: settings.values

    // Emitted once when the first read settles, and after every reload that
    // actually changed something.
    signal reloaded()
    signal keyChanged(string path, var value, var previous)

    function get(path: string): var { return settings.get(path); }
    function set(path: string, value: var): bool { return settings.set(path, value); }
    function reset(path: string): bool { return settings.reset(path); }

    // The one shorthand the shell has so far. Read by the background surface on
    // the first frame, so it stays a plain property rather than a lookup.
    readonly property string wallpaper: settings.values.wallpaper?.path ?? ""

    // Its neighbour, and deliberately not the same thing (#45): `wallpaper` is
    // *the* wallpaper, and this is only where the picker goes looking for more.
    // A machine whose wallpaper lives outside this folder is a normal machine.
    readonly property string wallpaperFolder: settings.values.wallpaper?.folder ?? ""

    // Held as its own property rather than declared inline on `schema` below:
    // an object declaration assigned straight to a child's required property
    // leaves the whole singleton empty at runtime, with no error printed.
    readonly property QtObject schema: SettingsSchema {}

    SpecFile {
        id: settings

        label: "config"
        path: Paths.settingsFile
        schema: root.schema
        blocking: true   // stage one: the wallpaper depends on this

        onReloaded: root.reloaded()
        onKeyChanged: (path, value, previous) => root.keyChanged(path, value, previous)
    }

    Component.onCompleted: Logger.stage("config ready")
}
