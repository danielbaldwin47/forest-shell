// The design system as data (#8, #34) — every value the shell is allowed to
// paint with, and the pure functions that resolve them.
//
// Split out of Core/Theme.qml for the same reason Core/SettingsSchema.qml is
// split out of Core/Config.qml: this file imports nothing but QtQuick, so
// tests/ can reach it (Quickshell's QML modules are compiled into the
// quickshell binary, and qmltestrunner cannot load them). Theme is the
// singleton consumers name; this is what it is made of.
//
// Colours are held as a *table*, not as one property per role, because the
// palette is swappable data (#12 §6): dark and light are two rows of the same
// table, a preset or an override replaces cells in it, and `palette()` is the
// one place a role name turns into a colour. Everything else — spacing, radii,
// type, motion — is a fixed constant and is declared as a plain property.
//
// The dark row is the board design brief §2 verbatim, names included. The light
// row was the brief's light table plus a per-token fallback to dark for the
// seven roles it never sampled; #44 filled those, because the Dark/Light tile
// is the first thing in the shell that flips this palette live and a fallback
// to dark is a near-black hover on a white card. The fallback machinery stays —
// a theme preset (#56) can reintroduce a partial row.
//
// Both rows are gated by `tests/tst_tokens.qml`, which computes every
// text-on-surface ratio in both modes. That is a seam-1 check and not seam 3's
// `--contrast` on purpose: these are opaque tokens, so the ratio is arithmetic
// over two constants. Seam 3 measures a *composite* — a translucent fill over a
// wallpaper (#79) — which is a number no table can predict.
import QtQuick

QtObject {
    id: tokens

    // --- colour --------------------------------------------------------------

    // The role names, in brief order. This list is the token set: a role that
    // is not here does not exist, and `palette()` returns exactly these keys.
    readonly property var colorRoles: [
        "bgBase", "bgSunken", "surface", "surfaceRaised", "surfaceOverlay",
        "borderSubtle", "borderStrong",
        "textPrimary", "textSecondary", "textMuted",
        "accentPrimary", "accentDeep", "accentWarm", "accentEmber",
        "accentLichen", "accentStone",
        "fogWash"
    ]

    // Dark — board design brief §2, adopted verbatim by #8.
    //
    // Backgrounds are not neutral black: they carry a green/olive cast sampled
    // from forest-floor shadow, and that cast is the signature. The accent
    // structure is three-part and load-bearing — teal is interactive, lamplight
    // amber is attention (exactly one element at a time), ember is urgent.
    readonly property var dark: ({
        bgBase: "#0b100d",          // deepest canvas
        bgSunken: "#070a08",        // wells, insets, terminal bg
        surface: "#141b17",         // bar, panels — 1.10:1 vs base, on purpose
        surfaceRaised: "#1c2621",   // popovers, notification cards
        surfaceOverlay: "#243029",  // hover, menus, tooltips
        borderSubtle: "#2a3830",    // hairlines
        borderStrong: "#3c554d",    // focus rings, active edges
        textPrimary: "#e6ece8",     // 16.0:1 on base
        textSecondary: "#a9b8b0",   // 9.3:1
        textMuted: "#7d8f86",       // 5.6:1 — still AA for body text
        accentPrimary: "#6fbec4",   // glacier teal — interactive
        accentDeep: "#0c757b",      // lake teal — fills, selected states
        accentWarm: "#d8ac81",      // lamplight — attention, rare
        accentEmber: "#e07a5f",     // campfire — urgent, destructive
        accentLichen: "#afbd7a",    // sunlit meadow — success
        accentStone: "#9d9e8d",     // rock and dry grass — dormant states
        fogWash: "#beced1"          // the mist a scrim is made of (brief §3.1)
    })

    // Light — the brief's light table, completed.
    //
    // The first ten are the brief's own samples. The last six are #44's: the
    // Dark/Light tile is the first thing in the shell that flips this palette
    // live, and a mode where seven roles fell back to their *dark* values was a
    // mode that painted a near-black hover over a white card, an unreadable
    // pale-lichen success line, and a 10% pale wash over an already pale
    // desktop — a fog that obscured nothing.
    //
    // The added six are measured rather than authored, which after #79 and #94
    // is the rule: the ratios in the comments are computed against this row's
    // own `bgBase`, and the whole row is gated by the contrast tests in
    // `tests/tst_tokens.qml` — every text role against every surface, in both
    // modes. Where a dark counterpart exists, the light value is aimed at the same
    // *step* rather than the same number — the two rows are the same design at
    // opposite ends, so what has to match is the separation between a surface
    // and the thing raised above it.
    //
    // The brief also lists an `accent-secondary` (#1a5f77, deeper lake blue)
    // with no dark counterpart. #8 flagged it provisional pending role
    // symmetry, so it is recorded here in prose and kept out of the token set —
    // a role that exists in one mode only is not mode-blind.
    readonly property var lightSeed: ({
        bgBase: "#eef1ec",          // warm-cool paper, not white
        bgSunken: "#e0e5df",        // wells sink *below* paper — 1.12:1 step (dark: 1.04:1)
        surface: "#f7f9f5",         // cards sit *above* the base here
        surfaceRaised: "#ffffff",
        surfaceOverlay: "#edf2eb",  // hover darkens where dark's lightens — 1.14:1
                                    // under `surfaceRaised`, the same step dark
                                    // puts over it
        borderSubtle: "#dbe1da",
        borderStrong: "#94a397",    // 2.5:1 on surface (dark: 2.2:1)
        textPrimary: "#1b241f",     // 14.0:1
        textSecondary: "#46564d",   // 6.8:1
        textMuted: "#6b7a71",       // 4.0:1 — large text only
        accentPrimary: "#0c757b",   // teal darkens for a light bg — 4.8:1
        // The one added role that does not simply darken. `accentDeep` is a
        // *fill* — the selected chip (#54), the active session row, the lit
        // control-centre tile — and every one of those draws `textPrimary` on
        // it. In dark that pairing is #e6ece8 on a saturated teal, 4.6:1. A
        // light row that darkened this to match would put light mode's *dark*
        // textPrimary on a dark fill, which is the one combination that cannot
        // be read at all. So the fill inverts with the mode the text does:
        // 9.6:1 under #1b241f, and 1.6:1 against `surface`, which is what makes
        // a selected row look selected.
        accentDeep: "#a9d0d3",      // pale lake — 9.6:1 under textPrimary
        accentWarm: "#8a5a2f",      // wood brown — 5.1:1
        accentEmber: "#b0512f",     // 4.5:1
        accentLichen: "#59682c",    // meadow in daylight — 5.4:1
        accentStone: "#68695b",     // 4.9:1 — dormant, and still AA
        // The one role that inverts rather than darkening by degrees. The fog
        // is a 10% wash whose whole job is to obscure, and 10% of a pale mist
        // over a pale desktop is a scrim you can read straight through — so in
        // light the mist is the *shadow* between the trees rather than the
        // light in them.
        fogWash: "#4a5a5e"
    })

    // Roles the light row borrows from dark. Derived, never hand-listed: it was
    // seven before #44 and is empty now, and it stays here because a preset
    // (#56) can reintroduce a partial row.
    readonly property var lightFallbackRoles: colorRoles.filter(
        role => lightSeed[role] === undefined)

    /// The colour table for one mode, with user overrides applied.
    ///
    /// Always returns every role in `colorRoles`, so consumers are mode-blind:
    /// nothing downstream ever tests which palette it got.
    ///
    /// `overrides` is `appearance.paletteOverrides` — a role → colour map. An
    /// unknown role or an unparseable colour is dropped with a warning rather
    /// than poisoning the palette, because it arrives from a hand-edited file.
    function palette(darkMode: bool, overrides: var): var {
        const out = {};
        for (const role of colorRoles)
            out[role] = (darkMode ? undefined : lightSeed[role]) ?? dark[role];

        if (overrides)
            for (const role in overrides) {
                if (out[role] === undefined) {
                    console.warn("Theme: unknown palette role in overrides:", role);
                    continue;
                }
                if (!isColor(overrides[role])) {
                    console.warn("Theme: not a colour:", role, "=", overrides[role]);
                    continue;
                }
                out[role] = overrides[role];
            }

        return out;
    }

    /// Whether a value is a hex colour literal Qt will parse. The three lengths
    /// are the ones `QColor` actually accepts — `#RGB`, `#RRGGBB` and
    /// `#AARRGGBB`; there is no four-digit `#RGBA` form, and admitting one would
    /// let an override through that paints as something else entirely.
    ///
    /// Deliberately narrower than Qt's own parser besides: named colours
    /// ("teal") are refused, so an override cannot smuggle in a hue the palette
    /// never sampled.
    function isColor(value: var): bool {
        return typeof value === "string"
            && /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(value);
    }

    // --- fog scrim -----------------------------------------------------------
    // Brief §3.1, spec'd whole in #8: the desktop recedes into *mist*, not into
    // a black dim. Only the opacity ever animates — the blur never does, and is
    // likely delegated to a Hyprland layer rule.
    //
    // The brief's other atmospheric device — the vertical luminance gradient
    // (§3.2) — is a range, not a value. The surface ticket that picks one adds
    // the token then; guessing here would commit a number that ticket would
    // have to migrate away from.
    readonly property real fogWashOpacity: 0.10   // the wash over a scrimmed desktop
    // The anti-banding grain (§3.5), picked by the first surface that needed it
    // as a constant rather than a setting — the drawer's fog (#38). The bar
    // exposes its own grain as a Bar-tab knob because the bar is a surface you
    // look at; the fog is one you look *through*, and 3% is the middle of the
    // brief's 2–4% band, which is what the launcher prototype used
    // (.wayfinder/prototypes/launcher-clearing/Fog.qml).
    readonly property real fogGrain: 0.03
    readonly property real fogBlur: 14            // px; Hyprland layer blur live
    readonly property real fogSaturation: -0.20   // MultiEffect delta for saturate(0.8)

    // The vertical luminance gradient (brief §3.2), picked by the first surface
    // that needed it — the lock (#47), where a wallpaper of any brightness has
    // to hold a serif clock and a password field legibly. `bgBase` at these
    // alphas, bright end at the top, per the brief's "every pin is dark at the
    // bottom, bright at the top".
    //
    // The brief's own 4–6% is the delta between *bands of a surface*; a veil
    // over an arbitrary photograph needs more, and 8→55% is what keeps
    // `textPrimary` above its measured contrast on the brightest wallpaper
    // without the wallpaper reading as switched off.
    readonly property real veilTop: 0.08
    readonly property real veilBottom: 0.55

    // What the fog does when a surface has to refuse something — the lock's
    // failed password (#30). Opacity only, one step of the ladder, no blur
    // change: the mist thickens for a moment and settles back.
    readonly property real fogPulseOpacity: 0.28

    // --- spacing -------------------------------------------------------------
    // 4px grid (#8). Component internals 4–16, panel padding 16–24, section
    // gaps 32+. Component *dimensions* — bar height, launcher width — are per
    // feature spec, not tokens.
    readonly property int space1: 4
    readonly property int space2: 8
    readonly property int space3: 12
    readonly property int space4: 16
    readonly property int space5: 20
    readonly property int space6: 24
    readonly property int space7: 32
    readonly property int space8: 40
    readonly property int space9: 48
    readonly property int space10: 64

    readonly property int hairline: 1   // rules and borders
    readonly property int rail: 2       // the accent rail on a selected row

    // --- state ---------------------------------------------------------------
    // One opacity for "here, readable, and not available" — a control whose
    // feature has not landed, an option that cannot be chosen yet, an action
    // that would do nothing. Greying is the shell's whole vocabulary for it:
    // nothing is ever hidden to say it is unavailable, because a control that
    // appears later is a worse surprise than one that waits in place (#54).
    readonly property real opacityInert: 0.4

    // --- radii ---------------------------------------------------------------
    // Nothing sharp (brief §5).
    readonly property int radiusSm: 6     // buttons, chips
    readonly property int radiusMd: 10    // cards, notifications
    readonly property int radiusLg: 16    // launcher, modals
    readonly property int radiusFull: 9999 // toggles, avatars — larger than any

    // --- type ----------------------------------------------------------------
    // Plain family names only. fontconfig also exposes legacy sub-families
    // ("IBM Plex Sans Medm", "IBM Plex Mono SmBld"); naming those is a bug even
    // though it renders, because weight then has nowhere to go. Weight on the
    // canonical family resolves to the same face, measured in #18.
    readonly property string fontUi: "IBM Plex Sans"
    readonly property string fontMono: "IBM Plex Mono"
    readonly property string fontDisplay: "Newsreader"   // clock only, once, never twice

    readonly property int weightDisplay: 300  // Newsreader Light, off its variable axis
    readonly property int weightRegular: 400
    readonly property int weightText: 450     // Plex "Text" — no named QML constant
    readonly property int weightMedium: 500

    // The one type size the design system fixes: tiny all-caps section labels.
    // Everything else is per feature spec.
    readonly property real capsSize: 10.5
    readonly property real capsTrackingEm: 0.08
    readonly property real lineHeightBody: 1.55

    /// px → pt. `font.pixelSize` is an `int` and the scale has half-pixel steps
    /// (14.5, 12.5, 10.5), so sizes go through `font.pointSize`, which is a
    /// real. Exact at Qt's 96 logical DPI.
    function pt(px: real): real { return px * 72 / 96; }

    /// `font.letterSpacing` is in pixels; the spec is in em.
    function tracking(pixelSize: real, em: real): real { return pixelSize * em; }

    // --- motion --------------------------------------------------------------
    // Fog moves, it doesn't snap. One curve, three steps, no springs (#8, #27).

    // cubic-bezier(0.22, 1, 0.36, 1), in the six-number form
    // `easing.bezierCurve` wants (two control points plus the fixed endpoint).
    readonly property var fogEase: [0.22, 1.0, 0.36, 1.0, 1.0, 1.0]

    // Step = how much of the screen the motion touches (#27).
    readonly property int motionFast: 140      // in-place change inside a visible surface
    readonly property int motionStandard: 240  // one surface entering or leaving
    readonly property int motionSlow: 320      // fog-scale; the whole screen changes meaning

    readonly property var motionSteps: [motionFast, motionStandard, motionSlow]

    /// Exits run one step faster than entrances, floored at `motionFast` — the
    /// 140 class is symmetric, and no fourth micro-step exists.
    ///
    /// A duration that is not on the ladder is not a design system value, so it
    /// gets the floor rather than arithmetic that would invent a fourth step.
    function exitDuration(enterMs: int): int {
        const i = motionSteps.indexOf(enterMs);
        return i > 0 ? motionSteps[i - 1] : motionFast;
    }
}
