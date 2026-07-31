// Design-system tokens (issue #8), verbatim. The prototype never writes a raw
// hex or a magic duration anywhere else — same rule the real Core/Theme.qml
// will carry (issue #12, decision 6).
pragma Singleton

import QtQuick
import Quickshell

Singleton {
    // --- dark palette (board design brief §2) -----------------------------
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
    readonly property color accentPrimary: "#6fbec4"   // glacier teal — interactive
    readonly property color accentDeep: "#0c757b"      // lake teal — fills, selection
    readonly property color accentWarm: "#d8ac81"      // lamplight — attention, rare
    readonly property color accentEmber: "#e07a5f"     // campfire — urgent
    readonly property color accentLichen: "#afbd7a"
    readonly property color accentStone: "#9d9e8d"

    // --- fog scrim (brief §3.1, spec'd in #8) -----------------------------
    readonly property color fogWash: "#beced1"
    readonly property real fogWashOpacity: 0.10
    readonly property real fogBlur: 14            // px, Hyprland layer blur live
    readonly property real fogSaturation: -0.20   // "saturate(0.8)"

    // --- spacing: 4px grid ------------------------------------------------
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

    readonly property int radiusSmall: 6
    readonly property int radiusMedium: 10
    readonly property int radiusLarge: 16

    // --- type -------------------------------------------------------------
    readonly property string fontUi: "IBM Plex Sans"
    readonly property string fontMono: "IBM Plex Mono"
    readonly property string fontDisplay: "Newsreader"
    readonly property int weightRegular: 400
    readonly property int weightMedium: 500

    // The spec's type scale has half-pixel steps (14.5, 12.5, 10.5) and
    // `font.pixelSize` is an int — so sizes go through pointSize, which is a
    // real. At Qt's 96 logical DPI that is an exact px->pt conversion; the
    // shipping Theme will need the same helper.
    function pt(px) { return px * 72 / 96; }

    // --- motion (#8) ------------------------------------------------------
    // cubic-bezier(0.22, 1, 0.36, 1) — the one curve, no exceptions.
    readonly property var fogEase: [0.22, 1.0, 0.36, 1.0, 1.0, 1.0]
    readonly property int motionFast: 140
    readonly property int motionStandard: 240
    readonly property int motionSlow: 320
}
