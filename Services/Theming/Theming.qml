pragma Singleton

// The theming mode switch (#58, #12 §6): which palette the shell is wearing and
// what, if anything, the wallpaper is allowed to say about it.
//
//     appearance.mode = "forest"    // the shipped palette, untouched
//                     = "accent"    // the constrained wallpaper-coupled accent
//                     = "dynamic"   // the full generated palette (#59)
//
// Every decision this service makes is in Services/Theming/AccentPolicy.qml and
// Services/Theming/MatugenPolicy.qml where tests/ can reach it. What is left
// here is the three things that need a running shell: reading the wallpaper,
// noticing when it changes, and writing the answer down.
//
// The two wallpaper-coupled modes read the same wallpaper by different means
// and land in the same key. The constrained accent quantizes it in-process and
// moves two roles; full dynamic hands the path to matugen and replaces all
// seventeen (Services/Theming/Matugen.qml). Which one is running is this
// file's business and nothing downstream's.
//
// ## Nothing here paints anything
//
// The result is written to `appearance.dynamic` and read back by
// Core/Theme.qml, which layers it under the user's own overrides. That is the
// whole delivery mechanism, and it is a settings key rather than a property on
// this singleton for three reasons:
//
//   - Core cannot import upwards. `Core/Theme.qml` is the one thing every
//     surface reads and it must not depend on `Services/`;
//   - consumers stay mode-blind. A surface reads `Theme.accentPrimary` and has
//     no way to discover whether a mode produced it, which is what the ticket
//     asks for and what keeps this from becoming a per-surface feature;
//   - the shell opens already wearing last session's accent. The quantizer is
//     asynchronous, so a property would start empty and the first frame would
//     paint the shipped teal and then jump. A file does not.
//
// The same key is where #59's generated palette will land, and the reason the
// schema flags it `derived`: it is what *this* machine sampled from *this*
// wallpaper, so a theme preset replaces it wholesale and never carries it to
// another machine (#56).
//
// ## When it recomputes, and when it refuses to
//
// The quantizer's source is the wallpaper, so a new wallpaper is a new reading
// with nothing to subscribe to. The mode changing and the dark/light flip are
// the other two inputs — the light row's accent is a different colour and
// starts from a different hue.
//
// An empty reading is not a failure and is not written: the quantizer answers
// off-thread and `colors` is empty until it does, so "not yet" leaves the
// previous answer standing. A reading that arrives and has no dominant hue *is*
// written — as nothing at all, which restores the shipped accent. Failing
// closed is the safety story and it has to be reachable.
import QtQuick
import Quickshell
import qs.Core

Singleton {
    id: root

    readonly property AccentPolicy policy: AccentPolicy {}

    /// The generated mode's rules, held here rather than read through
    /// `Matugen.policy`: both are pure `QtObject`s that cost nothing to
    /// instantiate, and a service reaching through another service into its
    /// child for a sentence it is about to log itself is a chain that makes the
    /// singleton's shape part of this file's business.
    readonly property MatugenPolicy generated: MatugenPolicy {}

    /// The shipped rows, unlayered. The shift is always measured from where the
    /// brief put the accent and never from what this service last produced —
    /// otherwise each wallpaper change would rotate from the previous result and
    /// the accent would walk off across a morning's worth of wallpapers.
    /// `Theme.palette` is the wrong thing to read here for exactly that reason:
    /// it already has this service's own output in it.
    readonly property Tokens tokens: Tokens {}

    readonly property string mode: Config.values.appearance.mode

    /// The wallpaper, named as a property so the change handler below is the
    /// dependency list. The quantizer notices its own source moving; matugen is
    /// a subprocess and notices nothing, so full-dynamic mode needs this.
    readonly property string wallpaper: Config.wallpaper

    /// Whether matugen may render the user's own templates (#59). An input to
    /// the *command*, so it is named here like the others: turning it on is a
    /// request to restyle the external apps now, and a shell that waited for the
    /// next wallpaper change to honour it would look like a switch that did
    /// nothing.
    readonly property bool templates: Config.values.appearance.matugenTemplates

    readonly property ColorQuantizer quantizer: ColorQuantizer {
        // Only in the mode that uses it: quantizing a 5824×3264 wallpaper is
        // not free, and a mode that is off should cost nothing. An empty source
        // gives an empty `colors`, which this service already treats as "not
        // yet" and never writes.
        source: root.mode === "accent" && Config.wallpaper !== ""
            ? Paths.fileUrl(Config.wallpaper) : ""
        // 2⁴ = 16 colours. The accent needs a hue *distribution* rather than a
        // mean, so it wants more clusters than the bar's adaptive opacity takes
        // (Surfaces/Bar/AdaptiveOpacity.qml, depth 3) — 16 is what the research
        // swept the reference images at.
        depth: 4
        // The docs ask for a rescale and mean it: without one the quantizer
        // walks every pixel of the original.
        rescaleSize: 64
    }

    onModeChanged: root.retune()
    onWallpaperChanged: root.retune()
    onTemplatesChanged: root.retune()

    Connections {
        target: root.quantizer
        function onColorsChanged() { root.retune(); }
    }

    Connections {
        target: Theme
        // The light row's accent is a different colour at a different hue, so
        // the same wallpaper earns a different answer in the other mode. The
        // generated palette is two whole rows apart for the same reason.
        function onDarkChanged() { root.retune(); }
    }

    Connections {
        target: Matugen

        // The probe is asynchronous, so a session that opens already in
        // full-dynamic mode reaches `retune()` before the answer to "is it
        // installed" exists. This is that answer arriving.
        function onProbedChanged() { root.retune(); }

        // The palette matugen produced, delivered the same way the constrained
        // accent's is: written to `appearance.dynamic` and read back by
        // Core/Theme.qml, so consumers stay mode-blind and nothing downstream
        // can tell which mode painted it.
        function onGenerated(palette, lifted) {
            if (root.mode !== "dynamic")
                return;   // the mode moved while the run was out
            if (root.same(root.current(), palette))
                return;
            Config.set("appearance.dynamic", palette);
        }
    }

    /// Recompute, and write the answer only if it is news.
    ///
    /// Guarded rather than bound: this ends in a settings write, and a binding
    /// that writes the file it reads from is how a loop gets built. The three
    /// inputs — the mode, the wallpaper's colours and the dark/light flip — are
    /// named as change handlers above so the dependencies are that list rather
    /// than whatever an expression happened to touch.
    function retune() {
        if (root.mode === "dynamic") {
            root.regenerate();
            return;
        }
        if (root.mode !== "accent") {
            root.clear();
            return;
        }

        // Dropped before the quantizer is asked anything. The accent's own
        // recompute is asynchronous and its source only starts loading when the
        // mode becomes "accent", so a switch that waited for it would leave the
        // shell wearing all seventeen generated roles — backgrounds included —
        // for as long as the quantize took. The ticket asks for that switch to
        // restore *instantly*, and instant is the shipped row now and the tuned
        // accent a moment later, not the previous mode's palette held over.
        if (root.generated.generatedHere(root.current()))
            root.clear();

        const colors = root.quantizer.colors;
        if (!colors || colors.length === 0)
            return;   // the quantizer has not answered yet; keep what we have

        const reading = root.policy.dominantHue(colors);
        const shipped = root.tokens.palette(Theme.dark, null, null);
        const next = root.policy.accentFor(reading, shipped, Theme.dark);

        // Declining is a decision, and it is logged every time it is taken —
        // including on a session that has nothing stored to drop. "The mode ran
        // and this wallpaper has no hue" and "the service never ran" look
        // identical from outside otherwise, and that ambiguity is what #81 cost
        // a week.
        if (Object.keys(next).length === 0) {
            Logger.log("theming",
                       root.policy.keptLine(reading.concentration, reading.sampled));
            root.forget();
            return;
        }
        if (root.same(root.current(), next))
            return;

        Config.set("appearance.dynamic", next);
        Logger.log("theming", root.policy.tunedLine(
            root.policy.toOklch(next.accentPrimary).H, reading.concentration,
            next.accentPrimary));
    }

    /// Ask matugen for a palette (#59).
    ///
    /// Nothing is cleared on the way in. The previous palette stays on screen
    /// until a new one arrives, which is what makes a wallpaper change a
    /// restyle rather than a flash of the shipped forest and then a restyle —
    /// and what makes a failed run cost nothing at all.
    ///
    /// The missing-binary path is a log line and no palette. It is reachable
    /// only from a hand-edited config: the settings window greys the mode out
    /// when `Matugen.available` is false, so the shell says so in the one place
    /// left that can (#81).
    function regenerate() {
        if (!Matugen.probed)
            return;   // the probe has not answered; `onProbedChanged` calls back
        if (!Matugen.available) {
            if (!root.warned) {
                root.warned = true;
                Logger.warn("theming", root.generated.absentLine());
            }
            return;
        }
        root.warned = false;
        Matugen.run(root.wallpaper, Theme.dark, root.templates);
    }

    /// Whether the missing-binary line has been said. Said once per stretch of
    /// the mode being unserveable rather than once per wallpaper change: the
    /// same sentence eight times in a row is a log nobody reads.
    property bool warned: false

    /// Back to the shipped palette because the mode says so — announced only
    /// when there is a sample to drop, since a mode that never sampled has
    /// nothing to say and `theming ready (mode …)` has already said which mode
    /// it is in.
    function clear() {
        const stored = root.current();
        if (Object.keys(stored).length === 0)
            return;
        // Which mode wrote it, read off what it wrote. The key carries no
        // provenance — two modes write to it — and the thing that tells them
        // apart is the contract each one keeps: a generated palette is every
        // role or it is refused, and the constrained accent is two of them. The
        // two lines are different sentences because they are different amounts
        // of shell going back to the shipped look, and a log that called both
        // "accent cleared" would make the bigger one unfindable.
        Logger.log("theming", root.generated.generatedHere(stored)
                   ? root.generated.clearedLine(root.mode)
                   : root.policy.clearedLine(root.mode));
        root.forget();
    }

    /// Drop the sampled accent, if there is one.
    ///
    /// `reset` and not a write of `{}`: the settings file is sparse, and a key
    /// deleted is a key that follows the shipped default if it ever changes.
    function forget() {
        if (Object.keys(root.current()).length === 0)
            return;
        Config.reset("appearance.dynamic");
    }

    function current(): var {
        return Config.values.appearance.dynamic ?? ({});
    }

    /// Whether two role → colour maps say the same thing. Cheap, and the reason
    /// a wallpaper that quantizes to the same hues twice does not rewrite the
    /// settings file twice.
    function same(one: var, other: var): bool {
        const keys = Object.keys(one);
        if (keys.length !== Object.keys(other).length)
            return false;
        return keys.every(key => one[key] === other[key]);
    }

    Component.onCompleted: {
        Logger.stage("theming ready (mode " + root.mode + ")");
        root.retune();
    }
}
