# Harvester Reflavor (Summoner rename + Scythe weapon fix) — Design

**Date:** 2026-08-23
**Status:** Approved by player, ready for implementation planning.

This spec closes out the naming/theme work the minion-summoning class (`&"summoner"` in
`combat/class_library.gd`) has been carrying as an explicit placeholder since it shipped —
`docs/superpowers/specs/2026-08-16-summoner-ability-kit-design.md` §9 flagged every name in the
kit (class, minions, Ultimate) as "a working name the player intends to revisit later." It also
fixes a real balance gap surfaced during the 2026-08-21 human playtest (see Background).

This spec is **naming/tuning only** — it does not touch the minion mechanism (summon-reel,
3-stage auto-cast escalation, expiry rules) or the meter economy, both of which are shipped,
playtested, and confirmed working as-is.

---

## Background

The 2026-08-21 playtest of the Summoner Bonus Meter economy fix (`1fd1130`) was positive overall —
Grand Sacrifice's bonus fires correctly, and the class now hits its Ultimate roughly every other
minion cast as intended. But it surfaced a new complaint: with a minion in play and no Ultimate
available, the class's weapon-only attack (2 action reels) reads as a bland "stick hitter."

Investigation (this session) found the real cause was **not** the reel count. Comparing every
class's `(weapon_base_damage × reel_count × 0.6)` expected-damage-per-turn (0.6 = the fraction of
`ActionReel.make_default()`'s 50 faces that deal damage: 40% SUCCESS at 1.0x + 10% CRIT_SUCCESS at
2.0x):

| Class | Weapon | Reels | Base Dmg | Expected dmg/turn |
|---|---|---|---|---|
| Vanguard | War Hammer | 2 | 15.0 | 18.0 |
| Seer | Mystic War Staff | 2 | 13.0 | 15.6 |
| Warden | Earthstave | 3 | 9.0 | 16.2 |
| Warrior | Steel Longsword | 3 | 8.0 | 14.4 |
| Ranger | Hunting Bow | 4 | 7.0 | 16.8 |
| **Summoner (current)** | Warden's Staff | 2 | 6.0 | **7.2** |

The Summoner's weapon deals under half the expected damage of every other class, including the
other two 2-reel "heavy hitters" (Vanguard, Seer). `weapon_base_damage = 6.0` was simply never
tuned up to a real 2-reel-tier number — the class was presumably assumed to lean on minions/
abilities instead. This spec fixes that number directly rather than changing the reel count.

---

## 1. Class rename: Summoner → Harvester

- `combat/class_library.gd`: `c.display_name = "Summoner"` → `"Harvester"`. `class_id` stays
  `&"summoner"` (an internal StringName key, not player-facing — renaming it would touch every
  save/reference for no player-visible benefit; see Open Questions).
- Theme: a druid/farmer archetype with a deep connection to nature, who calls up plant-spirit
  minions rather than generic "summons." All other renames in this spec (weapon, minions,
  Ultimate) serve this identity.

## 2. Weapon: Warden's Staff → Scythe (2 reels, retuned damage)

- `combat/class_library.gd`, `&"summoner"` case: `c.weapon_display_name = "Warden's Staff"` →
  `"Scythe"`. `c.reel_count` stays `2`. `c.weapon_base_damage` changes from `6.0` to **`14.0`**
  (between Seer's 13.0 and Vanguard's 15.0 — the class's two 2-reel peers), landing at ~16.8
  expected dmg/turn, in line with every other class instead of roughly half of it.
- `c.weapon_type` stays `earth` (see §5 — no new damage type needed or wanted).
- This is a **straight stat/name swap on the existing weapon slot**, not a new equippable item
  type — the player has confirmed a future direction where classes can equip additional weapon
  types beyond their starting one, but that system doesn't exist yet and is explicitly out of
  scope here (see Open Questions).
- Visual direction (for whenever real art replaces the placeholder rectangle): a magical scythe
  swing rather than a raw physical sweep — reinforces this is a nature-magic caster, not a melee
  reaper. Not implementable yet; noted for the eventual art pass.

## 3. Minion renames (display names only — mechanism, costs, and stage effects unchanged)

`combat/minion_library.gd`'s `DISPLAY_NAMES` dictionary, mapped by existing `minion_type` key
(`&"ember"`, `&"dew"`, `&"misfortune"`, `&"hasty"` — **StringName keys unchanged**, same rationale
as `class_id` above):

| `minion_type` key | Old display name | New display name | Mechanical role (unchanged) |
|---|---|---|---|
| `&"ember"` | Ember Minion | **Touch-Me-Not** | Single-target burst damage |
| `&"dew"` | Dew Minion | **Lotus** | AoE heal + cleanse-oldest-debuff |
| `&"misfortune"` | Misfortune Minion | **Nightshade** | Debuff/jinx application |
| `&"hasty"` | Hasty Minion | **Wheat** | Buff: extra attack reel + resource regen |

Naming rationale: Touch-Me-Not (Jewelweed) is a real wild plant whose seed pods visibly swell and
explosively burst when ripe — a near-literal match for "grows across 3 stages, then detonates for
burst damage," and deliberately NOT fire-colored (the burst is a kinetic/visual metaphor, not an
elemental one, matching the retained Earth damage type in §5). Lotus carries purity/rebirth
symbolism fitting the cleanse mechanic. Nightshade's poison association needs no explanation.
Wheat supports a wind/breeze visual treatment that doubles as an at-a-glance "buff is active" tell.

**Deferred, not designed here:** the runner-up names considered and rejected for now — Thistle,
Water Lily, Foxglove, Dandelion — were NOT discarded. Player wants these reserved as candidate
plant-swap variants unlockable via a future talent-tree pick or other end-game system. No mechanic
exists for this yet; flagged for a future spec.

## 4. Ultimate rename: Grand Sacrifice → Strawfellow's Due

- Every reference to `&"grand_sacrifice"`'s **display name** (wherever the Ultimate is shown in
  UI/logs) changes to **"Strawfellow's Due."** The ability id `&"grand_sacrifice"` stays unchanged
  (same internal-key rationale as above).
- In-world naming: **Old Strawfellow** is an original (confirmed via web search — no prior
  folkloric or fictional character found under this name) whimsical, semi-mythic wandering
  scarecrow-spirit, in the vein of a Tom Bombadil-style figure for this setting. Folklore holds he
  blesses a farmer's field generously if given a fair portion of the harvest back, and lets a
  stingy field go to rot. The scarecrow-as-effigy image mirrors the Ultimate's actual mechanic
  (consume the active minion for a burst effect) more directly than the generic "Grand Sacrifice"
  did, and doubles as a reusable worldbuilding figure beyond just this one ability name (e.g. for
  `docs/design-bible/` lore, an NPC, or overworld set-dressing later — not scoped here).
- Mechanically **unchanged**: the Ultimate's effect still varies by whichever minion is currently
  active (large single-target burst if Touch-Me-Not, AoE heal+cleanse if Lotus, party-wide jinx if
  Nightshade, party-wide buff if Wheat), per the shipped 2026-08-16 spec §8. No minion "owns" the
  sacrifice theme mechanically — it's generic across all four by design.

## 5. Damage type: stays Earth, no new type added

Player asked whether a dedicated "Nature" damage type exists among the project's 8 types
(Slashing, Piercing, Crushing, Storm, Mystic, Earth, Light, Dark — CLAUDE.md §4). It does not —
Earth is already the closest thematic fit for grounded/natural power, and it's shared with Warden
(Earthstave), another nature-adjacent class. Per CLAUDE.md §7's explicit scope discipline ("resist
adding a 7th damage type... just because"), this spec does NOT add a new type. Earth stays the
Harvester's weapon and minion (`defense_type`) type, unchanged from current code.

## 6. Visual design direction (not implementable yet — noted for the future art pass)

The project currently uses placeholder-rectangle art (CLAUDE.md §1) — nothing in this section
requires code changes now. Recorded here so the intent isn't lost before a real art pass:

- All four minions should share one legible 3-stage growth **grammar**, serving the project's
  legibility pillar (CLAUDE.md §3): Stage 1 = sprout/bud, low visual noise. Stage 2 = visibly
  swelling/deepening color, a particle tell begins. Stage 3 = fully grown, straining, visibly
  primed. A player should be able to read ANY minion's current stage at a glance without needing
  to learn each plant's tells separately.
- Each plant's actual **burst** (stage-3 payoff or Strawfellow's Due consumption) gets a UNIQUE
  animation/particle treatment layered on top of that shared grammar — e.g. Touch-Me-Not's pod
  visibly ruptures outward, Lotus fully unfurls into a radiant pulse, Nightshade's blooms release a
  toxic spore cloud, Wheat's stalks whip and scatter in a gust.
- Even placeholder-rectangle art can approximate this today via simple scale/tint changes on the
  minion's panel sprite per stage, ahead of any real art existing.

---

## Open Questions (explicitly deferred, not blocking this spec)

- Whether `class_id = &"summoner"` and `minion_type` keys / ability ids (`&"ember_minion"`,
  `&"grand_sacrifice"`, etc.) ever get renamed to match their new display names. Decided NOT to
  touch them here — they're internal keys with no player-facing surface, and renaming risks
  breaking existing references for zero visible benefit. Revisit only if a concrete need arises
  (e.g. a save-file migration is already happening for another reason).
- The "classes can equip additional weapon types beyond their starting one" system the player
  mentioned in passing — does not exist yet, not designed here, would be its own future spec.
- Plant-swap unlockable variants (Thistle/Water Lily/Foxglove/Dandelion) via talent tree or
  end-game system — flagged in §3, not designed.
- Strawfellow as a broader worldbuilding figure (design-bible lore entry, NPC, overworld
  set-dressing) — flagged in §4, not designed.

---

## Implementation summary (for the next writing-plans pass)

All changes are display-string and one numeric-constant edits, no mechanism changes:

- **Modify:** `combat/class_library.gd` — `&"summoner"` case: `display_name`, `weapon_display_name`,
  `weapon_base_damage` (6.0 → 14.0).
- **Modify:** `combat/minion_library.gd` — `DISPLAY_NAMES` dictionary values (4 entries).
- **Modify:** wherever the Ultimate's display name is sourced for UI/log text (likely an ability-
  display-name lookup keyed by `&"grand_sacrifice"` — needs locating during planning; grep for the
  ability id's existing display string, not "Grand Sacrifice" as literal text, since the id itself
  is unchanged).
- **Tests:** update any test asserting the old display strings ("Summoner", "Warden's Staff", "Ember
  Minion", "Dew Minion", "Misfortune Minion", "Hasty Minion", "Grand Sacrifice" as a display string)
  to the new names; add/adjust a weapon-damage assertion for the new `14.0` base damage on
  `&"summoner"`'s weapon.
