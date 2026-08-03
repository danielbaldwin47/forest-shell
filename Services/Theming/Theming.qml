pragma Singleton

// The theming mode switch (#58, #12 §6): which palette the shell is wearing and
// what, if anything, the wallpaper is allowed to say about it.
//
//     appearance.mode = "forest"    // the shipped palette, untouched
//                     = "accent"    // the constrained wallpaper-coupled accent
//                     = "dynamic"   // the full generated palette (#59)
//
// Every decision this service makes is in Services/Theming/AccentPolicy.qml
// where tests/ can reach it. What is left here is the three things that need a
// running shell: reading the wallpaper, noticing when it changes, and writing
// the answer down.
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

    /// The shipped rows, unlayered. The shift is always measured from where the
    /// brief put the accent and never from what this service last produced —
    /// otherwise each wallpaper change would rotate from the previous result and
    /// the accent would walk off across a morning's worth of wallpapers.
    /// `Theme.palette` is the wrong thing to read here for exactly that reason:
    /// it already has this service's own output in it.
    readonly property Tokens tokens: Tokens {}

    readonly property string mode: Config.values.appearance.mode

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

    Connections {
        target: root.quantizer
        function onColorsChanged() { root.retune(); }
    }

    Connections {
        target: Theme
        // The light row's accent is a different colour at a different hue, so
        // the same wallpaper earns a different answer in the other mode.
        function onDarkChanged() { root.retune(); }
    }

    /// Recompute, and write the answer only if it is news.
    ///
    /// Guarded rather than bound: this ends in a settings write, and a binding
    /// that writes the file it reads from is how a loop gets built. The three
    /// inputs — the mode, the wallpaper's colours and the dark/light flip — are
    /// named as change handlers above so the dependencies are that list rather
    /// than whatever an expression happened to touch.
    function retune() {
        if (root.mode !== "accent") {
            root.clear();
            return;
        }

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

    /// Back to the shipped palette because the mode says so — announced only
    /// when there is a sample to drop, since a mode that never sampled has
    /// nothing to say and `theming ready (mode …)` has already said which mode
    /// it is in.
    function clear() {
        if (Object.keys(root.current()).length === 0)
            return;
        Logger.log("theming", root.policy.clearedLine(root.mode));
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
