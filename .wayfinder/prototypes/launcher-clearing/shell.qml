// Entry point. Two modes, one file:
//
//   FS_SHOOT=1 qs-upstream -p shell.qml   scripted capture — walks a list of
//       scenes over a procedural stand-in desktop, grabbing each to shots/,
//       then exits. Keyboard focus is never taken, so it can run while you work.
//
//   qs-upstream -p shell.qml              live, over the real desktop: real
//       typing, real selection, real Hyprland layer blur. F1–F6 flip the knobs,
//       Esc quits. See run-live.sh for the layerrule.
import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
    id: shellRoot

    readonly property bool shootMode: Quickshell.env("FS_SHOOT") === "1"
    readonly property string outDir: Quickshell.shellDir + "/shots"

    PanelWindow {
        id: win
        screen: Quickshell.screens[0]
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "forest-shell:launcher-proto"
        // Never steal the keyboard while shooting.
        WlrLayershell.keyboardFocus: shellRoot.shootMode ? WlrKeyboardFocus.None
                                                         : WlrKeyboardFocus.Exclusive

        // Everything lives inside one QML-declared Item: `win.contentItem` is a
        // C++-side proxy with no QML engine attached, and grabToImage refuses it.
        Item {
            id: canvas
            anchors.fill: parent

            // The stand-in desktop. Live mode leaves it off and lets the
            // compositor show through — the comparison being what Hyprland's
            // blur can and can't reproduce (see findings.md).
            Backdrop {
                id: backdrop
                anchors.fill: parent
                flavour: "ridge"
                visible: shellRoot.shootMode || scene.fakeDesktop
            }

            Fog {
                id: fog
                anchors.fill: parent
                backdrop: backdrop.visible ? backdrop : null
                mode: "fog"
            }

            Clearing {
                id: clearing
                anchors.fill: parent
                focus: !shellRoot.shootMode
                Keys.onPressed: event => scene.handleKey(event)
            }
        }

        // --- scene driver -------------------------------------------------
        QtObject {
            id: scene
            property bool fakeDesktop: false

            function apply(s) {
                backdrop.flavour = s.wall || "ridge";
                fog.mode = s.scrim || "fog";
                fog.blurred = s.blurred === undefined ? true : s.blurred;
                clearing.fieldStyle = s.field || "horizon";
                clearing.panelStyle = s.panel || "strata";
                clearing.rowHaze = s.haze === undefined ? true : s.haze;
                clearing.godRay = s.godRay === undefined ? true : s.godRay;
                clearing.showLegend = s.legend === undefined ? true : s.legend;
                clearing.showCategory = s.category === undefined ? true : s.category;
                clearing.horizonFraction = s.horizon || 0.32;
                clearing.query = s.query || "";
                clearing.selected = s.selected || 0;
                clearing.claudeTurns = s.turns || [];
                clearing.claudeStreaming = s.streaming || "";
            }

            function handleKey(event) {
                switch (event.key) {
                case Qt.Key_Escape:
                    Qt.exit(0);
                    return;
                case Qt.Key_F1:
                    fog.mode = fog.mode === "fog" ? "dusk"
                             : fog.mode === "dusk" ? "dim"
                             : fog.mode === "dim" ? "fogGradient" : "fog";
                    return;
                case Qt.Key_F2:
                    clearing.fieldStyle = clearing.fieldStyle === "horizon" ? "boxed" : "horizon";
                    return;
                case Qt.Key_F3:
                    clearing.panelStyle = clearing.panelStyle === "strata" ? "card" : "strata";
                    return;
                case Qt.Key_F4:
                    clearing.rowHaze = !clearing.rowHaze;
                    return;
                case Qt.Key_F5:
                    backdrop.flavour = backdrop.flavour === "ridge" ? "forest"
                                     : backdrop.flavour === "forest" ? "busy" : "ridge";
                    return;
                case Qt.Key_F6:
                    scene.fakeDesktop = !scene.fakeDesktop;
                    return;
                case Qt.Key_F7:
                    clearing.horizonFraction = clearing.horizonFraction > 0.35 ? 0.22
                                             : clearing.horizonFraction > 0.27 ? 0.42 : 0.32;
                    return;
                case Qt.Key_Down:
                    clearing.selected = Math.min(clearing.selected + 1, clearing.rows.length - 1);
                    return;
                case Qt.Key_Up:
                    clearing.selected = Math.max(clearing.selected - 1, 0);
                    return;
                case Qt.Key_Backspace:
                    clearing.query = clearing.query.slice(0, -1);
                    return;
                }
                if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32)
                    clearing.query += event.text;
            }
        }

        // --- scripted capture ---------------------------------------------
        readonly property var claudeTranscript: [
            { role: "user", text: "what's the difference between a wayland layer surface and a regular toplevel?" },
            { role: "assistant", text: "A layer surface is positioned by the compositor against a screen edge or filled to the whole output, sits in one of four fixed layers (background, bottom, top, overlay), and can reserve exclusive space so other windows tile around it. A toplevel is an ordinary application window the compositor may tile, float, stack or fullscreen." }
        ]

        // Every scene is the baseline with exactly one knob moved, so any two
        // shots can be diffed by eye.
        readonly property var scenes: [
            { file: "01-baseline",           s: {} },
            { file: "02-scrim-dim",          s: { scrim: "dim" } },
            { file: "03-scrim-fog-gradient", s: { scrim: "fogGradient" } },
            { file: "04-wall-forest",        s: { wall: "forest" } },
            { file: "05-wall-busy",          s: { wall: "busy" } },
            { file: "06-wall-busy-dim",      s: { wall: "busy", scrim: "dim" } },
            { file: "07-field-boxed",        s: { field: "boxed" } },
            { file: "08-panel-none",         s: { panel: "none" } },
            { file: "09-panel-card",         s: { panel: "card" } },
            { file: "10-rowhaze-off",        s: { haze: false } },
            { file: "11-godray-off",         s: { godRay: false } },
            { file: "12-category-selected-only", s: { category: false } },
            { file: "13-apps-query",         s: { query: "co", selected: 0 } },
            { file: "14-apps-query-busy",    s: { query: "co", wall: "busy" } },
            { file: "15-apps-query-panel-none", s: { query: "co", panel: "none" } },
            { file: "16-calculator",         s: { query: "=1920*0.62" } },
            { file: "17-clipboard",          s: { query: ";", selected: 1 } },
            { file: "18-emoji",              s: { query: ":", selected: 2 } },
            { file: "19-actions",            s: { query: "/", selected: 0 } },
            { file: "20-ask-claude",         s: { query: "?", turns: win.claudeTranscript, streaming: "" } },
            { file: "21-no-matches",         s: { query: "qqzz" } },
            { file: "22-horizon-high",       s: { horizon: 0.22, query: "co" } },
            { file: "23-horizon-low",        s: { horizon: 0.42, query: "co" } },
            { file: "24-legend-off",         s: { legend: false, query: "co" } },
            // dusk: the option the study surfaced, against the same three walls
            { file: "25-scrim-dusk",         s: { scrim: "dusk" } },
            { file: "26-scrim-dusk-busy",    s: { scrim: "dusk", wall: "busy" } },
            { file: "27-scrim-dusk-forest",  s: { scrim: "dusk", wall: "forest" } },
            { file: "28-scrim-dusk-panel-none", s: { scrim: "dusk", panel: "none" } },
            { file: "29-scrim-fog-panel-none-busy", s: { panel: "none", wall: "busy" } },
            { file: "30-ask-claude-dusk",    s: { query: "?", turns: win.claudeTranscript, scrim: "dusk" } },
            { file: "31-ask-claude-dusk-panel-none", s: { query: "?", turns: win.claudeTranscript, scrim: "dusk", panel: "none" } },
            { file: "32-apps-query-dusk-panel-none", s: { query: "co", scrim: "dusk", panel: "none" } },
            { file: "33-baseline-dusk-busy-panel-none", s: { scrim: "dusk", wall: "busy", panel: "none" } },
            // what each scrim degrades to when the compositor won't blur
            { file: "34-fog-no-compositor-blur",  s: { blurred: false } },
            { file: "35-dusk-no-compositor-blur", s: { scrim: "dusk", panel: "none", blurred: false } },
            { file: "36-dusk-no-blur-busy",       s: { scrim: "dusk", panel: "none", blurred: false, wall: "busy" } }
        ]

        property int shotIndex: -1

        Timer {
            id: shooter
            running: shellRoot.shootMode
            interval: 700
            repeat: true

            // grabToImage renders asynchronously: anything applied between the
            // request and the callback lands in the picture. So the scene only
            // advances *inside* the callback — otherwise every file quietly
            // holds the next scene's state, which looks like a working capture.
            property bool pending: false

            onTriggered: {
                if (pending) return;
                if (win.shotIndex < 0) {        // first tick: let fonts settle
                    win.shotIndex = 0;
                    scene.apply(win.scenes[0].s);
                    return;
                }
                var current = win.scenes[win.shotIndex];
                pending = true;
                canvas.grabToImage(function (result) {
                    result.saveToFile(shellRoot.outDir + "/" + current.file + ".png");
                    console.log("shot", current.file);
                    win.shotIndex++;
                    if (win.shotIndex >= win.scenes.length) {
                        shooter.running = false;
                        doneTimer.running = true;
                        return;
                    }
                    scene.apply(win.scenes[win.shotIndex].s);
                    shooter.pending = false;
                });
            }
        }

        Timer {
            id: doneTimer
            interval: 1200
            onTriggered: { console.log("shots complete"); Qt.exit(0); }
        }
    }
}
