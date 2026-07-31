// The scrim. The brief's most distinctive claim (§6.1) is that the desktop
// should recede into *mist* rather than dim to black — so this component makes
// both renderable side by side over the same backdrop.
//
// Two ways it can run:
//   backdrop != null  — the study fakes the compositor: blur + desaturate the
//                       stand-in wallpaper in-process, then wash it. This is the
//                       *intended* look, including the desaturation Hyprland
//                       cannot do per-layer.
//   backdrop == null  — live over the real desktop: only the wash is ours; blur
//                       comes from `layerrule = blur, <namespace>`, and there is
//                       no desaturation available.
import QtQuick
import QtQuick.Effects

Item {
    id: root

    /// Item to blur/desaturate in-process. Null when running live.
    property Item backdrop: null

    /// "fog" | "dim" | "fogGradient" | "dusk"
    ///
    /// "dusk" is not in the brief. It surfaced from the study: the shell is
    /// dark-first, so a *pale* mist lightens exactly the thing our light text
    /// has to sit on. Dusk keeps the mist mechanic — blur, desaturate, veil —
    /// but veils toward the palette's own deep green instead of toward white.
    property string mode: "fog"

    /// 2–4% monochrome noise over the flat wash — kills banding (brief §3.5).
    property bool noise: true

    /// Strength of the pale wash. The brief's §6.1 figure is 0.10, which assumes
    /// the compositor is blurring behind the surface. When it is not, the veil is
    /// the only thing standing between the wallpaper and the UI, and it has to
    /// carry more — see findings.md §3.
    property real washOpacity: Theme.fogWashOpacity

    /// Drives every animated property, so open/close is one opacity ramp.
    property real amount: 1.0

    /// Models whether the compositor blurs behind the layer surface at all.
    /// It is not ours to assume: `layerrule = blur` does nothing unless
    /// `decoration:blur:enabled` is on globally, and it is off on this machine.
    /// The scrim has to still read as a scrim with this false.
    property bool blurred: true

    readonly property bool isDim: mode === "dim"

    MultiEffect {
        anchors.fill: parent
        source: root.backdrop
        visible: root.backdrop !== null
        blurEnabled: root.blurred
        // ~14px of blur (#8) — at blurMax 48 the wallpaper turns to soup and
        // the scrim stops reading as *atmosphere over a place*. Landmarks have
        // to survive: fog you can still see the ridge through.
        blur: 0.5
        blurMax: 32
        blurMultiplier: root.amount
        // Atmospheric perspective is lightening *plus* desaturation with
        // distance (brief §3.1) — the desktop is what moves away from you.
        saturation: root.isDim ? 0.0 : Theme.fogSaturation * root.amount
        brightness: root.isDim ? -0.15 * root.amount : 0.0
    }

    // The wash itself.
    Rectangle {
        anchors.fill: parent
        visible: root.mode === "fog"
        color: Theme.fogWash
        opacity: root.washOpacity * root.amount
    }

    // Same wash, but carrying the board's vertical luminance gradient: more
    // mist near the horizon, clearer sky above.
    Rectangle {
        anchors.fill: parent
        visible: root.mode === "fogGradient"
        opacity: root.amount
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0.745, 0.808, 0.820, 0.04) }
            GradientStop { position: 0.42; color: Qt.rgba(0.745, 0.808, 0.820, 0.13) }
            GradientStop { position: 1.0; color: Qt.rgba(0.745, 0.808, 0.820, 0.06) }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.isDim
        color: "#000000"
        opacity: 0.45 * root.amount
    }

    // Dusk: the same atmospheric move, veiled toward bg-base instead of white.
    Rectangle {
        anchors.fill: parent
        visible: root.mode === "dusk"
        color: Theme.bgBase
        opacity: 0.55 * root.amount
    }
    Rectangle {
        anchors.fill: parent
        visible: root.mode === "dusk"
        opacity: root.amount
        // still lit from the top, still lightening with distance — the fog is
        // there, it is just an evening fog.
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0.745, 0.808, 0.820, 0.10) }
            GradientStop { position: 0.55; color: Qt.rgba(0.745, 0.808, 0.820, 0.04) }
            GradientStop { position: 1.0; color: Qt.rgba(0.745, 0.808, 0.820, 0.01) }
        }
    }

    Image {
        anchors.fill: parent
        visible: root.noise
        source: Qt.resolvedUrl("gen/noise.png")
        fillMode: Image.Tile
        opacity: 0.028 * root.amount
    }
}
