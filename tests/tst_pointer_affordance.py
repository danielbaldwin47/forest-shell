#!/usr/bin/env python3
"""Every click target on the bar, the drawers and the notifications shows a
pointer (#185).

The bar draws no hover highlight at all — that was a decision, not an omission —
so the cursor is the only thing that says a glyph can be clicked. Nine bar
controls shipped without one because the shared base set no cursor, and the two
that had one (the clock, the workspace strip) had rolled their own input and
happened to get it right. That is the drift this guard exists to stop: the next
widget that grows a `MouseArea` and no `cursorShape`.

This is a source-level check in the shape of `tst_control_bytes.py`, because the
widgets pull in the shell's theme and config modules and `qmltestrunner` cannot
load either — nothing here instantiates a thing. What it buys is breadth: every
click target in three directories, checked on every run. What it cannot do is
say the pixels are right, which is `tools/cursor-harness.sh`'s job (#185 was
filed believing no seam could; a cursor turns out to be a request on the wire,
and seam 2 can read it). A regression guard, not a proof.

Two rules, and the second is the one that keeps the first from being restated
per widget:

  1. A `MouseArea` or `TapHandler` that handles a click or a wheel must have a
     `cursorShape` — on itself, on a sibling (the `HoverHandler`-beside-a-
     `TapHandler` shape the clock uses), or on its parent.
  2. `BarIndicator`'s own cursor must follow `interactive`, the same flag that
     enables its input. A bar module that becomes clickable later then gets the
     pointer without being edited.

A click target that genuinely wants the arrow says so in place:

    // pointer-exempt: <why>

Stdlib only, same rule as everything else inside a gate.

    tests/tst_pointer_affordance.py     # part of tests/run.sh
"""

import re
import sys
from pathlib import Path

# Where a click is a control the user aims at. `Surfaces/Screenshot` is out:
# its picker wants the crosshair, and says so with its own `cursorShape`.
SCOPE = ("Surfaces/Bar", "Surfaces/Drawers", "Surfaces/Notifications", "Widgets")

# The two item-level input elements the shell uses. `HoverHandler` is not here —
# it accepts no click; it is only ever the thing that *carries* the cursor.
CLICKERS = ("MouseArea", "TapHandler")

# A handler that means the element is aimed at rather than merely covered.
# `onWheel` counts: a reading that steps under the wheel is changed from here,
# which is the same promise a click makes.
HANDLED = re.compile(r"\bon(Clicked|Tapped|Pressed|DoubleTapped|PressAndHold|Wheel)\b")

EXEMPT = re.compile(r"//\s*pointer-exempt\b")

# The *hand*, and not merely some cursor. A `cursorShape: Qt.ArrowCursor` on a
# click target is the bug this guard is for, spelled out — checking only that
# the property is present would have passed the nine modules #185 was filed
# about. A conditional counts: `dimmed ? Qt.ArrowCursor : Qt.PointingHandCursor`
# is a row that shows the hand whenever it is clickable at all.
POINTER = re.compile(r"cursorShape\s*:[^\n]*PointingHandCursor")

# `Type {` — an object declaration, as against `anchors {`, `onClicked: {` or a
# JavaScript block, all of which open a brace after something lowercase.
DECLARATION = re.compile(r"([A-Z]\w*(?:\.\w+)*)\s*$")


class Block:
    """One `Type { ... }` declaration, and what it holds directly.

    `own` is the block's text with its child declarations cut out, so a
    `cursorShape` found in it belongs to *this* element and not to something
    nested three levels down.
    """

    def __init__(self, type_name, start, line):
        self.type = type_name
        self.start = start
        self.line = line
        self.end = None
        self.parent = None
        self.children = []
        self.own = ""

    def has(self, pattern) -> bool:
        return bool(re.search(pattern, self.own))


def blank_noise(text: str) -> str:
    """`text` with comments and string bodies replaced by spaces.

    Positions and line breaks are preserved so an offset into the result is an
    offset into the original. A brace inside a comment or a string is not a
    brace, and a `cursorShape` inside one is not a cursor.
    """
    out = list(text)
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        if ch == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                out[i] = " "
                i += 1
        elif ch == "/" and i + 1 < n and text[i + 1] == "*":
            while i < n and not (text[i] == "*" and i + 1 < n and text[i + 1] == "/"):
                if text[i] != "\n":
                    out[i] = " "
                i += 1
            for j in range(i, min(i + 2, n)):
                out[j] = " "
            i += 2
        elif ch in "\"'`":
            # A quote only opens a string if it closes on the same line. QML has
            # no multi-line string literal, and the alternative reading is worse
            # than useless: the quote inside a regular expression — `/'/g`, which
            # this tree has — would otherwise swallow the rest of the file, and a
            # file blanked to nothing looks exactly like a file with no bare
            # click targets in it.
            quote = ch
            close = i + 1
            while close < n and text[close] not in (quote, "\n"):
                close += 2 if text[close] == "\\" else 1
            if close < n and text[close] == quote:
                for j in range(i + 1, close):
                    out[j] = " "
                i = close + 1
            else:
                i += 1
        else:
            i += 1
    return "".join(out)


def parse(text: str) -> list:
    """Every `Type { ... }` declaration in `text`, as a tree, in source order."""
    clean = blank_noise(text)
    blocks, stack, open_braces = [], [], []
    for match in re.finditer(r"[{}]", clean):
        at = match.start()
        if match.group() == "{":
            # Only a declaration opens a Block; every other brace still has to
            # be counted, or the closing one would pop a block that is still open.
            head = DECLARATION.search(clean[:at])
            if head:
                block = Block(head.group(1), at, clean.count("\n", 0, at) + 1)
                block.parent = stack[-1] if stack else None
                if block.parent:
                    block.parent.children.append(block)
                blocks.append(block)
                stack.append(block)
                open_braces.append(block)
            else:
                open_braces.append(None)
        else:
            block = open_braces.pop() if open_braces else None
            if block is not None:
                block.end = at
                stack.pop()

    for block in blocks:
        if block.end is None:                      # unbalanced file; nothing to say
            block.end = len(clean)
        body, cut = clean[block.start:block.end], 0
        pieces = []
        for child in block.children:
            pieces.append(body[cut:child.start - block.start])
            cut = child.end - block.start
        pieces.append(body[cut:])
        block.own = "".join(pieces)
    return blocks


def uncovered(text: str) -> list:
    """(line, type) for every click target in `text` with no pointer affordance.

    Covered means a pointer `cursorShape` on the element itself, on its parent,
    or on a `HoverHandler` beside it. That last case is not a loophole — it is
    the shape the clock and the notification centre already use, a handler that
    carries the cursor for the `TapHandler` next to it, both belonging to the
    same item. Only a `HoverHandler` counts as the sibling: a second
    `MouseArea` next door is a different target with a different job, and
    letting one cover the other is how a bare click target gets added beside a
    cursored one and passes.
    """
    exemptions = [m.start() for m in EXEMPT.finditer(text)]
    found = []
    for block in parse(text):
        if block.type not in CLICKERS or not block.has(HANDLED):
            continue
        # The marker has to sit in the block's *own* body. One inside a child
        # was written about the child.
        if any(block.start <= at <= block.end
               and not any(kid.start <= at <= kid.end for kid in block.children)
               for at in exemptions):
            continue
        family = [block]
        if block.parent:
            family.append(block.parent)
            family.extend(kid for kid in block.parent.children
                          if kid.type == "HoverHandler")
        if not any(kin.has(POINTER) for kin in family):
            found.append((block.line, block.type))
    return found


def base_follows_interactive(text: str) -> bool:
    """Does `BarIndicator`'s cursor follow the flag that enables its input?

    The whole point of the ticket: nine modules were arrow-only because the
    cursor was decided somewhere other than where the input was. A cursor line
    that names some other flag passes rule 1 and reintroduces the bug.
    """
    for block in parse(text):
        if block.type == "MouseArea" and block.has(r"enabled\s*:.*\binteractive\b"):
            cursor = re.search(r"cursorShape\s*:([^\n]*)", block.own)
            if cursor and "interactive" in cursor.group(1) \
                    and "PointingHandCursor" in cursor.group(1):
                return True
    return False


def scanned_files(root: Path) -> list:
    files = []
    for folder in SCOPE:
        files.extend(p for p in (root / folder).rglob("*.qml")
                     if not any(part.startswith(".") for part in p.relative_to(root).parts))
    return sorted(files)


def main() -> int:
    problems = []

    def check(name, ok):
        print(("ok   " if ok else "FAIL ") + name)
        if not ok:
            problems.append(name)

    # The guard's own redness. Each snippet is a shape that exists in the tree.
    check("a bare click target is caught",
          uncovered("MouseArea {\n  onClicked: go()\n}\n") == [(1, "MouseArea")])
    check("a bare wheel target is caught",
          uncovered("MouseArea {\n  onWheel: step()\n}\n") == [(1, "MouseArea")])
    check("its own cursor covers it",
          uncovered("MouseArea {\n  cursorShape: Qt.PointingHandCursor\n  onClicked: go()\n}\n") == [])
    check("an arrow on a click target is not coverage",
          uncovered("MouseArea {\n  cursorShape: Qt.ArrowCursor\n  onClicked: go()\n}\n")
          == [(1, "MouseArea")])
    check("a lookalike property name is not a cursor",
          uncovered("MouseArea {\n  property int cursorShapeNote: 1\n  onClicked: go()\n}\n")
          == [(1, "MouseArea")])
    check("a sibling MouseArea does not cover another",
          uncovered("Row {\n  MouseArea { cursorShape: Qt.PointingHandCursor\n    onClicked: a() }\n"
                    "  MouseArea { onClicked: b() }\n}\n") == [(4, "MouseArea")])
    check("a regex literal holding a quote does not blank the file",
          uncovered("Item {\n  function f(s) { return s.replace(/'/g, \"\") }\n"
                    "  MouseArea { onClicked: go() }\n}\n") == [(3, "MouseArea")])
    check("an exemption inside a child does not cover the parent",
          uncovered("MouseArea {\n  onClicked: go()\n"
                    "  Item {\n    // pointer-exempt: about this one\n  }\n}\n")
          == [(1, "MouseArea")])
    check("a sibling HoverHandler covers a TapHandler",
          uncovered("Rectangle {\n  HoverHandler { cursorShape: Qt.PointingHandCursor }\n"
                    "  TapHandler { onTapped: go() }\n}\n") == [])
    check("a cursor on an unrelated branch does not",
          uncovered("Item {\n  Rectangle { HoverHandler { cursorShape: Qt.PointingHandCursor } }\n"
                    "  Rectangle { MouseArea { onClicked: go() } }\n}\n") == [(3, "MouseArea")])
    check("a conditional cursor covers it",
          uncovered("MouseArea {\n  cursorShape: row.dimmed ? Qt.ArrowCursor : Qt.PointingHandCursor\n"
                    "  onClicked: go()\n}\n") == [])
    check("a click target with no handler is not a target",
          uncovered("MouseArea {\n  anchors.fill: parent\n}\n") == [])
    check("an exemption is honoured",
          uncovered("MouseArea {\n  // pointer-exempt: swallows the click outside\n"
                    "  onClicked: close()\n}\n") == [])
    check("a commented-out cursor does not count",
          uncovered("MouseArea {\n  // cursorShape: Qt.PointingHandCursor\n  onClicked: go()\n}\n")
          == [(1, "MouseArea")])
    check("a cursor named in a string does not count",
          uncovered('MouseArea {\n  note: "cursorShape"\n  onClicked: go()\n}\n')
          == [(1, "MouseArea")])
    check("a brace inside a comment does not break the tree",
          uncovered("Rectangle {\n  // }\n  MouseArea { onClicked: go() }\n}\n") == [(3, "MouseArea")])
    check("a JavaScript block does not open a declaration",
          uncovered("MouseArea {\n  cursorShape: Qt.PointingHandCursor\n"
                    "  onClicked: { if (a) { go() } }\n}\n") == [])
    check("the base rule reads the flag",
          base_follows_interactive(
              "MouseArea {\n  enabled: indicator.interactive\n"
              "  cursorShape: indicator.interactive ? Qt.PointingHandCursor "
              ": Qt.ArrowCursor\n}\n"))
    check("the base rule rejects another flag",
          not base_follows_interactive("MouseArea {\n  enabled: indicator.interactive\n"
                                       "  cursorShape: indicator.opensPanel ? A : B\n}\n"))
    check("the base rule rejects an arrow on both branches",
          not base_follows_interactive(
              "MouseArea {\n  enabled: indicator.interactive\n"
              "  cursorShape: indicator.interactive ? Qt.ArrowCursor : Qt.ArrowCursor\n}\n"))
    check("the base rule rejects no cursor at all",
          not base_follows_interactive("MouseArea {\n  enabled: indicator.interactive\n}\n"))

    root = Path(__file__).resolve().parent.parent
    files = scanned_files(root)
    check("the sweep found QML to scan", len(files) > 0)
    for path in files:
        for line, kind in uncovered(path.read_text(encoding="utf-8")):
            where = f"{path.relative_to(root)}:{line}"
            problems.append(where)
            print(f"FAIL {kind} at {where} takes a click and shows no pointer — "
                  "set cursorShape, or say why with `// pointer-exempt:`")

    base = root / "Surfaces/Bar/Modules/BarIndicator.qml"
    check("the bar's cursor follows `interactive`",
          base_follows_interactive(base.read_text(encoding="utf-8")))

    if problems:
        print(f"{len(problems)} problem(s): {', '.join(problems)}")
        return 1
    print(f"pointer affordance: {len(files)} QML files clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
