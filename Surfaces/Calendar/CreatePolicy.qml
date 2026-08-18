// Where a new event lands when it is asked for from the chrome rather than
// dragged onto the grid.
//
// ## Why this is a decision and not a constant
//
// A `+` in the sidebar has no y coordinate to read a time off, so something has
// to choose one, and "09:00" is only right on a day that is not today. On today
// the useful answer is *next*, not *morning*: the reason to press a create
// button at 13:40 is almost never to schedule something that already started.
//
// So: the next snap boundary after now when the day in view is today, and the
// start of the working day on any other day. Both are guesses, and both are
// guesses the user immediately corrects by dragging the chip — the point is
// that the chip lands somewhere they can see it, which a 09:00 event on a grid
// scrolled to the afternoon does not.
//
// ## Why it clamps
//
// An event created at 23:55 would run past midnight, and this store has no
// concept of an event that spans days. The last start that fits a whole hour is
// what a late press gets, which is visibly wrong in the right direction — the
// chip is on screen at the bottom of today rather than absent.
pragma ComponentBehavior: Bound
import QtQuick

QtObject {
    id: policy

    /// Minutes after midnight for a new event on `anchorIso`.
    ///
    /// `nowMin` is minutes after midnight *now*, and `snapMin` the grid's own
    /// snap (15), so a chip made from the button lands on the same rules a chip
    /// dragged out by hand does — two create paths that disagreed about where
    /// 13:47 rounds to would be two calendars.
    function startMinute(anchorIso: string, todayIso: string, nowMin: int,
                         snapMin: int, minutes: int): int {
        const snap = snapMin > 0 ? snapMin : 15;
        const length = minutes > 0 ? minutes : 60;
        const latest = 24 * 60 - length;
        if (anchorIso !== todayIso || !todayIso)
            return Math.max(0, Math.min(policy.dayStart, latest));
        const next = Math.ceil((Math.max(0, nowMin) + 1) / snap) * snap;
        return Math.max(0, Math.min(next, latest));
    }

    /// 09:00 — the top of the working day, and the row the week view scrolls to
    /// when it opens, so a chip created on another day is inside the first
    /// screenful rather than above it.
    readonly property int dayStart: 9 * 60

    // --- where the quick-create panel goes ------------------------------------
    //
    // The panel belongs *beside* the chip it was made from, because the chip is
    // what the eye is on when the mouse comes up and a panel that covered it
    // would hide the thing being named. "Beside" is a decision with three parts
    // and every one of them is arithmetic, which is why it is here and not in
    // the popover:
    //
    //   - **side.** To the right of the chip by default. A chip in Saturday has
    //     no room on its right, so the panel flips to the left — and a grid
    //     narrower than the panel plus both gaps has no room on either side, so
    //     it gives up on "beside" and clamps, which is the only case where it
    //     overlaps the chip.
    //   - **top.** Aligned with the chip's own top edge, so the title field
    //     lands on the line the event starts at. A short chip near the bottom
    //     of the grid would push the panel off, so the top slides up just far
    //     enough to fit.
    //   - **margin.** Never flush against the view's edge: a panel whose shadow
    //     is clipped by the window reads as a panel that is half off screen.
    //
    // Flipping and clamping are separate on purpose. Clamping alone would slide
    // a panel over its own chip rather than putting it on the other side, and
    // the resulting picture — panel on top of the event it describes — is the
    // one Notion ships on a narrow window.

    /// Top-left corner for a panel of `panelW` x `panelH` beside `anchor`
    /// (`{x, y, width, height}`), inside a `boundsW` x `boundsH` box.
    ///
    /// `gap` is the air between chip and panel, `margin` the air the panel
    /// keeps from the view's own edges. Both fall back rather than propagating
    /// a zero, so a caller that has not measured yet still gets a placement
    /// that is on screen.
    function popoverAnchor(anchor: var, panelW: real, panelH: real,
                           boundsW: real, boundsH: real,
                           gap: real, margin: real): var {
        const a = anchor || {};
        const ax = isFinite(a.x) ? a.x : 0;
        const ay = isFinite(a.y) ? a.y : 0;
        const aw = a.width > 0 ? a.width : 0;
        const g = gap >= 0 ? gap : 8;
        const m = margin >= 0 ? margin : 8;

        const right = ax + aw + g;
        const left = ax - g - panelW;
        // Preferred first, the flip second, the clamp last. `right` wins
        // whenever the whole panel fits; `left` only when it fits *and* right
        // did not, so a panel never crosses to the cramped side for the sake of
        // a pixel.
        let x = right;
        if (right + panelW + m > boundsW)
            x = left >= m ? left : right;
        x = Math.max(m, Math.min(x, Math.max(m, boundsW - panelW - m)));

        let y = ay;
        y = Math.max(m, Math.min(y, Math.max(m, boundsH - panelH - m)));

        // Where the caret goes, in the panel's own coordinates: the anchor's
        // vertical centre, clamped so the point never runs off a rounded
        // corner. A caret is a *claim* about which chip the panel belongs to,
        // and a caret sitting on the corner radius points at nothing — so a
        // panel that had to slide away from its chip gets a caret at the
        // nearest end rather than a caret half off the edge.
        const ah = a.height > 0 ? a.height : 0;
        const inset = 12;
        const centre = ay + ah / 2 - y;
        const caretY = Math.max(inset, Math.min(centre, Math.max(inset, panelH - inset)));
        return { "x": x, "y": y, "flipped": x < ax, "caretY": caretY };
    }
}
