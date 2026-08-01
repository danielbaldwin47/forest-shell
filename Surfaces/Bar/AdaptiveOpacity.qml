// The wallpaper end of adaptive opacity: quantize the image, average what
// comes back, hand the bar a fill opacity (Surfaces/Bar/SurfaceOpacity.qml has
// the arithmetic and the caveats).
//
// Its own file, loaded only while `bar.surface.adaptiveOpacity` is on, for two
// reasons. It is the only part of the bar that reads and decodes the wallpaper
// a second time, and an off switch that still decodes is not off. And it is the
// only part that depends on `ColorQuantizer`, so a runtime without that type
// loses this feature rather than the bar.
//
// Quantization is not free and not on the first-frame path: the bar paints at
// the configured opacity and firms up when the answer arrives, which is a slow
// fade on the fog curve rather than a snap (Surfaces/Bar/BarSurface.qml).
import QtQuick
import Quickshell
import qs.Core

QtObject {
    id: root

    /// Whether the reading is good. Until it is, the bar uses the plain
    /// setting — there is nothing to wait for, only something to improve.
    readonly property bool ready: isFinite(root.luminance)

    readonly property real luminance: math.meanLuminance(quantizer.colors)

    readonly property real value: math.opacityFor(
        Config.values.bar.surface.opacity, root.luminance)

    readonly property SurfaceOpacity math: SurfaceOpacity {}

    readonly property ColorQuantizer quantizer: ColorQuantizer {
        source: Paths.fileUrl(Config.wallpaper)
        // 2^3 = 8 colours is plenty for a mean, and cheaper than the 16 the
        // accent work (#59) will want.
        depth: 3
        // Without a rescale the quantizer walks every pixel of a 5824×3264
        // wallpaper. The docs ask for one; 64px is what the theming research
        // settled on.
        rescaleSize: 64
    }
}
