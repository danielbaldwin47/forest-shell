pragma Singleton

// Every path the shell knows, in one place.
//
// The repo root *is* the Quickshell config dir (#12), but user settings do not
// live in it — they go to `~/.config/forest-shell/`, so the checkout stays
// clean and a git pull never fights a settings write.
import QtQuick
import Quickshell

Singleton {
    readonly property string shellDir: Quickshell.shellDir

    readonly property string home: Quickshell.env("HOME") ?? ""

    readonly property string configDir:
        (Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")) + "/forest-shell"

    // User intent — hand-editable, hot-reloaded. Owned by Core/Config.qml.
    readonly property string settingsFile: configDir + "/settings.json"

    // Ephemera (last tab, session ids, DND) — never mixed into settings.json.
    readonly property string stateDir: Quickshell.stateDir
    readonly property string stateFile: stateDir + "/state.json"

    // QML `source` properties want a URL, not a path. Percent-encoding is not
    // optional: a wallpaper living in a directory with a `#` in its name parses
    // as a URL fragment and the file silently never loads.
    function fileUrl(path: string): string {
        if (!path)
            return "";
        if (path.startsWith("file://") || path.startsWith("qrc:") || path.startsWith("root:"))
            return path;
        const absolute = path.startsWith("~/") ? home + path.slice(1) : path;
        // encodeURI keeps `/` intact but leaves the URL delimiters alone.
        return "file://" + encodeURI(absolute)
            .replace(/#/g, "%23")
            .replace(/\?/g, "%3F");
    }
}
