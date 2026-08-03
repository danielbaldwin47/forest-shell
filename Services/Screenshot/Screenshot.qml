pragma Singleton

// The screenshot pipeline (#51) — freeze, select, save, copy, hand off.
//
//     Screenshot.open("ipc")            put the picker up
//     Screenshot.commit(rect, "drag")   take that rectangle
//     Screenshot.cancel("escape")       put it away
//
// Every *decision* is ScreenshotPolicy.qml next door, where `tests/` can reach
// it (CLAUDE.md, seam 1). What is here is the four things that need a
// compositor or a subprocess: the freeze, the window list, the two optional
// tools, and the state the surface binds to.
//
// ## The surface does the grab, and that is deliberate
//
// This file never touches a pixel. It computes *where* the file goes and emits
// `saveRequested`; Surfaces/Screenshot/PickerWindow.qml owns the Item holding
// the frozen frame, so it is the only thing that *can* grab it, and it calls
// `saved()` back with the outcome. Putting the grab here would mean a service
// reaching into a surface for an Item, which is the dependency the wrong way
// round — and `grabToImage` is asynchronous, so the callback has to live where
// the Item does regardless.
//
// ## Why the freeze is a file and not a live texture
//
// The ticket asks for `ScreencopyView`, and it is the better shape — a texture
// with no subprocess. Measured against upstream Quickshell 0.3.0 on Hyprland
// 0.56.1 it never produces a frame: `hasContent` stays false and `sourceSize`
// stays `-1x-1` forever, in live mode and after an explicit `captureFrame()`,
// with all three screencopy protocols advertised by the compositor and the
// scene graph rendering normally. Nothing is logged when it fails, so a picker
// built on it comes up transparent and reads as a styling bug. `grim` writes
// the same frame to a scratch PNG in ~50ms, and a crop of that file was
// measured bit-identical to cropping the source — see the PR.
//
// `pragma Singleton` leads the file for the reason Core/Config.qml explains.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Core

Singleton {
    id: root

    readonly property ScreenshotPolicy policy: ScreenshotPolicy {}

    // --- what the surface binds to -------------------------------------------

    /// Whether the picker is up. The surface's `visible` hangs off this, and
    /// nothing else sets it — `open()` and `cancel()` are the only doors.
    property bool active: false

    /// The screen the picker is on, by name. One screen at a time: a region
    /// spanning two outputs is a different feature and `grim -g` would need a
    /// different capture anyway.
    property string screen: ""

    /// The frozen frame, as a URL for `Image.source`. Empty until grim lands,
    /// which is what the surface waits on before drawing anything.
    property string freeze: ""

    /// Which freeze this is. It is in the *file name* rather than in a query
    /// string on the URL, because `Image` caches by URL and will happily
    /// redisplay its previous decode of a path whose bytes have changed — the
    /// second screenshot of a session would be a picture of the first one.
    /// A distinct path per freeze does not rely on `cache: false` behaving.
    property int freezeEpoch: 0

    /// The window rectangles worth snapping to, on this screen and workspace.
    property var windows: []

    /// The screen's logical bounds and its scale factor — the two numbers the
    /// picker needs that are not in the freeze itself.
    property var bounds: root.policy.empty()
    property real scale: 1

    /// Where the surface should write the crop, and how big. Emitted once per
    /// committed selection; the surface answers with `saved()`.
    signal saveRequested(rect region, string file, var raster)

    // --- the compositor's answer ---------------------------------------------

    // Bound, never polled: Hyprland's models populate asynchronously and an
    // imperative read at `Component.onCompleted` returns an empty list with the
    // windows all there (the DesktopEntries trap, same shape).
    readonly property var toplevels: Hyprland.toplevels.values
    readonly property var focusedMonitor: Hyprland.focusedMonitor

    // --- opening -------------------------------------------------------------

    /// Put the picker up: freeze the screen, gather the windows, show it.
    ///
    /// Returns whether anything happened, so a caller — and
    /// tools/screenshot-harness.sh — can tell "opened" from "already open".
    function open(reason: string): bool {
        return root.openAfter(reason, 0);
    }

    /// The same, but with the freeze held back for `settleMs`.
    ///
    /// The delay exists for one caller and is passed in rather than worked out
    /// here: a picker opened *from the launcher* would otherwise photograph the
    /// launcher, because the drawer's close is a 140ms fade and grim needs
    /// ~50ms — so the shot lands while the surface that asked for it is still
    /// halfway down the screen. The service cannot see that for itself without
    /// importing `qs.Surfaces.Drawers`, which is a dependency from Services/
    /// into a surface and a cycle waiting to happen; the caller already knows
    /// how long its own animation is.
    ///
    /// Zero for the keybind and IPC paths, which have nothing to wait for and
    /// should not pay for someone else's fade.
    function openAfter(reason: string, settleMs: int): bool {
        if (root.active || settle.running || seed.running || freezer.running) {
            Logger.log("screenshot", root.policy.alreadyOpen());
            return false;
        }

        const monitor = root.focusedMonitor;
        if (!monitor) {
            Logger.warn("screenshot", "no focused monitor — nothing to photograph");
            return false;
        }

        const ipc = monitor.lastIpcObject ?? {};
        root.screen = String(monitor.name ?? "");
        root.bounds = root.policy.bounds(ipc);
        root.scale = Number(ipc.scale) > 0 ? Number(ipc.scale) : 1;
        root.windows = root.policy.windows(
            root.toplevels.map(t => t.lastIpcObject),
            (ipc.activeWorkspace ?? {}).id,
            ipc.id);

        root.openReason = reason;
        root.freezeEpoch++;
        root.freeze = "";

        // The destination directory is made now rather than at save time: it is
        // one `mkdir` either way, and doing it here means the failure — a
        // read-only home, a path that is a file — surfaces before the user has
        // spent a drag on it. The freeze waits for it rather than racing it:
        // the same step sweeps up the previous freeze, and run concurrently
        // that `rm` can land after grim has written the new one.
        if (settleMs > 0) {
            settle.interval = settleMs;
            settle.start();
        } else {
            seed.running = true;
        }
        return true;
    }

    /// Put it away. Every exit but a completed save comes through here, and the
    /// reason is in the log line because "the picker closed" has four causes.
    function cancel(reason: string): void {
        if (!root.active && !settle.running && !seed.running && !freezer.running)
            return;
        settle.stop();
        root.active = false;
        root.pendingRegion = null;
        Logger.log("screenshot", root.policy.cancelled(reason));
    }

    // --- taking it -----------------------------------------------------------

    /// Take a rectangle. `how` is prose for the log — "drag", "window: kitty",
    /// "ipc" — because a region that came out wrong is a question about which
    /// gesture produced it.
    function commit(region: var, how: string): bool {
        const wanted = root.policy.clamp(region, root.bounds);
        if (!root.policy.isRegion(wanted)) {
            Logger.warn("screenshot", root.policy.tooSmall(wanted));
            return false;
        }

        const dir = root.policy.directory(Config.values.system?.screenshot?.directory, Paths.home);
        const file = root.policy.path(dir, root.policy.filename(new Date()));
        const raster = root.policy.nativeSize(wanted, root.scale);

        Logger.log("screenshot", root.policy.selected(wanted, how));
        root.lastFile = file;
        root.saveRequested(Qt.rect(wanted.x, wanted.y, wanted.width, wanted.height), file, raster);
        return true;
    }

    /// What the surface reports back once `grabToImage` has run. The picker
    /// comes down here and not at `commit()`: the grab reads the item, so
    /// hiding it first would photograph an empty overlay.
    function saved(file: string, ok: bool, raster: var): void {
        root.active = false;

        if (!ok) {
            Logger.warn("screenshot", root.policy.saveFailed(file));
            return;
        }

        Logger.log("screenshot", root.policy.saved(file, raster));
        root.toClipboard(file);
        root.toEditor(file);
    }

    // --- the two optional tools ----------------------------------------------

    /// The image onto the Wayland selection.
    ///
    /// `Quickshell.clipboardText` owns the selection for text and needs no
    /// subprocess, but it is a string property — 0.3.0 has no image equivalent
    /// — so an image selection needs `wl-copy`. When it is missing the path
    /// goes on the clipboard instead: not what was asked for, but pasteable
    /// into a terminal, and the log says which one happened.
    function toClipboard(file: string): void {
        if (!Config.values.system?.screenshot?.copyToClipboard) {
            Logger.log("screenshot", "clipboard copy is off — leaving the selection alone");
            return;
        }

        if (!root.copyAvailable) {
            Quickshell.clipboardText = file;
            Logger.warn("screenshot", root.policy.copiedPathInstead(file));
            return;
        }

        copier.command = root.policy.copyArgv(file);
        copier.running = true;
        Logger.log("screenshot", root.policy.copied(file));
    }

    /// The shot to an editor, when one is configured and installed. An absent
    /// editor is a normal outcome — the ticket says "when present; silently
    /// absent otherwise" — so it is a `log` and not a `warn`.
    function toEditor(file: string): void {
        const tool = String(Config.values.system?.screenshot?.editor ?? "");
        if (!root.policy.wants(tool)) {
            Logger.log("screenshot", root.policy.editorOff());
            return;
        }
        if (!root.editorAvailable) {
            Logger.log("screenshot", root.policy.editorAbsent(tool));
            return;
        }

        editor.command = root.policy.editorArgv(tool, file);
        editor.running = true;
        Logger.log("screenshot", root.policy.handedOff(tool, file));
    }

    // --- internals -----------------------------------------------------------

    property string openReason: ""
    property string lastFile: ""
    property var pendingRegion: null

    /// Whether `wl-copy` and the configured editor are on PATH. Probed rather
    /// than assumed, and probed the only way that works: a `Process` whose
    /// binary does not exist emits no `exited` at all — no exit code to read —
    /// so the absence of `started` is the entire signal (#40).
    property bool copyAvailable: false
    property bool editorAvailable: false

    /// A stand-in for grim, for seam 2 only.
    ///
    /// `tools/screenshot-harness.sh` sets this because grim cannot be used
    /// inside the nested compositor at all: it does not fail there, it *hangs*
    /// waiting for a frame that compositor never presents. With a canned PNG
    /// copied into place instead, every other step of the lifecycle — the
    /// picker mapping, the keyboard grab, the crop, the file, the two optional
    /// tools — is exactly the real one. Empty everywhere else, which is every
    /// path a user is on.
    readonly property string freezeOverride: Quickshell.env("FOREST_SCREENSHOT_FREEZE") ?? ""

    readonly property string freezeFile:
        Paths.stateDir + "/screenshot-freeze-" + root.freezeEpoch + ".png"

    // The caller's own animation, waited out before the shutter — see
    // `openAfter()`. Not a `Process`, and deliberately the only timer here.
    Timer {
        id: settle
        repeat: false
        onTriggered: seed.running = true
    }

    Process {
        id: seed

        // `$1` and `$2` rather than interpolation: the destination is a user
        // setting, and a directory name with a space or a quote in it must not
        // be able to become another command.
        command: ["sh", "-c",
                  "mkdir -p \"$1\" \"$2\" && rm -f \"$2\"/screenshot-freeze-*.png",
                  "sh",
                  root.policy.directory(Config.values.system?.screenshot?.directory, Paths.home),
                  Paths.stateDir]

        onExited: (code) => {
            if (code !== 0) {
                Logger.warn("screenshot", "could not make the screenshot directory (exit "
                            + code + ") — not opening the picker");
                root.pendingRegion = null;
                return;
            }
            freezer.running = true;
        }
    }

    Process {
        id: freezer

        property bool started: false

        command: root.policy.freezeArgv(root.screen, root.freezeFile, root.freezeOverride)

        onStarted: {
            freezer.started = true;
            watchdog.restart();
        }

        onExited: (code) => {
            watchdog.stop();
            if (code !== 0) {
                Logger.warn("screenshot", root.policy.freezeFailed(code));
                return;
            }

            Logger.log("screenshot", root.policy.froze(root.freezeFile));
            root.freeze = Paths.fileUrl(root.freezeFile);
            root.active = true;
            Logger.log("screenshot", root.policy.opened(root.screen, root.windows.length));

            if (root.pendingRegion) {
                const wanted = root.pendingRegion;
                root.pendingRegion = null;
                root.commit(wanted, "ipc");
            }
        }

        onRunningChanged: {
            // False without ever having started: grim is not installed. The one
            // case with no exit code to read (#40).
            if (freezer.running || freezer.started)
                return;
            watchdog.stop();
            Logger.warn("screenshot", root.policy.freezeMissing());
            root.active = false;
            root.pendingRegion = null;
        }
    }

    // The deadline on the freeze — see `ScreenshotPolicy.freezeTimeoutMs`. A
    // capture that never answers must not leave the picker in a state that is
    // neither open nor closed, because every later press then answers "already
    // open" and nothing in the log says why.
    Timer {
        id: watchdog
        interval: root.policy.freezeTimeoutMs
        repeat: false
        onTriggered: {
            Logger.warn("screenshot", root.policy.freezeTimedOut());
            freezer.signal(15);
            root.active = false;
            root.pendingRegion = null;
        }
    }

    Process { id: copier }
    Process { id: editor }

    // Two one-shot probes. Each gets its own Process because reassigning
    // `command` on a running one kills the run in flight (#78).
    Process {
        id: copyProbe
        property bool started: false
        command: ["wl-copy", "--version"]
        running: true
        onStarted: copyProbe.started = true
        onRunningChanged: {
            if (copyProbe.running)
                return;
            root.copyAvailable = copyProbe.started;
            if (!copyProbe.started)
                Logger.log("screenshot", "wl-copy is not installed — screenshots will put "
                           + "their path on the clipboard rather than the image");
        }
    }

    Process {
        id: editorProbe
        property bool started: false
        command: [String(Config.values.system?.screenshot?.editor ?? "swappy"), "--version"]
        onStarted: editorProbe.started = true
        onRunningChanged: {
            if (editorProbe.running)
                return;
            root.editorAvailable = editorProbe.started;
        }
    }

    // --- the door from outside -----------------------------------------------

    // No `show`, `list` or `call` on this target: the `qs ipc` client parses
    // those as its own subcommands and exits 0 without calling anything (#77).
    IpcHandler {
        target: "screenshot"

        function open(): bool {
            return root.open("ipc");
        }

        function cancel(): bool {
            root.cancel("ipc");
            return true;
        }

        function isOpen(): bool {
            return root.active;
        }

        /// Take a rectangle without a drag — a keybind for a fixed region, and
        /// the door tools/screenshot-harness.sh drives, because a harness can
        /// move the pointer but cannot hold a button down across two positions.
        function region(x: int, y: int, width: int, height: int): bool {
            const wanted = { x: x, y: y, width: width, height: height };
            if (root.active)
                return root.commit(wanted, "ipc");

            root.pendingRegion = wanted;
            return root.open("ipc region");
        }

        /// The file the last shot went to — what a script chains off, and what
        /// the harness reads to find the file it should exist.
        function last(): string {
            return root.lastFile;
        }
    }

    Component.onCompleted: {
        // Probed after Config has a value to read, not at declaration: the
        // editor's name is a setting.
        editorProbe.running = true;
        Logger.stage("screenshot picker armed (ipc target: screenshot)");
    }
}
