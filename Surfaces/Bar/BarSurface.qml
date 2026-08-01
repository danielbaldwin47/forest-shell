// The bar's material (#35, brief §3 and §6.1): forest floor over blurred
// wallpaper, not a header band.
//
// Five layers, bottom up:
//
//   1. the fill — `surface` at 86%, so the compositor's blur of the wallpaper
//      reads through it without the text ever having to compete with a sky;
//   2. the mist wash — depth through haze rather than through shadow;
//   3. the top light — the vertical luminance every wallpaper has, compressed
//      into 32px, so the bar is lit from the same direction as the desktop;
//   4. grain — 3% noise, because a gradient that shallow bands on 8-bit;
//   5. the hairline — the bar's edge against the desktop *is* the horizon line
//      the design language keeps coming back to; a hairline makes it one
//      rather than a cut.
//
// Why 86% and not less: #10 measured a translucent bar against the brightest
// pin wallpaper and watched `text-secondary` fall to 2.89:1 under the
// right-hand cluster. The fill is what holds 7.12:1 there. The blur is the
// compositor's (`layerrule`, applied by the Hyprland facade) — a QML-side blur
// is ruled out on the T480's fill rate (#22 §5), and the bar is built to look
// right if the rule never lands.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core

Item {
    id: surface

    /// The resolved `bar.surface` knob set (Surfaces/Bar/BarSpec.qml).
    required property var knobs

    /// Non-zero for a floating bar.
    property real radius: 0

    /// Which edge faces the desktop — the top one, for a bar along the bottom
    /// of the screen.
    property bool hairlineAtTop: false

    /// Whether anything is on screen behind the bar. Only consulted when
    /// `adaptiveOpacity` is on, and then the bar goes solid over a used
    /// workspace and thins out over an empty one: transparency is for showing
    /// wallpaper, and over a maximised window there is no wallpaper to show.
    property bool contentBehind: false

    readonly property real fillOpacity: (surface.knobs.adaptiveOpacity && surface.contentBehind)
        ? 1.0 : surface.knobs.fillOpacity

    // Square corners on a flush bar, so nothing to clip; a floating bar clips
    // the wash and the grain to its own slab.
    clip: surface.radius > 0

    Rectangle {
        anchors.fill: parent
        radius: surface.radius
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, surface.fillOpacity)

        // Only ever a real event — an adaptive-opacity change, or the whole
        // shell recolouring on a dark/light flip. Nothing here animates at
        // rest (#22 §5).
        Behavior on color {
            ColorAnimation {
                duration: Theme.motionStandard
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.fogEase
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: surface.radius
        visible: surface.knobs.wash
        color: Qt.rgba(Theme.fogWash.r, Theme.fogWash.g, Theme.fogWash.b, Theme.fogWashOpacity)
    }

    Rectangle {
        anchors.fill: parent
        radius: surface.radius
        visible: surface.knobs.topLight
        // White rather than `Qt.lighter(surface)`: the fill is translucent, and
        // lightening a colour that is partly wallpaper lightens the wallpaper
        // with it. Transparent *white* at both ends, so the fade does not go
        // grey through premultiplied interpolation.
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, Theme.topLightAmount) }
            GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0) }
        }
    }

    Image {
        anchors.fill: parent
        visible: surface.knobs.grain
        source: Qt.resolvedUrl("../../assets/textures/grain.png")
        fillMode: Image.Tile
        opacity: Theme.grainOpacity
        // The tile is per-pixel noise: smoothing it at fractional scale turns
        // dither into a blur, which is the one thing it must not become.
        smooth: false
        cache: true
    }

    Rectangle {
        visible: surface.knobs.hairline && surface.radius === 0
        anchors {
            left: parent.left
            right: parent.right
            top: surface.hairlineAtTop ? parent.top : undefined
            bottom: surface.hairlineAtTop ? undefined : parent.bottom
        }
        height: Theme.hairline
        color: Theme.borderSubtle
    }
}
