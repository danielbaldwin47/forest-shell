// The wallpaper end of the bar's legibility floor (#79): read the strip of the
// wallpaper the bar actually covers, and say how opaque the fill has to be for
// the text on it to hold 4.5:1. Surfaces/Bar/SurfaceOpacity.qml has the
// arithmetic and the reasoning; this file is the part that needs a wallpaper.
//
// This replaces `adaptiveOpacity`, which was the same shape as a *taste*
// setting — off by default, "less translucency as the wallpaper brightens" —
// sitting next to a schema clamp that was supposed to be the safety net. #79
// measured the safety net at 2.73:1 and the taste knob recovering it to 3.18:1,
// so the two have been folded into one thing that is always on and is
// calibrated rather than shaped by feel.
//
// Three measurements shape how the strip is read (all reproducible with
// tools/measure-strip-floor.py, and the probes in that script's header):
//
//   `imageRect` is in the *source file's* pixels and crops before quantizing,
//   so the strip has to be mapped back through PreserveAspectCrop by hand. A
//   rect that overhangs the file is padded with black rather than clamped, and
//   black reads as "dark wallpaper, nothing to do" — the one failure mode here
//   that is silent, which is why `stripRect` is unit-tested at every aspect
//   ratio and refuses to answer without an intrinsic size.
//
//   The quantizer averages: a 100px bright block in an otherwise dark strip
//   came back as #6e6e6c rather than #faf8f5 at depth 3. So the strip is not
//   quantized for its palette — it is rescaled to one pixel per ~40px of screen
//   and given more buckets than it has pixels, which makes the returned colours
//   the per-cell means. The brightest of those is the brightest run of
//   wallpaper a line of text can sit on.
//
//   Cells are narrower than the 100px window measure-contrast.py reports on, so
//   the reading is the strict side of the metric of record rather than the
//   lenient one.
//
// Cost, honestly: the intrinsic size of an image is not available from QML
// without decoding it, so there is one full-size decode per wallpaper change
// (~1 s for the largest wallpaper on this machine, a 27 MiB 5824×3264 PNG),
// async, released as soon as the size is read. Nothing here is on the
// first-frame path — the bar paints at the user's setting and firms up when the
// answer arrives, on the fog curve rather than as a snap
// (Surfaces/Bar/BarSurface.qml).
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Core

QtObject {
    id: root

    /// The screen this bar is on. Set at load — the bar's windows are created
    /// and destroyed by hotplug and by nothing else, so it never changes under
    /// a live instance.
    property ShellScreen screen

    /// The floor the fill must not paint below, or `NaN` while the wallpaper
    /// has not been read. Never lowers anything: `SurfaceOpacity.effectiveOpacity`
    /// takes the greater of this and the user's setting.
    readonly property real floor: root.hasReading
        ? policy.minimumOpacity(root.look, root.brightest, Theme.textSecondary, root.target)
        : NaN

    /// Whether the reading is good. Until it is, the bar uses the plain setting
    /// — there is nothing to wait for, only something to improve.
    readonly property bool ready: isFinite(root.floor)

    /// The ratio the clamp actually solves for.
    ///
    /// 4.5:1 is the body-text floor #10 and #68 both cite. The margin on top of
    /// it is the measured gap between what the runtime can see and the metric
    /// of record: the quantizer hands back a strip already averaged down its
    /// 32px height, and averaging colour before taking luminance reads slightly
    /// darker than taking luminance per row and averaging that.
    ///
    /// 0.6 is the smallest margin that holds over every wallpaper on this
    /// machine — `tools/measure-strip-floor.py ~/Pictures/wallpaper --sweep`,
    /// which is also what says why it is not smaller: at 0.4 one of the 173
    /// lands at 4.34:1 and at 0.2 thirty of them do.
    readonly property real target: 4.5 + root.margin
    readonly property real margin: 0.6

    readonly property var surface: Config.values.bar.surface

    /// Everything that stands between the wallpaper and the text, which is
    /// everything the floor has to account for.
    readonly property var look: ({
        surface: Theme.surface,
        fogWash: Theme.fogWash,
        hairlineColor: Theme.borderSubtle,
        mistWash: root.surface.mistWash,
        grain: root.surface.grain,
        topLight: root.surface.topLight,
        topLightAmount: root.surface.topLightAmount,
        // The hairline is not drawn on a floating bar — an island has no
        // horizon, it has a shape (Surfaces/Bar/BarSurface.qml).
        hairline: root.surface.hairline && !Config.values.bar.floating,
        // The same expression BarContent hands BarSurface: a top-anchored bar
        // draws its edge along the bottom, and a bottom-anchored one along the
        // top.
        hairlineAtBottom: Config.values.bar.position === "top",
        rows: Config.values.bar.height
    })

    readonly property bool hasReading: policy.brightest(quantizer.colors) !== null

    readonly property color brightest: root.hasReading
        ? policy.brightest(quantizer.colors) : "transparent"

    readonly property SurfaceOpacity policy: SurfaceOpacity {}

    /// The wallpaper file, and its intrinsic size — the second of which is the
    /// only reason the probe below exists.
    readonly property string wallpaper: Paths.fileUrl(Config.wallpaper)

    property int imageWidth: 0
    property int imageHeight: 0

    /// The area the wallpaper is painted into, which is what PreserveAspectCrop
    /// resolves against and so what decides which pixels of the file are on
    /// screen at all. The screen, in the shell — the wallpaper is one
    /// full-screen item behind everything (Surfaces/Background/Wallpaper.qml).
    /// Settable because the capture harness draws that same wallpaper into a
    /// scene of its own size, and a clamp that assumed the screen there would
    /// solve for a crop of the file that is not the one in the picture.
    property int viewWidth: root.screen ? root.screen.width : 0
    property int viewHeight: root.screen ? root.screen.height : 0

    /// The part of the file under the bar, in the file's own pixels. `null`
    /// until the intrinsic size has arrived, which is what keeps the quantizer
    /// from ever reading a rect that is a guess.
    ///
    /// A floating bar is inset from the screen edge and reads the strip it
    /// actually covers — the flush strip would miss the rows along its far edge
    /// entirely, and missing rows are the failure that does not show up as a
    /// wrong number (Surfaces/Bar/Bar.qml).
    readonly property var strip: policy.stripRect(
        root.imageWidth, root.imageHeight,
        root.viewWidth, root.viewHeight,
        Config.values.bar.height, Config.values.bar.position,
        Config.values.bar.floating ? Config.values.bar.floatMarginH : 0,
        Config.values.bar.floating ? Config.values.bar.floatMarginV : 0)

    /// How finely the strip is read: 64 cells across the screen, so a cell is
    /// 30px at 1920 and 60px at 3840 — either way narrower than the 100px
    /// window the measurement of record uses, which puts the reading on the
    /// strict side of it. 64 is also the bucket count at depth 6, so every cell
    /// gets its own bucket and the returned colours are cell means rather than
    /// a palette.
    readonly property int cells: 64

    readonly property Image probe: Image {
        // Never rendered and never cached: this is here to answer one question
        // and then let go of ~76 MB of decoded pixmap.
        asynchronous: true
        cache: false
        visible: false

        onStatusChanged: {
            if (status !== Image.Ready)
                return;
            root.imageWidth = sourceSize.width;
            root.imageHeight = sourceSize.height;
            // The size is the whole point of the decode; drop the pixels.
            source = "";
        }
    }

    readonly property ColorQuantizer quantizer: ColorQuantizer {
        // Gated on the rect rather than bound alongside it: with no imageRect
        // this quantizes the *whole* wallpaper, which is the averaged reading
        // #79 rejected, and it would be live for the moment between the two
        // bindings settling.
        source: root.strip ? root.wallpaper : ""
        imageRect: root.strip ? root.strip : Qt.rect(0, 0, 1, 1)
        // Deep enough that every cell gets its own bucket, so the returned
        // colours are the per-cell means rather than a palette of the strip.
        depth: 6
        rescaleSize: root.cells
    }

    readonly property Connections wallpaperChanges: Connections {
        target: root
        function onWallpaperChanged() { root.readIntrinsicSize(); }
    }

    /// Logged where the reading arrives rather than off `onFloorChanged`, and
    /// that is not a style choice — it is the only place the "nothing to do"
    /// case is visible.
    ///
    /// A floor of 0 is the honest answer on a third of the wallpapers here, and
    /// 0 is also what a `real` property holds before its binding is first
    /// evaluated. So a dark wallpaper resolves the binding from 0 to 0, no
    /// change signal is emitted, and a handler hung on that signal stays silent
    /// exactly when the clamp is working and deciding nothing — which is
    /// indistinguishable in a log from the clamp never running at all. Measured
    /// on a nested session before it was written this way round (#81 is the
    /// standing argument for caring).
    readonly property Connections readings: Connections {
        target: root.quantizer
        function onColorsChanged() {
            if (!root.ready) {
                Logger.log("bar", "legibility read nothing from the wallpaper strip"
                           + " — the bar stays at its setting");
                return;
            }
            Logger.log("bar", "legibility floor " + root.floor.toFixed(3)
                       + " from " + root.quantizer.colors.length + " cells, brightest "
                       + root.brightest + " (setting " + root.surface.opacity.toFixed(2)
                       + (root.floor > root.surface.opacity ? ", clamped up)" : ", honoured)"));
        }
    }

    function readIntrinsicSize() {
        root.imageWidth = 0;
        root.imageHeight = 0;
        probe.source = root.wallpaper;
    }

    // A strip that cannot be worked out is a clamp that will never run, and the
    // reason is worth having in the log rather than inferred from the absence
    // of the reading above.
    onStripChanged: {
        if (root.strip)
            Logger.log("bar", "legibility strip " + root.strip.width + "×" + root.strip.height
                       + " at " + root.strip.x + "," + root.strip.y
                       + " of " + root.imageWidth + "×" + root.imageHeight);
        else
            Logger.log("bar", "legibility strip unknown — wallpaper "
                       + (root.wallpaper || "unset") + " has no size yet");
    }

    Component.onCompleted: root.readIntrinsicSize()
}
