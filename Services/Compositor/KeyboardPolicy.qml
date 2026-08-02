// What `hyprctl devices` says about the keyboard, as pure functions (#37).
//
// This is a parser as well as a policy, and it is a parser because Quickshell
// has no keyboard type: the Hyprland module models monitors, workspaces and
// toplevels natively, and nothing at all about input devices (surveyed against
// the 0.3.0 type info — there is no `devices` model to bind to). So the
// compositor facade next door runs `hyprctl devices -j` and hands the reply
// here, and the two awkward facts about that reply live in this file:
//
//   - **A machine has several keyboards.** The internal one, the USB one, and
//     one virtual device per running client that ever created a virtual
//     keyboard. Only one of them is the one Hyprland switches layouts on, and
//     it is the one flagged `main`.
//   - **The layouts are a comma-separated string in an XKB field**, not a list:
//     `"us,de"` with `active_layout_index: 1`. A machine with one layout is the
//     overwhelmingly common case and is exactly the case the module hides for.
//
// Imports nothing but QtQuick, so tests/ can reach it.
import QtQuick

QtObject {
    id: policy

    /// The Hyprland events after which the answer can have changed. Everything
    /// else the compositor emits is about windows.
    ///
    /// `activelayout` fires on a layout switch and carries the keyboard's name
    /// and the *human* layout name ("English (US)"), which is not the code the
    /// module shows — so it is used as a trigger to re-ask rather than parsed.
    /// A parser for that string would be a second, weaker source of truth for
    /// something one subprocess answers exactly.
    readonly property var layoutEvents: ["activelayout"]

    /// What `hyprctl devices -j` says, as `{ device, layouts, active }`:
    /// the name to switch on, the layout codes in the order Hyprland cycles
    /// them, and the index of the live one.
    ///
    /// An unreadable or unexpected reply answers "no keyboards", which the
    /// module reads as "nothing to show" — the same as a machine with one
    /// layout. A bar that guessed would be a bar claiming a layout is active
    /// when the shell has no idea which one is.
    function read(json: var): var {
        const empty = { device: "", layouts: [], active: 0 };

        let reply = json;
        if (typeof reply === "string") {
            try {
                reply = JSON.parse(reply);
            } catch (error) {
                return empty;
            }
        }
        if (!reply || !Array.isArray(reply.keyboards))
            return empty;

        const keyboard = policy.mainKeyboard(reply.keyboards);
        if (!keyboard)
            return empty;

        const layouts = policy.layouts(keyboard.layout);
        // An index the reply itself cannot justify — out of range, missing —
        // is reported as the first layout rather than dropped: which layout is
        // live is a smaller thing to be wrong about than whether there are any.
        const active = Number.isInteger(keyboard.active_layout_index)
                    && keyboard.active_layout_index >= 0
                    && keyboard.active_layout_index < layouts.length
            ? keyboard.active_layout_index : 0;

        return { device: String(keyboard.name ?? ""), layouts: layouts, active: active };
    }

    /// The keyboard Hyprland switches layouts on. `main` is the flag; the first
    /// entry is the fallback for a reply that sets it on none of them, because
    /// a shell that showed nothing there would be hiding a layout the user can
    /// see changing.
    function mainKeyboard(keyboards: var): var {
        for (const keyboard of keyboards)
            if (keyboard && keyboard.main === true)
                return keyboard;
        return keyboards.length > 0 ? keyboards[0] : null;
    }

    /// `"us,de"` → `["us", "de"]`. Blank entries are dropped: a trailing comma
    /// in a hand-written hyprland.conf is not a third layout.
    function layouts(field: var): var {
        if (field === undefined || field === null)
            return [];
        return String(field).split(",").map(name => name.trim()).filter(name => name !== "");
    }

    /// What the bar shows: the XKB code, uppercased. Two or three letters that
    /// people already read on every other bar — the human name ("English (US)")
    /// is four times the width for the same information.
    function label(layouts: var, active: int): string {
        if (!Array.isArray(layouts) || active < 0 || active >= layouts.length)
            return "";
        return String(layouts[active]).toUpperCase();
    }

    /// Whether the module belongs on the bar at all.
    ///
    /// **One layout is no module** (#9, and the ticket's own acceptance
    /// criterion). A machine with a single layout can never be in the wrong
    /// one, so a permanent `US` is furniture that says nothing and costs a
    /// module gap — the same rule the status cluster's bluetooth glyph follows.
    function showing(layouts: var): bool {
        return Array.isArray(layouts) && layouts.length > 1;
    }

    /// The argv that moves to the next layout.
    ///
    /// **`switchxkblayout` is a hyprctl command and not a dispatcher**, which is
    /// the trap here and cost this ticket a harness run to find: sending it
    /// through `Hyprland.dispatch` answers `Invalid dispatcher` and changes
    /// nothing. Measured against Hyprland 0.56.1, where `hyprctl dispatch
    /// switchxkblayout current next` is refused and `hyprctl switchxkblayout
    /// current next` answers `ok`. So this is the second subprocess the facade
    /// owns, alongside the layer rule — and it is argv for the reason
    /// LayerRulePolicy's is.
    ///
    /// `next` rather than an index, because Hyprland owns the cycle and an
    /// index computed here would disagree with it the moment a layout is added
    /// to the compositor config without the shell being told.
    function cycleCommand(device: string): var {
        return ["hyprctl", "switchxkblayout", device, "next"];
    }

    /// Did it happen? `ok` is the whole of Hyprland's yes — the same reply,
    /// read the same way, as the layer rule next door, and for the same reason:
    /// `hyprctl` exits 0 when it refuses something (#78).
    function switched(exitCode: int, output: string): bool {
        return exitCode === 0 && String(output ?? "").trim() === "ok";
    }
}
