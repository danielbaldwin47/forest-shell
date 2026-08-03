// The full-dynamic palette (#59): what matugen said, turned into the seventeen
// roles the shell paints with, and made legible before anything wears it.
//
// Pure like Services/Theming/AccentPolicy.qml and for the same reason — it
// imports nothing but QtQuick, so `tests/tst_matugenpolicy.qml` can load it.
// What is left on the other side of the line is Services/Theming/Matugen.qml:
// spawning the binary, reading its exit status, and noticing that it is not
// installed.
//
// ## Why a mapping and not a palette
//
// matugen hands back a Material 3 scheme — fifty semantic roles built from a
// source colour it extracted from the wallpaper — and the shell's design system
// is a different seventeen (Core/Tokens.qml). The mapping below is the whole of
// the translation, and it is a table rather than code because every line of it
// is a *design* decision about which Material role plays which forest role, and
// a table is the shape someone can argue with.
//
// Two of those decisions are worth their prose here:
//
//   - the five backgrounds come off M3's `surface_container_*` ladder rather
//     than off five tones picked by hand, because that ladder is already an
//     ordered series with the elevation steps designed in — which is exactly
//     what `bgSunken → bgBase → surface → surfaceRaised → surfaceOverlay` is;
//   - `fogWash` takes `inverse_surface`, which is the one M3 role that flips
//     sides with the mode. The fog is a wash whose job is to obscure, so in
//     dark it must be light and in light it must be dark (Core/Tokens.qml says
//     exactly this about the shipped rows), and every other candidate keeps the
//     same side in both modes.
//
// ## Why it is measured afterwards
//
// A generated palette is the least trustworthy input the contrast floor will
// ever see: nobody authored it, nobody looked at it, and the wallpaper that
// produced it arrived this morning. matugen's own tone assignments hold AA for
// *its* pairings, which are not the shell's — the shell draws `accentStone` as
// a label on `surfaceOverlay`, and M3 has no opinion about that pair.
//
// So the same contract `tests/tst_tokens.qml` holds the shipped rows to is
// re-applied here as arithmetic: `shortfalls()` lists every pairing that fails
// it and `enforce()` walks the offending role's lightness until it clears, hue
// and chroma untouched. A palette that leaves this file has been measured
// against the same numbers the shipped one was, which is what lets a wallpaper
// nobody vetted restyle a bar nobody can otherwise read.
import QtQuick

QtObject {
    id: policy

    /// The colour space, the WCAG arithmetic, and the sRGB round trip — all of
    /// it already written for #58. Sharing it rather than restating it is what
    /// makes a ratio computed here and a ratio computed there the same number.
    readonly property AccentPolicy color: AccentPolicy {}

    // --- the mapping ----------------------------------------------------------

    /// forest role → the M3 role it is made of. The full seventeen: a palette
    /// missing one of these is refused whole rather than delivered partial,
    /// because a half palette is the shipped row with five holes punched in it
    /// and no way to tell from a screenshot which half you are looking at.
    readonly property var roleSources: ({
        // The elevation ladder, darkest well to highest overlay.
        bgBase: "surface",
        bgSunken: "surface_container_lowest",
        surface: "surface_container_low",
        surfaceRaised: "surface_container",
        surfaceOverlay: "surface_container_high",
        // M3's two outlines are already a hairline and an edge.
        borderSubtle: "outline_variant",
        borderStrong: "outline",
        textPrimary: "on_surface",
        textSecondary: "on_surface_variant",
        // `outline` twice, on purpose: M3's outline is the dimmest tone it will
        // still call legible, which is what `textMuted` is. It arrives equal to
        // `borderStrong` and leaves different — the two have different floors
        // below and are measured separately.
        textMuted: "outline",
        // The accent structure. M3's primary/secondary/tertiary triad is not the
        // brief's teal/amber/ember one, so this is where the generated look
        // stops being the forest look — which is the mode's whole point.
        accentPrimary: "primary",
        // A *fill*, and M3's container roles are exactly that: a tone chosen to
        // be sat on rather than read.
        accentDeep: "primary_container",
        accentWarm: "tertiary",
        // The one role with a fixed meaning rather than a fixed hue. Urgent is
        // urgent whatever the wallpaper says, and M3 carries an error tone for
        // it that is red in every scheme it generates.
        accentEmber: "error",
        accentLichen: "secondary",
        accentStone: "outline_variant",
        fogWash: "inverse_surface"
    })

    readonly property var roles: Object.keys(policy.roleSources)

    // --- the contract ---------------------------------------------------------
    //
    // The floors are `tests/tst_tokens.qml`'s, restated as data. They are the
    // shipped palette's promises, so a generated one that clears them is
    // legible in the same places for the same reasons — and where that file
    // deliberately asks for less (muted text at the large-text floor, a border
    // at visibility rather than legibility) this asks for less too. A gate that
    // demanded more of a wallpaper than the design brief asks of itself would
    // reject palettes the shipped row could not pass either.

    readonly property real minRatio: 4.5        // AA, body text
    readonly property real mutedRatio: 3.0      // AA large — Core/Tokens.qml's own call
    readonly property real subtleRatio: 1.2     // a hairline that is still a line
    readonly property real strongRatio: 1.8     // a focus ring

    readonly property var backgroundRoles: [
        "bgBase", "bgSunken", "surface", "surfaceRaised", "surfaceOverlay"
    ]

    /// The four a label can land on. `bgSunken` is left out for the reason
    /// tst_tokens.qml gives: it is wells and grooves, and the shell draws no
    /// accent-coloured text into one.
    readonly property var labelSurfaces: [
        "bgBase", "surface", "surfaceRaised", "surfaceOverlay"
    ]

    /// Every pairing that has to hold, as `{ fg, against, floor }` — `against`
    /// being the roles the foreground is drawn on. Ordered: the text roles are
    /// settled before `accentDeep`, which is measured against the settled
    /// `textPrimary` rather than against the one matugen shipped.
    readonly property var rules: [
        { fg: "textPrimary", against: policy.backgroundRoles, floor: policy.minRatio },
        { fg: "textSecondary", against: policy.backgroundRoles, floor: policy.minRatio },
        { fg: "textMuted", against: policy.backgroundRoles, floor: policy.mutedRatio },
        { fg: "accentPrimary", against: policy.labelSurfaces, floor: policy.minRatio },
        { fg: "accentWarm", against: policy.labelSurfaces, floor: policy.minRatio },
        { fg: "accentEmber", against: policy.labelSurfaces, floor: policy.minRatio },
        { fg: "accentLichen", against: policy.labelSurfaces, floor: policy.minRatio },
        { fg: "accentStone", against: policy.labelSurfaces, floor: policy.minRatio },
        // The fill, measured under the text that sits on it. Moving this one
        // moves a background, which is why it comes after everything that is
        // measured against a background and why nothing after it is.
        { fg: "accentDeep", against: ["textPrimary"], floor: policy.minRatio },
        { fg: "borderSubtle", against: ["surface", "surfaceRaised"], floor: policy.subtleRatio },
        { fg: "borderStrong", against: ["surface", "surfaceRaised"], floor: policy.strongRatio }
    ]

    // --- reading what the binary said -----------------------------------------

    /// matugen's `--json hex` dump → `{ ok, dark, light, error }`, where `dark`
    /// and `light` are role → hex maps of *M3* roles.
    ///
    /// Both rows come out of one run. matugen emits the whole scheme in both
    /// modes whatever `--mode` it was given — `--mode` only picks which one it
    /// calls `default` and which one it renders templates with — so the dark
    /// flip does not need the wallpaper read a second time.
    ///
    /// Two output shapes are accepted because two are in the wild: 4.x nests
    /// the modes under the role (`colors.primary.dark.color`) and everything
    /// before it, still reachable via `--old-json-output`, nests the role under
    /// the mode (`colors.dark.primary`). Which one a machine produces is a
    /// property of the matugen someone's distribution shipped, and a mode that
    /// worked on one machine and silently did nothing on another is the failure
    /// this admits both shapes to avoid.
    function parse(text: string): var {
        if (!text || text.trim() === "")
            return { ok: false, error: "no output" };

        let raw;
        try {
            raw = JSON.parse(text);
        } catch (error) {
            return { ok: false, error: "unreadable output" };
        }

        const colors = raw && raw.colors;
        if (!colors || typeof colors !== "object")
            return { ok: false, error: "no colours in output" };

        // The old shape, keyed by mode at the top.
        if (colors.dark && colors.light && typeof colors.dark === "object"
                && policy.isHex(colors.dark[Object.keys(colors.dark)[0]]))
            return { ok: true, dark: colors.dark, light: colors.light };

        const rows = { dark: ({}), light: ({}) };
        for (const name in colors) {
            const entry = colors[name];
            if (!entry || typeof entry !== "object")
                continue;
            for (const mode of ["dark", "light"]) {
                const cell = entry[mode];
                const value = cell && typeof cell === "object" ? cell.color : cell;
                if (policy.isHex(value))
                    rows[mode][name] = value;
            }
        }

        if (Object.keys(rows.dark).length === 0)
            return { ok: false, error: "no colours in output" };
        return { ok: true, dark: rows.dark, light: rows.light };
    }

    /// `#rrggbb` and nothing else. Narrower than Qt's parser for the reason
    /// Core/Tokens.qml is: this ends up in the settings file, where a value
    /// that file cannot parse is dropped with a warning and a role goes back to
    /// the shipped one — a palette with one hole in it rather than a refusal.
    function isHex(value: var): bool {
        return typeof value === "string"
            && /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.test(value);
    }

    /// One row of M3 roles → the seventeen, unmeasured. `{}` if the row is
    /// missing any of them.
    function paletteFrom(row: var): var {
        if (!row)
            return ({});
        const out = {};
        for (const role of policy.roles) {
            const value = row[policy.roleSources[role]];
            if (!policy.isHex(value))
                return ({});
            out[role] = policy.normalize(value);
        }
        return out;
    }

    /// `#abc` → `#aabbcc`. The three-digit form is legal in the settings file
    /// but the arithmetic below round-trips through six, and a palette whose
    /// keys changed shape between "generated" and "regenerated" would rewrite
    /// the file on every wallpaper change that produced the same colours.
    function normalize(value: string): string {
        if (value.length !== 4)
            return value.toLowerCase();
        return ("#" + value[1] + value[1] + value[2] + value[2]
                + value[3] + value[3]).toLowerCase();
    }

    // --- the legibility pass --------------------------------------------------

    /// Every rule the palette fails, as `{ fg, bg, ratio, floor }`. Empty is
    /// the pass condition, and it is what the tests assert on: the same list
    /// this file uses to fix a palette is the list that proves it was fixed.
    function shortfalls(palette: var): var {
        const out = [];
        for (const rule of policy.rules) {
            const foreground = policy.luminance(palette[rule.fg]);
            for (const name of rule.against) {
                const ratio = policy.color.contrast(foreground,
                                                    policy.luminance(palette[name]));
                if (ratio < rule.floor - 0.0005)
                    out.push({ fg: rule.fg, bg: name, ratio: ratio, floor: rule.floor });
            }
        }
        return out;
    }

    function luminance(hex: string): real {
        return policy.color.relativeLuminance(policy.color.toRgb(hex));
    }

    /// The palette, made legible: each failing role's lightness walked until it
    /// clears its floor against every background it is drawn on, hue and chroma
    /// untouched.
    ///
    /// Lightness only, for AccentPolicy's reason — rescuing contrast by
    /// rotating would change the colour the wallpaper earned into a different
    /// one and call it the same. What moves is how light it is, which is the
    /// only axis contrast is actually about.
    ///
    /// The backgrounds themselves are never touched. They are the palette's
    /// structure — five tones whose *spacing* is what makes an overlay look
    /// raised — and a pass that nudged one to rescue a text role would flatten
    /// the ladder to fix a label.
    function enforce(palette: var): var {
        const out = {};
        for (const role in palette)
            out[role] = palette[role];

        for (const rule of policy.rules) {
            const backgrounds = rule.against.map(name => policy.luminance(out[name]));
            out[rule.fg] = policy.fit(out[rule.fg], backgrounds, rule.floor);
        }
        return out;
    }

    /// The nearest lightness at which `hex` clears `floor` against all of
    /// `backgrounds` — or, if no lightness does, the one that comes closest.
    ///
    /// A scan rather than AccentPolicy's bisection, and the difference is the
    /// input. That one rescues a single accent against a single background,
    /// where the ratio rises monotonically as L moves away and bisection is
    /// exact. This one answers to up to five backgrounds at once on a palette
    /// nobody authored: a generated row can put text *between* two of its own
    /// surfaces, and the worst-case ratio across a straddling set is not
    /// monotonic in L — a bisection would walk confidently into the dip between
    /// them. Sixty-four steps from where the colour started outwards, taking the
    /// first that clears, is monotonic in nothing and needs to be.
    ///
    /// Note the direction is chosen by score and not by "away from the
    /// background": with several backgrounds there is no single away.
    function fit(hex: string, backgrounds: var, floor: real): string {
        const score = value => {
            let worst = Infinity;
            for (const background of backgrounds)
                worst = Math.min(worst, policy.color.contrast(value, background));
            return worst;
        };

        const start = policy.color.toOklch(hex);
        if (score(policy.luminance(hex)) >= floor)
            return policy.normalize(hex);

        // Scored on the *hex*, not on the channels that produced it. A colour
        // leaves here as eight bits per channel and is measured again from
        // there by `shortfalls()`; scoring the unrounded value would let a
        // candidate clear the floor by less than one rounding step and land
        // under it, which is a role that passed its own pass.
        const at = okL => {
            const value = policy.color.hexOf(
                policy.color.fromOklch(okL, start.C, start.H));
            return { hex: value, score: score(policy.luminance(value)) };
        };

        // Which end of the L axis to walk towards. Both are tried at their
        // extreme first, because the answer is "whichever end has any headroom
        // at all" — on a mid-grey against a straddling pair that is not the end
        // a single background would have pointed at.
        const steps = 64;
        const darkEnd = at(0);
        const lightEnd = at(1);
        const target = lightEnd.score > darkEnd.score ? 1 : 0;

        let best = at(start.L);
        for (let step = 1; step <= steps; step++) {
            const candidate = at(start.L + (target - start.L) * (step / steps));
            if (candidate.score >= floor)
                return candidate.hex;
            if (candidate.score > best.score)
                best = candidate;
        }
        // Unreachable on any palette matugen has produced — the ends of the L
        // axis are black and white, and one of them clears 4.5:1 against
        // anything. Kept because "closest we could get" is a better palette
        // than a role left at a ratio the pass already knew was too low.
        return best.hex;
    }

    // --- the whole computation ------------------------------------------------

    /// What the run produced: `{ ok, palette, error }`.
    ///
    /// The exit status is read first and read strictly (#78). matugen writes
    /// its errors to stderr and exits non-zero — "multiple source colours found
    /// and no preference was given" is one it exits 1 on with an empty stdout —
    /// so a caller that only looked at stdout would read "no palette" as "this
    /// wallpaper is not colourful", which is a sentence about the wallpaper
    /// rather than about the failure that actually happened.
    /// `lifted` is how many roles the legibility pass had to move, and it is
    /// carried out to the log rather than kept: a wallpaper whose palette needs
    /// eight roles rescued is a wallpaper the mode is barely serving, and that
    /// is worth being able to read off a log without re-running anything.
    function outcome(exitCode: int, text: string, darkMode: bool): var {
        if (exitCode !== 0)
            return { ok: false, palette: ({}), lifted: 0,
                     error: "matugen exited " + exitCode };

        const parsed = policy.parse(text);
        if (!parsed.ok)
            return { ok: false, palette: ({}), lifted: 0, error: parsed.error };

        const mapped = policy.paletteFrom(darkMode ? parsed.dark : parsed.light);
        if (Object.keys(mapped).length === 0)
            return { ok: false, palette: ({}), lifted: 0,
                     error: "incomplete scheme" };

        const fixed = policy.enforce(mapped);
        let lifted = 0;
        for (const role in fixed)
            if (fixed[role] !== mapped[role])
                lifted++;

        return { ok: true, palette: fixed, lifted: lifted, error: "" };
    }

    // --- the command ----------------------------------------------------------

    /// The argument vector for one generation.
    ///
    /// `--dry-run` is the default and is what makes this mode a *shell* theming
    /// mode: without it matugen renders every template in the user's
    /// `~/.config/matugen/config.toml`, reloads the apps those templates name,
    /// and runs whatever post-hooks it finds there — none of which the shell
    /// asked for, all of which happen on every wallpaper change. Dropping the
    /// flag is `appearance.matugenTemplates`, off until someone turns it on,
    /// and documented in Services/Theming/README.md.
    ///
    /// `--prefer saturation` is not a preference so much as a requirement: on
    /// an image with more than one candidate source colour matugen asks the
    /// terminal which to use, and a shell that spawned it has no terminal to
    /// ask — it exits 1 with "no preference was inputted" instead. Saturation
    /// picks the most colourful candidate, which is the one a wallpaper is
    /// about.
    ///
    /// `--mode` only decides which row matugen calls `default`; both rows are
    /// in the JSON either way. It is passed because a template *does* render
    /// from `default`, so with templates on this is what keeps the external
    /// apps in the same mode as the shell.
    function argv(image: string, darkMode: bool, templates: bool): var {
        const out = ["matugen", "image", image,
                     "--json", "hex",
                     "--prefer", "saturation",
                     "--mode", darkMode ? "dark" : "light",
                     "--quiet"];
        if (!templates)
            out.push("--dry-run");
        return out;
    }

    function probeArgv(): var {
        return ["matugen", "--version"];
    }

    // --- the log (#81) ---------------------------------------------------------
    //
    // A generated palette is a state change with no other evidence — the shell
    // is a different colour, on a machine where it may always have been that
    // colour. Each outcome says which one it was and why, and the absent-binary
    // path says so once rather than failing quietly every wallpaper change.

    function generatedLine(hex: string, fixed: int, darkMode: bool): string {
        return "palette generated (" + (darkMode ? "dark" : "light") + ") "
            + hex + ", " + fixed + " role(s) lifted to floor";
    }

    function failedLine(reason: string): string {
        return "palette generation failed: " + reason + " — keeping current palette";
    }

    function absentLine(): string {
        return "matugen not installed — full dynamic mode unavailable";
    }

    function foundLine(version: string): string {
        return "matugen found (" + version.trim() + ")";
    }

    function clearedLine(mode: string): string {
        return "generated palette cleared (mode " + mode + ")";
    }
}
