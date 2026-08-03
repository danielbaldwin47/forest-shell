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
// brightest part of the sky.) So the bar is a fill, and the blur behind it is
// the compositor's (Surfaces/Bar/Bar.qml pushes the layerrule).
//
// Those four numbers were taken against an *averaged* wallpaper luminance, and
// that is the part #79 overturned: over the strip the bar actually covers on a
// real wallpaper, 86% fill measures 4.85:1 rather than 7.12:1 and the schema's
// old 0.65 clamp measures 2.82:1 rather than the 4.44:1 that was supposed to
// be the failing case. The ranking above survives — a fill still beats a fog
// band — but the floor does not live in the schema any more. `fillOpacity` is
// handed in already clamped to what the wallpaper allows
// (Surfaces/Bar/BarLegibility.qml).
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

    /// Painted opacity of the fill. Separate from `settings.opacity` because
    /// the legibility floor (#79) raises it without writing to the config —
    /// what the user set and what the wallpaper allows are two different
    /// numbers, and only one of them belongs in settings.json.
    property real fillOpacity: settings.opacity

    /// What the fill is painting *right now*, which is not `fillOpacity` while
    /// the Behavior below is still running. The legibility floor (#79) arrives
    /// after the first frame and fades in over `motionSlow`, so anything that
    /// photographs the bar has to wait for this to reach `fillOpacity` rather
    /// than for the floor to be decided — measured: three captures taken on the
    /// decision alone read 5.05:1, 4.76:1 and 4.45:1 off one identical fill.
    readonly property real paintedOpacity: fill.opacity

    /// The band arithmetic, here only for the two constants the top-light
    /// gradient below is drawn from — see `topLightStop`.
    readonly property SurfaceOpacity band: SurfaceOpacity {}

    property real radius: 0

    /// Which edge the hairline sits on — the one facing the desktop, since it
    /// is the bar's horizon. Top bar: the bottom edge.
    property bool hairlineAtBottom: true

    // Which layers sit inside the fill and which sit above it is not a detail:
    // the fill is translucent, so anything parented to it is painted at 86% of
    // its own strength and moves whenever the legibility clamp moves the fill. So
    // the rule is what each layer is *about*.
    //
    //   inside — the top-light, which is about the fill itself and has no
    //            meaning apart from it. "Inside" is where it is parented, and
    //            not what it does to the pixels: Qt Quick multiplies opacity
    //            down the tree and blends each node against what is already
    //            there, so this is drawn *over* the wallpaper the fill let
    //            through and blocks some of it, rather than lightening the
    //            fill's colour before the blend. Over a bright wallpaper that
    //            makes the top of the bar darker than its middle — visible in
    //            any capture, and the detail the #79 clamp had to model
    //            correctly to predict what this renders;
    //   above  — the mist wash, the grain and the hairline, each of which is
    //            specified as an absolute (0.10, 3%, 1px `border-subtle`) and
    //            each of which is about the *band*, not about the fill.
    //
    // The mist wash in particular has to be above: under an 86% fill it would
    // contribute about 1.4% and the setting would do nothing at all, which is
    // not what "86% fill over blurred wallpaper, **plus** the mist wash" (#10)
    // describes. It costs a little contrast — text-secondary over the band
    // measures ~6.9:1 rather than the fill's own 7.12:1 on the averaged
    // reading, and 4.5:1 rather than 4.85:1 over a real bright strip. The
    // clamp accounts for it rather than absorbing it.

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
        // the stop just past halfway leaves the bottom half of the bar flat.
        //
        // Both come from SurfaceOpacity rather than being written here, because
        // that file predicts this gradient to decide the legibility floor (#79)
        // and a stop the two disagree on is a floor calculated for a bar nobody
        // draws — which fails as a passing number rather than as a wrong-looking
        // bar.
        Rectangle {
            anchors.fill: parent
            radius: fill.radius
            visible: root.settings.topLight
            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: Qt.lighter(Theme.surface,
                                      1.0 + root.settings.topLightAmount * band.topLightScale)
                }
                GradientStop { position: band.topLightStop; color: "transparent" }
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
