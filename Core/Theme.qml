pragma Singleton

// The single source of design tokens (#12 §6, #34): no raw hex, no magic
// spacing, no ad-hoc durations anywhere else in the shell.
//
// This file is deliberately thin — the same shape as Config: the tokens are
// data (Core/Tokens.qml, which imports nothing but QtQuick so tests/ can reach
// it), and what is left here is the singleton consumers name plus the one wire
// into Config.
//
// Reading a token:
//
//   color: Theme.surface
//   anchors.margins: Theme.space4
//   NumberAnimation { duration: Theme.duration(Theme.motionStandard) }
//
// A transition asks the *ladder* for its duration rather than naming a step
// directly, because `appearance.reducedEffects` collapses every one of them
// (#22 §7, #69) — see "reduced effects" at the foot of this file.
//
// Consumers are **mode-blind**: they read a role, never a mode. `Theme.dark`
// exists for the one control that is *about* the mode — the Dark/Light tile —
// and for nothing else. Flipping it re-evaluates every colour binding below, so
// the whole shell recolours live with no reload and no per-surface handling.
//
// Colours come from a swappable table rather than being frozen here, because
// three things replace cells in it: the light row, a theme preset (#56), and
// the user's own `appearance.paletteOverrides`. Everything non-colour is a
// fixed constant and is aliased straight through.
//
// `pragma Singleton` leads this file for the reason Core/Config.qml explains at
// length: Quickshell's scan for it gives up at the first line that looks like
// the start of an object body, comment or not.
import QtQuick
import Quickshell

Singleton {
    id: root

    // The token table. Held as a child object with an id so the constants below
    // can alias it — an alias needs something to point at.
    Tokens { id: tokenData }

    // The `reducedEffects` ladder (Core/EffectsPolicy.qml, #69). Here for the
    // same reason the tokens are: it is a design-system rule stated as pure
    // functions, and this singleton is the one thing that already holds both
    // the motion ladder and a wire into Config. Surfaces call the wrapped forms
    // below and never read the key themselves — one place names it.
    EffectsPolicy { id: ladder }

    // --- mode ----------------------------------------------------------------

    /// Dark is the primary theme; v1 ships dark-first (#8). Unguarded on
    /// purpose: reading `Config.values` constructs Config, whose read is
    /// synchronous (stage one — the wallpaper depends on it) and whose resolve
    /// fills every leaf, so this is either complete or unreachable. A `?? true`
    /// here would be the schema's default written down a second place.
    readonly property bool dark: Config.values.appearance.darkMode

    /// Flip the mode. The one write Theme owns — so the key name lives here,
    /// with the property that reads it, and the Dark/Light tile stays a tile.
    function setDark(value: bool): bool {
        return Config.set("appearance.darkMode", value);
    }

    // --- colour --------------------------------------------------------------

    // Every role, resolved for the current mode with the user's overrides on
    // top. Re-evaluates when either changes; the roles below ride that.
    readonly property var palette: tokenData.palette(
        root.dark, Config.values.appearance.paletteOverrides)

    readonly property color bgBase: palette.bgBase
    readonly property color bgSunken: palette.bgSunken
    readonly property color surface: palette.surface
    readonly property color surfaceRaised: palette.surfaceRaised
    readonly property color surfaceOverlay: palette.surfaceOverlay
    readonly property color borderSubtle: palette.borderSubtle
    readonly property color borderStrong: palette.borderStrong

    readonly property color textPrimary: palette.textPrimary
    readonly property color textSecondary: palette.textSecondary
    readonly property color textMuted: palette.textMuted

    readonly property color accentPrimary: palette.accentPrimary   // glacier teal — interactive
    readonly property color accentDeep: palette.accentDeep         // lake teal — fills, selection
    readonly property color accentWarm: palette.accentWarm         // lamplight — attention, rare
    readonly property color accentEmber: palette.accentEmber       // campfire — urgent
    readonly property color accentLichen: palette.accentLichen     // success
    readonly property color accentStone: palette.accentStone

    /// Whether a value is a colour literal the palette will accept. Exposed
    /// because the settings GUI has to answer the same question *before* a
    /// write (#54): an override the palette drops is only a line on stderr, and
    /// a field that lets you type one is worse than one that says no. Two
    /// copies of the pattern would silently drift, so there is one.
    function isColor(value: var): bool { return tokenData.isColor(value); }       // dormant

    // --- material ------------------------------------------------------------
    readonly property color fogWash: palette.fogWash
    readonly property alias fogWashOpacity: tokenData.fogWashOpacity
    readonly property alias fogBlur: tokenData.fogBlur
    readonly property alias fogSaturation: tokenData.fogSaturation
    readonly property alias fogPulseOpacity: tokenData.fogPulseOpacity
    readonly property alias veilTop: tokenData.veilTop
    readonly property alias veilBottom: tokenData.veilBottom

    // --- spacing -------------------------------------------------------------
    readonly property alias space1: tokenData.space1
    readonly property alias space2: tokenData.space2
    readonly property alias space3: tokenData.space3
    readonly property alias space4: tokenData.space4
    readonly property alias space5: tokenData.space5
    readonly property alias space6: tokenData.space6
    readonly property alias space7: tokenData.space7
    readonly property alias space8: tokenData.space8
    readonly property alias space9: tokenData.space9
    readonly property alias space10: tokenData.space10
    readonly property alias hairline: tokenData.hairline
    readonly property alias rail: tokenData.rail
    readonly property alias opacityInert: tokenData.opacityInert

    // --- radii ---------------------------------------------------------------
    readonly property alias radiusSm: tokenData.radiusSm
    readonly property alias radiusMd: tokenData.radiusMd
    readonly property alias radiusLg: tokenData.radiusLg
    readonly property alias radiusFull: tokenData.radiusFull

    // --- type ----------------------------------------------------------------
    readonly property alias fontUi: tokenData.fontUi
    readonly property alias fontMono: tokenData.fontMono
    readonly property alias fontDisplay: tokenData.fontDisplay
    readonly property alias weightDisplay: tokenData.weightDisplay
    readonly property alias weightRegular: tokenData.weightRegular
    readonly property alias weightText: tokenData.weightText
    readonly property alias weightMedium: tokenData.weightMedium
    readonly property alias capsSize: tokenData.capsSize
    readonly property alias capsTrackingEm: tokenData.capsTrackingEm
    readonly property alias lineHeightBody: tokenData.lineHeightBody

    function pt(px: real): real { return tokenData.pt(px); }
    function tracking(pixelSize: real, em: real): real { return tokenData.tracking(pixelSize, em); }

    // --- motion --------------------------------------------------------------
    readonly property alias fogEase: tokenData.fogEase
    readonly property alias motionFast: tokenData.motionFast
    readonly property alias motionStandard: tokenData.motionStandard
    readonly property alias motionSlow: tokenData.motionSlow

    // --- reduced effects ------------------------------------------------------
    // The one degrade knob (#22 §7), applied (#69). Every rung is a live
    // binding on the key, so flipping the toggle re-evaluates the whole shell
    // with no restart — the same mechanism `dark` above rides.
    //
    // What each of these means, and why "opacity-only" is read the way it is,
    // is in the header of Core/EffectsPolicy.qml.

    /// The knob. Read this only to *ask the ladder something* — a surface that
    /// branches on it directly is a rung nobody wrote down.
    readonly property bool reducedEffects: Config.values.appearance.reducedEffects

    /// Rung 1 — whether to ask the compositor for blur, given what the
    /// surface's own blur setting wants.
    function blurRequested(wanted: bool): bool {
        return ladder.blurRequested(wanted, root.reducedEffects);
    }

    /// Rung 2 — whether decoration that exists only to look like something is
    /// drawn. No shipped surface has any yet; the next one binds to this.
    readonly property bool drawDecoration: ladder.drawsDecoration(root.reducedEffects)

    /// Rung 3 — how long a transition runs, and whether the ones that move
    /// something run at all.
    function duration(requestedMs: int): int {
        return ladder.duration(requestedMs, root.reducedEffects);
    }

    function exitDuration(enterMs: int): int {
        return ladder.exitDuration(enterMs, root.reducedEffects);
    }

    readonly property bool animateTransforms: ladder.animatesTransforms(root.reducedEffects)

    Component.onCompleted: Logger.stage("theme ready (" + (root.dark ? "dark" : "light") + ")")
}
