// The bar: one layer-shell window per screen, kept alive for the life of the
// shell (#12 §2, #22 §1).
//
// Windows are created and destroyed by screen hotplug and by nothing else. Not
// by auto-hide, not by a settings change, not by the drawers opening over the
// top — destroying and recreating layer surfaces is the compositor-crash class
// the reference-shell survey found, and the whole window discipline exists to
// avoid it. Hiding drops the *content* instead, after a debounce
// (Widgets/DebouncedLoader.qml), so a reveal inside the delay costs nothing and
// a hidden bar contributes zero wakeups.
//
// Uniform per screen with no per-monitor keys, per #22 §1: both target machines
// are single-monitor, so multi-monitor is a correctness tier that must not
// break and gets no tuning. A "bar on primary only" setting would be a dead
// setting on every machine this runs on.
//
// The bar is on the critical path to the first frame (#22 §4 — "first frame
// (wallpaper + bar rendered) ≤ 1.5 s"), so it is a direct child of the shell
// root rather than deferred. Its content still gates on `Config.ready` like
// every other surface, so nothing flashes a default and snaps (#12 §4).
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Core
import qs.Services.Compositor
import qs.Widgets

Scope {
    id: bar

    // The layer-shell namespace, and so the handle every Hyprland rule for the
    // bar is written against.
    readonly property string layerNamespace: "forest-shell:bar"

    readonly property var settings: Config.values.bar

    // --- hide and show, from outside the pointer (#70) ------------------------

    // The whole visibility decision lives next door, on the side of the line
    // tests/ can reach (tests/tst_barvisibility.qml).
    BarVisibilityPolicy { id: visibility }

    // What a keybind or a script has asked for: "auto", "shown" or "hidden".
    // Shell-wide rather than per-window, because the bar is uniform per screen
    // (#22 §1) and a per-monitor override would be the dead setting that
    // section rules out. `auto` is where it starts and where a second toggle
    // press puts it back.
    property string override: "auto"

    onOverrideChanged: Logger.log("bar", "override: " + bar.override)

    function toggle(source: string): bool {
        // Decided against the focused screen's window, which is the one the
        // user is looking at when they press the key. With one monitor — both
        // calibration machines — there is nothing to choose between.
        const ctx = bar.decisionContext();
        bar.override = visibility.next(ctx);
        Logger.log("bar", "toggle (" + source + "): "
                   + visibility.describe(bar.decisionContext()));
        return true;
    }

    function setOverride(value: string, source: string): bool {
        bar.override = value;
        Logger.log("bar", value + " (" + source + "): "
                   + visibility.describe(bar.decisionContext()));
        return true;
    }

    /// The context as the focused screen sees it, for the decisions that are
    /// taken once for the whole shell rather than per window. Hover is not in
    /// it: a toggle is about what the bar does when the pointer is not there.
    function decisionContext(): var {
        return visibility.context(bar.settings.autoHide, false, false,
                                  bar.override, Compositor.focusedFullscreen,
                                  true);
    }

    // No `show` on this target: the `qs ipc` client parses it as its own
    // subcommand, prints the target listing and exits 0 without calling
    // anything (#77, and the table in Core/SurfaceBusPolicy.qml). #70 asked
    // for `show`; `reveal` is that door under a name a person can actually
    // type.
    //
    // One handler for the shell, not one per screen: this Scope is outside
    // Variants and is instantiated once, and two IpcHandlers on one target is
    // one of them silently never answering.
    IpcHandler {
        target: "bar"

        function toggle(): bool {
            return bar.toggle("ipc");
        }

        function reveal(): bool {
            return bar.setOverride("shown", "ipc");
        }

        function hide(): bool {
            return bar.setOverride("hidden", "ipc");
        }

        /// Back to letting the settings and the compositor decide — the state
        /// a second `toggle` reaches on its own, spelled out for scripts that
        /// only ever call `reveal` and `hide`.
        function auto(): bool {
            return bar.setOverride("auto", "ipc");
        }

        function isRevealed(): bool {
            return visibility.revealed(bar.decisionContext());
        }
    }

    // The no-subprocess door, for the same reason the launcher has one
    // (Surfaces/Drawers/Drawers.qml): a `global` dispatch spawns no `qs` per
    // keypress. It cannot carry the `|| notify-send` fallback the exec binds
    // use — a global dispatch has nothing to fail — so both are documented in
    // integration/hyprland/forest-binds.conf and the user picks one.
    //
    //     bind = SUPER SHIFT, B, global, forest-shell:bar-toggle
    //
    // Nothing happens if the user has not written the bind, and that is not
    // worth logging on a timer: the IPC door above answers the same question.
    GlobalShortcut {
        appid: "forest-shell"
        name: "bar-toggle"
        description: "Show or hide the bar"

        onPressed: bar.toggle("shortcut")
    }

    // Blur is the compositor's job (#22 §6 forbids QML-side full-screen blur
    // outright), and a layerrule is how it is asked for. Pushed live rather
    // than left to the user's hyprland.conf so the bar looks the way it was
    // measured on a fresh install — and re-pushed when the setting changes,
    // because the fill is translucent enough that turning it off is visible.
    //
    // #35 asks for the layerrule "unconditionally", which is about *this*: the
    // shell ships the rule itself instead of asking the user to paste a line
    // into their compositor config, and it does not condition the rule on the
    // wallpaper the way the rejected fog band would have. It is still subject
    // to the two switches the same ticket's own sources define — #10 ships the
    // blur as a Bar-tab setting, and #22 §7 makes turning it off the first rung
    // of the `reducedEffects` ladder.
    //
    // Deferred: the first frame does not wait on a subprocess. The shell must
    // look correct with blur off, so there is nothing to gate on it.
    //
    // #78 asked whether a runtime `hyprctl keyword layerrule` is the right
    // mechanism at all, or whether this belongs in the user's own
    // hyprland.conf. Kept, for two reasons and one caveat. The transport is not
    // in doubt — a windowrule pushed the identical way applied instantly on the
    // same machine, and the layerrule now returns `ok` rather than the syntax
    // error it returned for four PRs. And a line in hyprland.conf cannot be a
    // setting: #10 ships this as a Bar-tab toggle and #22 §7 makes it the first
    // rung of the `reducedEffects` ladder, both of which have to take effect
    // while the shell is running. The caveat is that "accepted" and "blurred"
    // are still different claims: #78 could not tell them apart on a machine
    // where blur renders nowhere, so the first session on a machine where it
    // does is what confirms the rule has the effect it asks for.
    Connections {
        target: Startup
        function onDeferredStage() { bar.applyBlurRule(); }
    }

    Connections {
        target: Config
        function onKeyChanged(path) {
            if (Startup.deferredRan
                    && (path === "bar.surface" || path === "appearance.reducedEffects"))
                bar.applyBlurRule();
        }
    }

    function applyBlurRule() {
        // `reducedEffects` turns the compositor blur off first, at the top of
        // its cost ladder (#22 §7) — the rung itself is in Core/EffectsPolicy,
        // where the other two are and where it is unit-checked (#69).
        const wanted = Theme.blurRequested(bar.settings.surface.blur);
        // Off is `blur 0`, not a rule being taken away: Hyprland's 0.5x syntax
        // has no clearing verb (`unset` answers `invalid field unset`), and a
        // boolean rule needs its value spelled out either way. Rules accumulate
        // and the later one is what applies, so pushing the opposite is how the
        // setting is turned off. The value belongs here rather than inside the
        // facade because only this file knows what off means for blur.
        Compositor.setLayerRule(wanted ? "blur 1" : "blur 0", bar.layerNamespace);
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: window

            required property ShellScreen modelData

            readonly property var settings: bar.settings
            readonly property bool atTop: settings.position === "top"

            // Everything the visibility decision reads, built once here so the
            // four bindings below cannot drift apart. A binding, so a change to
            // any of it re-evaluates all four.
            readonly property var visibilityContext: visibility.context(
                settings.autoHide, hover.hovered, linger.running, bar.override,
                Compositor.focusedFullscreen, Compositor.isFocused(modelData))

            // Whether the bar is showing. Auto-hide and its reveal strip (#35),
            // a fullscreen window on this screen, and an explicit hide over IPC
            // or the keybind (#70) — resolved in Surfaces/Bar/
            // BarVisibilityPolicy.qml, which tests/ can reach.
            readonly property bool revealed: visibility.revealed(visibilityContext)

            screen: modelData

            anchors {
                top: window.atTop
                bottom: !window.atTop
                left: true
                right: true
            }

            margins {
                top: settings.floating && window.atTop ? settings.floatMarginV : 0
                bottom: settings.floating && !window.atTop ? settings.floatMarginV : 0
                left: settings.floating ? settings.floatMarginH : 0
                right: settings.floating ? settings.floatMarginH : 0
            }

            implicitHeight: settings.height

            // An auto-hiding bar does not reserve space — that is the point of
            // it. A pinned one does, and lets the compositor tile under it.
            // An explicitly hidden one gives its band back too; a fullscreen
            // one does not, because nothing is reading the zone while a
            // fullscreen surface is ignoring it (BarVisibilityPolicy).
            exclusionMode: visibility.reservesSpace(visibilityContext)
                           ? ExclusionMode.Auto : ExclusionMode.Ignore

            // The window paints nothing itself: the surface material is content
            // (Surfaces/Bar/BarSurface.qml), and while hidden there is
            // deliberately nothing there at all.
            color: "transparent"

            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: bar.layerNamespace
            // The bar is clicked, never typed into. #38 puts the drawers' fog
            // *below* this window so the bar stays clickable over it.
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // ...and being *below* the fog is only half of staying clickable:
            // while a drawer holds its focus grab, a click outside the grabbed
            // windows is consumed dismissing it. #27 wants the opposite here —
            // "clicking another bar icon triggers the cross-drawer transition
            // directly" — so the bar's windows join the grab (#38, and the
            // header of Core/FocusGrabWindows.qml). Announced rather than
            // reached for, because these are created and destroyed by hotplug.
            Component.onCompleted: FocusGrabWindows.keep(window)
            Component.onDestruction: FocusGrabWindows.release(window)

            // Input is masked to what is actually there: the whole bar while
            // it is showing, and a one-pixel reveal strip along the screen edge
            // while it is hidden. Without the mask a hidden auto-hide bar would
            // still swallow clicks meant for the window underneath it.
            mask: Region {
                item: window.revealed ? content : revealStrip
            }

            Item {
                id: revealStrip

                anchors {
                    left: parent.left
                    right: parent.right
                    top: window.atTop ? parent.top : undefined
                    bottom: window.atTop ? undefined : parent.bottom
                }
                height: 1
            }

            // Pointer anywhere in the window keeps the bar out; leaving starts
            // the linger, so crossing the bar on the way somewhere else does
            // not make it flap.
            HoverHandler {
                id: hover
                // Armed for the reasons the shell chose — auto-hide, and a
                // fullscreen window — and not after an explicit hide, which is
                // intent the pointer must not undo (#70).
                enabled: visibility.hoverArms(window.visibilityContext)
            }

            // No handler: the timer *running* is the state, and it stopping is
            // what re-evaluates `revealed`.
            //
            // Not a motion step — the ladder in Core/Tokens.qml is for things
            // that move, and this is a dwell. It is how long the bar waits
            // before believing you meant to leave, which wants to be longer
            // than any of the three animation durations and is a feel rather
            // than a measurement. It is deliberately not a setting: a knob for
            // it would be the kind of long-tail option #9 leaves in JSON, and
            // it has no JSON to be in until someone asks.
            Timer {
                id: linger
                interval: 400
            }

            Connections {
                target: hover
                function onHoveredChanged() {
                    if (hover.hovered)
                        linger.stop();
                    else if (visibility.hoverArms(window.visibilityContext))
                        linger.restart();
                }
            }

            Item {
                id: content

                anchors.fill: parent

                /// Where the content sits while the bar is away — out of the
                /// window on the side the bar is anchored to.
                readonly property real parkedY: window.atTop ? -height : height

                // Slides out of the window rather than shrinking it: the window
                // keeps its geometry, so nothing about the surface changes and
                // the compositor is not asked to resize anything.
                //
                // Reduced, it does not slide at all — it stays at y: 0 and
                // fades. This is the one transform in the shell that *is* a
                // surface's entrance, so it is the one rung 3 has to turn into
                // a fade rather than simply drop: a bar that popped in and out
                // would be the broken mode #22 §7 says this knob must not be
                // (#69). Input is unaffected either way — the window's mask,
                // not the content's position, is what stops a hidden bar
                // swallowing clicks.
                y: window.revealed || !Theme.animateTransforms ? 0 : content.parkedY

                // Two jobs in one property, which is why it is written as a
                // comparison rather than as `revealed`. Reduced, it is the
                // whole of the reveal. Unreduced, it is what makes the parked
                // content *gone* rather than merely off the window — and it
                // waits for the slide to finish before saying so, so the slide
                // is still visible, and so that turning the knob on while the
                // bar is hidden does not flash it on screen to fade it out.
                opacity: window.revealed
                         || (Theme.animateTransforms && content.y !== content.parkedY) ? 1 : 0

                // The second clause is about the knob rather than about the
                // bar: flipping it moves `y` too, and that move is not a
                // reveal. Without the guard, turning reduced effects *off*
                // while the bar is hidden would find the content parked at
                // y: 0 and slide a bar the user cannot see all the way out
                // across the screen. Hidden in either mode means "not visible",
                // so `opacity` is what tells the two kinds of move apart.
                Behavior on y {
                    enabled: Theme.animateTransforms
                             && (window.revealed || content.opacity > 0)
                    NumberAnimation {
                        duration: Theme.motionStandard
                        easing.type: Easing.Bezier
                        easing.bezierCurve: Theme.fogEase
                    }
                }

                // Only reduced, where entrance and exit are one duration — so
                // no ternary. Unreduced this property snaps, at the two moments
                // the content is entirely off the window anyway.
                Behavior on opacity {
                    enabled: !Theme.animateTransforms
                    NumberAnimation {
                        duration: Theme.duration(Theme.motionStandard)
                        easing.type: Easing.Bezier
                        easing.bezierCurve: Theme.fogEase
                    }
                }

                DebouncedLoader {
                    anchors.fill: parent
                    // Gated on the config, like every surface (#12 §4), and
                    // dropped again a beat after the bar hides.
                    shown: Config.ready && window.revealed
                    sourceComponent: contentComponent
                }

                Component {
                    id: contentComponent
                    BarContent { screen: window.modelData }
                }
            }
        }
    }
}
