// One settings control's wire into the config engine (#54).
//
// Every control on every tab holds one of these and nothing else: it names a
// dotted path, reads the live value, and writes through `Config.set`. That is
// what makes the GUI ground rules true by construction rather than by
// discipline — writes are sparse and preserve unknown keys because `Config.set`
// is the only way in, and a hand edit to `settings.json` moves the control
// because the value is a *binding* on `Config.values`, which the reload
// replaces wholesale.
//
// Two kinds of target, one interface:
//
//   ConfigBinding { path: "appearance.darkMode" }                — a leaf
//   ConfigBinding { path: "bar.surface"; knob: "opacity" }       — one knob of
//                                                                  a themed group
//
// The second exists because a theme-flagged group (#56) is a *single* leaf
// carrying a whole sub-object — a preset has to replace it atomically — so
// there is no path to `bar.surface.opacity` and the write is a read-modify-write
// of the whole group. Callers never see that difference.
//
// Not in Widgets/: everything there is dumb by contract and takes its value as a
// property (Widgets/README.md). This reads Config, which is exactly the line
// that directory draws, so the settings-form controls live with the surface
// that uses them. When the control centre wants a switch, the *switch* is what
// moves to Widgets/, not this.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core

QtObject {
    id: root

    /// Dotted path of the leaf, e.g. `bar.height`. For a themed group, the path
    /// of the *group* — `bar.surface` — with `knob` naming the key inside it.
    required property string path

    /// Key inside a themed group, or empty for an ordinary leaf.
    property string knob: ""

    /// The live value. A binding and not a cached copy: `Config.values` is
    /// replaced whole on every write and every reload, so an external edit to
    /// the file moves the control with nothing subscribed and nothing polled
    /// (#54 — "external hand-edit reflected live in the GUI").
    ///
    /// Walked here rather than through `Config.get()` so the dependency on
    /// `Config.values` is a real one: a binding that only calls a function does
    /// not re-evaluate when the function's data changes.
    readonly property var value: {
        let node = Config.values;
        for (const key of root.path.split("."))
            node = node === undefined || node === null ? undefined : node[key];
        return root.knob === "" ? node : (node === undefined ? undefined : node[root.knob]);
    }

    /// The spec node this path resolves to — `{ def, coerce, … }` for a leaf,
    /// and for a group the node carrying its `knobs` table.
    readonly property var leaf: {
        let node = Config.schema.spec;
        for (const key of root.path.split("."))
            node = node === undefined || node === null ? undefined : node[key];
        return node ?? null;
    }

    /// What this control's knob declares — label, range, closed list. Null for
    /// an ordinary leaf, which has no such table: a leaf's control says what it
    /// is at the call site, because there is one of it.
    readonly property var spec: root.knob === "" ? null : (root.leaf?.knobs?.[root.knob] ?? null)

    /// The shipped default, for the reset affordance and for "this is not the
    /// default" marks.
    readonly property var defaultValue: root.knob === ""
        ? root.leaf?.def
        : root.leaf?.def?.[root.knob]

    readonly property bool modified: !store.equals(root.value, root.defaultValue)

    /// Writes the value. False when the config engine refused it — an unknown
    /// key, a value the coercer will not take, or a `settings.json` that cannot
    /// currently be read (a half-typed hand edit). Controls surface that rather
    /// than snapping back silently.
    function commit(next: var): bool {
        if (root.knob === "")
            return Config.set(root.path, next);

        // Read-modify-write of the whole group: it is one key, and writing a
        // bare `{ opacity: … }` would be a preset-style replacement that drops
        // every other knob. Read from the group and not from this knob — a knob
        // that is currently absent is exactly the case where the *other* keys
        // are the ones that must survive.
        const group = Object.assign({}, Config.get(root.path) ?? {});
        group[root.knob] = next;
        return Config.set(root.path, group);
    }

    /// Removes a key from an open map leaf — `appearance.paletteOverrides` is
    /// the one in v1. An override is not a knob with a default that could be
    /// written back; the way to stop overriding a palette role is for the role
    /// not to be in the object.
    function removeKnob(): bool {
        const group = Object.assign({}, Config.get(root.path) ?? {});
        delete group[root.knob];
        return Config.set(root.path, group);
    }

    /// Back to the shipped default. Three shapes, one verb:
    ///
    ///   - a leaf resets by key *deletion*, so a later change to the shipped
    ///     default reaches the user (#21);
    ///   - a knob of a themed group writes its default back, because the group
    ///     is one key and the other knobs in it are staying;
    ///   - a key of an open map has no default, so it is removed.
    function resetValue(): bool {
        if (root.knob === "")
            return Config.reset(root.path);
        return root.defaultValue === undefined ? removeKnob() : commit(root.defaultValue);
    }

    readonly property QtObject store: SpecStore {}
}
