// The calendar's keyboard, as a lookup table rather than a pile of `Keys.on…`
// handlers.
//
// What it decides: given a key, the modifiers held with it, and what the
// surface currently has on screen, *which verb the calendar should run* —
// `{kind, arg}`, or `null` for "this key is not ours, let it through". Nothing
// here touches an event, a store or a window; the view switches on `kind` and
// does the work. That is what puts every shortcut at the first seam, where
// `tests/tst_keynavpolicy.qml` can hold the whole table to account without a
// compositor, a focus chain or a single delivered key press.
//
// Why it is worth a file: a keymap is exactly the kind of thing that rots
// silently. Two handlers claim `K`, a modifier check is `>= Qt.ControlModifier`
// instead of a mask, `?` arrives as `Key_Slash` on one layout and `Key_Question`
// on another — and every one of those is invisible in a screenshot and obvious
// in a table. The shortcuts sheet and the command menu are generated from the
// same source (`shortcutsTable`, `commands`), so a shortcut cannot be added to
// the keymap and forgotten in the help.
//
// ## The keymap (Notion Calendar's defaults)
//
//   D / W / M      view          day / week / month
//   T              today         jump the anchor to today
//   J / Left       period  -1    previous day, week or month
//   K / Right      period  +1    next
//   Up / Down      select        previous / next event of the visible range
//   C / Ctrl+N     create        new event at the anchor's next free slot
//   Enter          open          the selected event
//   Backspace/Del  delete        the selected event
//   Escape         close         the overlay if one is open, else the window
//   ? (Shift+/)    shortcuts     the shortcuts sheet
//   Ctrl+K         command       the command menu
//
// Only D/W/M switch views: `1`/`2`/`3` are deliberately *not* bound, because
// they are the digits a person types into a duration or a time field and
// stealing them is the bug this note exists to prevent.
//
// ## Three rules the table obeys
//
//   - **Ctrl outranks the bare letter.** `K` is next-period and `Ctrl+K` is the
//     command menu; the modifier is checked as a mask, and `Alt`/`Meta` on any
//     binding means "not ours" rather than "close enough".
//   - **A caret owns the keyboard.** With `ctx.typing` set, every binding but
//     `Escape` and the `Ctrl` pair returns `null`, so typing `d` into a title
//     field cannot flip the calendar to day view.
//   - **`?` is two keys.** X11 and Wayland layouts disagree about whether
//     Shift+/ arrives as `Key_Question` or as `Key_Slash` with Shift held, so
//     both are accepted and bare `/` is not.
//
// ## Calling convention
//
// `key` is a `Qt.Key_*` integer *or* a name string — `"D"`, `"Left"`, `"esc"`,
// `"?"` — because a test that has to spell `Qt.Key_Backspace` to ask a question
// about Backspace is a test nobody writes. `mods` is a `Qt.KeyboardModifiers`
// mask, or a string/array of names (`"ctrl+shift"`, `["Control"]`), or nothing
// at all for none. `keyName` is the normaliser and is public so the view can
// log what it saw.
//
// Dates are the same local wall-clock strings the rest of the calendar uses —
// a day is `"2026-08-18"`, a stamp is `"2026-08-18T09:15"` — and all the
// arithmetic is `CalendarTime`'s, so this file contains no `Date` either.
import QtQuick
import "../../Services/Calendar"

QtObject {
    id: policy

    property CalendarTime time: CalendarTime {}

    /// New events land on a quarter-hour, like every other edit in the grid.
    readonly property int snapMinutes: 15

    /// 09:00 — where `C` puts an event on a day that is not today. A day with
    /// no "now" in it has no better anchor than the top of the working day.
    readonly property int defaultCreateMinute: 540

    /// The last slot that still starts on the anchor's own day (23:45). `C` at
    /// 23:52 creates at 23:45 rather than rolling onto tomorrow, because the
    /// key means "here", and "here" is the day being looked at.
    readonly property int lastCreateMinute: 1440 - policy.snapMinutes

    // --- key naming -----------------------------------------------------------

    /// The non-letter keys the calendar binds, by `Qt.Key_*` code. Letters are
    /// not in here: they are a contiguous ASCII range and are folded directly.
    readonly property var namedKeys: ({
        [Qt.Key_Left]: "Left",
        [Qt.Key_Right]: "Right",
        [Qt.Key_Up]: "Up",
        [Qt.Key_Down]: "Down",
        [Qt.Key_Return]: "Return",
        [Qt.Key_Enter]: "Return",     // the keypad one is the same verb
        [Qt.Key_Escape]: "Escape",
        [Qt.Key_Backspace]: "Backspace",
        [Qt.Key_Delete]: "Delete",
        [Qt.Key_Question]: "Question",
        [Qt.Key_Slash]: "Slash"
    })

    /// Spellings a caller may reasonably use for the same key.
    readonly property var keyAliases: ({
        "left": "Left", "right": "Right", "up": "Up", "down": "Down",
        "arrowleft": "Left", "arrowright": "Right",
        "arrowup": "Up", "arrowdown": "Down",
        "return": "Return", "enter": "Return",
        "escape": "Escape", "esc": "Escape",
        "backspace": "Backspace", "back": "Backspace",
        "delete": "Delete", "del": "Delete",
        "question": "Question", "?": "Question",
        "slash": "Slash", "/": "Slash"
    })

    /// A `Qt.Key_*` code or a name string -> the one canonical name, or `""`
    /// for a key this policy has never heard of. `""` is the answer that makes
    /// `action` return `null`, so an unknown key is silently not ours.
    function keyName(key: var): string {
        if (typeof key === "number") {
            if (key >= Qt.Key_A && key <= Qt.Key_Z)
                return String.fromCharCode(key);
            const named = policy.namedKeys[key];
            return named === undefined ? "" : named;
        }
        if (typeof key !== "string")
            return "";
        const raw = key.trim();
        if (!raw)
            return "";
        if (raw.length === 1 && /[a-zA-Z]/.test(raw))
            return raw.toUpperCase();
        const alias = policy.keyAliases[raw.toLowerCase()];
        return alias === undefined ? "" : alias;
    }

    /// A modifier mask, a name string (`"ctrl+shift"`), an array of names, or
    /// nothing -> a `Qt.KeyboardModifiers` mask.
    ///
    /// Keypad and group-switch bits are stripped: they ride along with perfectly
    /// ordinary key presses and no binding here cares about either, so leaving
    /// them in would make `Enter` on the numeric keypad a different key.
    function modMask(mods: var): int {
        const ignored = Qt.KeypadModifier | Qt.GroupSwitchModifier;
        if (typeof mods === "number")
            return mods & ~ignored;
        let names = [];
        if (typeof mods === "string")
            names = mods.split(/[+\s,]+/);
        else if (mods && typeof mods.length === "number")
            names = mods;
        let mask = 0;
        for (let i = 0; i < names.length; i++) {
            switch (String(names[i]).toLowerCase()) {
            case "shift": mask |= Qt.ShiftModifier; break;
            case "ctrl": case "control": mask |= Qt.ControlModifier; break;
            case "alt": case "option": mask |= Qt.AltModifier; break;
            case "meta": case "super": case "cmd": mask |= Qt.MetaModifier; break;
            }
        }
        return mask;
    }

    // --- the table ------------------------------------------------------------

    /// The whole keymap. `{kind, arg}` or `null`.
    ///
    /// `ctx` is what the surface knows: `{view, anchorIso, nowIso, selectedId,
    /// selectedTitle, visibleEventIds, overlayOpen, typing}`. Every field is
    /// optional — a missing one only ever costs the bindings that need it.
    ///
    /// The kinds, and what the view does with each:
    ///
    ///   view       arg `"day"|"week"|"month"`   switch views
    ///   today      arg `null`                   anchor := today
    ///   period     arg `-1|+1`                  anchor := `shiftPeriod(...)`
    ///   select     arg an event id              select it
    ///   create     arg a stamp                  open quick-create there
    ///   open       arg an event id              open the editor
    ///   delete     arg an event id              delete it
    ///   close      arg `"overlay"|"window"`     dismiss one or the other
    ///   shortcuts  arg `null`                   the shortcuts sheet
    ///   command    arg `null`                   the command menu
    ///
    /// A binding whose subject is absent answers `null` rather than a verb with
    /// an empty argument: Enter with nothing selected opens nothing, and the
    /// view should not have to check.
    function action(key: var, mods: var, ctx: var): var {
        const name = policy.keyName(key);
        if (!name)
            return null;

        const mask = policy.modMask(mods);
        const ctrl = (mask & Qt.ControlModifier) !== 0;
        const shift = (mask & Qt.ShiftModifier) !== 0;
        if ((mask & (Qt.AltModifier | Qt.MetaModifier)) !== 0)
            return null;

        const c = ctx || {};

        // Ctrl first, so `Ctrl+K` is the command menu and not next-period.
        if (ctrl) {
            if (shift)
                return null;
            if (name === "K")
                return { "kind": "command", "arg": null };
            if (name === "N")
                return policy.createAction(c);
            return null;
        }

        // Escape outranks the caret: it is how a text field is escaped.
        if (name === "Escape")
            return { "kind": "close", "arg": c.overlayOpen ? "overlay" : "window" };
        if (c.typing)
            return null;

        if (name === "Question" || (name === "Slash" && shift))
            return { "kind": "shortcuts", "arg": null };
        if (shift)
            return null;

        switch (name) {
        case "D": return { "kind": "view", "arg": "day" };
        case "W": return { "kind": "view", "arg": "week" };
        case "M": return { "kind": "view", "arg": "month" };
        case "T": return { "kind": "today", "arg": null };
        case "J": case "Left": return { "kind": "period", "arg": -1 };
        case "K": case "Right": return { "kind": "period", "arg": 1 };
        case "Up": return policy.selectAction(c, -1);
        case "Down": return policy.selectAction(c, 1);
        case "C": return policy.createAction(c);
        case "Return":
            return c.selectedId ? { "kind": "open", "arg": c.selectedId } : null;
        case "Backspace": case "Delete":
            return c.selectedId ? { "kind": "delete", "arg": c.selectedId } : null;
        }
        return null;
    }

    /// `Up`/`Down` resolved against the visible range, so the view never has to
    /// re-derive it. `null` when there is nothing to select.
    function selectAction(ctx: var, delta: int): var {
        const c = ctx || {};
        const next = policy.nextSelection(c.visibleEventIds, c.selectedId, delta);
        return next ? { "kind": "select", "arg": next } : null;
    }

    /// `C` and `Ctrl+N` resolved to the stamp they would create at. `null` when
    /// the context carries no usable anchor day.
    function createAction(ctx: var): var {
        const stamp = policy.createStamp(ctx);
        return stamp ? { "kind": "create", "arg": stamp } : null;
    }

    // --- the arithmetic behind three of the verbs -----------------------------

    /// Where `C` puts a new event: the next quarter-hour from now when the
    /// anchor *is* today, and 09:00 when it is any other day — a stamp, or `""`
    /// if `ctx.anchorIso` is not a day.
    ///
    /// "Next" is a ceiling, so 13:45 on the nose stays 13:45 rather than
    /// skipping a slot, and the result never leaves the anchor's own day.
    function createStamp(ctx: var): string {
        const c = ctx || {};
        const anchor = c.anchorIso || "";
        if (!policy.time.isDay(anchor))
            return "";
        if (policy.time.dayOf(c.nowIso || "") !== anchor)
            return policy.time.formatStamp(anchor, policy.defaultCreateMinute);
        const now = policy.time.parseMinutes(c.nowIso);
        const snapped = Math.ceil(now / policy.snapMinutes) * policy.snapMinutes;
        return policy.time.formatStamp(anchor, Math.min(snapped, policy.lastCreateMinute));
    }

    /// The anchor `delta` periods away, in the units the current view counts in:
    /// a day, seven days, or a calendar month. `""` for a day that is not one or
    /// a view this policy does not know — never a guess, the way `CalendarTime`
    /// answers.
    ///
    /// The month step keeps the day of the month and **clamps** it: a month on
    /// from 2026-01-31 is 2026-02-28, not 2026-03-03. Rolling over would be the
    /// same class of silent wrong answer `Date` gives, arrived at by hand.
    function shiftPeriod(view: string, anchorIso: string, delta: int): string {
        const d = policy.time.parseDay(anchorIso);
        if (!d)
            return "";
        const step = Math.round(delta);
        switch (view) {
        case "day":
            return policy.time.addDays(anchorIso, step);
        case "week":
            return policy.time.addDays(anchorIso, step * 7);
        case "month": {
            const total = d.year * 12 + (d.month - 1) + step;
            const year = Math.floor(total / 12);
            const month = total - year * 12 + 1;
            return policy.time.dayIso(year, month,
                                      Math.min(d.day, policy.time.daysInMonth(year, month)));
        }
        }
        return "";
    }

    /// The days a view has on screen, as `{from, to}` inclusive — the range
    /// `Up`/`Down` walk, and the one the surface hands to
    /// `EventPolicy.forRange`. `null` for a day that is not one.
    ///
    /// The month case is the **calendar month**, 1st to last, and deliberately
    /// not the six-row grid: the grid's leading and trailing cells belong to
    /// the months either side, and arrowing off the end of August into a chip
    /// that is faintly greyed out because it is really September is a selection
    /// nobody asked for. What is legible in the grid and what is navigable are
    /// two different questions.
    function visibleRange(view: string, anchorIso: string, firstDay: int): var {
        const d = policy.time.parseDay(anchorIso);
        if (!d)
            return null;
        switch (view) {
        case "day":
            return { "from": anchorIso, "to": anchorIso };
        case "week": {
            const start = policy.time.weekStart(anchorIso, firstDay);
            return { "from": start, "to": policy.time.addDays(start, 6) };
        }
        case "month":
            return {
                "from": policy.time.dayIso(d.year, d.month, 1),
                "to": policy.time.dayIso(d.year, d.month,
                                         policy.time.daysInMonth(d.year, d.month))
            };
        }
        return null;
    }

    /// The id `delta` steps along `ids` from `current`, wrapping at both ends.
    /// `""` when the list is empty.
    ///
    /// With `current` absent from the list — it was just deleted, or the range
    /// scrolled away from it — a forward step lands on the first id and a
    /// backward one on the last, so `Down` always selects something.
    ///
    /// `ids` is length-checked rather than `Array.isArray`-checked: a QML
    /// sequence property handed in here is not an `Array` and would otherwise
    /// silently read as empty.
    function nextSelection(ids: var, current: string, delta: int): string {
        const list = (ids && typeof ids !== "string" && typeof ids.length === "number")
                   ? ids : [];
        const n = list.length;
        if (n === 0)
            return "";
        const step = Math.round(delta) || 0;
        let idx = -1;
        for (let i = 0; i < n; i++) {
            if (list[i] === current) {
                idx = i;
                break;
            }
        }
        if (idx < 0)
            return step < 0 ? list[n - 1] : list[0];
        return list[((idx + step) % n + n) % n];
    }

    // --- the same table, for humans -------------------------------------------

    /// Every binding as `{keys, label, group}`, in the order the shortcuts sheet
    /// prints it. Generated fresh on each call, because a `Repeater` handed the
    /// same array object back does not rebuild its delegates.
    ///
    /// Rows pair the alternatives that run the same verb (`J / ←`), which is
    /// what keeps this list the length of the *keymap* rather than the length
    /// of the key table.
    function shortcutsTable(): var {
        return [
            { "keys": "D", "label": "Day view", "group": "Views" },
            { "keys": "W", "label": "Week view", "group": "Views" },
            { "keys": "M", "label": "Month view", "group": "Views" },
            { "keys": "T", "label": "Jump to today", "group": "Navigate" },
            { "keys": "J / ←", "label": "Previous period", "group": "Navigate" },
            { "keys": "K / →", "label": "Next period", "group": "Navigate" },
            { "keys": "↑ / ↓", "label": "Select previous / next event", "group": "Navigate" },
            { "keys": "C / Ctrl+N", "label": "New event at the next slot", "group": "Events" },
            { "keys": "Enter", "label": "Open the selected event", "group": "Events" },
            { "keys": "Backspace / Del", "label": "Delete the selected event", "group": "Events" },
            { "keys": "Esc", "label": "Close the overlay, then the window", "group": "General" },
            { "keys": "?", "label": "Keyboard shortcuts", "group": "General" },
            { "keys": "Ctrl+K", "label": "Command menu", "group": "General" }
        ];
    }

    /// The same table gathered under its headings, `[{group, rows}]`, in the
    /// order the groups first appear. A sheet that regrouped by hand would be a
    /// second place the group names are written down.
    function shortcutsGroups(): var {
        const out = [];
        const seen = ({});
        const table = policy.shortcutsTable();
        for (let i = 0; i < table.length; i++) {
            const row = table[i];
            const name = row.group || "";
            if (seen[name] === undefined) {
                seen[name] = out.length;
                out.push({ "group": name, "rows": [] });
            }
            out[seen[name]].rows.push(row);
        }
        return out;
    }

    /// Those groups split into the sheet's two columns, `[left, right]`.
    ///
    /// Split by **printed height**, not by group count: a heading costs a row
    /// like everything else, so a 3-row group and a 4-row group are 4 and 5
    /// units. The left column takes whole groups until it is at least half the
    /// total, which keeps a group's rows under their own heading — the one rule
    /// a two-column reference cannot break, because a heading with nothing
    /// under it and rows with no heading above them are both unreadable.
    ///
    /// A single group is never split, so a table that is one long group prints
    /// as one column rather than as two halves of a list.
    function shortcutsColumns(): var {
        const groups = policy.shortcutsGroups();
        let total = 0;
        for (let i = 0; i < groups.length; i++)
            total += groups[i].rows.length + 1;
        const left = [];
        const right = [];
        let filled = 0;
        for (let j = 0; j < groups.length; j++) {
            if (left.length === 0 || (filled * 2 < total && j < groups.length - 1)) {
                left.push(groups[j]);
                filled += groups[j].rows.length + 1;
            } else {
                right.push(groups[j]);
            }
        }
        return [left, right];
    }

    /// What the command menu lists, as `{id, label, shortcut, group}`.
    ///
    /// `id` is the verb the view dispatches on — `"view.day"`, `"period.next"`
    /// — rather than an index, so reordering this list or filtering it cannot
    /// change what running an entry does.
    ///
    /// Two of them are context-dependent: open and delete appear only with
    /// something selected, and name it when `ctx.selectedTitle` is known, since
    /// "Delete the selected event" in a menu that hides what is selected is a
    /// question rather than a command.
    function commands(ctx: var): var {
        const c = ctx || {};
        const noun = ({ "day": "day", "week": "week", "month": "month" })[c.view] || "period";
        const subject = c.selectedTitle ? "“" + c.selectedTitle + "”" : "the selected event";
        const out = [
            { "id": "view.day", "label": "Day view", "shortcut": "D",
              "group": "View", "icon": "calendar" },
            { "id": "view.week", "label": "Week view", "shortcut": "W",
              "group": "View", "icon": "calendar-range" },
            { "id": "view.month", "label": "Month view", "shortcut": "M",
              "group": "View", "icon": "calendar-days" },
            { "id": "today", "label": "Jump to today", "shortcut": "T",
              "group": "Navigate", "icon": "calendar-check" },
            { "id": "period.previous", "label": "Previous " + noun, "shortcut": "J",
              "group": "Navigate", "icon": "chevron-left" },
            { "id": "period.next", "label": "Next " + noun, "shortcut": "K",
              "group": "Navigate", "icon": "chevron-right" },
            { "id": "event.create", "label": "New event", "shortcut": "C",
              "group": "Event", "icon": "plus" }
        ];
        if (c.selectedId) {
            out.push({ "id": "event.open", "label": "Open " + subject, "shortcut": "Enter",
                       "group": "Event", "icon": "square-pen" });
            out.push({ "id": "event.delete", "label": "Delete " + subject, "shortcut": "Backspace",
                       "group": "Event", "icon": "trash-2" });
        }
        out.push({ "id": "help.shortcuts", "label": "Keyboard shortcuts", "shortcut": "?",
                   "group": "Help", "icon": "keyboard" });
        return out;
    }

    /// How well `query` matches `text`, and the whole of the ranking:
    ///
    ///   3  `text` starts with the query        "da" -> "Day view"
    ///   2  a word of `text` does               "vi" -> "Day view"
    ///   1  the query is a subsequence of it    "dv" -> "Day view"
    ///   0  no match
    ///
    /// Case-folded, and an empty query is 3 for everything so a menu opens
    /// showing its own order rather than nothing.
    function rank(text: var, query: var): int {
        const t = String(text === undefined || text === null ? "" : text).toLowerCase();
        const q = String(query === undefined || query === null ? "" : query).trim().toLowerCase();
        if (!q)
            return 3;
        if (!t)
            return 0;
        if (t.indexOf(q) === 0)
            return 3;
        const words = t.split(/[^a-z0-9]+/);
        for (let i = 0; i < words.length; i++) {
            if (words[i] && words[i].indexOf(q) === 0)
                return 2;
        }
        let seen = 0;
        for (let j = 0; j < t.length && seen < q.length; j++) {
            if (t.charAt(j) === q.charAt(seen))
                seen++;
        }
        return seen === q.length ? 1 : 0;
    }

    /// The command list narrowed to `query`, best match first.
    ///
    /// An entry matches on its label or on its id, and an id-only match ranks at
    /// the bottom: `"view"` should list the three views by label before it lists
    /// anything that merely has `view` in its id. Ties keep the list's own
    /// order, which is the order `commands` chose and the only one a person
    /// arrowing down a menu can predict.
    function filter(items: var, query: var): var {
        const list = (items && typeof items !== "string" && typeof items.length === "number")
                   ? items : [];
        const scored = [];
        for (let i = 0; i < list.length; i++) {
            const item = list[i];
            const byLabel = policy.rank(item ? item.label : "", query);
            const byId = policy.rank(item ? item.id : "", query) > 0 ? 1 : 0;
            const score = Math.max(byLabel, byId);
            if (score > 0)
                scored.push({ "item": item, "score": score, "index": i });
        }
        scored.sort(function (a, b) {
            return a.score !== b.score ? b.score - a.score : a.index - b.index;
        });
        const out = [];
        for (let k = 0; k < scored.length; k++)
            out.push(scored[k].item);
        return out;
    }

    /// A shortcut string broken into what a keycap row draws:
    /// `{kind: "key"|"sep", text}`.
    ///
    /// Two separators, and they mean opposite things, which is why one is drawn
    /// and one is not. `+` is a **chord** — `Ctrl+N` is one gesture, so its caps
    /// sit side by side and the plus disappears, exactly as a keyboard does not
    /// have a plus key on it. `/` is an **alternative** — `C / Ctrl+N` is two
    /// ways to do one thing, and dropping that slash would read as a four-key
    /// chord nobody could press.
    function keyCaps(text: var): var {
        const s = String(text === undefined || text === null ? "" : text).trim();
        const out = [];
        if (!s)
            return out;
        const alternatives = s.split("/");
        for (let i = 0; i < alternatives.length; i++) {
            const chord = alternatives[i].trim().split("+");
            const before = out.length;
            for (let j = 0; j < chord.length; j++) {
                const cap = chord[j].trim();
                if (cap)
                    out.push({ "kind": "key", "text": cap });
            }
            // Only between two alternatives that both produced a cap — a
            // trailing slash must not print a separator with nothing after it.
            if (i > 0 && before > 0 && out.length > before)
                out.splice(before, 0, { "kind": "sep", "text": "/" });
        }
        return out;
    }

    // --- the menu as rows, headings included ----------------------------------

    /// A filtered command list flattened into what the menu actually draws:
    /// `{kind: "group", label}` headings interleaved with
    /// `{kind: "command", command}` rows.
    ///
    /// One list rather than a list of sections, because the highlight is an
    /// **index into what is on screen** and a nested model would make it a pair
    /// of indices — which is the shape that goes wrong the first time a filter
    /// empties a group. Headings appear in the order their groups first appear
    /// in `items`, so filtering reorders the whole menu rather than leaving a
    /// heading stranded above a better-scoring row from somewhere else.
    function menuRows(items: var): var {
        const list = (items && typeof items !== "string" && typeof items.length === "number")
                   ? items : [];
        const out = [];
        const order = [];
        const bucket = ({});
        for (let i = 0; i < list.length; i++) {
            const name = (list[i] && list[i].group) || "";
            if (bucket[name] === undefined) {
                bucket[name] = [];
                order.push(name);
            }
            bucket[name].push(list[i]);
        }
        for (let g = 0; g < order.length; g++) {
            out.push({ "kind": "group", "label": order[g], "command": null });
            const rows = bucket[order[g]];
            for (let r = 0; r < rows.length; r++)
                out.push({ "kind": "command", "label": rows[r].label, "command": rows[r] });
        }
        return out;
    }

    /// The index of the first command row, or `-1` when the filter matched
    /// nothing. What the menu highlights on open and after every keystroke.
    function firstRow(rows: var): int {
        return policy.stepRow(rows, -1, 1);
    }

    /// The next selectable row `delta` steps from `index`, wrapping, skipping
    /// headings. `-1` when there is nothing selectable at all — which is a real
    /// state (a query that matches nothing), not an error.
    ///
    /// Wrapping is why this is arithmetic and not `index + delta`: a menu whose
    /// first row is a heading would start the highlight on the heading, and one
    /// whose last row is a command would stop dead at the bottom.
    function stepRow(rows: var, index: int, delta: int): int {
        const list = (rows && typeof rows !== "string" && typeof rows.length === "number")
                   ? rows : [];
        const n = list.length;
        if (n === 0)
            return -1;
        const step = (Math.round(delta) || 1) > 0 ? 1 : -1;
        let at = Math.round(index);
        // No usable starting point — before the first row going down, past the
        // last one going up, so the first step lands on an end rather than two
        // rows in from one.
        if (isNaN(at) || at < 0 || at >= n)
            at = step < 0 ? n : -1;
        for (let i = 0; i < n; i++) {
            at = ((at + step) % n + n) % n;
            if (list[at] && list[at].kind === "command")
                return at;
        }
        return -1;
    }
}
