r"""Reads the class folders next to this file and rewrites the sound list RatBites plays from.

Each folder is a bag ("Death Knight" -> deathknight); every .ogg in it is a variant, by any name.
Add or remove .ogg files in a folder, then run "Update sounds.bat". Folders starting with "_" are
skipped (keep sounds there you're only listening to). The game can't list files itself, so this list
(List.lua) is what it reads, and it only finds NEW files after a full restart.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LEVELS = (25, 50, 75)  # % volume copies in vNN\ folders (the game can't turn one sound down)

# folder name word -> bag name RatBites asks for (longest words first: "hunter gun" before "gun")
BAGS = {
    "tank": "tank", "heal": "heal", "bow": "bow", "gun": "gun",
    "death knight": "deathknight", "paladin": "paladin", "warrior": "warrior", "rogue": "rogue",
    "mage": "mage", "warlock": "warlock", "priest": "priest", "shaman": "shaman", "druid": "druid",
}
DEFAULT_DPS = "rogue"  # a class with no folder of its own plays this one

try:  # optional: without it there are no quieter copies and the volume setting hides
    import numpy as np
    import soundfile as sf
except ImportError:
    sf = None


def bag_of(folder):
    if folder.startswith("_") or folder.lower() in {f"v{l}" for l in LEVELS}:
        return None
    low = folder.lower()
    for word, bag in BAGS.items():
        if word in low:
            return bag
    return None


def volume_files():
    """Every .ogg in the vNN folders, relative to this folder."""
    out = set()
    for level in LEVELS:
        top = os.path.join(HERE, f"v{level}")
        for root, _, files in os.walk(top):
            for f in files:
                if f.lower().endswith(".ogg"):
                    out.add(os.path.relpath(os.path.join(root, f), HERE))
    return out


def write_level(src, dst, level):
    """A copy of src at level% of its loudness."""
    if os.path.exists(dst) and os.path.getmtime(dst) >= os.path.getmtime(src):
        return
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    data, rate = sf.read(src, always_2d=True)
    data = np.clip(data * (level / 100.0), -1.0, 1.0)
    sf.write(dst, data, rate, format="OGG", subtype="VORBIS")


def read_list():
    """The files the current Sounds.lua names, to tell new files from known ones."""
    p = os.path.join(HERE, "List.lua")
    if not os.path.exists(p):
        return set()
    import re
    return set(re.findall(r'"([^"]+\.ogg)"', open(p, encoding="utf-8").read()))


def main():
    known = read_list()
    before = volume_files()
    lists, wanted, used = {}, set(), set()
    for folder in sorted(os.listdir(HERE)):
        src = os.path.join(HERE, folder)
        bag = bag_of(folder) if os.path.isdir(src) else None
        if not bag:
            continue
        names = []
        for f in sorted(os.listdir(src)):
            if not f.lower().endswith(".ogg"):
                continue
            rel = f"{folder}\\{f}"
            names.append(rel)
            used.add(rel)
            if sf:
                for level in LEVELS:
                    copy = os.path.join(f"v{level}", folder, f)
                    write_level(os.path.join(src, f), os.path.join(HERE, copy), level)
                    wanted.add(copy)
        lists.setdefault(bag, []).extend(names)
        print(f"{folder:24} -> {bag:12} {len(names)} sounds")

    for f in before - wanted:  # quieter copies of sounds no folder has any more
        os.remove(os.path.join(HERE, f))
    for level in LEVELS:  # and the folders they leave empty
        top = os.path.join(HERE, f"v{level}")
        for root, dirs, files in os.walk(top, topdown=False):
            if not os.listdir(root):
                os.rmdir(root)

    def lua(names):
        return ", ".join('"%s"' % n.replace("\\", "\\\\") for n in names)

    lines = [
        "-- Written by \"Update sounds.bat\": one bag per folder here. Don't edit, edit the folders.",
        "RatBitesSounds = {",
        "\tpath = [[Interface\\AddOns\\RatBites\\Sounds\\]],",
    ]
    if sf:
        lines.append("\tvolumes = { %s }," % ", ".join(str(l) for l in LEVELS))
    for bag, names in lists.items():
        lines.append("\t%s = { %s }," % (bag, lua(names)))
    if DEFAULT_DPS in lists:
        lines.append("\tdps = { %s }," % lua(lists[DEFAULT_DPS]))
    lines.append("}")
    with open(os.path.join(HERE, "List.lua"), "w", encoding="utf-8", newline="\r\n") as fh:
        fh.write("\n".join(lines) + "\n")

    print()
    if not sf:
        print("(No volume copies: Python's soundfile isn't installed. pip install soundfile)")
    new = sorted(used - known)
    if new:
        print(f"{len(new)} new sound files (e.g. {', '.join(new[:4])})")
        print(">>> CLOSE WoW AND OPEN IT AGAIN: the game only finds new files when it starts.")
    else:
        print(">>> Done. Type /reload in game.")


if __name__ == "__main__":
    main()
