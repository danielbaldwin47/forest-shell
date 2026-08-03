// What the background window actually draws.
//
// The gradient underneath is not a placeholder: it is what an unset wallpaper
// looks like, and what shows through if the configured file goes missing or
// fails to decode.
import QtQuick
import Quickshell
import qs.Core

Item {
    id: root

    required property ShellScreen screen

    readonly property string source: Paths.fileUrl(Config.wallpaper)

    // Decode budget. The wallpaper is decoded *twice* at startup and there is
    // no way around it from QML: the layer surface is configured at scale 2
    // and then corrected to the output's real 1.5, and QQuickImage re-requests
    // its file whenever the window's device-pixel-ratio changes (measured, not
    // assumed — the pixmap cache does not dedupe across the change either).
    // Both decodes land before the first frame, so `sourceSize` bounds each one
    // to the output rather than the file: a 5824×3264 wallpaper costs ~470 ms
    // per full-size decode and puts first frame past the 1.5 s budget (#22 §4).
    //
    // devicePixelRatio is not trusted for the multiplier: it reports 2 on this
    // machine's 1.5× output. Clamped to 1–2, it is an oversample bound, not a
    // raster size.
    //
    // `screen` is `required`, but required only means the instantiator must
    // name it — not that it holds a value when this binding first runs. The
    // lock builds its surface before the session-lock protocol has told it
    // which output it is on, so `surface.screen` is null for the first
    // evaluation and this read raised a TypeError every time the lock opened
    // (caught by tools/binds-harness.sh, #57). Falling back to 1 costs nothing:
    // the binding re-runs with the real ratio the moment the screen arrives,
    // and 1 is the no-oversample case rather than a wrong raster size.
    readonly property real decodeScale: screen
        ? Math.min(2, Math.max(1, screen.devicePixelRatio))
        : 1

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.bgBase }
            GradientStop { position: 1.0; color: Theme.bgSunken }
        }
    }

    Image {
        anchors.fill: parent
        // Not loaded until the screen is known. `sourceSize` below is what keeps
        // the decode bounded, and it cannot be computed without the screen — an
        // unbounded request here is a full-size synchronous decode of a
        // 5824×3264 file, which is the ~470 ms the budget above exists to avoid.
        // So the request waits rather than being made at the wrong size.
        source: root.screen ? root.source : ""
        visible: status === Image.Ready
        fillMode: Image.PreserveAspectCrop
        // Synchronous: a wallpaper that arrives a frame late is a visible flash
        // of empty desktop at login.
        asynchronous: false
        smooth: true
        // With sourceSize pinned, the re-request after the reparent asks for
        // exactly what the first one did, so it comes back from the pixmap
        // cache rather than decoding again.
        cache: true
        // Same transient null as `decodeScale` above — this binding still runs
        // while `source` is held empty, so it needs the guard too. The 0×0 it
        // falls back to would mean "unbounded" to Qt, which is why `source`
        // above waits rather than relying on this value being harmless.
        sourceSize: root.screen
            ? Qt.size(root.screen.width * root.decodeScale,
                      root.screen.height * root.decodeScale)
            : Qt.size(0, 0)

        onStatusChanged: {
            if (status === Image.Ready)
                Logger.log("background", "wallpaper " + root.source
                           + " (" + sourceSize.width + "×" + sourceSize.height + ")");
            else if (status === Image.Error)
                Logger.warn("background", "could not load wallpaper " + root.source);
        }
    }
}
