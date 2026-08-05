// The region picker's window (#51) — the layer surface the drag happens on,
// and the only thing in the shell that can grab the frozen frame.
//
// The picture is PickerOverlay.qml next door, kept separate so seam 3 can
// render it. What is here is the three things that need a compositor: the
// layer surface and its keyboard grab, the pointer gestures, and the crop.
//
// ## The crop is a clipped Item, not a second capture
//
// `Screenshot.commit()` emits `saveRequested`; this file positions `cropper`
// over the frozen frame, grabs it at the region's *native* size and writes the
// PNG. The alternative — hide the picker, then run `grim -g` on the live screen
// — reintroduces exactly what freeze mode exists to remove: the screen is free
// to change between the freeze the user aimed at and the capture they get, and
// the overlay has to be gone before the shutter or it photographs itself.
//
// Measured: a `grabToImage` crop of a grim freeze is bit-identical to cropping
// the same PNG with Pillow — max channel difference 0 over 600x450 px. So this
// costs nothing in fidelity and removes a race.
//
// ## Why `cropper` sits behind the freeze rather than being hidden
//
// `grabToImage` renders an item's subtree into an FBO, and an item with
// `visible: false` is not rendered at all — the grab comes back empty. So the
// cropper is a real, visible item parked at `z: -1` underneath the full-screen
// frozen image, which is opaque and covers it completely. It renders, it is
// grabbable, and it is never seen.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Services.Screenshot

Variants {
    model: Quickshell.screens

    PanelWindow {
        id: window

        required property ShellScreen modelData

        /// Only on the screen the freeze was taken of. The other outputs get a
        /// window that is never visible rather than no window at all, so that
        /// moving to a second monitor does not need a reload.
        readonly property bool mine: Screenshot.screen === window.modelData.name

        readonly property bool showing:
            Screenshot.active && window.mine && Screenshot.freeze !== ""

        screen: modelData
        anchors { top: true; bottom: true; left: true; right: true }

        visible: window.showing

        // Above everything, including the bar and any drawer: the freeze
        // already contains all of them, so a shell surface drawn over the
        // picker would be that surface twice — once in the photograph and once
        // on top of it.
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "forest-shell:screenshot"
        WlrLayershell.keyboardFocus: window.showing ? WlrKeyboardFocus.Exclusive
                                                    : WlrKeyboardFocus.None

        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0

        color: "transparent"

        // The whole surface takes input while it is up — a picker you can click
        // through is a picker that selects the window it just gave focus to.
        mask: Region {
            width: window.showing ? window.width : 0
            height: window.showing ? window.height : 0
        }

        // --- state ------------------------------------------------------------

        property real originX: 0
        property real originY: 0
        property bool dragging: false
        property rect selection: Qt.rect(0, 0, 0, 0)
        property var hovered: null

        /// A drawn rectangle with its edges pulled onto window edges, when the
        /// user wants that. Off, the rectangle is returned untouched — the
        /// setting is the difference between a screenshot of a window and one
        /// with four pixels of desktop down its side, and some people want the
        /// four pixels.
        function snapped(drawn: var): var {
            if (Screenshot.settings.snapToWindows === false)
                return drawn;
            return Screenshot.policy.snap(drawn, Screenshot.windows, Screenshot.bounds);
        }

        function reset(): void {
            window.dragging = false;
            window.selection = Qt.rect(0, 0, 0, 0);
            window.hovered = null;
        }

        onShowingChanged: if (!window.showing) window.reset()

        // --- the picture ------------------------------------------------------

        PickerOverlay {
            id: overlay
            anchors.fill: parent

            freezeSource: Screenshot.freeze
            windows: Screenshot.windows
            selection: window.selection
            hovered: window.hovered
            outputScale: Screenshot.scale
        }

        // --- the gestures -----------------------------------------------------

        FocusScope {
            anchors.fill: parent
            focus: window.showing

            // Focus is taken on the window becoming visible rather than at
            // `Component.onCompleted`: a layer surface is built before it is
            // mapped, and `forceActiveFocus()` on an unmapped window is a
            // silent no-op (#81).
            onFocusChanged: if (focus) forceActiveFocus()

            Keys.onEscapePressed: Screenshot.cancel("escape")

            MouseArea {
                // pointer-exempt: a region picker aims rather than presses —
                // the crosshair below is the affordance, and a hand would say
                // the pixel under it is a control (#185).
                id: pointer
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.CrossCursor

                onPositionChanged: mouse => {
                    if (!window.dragging) {
                        window.hovered = Screenshot.policy.hit(Screenshot.windows,
                                                               mouse.x, mouse.y);
                        return;
                    }

                    const drawn = Screenshot.policy.normalise(window.originX, window.originY,
                                                              mouse.x, mouse.y);
                    // Snapped while the drag is live, so the edge the user is
                    // about to release on is the edge they can see.
                    const fitted = Screenshot.policy.clamp(window.snapped(drawn),
                                                           Screenshot.bounds);
                    window.selection = Qt.rect(fitted.x, fitted.y, fitted.width, fitted.height);
                }

                onPressed: mouse => {
                    if (mouse.button === Qt.RightButton) {
                        Screenshot.cancel("right click");
                        return;
                    }
                    window.originX = mouse.x;
                    window.originY = mouse.y;
                    window.dragging = true;
                    window.selection = Qt.rect(0, 0, 0, 0);
                }

                onReleased: mouse => {
                    if (mouse.button !== Qt.LeftButton || !window.dragging)
                        return;
                    window.dragging = false;

                    const drawn = Screenshot.policy.normalise(window.originX, window.originY,
                                                              mouse.x, mouse.y);

                    if (Screenshot.policy.isRegion(drawn)) {
                        Screenshot.commit(window.snapped(drawn), "drag");
                        return;
                    }

                    // Not a drag: take the window under the pointer. Without
                    // this a click captures three stray pixels and the snapping
                    // looks broken (ScreenshotPolicy.isRegion).
                    const under = Screenshot.policy.hit(Screenshot.windows, mouse.x, mouse.y);
                    if (under) {
                        window.selection = Qt.rect(under.x, under.y, under.width, under.height);
                        Screenshot.commit(under, "window: "
                                          + (under.title !== "" ? under.title : under.appId));
                        return;
                    }

                    Screenshot.cancel("clicked empty desktop");
                }
            }
        }

        // --- the crop ---------------------------------------------------------

        Item {
            id: cropper

            // Parked under the opaque frozen image — see the header.
            z: -1
            clip: true
            width: 1
            height: 1

            Image {
                id: cropSource
                source: Screenshot.freeze
                width: window.width
                height: window.height
                fillMode: Image.Stretch
                smooth: true
                cache: false
                asynchronous: false
            }
        }

        Connections {
            target: Screenshot

            function onSaveRequested(region, file, raster) {
                if (!window.mine)
                    return;

                cropper.width = region.width;
                cropper.height = region.height;
                cropSource.x = -region.x;
                cropSource.y = -region.y;

                // No `targetSize`, and that is the whole of getting the
                // resolution right. `grabToImage` renders the item at its
                // logical size and *then* multiplies by the surface's device
                // pixel ratio — which on this output is the 1.5 the region
                // already needs. Passing the native size as a target applied
                // the scale a second time and wrote a 900x675 file for a
                // 400x300 region (measured), with the log still claiming the
                // 600x450 it had asked for: a wrong picture that reads as a
                // right one.
                const ok = cropper.grabToImage(function (result) {
                    const written = result.saveToFile(file);
                    Screenshot.saved(file, written, raster);
                });

                if (!ok)
                    Screenshot.saved(file, false, raster);
            }
        }

        Component.onCompleted: if (window.mine)
            Logger.log("screenshot", Screenshot.policy.windowBuilt(window.modelData.name))
    }
}
