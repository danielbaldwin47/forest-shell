pragma Singleton

// The single source of design tokens (#12 §6): no raw hex, no magic spacing,
// no ad-hoc durations anywhere else in the shell.
//
// STUB — a frozen slice of the design system spec (#8), enough for the skeleton
// to render. The theme tokens & icon pipeline ticket (#34) fills this file in
// (swappable palette data, light seed, type scale, semantic roles); consumers
// keep the same `Theme.<token>` call sites, so nothing above it moves.
import QtQuick
import Quickshell

Singleton {
    // --- colour -------------------------------------------------------------
    readonly property color bgBase: "#0b100d"
    readonly property color bgSunken: "#070a08"
    readonly property color surface: "#141b17"
    readonly property color surfaceRaised: "#1c2621"
    readonly property color surfaceOverlay: "#243029"
    readonly property color borderSubtle: "#2a3830"
    readonly property color borderStrong: "#3c554d"

    readonly property color textPrimary: "#e6ece8"
    readonly property color textSecondary: "#a9b8b0"
    readonly property color textMuted: "#7d8f86"

    readonly property color accentPrimary: "#6fbec4"  // glacier teal — interactive
    readonly property color accentDeep: "#0c757b"
    readonly property color accentWarm: "#d8ac81"     // lamplight — attention, rare
    readonly property color accentEmber: "#e07a5f"
    readonly property color accentLichen: "#afbd7a"
    readonly property color accentStone: "#9d9e8d"

    // --- spacing (4px grid) --------------------------------------------------
    readonly property int space1: 4
    readonly property int space2: 8
    readonly property int space3: 12
    readonly property int space4: 16
    readonly property int space5: 20
    readonly property int space6: 24

    // --- radii ---------------------------------------------------------------
    readonly property int radiusSm: 6
    readonly property int radiusMd: 10
    readonly property int radiusLg: 16

    // --- type ----------------------------------------------------------------
    readonly property string fontUi: "IBM Plex Sans"
    readonly property string fontMono: "IBM Plex Mono"
    readonly property string fontDisplay: "Newsreader"

    // --- motion --------------------------------------------------------------
    readonly property var fogEase: [0.22, 1.0, 0.36, 1.0, 1.0, 1.0]
    readonly property int motionFast: 140
    readonly property int motionStandard: 240
    readonly property int motionSlow: 320
}
