#!/usr/bin/env python3
"""Build the launcher prototype's app fixture from the real desktop entries.

A fixture, not a live scan: the design study must render the *same* rows every
run so two screenshots differ only by the knob under test. Quickshell's own
`DesktopEntries.applications` also comes back empty in this environment
(see findings.md), so nothing is lost by baking it.

    ./tools/make-fixtures.py > fixtures/apps.json
"""

import configparser
import json
import os
import sys
from pathlib import Path

APP_DIRS = [
    Path.home() / ".local/share/applications",
    Path("/usr/share/applications"),
]
ICON_DIRS = [
    Path.home() / ".local/share/icons",
    Path("/usr/share/icons"),
    Path("/usr/share/pixmaps"),
]

# Apps a real session would actually show, in rough frecency order. Anything
# not installed is dropped silently.
WANTED = [
    "kitty", "Alacritty", "firefox", "zen", "chromium", "google-chrome",
    "code", "code-oss", "VSCodium", "zed", "org.gnome.Nautilus", "thunar",
    "spotify", "discord", "obsidian", "steam", "gimp", "inkscape", "krita",
    "org.kde.dolphin", "org.kde.okular", "org.kde.spectacle", "vlc", "mpv",
    "libreoffice-writer", "libreoffice-calc", "signal-desktop", "telegram-desktop",
    "thunderbird", "blender", "obs", "com.obsproject.Studio", "virt-manager",
    "btop", "htop", "nvim", "org.gnome.Calculator", "pavucontrol", "blueman-manager",
]


def has_icon(name: str) -> bool:
    if not name:
        return False
    if name.startswith("/"):
        return Path(name).exists()
    for d in ICON_DIRS:
        if not d.exists():
            continue
        for ext in (".png", ".svg", ".xpm"):
            hit = next(d.rglob(name + ext), None)
            if hit:
                return True
    return False


def read_entry(path: Path):
    cp = configparser.ConfigParser(interpolation=None, strict=False)
    try:
        cp.read(path, encoding="utf-8")
        s = cp["Desktop Entry"]
    except Exception:
        return None
    if s.get("NoDisplay", "false").lower() == "true":
        return None
    if s.get("Type") != "Application":
        return None
    return {
        "id": path.stem,
        "name": s.get("Name", path.stem),
        "subtitle": s.get("GenericName") or s.get("Comment") or "",
        "icon": s.get("Icon", ""),
    }


def main():
    found = {}
    for d in APP_DIRS:
        if not d.exists():
            continue
        for f in d.glob("*.desktop"):
            e = read_entry(f)
            if e and e["id"] not in found:
                found[e["id"]] = e

    out = []
    for want in WANTED:
        e = found.get(want)
        if e and has_icon(e["icon"]):
            out.append(e)

    # Top up from whatever else is installed so the list is long enough to scroll.
    for e in sorted(found.values(), key=lambda x: x["name"].lower()):
        if len(out) >= 40:
            break
        if e["id"] in {x["id"] for x in out}:
            continue
        if has_icon(e["icon"]):
            out.append(e)

    # Subtitles are kept whole — the row elides them, which is what the real
    # launcher will do, and truncating here would hide that from the study.
    json.dump({"apps": out}, sys.stdout, indent=1, ensure_ascii=False)
    print(file=sys.stderr and sys.stderr)
    print(f"{len(out)} apps", file=sys.stderr)


if __name__ == "__main__":
    main()
