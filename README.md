# RatBites

Damage and heal numbers with spell icons, right on each nameplate. For World of Warcraft 3.3.5a.

- Your hits rise in a short arc over the enemy's nameplate: grey for normal hits, gold for big hits,
  orange for crits.
- Your heals show in green over the friend you healed, however you cast them (raid frames, mouseover).
  This needs friendly nameplates on; hide their look in your nameplate addon and the numbers still
  show. Heals with no plate rise in a column right of the screen's centre.
- What you do shows on nameplates or in My box; what lands on you (your self-heals too) always goes
  to the Received box, and can also float over your character.
- Pick what shows: normal or critical hits, auto-attacks, abilities, damage over time, heals, misses,
  pet damage.
- Optional incoming damage and heals, left of the screen's centre.
- Turns the game's own floating numbers off while it runs, and puts them back when you disable it.

## Commands

- `/bites` (or `/ratbites`): settings
- `/bites test`: one number of each kind on your target

## Notes

3.3.5a nameplates don't carry a unit id, so numbers are matched to plates by name. When several mobs
with the same name are on screen, your target always gets its numbers; the others keep the plate they
were last seen on. With nameplates off, only your target's numbers show, above the screen's centre.

See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
