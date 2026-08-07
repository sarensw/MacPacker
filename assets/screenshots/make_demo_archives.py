#!/usr/bin/env python3
"""Regenerates the demo archives the screenshot plan (../../sandboxpilot.json) opens.

They live in ~/Downloads/MacPacker-Demo because that is the one place a sandboxed
MacPacker can read without the user picking a file (the downloads entitlement).
The archives are ~200 MB of incompressible filler, so they are generated rather
than committed — the entries only have to *look* like a real handoff bundle in a
screenshot, nothing ever opens their content.

    python3 assets/screenshots/make_demo_archives.py [--force]

Existing files are kept unless --force is passed, so a run never clobbers demo
assets that a recording is using.
"""

import datetime
import hashlib
import os
import sys
import zipfile

MB = 1024 * 1024
DEST = os.path.expanduser("~/Downloads/MacPacker-Demo")

# How much of each entry survives compression, by extension. The point is the
# Packed Size column: filler that is pure random data packs to 100% and every row
# then reads "14 MB / 14 MB", which makes the app look like it does nothing. Each
# entry is written as `ratio` random bytes followed by zeros, so deflate lands on
# roughly this ratio — loose for already-compressed formats, tight for text.
RATIO = {
    "pdf": 0.58, "png": 0.85, "jpg": 0.94, "mp4": 0.96, "m4a": 0.92, "psd": 0.36,
    "key": 0.71, "numbers": 0.68, "docx": 0.63, "xlsx": 0.59, "sketch": 0.54,
    "fig": 0.49, "md": 0.22, "dng": 0.55,
}
DEFAULT_RATIO = 0.7

# name -> size in MB. A folder entry is a name ending in "/".
HANDOFF = [
    ("Pricing.numbers", 2), ("Keynote Deck.key", 22), ("Roadmap.pdf", 5),
    ("Renders/", 0), ("Renders/Hero-4k.png", 14), ("Icon Set.sketch", 6),
    ("Teaser.mp4", 26), ("Moodboard.jpg", 8), ("Hero Render.png", 9),
    ("Brand Guidelines.pdf", 13), ("Launch Plan.docx", 3), ("Voiceover.m4a", 12),
    ("Docs/", 0), ("Docs/Notes.md", 1), ("Press Release.docx", 1),
    ("Site Mockup.fig", 11), ("Logo Master.psd", 38), ("Contract Signed.pdf", 4),
    ("Style Guide.pdf", 7), ("Photos/", 0), ("Photos/Launch-01.jpg", 6),
    ("Photos/Launch-02.jpg", 7), ("Budget Q3.xlsx", 2),
]

# The nested-archive shot: an archive inside an archive, both with entries whose
# sizes read as real files.
PHOTO_DELIVERY = [
    ("Delivery Notes.pdf", 2), ("Invoice.pdf", 1),
    ("Selects/", 0), ("Selects/Frame-014.jpg", 6), ("Selects/Frame-027.jpg", 7),
]
RAW_FILES = [("DSC_0142.dng", 12), ("DSC_0143.dng", 13), ("Contact Sheet.pdf", 3)]

# Loose files for the -AddFiles shots: filling a new archive, and adding to an
# existing one. Names deliberately absent from HANDOFF, so an added entry reads
# as an addition rather than a duplicate row.
EXTRAS = [("Handover Notes.pdf", 2), ("Final Logo.png", 5), ("Amendment.docx", 1)]


# Entry timestamps. Freshly written files all read "52 seconds ago" in the Date
# Modified column; a fixed date in the past reads like a real project bundle and
# keeps every run identical.
BASE_DATE = (2026, 7, 28, 9, 12, 0)


def info(name: str, index: int) -> zipfile.ZipInfo:
    """Entry metadata: a stable date, staggered per entry, and sane permissions
    (a bare ZipInfo has none, which shows up as 000 in the permissions column)."""
    year, month, day, hour, minute, second = BASE_DATE
    entry = zipfile.ZipInfo(name, date_time=(year, month, day, max(0, hour - index % 8), minute, second))
    entry.external_attr = (0o755 << 16) | 0x10 if name.endswith("/") else 0o644 << 16
    return entry


def filler(size: int, name: str) -> bytes:
    """`ratio` incompressible bytes padded with zeros (which compress to
    nothing), so the entry deflates to about `ratio` of its size.

    The bytes come from SHAKE-256 seeded with the entry, not from `os.urandom`:
    a hash stream is just as incompressible, and it makes a rebuild produce
    byte-identical archives — same fixtures, same screenshots, on any machine."""
    ratio = RATIO.get(name.rsplit(".", 1)[-1].lower(), DEFAULT_RATIO)
    noise = int(size * ratio)
    seed = f"{name}:{size}".encode()
    return hashlib.shake_256(seed).digest(noise) + bytes(size - noise)


def write(zf: zipfile.ZipFile, name: str, megabytes: int, index: int = 0) -> None:
    if name.endswith("/"):
        zf.writestr(info(name, index), b"")
        return
    zf.writestr(info(name, index), filler(megabytes * MB, name) if megabytes else b"demo\n",
                compress_type=zipfile.ZIP_DEFLATED)


def keep(path: str) -> bool:
    if os.path.exists(path) and "--force" not in sys.argv:
        print(f"keep   {os.path.relpath(path, DEST)} (exists — pass --force to rebuild)")
        return True
    return False


def build(filename: str, entries, nested=None) -> None:
    path = os.path.join(DEST, filename)
    if keep(path):
        return
    with zipfile.ZipFile(path, "w") as zf:
        for index, (name, size) in enumerate(entries):
            write(zf, name, size, index)
        if nested:
            inner_name, inner_entries = nested
            inner_path = os.path.join(DEST, ".inner.zip")
            with zipfile.ZipFile(inner_path, "w") as inner:
                for index, (name, size) in enumerate(inner_entries):
                    write(inner, name, size, index)
            # stored: a zip inside a zip is already compressed, and deflating it
            # again would only make the entry bigger
            nested_info = info(inner_name, len(entries))
            nested_info.compress_type = zipfile.ZIP_STORED
            with open(inner_path, "rb") as f:
                zf.writestr(nested_info, f.read())
            os.remove(inner_path)
    print(f"wrote  {filename} ({os.path.getsize(path) // MB} MB)")


if __name__ == "__main__":
    os.makedirs(os.path.join(DEST, "extra"), exist_ok=True)
    build("Handoff.zip", HANDOFF)
    build("Photo Delivery.zip", PHOTO_DELIVERY, nested=("Raw Files.zip", RAW_FILES))
    stamp = datetime.datetime(*BASE_DATE).timestamp()
    for name, size in EXTRAS:
        path = os.path.join(DEST, "extra", name)
        if not keep(path):
            with open(path, "wb") as f:
                f.write(filler(size * MB, name))
            # same fixed date as the archive entries — otherwise an added file
            # reads "2 minutes ago" in every screenshot
            os.utime(path, (stamp, stamp))
            print(f"wrote  extra/{name} ({size} MB)")
    print(f"\n{DEST}")
