r"""Builds Effects-Data.lua: for each class, every spell that makes a number under another name and the
class spell, talent or glyph that causes it (Blood Corruption -> Seal of Corruption).

Reads the client's own tables (extract_dbc.py pulls them out of the MPQs):
    python gen_effects.py <dbc folder> <out Effects-Data.lua> [audit.txt]

A root is what a player has: a class spell (SkillLineAbility of the class's skill lines), a talent
(Talent.dbc, every rank) or a glyph (GlyphProperties). Its effects are the spells it triggers
(EffectTriggerSpell, followed down), the spells it learns (a talent that teaches one), and, for what the
game triggers in code rather than in the tables, the same-family spells its text names or that share
its icon and a word of its name.
"""
import os
import re
import struct
import sys
from collections import defaultdict

CLASSES = {1: "WARRIOR", 2: "PALADIN", 3: "HUNTER", 4: "ROGUE", 5: "PRIEST", 6: "DEATHKNIGHT",
           7: "SHAMAN", 8: "MAGE", 9: "WARLOCK", 11: "DRUID"}
FAMILY = {"MAGE": 3, "WARRIOR": 4, "WARLOCK": 5, "PRIEST": 6, "DRUID": 7, "ROGUE": 8, "HUNTER": 9,
          "PALADIN": 10, "SHAMAN": 11, "DEATHKNIGHT": 15}

# Spell.dbc columns (3.3.5a, 234 fields)
F_EFFECT, F_AURA, F_TRIGGER = 71, 95, 116
F_ICON, F_NAME, F_DESC, F_FAMILY = 133, 136, 170, 208

# effects and auras that put a number on screen
NUMBER_EFFECTS = {2, 9, 10, 17, 30, 31, 58, 62, 67, 121, 136, 137}  # damage, leech, heal, energize, weapon
NUMBER_AURAS = {3, 8, 20, 24, 53, 64}  # periodic damage / heal / energize / leech
LEARN_SPELL = 36


class DBC:
    def __init__(self, path):
        raw = open(path, "rb").read()
        magic, self.count, self.fields, self.size, strings = struct.unpack("<4s4I", raw[:20])
        assert magic == b"WDBC", path
        self.body = raw[20:20 + self.count * self.size]
        self.strings = raw[20 + self.count * self.size:]

    def rows(self):
        n = self.size // 4
        for i in range(self.count):
            yield struct.unpack_from(f"<{n}I", self.body, i * self.size)

    def text(self, offset):
        end = self.strings.find(b"\0", offset)
        return self.strings[offset:end].decode("utf-8", "replace")


def main():
    src, out = sys.argv[1], sys.argv[2]
    audit_path = sys.argv[3] if len(sys.argv) > 3 else None
    load = lambda n: DBC(os.path.join(src, n))

    spells, sdbc = {}, load("Spell.dbc")
    for r in sdbc.rows():
        spells[r[0]] = {
            "name": sdbc.text(r[F_NAME]),
            "desc": sdbc.text(r[F_DESC]),
            "icon": r[F_ICON],
            "family": r[F_FAMILY],
            "effects": r[F_EFFECT:F_EFFECT + 3],
            "auras": r[F_AURA:F_AURA + 3],
            "triggers": [t for t in r[F_TRIGGER:F_TRIGGER + 3] if t],
        }
    for s in spells.values():
        s["numbers"] = any(e in NUMBER_EFFECTS for e in s["effects"]) or \
            any(e == 6 and a in NUMBER_AURAS for e, a in zip(s["effects"], s["auras"]))
        # a spell this one teaches (a talent that gives a spell): the learn effect's trigger
        s["learns"] = [t for e, t in zip(s["effects"], s["triggers"] + [0, 0, 0]) if e == LEARN_SPELL and t]

    # class skill lines (category 7 = class) and the spells on them, by class mask
    skill = load("SkillLine.dbc")
    class_lines = {r[0] for r in skill.rows() if r[1] == 7}
    roots = defaultdict(dict)  # class -> spell id -> kind
    for r in load("SkillLineAbility.dbc").rows():
        _, line, spell, _, classmask = r[:5]
        if line in class_lines and spell in spells:
            for cid, cls in CLASSES.items():
                if classmask & (1 << (cid - 1)):
                    roots[cls][spell] = "class"
    # talents: every rank, under the tab's class
    tab_class = {}
    for r in load("TalentTab.dbc").rows():
        for cid, cls in CLASSES.items():
            if r[20] & (1 << (cid - 1)):
                tab_class[r[0]] = cls
    for r in load("Talent.dbc").rows():
        cls = tab_class.get(r[1])
        if cls:
            for spell in r[4:13]:
                if spell in spells:
                    roots[cls][spell] = "talent"
    # glyphs: the glyph's spell, by the family of what it triggers or its own
    glyph_ids = [r[1] for r in load("GlyphProperties.dbc").rows() if r[1] in spells]
    by_family = {v: k for k, v in FAMILY.items()}
    for gid in glyph_ids:
        g = spells[gid]
        fam = g["family"] or next((spells[t]["family"] for t in g["triggers"] if t in spells and spells[t]["family"]), 0)
        cls = by_family.get(fam)
        if cls and g["name"].startswith("Glyph of"):
            roots[cls][gid] = "glyph"

    words = lambda name: {w for w in re.findall(r"[A-Za-z]+", name) if w not in ("of", "the")}
    # how many spell texts name a phrase: a general spell named in few (Replenishment) is a real link,
    # one named everywhere (Fire, Attack, Damage) is just a word
    all_text = chr(10).join(s["desc"] for s in spells.values())
    counted = {}
    BOUND = chr(92) + "b"  # a word edge in a pattern

    def mentions(name):
        if name not in counted:
            counted[name] = len(re.findall(BOUND + re.escape(name) + BOUND, all_text))
        return counted[name]
    # what each spell is triggered or taught by, all the way up
    up = defaultdict(set)
    for sid, s in spells.items():
        for t in s["triggers"] + s["learns"]:
            up[t].add(sid)

    def ancestors(sid):
        seen, todo = set(), list(up[sid])
        while todo:
            a = todo.pop()
            if a not in seen:
                seen.add(a)
                todo += up[a]
        return seen

    effects, audit = {}, []
    for cls in sorted(roots):
        fam = FAMILY[cls]
        root_ids = roots[cls]
        by_name = defaultdict(list)  # a root's name -> its ids (ranks)
        for rid in root_ids:
            by_name[spells[rid]["name"]].append(rid)
        parents = {}  # effect name -> [root names, strongest link first]
        for sid, s in spells.items():
            name = s["name"]
            if not s["numbers"] or not name:
                continue
            general = s["family"] == 0
            if s["family"] != fam and not general:
                continue
            if general and not any(name in spells[i]["desc"] for i in root_ids):
                continue
            if general and mentions(name) > 20:
                continue
            found = parents.setdefault(name, {})

            def add(root, tier):
                # strongest link kept: 0 the tables, 1 a shared word, 2 only named in its text
                if root != name and tier < found.get(root, 9):
                    found[root] = tier
            # 1. the tables: a root that triggers or teaches it
            for a in ancestors(sid):
                if a in root_ids:
                    add(spells[a]["name"], 0)
            # 2. a root whose text names it: a link when they share a word (Judgement of Light and
            # Judgement), weak when not (a talent that only makes it stronger)
            pattern = re.compile(BOUND + re.escape(name) + BOUND)
            for root, ids in by_name.items():
                if any(pattern.search(spells[i]["desc"]) for i in ids):
                    add(root, 1 if words(root) & words(name) else 2)
            # 3. a same-class root with its icon and a word of its name (a seal and its effects)
            if not general:
                for root, ids in by_name.items():
                    if any(spells[i]["icon"] == s["icon"] for i in ids) and words(root) & words(name):
                        add(root, 1)
        # strongest link first, then a class spell before a talent before a glyph, then by name
        KIND = {"class": 0, "talent": 1, "glyph": 2}
        kind_of = {spells[rid]["name"]: KIND[k] for rid, k in root_ids.items()}
        parents = {n: sorted(p, key=lambda r: (p[r], kind_of.get(r, 3), r)) for n, p in parents.items()}
        effects[cls] = {n: p for n, p in parents.items() if p}
        for n in sorted(effects[cls]):
            audit.append(f"{cls:12} {n} <- {' | '.join(effects[cls][n])}")

    lines = [
        "-- Generated by scripts/gen_effects.py from the 3.3.5a client's Spell, Talent and Glyph tables;",
        "-- don't edit. For each class: a spell that makes a number -> the class spells, talents or glyphs",
        "-- that can cause it, strongest link first; RatBites takes the first one you have.",
        "RatBitesEffects = {",
    ]
    lua = lambda t: '"' + t.replace("\\", "\\\\").replace('"', '\\"') + '"'
    for cls in sorted(effects):
        lines.append(f"\t{cls} = {{")
        for name in sorted(effects[cls]):
            lines.append(f"\t\t[{lua(name)}] = {{ {', '.join(lua(p) for p in effects[cls][name])} }},")
        lines.append("\t},")
    lines.append("}")
    with open(out, "w", encoding="utf-8", newline="\r\n") as fh:
        fh.write("\n".join(lines) + "\n")
    print(out, sum(len(v) for v in effects.values()), "effects")
    if audit_path:
        open(audit_path, "w", encoding="utf-8").write("\n".join(audit) + "\n")


if __name__ == "__main__":
    main()
