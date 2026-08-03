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

    // Saved skins (#56), beside the settings they are fragments of: a theme is
    // a file the user may hand-write, copy between machines and keep in a dotfile
    // repo, which is the same claim `settings.json` makes.
    readonly property string themesDir: configDir + "/themes"

    // Ephemera (last tab, session ids, DND) — never mixed into settings.json.
    readonly property string stateDir: Quickshell.stateDir
    readonly property string stateFile: stateDir + "/state.json"

    // The undo slot behind "Previous settings" (#56): what the skin was just
    // before the last apply. State and not config — it is written by the shell,
    // for the shell, and losing it costs one press of undo.
    readonly property string previousThemeFile: stateDir + "/previous-theme.json"

    // Where every `claude -p` turn runs (#41). It is a directory and not a
    // detail: the CLI scopes session lookup to the working directory, so two
    // turns run from different places are two conversations. Pinned here,
    // stable, and deliberately not the checkout — a git repository widens the
    // lookup across worktrees in ways nothing here can predict.
    readonly property string claudeDir: stateDir + "/claude"

    // Clipboard thumbnails, decoded out of cliphist (#53). Cache and not state:
    // every file in here is reproducible from the history in one `cliphist
    // decode`, so losing the lot costs one decode per picture and nothing else.
    // That is the whole difference between this directory and `stateDir`, and it
    // is why a `rm -rf` of it is a supported thing to do.
    readonly property string cacheDir: Quickshell.cacheDir
    readonly property string clipboardDir: cacheDir + "/clipboard"

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
