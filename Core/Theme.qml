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
//   NumberAnimation { duration: Theme.motionStandard; easing.bezierCurve: Theme.fogEase }
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
    readonly property color accentStone: palette.accentStone       // dormant

    // --- material ------------------------------------------------------------
    readonly property color fogWash: palette.fogWash
    readonly property alias fogWashOpacity: tokenData.fogWashOpacity
    readonly property alias fogBlur: tokenData.fogBlur
    readonly property alias fogSaturation: tokenData.fogSaturation

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

    function exitDuration(enterMs: int): int { return tokenData.exitDuration(enterMs); }

    Component.onCompleted: Logger.stage("theme ready (" + (root.dark ? "dark" : "light") + ")")
}
