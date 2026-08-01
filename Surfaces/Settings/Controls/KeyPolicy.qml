// What a key press means in the settings window (#77), as pure functions.
//
// Split out of the controls for the reason Surfaces/Lock/LockPolicy.qml is split
// out of the lock: this file imports nothing but QtQuick, so tests/ can reach it
// — and every keyboard decision the window makes is a decision rather than a
// picture, so all of them belong on that side of the line. What is left in the
// controls is `activeFocusOnTab`, a focus ring, and a call into here.
//
// #77 shipped the window pointer-only: every control drove off a `TapHandler`,
// nothing was focusable, and Escape did nothing. That is the whole of the
// keyboard path, so it is one treatment in `Controls/` rather than seven, and
// #55's six remaining tabs inherit it by being built out of the same controls.
import QtQuick

QtObject {
    id: policy

    // --- what a key does -----------------------------------------------------

    /// Whether this key activates the focused control — toggles the switch,
    /// picks the chip, presses the icon button.
    ///
    /// Space and Enter both, because the shell's controls are a mix of buttons
    /// (Space, by X11 convention) and list selections (Enter), and a settings
    /// window is not the place to make someone remember which is which.
    function isActivate(key: int): bool {
        return key === Qt.Key_Space || key === Qt.Key_Return || key === Qt.Key_Enter;
    }

    /// Whether this key dismisses the window.
    function isDismiss(key: int): bool {
        return key === Qt.Key_Escape;
    }

    /// Which way an arrow points: -1 back, +1 on, 0 for anything else.
    ///
    /// Both axes, deliberately. The tab rail is vertical and a chip row is
    /// horizontal, and a control that only answered its own axis would leave
    /// half the arrow keys dead on a surface whose whole complaint was that the
    /// keyboard did nothing.
    function step(key: int): int {
        if (key === Qt.Key_Left || key === Qt.Key_Up)
            return -1;
        if (key === Qt.Key_Right || key === Qt.Key_Down)
            return 1;
        return 0;
    }

    // --- moving through a list -----------------------------------------------

    /// The next index `delta` away from `index`, skipping entries that are
    /// present but not choosable, and stopping at the ends.
    ///
    /// `allowed` is one bool per entry: a theming mode whose service has not
    /// landed (#58, #59) is listed and inert, and an arrow key must walk past it
    /// rather than land on it and appear broken.
    ///
    /// Clamped rather than wrapped. Wrapping a three-item chip row means Right
    /// on the last chip silently selects the first, which reads as a misfire on
    /// a control whose whole point is that the alternatives are all visible.
    function advance(index: int, delta: int, allowed: var): int {
        if (delta === 0)
            return index;

        let next = index;
        for (let guard = 0; guard < allowed.length; guard++) {
            next += delta;
            if (next < 0 || next >= allowed.length)
                return index;
            if (allowed[next])
                return next;
        }
        return index;
    }

    /// The first choosable index, for a list whose current value is not in it —
    /// an arrow key on a chip row showing a value the schema has since dropped.
    function firstAllowed(allowed: var): int {
        for (let i = 0; i < allowed.length; i++)
            if (allowed[i])
                return i;
        return -1;
    }

    // --- moving a number -----------------------------------------------------

    /// A slider value as it should be written. `integers` is the knob's own
    /// answer to "is this a whole-number knob", taken from its shipped default:
    /// a knob whose default is `14` is not one anybody wants at `14.3`.
    ///
    /// Both the drag and the arrow keys go through here, so a value typed in by
    /// keyboard cannot differ in shape from the same value dragged to — and
    /// `0.8600000000000001` in a file meant to be read by hand is a bug
    /// whichever input produced it.
    function roundOff(value: real, integers: bool): real {
        return integers ? Math.round(value) : Math.round(value * 1000) / 1000;
    }

    /// A slider one step along, clamped to its range and rounded the same way.
    function nudge(value: real, delta: int, from: real, to: real, stepSize: real,
                   integers: bool): real {
        const stepped = value + delta * stepSize;
        return policy.roundOff(Math.max(from, Math.min(to, stepped)), integers);
    }

    // --- keeping the focused thing on screen ---------------------------------

    /// Where a `Flickable` has to scroll to for `itemY`..`itemY + itemHeight` to
    /// be inside the viewport, with `margin` of air around it. Returns the
    /// current `contentY` when the item is already visible, so tabbing along a
    /// row does not nudge the page.
    ///
    /// Without this the keyboard path is only half built: focus moves into a
    /// control below the fold and the window shows no sign of it, which is
    /// indistinguishable from Tab having done nothing.
    function scrollTo(contentY: real, viewportHeight: real, itemY: real, itemHeight: real,
                      margin: real, maxContentY: real): real {
        if (viewportHeight <= 0)
            return contentY;

        const ceiling = Math.max(0, maxContentY);
        const top = itemY - margin;
        const bottom = itemY + itemHeight + margin;

        // Top first: an item taller than the viewport is pinned to its top,
        // which is where its label is.
        if (top < contentY)
            return Math.max(0, Math.min(ceiling, top));
        if (bottom > contentY + viewportHeight)
            return Math.max(0, Math.min(ceiling, bottom - viewportHeight));
        return contentY;
    }
}
