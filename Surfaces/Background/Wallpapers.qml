pragma Singleton

// The wallpaper picker's source (#45): what is in the folder, and the one write
// that makes a pick survive a restart.
//
//     Wallpapers.entries      // [{ path, name, current }], ready to draw
//     Wallpapers.folder       // where it looked, expanded
//     Wallpapers.choose(path) // sets wallpaper.path and returns
//
// ## Why the pick persists, in one sentence
//
// `choose()` writes `wallpaper.path` into settings.json, which is the same key
// Core/Config.qml reads synchronously at stage one and the same one
// Surfaces/Background/Wallpaper.qml binds its `Image` to. There is no second
// store, no cache and no copy: the wallpaper after a restart is the wallpaper
// before it because both are that one string being read twice.
//
// ## Why the listing is `FolderListModel`
//
// The alternative was a `Process` running `find`, which is what
// Services/Networking/Vpn.qml does for a listing it cannot get natively. Here
// it would be a subprocess spawn for something Qt already has, and the model
// arrives asynchronously either way — so the shell would carry a parser, an
// exit status to check (#78) and a second thing to get wrong, in exchange for
// nothing. `FolderListModel` is a plain Qt module: it costs no Quickshell import
// and it is not on any critical path, since nothing reads this until the picker
// is opened.
//
// What it does cost is that the *decisions* have to stay out of it — which files
// count, what order, which one carries the tick — and those are all in
// Surfaces/Background/WallpaperPolicy.qml where tests/ can reach them.
//
// `pragma Singleton` leads the file for the reason Core/Config.qml explains.
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import qs.Core

Singleton {
    id: root

    readonly property WallpaperPolicy policy: WallpaperPolicy {}

    /// Where to look, as the user wrote it — `~/Pictures/Wallpapers` unless
    /// they said otherwise. Kept as written so the settings row shows what is
    /// in the file rather than an expansion of it.
    readonly property string configured: Config.wallpaperFolder || policy.defaultFolder

    /// The same path with `~` resolved, which is what a `file://` URL needs and
    /// what the empty-state line shows: a picker that says it found nothing in
    /// `~/Pictures/Wallpapers` on a machine where that is not where it looked
    /// is a picker that sends people to the wrong folder.
    readonly property string folder: root.configured.startsWith("~/")
                                     ? Paths.home + root.configured.slice(1)
                                     : root.configured

    /// Whether the picker has anything to draw. False on a fresh machine with
    /// no such folder, which is a normal machine — the panel says where it
    /// looked rather than treating it as an error.
    readonly property bool empty: root.entries.length === 0

    /// The grid, ready to draw. Republished only when the policy's signature
    /// moves (#75): a thumbnail is an `Image` with a decode behind it, so a
    /// rebuilt delegate is the whole folder decoded again — by some distance the
    /// most expensive rebuild in the shell.
    property var entries: []
    property string signature: ""

    function rebuild(): void {
        const files = [];
        for (let i = 0; i < listing.count; i++)
            files.push({ path: listing.get(i, "filePath") });

        const rows = root.policy.entries(files, root.currentPath);
        const signature = root.policy.signature(rows);
        if (signature === root.signature)
            return;
        root.signature = signature;
        root.entries = rows;
        Logger.log("wallpaper", root.policy.counted(rows.length, root.folder));
    }

    /// The wallpaper that is set, with `~` expanded so it can be compared
    /// against the absolute paths the listing hands back. The policy normalises
    /// the rest — a `file://` URL and a doubled slash both name the same file —
    /// but it has no environment to expand a home directory with.
    readonly property string currentPath: Config.wallpaper.startsWith("~/")
                                          ? Paths.home + Config.wallpaper.slice(1)
                                          : Config.wallpaper

    FolderListModel {
        id: listing

        folder: Paths.fileUrl(root.folder)
        // The policy decides what counts as a wallpaper — this is only what the
        // model is willing to hand over, and it has to be *wider* than the
        // policy's answer or a file the policy would accept could never reach
        // it. Directories are excluded here rather than there because "is this
        // a directory" is not a decision, it is a fact about a filesystem.
        showDirs: false
        showHidden: false
        sortField: FolderListModel.Name

        onCountChanged: root.rebuild()
        onStatusChanged: if (status === FolderListModel.Ready) root.rebuild();
    }

    // The tick moves when the wallpaper does, including when it is changed by
    // hand in settings.json while the picker is open.
    onCurrentPathChanged: root.rebuild()

    /// Pick one. The whole of persistence, and deliberately the whole of it:
    /// one key, written once.
    ///
    /// A pick that changes nothing is not a write. Every write is a settings
    /// file rewritten and a reload pushed to every surface bound to it, and
    /// pressing the wallpaper you are already on is the most likely press in
    /// the panel — it is the one with the tick on it.
    function choose(path: string): void {
        const wanted = String(path ?? "").trim();
        if (wanted === "") {
            Logger.warn("wallpaper", root.policy.refused("", "no path"));
            return;
        }
        if (!root.policy.isImage(wanted)) {
            Logger.warn("wallpaper", root.policy.refused(wanted, "not an image"));
            return;
        }
        if (!root.policy.changed(root.currentPath, wanted)) {
            Logger.log("wallpaper", root.policy.refused(wanted, "already set"));
            return;
        }

        if (!Config.set("wallpaper.path", wanted)) {
            // Config.set answers false for a key the schema does not have or a
            // value it will not coerce. Neither should be reachable from a row
            // this panel drew, which is exactly why it is worth a line if it
            // ever is (#78: a write that failed and said nothing is the shape
            // of bug that costs a session).
            Logger.warn("wallpaper", root.policy.refused(wanted, "the config refused it"));
            return;
        }
        Logger.log("wallpaper", root.policy.applied(wanted));
    }
}
