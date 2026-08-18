// Which of the eight event hues an event wears.
//
// The colours themselves are in `CalendarTokens.qml`, which is where a Theme
// import is allowed; this file holds only the *choice*, so it stays a pure
// QtObject that `tests/tst_huepolicy.qml` can load offscreen.
//
// Two things have to be true of that choice and neither is obvious:
//
// 1. **An event with no colour still has to get one.** The fixture events all
//    carry `colour: ""` and so will most real ones — nobody picks a colour for
//    a meeting they accepted. A week of eight grey chips is a worse picture
//    than a week of eight arbitrary but *stable* ones, so an uncoloured event
//    is hashed onto the wheel by its id.
// 2. **The same event must get the same hue on every run.** The hash is over
//    the id, which is `evt-3` forever, and not over an array index, a load
//    order or an insertion time — any of which would repaint the whole week
//    when one event is deleted and would make two captures of the same fixture
//    two different pictures.
// 3. **The hash never hands out grey.** See `autoCount`: grey is a status in
//    every calendar anyone has used, so it cannot also be the colour a coin
//    toss gives an ordinary meeting.
pragma ComponentBehavior: Bound
import QtQuick

QtObject {
    id: policy

    /// The wheel, in order. The index into this array is the hue's identity
    /// everywhere else: `CalendarTokens` indexes its three colour tables by it,
    /// and a stored `colour` is one of these names.
    readonly property var names: [
        "glacier", "moss", "lamplight", "ember", "lake", "lichen", "heather", "stone"
    ]

    readonly property int count: policy.names.length

    /// How many of them the **hash** may hand out. Seven, not eight: `stone` is
    /// the grey one, and grey is not a colour in a calendar — it is a status.
    /// Every calendar the reader has used paints a declined or tentative event
    /// grey, so an event that was auto-coloured grey is an event wearing a
    /// meaning nobody gave it. It stays on the wheel because a person may pick
    /// it, and it stays last so picking it by index does not move anything else.
    readonly property int autoCount: policy.count - 1

    /// A stable non-negative hash of a string. djb2, kept here rather than
    /// pulled from anywhere clever because the only property that matters is
    /// that it never changes — an implementation someone might "improve" would
    /// repaint every calendar in the world.
    ///
    /// `>>> 0` after each step keeps the value in 32 unsigned bits: QML numbers
    /// are doubles, and a djb2 left to run past 2^53 stops being the same hash
    /// on the next character.
    function hash(text: string): int {
        let h = 5381;
        const s = String(text === undefined || text === null ? "" : text);
        for (let i = 0; i < s.length; i++)
            h = (((h * 33) >>> 0) ^ s.charCodeAt(i)) >>> 0;
        return h >>> 0;
    }

    /// The hue index for a stored `colour` and an id, always `0..count-1`.
    ///
    /// A named colour wins, case-insensitively. An out-of-range or unknown
    /// name does **not** fall back to hue 0 — that would quietly make every
    /// typo glacier and hide the typo — it falls through to the id hash, which
    /// at least keeps two mistyped events apart.
    ///
    /// A numeric string is accepted too (`"3"`), because a colour picker that
    /// stores an index is the obvious next thing someone writes and refusing it
    /// would be a silent all-glacier calendar.
    function indexFor(colour: string, id: string): int {
        const name = String(colour === undefined || colour === null ? "" : colour).trim().toLowerCase();
        if (name.length > 0) {
            const named = policy.names.indexOf(name);
            if (named >= 0)
                return named;
            if (/^[0-9]+$/.test(name)) {
                const n = parseInt(name, 10);
                if (n >= 0 && n < policy.count)
                    return n;
            }
        }
        return policy.hash(id) % policy.autoCount;
    }

    /// The same question asked of a whole event, which is what a surface has in
    /// its hand. A missing event is hue 0 rather than an exception: the caller
    /// is a delegate mid-rebuild, and a thrown TypeError there costs the whole
    /// column.
    function forEvent(event: var): int {
        if (!event)
            return 0;
        return policy.indexFor(event.colour, event.id);
    }

    // --- keeping neighbours apart ---------------------------------------------
    //
    // A hash spreads evenly over the *wheel*, which is not the same as spreading
    // evenly over the *eye*. The fixture's Tuesday drew `ember` beside
    // `lamplight` — 15° and 30° on the colour circle, two chips that touch, and
    // at the low chroma these fills sit at they were reported as one colour with
    // a rendering glitch down the middle. Hue is only information while two hues
    // are different; two indistinguishable ones are worse than one, because the
    // reader spends a beat deciding whether they mean the same thing.
    //
    // So a *day* of chips is checked for perceptual collisions and the collider
    // is rotated. A day and not an overlap cluster: chips that overlap touch
    // side to side, but a 2 pm meeting ending where a 3 pm one begins touches
    // too — the fixture's Thursday drew that pair a family apart, one column,
    // two chips, one apparent colour — and a day is the unit the eye compares
    // in a glance. Three properties are held on purpose:
    //
    //   - **the hash still decides.** A hue only moves when it collides, so most
    //     events keep the colour they always had.
    //   - **an explicit colour never moves.** Someone chose it; a policy that
    //     overrode a choice to improve a picture would be lying about the data.
    //   - **it is per day, not per week.** Spreading a whole week would repaint
    //     Friday because something moved on Monday, and two chips four columns
    //     apart were never going to be confused with each other.

    /// Where each hue sits on the colour circle, in degrees, measured off the
    /// dark bar inks in `CalendarTokens`. `stone` is the grey one and has no
    /// meaningful angle; it is parked at -1 and treated as far from everything,
    /// which is true — a desaturated chip is never confusable with a saturated
    /// one whatever their hues.
    readonly property var angles: [185, 95, 30, 15, 210, 70, 275, -1]

    /// Two hues closer than this on the circle are one colour to the reader at
    /// chip size and chip chroma. 45 is the measured gap: `ember` to
    /// `lamplight` is 15 and was called indistinguishable; `lichen` to `moss`
    /// is 25 and is the next pair down; `moss` to `glacier` is 90 and nobody
    /// has ever confused them.
    readonly property int minSeparationDeg: 45

    /// The angular distance between two hues, or a large number when either is
    /// the grey.
    function separation(a: int, b: int): real {
        const x = policy.angles[a % policy.count];
        const y = policy.angles[b % policy.count];
        if (x < 0 || y < 0)
            return 360;
        const d = Math.abs(x - y) % 360;
        return Math.min(d, 360 - d);
    }

    /// Hues for one day of events, in the order they were given:
    /// `[hueIndex, ...]`, the same length as `events`.
    ///
    /// A colliding auto-hue is rotated by +3 at a time — 3 is coprime with the
    /// seven the hash may hand out, so the rotation visits every one of them
    /// before repeating, and the first clear hue wins. If the day is busy
    /// enough that no hue is clear — five or more chips, where the wheel simply
    /// runs out of 45° gaps — the hash's own answer stands: a repeated colour is
    /// a smaller lie than a colour chosen by how far the loop happened to get.
    function spread(events: var): var {
        const list = events || [];
        const out = [];
        const taken = [];
        for (let i = 0; i < list.length; i++) {
            const event = list[i];
            const base = policy.forEvent(event);
            const fixed = !!(event && event.colour
                             && String(event.colour).trim().length > 0);
            let hue = base;
            if (!fixed) {
                for (let step = 0; step < policy.autoCount; step++) {
                    const candidate = (base + step * 3) % policy.autoCount;
                    let clear = true;
                    for (let t = 0; t < taken.length; t++) {
                        if (policy.separation(candidate, taken[t])
                            < policy.minSeparationDeg) {
                            clear = false;
                            break;
                        }
                    }
                    if (clear) {
                        hue = candidate;
                        break;
                    }
                }
            }
            taken.push(hue);
            out.push(hue);
        }
        return out;
    }

    // --- how strong a hue reads as a chip body ---------------------------------

    /// The alpha a hue is laid over `Theme.surface` at to become a chip's fill.
    ///
    /// This is the one number that decides how heavy every chip in the window
    /// looks, so it lives here — pure, tested, and read by `CalendarTokens`
    /// rather than restated by it. An earlier pass wrote the eight fills out as
    /// hex in three places' worth of tables and they drifted: the week's tint
    /// and the month's were solved separately and no longer agreed, which is
    /// exactly the failure a single source exists to stop.
    ///
    /// 0.16 in dark and 0.12 in light are the design spec's, and they are not
    /// arbitrary: at those alphas the eight bars land on the spec's own fill
    /// table to the byte, and every ink stays ≥7:1 on its fill in both modes —
    /// well past the 4.5 AA asks and past the 6 this surface solves at, because
    /// a chip prints pt(11) type whose antialiased edges measure below the
    /// computed ratio.
    ///
    /// What carries the chip's *edge* at these alphas is not the fill: it is
    /// the 3px bar in the hue and the 1px hue hairline around it
    /// (`CalendarTokens.chipBorder`). A fill strong enough to be its own edge is
    /// a fill that has stopped being a tint, which is the reference this surface
    /// is measured against.
    readonly property real tintAlphaDark: 0.16
    readonly property real tintAlphaLight: 0.12

    function tintAlpha(dark: bool): real {
        return dark ? policy.tintAlphaDark : policy.tintAlphaLight;
    }

    /// The **banner** alpha, and the reason it is a second number rather than a
    /// second opinion about the first.
    ///
    /// `tintAlpha` is solved for a chip drawn *among other tinted chips*: at
    /// 0.16 a chip is one step from its neighbours, which is all it needs when
    /// the neighbours are the same kind of object. A month banner is the only
    /// filled thing in its grid — every timed event beside it is an unfilled
    /// line — so its step is not against a neighbour but against the bare cell
    /// under it, and 0.16 against a cell measured as a smudge rather than a
    /// pill: the shape that carries the whole "this owns the day" statement was
    /// the faintest object in the picture.
    ///
    /// 0.26 dark and 0.22 light are where the fill closes into a shape with an
    /// edge of its own, which is what lets the banner drop the hairline it used
    /// to need. The reference's all-day fill sits in the same place — roughly a
    /// quarter of the calendar's own colour over the page.
    ///
    /// **The ceiling is the ink, and it is a measurement, not a taste.**
    /// Computed over all eight hues against `surfaceRaised` in both palettes,
    /// the worst ink lands at 6.22:1 dark and 6.35:1 light — clear of the 6:1
    /// this surface solves at, which is itself past 4.5 because a chip prints
    /// pt(11) type whose antialiased edges measure below the computed ratio.
    /// 0.30 dark was tried first and put moss at 5.67:1; that is the number
    /// that set these.
    readonly property real bannerAlphaDark: 0.26
    readonly property real bannerAlphaLight: 0.22

    function bannerAlpha(dark: bool): real {
        return dark ? policy.bannerAlphaDark : policy.bannerAlphaLight;
    }

    /// `#rrggbb` for `hue` laid over `base` at `alpha`. Hex in, hex out, so the
    /// arithmetic is checkable offscreen without a `color` type or a Theme.
    function tint(hue: string, base: string, alpha: real): string {
        const h = policy.channels(hue);
        const b = policy.channels(base);
        if (!h || !b)
            return policy.hex(b || [0, 0, 0]);
        const a = Math.max(0, Math.min(1, alpha));
        return policy.hex([0, 1, 2].map(i => b[i] + (h[i] - b[i]) * a));
    }

    /// `#rrggbb` → `[r, g, b]`, or `null` for anything that is not one. Short
    /// form `#rgb` is accepted because a hand-written token may use it.
    function channels(value: string): var {
        const text = String(value || "").trim().replace(/^#/, "");
        if (text.length === 3)
            return [0, 1, 2].map(i => parseInt(text[i] + text[i], 16));
        if (text.length !== 6)
            return null;
        const out = [0, 2, 4].map(i => parseInt(text.substr(i, 2), 16));
        return out.some(v => !isFinite(v)) ? null : out;
    }

    function hex(rgb: var): string {
        return "#" + rgb.map(v => {
            const n = Math.max(0, Math.min(255, Math.round(v)));
            return (n < 16 ? "0" : "") + n.toString(16);
        }).join("");
    }

    // --- past and future -------------------------------------------------------
    //
    // **The week's strongest ordering is not colour, it is time**, and until now
    // this surface did not draw it. Every chip printed at the same weight, so a
    // week already three-quarters spent looked exactly as busy as an empty one
    // and the eye had to read the gutter to find out where it stood. The
    // reference splits its chips on the same axis and the split is the single
    // most useful thing about its week picture.
    //
    // Where this parts company with the reference is *how far* the past is
    // pushed down. Measured off the live capture, its past titles sit at about
    // 35% coverage on their fill — call it 2.5:1, well under AA — so a past
    // meeting is not dim, it is unreadable, and the reader who wants to know
    // what they were doing at 10am has to select the chip to find out. A past
    // event is still information: it is what the week *was*. So the ladder here
    // is a real one and both rungs are legible — future inks land at 8.9–9.6:1
    // on their fills (dark) and 7.0–7.2 (light); past inks at 4.6–4.9 in both,
    // still past AA. `tests/tst_huepolicy.qml` asserts both bands, which is what
    // stops a later "dim it a bit more" from quietly crossing the line.

    /// The tint alpha a **past** chip's fill is laid over the page at.
    ///
    /// Under half the live one (0.07 against 0.16 dark). A past chip should read
    /// as a mark on the grid rather than as a card on it, and the thing that
    /// still says *which calendar* is the accent bar, not the fill.
    readonly property real pastTintAlphaDark: 0.07
    readonly property real pastTintAlphaLight: 0.055

    function pastTintAlpha(dark: bool): real {
        return dark ? policy.pastTintAlphaDark : policy.pastTintAlphaLight;
    }

    /// How much of the hue a past chip's **accent bar** keeps, mixed over the
    /// page. 0.45 — under half, so the bar is plainly quieter, and still enough
    /// hue that a past `lake` and a past `ember` are told apart at a glance,
    /// which is the whole reason the bar exists.
    readonly property real pastBarStrength: 0.45

    /// How much of the ink a past chip's **text** keeps, mixed over its own
    /// fill. Two numbers, because the mix runs opposite ways in the two modes:
    /// in dark the ink is pale over a dark fill and fading it costs contrast
    /// fast, in light the ink is dark over a pale fill and fading it costs
    /// contrast faster still. These are the lowest values on a 0.02 grid at
    /// which all eight hues still clear 4.6:1 — solved, not chosen.
    readonly property real pastInkStrengthDark: 0.60
    readonly property real pastInkStrengthLight: 0.80

    function pastInkStrength(dark: bool): real {
        return dark ? policy.pastInkStrengthDark : policy.pastInkStrengthLight;
    }

    /// `YYYY-MM-DDTHH:MM` for a stamp that may be short of one, or `""`.
    ///
    /// An all-day event stores a bare date, and a bare date used as an *end* is
    /// not over until the day is: `2026-08-18` normalises to `2026-08-18T23:59`,
    /// so today's all-day event stays a future one all day. Anything longer is
    /// cut to the minute so that two stamps of different precision still compare
    /// — seconds on one side and none on the other would otherwise make
    /// `…T09:30:00` sort after `…T09:30`, which is the wrong answer at exactly
    /// the moment the answer changes.
    function normaliseEnd(stamp: string): string {
        const s = String(stamp === undefined || stamp === null ? "" : stamp).trim();
        if (!/^[0-9]{4}-[0-9]{2}-[0-9]{2}/.test(s))
            return "";
        if (s.length === 10)
            return s + "T23:59";
        return /^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}/.test(s)
            ? s.substring(0, 16) : "";
    }

    /// The same, for the clock. A bare date here is the *start* of the day: a
    /// caller who says "now is 2026-08-18" has said nothing about the hour, and
    /// treating that as midnight makes nothing on that day past, which is the
    /// safe direction — a future chip misread as future costs nothing, a live
    /// meeting greyed out costs the reader the one chip they were looking for.
    function normaliseNow(stamp: string): string {
        const s = String(stamp === undefined || stamp === null ? "" : stamp).trim();
        if (!/^[0-9]{4}-[0-9]{2}-[0-9]{2}/.test(s))
            return "";
        if (s.length === 10)
            return s + "T00:00";
        return /^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}/.test(s)
            ? s.substring(0, 16) : "";
    }

    /// **Has this event finished?** — the one decision the whole past/future
    /// ladder hangs off.
    ///
    /// It is `end`, not `start`: an event that began an hour ago and runs for
    /// another one is the reader's *current* meeting and the loudest thing on
    /// the grid. Dimming at `start` would grey out the chip you are sitting in.
    ///
    /// No clock means no past. The capture harness, a test, and the surface for
    /// the first frame after load all hand this an empty `nowStamp`, and a week
    /// that dims itself because it does not yet know the time is a week that
    /// flickers on every launch. Both stamps are ISO and fixed-width after
    /// normalisation, so a string compare *is* the chronological one — no `Date`
    /// parsing, no timezone, and the same answer offscreen as on the grid.
    function isPast(endStamp: string, nowStamp: string): bool {
        const now = policy.normaliseNow(nowStamp);
        if (now.length === 0)
            return false;
        const end = policy.normaliseEnd(endStamp);
        if (end.length === 0)
            return false;
        return end <= now;
    }

    /// `"past"` or `"future"` — the same decision named, for a surface that
    /// wants to switch on it rather than on a bool, and for a log line.
    function strengthFor(endStamp: string, nowStamp: string): string {
        return policy.isPast(endStamp, nowStamp) ? "past" : "future";
    }

    /// The same question asked of a whole event. Missing event, missing clock
    /// or a malformed stamp all answer `false`, for the reason `forEvent` above
    /// answers 0: the caller is a delegate mid-rebuild.
    function eventIsPast(event: var, nowStamp: string): bool {
        if (!event)
            return false;
        return policy.isPast(event.end, nowStamp);
    }

    // --- contrast, so the ladder can be asserted rather than eyeballed ---------

    /// Relative luminance per WCAG 2.1, from a `#rrggbb`.
    function luminance(colour: string): real {
        const c = policy.channels(colour);
        if (!c)
            return 0;
        const lin = c.map(v => {
            const x = v / 255;
            return x <= 0.03928 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4);
        });
        return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2];
    }

    /// The WCAG contrast ratio between two `#rrggbb`, 1..21.
    function contrast(a: string, b: string): real {
        const x = policy.luminance(a);
        const y = policy.luminance(b);
        const hi = Math.max(x, y);
        const lo = Math.min(x, y);
        return (hi + 0.05) / (lo + 0.05);
    }

    // --- taking the forest out of the furniture ---------------------------------

    /// `colour` pulled `amount` of the way toward the **grey of its own
    /// luminance**.
    ///
    /// The palette's neutrals are not neutral — `textMuted` is `#7d8f86`, which
    /// is a green — and that is right for a shell whose whole identity is the
    /// forest. It is wrong for a *grid*: an hour gutter and a row of weekday
    /// caps are rulings, and twenty of them in a tinted grey read as a wash the
    /// eye keeps trying to interpret, sitting a few degrees off the eight hues
    /// that actually carry meaning here. So the chrome desaturates and the
    /// content does not — the theme survives in every surface, border, wash and
    /// chip, and the furniture stops competing with them.
    ///
    /// Mixing toward the *equal-luminance* grey rather than toward mid-grey is
    /// what makes this free: the endpoints have the same relative luminance, so
    /// every ratio this ink held against every background it is drawn on
    /// survives the change. `tests/tst_huepolicy.qml` asserts that, which is the
    /// only reason this is allowed to touch text colour at all.
    function neutralise(colour: string, amount: real): string {
        const c = policy.channels(colour);
        if (!c)
            return String(colour || "");
        const a = Math.max(0, Math.min(1, amount));
        const target = policy.luminance(colour);
        // Invert the sRGB transfer curve on the luminance to get the grey level
        // that carries it: for a grey, R = G = B, so luminance is just the
        // linear value back through the curve.
        const g = target <= 0.0031308
            ? target * 12.92 : 1.055 * Math.pow(target, 1 / 2.4) - 0.055;
        const level = g * 255;
        return policy.hex(c.map(v => v + (level - v) * a));
    }
}
