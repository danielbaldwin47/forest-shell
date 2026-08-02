// What the wallpaper picker decides (#45), as pure functions.
//
// The files arrive as plain rows — `{ path, name }` — from whatever listed the
// folder, which is what keeps this file free of `FolderListModel` and therefore
// reachable from tests/. Surfaces/Background/Wallpapers.qml is the half that
// knows what a directory is.
//
// ## Two paths, and only one of them is the wallpaper
//
// `wallpaper.path` is the wallpaper. `wallpaper.folder` is where the picker
// looks for candidates, and nothing else reads it — a machine whose wallpaper
// lives outside that folder is a normal machine, and the picker showing no tick
// is the correct answer there rather than a reason to move the file.
//
// ## The intent that persists is the path
//
// The ticket asks for the pick to survive a restart, and the whole of how it
// does is that the picker writes `wallpaper.path` to settings.json — which is
// the same key Core/Config.qml has read at stage one since #32 and the same one
// Surfaces/Background/Wallpaper.qml binds its image to. There is no second
// store and no cache: the wallpaper on screen after a restart is the wallpaper
// on screen before it because both are that one string.
import QtQuick

QtObject {
    id: policy

    /// What counts as a wallpaper. Raster only, and deliberately: an SVG
    /// scaled to a 4K output is a decode that misses the first-frame budget
    /// (#22 §4, which Surfaces/Background/Wallpaper.qml measures at ~470 ms for
    /// a large JPEG), and an animated GIF as a wallpaper is a repaint per frame
    /// forever against an idle budget of one a minute (#22 §5).
    readonly property var extensions: ["jpg", "jpeg", "png", "webp", "bmp"]

    /// The default folder, as it is written in the schema. `~` and not an
    /// absolute path, because settings.json travels between machines (#33's
    /// "my setup") and the home directory does not.
    readonly property string defaultFolder: "~/Pictures/Wallpapers"

    function isImage(name: var): bool {
        const text = String(name ?? "");
        const dot = text.lastIndexOf(".");
        if (dot < 1)                 // no extension, or a dotfile with none
            return false;
        return policy.extensions.indexOf(text.slice(dot + 1).toLowerCase()) >= 0;
    }

    /// The picker's grid, in the order it is drawn: alphabetical by the name
    /// under each thumbnail, case-insensitively.
    ///
    /// Not by modification time, which is the other plausible ordering: a
    /// folder of wallpapers is a thing people scroll through looking for the
    /// one they remember, and "the one I remember" is found by name.
    function entries(files: var, current: var): var {
        const chosen = policy.normalise(current);
        const out = [];
        for (const file of files ?? []) {
            const path = String(file?.path ?? "").trim();
            if (path === "" || !policy.isImage(path))
                continue;
            out.push({
                path: path,
                name: policy.displayName(path),
                current: policy.normalise(path) === chosen && chosen !== ""
            });
        }
        return out.sort((a, b) => {
            const left = a.name.toLowerCase();
            const right = b.name.toLowerCase();
            if (left !== right)
                return left < right ? -1 : 1;
            return a.path < b.path ? -1 : a.path > b.path ? 1 : 0;
        });
    }

    /// The words under a thumbnail: the file's name without its extension and
    /// without its folder. `forest-at-dawn.jpg` is `forest-at-dawn`, because
    /// the extension is the one part of a filename nobody chose.
    function displayName(path: var): string {
        const text = String(path ?? "");
        const slash = text.lastIndexOf("/");
        const base = slash >= 0 ? text.slice(slash + 1) : text;
        const dot = base.lastIndexOf(".");
        return dot > 0 ? base.slice(0, dot) : base;
    }

    /// One path, for comparing two. A `file://` URL, a `~/`-relative path and
    /// an absolute one can all name the same file, and the tick under the
    /// current wallpaper has to appear whichever of the three settings.json
    /// happens to hold.
    ///
    /// The home directory is not substituted here — the caller has it and this
    /// file has no environment — so `~/x.jpg` and `/home/me/x.jpg` still differ.
    /// Surfaces/Background/Wallpapers.qml expands before it calls.
    function normalise(path: var): string {
        let text = String(path ?? "").trim();
        if (text === "")
            return "";
        if (text.startsWith("file://"))
            text = decodeURI(text.slice(7));
        // A trailing slash on a file path is not a thing, but a doubled one in
        // the middle is what a naive join produces.
        return text.split("//").join("/");
    }

    /// What the panel compares before it republishes (#75). A thumbnail is an
    /// `Image` with a decode behind it, so a rebuilt delegate is a folder of
    /// wallpapers decoded again — the most expensive rebuild in the shell.
    function signature(rows: var): string {
        return (rows ?? []).map(row => row.path + (row.current ? "*" : "-")).join("");
    }

    /// Whether a pick is worth writing at all. Pressing the wallpaper that is
    /// already set is a no-op rather than a config write, because every write
    /// is a file rewritten and a reload of every surface bound to it.
    function changed(current: var, next: var): bool {
        const wanted = policy.normalise(next);
        return wanted !== "" && wanted !== policy.normalise(current);
    }

    // --- what the log says ---------------------------------------------------

    function applied(path: string): string {
        return "wallpaper set to " + path;
    }

    function refused(path: string, reason: string): string {
        return "wallpaper unchanged — " + reason + (path ? ": " + path : "");
    }

    /// The empty state. It names the folder it looked in *and* the key that
    /// changes it, because those are the two things somebody seeing this needs
    /// and neither is guessable: a picker that says "no wallpapers" is one
    /// nobody can fix, and one that says where it looked but not how to look
    /// elsewhere is one they can only fix by moving their files.
    ///
    /// There is deliberately no settings row for that key. It would land on the
    /// Appearance tab, whose "reset this section" button covers `appearance.*`
    /// and so would silently not cover it — a control with a reset that does
    /// not reset it is worse than a documented key.
    function emptyLine(folder: string): string {
        return "No images in " + (folder || policy.defaultFolder)
            + " — set wallpaper.folder in settings.json to look elsewhere.";
    }

    function counted(count: int, folder: string): string {
        return count + " wallpaper(s) in " + folder;
    }
}
