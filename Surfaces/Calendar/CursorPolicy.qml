// What the pointer turns into over each part of the calendar.
//
// A cursor shape is the cheapest affordance a surface has and the only one that
// costs no pixels, so this window spends it deliberately: the hand says *this
// is pressable*, the vertical resize arrows say *this edge is draggable*, and
// the crosshair says *press here and a new event starts*. A window where
// everything is a hand says none of those things.
//
// **It is a decision, so it lives here rather than in five `cursorShape:`
// bindings.** Three surfaces ask the same question — the chip, its two edge
// strips, the empty grid — and the answer drifted between them once already: a
// grid that offered a hand promised a press that would open something, and what
// a press there actually does is draw a new event.
//
// The second reason it is a policy is that seam 2 can read it. A cursor shape
// is not something the client draws, it is a `wp_cursor_shape_device_v1
// .set_shape` request (`tools/cursor-harness.sh`, #185) — so `waylandShape`
// carries the protocol number the shell will send, `name` carries the word the
// surface logs, and `tests/tst_cursorpolicy.qml` pins the pair together. A log
// line that says `cursor ns-resize` and a protocol request that says `27` are
// then two readings of one decision rather than two decisions.
pragma ComponentBehavior: Bound
import QtQuick

QtObject {
    id: policy

    /// The zones, as the surface names them. `chip` is a chip's body,
    /// `chip-edge` either of its resize strips, `grid` the empty time grid, and
    /// `chrome` everything in the toolbar and sidebar that takes a click.
    /// Anything else — rulers, headers, washes — is `idle`.
    readonly property var zones: ["chip", "chip-edge", "grid", "chrome", "idle"]

    /// The word. This is what goes in the shell log, and it is the CSS name
    /// rather than the Qt enum name so the log reads the same as the protocol.
    function name(zone: string): string {
        switch (String(zone || "")) {
        case "chip":
        case "chrome":
            return "pointing-hand";
        case "chip-edge":
            return "ns-resize";
        case "grid":
            return "crosshair";
        }
        return "default";
    }

    /// The `wp_cursor_shape_device_v1` enum value the compositor will see.
    /// 4 pointer, 8 crosshair, 27 ns-resize, 1 default — the numbers
    /// `tools/cursor-harness.sh` greps out of a `WAYLAND_DEBUG` log.
    function waylandShape(zone: string): int {
        switch (policy.name(zone)) {
        case "pointing-hand":
            return 4;
        case "crosshair":
            return 8;
        case "ns-resize":
            return 27;
        }
        return 1;
    }

    /// Which zone a point inside a chip `h` tall is in, given the depth of the
    /// resize strips at each end. Same arithmetic `DragPolicy` uses to decide
    /// whether a press is a move or a resize, asked of a hover instead — the
    /// two must agree or the pointer promises an edge the press does not take.
    function chipZone(y: real, h: real, edge: real): string {
        const height = Math.max(0, h);
        const depth = Math.max(0, Math.min(edge, height / 2));
        if (depth <= 0)
            return "chip";
        if (y <= depth || y >= height - depth)
            return "chip-edge";
        return "chip";
    }
}
