#!/usr/bin/env python3
"""No `.qml` file may carry a raw control byte (#149).

`Services/Networking/WifiPolicy.qml` built its row signature by joining on
literal NUL and SOH bytes. Both consequences were invisible until something
tripped over them: git's binary heuristic keys off a NUL, so every diff of that
file read `Bin 11634 -> 12344 bytes` and no change to it was reviewable; and
`grep` skips the file it has decided is binary, so the address-first workflow
the repo runs on ("grep for the key, then Read a range") silently returned
nothing. The escape sequence `"\\x00"` is the same byte at runtime and none of
that.

The guard is a walk rather than a grep because grep cannot do this job: GNU
grep -P scans NUL-terminated buffers, so a NUL is exactly the byte its pattern
can never match — the check for the bug would have been blind to the bug.

    tests/tst_control_bytes.py     # part of tests/run.sh

Stdlib only, same rule as everything else inside a gate.
"""

import sys
import tempfile
from pathlib import Path

# Tab, newline and carriage return are the control bytes a text file is allowed
# to contain; every other byte below 0x20, plus DEL, is one someone typed by
# accident or pasted out of a terminal.
ALLOWED = {0x09, 0x0A, 0x0D}
NAMES = {0x00: "NUL", 0x01: "SOH", 0x07: "BEL", 0x08: "BS", 0x0B: "VT",
         0x0C: "FF", 0x1B: "ESC", 0x7F: "DEL"}


def offenders(data: bytes) -> list:
    """(line, column, byte) for every disallowed control byte in `data`.

    The column counts characters rather than bytes — a UTF-8 continuation byte
    is the back half of a character an editor already showed — so an address
    here is the one the editor puts the cursor on.
    """
    found = []
    line, column = 1, 1
    for byte in data:
        if byte < 0x20 or byte == 0x7F:
            if byte not in ALLOWED:
                found.append((line, column, byte))
        if byte == 0x0A:
            line, column = line + 1, 1
        elif byte & 0xC0 != 0x80:
            column += 1
    return found


def qml_files(root: Path) -> list:
    """Every `.qml` file under `root`, skipping dot-directories.

    `.git` holds packed originals of the very bytes this forbids, and
    `.claude/worktrees` holds whole copies of the repo at other commits — a
    sweep that walked either would report files no one in this checkout can fix.
    """
    return sorted(p for p in root.rglob("*.qml")
                  if not any(part.startswith(".") for part in p.relative_to(root).parts))


def describe(byte: int) -> str:
    return f"{NAMES.get(byte, 'control')} (0x{byte:02x})"


def main() -> int:
    problems = []

    def check(name, ok):
        print(("ok   " if ok else "FAIL ") + name)
        if not ok:
            problems.append(name)

    # The guard's own redness, checked here rather than by hand: a reintroduced
    # NUL has to be caught, and the bytes a source file legitimately holds have
    # to be left alone.
    check("a raw NUL is caught", offenders(b'join("\x00")') == [(1, 7, 0x00)])
    check("a raw SOH is caught", offenders(b'\njoin("\x01")') == [(2, 7, 0x01)])
    check("a raw ESC is caught", offenders(b'"\x1b[0m"') == [(1, 2, 0x1B)])
    check("tabs and newlines are fine", offenders(b"a\tb\r\nc\n") == [])
    check("escape sequences are fine", offenders(rb'join("\x00")') == [])
    check("UTF-8 is fine", offenders("row … end\n".encode()) == [])
    check("the column counts characters, not bytes",
          offenders("row … \x01".encode()) == [(1, 7, 0x01)])

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / ".git").mkdir()
        (root / ".git" / "packed.qml").write_bytes(b"\x00")
        (root / "kept.qml").write_bytes(b"ok\n")
        check("dot-directories are skipped",
              [p.name for p in qml_files(root)] == ["kept.qml"])

    root = Path(__file__).resolve().parent.parent
    scanned = qml_files(root)
    check("the sweep found QML to scan", len(scanned) > 0)
    for path in scanned:
        found = offenders(path.read_bytes())
        if found:
            line, column, byte = found[0]
            where = f"{path.relative_to(root)}:{line}:{column}"
            extra = f" (+{len(found) - 1} more)" if len(found) > 1 else ""
            problems.append(where)
            print(f"FAIL raw {describe(byte)} at {where}{extra} — write it as an escape sequence")

    if problems:
        print(f"{len(problems)} problem(s): {', '.join(problems)}")
        return 1
    print(f"control bytes: {len(scanned)} QML files clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
