// Every decision the screenshot picker makes (#51), as pure functions.
//
// The picker itself is a drag on a layer surface and a grab to a file; what is
// *wrong* about a screenshot is almost never the drag. It is which rectangle a
// backwards drag means, which window a click landed on, whether an edge should
// have snapped, what the file is called, and which argv reaches the tool. All
// of that is here, where `tests/` can pose it (CLAUDE.md, seam 1), and the
// surface next door keeps only the parts that need a compositor.
//
// ## One coordinate space, and it is the compositor's
//
// The single fact that keeps this file simple: **windows, the picker's own
// window, and `grim -g` all speak the compositor's layout space.** Measured on
// eDP-1 (1920x1080 native, scale 1.5, so 1280x720 logical):
//
//   - a toplevel reports `at: [14, 58], size: [1252, 648]` — logical
//   - the picker's layer surface is 1280x720 — logical
//   - `grim -g "200,150 400x300"` writes a 600x450 PNG — logical in, native out
//
// So no rectangle in this file is ever scaled. The output *raster* is the one
// place the scale factor appears (`nativeSize`), because that is a question
// about pixels rather than about position.
//
// ## The monitor's own size is the exception, and it is reported natively
//
// `hyprctl monitors` gives `width: 1920, height: 1080, scale: 1.5` — native
// dimensions beside the factor, not logical ones. Dividing is therefore
// mandatory and `bounds()` is the only place it happens. Getting this backwards
// clamps every selection to the top-left ~44% of the screen, which reads as
// "the drag stopped working" rather than as an arithmetic error.
//
// ## The picker may select over the bar
//
// A monitor carries `reserved: [0, 44, 0, 0]` — the bar's exclusive zone. The
// bounds below deliberately ignore it: the freeze is a picture of the whole
// output, the bar is *in* that picture, and a screenshot tool that refuses to
// select the top 44 pixels of its own screenshot would be refusing the one
// region a person photographing a shell bug most wants.
//
// Imports nothing but QtQuick, so `tests/` can reach it.
import QtQuick

QtObject {
    id: policy

    // --- the shape of a rectangle --------------------------------------------

    /// A drag, as a rectangle. Both corners come from the pointer, so either
    /// may be the smaller one — dragging up-and-left is not a mistake and not
    /// a negative-width rectangle, it is the same rectangle drawn the other
    /// way round.
    ///
    /// Rounded, because the pointer arrives as a real and a region boundary
    /// that lands on a half pixel is a row of blended edge pixels in the file.
    function normalise(x0: real, y0: real, x1: real, y1: real): var {
        const left = Math.round(Math.min(x0, x1));
        const top = Math.round(Math.min(y0, y1));
        return {
            x: left,
            y: top,
            width: Math.round(Math.max(x0, x1)) - left,
            height: Math.round(Math.max(y0, y1)) - top
        };
    }

    /// A rectangle cut to fit inside another. Both edges move, so a drag that
    /// left the screen on one side keeps everything it selected on the other —
    /// clamping only the origin would slide the whole region instead of
    /// trimming it, and hand back a region the pointer never covered.
    function clamp(rect: var, bounds: var): var {
        if (!rect || !bounds)
            return policy.empty();

        const left = Math.max(bounds.x, Math.min(rect.x, bounds.x + bounds.width));
        const top = Math.max(bounds.y, Math.min(rect.y, bounds.y + bounds.height));
        const right = Math.max(bounds.x, Math.min(rect.x + rect.width, bounds.x + bounds.width));
        const bottom = Math.max(bounds.y, Math.min(rect.y + rect.height, bounds.y + bounds.height));

        return { x: left, y: top, width: right - left, height: bottom - top };
    }

    function empty(): var {
        return { x: 0, y: 0, width: 0, height: 0 };
    }

    /// The monitor's logical bounds, from what `hyprctl monitors` reports.
    ///
    /// `x`/`y` are already layout coordinates; `width`/`height` are not — see
    /// the header. A monitor with no scale reported is taken as 1 rather than
    /// as 0, which would divide the screen away entirely.
    function bounds(monitor: var): var {
        const it = monitor ?? {};
        const scale = Number(it.scale) > 0 ? Number(it.scale) : 1;
        return {
            x: Math.round(Number(it.x) || 0),
            y: Math.round(Number(it.y) || 0),
            width: Math.round((Number(it.width) || 0) / scale),
            height: Math.round((Number(it.height) || 0) / scale)
        };
    }

    // --- a drag, or a click --------------------------------------------------

    /// Below this, in either dimension, a drag was not a drag. Eight logical
    /// pixels rather than one: a press and release at the "same" place still
    /// travels two or three pixels on a trackpad, and a 3x2 screenshot is not
    /// a thing anyone meant to ask for.
    readonly property int minSide: 8

    /// Whether a rectangle is a region the user drew, as opposed to the
    /// residue of a click. The distinction is the whole of the click gesture:
    /// a click selects the window under the pointer (`hit()`), and without a
    /// floor here every click would instead capture a few stray pixels and
    /// look like the window snapping had failed.
    function isRegion(rect: var): bool {
        return !!rect && rect.width >= policy.minSide && rect.height >= policy.minSide;
    }

    // --- windows -------------------------------------------------------------

    /// The window rectangles worth snapping to, out of the compositor's
    /// toplevel list.
    ///
    /// `toplevels` is a list of `lastIpcObject`s off `Hyprland.toplevels` —
    /// taken as plain objects rather than as the live model so that this stays
    /// a function `tests/` can hand three windows to.
    ///
    /// Three filters, each of which is a window that is on the list and not on
    /// the screen:
    ///
    ///   - `mapped: false` / `hidden: true` — a window the compositor is
    ///     holding but not showing. Its rectangle is stale and snapping to it
    ///     highlights empty desktop.
    ///   - another workspace — same picture, via the more common route. The
    ///     freeze shows the *current* workspace, so every other workspace's
    ///     windows are rectangles over content they do not own.
    ///   - another monitor — the picker is per-screen, and a rectangle from
    ///     the output next door lands at coordinates inside this one.
    ///
    /// A zero-area window is dropped last: it cannot be clicked, and leaving it
    /// in makes `hit()`'s smallest-wins rule pick something unclickable.
    function windows(toplevels: var, workspaceId: var, monitorId: var): var {
        const list = toplevels ?? [];
        const wanted = Number(workspaceId);
        const onMonitor = Number(monitorId);
        const out = [];

        for (const raw of list) {
            const it = raw ?? {};
            if (it.mapped === false || it.hidden === true)
                continue;

            const workspace = it.workspace ?? {};
            if (!isNaN(wanted) && Number(workspace.id) !== wanted)
                continue;
            if (!isNaN(onMonitor) && Number(it.monitor) !== onMonitor)
                continue;

            const at = it.at ?? [];
            const size = it.size ?? [];
            const rect = {
                x: Math.round(Number(at[0]) || 0),
                y: Math.round(Number(at[1]) || 0),
                width: Math.round(Number(size[0]) || 0),
                height: Math.round(Number(size[1]) || 0),
                title: String(it.title ?? ""),
                appId: String(it.class ?? "")
            };
            if (rect.width <= 0 || rect.height <= 0)
                continue;

            out.push(rect);
        }

        return out;
    }

    /// The window under a point, or null.
    ///
    /// Smallest area wins. Hyprland's list is in focus-history order rather
    /// than stacking order, so "the one on top" is not a thing this list can
    /// answer directly — but a dialog over its parent, a floating window over a
    /// tiled one, and a tiled window over nothing are all cases where the
    /// smaller rectangle is the one in front. Where two windows genuinely
    /// overlap at the same size the answer is arbitrary, and that is a tie the
    /// user resolves by dragging instead.
    function hit(rects: var, px: real, py: real): var {
        const list = rects ?? [];
        let best = null;
        let bestArea = Infinity;

        for (const rect of list) {
            if (px < rect.x || px >= rect.x + rect.width)
                continue;
            if (py < rect.y || py >= rect.y + rect.height)
                continue;

            const area = rect.width * rect.height;
            if (area < bestArea) {
                best = rect;
                bestArea = area;
            }
        }

        return best;
    }

    // --- snapping ------------------------------------------------------------

    /// How close an edge has to come before it is taken to mean the window's
    /// edge. Twelve logical pixels — wide enough that a hand-drawn edge lands
    /// on it, narrow enough that a deliberate 20px margin around a window
    /// survives.
    readonly property int snapDistance: 12

    /// A drawn rectangle with its edges pulled onto nearby window edges.
    ///
    /// Each of the four edges is considered on its own against every candidate
    /// edge on the same axis, and the nearest within `snapDistance` wins. Per
    /// edge rather than per window, because the common ask is a region that
    /// runs from one window's left to another's right, and a whole-rectangle
    /// snap can only ever offer one window at a time.
    ///
    /// The screen's own bounds are candidates too when given: "flush with the
    /// top of the screen" is the same gesture and fails in the same annoying
    /// way without help.
    ///
    /// Snapping never *grows* a rectangle past the bounds, because the caller
    /// clamps afterwards — this returns intent, and `clamp()` returns legality.
    function snap(rect: var, rects: var, bounds: var): var {
        if (!rect)
            return policy.empty();

        const verticals = [];
        const horizontals = [];

        for (const other of (rects ?? [])) {
            verticals.push(other.x, other.x + other.width);
            horizontals.push(other.y, other.y + other.height);
        }
        if (bounds) {
            verticals.push(bounds.x, bounds.x + bounds.width);
            horizontals.push(bounds.y, bounds.y + bounds.height);
        }

        const left = policy.nearest(rect.x, verticals);
        const right = policy.nearest(rect.x + rect.width, verticals);
        const top = policy.nearest(rect.y, horizontals);
        const bottom = policy.nearest(rect.y + rect.height, horizontals);

        // A snap that collapses the region is a snap refused: both edges of a
        // narrow selection can find the same candidate, and a zero-width
        // rectangle is not what the drag asked for.
        const x = left, w = right - left;
        const y = top, h = bottom - top;
        if (w < policy.minSide || h < policy.minSide)
            return { x: rect.x, y: rect.y, width: rect.width, height: rect.height };

        return { x: x, y: y, width: w, height: h };
    }

    /// The nearest candidate to a value, or the value itself when none is close
    /// enough.
    function nearest(value: real, candidates: var): real {
        let best = value;
        let bestGap = policy.snapDistance + 1;

        for (const candidate of (candidates ?? [])) {
            const gap = Math.abs(candidate - value);
            if (gap < bestGap) {
                best = candidate;
                bestGap = gap;
            }
        }

        return Math.round(best);
    }

    // --- where it lands ------------------------------------------------------

    /// The directory screenshots are written to.
    ///
    /// `~` is expanded here rather than left to the shell, because nothing on
    /// this path goes through a shell — `Process` takes an argv, and a literal
    /// `~/Pictures` would become a directory called `~` in the home directory,
    /// which is the kind of bug that is only ever found much later.
    function directory(configured: var, home: string): string {
        const set = String(configured ?? "").trim();
        if (set === "")
            return home + "/Pictures/Screenshots";
        if (set === "~")
            return home;
        if (set.startsWith("~/"))
            return home + set.slice(1);
        return set;
    }

    /// The timestamp in a file name. Sortable, and free of the two characters
    /// that make a name hostile to type: `:` (legal on Linux, but it is a path
    /// separator to enough tools to matter) and a space.
    function stamp(date: var): string {
        const d = date instanceof Date ? date : new Date();
        const pad = n => (n < 10 ? "0" : "") + n;
        return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
            + "T" + pad(d.getHours()) + "-" + pad(d.getMinutes()) + "-" + pad(d.getSeconds());
    }

    function filename(date: var): string {
        return "forest-" + policy.stamp(date) + ".png";
    }

    function path(dir: string, name: string): string {
        const base = String(dir ?? "");
        return (base.endsWith("/") ? base.slice(0, -1) : base) + "/" + name;
    }

    /// The output raster for a region — the one place a scale factor belongs.
    ///
    /// The region is logical; the freeze on disk is native; a grab that asked
    /// for the logical size would resample a 1.5x screenshot down to 1x and
    /// hand back a soft picture of a sharp screen.
    function nativeSize(rect: var, scale: real): var {
        const factor = Number(scale) > 0 ? Number(scale) : 1;
        return {
            width: Math.max(1, Math.round((rect?.width ?? 0) * factor)),
            height: Math.max(1, Math.round((rect?.height ?? 0) * factor))
        };
    }

    // --- the tools -----------------------------------------------------------

    /// Freezing the screen: a whole-output capture to a scratch file.
    ///
    /// `grim` and not `ScreencopyView`. The ticket asks for the latter and it
    /// is the right shape — a live texture with no subprocess — but measured
    /// against upstream Quickshell 0.3.0 on Hyprland 0.56.1 it never produces a
    /// frame: `hasContent` stays false and `sourceSize` stays `-1x-1` forever,
    /// in live mode and after an explicit `captureFrame()`, with
    /// `zwlr_screencopy_manager_v1`, `ext_image_copy_capture_manager_v1` and
    /// `ext_output_image_capture_source_manager_v1` all advertised by the
    /// compositor and the scene graph rendering normally. Nothing is logged
    /// when this happens, which is the dangerous part: a picker built on it
    /// shows a transparent overlay and looks like a styling bug.
    ///
    /// `-c` is absent deliberately: the cursor is over the picker, not over the
    /// thing being photographed, so including it would draw a pointer that was
    /// never there.
    function freezeArgv(output: string, file: string, override: var): var {
        const custom = String(override ?? "").trim();
        if (custom !== "")
            return ["sh", "-c", custom + " \"$1\"", "sh", String(file ?? "")];
        return ["grim", "-o", String(output ?? ""), String(file ?? "")];
    }

    /// How long the freeze gets before the shell gives up on it, in ms.
    ///
    /// This is not defensive padding. Inside the nested Hyprland that seam 2
    /// runs in, `grim` does not fail — it *hangs*, because it asks for a
    /// screencopy frame and that compositor never presents one after its first
    /// commit (#85, hyprwm/aquamarine#348). Without a deadline the picker sits
    /// in a state that is neither open nor closed, logging nothing, and every
    /// later press answers "already open" forever. Three seconds is ~60x the
    /// ~50ms a real capture takes.
    readonly property int freezeTimeoutMs: 3000

    function freezeTimedOut(): string {
        return "grim did not answer in " + policy.freezeTimeoutMs
            + "ms — giving up on the freeze rather than hanging the picker";
    }

    /// Putting an image on the Wayland clipboard.
    ///
    /// Quickshell owns the selection for *text* — `Quickshell.clipboardText` is
    /// writable and needs no subprocess — but it is a `QString` property and
    /// there is no image equivalent in 0.3.0. An image selection therefore
    /// needs `wl-copy`, which is a real dependency and not present on this
    /// machine; `Screenshot.qml` probes for it and falls back to putting the
    /// *path* on the clipboard, which is at least pasteable into a terminal.
    ///
    /// Run through `sh -c` for the redirection: `wl-copy` reads the image from
    /// stdin, and it daemonises itself to keep serving the selection after this
    /// process exits, which is exactly the behaviour wanted here.
    function copyArgv(file: string): var {
        return ["sh", "-c", "wl-copy --type image/png < \"$1\"", "wl-copy", String(file ?? "")];
    }

    /// Handing the shot to an editor. Optional by design: the ticket asks for
    /// `swappy` "when installed", so an absent editor is a normal outcome and
    /// not a failure — see `editorAbsent()` for what the log says about it.
    function editorArgv(tool: string, file: string): var {
        return [String(tool ?? ""), "-f", String(file ?? "")];
    }

    /// Whether a tool name is one this shell will actually run. Empty means the
    /// user turned the handoff off, which is a different thing from a tool that
    /// is configured and missing, and the two get different log lines.
    function wants(tool: var): bool {
        return String(tool ?? "").trim() !== "";
    }

    // --- what a harness reads ------------------------------------------------
    //
    // A line per state change with the reason in it (#81, and CLAUDE.md's rule).
    // "The picker did not open" has four causes — no compositor, the freeze
    // failed, it was already open, or it opened and drew nothing — and without
    // these they are one picture.

    function opened(screen: string, windowCount: int): string {
        return "picker opened on " + screen + " (" + windowCount
            + (windowCount === 1 ? " window" : " windows") + " to snap to)";
    }

    function alreadyOpen(): string {
        return "picker already open — ignoring open";
    }

    function cancelled(reason: string): string {
        return "picker cancelled (" + (reason !== "" ? reason : "request") + ")";
    }

    function froze(file: string): string {
        return "froze the screen to " + file;
    }

    function freezeFailed(code: int): string {
        return "grim failed (exit " + code + ") — no freeze, so no picker";
    }

    function freezeMissing(): string {
        return "grim is not installed — the region picker needs it to freeze the screen";
    }

    function selected(rect: var, how: string): string {
        return "selected " + rect.width + "x" + rect.height
            + " at " + rect.x + "," + rect.y + " (" + how + ")";
    }

    function tooSmall(rect: var): string {
        return "selection " + rect.width + "x" + rect.height
            + " is under " + policy.minSide + "px — nothing under the pointer to fall back to";
    }

    function saved(file: string, size: var): string {
        return "saved " + size.width + "x" + size.height + " to " + file;
    }

    function saveFailed(file: string): string {
        return "could not write " + file;
    }

    function copied(file: string): string {
        return "copied the image to the clipboard (" + file + ")";
    }

    /// The degraded clipboard. Named rather than silent, because a person who
    /// pressed the key and then pressed paste needs to know they have a path
    /// and not a picture — and needs to be told what to install.
    function copiedPathInstead(file: string): string {
        return "wl-copy is not installed — put the path on the clipboard instead of the image ("
            + file + ")";
    }

    function handedOff(tool: string, file: string): string {
        return "handed " + file + " to " + tool;
    }

    function editorAbsent(tool: string): string {
        return tool + " is not installed — skipping the edit handoff";
    }

    function editorOff(): string {
        return "no editor configured — skipping the edit handoff";
    }

    /// The clipboard turned off in settings, which is not the same statement as
    /// a clipboard that failed.
    function clipboardOff(): string {
        return "clipboard copy is off — leaving the selection alone";
    }

    /// `wl-copy` ran and came back non-zero. Logged from its `onExited` and not
    /// from the moment it was spawned: a copy reported at spawn time is a copy
    /// reported before it can have failed.
    function copyFailed(code: int): string {
        return "wl-copy failed (exit " + code + ") — the image is not on the clipboard";
    }

    function copyProbed(): string {
        return "wl-copy is not installed — screenshots will put their path on "
            + "the clipboard rather than the image";
    }

    /// The fourth cause of "the picker did not open", and the one the header
    /// claims to enumerate — so it belongs here with the other three rather
    /// than as a string in the service.
    function noMonitor(): string {
        return "no focused monitor — nothing to photograph";
    }

    function directoryFailed(code: int): string {
        return "could not make the screenshot directory (exit " + code
            + ") — not opening the picker";
    }

    function armed(): string {
        return "screenshot picker armed (ipc target: screenshot)";
    }

    function windowBuilt(screen: string): string {
        return "picker window built on " + screen;
    }
}
