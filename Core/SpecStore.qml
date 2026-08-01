// The generic spec-table store (#21, #33).
//
// One nested table — `{ def, coerce, onChange }` per key, mirroring the file's
// sections — drives defaults, parsing, sparse serialization and change
// dispatch. There is no per-property boilerplate anywhere: adding a setting is
// one line in a schema file, and `settings.json` and `state.json` are the same
// machinery with a different schema.
//
// Shape rule: a node carrying a `def` key is a **leaf**; any other object is a
// section. A leaf's value may itself be a whole sub-object (`bar.surface`,
// `appearance.paletteOverrides`), which is how theme-flagged groups stay atomic
// — a preset replaces the group rather than merging into whatever keys the user
// happened to leave behind (#56).
//
// The file on disk is **sparse**: only keys that differ from their default are
// written, keys the shell does not know are carried through untouched, and
// reset-to-default is key deletion — so a later change to a shipped default
// reaches users who never touched that key.
//
// Pure functions, no Quickshell imports, so tests/ can reach them.
import QtQuick

QtObject {
    id: root

    // Deep copy / plain-object test / safe parse, shared with the merge rule
    // the file format is built on.
    readonly property QtObject json: JsonMerge {}

    function isLeaf(node) {
        return json.isPlainObject(node) && node.def !== undefined;
    }

    // Nested object of every leaf's `def`. Never shares state with the spec:
    // one consumer's in-place edit must not rewrite the defaults for every
    // later reload.
    function defaults(spec) {
        const out = {};
        for (const key in spec) {
            const node = spec[key];
            out[key] = isLeaf(node) ? json.deepCopy(node.def) : defaults(node);
        }
        return out;
    }

    // Every leaf as a dotted path, depth first. This is the list every walk
    // below iterates — the spec is traversed once, here, and nowhere else.
    function leafPaths(spec, prefix) {
        const base = prefix ? prefix + "." : "";
        let out = [];
        for (const key in spec) {
            const node = spec[key];
            if (isLeaf(node))
                out.push(base + key);
            else
                out = out.concat(leafPaths(node, base + key));
        }
        return out;
    }

    // Every leaf at or below a dotted path — one leaf for a leaf path, a
    // section's worth for a section path, and nothing for a path the spec does
    // not have. This is what makes per-section and whole-file reset the same
    // operation at a different depth (#21).
    function leafPathsUnder(spec, path) {
        let node = spec;
        for (const key of path.split(".")) {
            if (!json.isPlainObject(node) || isLeaf(node) || node[key] === undefined)
                return [];
            node = node[key];
        }
        if (isLeaf(node))
            return [path];
        return leafPaths(node).map(under => path + "." + under);
    }

    // The leaf spec at a dotted path, or null if the path is not a leaf —
    // including paths that reach *into* a whole-sub-object leaf, which have no
    // spec of their own.
    function leafAt(spec, path) {
        let node = spec;
        for (const key of path.split(".")) {
            if (!json.isPlainObject(node) || node[key] === undefined)
                return null;
            node = node[key];
        }
        return isLeaf(node) ? node : null;
    }

    function getPath(obj, path) {
        let node = obj;
        for (const key of path.split(".")) {
            if (!json.isPlainObject(node))
                return undefined;
            node = node[key];
            if (node === undefined)
                return undefined;
        }
        return node;
    }

    function setPath(obj, path, value) {
        const keys = path.split(".");
        let node = obj;
        for (let i = 0; i < keys.length - 1; i++) {
            if (!json.isPlainObject(node[keys[i]]))
                node[keys[i]] = {};
            node = node[keys[i]];
        }
        node[keys[keys.length - 1]] = value;
        return obj;
    }

    // Deletes the key, then every section the deletion left empty — a sparse
    // file should not accumulate `"bar": {}` husks after a reset-to-defaults.
    function unsetPath(obj, path) {
        const keys = path.split(".");
        const chain = [obj];
        let node = obj;
        for (let i = 0; i < keys.length - 1; i++) {
            node = node[keys[i]];
            if (!json.isPlainObject(node))
                return obj;   // the path is not in this file; nothing to delete
            chain.push(node);
        }

        delete node[keys[keys.length - 1]];
        for (let i = chain.length - 1; i > 0; i--) {
            if (Object.keys(chain[i]).length > 0)
                break;
            delete chain[i - 1][keys[i - 1]];
        }
        return obj;
    }

    // `{ values, issues }` from raw parsed JSON. `values` is always complete —
    // every leaf in the spec resolves to something, so no consumer ever has to
    // handle `undefined` — and every value that could not be coerced is both
    // replaced by its default and reported, so the shell can say which key it
    // ignored rather than silently doing something else.
    function resolve(spec, raw) {
        const values = {};
        const issues = [];

        for (const path of leafPaths(spec)) {
            const leaf = leafAt(spec, path);
            const rawValue = getPath(raw, path);

            if (rawValue === undefined) {
                setPath(values, path, json.deepCopy(leaf.def));
                continue;
            }

            const coerced = leaf.coerce ? leaf.coerce(rawValue) : rawValue;
            if (coerced === undefined) {
                issues.push({ path: path, value: rawValue });
                setPath(values, path, json.deepCopy(leaf.def));
            } else {
                setPath(values, path, json.deepCopy(coerced));
            }
        }

        return { values: values, issues: issues };
    }

    // The file as it should be on disk: `raw` is what is there now, and only
    // the leaves that differ from their default are written into it. Neither
    // argument is mutated.
    function serialize(spec, values, raw) {
        const out = json.deepCopy(json.isPlainObject(raw) ? raw : {});

        for (const path of leafPaths(spec)) {
            const leaf = leafAt(spec, path);
            const value = getPath(values, path);
            if (value === undefined)
                continue;

            if (equals(value, leaf.def))
                unsetPath(out, path);
            else
                setPath(out, path, json.deepCopy(value));
        }

        return out;
    }

    // Which leaves moved between two resolved value sets. Compared by value,
    // not identity: a reload builds a fresh object every time, so identity
    // would report every key as changed on every reload.
    function changedPaths(spec, before, after) {
        const out = [];
        for (const path of leafPaths(spec))
            if (!equals(getPath(before, path), getPath(after, path)))
                out.push(path);
        return out;
    }

    function equals(a, b) {
        if (a === b)
            return true;
        if (Array.isArray(a) && Array.isArray(b))
            return a.length === b.length && a.every((item, i) => equals(item, b[i]));
        if (json.isPlainObject(a) && json.isPlainObject(b)) {
            const keys = Object.keys(a);
            return keys.length === Object.keys(b).length
                && keys.every(key => equals(a[key], b[key]));
        }
        return false;
    }
}
