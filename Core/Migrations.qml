// The migration runner (#12 §5, #21, #33).
//
// Migrations exist from day one because the alternative is a settings file that
// can never be reorganised without breaking every user who already has one.
//
// They run on the **raw** parsed JSON, before the spec table sees it: resolving
// through the spec drops every key the current schema does not know, and a
// rename migration's whole job is to read exactly those. Each entry is
// `{ to, describe, migrate(raw) }`; only the steps above the file's own version
// run, in version order.
//
// A file from a *newer* forest-shell is never touched or downgraded — its
// version stands, no step runs, and the sparse write preserves the keys this
// build cannot see.
//
// Pure functions, no Quickshell imports, so tests/ can reach them.
import QtQuick

QtObject {
    readonly property QtObject json: JsonMerge {}

    // A file with no version stamp — hand-written, or written before the stamp
    // existed — is the oldest version.
    function versionOf(raw, versionKey, oldest) {
        const value = json.isPlainObject(raw) ? raw[versionKey] : undefined;
        const version = typeof value === "number" ? Math.floor(value) : NaN;
        return isNaN(version) ? oldest : version;
    }

    // `{ raw, from, to, applied, rewritten }`. The input is not mutated.
    //
    // `rewritten` says whether a step actually changed something, which is what
    // decides whether a backup is worth keeping: a file that only lacked its
    // version stamp gets stamped, not backed up.
    function run(raw, registry, versionKey, latest) {
        const from = versionOf(raw, versionKey, 1);
        const ordered = (registry || []).slice().sort((a, b) => a.to - b.to);

        let out = json.deepCopy(json.isPlainObject(raw) ? raw : {});
        const applied = [];
        let rewritten = false;

        for (const step of ordered) {
            if (step.to <= from || step.to > latest)
                continue;

            const before = JSON.stringify(out);
            out = step.migrate(out) || out;
            applied.push(step.describe);
            if (JSON.stringify(out) !== before)
                rewritten = true;
        }

        out[versionKey] = Math.max(from, latest);
        return { raw: out, from: from, to: out[versionKey], applied: applied, rewritten: rewritten };
    }
}
