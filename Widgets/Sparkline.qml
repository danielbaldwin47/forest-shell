// A minute of a number, as a row of forms (#50).
//
//     Sparkline {
//         values: [0.1, 0.4, NaN, 0.8]   // oldest first, 0..1
//         slots: 60
//         color: Theme.textSecondary
//     }
//
// The system monitor's row graph, and it has no idea what it is graphing: it
// takes a list of fractions and draws them, the way Widgets/Ridgeline.qml takes
// a list of cells. Dumb by contract, like everything in `Widgets/`: no Services,
// no Config, no Theme — colours and geometry arrive as properties.
//
// ## Right-aligned, fixed slots
//
// The newest sample is at the right edge and the row has a fixed number of
// slots, so a card that has been open for four seconds draws four bars against
// the right with empty space to their left — rather than four bars stretched
// across the full width, which would show a monitor whose history *narrows* as
// it gains samples. The scale is fixed the same way: 0 is the floor and 1 the
// top, never the range of what is in `values`, because a sparkline autoscaled to
// its own contents makes an idle machine look as busy as a loaded one.
//
// ## Gaps
//
// A NaN is a sample that could not be taken — the first CPU reading of a
// freshly-opened card has no previous snapshot to be a delta of
// (Services/System/SystemStatsPolicy.qml). It draws nothing at all, not a bar of
// zero: "not measured" and "measured as idle" are different, and the difference
// is exactly what someone stares at a monitor to see.
pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: root

    /// Oldest first, each 0..1. NaN is a gap.
    property var values: []

    /// How many samples fit across the row. The history feeding this is capped
    /// at the same number by the sampler.
    property int slots: 60

    property color color: "gray"

    /// Between forms. One logical pixel keeps 60 bars reading as a row rather
    /// than as a filled shape.
    property real gap: 1

    /// What a zero draws as. A row that vanished at idle would read as a
    /// monitor that had stopped rather than as a machine doing nothing.
    property real floorHeight: 1

    property real cornerRadius: 1

    readonly property int count: Math.max(1, root.slots)

    readonly property real barWidth:
        Math.max(1, (root.width - root.gap * (root.count - 1)) / root.count)

    /// The sample drawn in slot `index`, or NaN for a slot nothing has reached
    /// yet.
    ///
    /// This is the alignment rule in one place: `values` is oldest-first and the
    /// row is newest-at-the-right, so a history shorter than the row hangs off
    /// its right edge and a longer one is cropped from the left.
    function sample(index: int): real {
        return root.sampleFrom(root.list(root.values), root.count, index);
    }

    /// `values`, as something with a length, or an empty row.
    ///
    /// Tolerant of what it is handed, and it has to be: `Array.isArray` is
    /// false for a QML **sequence**, which is what a JavaScript array becomes
    /// on its way through a `Repeater`'s `modelData` — measured, and the reason
    /// this row drew nothing at all while the history behind it was sixty
    /// samples long. A string is excluded by name because it has a `length`
    /// too and is not a list of anything.
    function list(value): var {
        if (value === null || value === undefined || typeof value === "string")
            return [];
        return typeof value.length === "number" ? value : [];
    }

    /// The same rule with the row's state passed in, which is the form
    /// `slotValues` below uses — see the note there on why that matters.
    function sampleFrom(list: var, slots: int, index: int): real {
        const at = list.length - slots + index;
        if (at < 0 || at >= list.length)
            return NaN;
        const value = Number(list[at]);
        return isNaN(value) ? NaN : Math.max(0, Math.min(1, value));
    }

    /// Every slot's value, in drawing order, recomputed whenever the history or
    /// the row's width in slots changes.
    ///
    /// A property and not a call from each bar's own binding, which is what this
    /// was first: `value: root.sample(index)` looks equivalent and is not —
    /// measured, the bars kept the answer they were built with and never
    /// updated, so the row stayed empty while the history filled behind it. A
    /// binding that reads a property *inside a called function* does not always
    /// register it as a dependency; this one reads `values` and `count` in the
    /// binding itself, where the capture is not in doubt.
    readonly property var slotValues: {
        const list = root.list(root.values);
        const slots = root.count;
        const out = [];
        for (let i = 0; i < slots; i++)
            out.push(root.sampleFrom(list, slots, i));
        return out;
    }

    implicitHeight: 20

    Repeater {
        // Counted rather than enumerated, for the reason
        // Widgets/Ridgeline.qml documents: `values` arrives as a new array on
        // every sample, and a Repeater over a JS array rebuilds every delegate
        // when the identity changes. With the slot count as the model the bars
        // are rebound instead, so the row survives a sample without being
        // reconstructed sixty times a minute.
        model: root.count

        delegate: Rectangle {
            id: bar

            required property int index

            readonly property real value: root.slotValues[bar.index] ?? NaN

            x: bar.index * (root.barWidth + root.gap)
            width: root.barWidth
            height: isNaN(bar.value)
                    ? 0
                    : Math.max(root.floorHeight, bar.value * root.height)
            y: root.height - height

            visible: !isNaN(bar.value)
            color: root.color
            radius: root.cornerRadius
        }
    }
}
