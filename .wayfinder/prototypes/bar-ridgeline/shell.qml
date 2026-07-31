// forest-shell bar & ridgeline prototype (issue #10) — throwaway.
//
//   qs-upstream -p .wayfinder/prototypes/bar-ridgeline/shell.qml
//
// Draws the real bar as a layer-shell surface on the real screen, over a strip
// of wallpaper it paints itself (so the "near-flush with the wallpaper" claim
// is judged against a plausible forest wallpaper, not whatever is on the
// desktop, and so the existing shell's bar is covered). Input is masked to the
// bar itself — the rest of the strip clicks through.
//
// A floating control window drives every knob live; `Vars.dump()` prints the
// current configuration for pasting into the ticket.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "."

ShellRoot {
    id: rootShell

    property var wallpapers: [
        "/home/daniel/Pictures/wallpaper/forest-landscape.jpg",
        "/home/daniel/Pictures/wallpaper/mountain-lake.jpg",
        "/home/daniel/Pictures/wallpaper/deer_in_pine_forest.jpg",
        "/home/daniel/Pictures/wallpaper/sunset-in-thick-forest.jpg",
        "/home/daniel/Pictures/wallpaper/mountain-snow-minima.jpg",
        "/home/daniel/Pictures/wallpaper/natures-mountain-waters.jpg",
    ]
    property int wallpaperIndex: 0
    property var strip: null

    Component.onCompleted: Vars.wallpaper = wallpapers[0]

    PanelWindow {
        id: panel
        anchors { top: true; left: true; right: true }
        implicitHeight: Vars.showBackdrop
            ? Vars.backdropHeight
            : (Vars.barHeight + (Vars.floating ? Vars.floatMarginV * 2 : 0))
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "forest-proto"

        // Only the bar takes input; the wallpaper strip clicks through.
        mask: Region {
            x: barZone.x
            y: barZone.y
            width: barZone.width
            height: barZone.height
        }

        Item {
            id: stripContent
            anchors.fill: parent
            Component.onCompleted: rootShell.strip = stripContent

            // The desktop as forest-shell would have it: our own wallpaper,
            // cropped to the top of the screen exactly as a full-screen
            // wallpaper would be.
            Item {
                anchors.fill: parent
                clip: true
                visible: Vars.showBackdrop
                Image {
                    width: panel.screen.width
                    height: panel.screen.height
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    source: Vars.wallpaper ? "file://" + Vars.wallpaper : ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(panel.screen.width * 2, panel.screen.height * 2)
                    asynchronous: true
                }
            }

            Item {
                id: barZone
                anchors.top: parent.top
                anchors.topMargin: Vars.floating ? Vars.floatMarginV : 0
                anchors.horizontalCenter: parent.horizontalCenter
                width: Vars.floating ? parent.width - Vars.floatMarginH * 2 : parent.width
                height: Vars.barHeight

                Behavior on height { NumberAnimation { duration: Theme.motionStandard; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.fogEase } }

                Bar {
                    anchors.fill: parent
                    backdropSource: Vars.wallpaper ? "file://" + Vars.wallpaper : ""
                    backdropWidth: panel.screen.width
                    backdropHeight: panel.screen.height
                    backdropOffsetY: barZone.y
                }
            }
        }
    }

    Knobs {}

    // Scripted control, so screenshots can be driven without touching the UI:
    //   qs-upstream -p <this file> ipc call proto set barHeight 36
    //   qs-upstream -p <this file> ipc call proto capture /tmp/shot.png
    IpcHandler {
        target: "proto"

        function set(key: string, value: string): string {
            if (Vars[key] === undefined) return "no such key: " + key;
            const cur = Vars[key];
            let v = value;
            if (typeof cur === "boolean") v = (value === "true" || value === "1");
            else if (typeof cur === "number") v = parseFloat(value);
            Vars[key] = v;
            return key + " = " + Vars[key];
        }

        function get(): string { return Vars.dump(); }

        function wallpaper(index: string): string {
            rootShell.wallpaperIndex = parseInt(index) % rootShell.wallpapers.length;
            Vars.wallpaper = rootShell.wallpapers[rootShell.wallpaperIndex];
            return Vars.wallpaper;
        }

        // Grabs the strip (wallpaper + bar) at 2x — pixel-accurate to what is
        // on screen, and free of the self-capture problem a screencopy has.
        function capture(path: string): string {
            const item = rootShell.strip;
            if (!item) return "no strip";
            const ok = item.grabToImage(function (result) {
                result.saveToFile(path);
                console.log("captured", path);
            }, Qt.size(item.width * 2, item.height * 2));
            return ok ? "capturing " + path : "grab failed";
        }
    }
}
