// The sidebar mini-month's arithmetic: which of its cells the grid beside it is
// currently showing, and what the seven letters above them say.
//
// The grid of days itself is `MonthPolicy.grid` — the mini-month draws exactly
// the same six-by-seven shape the month view does, and drawing it from a second
// source would be the place the two calendars start disagreeing about which
// September the 1st is.
//
// ## Why the band is a range and not a per-cell flag
//
// The mini-month's job is to answer "where am I?" at a glance, and the answer in
// a week view is *a week*, not seven separate days. A row of seven independently
// highlighted cells reads as seven selections; one rounded band reads as one
// period. So the policy returns the first and last column the band covers and
// the surface draws a single rectangle — which is also the only way the rounded
// ends land on the outside of the run rather than around every cell.
//
// ## Why the month view gets no band
//
// A band over all thirty-one days is not a highlight; it is a second background.
// In a month view the mini-month is already showing the month the grid is
// showing, and the heading above it says so in words. The honest answer is no
// band, and the anchor day keeps its ring so the eye still has somewhere to
// land.
//
// ## Why two letters
//
// One letter was the first pass, on the argument that a fixed seven-column grid
// tells the columns apart by position. It does — but only for someone who has
// already worked out which end the week starts at, and `S M T W T F S` gives no
// way to work that out: both Ts and both Ss are the same glyph, so the row is
// ambiguous exactly where the reader needs it. Two letters resolve it and cost
// nothing — at a 30px cell pitch "We" and "W" set in the same column with room
// to spare, so this is width the header already had.
pragma ComponentBehavior: Bound
import QtQuick
import "../../Services/Calendar"

QtObject {
    id: policy

    property MonthPolicy month: MonthPolicy {}
    property CalendarFormat format: CalendarFormat {}
    property CalendarTime time: CalendarTime {}

    /// The seven column labels, in display order for `firstDay`.
    ///
    /// Two letters, and mixed case rather than the caps the week view's own
    /// header uses: this row sits directly over numerals at nearly the same
    /// size, and caps at that pitch compete with the terrain instead of
    /// labelling it. See the header for why the second letter is not optional.
    function initials(firstDay: int): var {
        return policy.format.weekdayShort(firstDay).map(name => name.slice(0, 2));
    }

    /// Which columns of `row` the view beside the sidebar is currently showing,
    /// as `{ start, end }` inclusive, or `null` for none.
    ///
    /// `row` is one row of `MonthPolicy.grid` — seven cells, each with an `iso`.
    /// The three views answer differently on purpose:
    ///
    /// - `day` — the one cell whose date is the anchor, so the band is a circle.
    /// - `week` — the whole row, when the row is the anchor's week. The grid's
    ///   rows are weeks aligned to the same `firstDay` the week view uses, so
    ///   "the row containing the anchor" and "the anchor's week" are the same
    ///   seven days; there is no partial week to bound.
    /// - `month` — nothing. See the header.
    ///
    /// A row from a neighbouring month may hold the anchor in its corner cells
    /// (the 1st of September sitting in August's last row), and that is a real
    /// band: those days are genuinely on screen in the week view.
    function band(row: var, view: string, anchorIso: string): var {
        if (!row || row.length === 0 || !policy.time.isDay(anchorIso))
            return null;
        if (view === "month")
            return null;

        let hit = -1;
        for (let i = 0; i < row.length; i++) {
            if (row[i] && row[i].iso === anchorIso) {
                hit = i;
                break;
            }
        }
        if (hit < 0)
            return null;
        if (view === "day")
            return { "start": hit, "end": hit };
        return { "start": 0, "end": row.length - 1 };
    }

    /// Whether `iso` falls inside a band this row already carries — what a cell
    /// asks to decide whether its numeral is a full-strength one.
    function inBand(row: var, view: string, anchorIso: string, column: int): bool {
        const range = policy.band(row, view, anchorIso);
        return !!range && column >= range.start && column <= range.end;
    }

    /// The month the mini-month should be showing when the grid is anchored on
    /// `iso`, as any day inside it. Its own steppers move this without moving
    /// the grid, so the surface holds it as state and only re-snaps when the
    /// anchor lands in a different month — paging the sidebar to December and
    /// then clicking a day in the *week* view should not throw the sidebar back
    /// to August.
    function snapMonth(displayIso: string, anchorIso: string): string {
        if (!policy.time.isDay(anchorIso))
            return displayIso;
        if (!policy.time.isDay(displayIso))
            return anchorIso;
        return displayIso.slice(0, 7) === anchorIso.slice(0, 7) ? displayIso : anchorIso;
    }

    /// One month forward or back from `iso`, day clamped — `MonthPolicy`'s
    /// clamp, borrowed rather than restated so the sidebar's steppers and the
    /// toolbar's chevrons cannot land on different days.
    function step(iso: string, delta: int): string {
        return policy.month.shiftMonths(iso, delta);
    }

    // --- the calendar list ---------------------------------------------------

    /// The sidebar's calendar rows: every hue on the wheel, in wheel order, as
    /// `{ index, name, label }`.
    ///
    /// The label is the hue's own name title-cased. This is the honest state of
    /// the surface today — there are no calendar *accounts* to name yet, and a
    /// list of invented ones ("Work", "Birthdays") would be a picture of
    /// something that does not exist. When accounts arrive they bring their own
    /// names and this function takes the store instead of the wheel.
    function rows(hues: var): var {
        const names = (hues && hues.names) ? hues.names : [];
        const out = [];
        for (let i = 0; i < names.length; i++) {
            const name = names[i];
            out.push({
                "index": i,
                "name": name,
                "label": name.charAt(0).toUpperCase() + name.slice(1)
            });
        }
        return out;
    }
}
