// How a settings row divides its width between prose and control (#80).
//
// Pure arithmetic, no Quickshell, so tests/ can reach it — the row itself is a
// picture and this is the decision inside it.
//
// The bug it exists for: `SettingRow` gave the text column `Layout.fillWidth`
// ("take what is left over") and the control slot an unbounded `implicitWidth`
// ("never shrink"). Together those mean the control is served first however
// wide it is. A `SettingChoice` of three chips is wider than the content pane,
// so on the Appearance tab the hint wrapped one word per line and the chips ran
// off the right edge of the window — the control the row exists to present was
// off-screen and unreachable.
//
// The fix is a floor under the text and a ceiling over the slot, which is what
// is below. Both numbers are in one place because every tab is built out of
// `SettingRow` and #55 adds six more tabs on top of it.
import QtQuick

QtObject {
    id: metrics

    /// The narrowest the label-and-hint column may be squeezed to. A hint is
    /// body prose at ~11.5pt, and below roughly this it stops being a paragraph
    /// and starts being a column of words.
    readonly property int textFloor: 260

    /// The narrowest a control may be squeezed to before the row stops taking
    /// width off it. Below this a wrapped chip row is one chip per line, which
    /// is no more readable than the overflow it replaced.
    readonly property int slotFloor: 140

    /// Air around the focus ring a control draws when it is tabbed to, so the
    /// ring is not clipped by the row's own edge (#77).
    readonly property int focusInset: 3

    /// The widest a control may be in a row `rowWidth` across, where `taken` is
    /// what the rest of the row already spends — the layout spacing and the
    /// reset affordance.
    ///
    /// The floor wins on a narrow window: at the window's minimum size a
    /// three-chip control wraps rather than being crushed, and it is the row
    /// that grows taller, not the text that disappears.
    function slotCeiling(rowWidth: real, taken: real): real {
        return Math.max(metrics.slotFloor, rowWidth - metrics.textFloor - taken);
    }

    /// What a control that can wrap should actually be: its natural
    /// single-line width, or the ceiling if that is narrower. A control
    /// narrower than the ceiling keeps its size, so a switch stays a switch and
    /// does not float away from the right edge of the row.
    function slotWidth(naturalWidth: real, ceiling: real): real {
        if (ceiling <= 0)
            return naturalWidth;
        return Math.min(naturalWidth, ceiling);
    }
}
