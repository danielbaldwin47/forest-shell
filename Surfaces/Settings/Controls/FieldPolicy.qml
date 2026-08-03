// What a settings field will accept, before the config engine gets it (#55).
//
// `SettingText.validate` marks a value the coercer would refuse so the border
// goes ember and the commit is skipped — without it a rejected write is silent
// and the field reads as broken rather than as wrong. Each of those predicates
// is a *decision* about a value, which is the seam-1 side of the line
// (CLAUDE.md), and until this file they were six copies of one lambda written
// inline across three tabs with no test on any of them.
//
// Pure QtQuick, no Quickshell, so `tests/` can reach it — the same arrangement
// `RowMetrics.qml` and `KeyPolicy.qml` have, and for the same reason.
//
// None of these is the last word. The coercer is: `Core/Coerce.qml` clamps,
// falls back and salvages whatever arrives, including from a hand-edit that
// never passed through here. What these buy is the *warning*, and so they are
// deliberately permissive — a field that refused everything the schema merely
// normalises would be a field arguing with the file.
import QtQuick

QtObject {
    id: policy

    /// A path, or the empty string that means "work it out" / "not set".
    ///
    /// Absolute or `~`-relative and nothing else: a relative path in
    /// settings.json has no agreed base — the shell's working directory is
    /// whatever the compositor launched it from — so it is the one form that
    /// cannot be honoured. `~` is expanded by whoever reads the key rather than
    /// by a shell, which is why a path with a space in it is fine here.
    function looksLikePath(text: string): bool {
        return text === "" || text.startsWith("/") || text.startsWith("~");
    }

    /// A wall-clock time, 24-hour, as `system.nightLight.from` and `.to` are
    /// written. Anchored both ends: `19:00 ish` is not a time, and a schedule
    /// that silently did not start is the failure this warning exists for.
    function isClockTime(text: string): bool {
        return /^([01]\d|2[0-3]):[0-5]\d$/.test(text);
    }

    /// An idle-ladder timeout, in minutes. Fractional on purpose — the dim rung
    /// is 2.5 — and 0 is legal because 0 is what "off on this power source"
    /// means (#30). Blank is *not* legal: it is the one input that would land
    /// on the default rather than on what was typed.
    function isMinutes(text: string): bool {
        const value = Number(text);
        return text.trim() !== "" && isFinite(value) && value >= 0 && value <= 600;
    }

    /// The pool an ordered-list editor offers: everything the vocabulary knows
    /// that is not already placed.
    ///
    /// Three lists want this — the bar's clusters, the dashboard's cards, the
    /// control centre's grid and sliders — and the bar's is the one that spans
    /// several keys, which is why `placed` is passed in rather than read here.
    function pool(vocabulary: var, placed: var): var {
        const taken = Array.isArray(placed) ? placed : [];
        return (Array.isArray(vocabulary) ? vocabulary : [])
            .filter(id => taken.indexOf(id) < 0);
    }

    /// Which of a vocabulary's ids the thing that renders them cannot draw.
    ///
    /// The schema's vocabulary is deliberately ahead of the registry — a name
    /// the shell cannot render yet is dropped with a warning rather than
    /// refused (Surfaces/Bar/BarRegistry.qml), so a file written by a newer
    /// shell keeps its modules under an older one. The cost of that is a pool
    /// offering ids that do nothing when added, which is what #72 is about.
    ///
    /// `known` is the *renderer's own* table — `BarRegistry.modules`, an
    /// `id → { file, label }` map — and not a second list of unavailable ids.
    /// A list like that would have to be edited every time a module lands, and
    /// the failure mode of forgetting is the greying staying on a module that
    /// now works. Passing the registry's map means the greying goes away by
    /// itself the moment the registry grows an entry.
    /// No table at all greys nothing, rather than everything. This is a
    /// warning like the rest of this file and the permissive direction is the
    /// same one: an id wrongly greyed is one the user cannot add, while an id
    /// wrongly offered costs a console warning from the registry.
    function unsupported(vocabulary: var, known: var): var {
        if (known === undefined || known === null)
            return [];
        return (Array.isArray(vocabulary) ? vocabulary : [])
            .filter(id => known[id] === undefined);
    }

    /// A closed list as `SettingChoice` options, with the display names this
    /// window uses for them.
    ///
    /// The *list* is the schema's and only the wording is the GUI's, which is
    /// the settings README's "the schema is the single declaration" rule kept
    /// while still saying "Very high" rather than `very_high`. A value the
    /// labels do not name shows under its own id instead of vanishing — so a
    /// vocabulary that grows leaves an ugly chip here rather than an option the
    /// user cannot reach.
    function options(values: var, labels: var): var {
        const table = labels ?? ({});
        return (Array.isArray(values) ? values : [])
            .map(value => ({ value: value, label: table[value] ?? value }));
    }
}
