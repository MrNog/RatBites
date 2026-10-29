<p align="center">
  <img src="docs/images/banner.jpg" alt="RatBites — combat numbers for WoW 3.3.5a" width="100%">
</p>

<p align="center">
  <b>Combat numbers with spell icons for World of Warcraft 3.3.5a.</b><br>
  Your hits and heals on each nameplate, what lands on you in its own box.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/WoW-3.3.5a%20WotLK-1f6feb?style=flat-square" alt="WoW 3.3.5a">
  <img src="https://img.shields.io/badge/Interface-30300-c0943a?style=flat-square" alt="Interface 30300">
  <img src="https://img.shields.io/badge/license-all%20rights%20reserved-8a8d93?style=flat-square" alt="All rights reserved">
  <img src="https://img.shields.io/badge/changes-via%20pull%20request-c0943a?style=flat-square" alt="Changes via pull request">
</p>

---

## What you see

- **Output, what you do:** every hit and heal rises over its target's nameplate with the spell's icon,
  or goes into the **Output box**. Heals land on the friend you healed however you cast them (raid frames,
  mouseover); friendly nameplates must be on, but you can hide their look in your nameplate addon.
- **Receiving, what lands on you:** heals, shields and hits on you (your self-heals too) go to the
  **Input box**, and can also float over your character.
- **Colours that tell you what happened:** grey hits, gold big hits, orange crits, green heals, mint
  heal crits, dim overheal, blue shields, red damage taken. Crits get a thick outline and bigger text.

## Features

| | |
|---|---|
| **Nameplates** | Numbers ride the enemy's or friend's plate, with ElvUI plates too. Hits landing together stack a line apart. |
| **Boxes** | Output box (what you do) and Input box (what lands on you), xCT style. Move and resize them; each has its own scroll direction, alignment, merge and line time. |
| **Merging** | In a box, the same spell again within a few seconds joins one line as a total with `x5`, like an AoE on five mobs. |
| **Shields** | Val'anyr (with its mace icon), Divine Aegis and Sacred Shield show their size; Power Word: Shield shows as *Shield*. |
| **Weapon icon** | Your auto-attacks show the weapon you have equipped. |
| **Animations** | Arc, Rise, Stay, Fountain or Fall, with sideways drift, travel distance and time on screen. |
| **Look** | Any font your addons share (ElvUI, SharedMedia), text and icon size, crits in your class colour. |
| **Filters** | Normal or critical hits, auto-attacks, spells, damage over time, heals and shields, misses, pet. |
| **Game numbers** | The game's own floating numbers turn off while RatBites runs and come back when you disable it. |

<p align="center">
  <img src="docs/images/colors.png" alt="Every kind of number in its colour" width="40%">
</p>

## Install

1. Download **RatBites.zip** from the latest release.
2. Unzip it into `World of Warcraft\Interface\AddOns\` so you have a **`RatBites`** folder.
3. Restart the game.

## Use

- `/bites` (or `/ratbites`), or click the rat on the minimap: settings
- `/bites test`: one number of each kind on your target
- `/bites colors`: every kind of number in its colour, as your settings draw it
- `/bites move`: unlock the boxes to move and resize them
- `/bites sound`: plays each crit sound, and says which one your crits use now

## Crit sounds

Your crits play a sound, one bag per role or class. The sounds are in RatBites' **`Sounds`** folder,
one folder per bag, and you can change them.

```
Interface\AddOns\RatBites\Sounds\
  Tank\  Healer\  Hunter Bow\  Hunter Gun\
  Death Knight\  Paladin\  Warrior\  Rogue\
  Mage\  Warlock\  Priest\  Shaman\  Druid\
  List.lua             the list RatBites reads
  Update sounds.bat    rewrites that list from the folders (needs Python)
```

Turn the sounds off with **Crit sounds** in the settings.

- **Which bag plays:** a heal crit plays *Healer*, while tanking *Tank*, a hunter *Hunter Bow* or
  *Hunter Gun* (the weapon equipped), anyone else their class folder. A class without a folder
  uses *Rogue*.
- **Variants:** every `.ogg` in a folder is a variant, by any name. They play in a shuffled order, so
  the same sound doesn't play twice in a row.
- **Adding or removing sounds:** put `.ogg` files in a folder or take them out, then run
  **Update sounds.bat**. Folders starting with `_` are skipped: keep sounds there that you're only
  trying out.
- **Why the extra step:** WoW can't look inside a folder. It plays a sound only by its exact file name,
  so `List.lua` has to list them, and the game finds new files only when it starts. After adding
  files, **close WoW and open it again**. After only removing files, `/reload` is enough.
- **Volume:** the game can't turn one sound down. With Python's `soundfile` installed, the update also
  writes quieter copies (25/50/75 %), and the **Crit volume** setting picks one.
- **Testing:** `/bites sound` plays every bag. *Test as* (bottom of the settings) lets you hear and
  see another class or role on your own hits.
- **When a crit plays a sound:** only when its number is shown (*Which hits* and the plate/box ticks),
  and only when both ticks of its spell are on in the *Spells* page.

## Notes

3.3.5a nameplates don't carry a unit id, so numbers are matched to plates by name. When several mobs
with the same name are on screen, your target always gets its numbers; the others keep the plate they
were last seen on. A heal on someone without a plate on screen goes to the Output box (or a column right of the screen's centre, or nowhere: your choice).

See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
