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
}
