"""Pulls the DBC tables Effects-Data needs out of the 3.3.5a client's MPQs, newest patch winning.

    python extract_dbc.py "D:\\Games\\world of warcraft 3.3.5a hd stable" out_dir
"""
import os
import sys

import mpyq

WANT = ["Spell.dbc", "Talent.dbc", "TalentTab.dbc", "GlyphProperties.dbc", "SkillLineAbility.dbc",
        "SkillLine.dbc", "SpellItemEnchantment.dbc", "ChrClasses.dbc"]


def archives(game):
    """Every MPQ, lowest priority first (WoW loads patch-2..9 then patch-a..z over the base)."""
    data = os.path.join(game, "data")
    out = []
    for folder in (data, os.path.join(data, "enus")):
        for f in os.listdir(folder):
            if f.lower().endswith(".mpq"):
                out.append(os.path.join(folder, f))

    def rank(path):
        name = os.path.basename(path).lower()[:-4]
        locale = "enus" in name
        if not name.startswith("patch"):
            return (0, locale, name)
        tail = name.rsplit("-", 1)[-1] if name.count("-") >= (2 if locale else 1) else ""
        return (1, tail, locale)
    return sorted(out, key=rank)


def main():
    game, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    found = {}
    for path in archives(game):
        try:
            mpq = mpyq.MPQArchive(path, listfile=True)
        except Exception as e:
            print("skip", os.path.basename(path), e)
            continue
        names = {n.decode("latin-1").lower(): n for n in (mpq.files or [])}
        for want in WANT:
            key = ("dbfilesclient\\" + want).lower()
            if key in names:
                try:
                    data = mpq.read_file(names[key].decode("latin-1"))
                except Exception as e:
                    print("cannot read", want, "from", os.path.basename(path), e)
                    continue
                if data:
                    found[want] = (os.path.basename(path), data)
    for want, (src, data) in found.items():
        open(os.path.join(out, want), "wb").write(data)
        print(f"{want:28} {len(data):>10} bytes  from {src}")
    for want in WANT:
        if want not in found:
            print("MISSING", want)


if __name__ == "__main__":
    main()
