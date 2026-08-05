// Where the bar's input strip is on its screen, and what a drawer has to
// subtract from its own input mask to leave that strip reachable (#199).
//
// #187 made a click on the bar reach the bar while a drawer is open, and did it
// with geometry alone: the bar reserves an exclusive zone, the drawer is
// `ExclusionMode.Normal`, so the compositor lays the fog out *below* the strip
// and there is nothing to arrange. That mechanism has one hole in it, and the
// hole is exactly an auto-hiding bar — which reserves nothing by definition, so
// there is no strip for the fog to stop at and the fog covers the bar. Two
// `WlrLayer.Top` surfaces are ordered by map order and the drawer maps second,
// so the revealed bar is underneath it and every row of #187's table fails
// again.
//
// What replaces geometry there is a hole in the drawer's input region over the
// bar's current rect. This file is the arithmetic for both halves of that: the
// rect the bar publishes (`stripRect`), and the hole the drawer subtracts
// (`cutout`). Both are decisions rather than pictures, so they live here where
// tests/ can reach them — the surfaces on the other side are
// Surfaces/Bar/Bar.qml and Surfaces/Drawers/DrawerWindow.qml, which import
// Quickshell and so cannot be loaded by qmltestrunner.
//
// Pure functions, no Quickshell imports.
import QtQuick

QtObject {
    id: root

    /// Everything `stripRect` reads, built in one call so the bar cannot
    /// assemble half of it from one frame and half from another — the same
    /// reason Surfaces/Bar/BarVisibilityPolicy.qml takes a context.
    ///
    /// `reserves` is that file's own `reservesSpace` answer, carried rather
    /// than recomputed: a strip that reserves space needs no hole at all, and
    /// two files disagreeing about which case this is would be the bug.
    function context(atTop: bool, revealed: bool, reserves: bool, barHeight: int,
                     floating: bool, marginH: int, marginV: int,
                     screenW: int, screenH: int): var {
        return {
            atTop: atTop,
            revealed: revealed,
            reserves: reserves,
            barHeight: barHeight,
            floating: floating,
            marginH: marginH,
            marginV: marginV,
            screenW: screenW,
            screenH: screenH
        };
    }

    /// The bar's input rect in *screen* coordinates — what its own mask covers,
    /// not what its window spans.
    ///
    /// The two differ, and the difference is the whole point of an auto-hiding
    /// bar: the window keeps its full height while hidden and masks itself down
    /// to the one-pixel reveal strip along the screen edge (`revealStrip` in
    /// Bar.qml). So a hidden bar's rect is that one pixel, and a revealed one's
    /// is the whole band. Both are reported honestly; whether either is worth
    /// cutting a hole for is `cutout`'s decision, not this one's.
    function stripRect(ctx: var): var {
        const marginH = ctx.floating ? Math.max(0, ctx.marginH) : 0;
        const marginV = ctx.floating ? Math.max(0, ctx.marginV) : 0;

        const band = Math.max(0, ctx.barHeight);
        // A zero-height bar has no reveal strip either — `Math.min` rather than
        // a flat 1 so "there is no bar" cannot produce a pixel of one.
        const height = ctx.revealed ? band : Math.min(1, band);

        const x = marginH;
        const width = Math.max(0, ctx.screenW - 2 * marginH);

        // Both cases fall out of one expression: the strip is anchored to the
        // window's top edge when the bar is at the top and to its bottom edge
        // when it is not, and the window's own edges are the screen's inset by
        // the float margin.
        const y = ctx.atTop ? marginV
                            : Math.max(0, ctx.screenH - marginV - height);

        return {
            x: x, y: y, width: width, height: height,
            reserves: ctx.reserves,
            revealed: ctx.revealed
        };
    }

    /// The hole a drawer window subtracts from its input mask, in that window's
    /// own coordinates. A zero rect means "punch nothing".
    ///
    /// Four of the five answers are zero, and each is a case where a hole would
    /// be wrong rather than merely unnecessary:
    ///
    /// - No strip published for this screen. A screen with no bar on it, or one
    ///   whose bar has not mapped yet.
    /// - The strip reserves space. #187's geometry already applies: the fog is
    ///   laid out below the bar and never overlapped it, so a hole here would
    ///   punch through fog that is somewhere else entirely.
    /// - **The bar is not showing.** There is nothing behind the fog to reach:
    ///   the bar's own dismiss handler lives inside `content`, which is parked
    ///   outside the window while the bar is away, so a hole cut over the reveal
    ///   strip would land on a surface with nothing in it — a row of the band
    ///   that neither acts nor dismisses. #199's second acceptance criterion
    ///   asks the opposite of that in as many words: with the bar hidden, a
    ///   click where the bar would be reaches the fog and dismisses. So the
    ///   whole band stays fog, and that is also how the bar comes back — the
    ///   click puts the drawer away, and hovering the edge works again the
    ///   moment there is no fog over it.
    /// - The drawer window is not the size of its screen. Something reserved an
    ///   exclusive zone — another bar, a dock, a panel that is not ours — so the
    ///   window's origin is offset from the screen's by an amount this file
    ///   cannot see, and a screen-coordinate rect would land in the wrong place.
    ///   Refusing is the honest answer: it degrades to the behaviour before
    ///   #199 rather than cutting a hole somewhere nobody asked for.
    function cutout(strip: var, windowW: int, windowH: int,
                    screenW: int, screenH: int): var {
        const none = { x: 0, y: 0, width: 0, height: 0 };

        if (!strip)
            return none;
        if (strip.reserves)
            return none;
        if (!strip.revealed)
            return none;
        if (windowW !== screenW || windowH !== screenH)
            return none;

        const x = Math.max(0, Math.min(strip.x, windowW));
        const y = Math.max(0, Math.min(strip.y, windowH));
        const width = Math.max(0, Math.min(strip.width, windowW - x));
        const height = Math.max(0, Math.min(strip.height, windowH - y));

        if (width <= 0 || height <= 0)
            return none;

        return { x: x, y: y, width: width, height: height };
    }

    /// The registry map with one screen's strip set, and with it removed.
    ///
    /// Both return a *new* map rather than editing the one they were given. A
    /// property bound to `strips[name]` does not re-evaluate when a key inside
    /// the object changes, and the drawer's input mask is exactly such a
    /// binding — this is the QML binding trap #50 measured three of. Doing it
    /// here rather than in the singleton next door is what puts it within reach
    /// of tests/: Core/BarStrips.qml imports Quickshell and qmltestrunner
    /// cannot load it.
    function withStrip(strips: var, screenName: string, strip: var): var {
        const next = {};
        for (const name in (strips || {}))
            next[name] = strips[name];
        next[screenName] = strip;
        return next;
    }

    function withoutStrip(strips: var, screenName: string): var {
        const next = {};
        for (const name in (strips || {})) {
            if (name !== screenName)
                next[name] = strips[name];
        }
        return next;
    }

    function isEmpty(rect: var): bool {
        return !rect || rect.width <= 0 || rect.height <= 0;
    }

    /// What the drawer logs when the hole changes, so seam 2 can assert on the
    /// hole itself rather than only on what a click did afterwards. #187's
    /// lesson was that a click test which passes for the wrong reason is worse
    /// than none: the verb was never the broken part.
    function cutoutLine(screenName: string, rect: var): string {
        if (root.isEmpty(rect))
            return "no bar cutout on " + screenName;
        return "bar cutout on " + screenName + ": "
             + rect.width + "×" + rect.height + "+" + rect.x + "+" + rect.y;
    }
}
