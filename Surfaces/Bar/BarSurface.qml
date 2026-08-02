// What the bar is made of (#10's resolution, board brief §3 and §6.1).
//
// The decision this file embodies, and the reason it is a fill rather than
// frosted glass: **flushness is a property of the wallpaper, not of the bar.**
// Every image on the board is dark at the bottom and bright at the top, so a
// `surface`-coloured band sits at a 6.14:1 luminance edge against a bright sky
// and 1.08:1 against a dark-topped one. There is no bar treatment that is
// near-flush on both, so the question was which failure mode to design for, and
// the answer was measured rather than argued:
//
//   opaque flush        7.94:1     ← honest, legible everywhere
//   86% fill            7.12:1     ← ships; indistinguishable, still alive
//   fog band, 45% fill  2.89:1     ← fails the body-text floor
//   fog band, 20% fill  1.25:1     ← invisible
//
// (text-secondary under the right-hand cluster, which always sits over the
// brightest part of the sky.) So the bar is a fill, the blur behind it is the
// compositor's (Surfaces/Bar/Bar.qml pushes the layerrule), and the schema
// clamps opacity at 0.65 because 0.60 measured 4.44:1 and fails.
//
// Everything else here is the brief's atmosphere, at bar scale: a mist wash
// under the fill, the vertical luminance gradient of a forest pin compressed
// into 32px, a grain that keeps that gradient from banding, and a hairline on
// the edge that is a horizon.
import QtQuick
import qs.Core

Item {
    id: root

    /// `Config.values.bar.surface`, whole — this component draws a settings
    /// group and does not read the config itself, so the gallery can show it
    /// against values that are not the user's.
    required property var settings

    /// Painted opacity of the fill. Separate from `settings.opacity` so
    /// adaptive opacity can drive it without writing to the config.
    property real fillOpacity: settings.opacity

    property real radius: 0

    /// Which edge the hairline sits on — the one facing the desktop, since it
    /// is the bar's horizon. Top bar: the bottom edge.
    property bool hairlineAtBottom: true

    // Which layers sit inside the fill and which sit above it is not a detail:
    // the fill is translucent, so anything parented to it is painted at 86% of
    // its own strength and moves whenever adaptive opacity moves the fill. So
    // the rule is what each layer is *about*.
    //
    //   inside — the top-light, which is a lightening of the fill itself and
    //            has no meaning apart from it;
    //   above  — the mist wash, the grain and the hairline, each of which is
    //            specified as an absolute (0.10, 3%, 1px `border-subtle`) and
    //            each of which is about the *band*, not about the fill.
    //
    // The mist wash in particular has to be above: under an 86% fill it would
    // contribute about 1.4% and the setting would do nothing at all, which is
    // not what "86% fill over blurred wallpaper, **plus** the mist wash" (#10)
    // describes. It costs a little contrast — text-secondary over the band
    // measures ~6.9:1 rather than the fill's own 7.12:1 — against a 4.5:1
    // floor, so the headroom is still most of the way to double.

    Rectangle {
        id: fill

        anchors.fill: parent
        radius: root.radius
        color: Theme.surface
        opacity: root.fillOpacity

        Behavior on opacity {
            NumberAnimation {
                // A fade, so it survives `reducedEffects` — at 140 rather than
                // at fog scale (#69).
                duration: Theme.duration(Theme.motionSlow)
                easing.type: Easing.Bezier
                easing.bezierCurve: Theme.fogEase
            }
        }

        // "Barely-perceptible top-edge lightening" — the luminance gradient
        // every board pin has, compressed into the bar's 32px.
        //
        // The two numbers are the prototype's, kept so this renders what was
        // captured: `Qt.lighter` takes a factor rather than a delta, so the
        // 0-0.4 setting is scaled by 4 to reach a useful range (0.05 → a 1.2
        // factor, which is the "barely perceptible" the brief asks for), and
        // the stop at 0.55 puts the fade out just past halfway so the bottom
        // half of the bar stays flat.
        Rectangle {
            anchors.fill: parent
            radius: fill.radius
            visible: root.settings.topLight
            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: Qt.lighter(Theme.surface, 1.0 + root.settings.topLightAmount * 4)
                }
                GradientStop { position: 0.55; color: "transparent" }
            }
        }
    }

    // The pale mist a scrim is made of (brief §3.1), over the band.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Theme.fogWash
        opacity: root.settings.mistWash
    }

    // 2-4% monochrome noise (brief §3.5). Without it the top-light bands
    // visibly on an 8-bit panel, because it is a very small luminance change
    // spread over very few pixels.
    //
    // Tiled from a 64px source, so it costs one small texture for the whole bar
    // however wide the screen is.
    Image {
        anchors.fill: parent
        visible: root.settings.grain > 0
        opacity: root.settings.grain
        source: Qt.resolvedUrl("../../assets/noise.png")
        fillMode: Image.Tile
    }

    // The bar's bottom edge *is* a horizon — the one place the brief's
    // horizontal-band motif is load-bearing rather than decorative. At full
    // strength, because it is an edge against the desktop rather than a mark on
    // the fill. Not drawn while floating: an island has no horizon, it has a
    // shape.
    Rectangle {
        visible: root.settings.hairline && root.radius === 0
        anchors {
            left: parent.left
            right: parent.right
            top: root.hairlineAtBottom ? undefined : parent.top
            bottom: root.hairlineAtBottom ? parent.bottom : undefined
        }
        height: Theme.hairline
        color: Theme.borderSubtle
    }
}
