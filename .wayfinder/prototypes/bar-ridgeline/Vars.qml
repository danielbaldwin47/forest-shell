// Every knob the prototype exposes. The control window writes these, the bar
// reads them, and `dump()` prints the current set so a chosen configuration can
// be pasted straight into the ticket resolution.
pragma Singleton
import QtQuick

QtObject {
    id: root

    // --- bar geometry -------------------------------------------------------
    property int barHeight: 32
    property bool floating: false        // false = flush full-width; true = inset island
    property int floatMarginH: 12
    property int floatMarginV: 8
    property int floatRadius: 10
    property int padH: 12                // bar inner horizontal padding
    property int moduleGap: 14           // gap between modules within a cluster

    // --- bar surface --------------------------------------------------------
    property real barOpacity: 1.0
    property bool topLight: true         // "barely-perceptible top-edge lightening"
    property real topLightAmount: 0.05   // lightness delta at the top edge
    property bool bottomHairline: false
    property bool grain: true            // 2-4% noise over flat fill (brief §3.5)
    property real grainAmount: 0.03

    // "Fog band" alternative to the opaque forest floor: the wallpaper behind
    // the bar, blurred and desaturated, with the brief's pale mist wash on top
    // (§6.1). Simulated in-surface rather than via a Hyprland layerrule so it
    // can be captured — the real shell would delegate the blur to the
    // compositor, which looks the same but costs nothing per frame.
    property bool barBlur: false
    property real barBlurAmount: 0.55    // 0..1 -> MultiEffect blur
    property real barSaturation: -0.2    // brief: saturate(0.8)
    property real fogWash: 0.10          // rgba(190,206,209, fogWash)

    // --- ridgeline ----------------------------------------------------------
    // "shape" ∈ strata | peaks | pills
    property string ridgeShape: "strata"
    property int ridgeUnitWidth: 14
    property int ridgeGap: 4
    property int ridgeActiveH: 14        // tallest — the active workspace
    property int ridgeOccupiedH: 9       // occupied, adjacent to active
    property int ridgeEmptyH: 3          // empty workspaces "nearly vanish"
    property int ridgeFalloff: 2         // px lost per step away from active
    property int ridgeMinH: 4
    property real ridgeOccupiedOpacity: 0.62
    property real ridgeEmptyOpacity: 0.22
    property real ridgeOpacityFalloff: 0.10
    property bool ridgeAmberActive: true // active carries lamplight (the one accent)
    property bool ridgeShowNumber: false // workspace id under the active peak
    property bool ridgeHorizon: false    // 1px ground line under the range

    // --- mock state ---------------------------------------------------------
    // The ridge is about how neighbours recede, which needs several occupied
    // workspaces. Rather than open windows across a live session, screenshots
    // can pin a plausible state.
    property bool mock: false
    property int mockActive: 3
    property var mockOccupied: [1, 2, 3, 5]

    // --- context ------------------------------------------------------------
    property string wallpaper: ""
    property bool showBackdrop: true     // paint our own wallpaper strip
    property int backdropHeight: 260     // how much desktop the strip covers

    function dump() {
        const keys = [
            "barHeight", "floating", "floatMarginH", "floatMarginV", "floatRadius",
            "padH", "moduleGap", "barOpacity", "topLight", "topLightAmount",
            "bottomHairline", "grain", "grainAmount",
            "ridgeShape", "ridgeUnitWidth", "ridgeGap", "ridgeActiveH",
            "ridgeOccupiedH", "ridgeEmptyH", "ridgeFalloff", "ridgeMinH",
            "ridgeOccupiedOpacity", "ridgeEmptyOpacity", "ridgeOpacityFalloff",
            "ridgeAmberActive", "ridgeShowNumber", "ridgeHorizon",
        ];
        let out = "";
        for (const k of keys) out += k + ": " + root[k] + "\n";
        console.log("\n--- vars ---\n" + out);
        return out;
    }
}
