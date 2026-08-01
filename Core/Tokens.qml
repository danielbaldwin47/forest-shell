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
// row is the brief's light table, which is a *seed*: #8 recorded it as
// incomplete, so roles it does not name fall back to their dark value per
// token rather than being invented here. v1 ships dark-first; light polish is
// post-v1 and gates nothing.
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

    // Light — the brief's light table, seed only.
    //
    // Deliberately partial: seven roles the brief never sampled are absent and
    // resolve to dark. Filling them is the light-theme ticket's work, and
    // guessing them here would commit values that ticket would have to undo.
    //
    // The brief also lists an `accent-secondary` (#1a5f77, deeper lake blue)
    // with no dark counterpart. #8 flagged it provisional pending role
    // symmetry, so it is recorded here in prose and kept out of the token set —
    // a role that exists in one mode only is not mode-blind.
    readonly property var lightSeed: ({
        bgBase: "#eef1ec",          // warm-cool paper, not white
        surface: "#f7f9f5",         // cards sit *above* the base here
        surfaceRaised: "#ffffff",
        borderSubtle: "#dbe1da",
        textPrimary: "#1b241f",     // 14.0:1
        textSecondary: "#46564d",   // 6.8:1
        textMuted: "#6b7a71",       // 4.0:1 — large text only
        accentPrimary: "#0c757b",   // teal darkens for a light bg — 4.8:1
        accentWarm: "#8a5a2f",      // wood brown — 5.1:1
        accentEmber: "#b0512f"      // 4.5:1
    })

    // Roles the light row borrows from dark. Derived, never hand-listed, so it
    // shrinks on its own as the light table is filled in.
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
    // The brief's other atmospheric devices — the vertical luminance gradient
    // (§3.2) and the anti-banding grain (§3.5) — are ranges, not values. The
    // surface ticket that picks one adds the token then; guessing here would
    // commit a number that ticket would have to migrate away from.
    readonly property real fogWashOpacity: 0.10   // the wash over a scrimmed desktop
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
