# Ability & Universal Talent Tracks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the two-track talent system locked in
`docs/superpowers/specs/2026-07-24-ability-talent-track-redesign-design.md`: a per-row Ability
Talent system (6 rows per class, one point each at L5-10, 3 options per row, 126 total options) and
a Universal Perk track (10 already-approved general stat perks, now picked at L2/4/6/8/10).

**Architecture:** `Combatant.ability_talent_picks: Dictionary` (row_id → option_id) tracks Track A;
`Combatant.talent_perks: Array[StringName]` (unchanged shape from the original spec) tracks Track B.
Both are bespoke GDScript — no generic rules/condition framework, matching this codebase's existing
per-ability-method convention. `AbilityTalentLibrary`/`TalentPerkLibrary` are static registries
(mirrors `ClassLibrary`/`EnemyLibrary`). `TalentMenuPanel` (new) presents both tracks.

**Tech Stack:** Godot 4.6.3, GDScript, headless test suite (`Godot_v4.6.3-stable_win64_console.exe`
one directory above the repo root).

**Continues from:** `docs/superpowers/plans/2026-07-23-ability-talent-redesign.md` Tasks 1-11, all
shipped (level cap 10, L1-4 ability compression, 7 per-class L5 passives). This plan replaces that
plan's Tasks 12-17 (superseded, not executed — see the note at that plan's Task 12).

## Global Constraints

- Level cap 10 (already enforced, Task 1 of the prior plan). Ultimate usability stays
  level-independent (Bonus Meter only) — only the Ultimate's TALENT ROW needs L10, not the Ultimate
  itself.
- Track A (Ability Talents): 6 rows per class — `base_ability`(L5) / `ability_l2`(L6) /
  `ability_l3`(L7) / `ability_l4`(L8) / `passive`(L9) / `ultimate`(L10). Each row: exactly 3 options,
  cap of 1 pick per row ever, a row's point is never spendable on another row, can be saved
  indefinitely unspent.
- Track B (Universal Perks): 10 fixed perks (content locked, §4 of the 2026-07-24 spec), one pick
  opportunity at each of L2/L4/L6/L8/L10 (5 total), one-time-pick per perk id (non-stacking).
- Both tracks: swappable, town-only respec (mirrors `InventoryMenuPanel`'s `vault_available`
  safe-zone pattern exactly — a boolean param, already-spent picks stay visible everywhere, only the
  swap action is gated).
- `TalentMenuPanel`: new standalone floating panel (not an `InventoryMenuPanel` tab), opened via
  `toggle_talents` bound to `N` (confirmed free), wired into `town_demo.gd`/`overworld_demo.gd`/
  `dungeon_demo.gd` the same way `toggle_inventory`/`toggle_stats`/`toggle_event_log` already are
  (pause PC movement, block `interact` while open). No Talents button in `combat.tscn`.
- Ability Talent grid UI: ALL 6 rows shown per class, including locked ones — locked rows render
  grayed out with their unlock level (e.g. "Unlocks at Level 8"), a deliberate departure from
  `AbilityMenuPanel`'s hide-when-locked convention.
- Passives/talents/perks stay bespoke GDScript methods — no generic condition/rules engine.
- Every task that touches game logic ends with a real headless test run over the whole suite (not
  just the focused test) before committing, given how many tasks touch shared `Combatant` methods.
  3 known pre-existing failures predate this whole effort and are NOT regressions:
  `test_adventuring_board_panel.gd` (1 internal FAIL line), `test_overworld_demo_npcs.gd` (5),
  `test_overworld_encounter_variety.gd` (6) — all confirmed via isolated-worktree checks before this
  plan started. Any OTHER failing file is a real regression and must be fixed before committing.

---

## Task 12: 🛑 CONTENT CHECKPOINT — 126 Ability Talent options (all 7 classes)

**This is not a code task.** Present the following table to the player and get explicit approval
(as-is or with changes) before starting Task 15 onward (Tasks 13-14 build the framework/data model
and don't depend on this content, so they may proceed in parallel with the checkpoint if useful, but
the per-class content tasks — 15-21 — are blocked until this is approved).

Every row follows the same 3-column shape per the spec's simple-scope rule ("a flat percentage bump
or a small added effect"): **Potency** (numeric bump to the ability's core effect), **Rider** (an
added/extended secondary effect), **Utility** (a cost/cooldown/minor tweak). All magnitudes are
`[ASSUMPTION]` per this project's convention (CLAUDE.md §4) — tune by playtest, not final. Every
option's mechanic is grounded in that ability's real, already-shipped implementation (verified
against `combat/combatant.gd`/`combat/combat.gd`/`combat/effect_library.gd`, not guessed).

### Warrior (Steel Longsword, Slashing, Stamina)

| Row | id | Name | Effect |
|---|---|---|---|
| base_ability (Rend) | `rend_deeper_cut` | Deeper Cut | Bleed's DoT damage +25% |
| base_ability (Rend) | `rend_lasting_wound` | Lasting Wound | Bleed's max stacks 3→4 |
| base_ability (Rend) | `rend_efficient` | Efficient Rend | Rend's Stamina cost 2→1 |
| ability_l2 (Sundering Strike) | `sunder_deeper` | Deeper Sunder | Sundered's incoming-damage multiplier 1.25→1.35 |
| ability_l2 (Sundering Strike) | `sunder_lingering` | Lingering Sunder | Sundered's duration 2→3 turns |
| ability_l2 (Sundering Strike) | `sunder_efficient` | Efficient Strike | Sundering Strike's Stamina cost 3→2 |
| ability_l3 (Heroic Guard) | `guard_reinforced` | Reinforced Guard | Heroic Guard's incoming multiplier 0.75→0.65 |
| ability_l3 (Heroic Guard) | `guard_cleansing` | Cleansing Guard | Heroic Guard also cleanses 1 active debuff on cast |
| ability_l3 (Heroic Guard) | `guard_lasting` | Lasting Guard | Heroic Guard's duration 3→4 turns |
| ability_l4 (Second Wind) | `wind_deeper` | Deeper Wind | Second Wind's heal 30%→40% max HP |
| ability_l4 (Second Wind) | `wind_empowering` | Empowering Wind | Second Wind also grants Empowered ×1.15 for 1 turn |
| ability_l4 (Second Wind) | `wind_swift` | Swift Recovery | Second Wind's cooldown 4→3 turns |
| passive (Last Stand) | `stand_deeper` | Deeper Grit | Last Stand's bonus +20%→+30% |
| passive (Last Stand) | `stand_wider` | Wider Window | Last Stand's HP threshold 30%→40% |
| passive (Last Stand) | `stand_guarded` | Guarded Stand | While Last Stand is active, also −10% incoming damage |
| ultimate (Wild) | `wild_truer` | Truer Wild | Wild also grants self Empowered (×1.15 outgoing damage) for its duration (revised 2026-07-24: avoids a CombatResolver signature change per the cost/scope call) |
| ultimate (Wild) | `wild_bleeding` | Bleeding Wild | Any hit landed during Wild also applies 1 stack of Bleed |
| ultimate (Wild) | `wild_lasting` | Lasting Wild | Wild's crit bias lasts 2 spins instead of 1 |

### Vanguard (War Hammer, Crushing, Stamina)

| Row | id | Name | Effect |
|---|---|---|---|
| base_ability (Heft) | `heft_reinforced` | Reinforced Heft | Heft also converts up to 1 NEUTRAL face per reel into SUCCESS |
| base_ability (Heft) | `heft_guarding` | Guarding Heft | Heft also grants self Guarded ×0.9 for 1 turn |
| base_ability (Heft) | `heft_efficient` | Efficient Heft | Heft's Stamina cost 2→1 |
| ability_l2 (Bloodwrath) | `wrath_deeper` | Deeper Wrath | Bloodwrath's missing-HP scaling 1.0→1.2 (cap 50%→60%) |
| ability_l2 (Bloodwrath) | `wrath_lasting` | Lasting Wrath | Bloodwrath's duration 2→3 turns |
| ability_l2 (Bloodwrath) | `wrath_efficient` | Efficient Wrath | Bloodwrath's Stamina cost 3→2 |
| ability_l3 (Quake Slam) | `slam_deeper` | Deeper Slam | Quake Slam's own hit deals +15% bonus damage |
| ability_l3 (Quake Slam) | `slam_heavier` | Heavier Slam | Quake Slam applies 2 stacks of Slow at once instead of 1 |
| ability_l3 (Quake Slam) | `slam_efficient` | Efficient Slam | Quake Slam's Stamina cost 4→3 |
| ability_l4 (Mountain Stance) | `stance_deeper` | Deeper Stance | Mountain Stance's incoming multiplier 0.5→0.4 |
| ability_l4 (Mountain Stance) | `stance_thorned` | Thorned Stance | Mountain Stance also grants 15% Thorns for its duration |
| ability_l4 (Mountain Stance) | `stance_swift` | Swift Stance | Mountain Stance's cooldown 4→3 |
| passive (Bulwark) | `bulwark_deeper` | Reinforced Bulwark | Bulwark's reduction −15%→−25% |
| passive (Bulwark) | `bulwark_wider` | Wider Bulwark | Bulwark's HP threshold 50%→60% (active more often) |
| passive (Bulwark) | `bulwark_thorned` | Thorned Bulwark | While Bulwark is active, attackers also take 10% Thorns |
| ultimate (Rampage) | `rampage_deeper` | Deeper Rampage | Rampage's added reel deals +15% bonus damage |
| ultimate (Rampage) | `rampage_slowing` | Slowing Rampage | Every enemy hit during Rampage is also Slowed 1 stack |
| ultimate (Rampage) | `rampage_lasting` | Lasting Rampage | Rampage's AoE/Heft effect lasts 2 spins instead of 1 |

### Skirmisher (Twin Daggers, Slashing, Stamina)

| Row | id | Name | Effect |
|---|---|---|---|
| base_ability (Flurry) | `flurry_deeper` | Deeper Flurry | Flurry's added reel gets +10% bonus damage |
| base_ability (Flurry) | `flurry_hastening` | Hastening Flurry | Flurry also grants self Haste for 1 turn |
| base_ability (Flurry) | `flurry_efficient` | Efficient Flurry | Flurry's Stamina cost 2→1 |
| ability_l2 (Feint & Riposte) | `feint_deeper` | Deeper Feint | Feint & Riposte grants +1 riposte charge immediately |
| ability_l2 (Feint & Riposte) | `feint_lasting` | Lasting Feint | Feint & Riposte's duration 3→4 turns |
| ability_l2 (Feint & Riposte) | `feint_efficient` | Efficient Feint | Feint & Riposte's Stamina cost 3→2 |
| ability_l3 (Quickstep) | `step_deeper` | Deeper Quickstep | Quickstep's Haste magnitude +20→+30 initiative |
| ability_l3 (Quickstep) | `step_evasive` | Evasive Quickstep | Quickstep also grants 1 turn of Evasion |
| ability_l3 (Quickstep) | `step_efficient` | Efficient Quickstep | Quickstep's Stamina cost 3→2 |
| ability_l4 (Riposte Storm) | `storm_deeper` | Deeper Storm | Riposte Storm's per-charge scaling +15%→+20% |
| ability_l4 (Riposte Storm) | `storm_lasting` | Lasting Storm | Riposte Storm's Empowered lasts 2 spins instead of 1 |
| ability_l4 (Riposte Storm) | `storm_swift` | Swift Storm | Riposte Storm's cooldown 3→2 |
| passive (Opportunist) | `opportunist_deeper` | Ruthless Opportunist | Opportunist's bonus +15%→+25% |
| passive (Opportunist) | `opportunist_wider` | Wider Opportunist | Opportunist's trigger also includes a Weakened defender |
| passive (Opportunist) | `opportunist_charging` | Charging Opportunist | Landing a hit via Opportunist also grants +1 meter charge |
| ultimate (Sticky Wild) | `sticky_deeper` | Deeper Sticky Wild | Sticky Wild also grants self Empowered (×1.15 outgoing damage) for its duration (revised 2026-07-24, same reasoning as Warrior's Truer Wild) |
| ultimate (Sticky Wild) | `sticky_hastening` | Hastening Wild | Casting Sticky Wild also grants self Haste for its duration |
| ultimate (Sticky Wild) | `sticky_lasting` | Lasting Sticky Wild | Sticky Wild's crit bias lasts 3 spins instead of 2 |

### Chancer (Storm Sling, Storm, Mana)

| Row | id | Name | Effect |
|---|---|---|---|
| base_ability (Re-roll) | `reroll_deeper` | Deeper Re-roll | The re-rolled reel gets +10% bonus damage if it hits |
| base_ability (Re-roll) | `reroll_double` | Double Re-roll | Re-roll now re-rolls the two worst reels instead of one |
| base_ability (Re-roll) | `reroll_efficient` | Efficient Re-roll | Re-roll's Mana cost 4→3 |
| ability_l2 (Loaded Dice) | `dice_deeper` | Loaded Deeper | Loaded Dice's added crit face multiplier 2.0→2.25 |
| ability_l2 (Loaded Dice) | `dice_lucky` | Lucky Dice | Loaded Dice also grants +1 flat Bonus Meter charge on cast |
| ability_l2 (Loaded Dice) | `dice_efficient` | Efficient Dice | Loaded Dice's Mana cost 3→2 |
| ability_l3 (Jinx the Odds) | `jinx_deeper` | Deeper Jinx | Jinx the Odds' own hit deals +15% bonus damage |
| ability_l3 (Jinx the Odds) | `jinx_lasting` | Lasting Jinx | Jinxed's duration 2→3 turns (from this ability) |
| ability_l3 (Jinx the Odds) | `jinx_efficient` | Efficient Jinx | Jinx the Odds' Mana cost 3→2 |
| ability_l4 (Double or Nothing) | `gamble_deeper` | Deeper Gamble | Double or Nothing's Empowered ×2.0→×2.25 |
| ability_l4 (Double or Nothing) | `gamble_refunding` | Refunding Gamble | +1 extra Mana refunded per non-recoil reel |
| ability_l4 (Double or Nothing) | `gamble_swift` | Swift Gamble | Double or Nothing's cooldown 7→6 |
| passive (House Edge) | `edge_deeper` | Bigger House Edge | House Edge's charge +1→+2 |
| passive (House Edge) | `edge_lucky` | Lucky Edge | House Edge has a 25% chance to also refund 1 Mana |
| passive (House Edge) | `edge_wider` | Wider Edge | House Edge also triggers on a NEUTRAL-tier utility reel result |
| ultimate (Wildcard Gamble) | `wildcard_deeper` | Deeper Wildcard | A re-rolled crit-success multiplies ×2.25 instead of ×2.0 |
| ultimate (Wildcard Gamble) | `wildcard_safer` | Safer Wildcard | A re-rolled failure deals 25% damage instead of zero |
| ultimate (Wildcard Gamble) | `wildcard_lucky` | Lucky Wildcard | Wildcard Gamble refunds +1 flat Bonus Meter charge after resolving |

### Ranger (Hunting Bow, Piercing, Stamina)

| Row | id | Name | Effect |
|---|---|---|---|
| base_ability (Hunter's Mark) | `mark_deeper` | Deeper Mark | Hunter's Mark's duration 3→4 turns |
| base_ability (Hunter's Mark) | `mark_weakening` | Weakening Mark | Hunter's Mark also applies 1 stack of Weakened |
| base_ability (Hunter's Mark) | `mark_efficient` | Efficient Mark | Hunter's Mark's Stamina cost 3→2 |
| ability_l2 (Aimed Shot) | `aim_deeper` | Deeper Aim | Aimed Shot's bonus +30%/+60%→+40%/+70% |
| ability_l2 (Aimed Shot) | `aim_piercing` | Piercing Aim | Aimed Shot also applies 1 stack of Weakened on this spin's hit |
| ability_l2 (Aimed Shot) | `aim_efficient` | Efficient Aim | Aimed Shot's Stamina cost 3→2 |
| ability_l3 (Snare Trap) | `snare_deeper` | Deeper Snare | Snare Trap's own hit deals +15% bonus damage |
| ability_l3 (Snare Trap) | `snare_lasting` | Lasting Snare | Rooted's duration 2→3 turns (from this ability) |
| ability_l3 (Snare Trap) | `snare_efficient` | Efficient Snare | Snare Trap's Stamina cost 4→3 |
| ability_l4 (Crippling Shot) | `crippling_deeper` | Deeper Crippling | Crippling Shot's CC-exploit bonus +50%→+65% |
| ability_l4 (Crippling Shot) | `crippling_lasting` | Lasting Crippling | Weakened's duration 2→3 turns (from this ability) |
| ability_l4 (Crippling Shot) | `crippling_swift` | Swift Crippling | Crippling Shot's cooldown 3→2 |
| passive (Steady Aim) | `steady_deeper` | Deadeye | Steady Aim's bonus +10%→+20% |
| passive (Steady Aim) | `steady_wider` | Wider Aim | Steady Aim's bonus also applies vs a Weakened defender |
| passive (Steady Aim) | `steady_charging` | Charging Aim | Landing a hit via Steady Aim also grants +1 meter charge |
| ultimate (Collateral Damage) | `collateral_deeper` | Deeper Collateral | Collateral Damage's splash fraction 1/2→2/3 of primary total |
| ultimate (Collateral Damage) | `collateral_marking` | Marking Collateral | Every enemy splashed also gets Hunter's Mark applied |
| ultimate (Collateral Damage) | `collateral_lasting` | Lasting Collateral | Collateral Damage's added reel stays for 2 spins instead of 1 |

### Seer (Mystic War Staff, Mystic, Mana)

| Row | id | Name | Effect |
|---|---|---|---|
| base_ability (Select your Fate!) | `fate_deeper` | Deeper Fate | Select your Fate's added reel gets +15% bonus damage |
| base_ability (Select your Fate!) | `fate_wilder` | Wilder Fate | Select your Fate also grants +1 temporary crit face this spin |
| base_ability (Select your Fate!) | `fate_efficient` | Efficient Fate | Select your Fate's Mana cost 6→5 |
| ability_l2 (Hex) | `hex_deeper` | Deeper Hex | Cursed's DoT damage +25% (from this ability) |
| ability_l2 (Hex) | `hex_lasting` | Lasting Hex | Cursed's max stacks 3→4 (from this ability) |
| ability_l2 (Hex) | `hex_efficient` | Efficient Hex | Hex's Mana cost 4→3 |
| ability_l3 (Foresight) | `foresight_deeper` | Deeper Foresight | Foresight's shield amount 15%→20% of max Mana |
| ability_l3 (Foresight) | `foresight_lasting` | Lasting Foresight | Foresight's shield duration 3→4 turns |
| ability_l3 (Foresight) | `foresight_efficient` | Efficient Foresight | Foresight's Mana cost 4→3 |
| ability_l4 (Mana Surge) | `surge_deeper` | Deeper Surge | Mana Surge's Empowered 1.6→1.75 |
| ability_l4 (Mana Surge) | `surge_refunding` | Refunding Surge | Mana Surge refunds 25% of its own Mana cost on cast |
| ability_l4 (Mana Surge) | `surge_swift` | Swift Surge | Mana Surge's cooldown 4→3 |
| passive (Arcane Reservoir) | `reservoir_deeper` | Overflowing Reservoir | Arcane Reservoir's bonus +20%→+35% |
| passive (Arcane Reservoir) | `reservoir_regen` | Flowing Reservoir | Arcane Reservoir also grants +1 flat Mana regen per Upkeep |
| passive (Arcane Reservoir) | `reservoir_efficient` | Efficient Reservoir | All of this Seer's ability Mana costs are reduced by 1 |
| ultimate (The Big Bang) | `bigbang_deeper` | Deeper Bang | The Big Bang's heal fraction 1/6→1/5 of spin total |
| ultimate (The Big Bang) | `bigbang_curing` | Curing Bang | The Big Bang also cleanses 1 debuff from each healed ally |
| ultimate (The Big Bang) | `bigbang_shielding` | Shielding Bang | The Big Bang's overflow-shield duration +1 turn |

### Warden (Earthstave, Earth, Mana)

| Row | id | Name | Effect |
|---|---|---|---|
| base_ability (Rallying Cry) | `cry_deeper` | Deeper Cry | Rallying Cry's shield amount (both tiers) +20% bigger |
| base_ability (Rallying Cry) | `cry_lasting` | Lasting Cry | Rallying Cry's shield duration +1 turn |
| base_ability (Rallying Cry) | `cry_efficient` | Efficient Cry | Rallying Cry's Mana cost 4→3 |
| ability_l2 (Entangle) | `entangle_deeper` | Deeper Entangle | Entangle's own hit deals +15% bonus damage |
| ability_l2 (Entangle) | `entangle_lasting` | Lasting Entangle | Rooted's duration 2→3 turns (from this ability) |
| ability_l2 (Entangle) | `entangle_efficient` | Efficient Entangle | Entangle's Mana cost 4→3 |
| ability_l3 (Regrowth) | `regrowth_deeper` | Deeper Regrowth | Regrowth's heal-over-time +25% per tick |
| ability_l3 (Regrowth) | `regrowth_lasting` | Lasting Regrowth | Regrowth's max stacks 3→4 |
| ability_l3 (Regrowth) | `regrowth_efficient` | Efficient Regrowth | Regrowth's Mana cost 4→3 |
| ability_l4 (Bastion) | `bastion_deeper` | Deeper Bastion | Bastion's Thorns 20%→30% |
| ability_l4 (Bastion) | `bastion_reinforced` | Reinforced Bastion | Bastion's incoming multiplier 0.5→0.4 |
| ability_l4 (Bastion) | `bastion_swift` | Swift Bastion | Bastion's cooldown 4→3 |
| passive (Deep Roots) | `roots_deeper` | Ancient Roots | Deep Roots' DoT reduction −15%→−25% |
| passive (Deep Roots) | `roots_regen` | Flourishing Roots | Deep Roots' Upkeep regen 1/16→1/12 of max HP |
| passive (Deep Roots) | `roots_thorned` | Thorned Roots | Deep Roots also grants a passive 10% Thorns at all times |
| ultimate (Earthquake) | `quake_deeper` | Deeper Quake | Earthquake's splash fraction 1/2→2/3 of primary total |
| ultimate (Earthquake) | `quake_rooting` | Rooting Quake | Every enemy hit by Earthquake also gets Rooted applied |
| ultimate (Earthquake) | `quake_lasting` | Lasting Quake | Earthquake's crit-bias effect lasts 2 spins instead of 1 |

**Do not proceed past Task 14 to any per-class task (15-21) until the player has confirmed this
table (as-is or with changes).**

---

## Task 13: Universal Perk track (Track B) — data model, cadence, hooks

**Files:**
- Create: `combat/resources/talent_perk_def.gd`
- Create: `combat/talent_perk_library.gd`
- Modify: `combat/combatant.gd` (`talent_perks`, `universal_points_earned()`/`available()`,
  `talent_stat_bonuses()`, `pick_talent_perk()`/`unpick_talent_perk()`, `talent_flat_initiative_bonus()`,
  `talent_incoming_multiplier()`, `talent_dot_damage_multiplier()`; extend `effective_stats()`,
  `apply_stats()`, `recompute_initiative()`, `incoming_damage_multiplier()`, `dot_damage_multiplier()`)
- Test: `tests/test_universal_perks.gd` (new)

**Interfaces:**
- Produces: `TalentPerkDef` (`id`, `display_name`, `description`, `stat_key: StringName = &""`,
  `stat_amount: int = 0`), `TalentPerkLibrary.universal_perks() -> Array[TalentPerkDef]`,
  `TalentPerkLibrary.find_perk(id: StringName) -> TalentPerkDef`, `Combatant.talent_perks:
  Array[StringName]`, `Combatant.universal_points_earned() -> int`,
  `Combatant.universal_points_available() -> int`, `Combatant.pick_talent_perk(id) -> bool`,
  `Combatant.unpick_talent_perk(id) -> bool`.
- Independent of Task 14 (Ability Talents) — no shared state, may be built in either order.

- [ ] **Step 1: Write the failing test**

Create `tests/test_universal_perks.gd`:

```gdscript
extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	# Earned/available across the L2/4/6/8/10 cadence (spec 2026-07-24 §2).
	var c: Combatant = Combatant.new()
	c.level = 1
	_check(c.universal_points_earned() == 0, "L1: 0 universal points earned")
	c.level = 2
	_check(c.universal_points_earned() == 1, "L2: 1st milestone reached")
	c.level = 3
	_check(c.universal_points_earned() == 1, "L3: still 1 (odd levels grant nothing)")
	c.level = 4
	_check(c.universal_points_earned() == 2, "L4: 2nd milestone reached")
	c.level = 6
	_check(c.universal_points_earned() == 3, "L6: 3rd milestone reached")
	c.level = 8
	_check(c.universal_points_earned() == 4, "L8: 4th milestone reached")
	c.level = 10
	_check(c.universal_points_earned() == 5, "L10: all 5 milestones reached")
	_check(c.universal_points_available() == 5, "L10, none spent: 5 available")

	# One-time-pick enforcement.
	_check(c.pick_talent_perk(&"vigor_boost"), "picking an unpicked perk succeeds")
	_check(c.universal_points_available() == 4, "one point spent")
	_check(not c.pick_talent_perk(&"vigor_boost"), "picking the SAME perk again is rejected")
	_check(c.universal_points_available() == 4, "rejected pick spends nothing")
	_check(not c.pick_talent_perk(&"does_not_exist"), "picking an unknown perk id is rejected")

	# Flat stat perk applies through effective_stats().
	_check(c.effective_stats().vigor == 2, "vigor_boost grants +2 Vigor via effective_stats()")

	# Unpick refunds the point.
	_check(c.unpick_talent_perk(&"vigor_boost"), "unpicking a picked perk succeeds")
	_check(c.universal_points_available() == 5, "unpicking refunds the point")
	_check(c.effective_stats().vigor == 0, "unpicking vigor_boost removes its bonus")
	_check(not c.unpick_talent_perk(&"vigor_boost"), "unpicking an unpicked perk is rejected")

	# Can't pick past the earned total.
	var poor_c: Combatant = Combatant.new()
	poor_c.level = 2
	_check(poor_c.pick_talent_perk(&"might_boost"), "1st pick at L2 succeeds")
	_check(not poor_c.pick_talent_perk(&"finesse_boost"), "2nd pick at L2 (only 1 point earned) is rejected")

	# Bespoke (non-stat) universal perks.
	var sr: Combatant = Combatant.new()
	sr.level = 2
	sr.pick_talent_perk(&"sharp_reflexes")
	sr.recompute_initiative()
	_check(sr.current_initiative == 5, "sharp_reflexes: +5 flat Initiative")

	var ts: Combatant = Combatant.new()
	ts.level = 2
	ts.pick_talent_perk(&"thick_skin")
	_check(is_equal_approx(ts.incoming_damage_multiplier(), 0.95), "thick_skin: -5% incoming damage")

	var bh: Combatant = Combatant.new()
	bh.level = 2
	bh.pick_talent_perk(&"battle_hardened")
	_check(is_equal_approx(bh.dot_damage_multiplier(), 0.9), "battle_hardened: -10% incoming DoT damage")

	var dr_stamina: Combatant = Combatant.new()
	dr_stamina.level = 2
	dr_stamina.base_max_stamina = 5
	dr_stamina.resource_pool = ResourcePool.new()
	dr_stamina.apply_stats()
	var before_stamina: int = dr_stamina.resource_pool.max_stamina
	dr_stamina.pick_talent_perk(&"deep_reserves")
	_check(dr_stamina.resource_pool.max_stamina == before_stamina + 3, "deep_reserves: +3 max Stamina for a Stamina-rail character")

	var dr_mana: Combatant = Combatant.new()
	dr_mana.level = 2
	dr_mana.base_max_mana = 9
	dr_mana.resource_pool = ResourcePool.new()
	dr_mana.apply_stats()
	var before_mana: int = dr_mana.resource_pool.max_mana
	dr_mana.pick_talent_perk(&"deep_reserves")
	_check(dr_mana.resource_pool.max_mana == before_mana + 3, "deep_reserves: +3 max Mana for a Mana-rail character")

	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_universal_perks.gd`
Expected: FAIL / parse error — none of these members exist yet.

- [ ] **Step 3: Create `TalentPerkDef`**

Create `combat/resources/talent_perk_def.gd`:

```gdscript
class_name TalentPerkDef
extends Resource

## Track B (Universal Perks, spec 2026-07-24 §4) — one entry per perk. A flat-stat perk sets
## stat_key/stat_amount and is applied generically via Combatant.talent_stat_bonuses(); a bespoke
## perk (deep_reserves/sharp_reflexes/thick_skin/battle_hardened) leaves stat_key empty and is
## instead checked by id at its own dedicated hook (same convention as passives).
@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var stat_key: StringName = &""
@export var stat_amount: int = 0
```

- [ ] **Step 4: Create `TalentPerkLibrary`**

Create `combat/talent_perk_library.gd`:

```gdscript
class_name TalentPerkLibrary
extends RefCounted

## Code registry of the 10 Universal Perks (spec 2026-07-24 §4 — content locked, carried over
## unchanged from the original Task 12 checkpoint). Mirrors ClassLibrary/EnemyLibrary/EffectLibrary:
## returns a FRESH Array each call. All magnitudes are [ASSUMPTION] (CLAUDE.md §4).

static func universal_perks() -> Array[TalentPerkDef]:
	var list: Array[TalentPerkDef] = []
	list.append(_flat(&"might_boost", "Heavy Hands", "+2 Might", &"might", 2))
	list.append(_flat(&"finesse_boost", "Quick Hands", "+2 Finesse", &"finesse", 2))
	list.append(_flat(&"vigor_boost", "Iron Will", "+2 Vigor", &"vigor", 2))
	list.append(_flat(&"focus_boost", "Clear Mind", "+2 Focus", &"focus", 2))
	list.append(_flat(&"grit_boost", "Stalwart", "+2 Grit", &"grit", 2))
	list.append(_flat(&"luck_boost", "Lucky Charm", "+2 Luck", &"luck", 2))
	list.append(_bespoke(&"deep_reserves", "Deep Reserves", "+3 to whichever resource pool (Stamina or Mana) this character uses"))
	list.append(_bespoke(&"sharp_reflexes", "Sharp Reflexes", "+5 flat Initiative"))
	list.append(_bespoke(&"thick_skin", "Thick Skin", "-5% incoming damage, always"))
	list.append(_bespoke(&"battle_hardened", "Battle Hardened", "-10% incoming DoT damage"))
	return list

static func find_perk(id: StringName) -> TalentPerkDef:
	for p: TalentPerkDef in universal_perks():
		if p.id == id:
			return p
	return null

static func _flat(id: StringName, dname: String, desc: String, stat_key: StringName, amount: int) -> TalentPerkDef:
	var d: TalentPerkDef = TalentPerkDef.new()
	d.id = id; d.display_name = dname; d.description = desc; d.stat_key = stat_key; d.stat_amount = amount
	return d

static func _bespoke(id: StringName, dname: String, desc: String) -> TalentPerkDef:
	var d: TalentPerkDef = TalentPerkDef.new()
	d.id = id; d.display_name = dname; d.description = desc
	return d
```

- [ ] **Step 5: Wire `Combatant`**

In `combat/combatant.gd`, add near the existing `passive_ability_id` field:

```gdscript
## Track B (Universal Perks, spec 2026-07-24 §4): the ids of perks this character has picked, in
## pick order. One-time-pick per id (non-stacking) — enforced by pick_talent_perk().
var talent_perks: Array[StringName] = []

const UNIVERSAL_PERK_LEVELS: Array[int] = [2, 4, 6, 8, 10]
```

Add these new methods (near `apply_luck()`/`luck_extra_lines()`):

```gdscript
## How many Universal Perk picks this character has earned: one for each milestone level in
## UNIVERSAL_PERK_LEVELS reached (spec 2026-07-24 §2's D&D-ASI-style cadence). Derived, not stored.
func universal_points_earned() -> int:
	var n: int = 0
	for milestone: int in UNIVERSAL_PERK_LEVELS:
		if level >= milestone:
			n += 1
	return n

func universal_points_available() -> int:
	return universal_points_earned() - talent_perks.size()

## Sum of every currently-picked FLAT-STAT universal perk's stat bonus. A bespoke perk contributes
## nothing here — it's read directly by id at its own hook (talent_flat_initiative_bonus() etc.),
## the same pattern as passives.
func talent_stat_bonuses() -> Stats:
	var s: Stats = Stats.new()
	for id: StringName in talent_perks:
		var def: TalentPerkDef = TalentPerkLibrary.find_perk(id)
		if def != null and def.stat_key != &"":
			match def.stat_key:
				&"might": s.might += def.stat_amount
				&"finesse": s.finesse += def.stat_amount
				&"vigor": s.vigor += def.stat_amount
				&"focus": s.focus += def.stat_amount
				&"grit": s.grit += def.stat_amount
				&"luck": s.luck += def.stat_amount
	return s

## Picks universal perk [param id] if a point is available, the perk exists, and it hasn't already
## been picked. Returns true on success.
func pick_talent_perk(id: StringName) -> bool:
	if universal_points_available() <= 0:
		return false
	if id in talent_perks:
		return false
	if TalentPerkLibrary.find_perk(id) == null:
		return false
	talent_perks.append(id)
	apply_stats()
	recompute_initiative()
	return true

## Unpicks [param id] (town-only respec — the caller/UI gates this, not this method). Returns true
## on success, false if [param id] wasn't picked.
func unpick_talent_perk(id: StringName) -> bool:
	if id not in talent_perks:
		return false
	talent_perks.erase(id)
	apply_stats()
	recompute_initiative()
	return true

## Flat Initiative bonus from a picked sharp_reflexes perk. 0 if not picked.
func talent_flat_initiative_bonus() -> int:
	return 5 if (&"sharp_reflexes" in talent_perks) else 0

## Multiplier contribution from a picked thick_skin perk, applied to INCOMING damage.
func talent_incoming_multiplier() -> float:
	return 0.95 if (&"thick_skin" in talent_perks) else 1.0

## Multiplier contribution from a picked battle_hardened perk, applied to incoming DoT damage.
func talent_dot_damage_multiplier() -> float:
	return 0.9 if (&"battle_hardened" in talent_perks) else 1.0
```

Change `effective_stats()` (existing, near line 395) from:

```gdscript
func effective_stats() -> Stats:
	var s: Stats = Stats.new()
	if base_stats != null:
		s = s.plus(base_stats)
	for g: Gear in gear:
		if g != null:
			s = s.plus(g.stat_bonuses)
	return s
```

to:

```gdscript
func effective_stats() -> Stats:
	var s: Stats = Stats.new()
	if base_stats != null:
		s = s.plus(base_stats)
	for g: Gear in gear:
		if g != null:
			s = s.plus(g.stat_bonuses)
	s = s.plus(talent_stat_bonuses())
	return s
```

Change `recompute_initiative()` (existing, near line 662) from:

```gdscript
func recompute_initiative() -> void:
	var total: float = 0.0
	for e: Effect in active_effects:
		if e != null and e.kind == Effect.Kind.INITIATIVE_MOD:
			total += e.effective_magnitude()
	current_initiative = base_initiative + int(roundf(total))
```

to:

```gdscript
func recompute_initiative() -> void:
	var total: float = 0.0
	for e: Effect in active_effects:
		if e != null and e.kind == Effect.Kind.INITIATIVE_MOD:
			total += e.effective_magnitude()
	current_initiative = base_initiative + int(roundf(total)) + talent_flat_initiative_bonus()
```

Change `incoming_damage_multiplier()` (existing, near line 561) from:

```gdscript
func incoming_damage_multiplier() -> float:
	var total: float = 1.0
	for e: Effect in active_effects:
		if e != null and e.kind == Effect.Kind.MULTIPLIER_EDIT and e.affects_incoming:
			total *= e.effective_magnitude()
	total *= passive_incoming_multiplier()
	return total
```

to:

```gdscript
func incoming_damage_multiplier() -> float:
	var total: float = 1.0
	for e: Effect in active_effects:
		if e != null and e.kind == Effect.Kind.MULTIPLIER_EDIT and e.affects_incoming:
			total *= e.effective_magnitude()
	total *= passive_incoming_multiplier()
	total *= talent_incoming_multiplier()
	return total
```

Change `dot_damage_multiplier()` (existing, near line 571) from:

```gdscript
func dot_damage_multiplier() -> float:
	var base: float = clampf(1.0 - effective_stats().vigor * VIGOR_DOT_RESIST_PER_POINT, VIGOR_DOT_RESIST_FLOOR, 1.0)
	return base * passive_dot_damage_multiplier()
```

to:

```gdscript
func dot_damage_multiplier() -> float:
	var base: float = clampf(1.0 - effective_stats().vigor * VIGOR_DOT_RESIST_PER_POINT, VIGOR_DOT_RESIST_FLOOR, 1.0)
	return base * passive_dot_damage_multiplier() * talent_dot_damage_multiplier()
```

In `apply_stats()` (existing, near line 468), change the resource-pool block from:

```gdscript
	if resource_pool != null:
		resource_pool.max_stamina = (base_max_stamina + s.focus) if base_max_stamina > 0 else 0
		resource_pool.stamina = mini(resource_pool.stamina, resource_pool.max_stamina)
		resource_pool.max_mana = ceili((base_max_mana + s.focus) * passive_max_mana_multiplier()) if base_max_mana > 0 else 0
		resource_pool.mana = mini(resource_pool.mana, resource_pool.max_mana)
```

to:

```gdscript
	if resource_pool != null:
		var deep_reserves_bonus: int = 3 if (&"deep_reserves" in talent_perks) else 0
		resource_pool.max_stamina = (base_max_stamina + s.focus + deep_reserves_bonus) if base_max_stamina > 0 else 0
		resource_pool.stamina = mini(resource_pool.stamina, resource_pool.max_stamina)
		resource_pool.max_mana = (ceili((base_max_mana + s.focus) * passive_max_mana_multiplier()) + deep_reserves_bonus) if base_max_mana > 0 else 0
		resource_pool.mana = mini(resource_pool.mana, resource_pool.max_mana)
```

- [ ] **Step 6: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_universal_perks.gd`
Expected: all lines print `ok `.

- [ ] **Step 7: Run the full suite**

Run every file under `tests/`. `effective_stats()`/`recompute_initiative()`/
`incoming_damage_multiplier()`/`dot_damage_multiplier()`/`apply_stats()` are all widely shared —
every pre-existing `Combatant` has an empty `talent_perks`, so every new term evaluates to its
neutral default (1.0 multiplier, 0 bonus) for anyone who hasn't picked a perk. Confirm only the 3
known pre-existing failures remain (see Global Constraints).

- [ ] **Step 8: Commit**

```bash
git add combat/resources/talent_perk_def.gd combat/talent_perk_library.gd combat/combatant.gd tests/test_universal_perks.gd
git commit -m "feat(talents): Universal Perk track — 10 perks, L2/4/6/8/10 cadence"
```

---

## Task 14: Ability Talent framework (Track A) — data model, row-unlock mapping, no content yet

**Files:**
- Create: `combat/resources/ability_talent_option.gd`
- Create: `combat/ability_talent_library.gd`
- Modify: `combat/resources/character_class.gd` (new `class_id` field)
- Modify: `combat/class_library.gd` (`c.class_id = id` in all 7 `match` branches; `build_combatant()`
  copy — see Step 4)
- Modify: `combat/combatant.gd` (`class_id`, `ability_talent_picks`, `ability_talent_row_unlock_level()`,
  `ability_talent_row_unlocked()`, `has_ability_talent()`, `pick_ability_talent()`,
  `unpick_ability_talent()`)
- Test: `tests/test_ability_talents_framework.gd` (new)

**Interfaces:**
- Produces: `AbilityTalentOption` (`id`, `display_name`, `description`), `AbilityTalentLibrary
  .options_for(class_id: StringName, row_id: StringName) -> Array[AbilityTalentOption]` (returns `[]`
  for any class until Tasks 15-21 populate it — a genuinely empty, not placeholder, state, mirroring
  how Task 3's passive scaffolding preceded Tasks 5-11's real content), `Combatant.class_id:
  StringName`, `Combatant.ability_talent_picks: Dictionary` (row_id → option_id),
  `Combatant.ability_talent_row_unlock_level(row_id) -> int`, `Combatant
  .ability_talent_row_unlocked(row_id) -> bool`, `Combatant.has_ability_talent(option_id) -> bool`,
  `Combatant.pick_ability_talent(row_id, option_id) -> bool`, `Combatant
  .unpick_ability_talent(row_id) -> bool`.
- Consumed by: Tasks 15-21 (per-class content, using `has_ability_talent(&"<option_id>")` checks at
  each ability's existing implementation site) and Task 22 (`TalentMenuPanel`).

- [ ] **Step 1: Write the failing test**

Create `tests/test_ability_talents_framework.gd`:

```gdscript
extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	# Row-unlock level mapping (spec 2026-07-24 §2's fixed table).
	var c: Combatant = Combatant.new()
	c.class_id = &"warrior"
	_check(c.ability_talent_row_unlock_level(&"base_ability") == 5, "base_ability unlocks at L5")
	_check(c.ability_talent_row_unlock_level(&"ability_l2") == 6, "ability_l2 row unlocks at L6")
	_check(c.ability_talent_row_unlock_level(&"ability_l3") == 7, "ability_l3 row unlocks at L7")
	_check(c.ability_talent_row_unlock_level(&"ability_l4") == 8, "ability_l4 row unlocks at L8")
	_check(c.ability_talent_row_unlock_level(&"passive") == 9, "passive row unlocks at L9")
	_check(c.ability_talent_row_unlock_level(&"ultimate") == 10, "ultimate row unlocks at L10")

	c.level = 4
	_check(not c.ability_talent_row_unlocked(&"base_ability"), "base_ability row locked below L5")
	c.level = 5
	_check(c.ability_talent_row_unlocked(&"base_ability"), "base_ability row unlocked at L5")
	_check(not c.ability_talent_row_unlocked(&"ability_l2"), "ability_l2 row still locked at L5")

	# Picking is rejected before the row unlocks, and rejected for a bogus option id.
	_check(not c.pick_ability_talent(&"ability_l2", &"anything"), "picking a still-locked row is rejected")
	c.level = 10  # every row unlocked now, but Task 14 seeds no real content yet — every options_for() is empty
	_check(not c.pick_ability_talent(&"base_ability", &"not_a_real_option"), "picking an option not in that row's list is rejected")
	_check(not c.has_ability_talent(&"not_a_real_option"), "has_ability_talent() is false for anything unpicked")

	# ability_talent_picks caps at 1 pick per row and is independently trackable per row — proven with
	# a synthetic option registered directly on the Dictionary (bypassing pick_ability_talent's
	# options_for() validation, since Task 14 seeds no real per-class content) to prove the STORAGE
	# shape works before Tasks 15-21 populate real, validatable options.
	c.ability_talent_picks[&"base_ability"] = &"synthetic_option"
	_check(c.ability_talent_picks.get(&"base_ability", &"") == &"synthetic_option", "a row's pick is stored under its own row_id key")
	_check(not c.ability_talent_picks.has(&"ability_l2"), "an unpicked row has no key at all")

	var uc: CharacterClass = ClassLibrary.make(&"warrior")
	_check(uc.class_id == &"warrior", "Warrior's CharacterClass carries class_id")
	var pc: Combatant = uc.build_combatant(true)
	_check(pc.class_id == &"warrior", "build_combatant() copies class_id")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_framework.gd`
Expected: FAIL / parse error — none of these members exist yet.

- [ ] **Step 3: Create `AbilityTalentOption` and `AbilityTalentLibrary`**

Create `combat/resources/ability_talent_option.gd`:

```gdscript
class_name AbilityTalentOption
extends Resource

## Track A (Ability Talents, spec 2026-07-24 §3) — one of a row's 3 options. Kept as its own
## resource (not reusing TalentPerkDef) since an ability-scoped option's effect is read at a
## specific bespoke hook (a per-class Combatant method), never a generic stat field.
@export var id: StringName = &""
## Which of the 6 fixed row ids (AbilityTalentLibrary.ROW_IDS) this option belongs to — set by
## whichever options_for() branch constructs it. Lets a caller (e.g. TalentMenuPanel, or a test)
## round-trip an option back to its row without a second lookup.
@export var row_id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
```

Create `combat/ability_talent_library.gd`:

```gdscript
class_name AbilityTalentLibrary
extends RefCounted

## Code registry of Track A's 126 options (spec 2026-07-24 §3/§5 — 6 rows × 3 options × 7 classes).
## Mirrors ClassLibrary/TalentPerkLibrary: returns a FRESH Array each call. Empty per class until
## Tasks 15-21 populate real content — NOT a placeholder, a genuinely correct empty state (mirrors
## Task 3's passive scaffolding preceding Tasks 5-11's real per-class content).
const ROW_IDS: Array[StringName] = [&"base_ability", &"ability_l2", &"ability_l3", &"ability_l4", &"passive", &"ultimate"]

static func options_for(class_id: StringName, row_id: StringName) -> Array[AbilityTalentOption]:
	match class_id:
		_:
			return []

static func _opt(id: StringName, dname: String, desc: String) -> AbilityTalentOption:
	var o: AbilityTalentOption = AbilityTalentOption.new()
	o.id = id; o.display_name = dname; o.description = desc
	return o
```

- [ ] **Step 4: Add `class_id` to `CharacterClass` and wire `ClassLibrary`/`Combatant`**

In `combat/resources/character_class.gd`, add alongside `passive_ability_id`:

```gdscript
## Which of ClassLibrary.IDS this class is (e.g. &"warrior") — needed by AbilityTalentLibrary to
## look up this class's own 18 Ability Talent options. Copied onto Combatant.class_id by
## build_combatant() the same way passive_ability_id already is.
@export var class_id: StringName = &""
```

In `combat/resources/character_class.gd`'s `build_combatant()`, add right after `c.passive_ability_id = passive_ability_id`:

```gdscript
	c.class_id = class_id
```

In `combat/class_library.gd`'s `make()`, add `c.class_id = id` as the FIRST line inside each of the
7 `match` branches' `var c: CharacterClass = CharacterClass.new()` block — e.g. for Warrior:

```gdscript
		&"warrior":
			# Balanced bruiser (the canonical Martin). Base ability Rend → stacking BLEED (§4B).
			var c: CharacterClass = CharacterClass.new()
			c.class_id = &"warrior"
			c.display_name = "Martin (Mouse)"; c.species = "Mouse"
```

(and the equivalent one-line addition — `c.class_id = &"vanguard"` / `&"skirmisher"` / `&"chancer"` /
`&"ranger"` / `&"seer"` / `&"warden"` — right after each of the other 6 branches'
`var c: CharacterClass = CharacterClass.new()` line, matching each branch's own existing `match id:`
value exactly).

In `combat/combatant.gd`, add alongside `passive_ability_id`:

```gdscript
## Which class this combatant is (mirrors CharacterClass.class_id) — used to look up this
## combatant's own Ability Talent options via AbilityTalentLibrary.options_for(). Empty for enemies
## (they don't have a talent tree).
var class_id: StringName = &""

## Track A (Ability Talents, spec 2026-07-24 §3): row_id -> the single option_id picked in that
## row. An absent key means no pick yet in that row (cap of 1 pick/row, enforced by
## pick_ability_talent()).
var ability_talent_picks: Dictionary = {}
```

Add these new methods (near the Universal Perk methods from Task 13):

```gdscript
## The fixed level at which [param row_id] unlocks (spec 2026-07-24 §2's table). -1 for an unknown
## row_id (should never happen with the 6 fixed AbilityTalentLibrary.ROW_IDS values).
func ability_talent_row_unlock_level(row_id: StringName) -> int:
	match row_id:
		&"base_ability": return 5
		&"ability_l2": return 6
		&"ability_l3": return 7
		&"ability_l4": return 8
		&"passive": return 9
		&"ultimate": return 10
		_: return -1

func ability_talent_row_unlocked(row_id: StringName) -> bool:
	return level >= ability_talent_row_unlock_level(row_id)

## True if [param option_id] is the one currently picked in whichever row it belongs to (a linear
## scan of the picks Dictionary's values — at most 6 entries, so this stays cheap).
func has_ability_talent(option_id: StringName) -> bool:
	return option_id in ability_talent_picks.values()

## Picks [param option_id] for [param row_id] if: the row is unlocked, the row has no pick yet (cap
## of 1/row), and option_id is genuinely one of that row's 3 valid options for this combatant's
## class. Returns true on success.
func pick_ability_talent(row_id: StringName, option_id: StringName) -> bool:
	if not ability_talent_row_unlocked(row_id):
		return false
	if ability_talent_picks.has(row_id):
		return false
	var valid: Array[AbilityTalentOption] = AbilityTalentLibrary.options_for(class_id, row_id)
	var found: bool = false
	for opt: AbilityTalentOption in valid:
		if opt.id == option_id:
			found = true
			break
	if not found:
		return false
	ability_talent_picks[row_id] = option_id
	return true

## Clears [param row_id]'s pick (town-only respec — the caller/UI gates this). Returns true on
## success, false if that row had no pick.
func unpick_ability_talent(row_id: StringName) -> bool:
	if not ability_talent_picks.has(row_id):
		return false
	ability_talent_picks.erase(row_id)
	return true

## Flat Stamina/Mana cost DISCOUNT (negative or zero) this combatant's Ability Talents grant to
## casting [param ability_id] (an "Efficient X" option). 0 for any (class_id, ability_id) with no
## such talent. Extended per-class in Tasks 15-21; consumed by MainPhasePlan.commit() at every
## ability-cost call site (Step 4 below).
func ability_talent_cost_delta(ability_id: StringName) -> int:
	match class_id:
		_:
			return 0

## Flat cooldown-turn DISCOUNT (negative or zero) this combatant's Ability Talents grant to
## [param ability_id] (a "Swift X" option, only meaningful on the 7 cooldown-bearing L4 extras). 0
## for any (class_id, ability_id) with no such talent. Extended per-class in Tasks 15-21; consumed
## by MainPhasePlan.commit()'s cooldown-start call (Step 4 below).
func ability_talent_cooldown_delta(ability_id: StringName) -> int:
	match class_id:
		_:
			return 0

## Applies this attacker's own Ability Talent adjustments to a freshly-made rider Effect (an id
## returned by EffectLibrary.make(rider_id)) before it's attached to [param target] — covers
## "Lasting X"/"Heavier X"/rider-magnitude-bump options. Mutates [param effect] in place and/or
## attaches an extra effect to [param target] directly. No-op for any (class_id, rider_id) pair with
## no adjustment. Extended per-class in Tasks 15-21; called from the shared rider-attach site in
## combat.gd (Step 5 below) — every rider-carrying ability across every class flows through this ONE
## site, so this dispatch (keyed by class_id, not by a per-ability id) is how a specific class's
## specific ability's rider gets adjusted without the other classes' rider-carrying abilities (which
## may reuse the same rider_id, e.g. &"rooted" is used by both Ranger's Snare Trap and Warden's
## Entangle) being affected.
func apply_rider_talent_adjustments(rider_id: StringName, effect: Effect, target: Combatant) -> void:
	match class_id:
		_:
			pass

## Flat bonus-damage PERCENTAGE (0.0 = none) this attacker's Ability Talents grant when their
## [param rider_id] rider-carrying reel lands a hit (a "Deeper X" option on a rider-attack ability,
## e.g. Quake Slam/Jinx the Odds/Snare Trap/Entangle) — dealt as an immediate separate follow-up
## hit of the same damage type, mirroring the existing Crippling Shot bonus_vs_cc precedent
## (combat.gd). 0.0 for any (class_id, rider_id) pair with no such talent. Extended per-class in
## Tasks 15-21; called from the same rider-attack damage site as bonus_vs_cc (Step 5 below).
func rider_talent_bonus_damage_pct(rider_id: StringName) -> float:
	match class_id:
		_:
			return 0.0
```

- [ ] **Step 5: Wire the shared call sites (`main_phase_plan.gd` cost/cooldown, `combat.gd` rider-attach)**

These are the ONLY 3 shared sites Tasks 15-21 need — each per-class task adds match arms to the 4
dispatch methods from Step 4 above, but never touches these call sites again.

In `combat/main_phase_plan.gd`'s `commit()` (existing, near line 378), change the base-ability block
from:

```gdscript
func commit() -> void:
	# When Heft is free-via-Rampage, skip the paid ability commit — fire_rampage applies the Heft itself.
	if ability_staged and not ability_is_free():
		match ability_id:
			&"flurry":
				combatant.try_splice_reel(combatant.weapon_type(), combatant.weapon_effective_base_damage(), ability_cost, reel_cap)
			&"rend":
				combatant.try_rend_reel(combatant.weapon_type(), ability_cost, reel_cap)
			&"heft":
				combatant.apply_heft(ability_cost)
			&"reroll":
				combatant.stage_reroll(ability_cost)
			&"hunters_mark":
				combatant.stage_hunters_mark(ability_cost)  # orchestrator attaches the mark to the defender
			&"select_fate":
				combatant.apply_select_fate(selected_fate_type, ability_cost)  # +1 reel, retype loadout (Seer)
			&"rallying_cry":
				combatant.apply_rallying_cry(ability_cost, reel_cap)  # +1 utility reel; orchestrator shields the party
			&"warden_support_heal":
				combatant.stage_warden_support_heal(ability_cost)
			&"warden_support_curse":
				combatant.stage_warden_support_curse(ability_cost)
```

to (only the added `talent_cost` local + its use in every call — the `match ability_id:` structure
and every branch's target method are unchanged):

```gdscript
func commit() -> void:
	# When Heft is free-via-Rampage, skip the paid ability commit — fire_rampage applies the Heft itself.
	var talent_cost: int = ability_cost + combatant.ability_talent_cost_delta(ability_id)
	if ability_staged and not ability_is_free():
		match ability_id:
			&"flurry":
				combatant.try_splice_reel(combatant.weapon_type(), combatant.weapon_effective_base_damage(), talent_cost, reel_cap)
			&"rend":
				combatant.try_rend_reel(combatant.weapon_type(), talent_cost, reel_cap)
			&"heft":
				combatant.apply_heft(talent_cost)
			&"reroll":
				combatant.stage_reroll(talent_cost)
			&"hunters_mark":
				combatant.stage_hunters_mark(talent_cost)  # orchestrator attaches the mark to the defender
			&"select_fate":
				combatant.apply_select_fate(selected_fate_type, talent_cost)  # +1 reel, retype loadout (Seer)
			&"rallying_cry":
				combatant.apply_rallying_cry(talent_cost, reel_cap)  # +1 utility reel; orchestrator shields the party
			&"warden_support_heal":
				combatant.stage_warden_support_heal(talent_cost)
			&"warden_support_curse":
				combatant.stage_warden_support_curse(talent_cost)
```

Change the extra-ability block (existing, near line 400) from:

```gdscript
	if staged_extra_ability_id != &"":
		var def: AbilityDef = combatant.find_extra_ability(staged_extra_ability_id)
		match staged_extra_ability_id:
			&"sundering_strike":
				combatant.try_sundering_strike(combatant.weapon_type(), def.cost, reel_cap)
			&"quake_slam":
				combatant.try_quake_slam(combatant.weapon_type(), def.cost, reel_cap)
			&"jinx_the_odds":
				combatant.try_jinx_the_odds(combatant.weapon_type(), def.cost, reel_cap)
			&"snare_trap":
				combatant.try_snare_trap(combatant.weapon_type(), def.cost, reel_cap)
			&"crippling_shot":
				combatant.try_crippling_shot(combatant.weapon_type(), def.cost, reel_cap)
			&"hex":
				combatant.try_hex(combatant.weapon_type(), def.cost, reel_cap)
			&"entangle":
				combatant.try_entangle(combatant.weapon_type(), def.cost, reel_cap)
			&"aimed_shot":
				combatant.stage_aimed_shot(def.cost)  # orchestrator attaches Empowered (bonus vs a Marked target)
			&"foresight":
				combatant.stage_foresight(def.cost)  # orchestrator picks lowest-HP% ally + shields them
			&"regrowth":
				combatant.stage_regrowth(def.cost)  # orchestrator picks lowest-HP% ally + grants Regen
			&"heroic_guard":
				combatant.apply_heroic_guard(def.cost)
			&"second_wind":
				combatant.apply_second_wind(def.cost)
			&"bloodwrath":
				combatant.apply_bloodwrath(def.cost)
			&"mountain_stance":
				combatant.apply_mountain_stance(def.cost)
			&"bastion":
				combatant.apply_bastion(def.cost)
			&"feint_riposte":
				combatant.apply_feint_riposte(def.cost)
			&"quickstep":
				combatant.apply_quickstep(def.cost)
			&"riposte_storm":
				combatant.fire_riposte_storm(def.cost)
			&"loaded_dice":
				combatant.apply_loaded_dice(def.cost)
			&"mana_surge":
				combatant.apply_mana_surge(combatant.weapon_type(), def.cost, reel_cap)
			&"double_or_nothing":
				combatant.fire_double_or_nothing(combatant.weapon_type(), reel_cap)
		if def != null and def.cooldown_turns > 0:
			combatant.start_cooldown(staged_extra_ability_id, def.cooldown_turns)
```

to (only `talent_cost`/the cooldown-delta line added — every match arm's target method call and the
`match staged_extra_ability_id:` structure are unchanged):

```gdscript
	if staged_extra_ability_id != &"":
		var def: AbilityDef = combatant.find_extra_ability(staged_extra_ability_id)
		var talent_cost: int = def.cost + combatant.ability_talent_cost_delta(staged_extra_ability_id)
		match staged_extra_ability_id:
			&"sundering_strike":
				combatant.try_sundering_strike(combatant.weapon_type(), talent_cost, reel_cap)
			&"quake_slam":
				combatant.try_quake_slam(combatant.weapon_type(), talent_cost, reel_cap)
			&"jinx_the_odds":
				combatant.try_jinx_the_odds(combatant.weapon_type(), talent_cost, reel_cap)
			&"snare_trap":
				combatant.try_snare_trap(combatant.weapon_type(), talent_cost, reel_cap)
			&"crippling_shot":
				combatant.try_crippling_shot(combatant.weapon_type(), talent_cost, reel_cap)
			&"hex":
				combatant.try_hex(combatant.weapon_type(), talent_cost, reel_cap)
			&"entangle":
				combatant.try_entangle(combatant.weapon_type(), talent_cost, reel_cap)
			&"aimed_shot":
				combatant.stage_aimed_shot(talent_cost)  # orchestrator attaches Empowered (bonus vs a Marked target)
			&"foresight":
				combatant.stage_foresight(talent_cost)  # orchestrator picks lowest-HP% ally + shields them
			&"regrowth":
				combatant.stage_regrowth(talent_cost)  # orchestrator picks lowest-HP% ally + grants Regen
			&"heroic_guard":
				combatant.apply_heroic_guard(talent_cost)
			&"second_wind":
				combatant.apply_second_wind(talent_cost)
			&"bloodwrath":
				combatant.apply_bloodwrath(talent_cost)
			&"mountain_stance":
				combatant.apply_mountain_stance(talent_cost)
			&"bastion":
				combatant.apply_bastion(talent_cost)
			&"feint_riposte":
				combatant.apply_feint_riposte(talent_cost)
			&"quickstep":
				combatant.apply_quickstep(talent_cost)
			&"riposte_storm":
				combatant.fire_riposte_storm(talent_cost)
			&"loaded_dice":
				combatant.apply_loaded_dice(talent_cost)
			&"mana_surge":
				combatant.apply_mana_surge(combatant.weapon_type(), talent_cost, reel_cap)
			&"double_or_nothing":
				combatant.fire_double_or_nothing(combatant.weapon_type(), reel_cap)
		if def != null and def.cooldown_turns > 0:
			var talent_cd: int = maxi(1, def.cooldown_turns + combatant.ability_talent_cooldown_delta(staged_extra_ability_id))
			combatant.start_cooldown(staged_extra_ability_id, talent_cd)
```

Also change `preview_resource()` (existing, near line 329) from:

```gdscript
func preview_resource() -> int:
	if combatant == null or combatant.resource_pool == null:
		return 0
	var res: StringName = combatant.ability_resource
	var cur: int = combatant.resource_pool.mana if res == &"mana" else combatant.resource_pool.stamina
	return (cur - ability_cost) if (ability_staged and not ability_is_free()) else cur
```

to:

```gdscript
func preview_resource() -> int:
	if combatant == null or combatant.resource_pool == null:
		return 0
	var res: StringName = combatant.ability_resource
	var cur: int = combatant.resource_pool.mana if res == &"mana" else combatant.resource_pool.stamina
	var talent_cost: int = ability_cost + combatant.ability_talent_cost_delta(ability_id)
	return (cur - talent_cost) if (ability_staged and not ability_is_free()) else cur
```

In `combat/combat.gd`'s rider-attach block (existing, near line 1904), change:

```gdscript
	if attack.rider_effect_id != &"":
		for t: Combatant in targets:
			var rider: Effect = EffectLibrary.make(attack.rider_effect_id)
			if rider != null:
				if rider.kind == Effect.Kind.DAMAGE_OVER_TIME and _attacker.weapon != null:
					rider.dot_base_damage = _attacker.weapon_effective_base_damage()
				t.attach_effect(rider)
				_log("  %s is afflicted with %s (%d turns)." % [t.display_name, String(rider.id).to_upper(), rider.duration])
				(_panels[t] as CombatantPanel).refresh_status()
				(_panels[t] as CombatantPanel).refresh_initiative()
		_turn_order_bar.set_order(_turn_manager.get_turn_order())
```

to:

```gdscript
	if attack.rider_effect_id != &"":
		for t: Combatant in targets:
			var rider: Effect = EffectLibrary.make(attack.rider_effect_id)
			if rider != null:
				if rider.kind == Effect.Kind.DAMAGE_OVER_TIME and _attacker.weapon != null:
					rider.dot_base_damage = _attacker.weapon_effective_base_damage()
				_attacker.apply_rider_talent_adjustments(attack.rider_effect_id, rider, t)
				t.attach_effect(rider)
				_log("  %s is afflicted with %s (%d turns)." % [t.display_name, String(rider.id).to_upper(), rider.duration])
				(_panels[t] as CombatantPanel).refresh_status()
				(_panels[t] as CombatantPanel).refresh_initiative()
		_turn_order_bar.set_order(_turn_manager.get_turn_order())
```

And change the bonus_vs_cc block (existing, near line 1871) from:

```gdscript
			if attack.source_reel != null and attack.source_reel.bonus_vs_cc:
				# stunned_this_turn is only ever true DURING the bearer's own turn (set by evaluate_stun
				# at their turn start, cleared by their own on_end) — checked here on the RANGER's turn,
				# against another combatant, it is always false by construction and the bonus would never
				# fire for a stunned target (playtest audit 2026-07-02). stunned_last_turn is the field
				# that's actually observable from outside the bearer's own turn: true from the moment
				# their stunned turn ends until their own NEXT on_end, which is exactly the window a
				# called shot like this should be able to exploit.
				if t.has_effect(&"slow") or t.has_effect(&"rooted") or t.stunned_last_turn:
					var bonus: int = ceili(attack.final_damage * 0.5)
					t.take_damage(bonus)
					_log("  🎯 Crippling Shot exploits %s's condition for %d bonus damage." % [t.display_name, bonus])
```

to (unchanged, plus one new block immediately after it, still inside the same `for t: Combatant in
targets:` loop):

```gdscript
			if attack.source_reel != null and attack.source_reel.bonus_vs_cc:
				# stunned_this_turn is only ever true DURING the bearer's own turn (set by evaluate_stun
				# at their turn start, cleared by their own on_end) — checked here on the RANGER's turn,
				# against another combatant, it is always false by construction and the bonus would never
				# fire for a stunned target (playtest audit 2026-07-02). stunned_last_turn is the field
				# that's actually observable from outside the bearer's own turn: true from the moment
				# their stunned turn ends until their own NEXT on_end, which is exactly the window a
				# called shot like this should be able to exploit.
				if t.has_effect(&"slow") or t.has_effect(&"rooted") or t.stunned_last_turn:
					var bonus: int = ceili(attack.final_damage * 0.5)
					t.take_damage(bonus)
					_log("  🎯 Crippling Shot exploits %s's condition for %d bonus damage." % [t.display_name, bonus])
			if attack.rider_effect_id != &"":
				var talent_bonus_pct: float = _attacker.rider_talent_bonus_damage_pct(attack.rider_effect_id)
				if talent_bonus_pct > 0.0:
					var talent_bonus: int = ceili(attack.final_damage * talent_bonus_pct)
					t.take_damage(talent_bonus)
					_log("  ✦ %s's talent adds %d bonus damage." % [_attacker.display_name, talent_bonus])
```

- [ ] **Step 6: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_framework.gd`
Expected: all lines print `ok `.

- [ ] **Step 7: Run the full suite**

Run every file under `tests/`. `class_id`/`ability_talent_picks` are new fields defaulting to
`&""`/`{}`, and every new dispatch method returns its neutral default (0 / 0.0 / no-op) for every
pre-existing `Combatant` — confirm only the 3 known pre-existing failures remain (see Global
Constraints). This is the widest-blast-radius task in this plan (touches `main_phase_plan.gd`'s
commit path and `combat.gd`'s rider-attach path, both used by every class) — give this run extra
scrutiny.

- [ ] **Step 8: Commit**

```bash
git add combat/resources/ability_talent_option.gd combat/ability_talent_library.gd combat/resources/character_class.gd combat/class_library.gd combat/combatant.gd combat/main_phase_plan.gd combat/combat.gd tests/test_ability_talents_framework.gd
git commit -m "feat(talents): Ability Talent framework — row-unlock mapping, shared cost/cooldown/rider hooks"
```

---

## Task 15: Warrior Ability Talents (18 options)

> Revised 2026-07-24 from the original draft: the ultimate row's `wild_truer` option originally
> called for a real crit-bias-chance parameter threaded through `CombatResolver.resolve_combat_phase()`
> /`_resolve_single()` — a genuine cross-cutting engine change. Per the player's own cost/scope call
> (simplify rather than keep deep engine changes), `wild_truer` is reworded to "Wild also grants self
> Empowered (×1.15 outgoing damage) for its duration" — implemented entirely inside the Warrior's own
> `fire_sticky_wild()` method, no shared-function signature change needed. Task 12's checkpoint table
> already reflects this reworded effect.

**Files:**
- Modify: `combat/ability_talent_library.gd` (fills in the `&"warrior":` branch of `options_for()`)
- Modify: `combat/combatant.gd` (`apply_heroic_guard()`, `apply_second_wind()`,
  `passive_outgoing_multiplier()`, `passive_incoming_multiplier()`, `fire_sticky_wild()`, and the 3
  shared dispatch methods that need a `&"warrior":` arm)
- Modify: `combat/combat.gd` (`_apply_attack()` gains the `wild_bleeding` on-hit check)
- Modify: `combat/main_phase_plan.gd` (`commit()`'s `&"wild":` arm gains the `wild_lasting` spin-count branch)
- Test: `tests/test_ability_talents_warrior.gd` (new)

**Interfaces:**
- Consumes: Task 14's `Combatant.class_id` / `ability_talent_picks` / `has_ability_talent()` /
  `pick_ability_talent()` / `ability_talent_cost_delta()` / `ability_talent_cooldown_delta()` /
  `apply_rider_talent_adjustments()` scaffolds, and `AbilityTalentLibrary.options_for()`'s empty
  `&"warrior":` stub. Also consumes the existing `EffectLibrary`/`MainPhasePlan` infrastructure:
  `try_rend_reel`, `try_sundering_strike`, `apply_heroic_guard`, `apply_second_wind`,
  `fire_sticky_wild`, `cleanse()`, and the `&"bleed"`/`&"sundered"`/`&"guarded"`/`&"taunt"`/
  `&"empowered"` `EffectLibrary` entries.
- Produces: 18 populated `AbilityTalentOption` entries for Warrior across all 6 rows; talent-aware
  Rend/Sundering Strike/Heroic Guard/Second Wind/Last Stand/Wild behavior. `rider_talent_bonus_damage_pct()`
  gets no Warrior arm (none of these 18 options are that shape) — its Task-14 stub stays untouched
  for this class.

- [ ] **Step 1: Write the failing test**

Create `tests/test_ability_talents_warrior.gd`:

```gdscript
extends SceneTree

# Headless test: the Warrior's 18 Ability Talent options (Task 15) — one row of 3 mutually-
# exclusive picks per Warrior ability (Rend / Sundering Strike / Heroic Guard / Second Wind /
# Last Stand / Wild). Exercises AbilityTalentLibrary.options_for(&"warrior", row_id),
# pick_ability_talent()/has_ability_talent(), the cost/cooldown-delta dispatch methods, and
# apply_rider_talent_adjustments() for the Bleed/Sundered riders.
#
# Bleeding Wild's ACTUAL on-hit attach lives in combat.gd's _apply_attack() — orchestrator-level,
# requires a running Combat scene — and is NOT headlessly tested here, consistent with this
# codebase's own documented precedent (tests/test_crippling_shot.gd's header comment on its
# bonus_vs_cc check). This test instead proves the precondition state combat.gd's wiring reads.
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_warrior.gd

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _mk_warrior() -> Combatant:
	var c: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	c.level = Combatant.MAX_LEVEL  # unlocks every talent row (5/6/7/8/9/10)
	c.resource_pool.stamina = 20
	return c

func _test_options_for_shape() -> void:
	var rows: Array[StringName] = [&"base_ability", &"ability_l2", &"ability_l3", &"ability_l4", &"passive", &"ultimate"]
	var all_ids: Array[StringName] = [
		&"rend_deeper_cut", &"rend_lasting_wound", &"rend_efficient",
		&"sunder_deeper", &"sunder_lingering", &"sunder_efficient",
		&"guard_reinforced", &"guard_cleansing", &"guard_lasting",
		&"wind_deeper", &"wind_empowering", &"wind_swift",
		&"stand_deeper", &"stand_wider", &"stand_guarded",
		&"wild_truer", &"wild_bleeding", &"wild_lasting",
	]
	var seen: Array[StringName] = []
	for row: StringName in rows:
		var opts: Array[AbilityTalentOption] = AbilityTalentLibrary.options_for(&"warrior", row)
		_check(opts.size() == 3, "Warrior row %s has exactly 3 options (got %d)" % [row, opts.size()])
		for o: AbilityTalentOption in opts:
			_check(o.row_id == row, "option %s reports its own row_id (%s)" % [o.id, row])
			_check(o.display_name != "" and o.description != "", "option %s has a non-empty display_name/description" % o.id)
			seen.append(o.id)
	for id: StringName in all_ids:
		_check(id in seen, "option %s is present in AbilityTalentLibrary.options_for(&warrior, ...)" % id)

func _test_rend_row() -> void:
	var c: Combatant = _mk_warrior()
	_check(c.ability_talent_cost_delta(&"rend") == 0, "no Rend cost delta with nothing picked")
	_check(c.pick_ability_talent(&"base_ability", &"rend_efficient"), "picks rend_efficient")
	_check(c.has_ability_talent(&"rend_efficient"), "has_ability_talent sees rend_efficient")
	_check(c.ability_talent_cost_delta(&"rend") == -1, "rend_efficient: Rend costs 1 less Stamina")

	var c2: Combatant = _mk_warrior()
	_check(c2.pick_ability_talent(&"base_ability", &"rend_deeper_cut"), "picks rend_deeper_cut")
	var bleed: Effect = EffectLibrary.make(&"bleed")
	var base_fractions: Array = bleed.dot_fractions.duplicate()
	c2.apply_rider_talent_adjustments(&"bleed", bleed, c2)
	for i: int in range(base_fractions.size()):
		_check(is_equal_approx(bleed.dot_fractions[i], base_fractions[i] * 1.25),
			"rend_deeper_cut: Bleed fraction %d is +25%% (got %.4f, want %.4f)" % [i, bleed.dot_fractions[i], base_fractions[i] * 1.25])
	_check(bleed.max_stacks == 3, "rend_deeper_cut alone leaves max_stacks at 3")

	var c3: Combatant = _mk_warrior()
	_check(c3.pick_ability_talent(&"base_ability", &"rend_lasting_wound"), "picks rend_lasting_wound")
	var bleed2: Effect = EffectLibrary.make(&"bleed")
	c3.apply_rider_talent_adjustments(&"bleed", bleed2, c3)
	_check(bleed2.max_stacks == 4, "rend_lasting_wound: Bleed max_stacks is 4 (got %d)" % bleed2.max_stacks)
	_check(bleed2.dot_fractions.size() == 4, "rend_lasting_wound: Bleed gained a 4th stack fraction (got %d entries)" % bleed2.dot_fractions.size())
	_check(is_equal_approx(bleed2.dot_fractions[3], 1.55), "rend_lasting_wound: 4th stack fraction is 1.55 (got %.4f)" % bleed2.dot_fractions[3])

	# Mutual exclusion: only 1 pick per row.
	var c4: Combatant = _mk_warrior()
	_check(c4.pick_ability_talent(&"base_ability", &"rend_efficient"), "first pick on the Rend row succeeds")
	_check(not c4.pick_ability_talent(&"base_ability", &"rend_deeper_cut"), "a second pick on an already-filled row is rejected (cap of 1/row)")
	_check(c4.has_ability_talent(&"rend_efficient"), "the row's original pick is still active")

func _test_sundering_strike_row() -> void:
	var c: Combatant = _mk_warrior()
	_check(c.ability_talent_cost_delta(&"sundering_strike") == 0, "no Sundering Strike cost delta with nothing picked")
	_check(c.pick_ability_talent(&"ability_l2", &"sunder_efficient"), "picks sunder_efficient")
	_check(c.ability_talent_cost_delta(&"sundering_strike") == -1, "sunder_efficient: Sundering Strike costs 1 less Stamina")

	var c2: Combatant = _mk_warrior()
	_check(c2.pick_ability_talent(&"ability_l2", &"sunder_deeper"), "picks sunder_deeper")
	var sundered: Effect = EffectLibrary.make(&"sundered")
	c2.apply_rider_talent_adjustments(&"sundered", sundered, c2)
	_check(is_equal_approx(sundered.magnitude, 1.35), "sunder_deeper: Sundered's incoming multiplier is 1.35 (got %.3f)" % sundered.magnitude)
	_check(sundered.duration == 2, "sunder_deeper alone leaves duration at 2")

	var c3: Combatant = _mk_warrior()
	_check(c3.pick_ability_talent(&"ability_l2", &"sunder_lingering"), "picks sunder_lingering")
	var sundered2: Effect = EffectLibrary.make(&"sundered")
	c3.apply_rider_talent_adjustments(&"sundered", sundered2, c3)
	_check(sundered2.duration == 3, "sunder_lingering: Sundered lasts 3 turns (got %d)" % sundered2.duration)
	_check(is_equal_approx(sundered2.magnitude, 1.25), "sunder_lingering alone leaves magnitude at 1.25")

func _test_heroic_guard_row() -> void:
	var c: Combatant = _mk_warrior()
	_check(c.apply_heroic_guard(2), "casts Heroic Guard (baseline)")
	var g: Effect = c._find_effect(&"guarded")
	_check(g != null, "sanity: Guarded attached")
	_check(is_equal_approx(g.magnitude, 0.75), "baseline Heroic Guard: Guarded magnitude 0.75")
	_check(g.duration == 3, "baseline Heroic Guard: 3-turn duration")

	var c2: Combatant = _mk_warrior()
	_check(c2.pick_ability_talent(&"ability_l3", &"guard_reinforced"), "picks guard_reinforced")
	_check(c2.apply_heroic_guard(2), "casts Heroic Guard (reinforced)")
	var g2: Effect = c2._find_effect(&"guarded")
	_check(is_equal_approx(g2.magnitude, 0.65), "guard_reinforced: Guarded magnitude 0.65 (got %.3f)" % g2.magnitude)

	var c3: Combatant = _mk_warrior()
	_check(c3.pick_ability_talent(&"ability_l3", &"guard_lasting"), "picks guard_lasting")
	_check(c3.apply_heroic_guard(2), "casts Heroic Guard (lasting)")
	var g3: Effect = c3._find_effect(&"guarded")
	var t3: Effect = c3._find_effect(&"taunt")
	_check(g3.duration == 4, "guard_lasting: Guarded lasts 4 turns (got %d)" % g3.duration)
	_check(t3.duration == 4, "guard_lasting: Taunt lasts 4 turns too (got %d)" % t3.duration)

	var c4: Combatant = _mk_warrior()
	_check(c4.pick_ability_talent(&"ability_l3", &"guard_cleansing"), "picks guard_cleansing")
	var slow: Effect = EffectLibrary.make(&"slow")
	c4.attach_effect(slow)
	_check(c4.has_effect(&"slow"), "sanity: a debuff is active before casting")
	_check(c4.apply_heroic_guard(2), "casts Heroic Guard (cleansing)")
	_check(not c4.has_effect(&"slow"), "guard_cleansing: the active debuff is cleansed on cast")
	_check(c4.has_effect(&"guarded"), "guard_cleansing still grants Guarded")

func _test_second_wind_row() -> void:
	var c: Combatant = _mk_warrior()
	_check(c.ability_talent_cooldown_delta(&"second_wind") == 0, "no Second Wind cooldown delta with nothing picked")
	_check(c.pick_ability_talent(&"ability_l4", &"wind_swift"), "picks wind_swift")
	_check(c.ability_talent_cooldown_delta(&"second_wind") == -1, "wind_swift: Second Wind cooldown is 1 less turn")

	var c2: Combatant = _mk_warrior()
	c2.max_hp = 100; c2.hp = 10
	_check(c2.pick_ability_talent(&"ability_l4", &"wind_deeper"), "picks wind_deeper")
	_check(c2.apply_second_wind(2), "casts Second Wind (deeper)")
	_check(c2.hp == 50, "wind_deeper: Second Wind heals 40% max HP (10 + 40 = 50, got %d)" % c2.hp)

	var c3: Combatant = _mk_warrior()
	c3.max_hp = 100; c3.hp = 10
	_check(c3.apply_second_wind(2), "casts Second Wind (baseline)")
	_check(c3.hp == 40, "baseline Second Wind heals 30%% max HP (10 + 30 = 40, got %d)" % c3.hp)

	var c4: Combatant = _mk_warrior()
	_check(c4.pick_ability_talent(&"ability_l4", &"wind_empowering"), "picks wind_empowering")
	_check(c4.apply_second_wind(2), "casts Second Wind (empowering)")
	var emp: Effect = c4._find_effect(&"empowered")
	_check(emp != null, "wind_empowering: Empowered attached")
	_check(is_equal_approx(emp.magnitude, 1.15), "wind_empowering: Empowered is x1.15 (got %.3f)" % emp.magnitude)
	_check(emp.duration == 1, "wind_empowering: Empowered lasts 1 turn (got %d)" % emp.duration)

func _test_last_stand_row() -> void:
	var c: Combatant = _mk_warrior()
	c.passive_ability_id = &"last_stand"
	c.max_hp = 100; c.hp = 30
	_check(is_equal_approx(c.passive_outgoing_multiplier(), 1.2), "baseline Last Stand: +20% at 30% HP")

	var c2: Combatant = _mk_warrior()
	c2.passive_ability_id = &"last_stand"
	c2.max_hp = 100; c2.hp = 30
	_check(c2.pick_ability_talent(&"passive", &"stand_deeper"), "picks stand_deeper")
	_check(is_equal_approx(c2.passive_outgoing_multiplier(), 1.3), "stand_deeper: +30% at 30% HP (got %.3f)" % c2.passive_outgoing_multiplier())

	var c3: Combatant = _mk_warrior()
	c3.passive_ability_id = &"last_stand"
	c3.max_hp = 100; c3.hp = 35
	_check(is_equal_approx(c3.passive_outgoing_multiplier(), 1.0), "sanity: 35% HP is above the baseline 30% threshold")
	_check(c3.pick_ability_talent(&"passive", &"stand_wider"), "picks stand_wider")
	_check(is_equal_approx(c3.passive_outgoing_multiplier(), 1.2), "stand_wider: Last Stand now active at 35% HP too (widened to 40%)")
	c3.hp = 41
	_check(is_equal_approx(c3.passive_outgoing_multiplier(), 1.0), "stand_wider: still inactive just above the widened 40% threshold")

	var c4: Combatant = _mk_warrior()
	c4.passive_ability_id = &"last_stand"
	c4.max_hp = 100; c4.hp = 30
	_check(is_equal_approx(c4.passive_incoming_multiplier(), 1.0), "baseline Last Stand grants no incoming reduction")
	_check(c4.pick_ability_talent(&"passive", &"stand_guarded"), "picks stand_guarded")
	_check(is_equal_approx(c4.passive_incoming_multiplier(), 0.9), "stand_guarded: -10% incoming while Last Stand is active (got %.3f)" % c4.passive_incoming_multiplier())
	c4.hp = 31
	_check(is_equal_approx(c4.passive_incoming_multiplier(), 1.0), "stand_guarded: no reduction once Last Stand's own condition drops off")

func _test_wild_row() -> void:
	var c: Combatant = _mk_warrior()
	c.bonus_meter.value = c.bonus_meter.cap
	_check(c.fire_sticky_wild(c.weapon.reels.size(), 1), "fires Wild (baseline)")
	_check(not c.has_effect(&"empowered"), "baseline Wild grants no Empowered")

	var c2: Combatant = _mk_warrior()
	c2.bonus_meter.value = c2.bonus_meter.cap
	_check(c2.pick_ability_talent(&"ultimate", &"wild_truer"), "picks wild_truer")
	_check(c2.fire_sticky_wild(c2.weapon.reels.size(), 1), "fires Wild (truer)")
	var emp: Effect = c2._find_effect(&"empowered")
	_check(emp != null, "wild_truer: Empowered attached")
	_check(is_equal_approx(emp.magnitude, 1.15), "wild_truer: Empowered is x1.15 (got %.3f)" % emp.magnitude)

	# Bleeding Wild's precondition state (the actual on-hit attach lives in combat.gd's
	# _apply_attack(), orchestrator-level — see the file header comment above).
	var c3: Combatant = _mk_warrior()
	c3.bonus_meter.value = c3.bonus_meter.cap
	_check(c3.pick_ability_talent(&"ultimate", &"wild_bleeding"), "picks wild_bleeding")
	_check(c3.fire_sticky_wild(c3.weapon.reels.size(), 1), "fires Wild (bleeding)")
	_check(c3.sticky_wild_spins_remaining > 0, "Wild is active for combat.gd's wild_bleeding check to read")

	var c4: Combatant = _mk_warrior()
	c4.bonus_meter.value = c4.bonus_meter.cap
	var plan: MainPhasePlan = MainPhasePlan.new(c4)
	_check(plan.ultimate_id == &"wild", "sanity: Warrior's Ultimate id is &wild")
	plan.toggle_ultimate()
	_check(plan.fire_ultimate_staged, "Wild ultimate stages when the meter is armed")
	plan.commit()
	_check(c4.sticky_wild_spins_remaining == 1, "without Lasting Wild, firing Wild grants 1 spin (got %d)" % c4.sticky_wild_spins_remaining)

	var c5: Combatant = _mk_warrior()
	c5.bonus_meter.value = c5.bonus_meter.cap
	_check(c5.pick_ability_talent(&"ultimate", &"wild_lasting"), "picks wild_lasting")
	var plan2: MainPhasePlan = MainPhasePlan.new(c5)
	plan2.toggle_ultimate()
	plan2.commit()
	_check(c5.sticky_wild_spins_remaining == 2, "wild_lasting: firing Wild grants 2 spins (got %d)" % c5.sticky_wild_spins_remaining)

func _init() -> void:
	_test_options_for_shape()
	_test_rend_row()
	_test_sundering_strike_row()
	_test_heroic_guard_row()
	_test_second_wind_row()
	_test_last_stand_row()
	_test_wild_row()
	print(("WARRIOR ABILITY TALENTS TEST PASSED" if _failures == 0 else "WARRIOR ABILITY TALENTS TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_warrior.gd`
Expected: FAIL on essentially every check — `AbilityTalentLibrary.options_for(&"warrior", ...)` still returns `[]`.

- [ ] **Step 3: Implement**

**(a) `combat/ability_talent_library.gd`** — replace the existing empty stub:

```gdscript
		&"warrior":
			return []
```

with the full nested match (6 rows × 3 options):

```gdscript
		&"warrior":
			match row_id:
				&"base_ability":
					var o1: AbilityTalentOption = AbilityTalentOption.new()
					o1.id = &"rend_deeper_cut"; o1.row_id = row_id
					o1.display_name = "Deeper Cut"
					o1.description = "Rend's Bleed deals +25% DoT damage."
					var o2: AbilityTalentOption = AbilityTalentOption.new()
					o2.id = &"rend_lasting_wound"; o2.row_id = row_id
					o2.display_name = "Lasting Wound"
					o2.description = "Rend's Bleed can stack up to 4 times (was 3)."
					var o3: AbilityTalentOption = AbilityTalentOption.new()
					o3.id = &"rend_efficient"; o3.row_id = row_id
					o3.display_name = "Efficient Rend"
					o3.description = "Rend's Stamina cost is reduced to 1 (was 2)."
					return [o1, o2, o3]
				&"ability_l2":
					var s1: AbilityTalentOption = AbilityTalentOption.new()
					s1.id = &"sunder_deeper"; s1.row_id = row_id
					s1.display_name = "Deeper Sunder"
					s1.description = "Sundering Strike's Sundered debuff raises incoming damage taken to +35% (was +25%)."
					var s2: AbilityTalentOption = AbilityTalentOption.new()
					s2.id = &"sunder_lingering"; s2.row_id = row_id
					s2.display_name = "Lingering Sunder"
					s2.description = "Sundering Strike's Sundered debuff lasts 3 turns (was 2)."
					var s3: AbilityTalentOption = AbilityTalentOption.new()
					s3.id = &"sunder_efficient"; s3.row_id = row_id
					s3.display_name = "Efficient Strike"
					s3.description = "Sundering Strike's Stamina cost is reduced to 2 (was 3)."
					return [s1, s2, s3]
				&"ability_l3":
					var g1: AbilityTalentOption = AbilityTalentOption.new()
					g1.id = &"guard_reinforced"; g1.row_id = row_id
					g1.display_name = "Reinforced Guard"
					g1.description = "Heroic Guard reduces incoming damage to 65% (was 75%)."
					var g2: AbilityTalentOption = AbilityTalentOption.new()
					g2.id = &"guard_cleansing"; g2.row_id = row_id
					g2.display_name = "Cleansing Guard"
					g2.description = "Heroic Guard also cleanses your active debuffs on cast."
					var g3: AbilityTalentOption = AbilityTalentOption.new()
					g3.id = &"guard_lasting"; g3.row_id = row_id
					g3.display_name = "Lasting Guard"
					g3.description = "Heroic Guard and its Taunt last 4 turns (was 3)."
					return [g1, g2, g3]
				&"ability_l4":
					var w1: AbilityTalentOption = AbilityTalentOption.new()
					w1.id = &"wind_deeper"; w1.row_id = row_id
					w1.display_name = "Deeper Wind"
					w1.description = "Second Wind heals 40% max HP (was 30%)."
					var w2: AbilityTalentOption = AbilityTalentOption.new()
					w2.id = &"wind_empowering"; w2.row_id = row_id
					w2.display_name = "Empowering Wind"
					w2.description = "Second Wind also grants Empowered (x1.15 outgoing damage) for 1 turn."
					var w3: AbilityTalentOption = AbilityTalentOption.new()
					w3.id = &"wind_swift"; w3.row_id = row_id
					w3.display_name = "Swift Recovery"
					w3.description = "Second Wind's cooldown is reduced to 3 turns (was 4)."
					return [w1, w2, w3]
				&"passive":
					var p1: AbilityTalentOption = AbilityTalentOption.new()
					p1.id = &"stand_deeper"; p1.row_id = row_id
					p1.display_name = "Deeper Grit"
					p1.description = "Last Stand's damage bonus increases to +30% (was +20%)."
					var p2: AbilityTalentOption = AbilityTalentOption.new()
					p2.id = &"stand_wider"; p2.row_id = row_id
					p2.display_name = "Wider Window"
					p2.description = "Last Stand activates at or below 40% HP (was 30%)."
					var p3: AbilityTalentOption = AbilityTalentOption.new()
					p3.id = &"stand_guarded"; p3.row_id = row_id
					p3.display_name = "Guarded Stand"
					p3.description = "While Last Stand is active, also reduce incoming damage by 10%."
					return [p1, p2, p3]
				&"ultimate":
					var u1: AbilityTalentOption = AbilityTalentOption.new()
					u1.id = &"wild_truer"; u1.row_id = row_id
					u1.display_name = "Truer Wild"
					u1.description = "Wild also grants self Empowered (x1.15 outgoing damage) for its duration."
					var u2: AbilityTalentOption = AbilityTalentOption.new()
					u2.id = &"wild_bleeding"; u2.row_id = row_id
					u2.display_name = "Bleeding Wild"
					u2.description = "Any hit landed while Wild is active also applies a stack of Bleed."
					var u3: AbilityTalentOption = AbilityTalentOption.new()
					u3.id = &"wild_lasting"; u3.row_id = row_id
					u3.display_name = "Lasting Wild"
					u3.description = "Wild's crit bias lasts 2 spins instead of 1."
					return [u1, u2, u3]
				_:
					return []
```

**(b) `combat/combatant.gd` — `apply_heroic_guard()`**, change from:

```gdscript
func apply_heroic_guard(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	var guard: Effect = EffectLibrary.make(&"guarded")
	guard.duration = 3
	attach_effect(guard)
	var taunt: Effect = EffectLibrary.make(&"taunt")
	taunt.duration = 3
	attach_effect(taunt)
	return true
```

to:

```gdscript
func apply_heroic_guard(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	var dur: int = 4 if has_ability_talent(&"guard_lasting") else 3
	var guard: Effect = EffectLibrary.make(&"guarded")
	if has_ability_talent(&"guard_reinforced"):
		guard.magnitude = 0.65
	guard.duration = dur
	attach_effect(guard)
	var taunt: Effect = EffectLibrary.make(&"taunt")
	taunt.duration = dur
	attach_effect(taunt)
	if has_ability_talent(&"guard_cleansing"):
		# Reuses the existing full debuff-cleanse (the same primitive Second Wind already calls) —
		# there's no "remove exactly 1 debuff" primitive in this codebase.
		cleanse()
	return true
```

**(c) `combat/combatant.gd` — `apply_second_wind()`**, change from:

```gdscript
func apply_second_wind(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	heal(ceili(max_hp * 0.30))
	cleanse()
	var guard: Effect = EffectLibrary.make(&"guarded")
	guard.duration = 3
	attach_effect(guard)
	return true
```

to:

```gdscript
func apply_second_wind(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	var heal_pct: float = 0.40 if has_ability_talent(&"wind_deeper") else 0.30
	heal(ceili(max_hp * heal_pct))
	cleanse()
	var guard: Effect = EffectLibrary.make(&"guarded")
	guard.duration = 3
	attach_effect(guard)
	if has_ability_talent(&"wind_empowering"):
		var empowered: Effect = EffectLibrary.make(&"empowered")
		empowered.magnitude = 1.15
		empowered.duration = 1
		attach_effect(empowered)
	return true
```

**(d) `combat/combatant.gd` — `passive_outgoing_multiplier()`**, change the `&"last_stand":` arm from:

```gdscript
		&"last_stand":
			return 1.2 if (float(hp) / float(maxi(max_hp, 1))) <= 0.30 else 1.0
```

to:

```gdscript
		&"last_stand":
			var threshold: float = 0.40 if has_ability_talent(&"stand_wider") else 0.30
			var bonus: float = 1.3 if has_ability_talent(&"stand_deeper") else 1.2
			return bonus if (float(hp) / float(maxi(max_hp, 1))) <= threshold else 1.0
```

**(e) `combat/combatant.gd` — `passive_incoming_multiplier()`**, change from:

```gdscript
	match passive_ability_id:
		&"bulwark":
			return 0.85 if (float(hp) / float(maxi(max_hp, 1))) > 0.50 else 1.0
		_:
			return 1.0
```

to:

```gdscript
	match passive_ability_id:
		&"bulwark":
			return 0.85 if (float(hp) / float(maxi(max_hp, 1))) > 0.50 else 1.0
		&"last_stand":
			if not has_ability_talent(&"stand_guarded"):
				return 1.0
			# stand_guarded shares the "passive" row with stand_wider (max 1 pick per row), so the
			# HP gate here is always the base 30% threshold — never simultaneously widened.
			return 0.9 if (float(hp) / float(maxi(max_hp, 1))) <= 0.30 else 1.0
		_:
			return 1.0
```

**(f) `combat/combatant.gd` — the 3 shared dispatch methods that need a Warrior arm.** Change each from its Task-14 stub:

```gdscript
func ability_talent_cost_delta(ability_id: StringName) -> int:
	match class_id:
		_:
			return 0
```

to:

```gdscript
func ability_talent_cost_delta(ability_id: StringName) -> int:
	match class_id:
		&"warrior":
			match ability_id:
				&"rend":
					return -1 if has_ability_talent(&"rend_efficient") else 0
				&"sundering_strike":
					return -1 if has_ability_talent(&"sunder_efficient") else 0
				_:
					return 0
		_:
			return 0
```

```gdscript
func ability_talent_cooldown_delta(ability_id: StringName) -> int:
	match class_id:
		_:
			return 0
```

to:

```gdscript
func ability_talent_cooldown_delta(ability_id: StringName) -> int:
	match class_id:
		&"warrior":
			match ability_id:
				&"second_wind":
					return -1 if has_ability_talent(&"wind_swift") else 0
				_:
					return 0
		_:
			return 0
```

```gdscript
func apply_rider_talent_adjustments(rider_id: StringName, effect: Effect, target: Combatant) -> void:
	match class_id:
		_:
			pass
```

to:

```gdscript
func apply_rider_talent_adjustments(rider_id: StringName, effect: Effect, target: Combatant) -> void:
	match class_id:
		&"warrior":
			match rider_id:
				&"bleed":
					if has_ability_talent(&"rend_deeper_cut"):
						for i: int in range(effect.dot_fractions.size()):
							effect.dot_fractions[i] *= 1.25
					if has_ability_talent(&"rend_lasting_wound"):
						effect.max_stacks = 4
						if effect.dot_fractions.size() < 4:
							effect.dot_fractions.append(1.55)
				&"sundered":
					if has_ability_talent(&"sunder_deeper"):
						effect.magnitude = 1.35
					if has_ability_talent(&"sunder_lingering"):
						effect.duration = 3
		_:
			pass
```

**(g) `combat/combatant.gd` — `fire_sticky_wild()`**, change from:

```gdscript
func fire_sticky_wild(reel_count: int, spins: int) -> bool:
	if bonus_meter == null or not bonus_meter.is_armed():
		return false
	bonus_meter.consume()
	sticky_wild_count = reel_count
	sticky_wild_spins_remaining = spins
	return true
```

to:

```gdscript
func fire_sticky_wild(reel_count: int, spins: int) -> bool:
	if bonus_meter == null or not bonus_meter.is_armed():
		return false
	bonus_meter.consume()
	sticky_wild_count = reel_count
	sticky_wild_spins_remaining = spins
	if class_id == &"warrior" and has_ability_talent(&"wild_truer"):
		var empowered: Effect = EffectLibrary.make(&"empowered")
		empowered.magnitude = 1.15
		empowered.duration = spins
		attach_effect(empowered)
	return true
```

**(h) `combat/combat.gd` — `_apply_attack()`**, insert the Bleeding-Wild check right after the existing Crippling Shot `bonus_vs_cc` block (after the `_log(...)` call, still inside the `for t: Combatant in targets:` loop, still inside `if attack.final_damage > 0:`):

```gdscript
			if attack.source_reel != null and attack.source_reel.bonus_vs_cc:
				if t.has_effect(&"slow") or t.has_effect(&"rooted") or t.stunned_last_turn:
					var bonus: int = ceili(attack.final_damage * 0.5)
					t.take_damage(bonus)
					_log("  🎯 Crippling Shot exploits %s's condition for %d bonus damage." % [t.display_name, bonus])
			# Warrior "Bleeding Wild" talent (Task 15): any hit landed while the Wild Ultimate is
			# still active this spin also lashes the target with a stack of Bleed. Checked BEFORE
			# consume_wild_spin() (called once for the whole spin in _finish_spin()), so
			# sticky_wild_spins_remaining is still the pre-decrement value for every reel this spin.
			if _attacker.class_id == &"warrior" and _attacker.has_ability_talent(&"wild_bleeding") and _attacker.sticky_wild_spins_remaining > 0:
				var wild_bleed: Effect = EffectLibrary.make(&"bleed")
				wild_bleed.dot_base_damage = _attacker.weapon_effective_base_damage()
				_attacker.apply_rider_talent_adjustments(&"bleed", wild_bleed, t)
				t.attach_effect(wild_bleed)
				_log("  🩸 %s's WILD lashes %s with a stack of BLEED." % [_attacker.display_name, t.display_name])
				(_panels[t] as CombatantPanel).refresh_status()
```

(The `apply_rider_talent_adjustments()` call here means a Warrior who's also picked `rend_deeper_cut`/`rend_lasting_wound` gets those Bleed amplifications on Wild-triggered stacks too — a deliberate, consistent bonus, not an oversight.)

**(i) `combat/main_phase_plan.gd` — `commit()`'s `&"wild":` arm**, change:

```gdscript
			&"wild":
				combatant.fire_sticky_wild(_weapon_reel_count(), WILD_SPINS)        # single spin (Warrior)
```

to:

```gdscript
			&"wild":
				# Warrior "Lasting Wild" talent (Task 15): the crit bias lasts 2 spins instead of 1.
				var spins: int = (WILD_SPINS + 1) if combatant.has_ability_talent(&"wild_lasting") else WILD_SPINS
				combatant.fire_sticky_wild(_weapon_reel_count(), spins)        # single spin (Warrior), +1 with Lasting Wild
```

*(Confirm the exact existing line/variable names — `_weapon_reel_count()`/`WILD_SPINS` — against the
real file before editing; if named differently, use the real names, the behavior is what matters.)*

- [ ] **Step 4: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_warrior.gd`
Expected: all lines print `ok:`.

- [ ] **Step 5: Run the full test suite**

Run every `tests/test_*.gd` file headlessly and confirm exit code 0 for each. The 3 known
pre-existing failures (see Global Constraints) are NOT regressions. Any other nonzero exit is a
real regression and must be root-caused before committing.

- [ ] **Step 6: Commit**

```bash
git add combat/ability_talent_library.gd combat/combatant.gd combat/combat.gd combat/main_phase_plan.gd tests/test_ability_talents_warrior.gd
git commit -m "feat(talents): Warrior Ability Talents — 18 options across Rend/Sundering Strike/Heroic Guard/Second Wind/Last Stand/Wild"
```

---

## Task 16: Vanguard Ability Talents (18 options)

> **Implementation note (not a reworded option — all 18 options below are implemented exactly as
> approved):** Vanguard's own weapon type is Crushing, and Crushing's `inherent_rider_id` is
> `&"slow"` — the exact same rider id Quake Slam's own reel uses. Both of Task 14's generic
> per-rider-id hooks (`apply_rider_talent_adjustments`/`rider_talent_bonus_damage_pct`) are keyed
> only by `rider_id`, not by which ability produced the hit, so wiring `slam_deeper`/`slam_heavier`
> through either would also fire on Vanguard's ordinary Crushing weapon crits, not just Quake Slam's
> own hit. Both options are instead implemented via reel-instance-scoped mechanisms (a direct
> multiplier scale on Quake Slam's own spliced reel, and a new `ActionReel.talent_extra_rider_stack`
> flag mirroring the existing `bonus_vs_cc` precedent) — no change to either shared dispatch method
> for this class. `rampage_deeper` uses the same reel-instance-scoped approach for the same reason
> (Rampage isn't a rider-carrying ability to begin with).
>
> **Flagged, not silently changed:** `bulwark_wider`'s approved effect ("HP threshold 50%→60%,
> active more often") appears to contradict itself under the existing `> threshold` polarity —
> raising the threshold NARROWS the active range, not widens it. Implemented literally to the
> approved number; flag to the player at the next playtest checkpoint whether the intent was
> actually a LOWERED threshold (e.g. 50%→40%, matching Warrior's `stand_wider`'s "lower the bar so
> it fires more often" pattern) rather than a raised one.

**Files:**
- Modify: `combat/ability_talent_library.gd` (fills in the `&"vanguard":` branch of `options_for()`)
- Modify: `combat/combatant.gd` (`apply_heft()`, `_heft_turn_reels()`, `bloodwrath_bonus_pct()` +
  `apply_bloodwrath()`, `try_quake_slam()`, `apply_mountain_stance()`, `passive_incoming_multiplier()`,
  `thorns_pct()`, `fire_rampage()`, and the 2 shared dispatch methods that need a `&"vanguard":` arm)
- Modify: `combat/resources/action_reel.gd` (new `talent_extra_rider_stack` field, alongside the
  existing `bonus_vs_cc`)
- Modify: `combat/combat.gd` (`_apply_attack()` gains the Heavier Slam 2nd-stack check and the
  Slowing Rampage on-hit check)
- Modify: `combat/main_phase_plan.gd` (`commit()`'s `&"rampage":` arm gains the `rampage_lasting`
  spin-count branch)
- Modify: `combat/ui/ability_menu_panel.gd` (`_dynamic_suffix()`'s Bloodwrath live-tooltip calc stays
  in sync with `wrath_deeper`, via `bloodwrath_bonus_pct()`'s new optional params)
- Test: `tests/test_ability_talents_vanguard.gd` (new)

**Interfaces:**
- Consumes: Task 14's `Combatant.class_id` / `ability_talent_picks` / `has_ability_talent()` /
  `pick_ability_talent()` / `ability_talent_cost_delta()` / `ability_talent_cooldown_delta()`
  scaffolds, and `AbilityTalentLibrary.options_for()`'s empty `&"vanguard":` stub. Also consumes the
  existing `EffectLibrary`/`MainPhasePlan` infrastructure: `apply_heft`, `_heft_turn_reels`,
  `apply_bloodwrath`, `try_quake_slam`, `apply_mountain_stance`, `fire_rampage`,
  `passive_incoming_multiplier`, `thorns_pct`, and the `&"slow"`/`&"guarded"`/`&"empowered"`/
  `&"taunt"` `EffectLibrary` entries. Reuses the existing `ActionReel.bonus_vs_cc` field as the
  precedent for the new `talent_extra_rider_stack` field.
- Produces: 18 populated `AbilityTalentOption` entries for Vanguard across all 6 rows; talent-aware
  Heft/Bloodwrath/Quake Slam/Mountain Stance/Bulwark/Rampage behavior. `apply_rider_talent_adjustments()`
  and `rider_talent_bonus_damage_pct()` get **no** Vanguard arm at all — both stay at their Task-14
  stub for this class (see the Implementation note above).

- [ ] **Step 1: Write the failing test**

Create `tests/test_ability_talents_vanguard.gd`:

```gdscript
extends SceneTree

# Headless test: the Vanguard's 18 Ability Talent options (Task 16) — one row of 3 mutually-
# exclusive picks per Vanguard ability (Heft / Bloodwrath / Quake Slam / Mountain Stance / Bulwark /
# Rampage). Exercises AbilityTalentLibrary.options_for(&"vanguard", row_id), pick_ability_talent()/
# has_ability_talent(), the cost/cooldown-delta dispatch methods, and the reel-instance-scoped
# mechanisms slam_deeper/slam_heavier/rampage_deeper use INSTEAD of the generic per-rider-id talent
# hooks (see this task's Implementation note: Vanguard's own Crushing weapon shares Quake Slam's
# &"slow" rider id, so those hooks can't distinguish "Quake Slam's hit" from "an ordinary weapon
# crit" for this class).
#
# Slowing Rampage's ACTUAL on-hit attach lives in combat.gd's _apply_attack() — orchestrator-level,
# requires a running Combat scene — and is NOT headlessly tested here, consistent with this
# codebase's own documented precedent (tests/test_ability_talents_warrior.gd's header comment on
# Bleeding Wild). This test instead proves the precondition state combat.gd's wiring reads.
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_vanguard.gd

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _count(reel: ActionReel, tier: ReelFace.ResultTier) -> int:
	var n: int = 0
	for f: ReelFace in reel.faces:
		if f.result_tier == tier:
			n += 1
	return n

func _empowered_magnitude(c: Combatant) -> float:
	var e: Effect = c._find_effect(&"empowered")
	return e.magnitude if e != null else -1.0

func _empowered_duration(c: Combatant) -> int:
	var e: Effect = c._find_effect(&"empowered")
	return e.duration if e != null else -1

func _mk_vanguard() -> Combatant:
	var c: Combatant = ClassLibrary.make(&"vanguard").build_combatant(true)
	c.level = Combatant.MAX_LEVEL  # unlocks every talent row (5/6/7/8/9/10)
	c.resource_pool.stamina = c.resource_pool.max_stamina
	c.begin_turn()  # populates turn_reels from the 2-reel Crushing War Hammer
	return c

func _test_options_for_shape() -> void:
	var rows: Array[StringName] = [&"base_ability", &"ability_l2", &"ability_l3", &"ability_l4", &"passive", &"ultimate"]
	var all_ids: Array[StringName] = [
		&"heft_reinforced", &"heft_guarding", &"heft_efficient",
		&"wrath_deeper", &"wrath_lasting", &"wrath_efficient",
		&"slam_deeper", &"slam_heavier", &"slam_efficient",
		&"stance_deeper", &"stance_thorned", &"stance_swift",
		&"bulwark_deeper", &"bulwark_wider", &"bulwark_thorned",
		&"rampage_deeper", &"rampage_slowing", &"rampage_lasting",
	]
	var seen: Array[StringName] = []
	for row: StringName in rows:
		var opts: Array[AbilityTalentOption] = AbilityTalentLibrary.options_for(&"vanguard", row)
		_check(opts.size() == 3, "Vanguard row %s has exactly 3 options (got %d)" % [row, opts.size()])
		for o: AbilityTalentOption in opts:
			_check(o.row_id == row, "option %s reports its own row_id (%s)" % [o.id, row])
			_check(o.display_name != "" and o.description != "", "option %s has a non-empty display_name/description" % o.id)
			seen.append(o.id)
	for id: StringName in all_ids:
		_check(id in seen, "option %s is present in AbilityTalentLibrary.options_for(&vanguard, ...)" % id)

func _test_heft_row() -> void:
	var c: Combatant = _mk_vanguard()
	_check(c.ability_talent_cost_delta(&"heft") == 0, "no Heft cost delta with nothing picked")
	_check(c.pick_ability_talent(&"base_ability", &"heft_efficient"), "picks heft_efficient")
	_check(c.ability_talent_cost_delta(&"heft") == -1, "heft_efficient: Heft costs 1 less Stamina")

	var c2: Combatant = _mk_vanguard()
	_check(c2.pick_ability_talent(&"base_ability", &"heft_reinforced"), "picks heft_reinforced")
	_check(c2.apply_heft(2), "casts Heft (reinforced)")
	var reel: ActionReel = c2.turn_reels[0]
	_check(_count(reel, ReelFace.ResultTier.NEUTRAL) == 1, "heft_reinforced: 1 NEUTRAL face converted (1 left, got %d)" % _count(reel, ReelFace.ResultTier.NEUTRAL))
	_check(_count(reel, ReelFace.ResultTier.SUCCESS) == 8, "heft_reinforced: SUCCESS count is 8 (2 base misses + crit-fail + 1 neutral, got %d)" % _count(reel, ReelFace.ResultTier.SUCCESS))

	var c3: Combatant = _mk_vanguard()
	_check(c3.apply_heft(2), "casts Heft (baseline)")
	var reel3: ActionReel = c3.turn_reels[0]
	_check(_count(reel3, ReelFace.ResultTier.NEUTRAL) == 2, "baseline Heft leaves both NEUTRAL faces untouched (got %d)" % _count(reel3, ReelFace.ResultTier.NEUTRAL))

	var c4: Combatant = _mk_vanguard()
	_check(c4.pick_ability_talent(&"base_ability", &"heft_guarding"), "picks heft_guarding")
	_check(c4.apply_heft(2), "casts Heft (guarding)")
	var g: Effect = c4._find_effect(&"guarded")
	_check(g != null, "heft_guarding: Guarded attached")
	_check(is_equal_approx(g.magnitude, 0.9), "heft_guarding: Guarded magnitude 0.9 (got %.3f)" % g.magnitude)
	_check(g.duration == 1, "heft_guarding: 1-turn duration (got %d)" % g.duration)

	# Mutual exclusion: only 1 pick per row.
	var c5: Combatant = _mk_vanguard()
	_check(c5.pick_ability_talent(&"base_ability", &"heft_efficient"), "first pick on the Heft row succeeds")
	_check(not c5.pick_ability_talent(&"base_ability", &"heft_guarding"), "a second pick on an already-filled row is rejected (cap of 1/row)")
	_check(c5.has_ability_talent(&"heft_efficient"), "the row's original pick is still active")

func _test_bloodwrath_row() -> void:
	var c: Combatant = _mk_vanguard()
	_check(c.ability_talent_cost_delta(&"bloodwrath") == 0, "no Bloodwrath cost delta with nothing picked")
	_check(c.pick_ability_talent(&"ability_l2", &"wrath_efficient"), "picks wrath_efficient")
	_check(c.ability_talent_cost_delta(&"bloodwrath") == -1, "wrath_efficient: Bloodwrath costs 1 less Stamina")

	var c2: Combatant = _mk_vanguard()
	c2.max_hp = 100; c2.hp = 10  # 90% missing
	_check(c2.pick_ability_talent(&"ability_l2", &"wrath_deeper"), "picks wrath_deeper")
	_check(c2.apply_bloodwrath(3), "casts Bloodwrath (deeper)")
	_check(is_equal_approx(_empowered_magnitude(c2), 1.60), "wrath_deeper: magnitude caps at 1.60 (90%% missing x1.2, capped 60%%, got %.3f)" % _empowered_magnitude(c2))

	var c3: Combatant = _mk_vanguard()
	c3.max_hp = 100; c3.hp = 10
	_check(c3.apply_bloodwrath(3), "casts Bloodwrath (baseline)")
	_check(is_equal_approx(_empowered_magnitude(c3), 1.50), "baseline Bloodwrath: magnitude caps at 1.50 (90%% missing, capped 50%%)")

	var c4: Combatant = _mk_vanguard()
	_check(c4.pick_ability_talent(&"ability_l2", &"wrath_lasting"), "picks wrath_lasting")
	_check(c4.apply_bloodwrath(3), "casts Bloodwrath (lasting)")
	_check(_empowered_duration(c4) == 3, "wrath_lasting: Empowered lasts 3 turns (got %d)" % _empowered_duration(c4))

	_check(is_equal_approx(Combatant.bloodwrath_bonus_pct(0.25), 0.25), "bloodwrath_bonus_pct(25%% missing), default scale/cap == 25%%")
	_check(is_equal_approx(Combatant.bloodwrath_bonus_pct(0.30, 1.2, 0.60), 0.36), "bloodwrath_bonus_pct(30%% missing, scale 1.2, cap 60%%) == 36%%")
	_check(is_equal_approx(Combatant.bloodwrath_bonus_pct(0.90, 1.2, 0.60), 0.60), "bloodwrath_bonus_pct(90%% missing, scale 1.2, cap 60%%) caps at 60%%")

func _test_quake_slam_row() -> void:
	var c: Combatant = _mk_vanguard()
	_check(c.ability_talent_cost_delta(&"quake_slam") == 0, "no Quake Slam cost delta with nothing picked")
	_check(c.pick_ability_talent(&"ability_l3", &"slam_efficient"), "picks slam_efficient")
	_check(c.ability_talent_cost_delta(&"quake_slam") == -1, "slam_efficient: Quake Slam costs 1 less Stamina")

	var c2: Combatant = _mk_vanguard()
	_check(c2.pick_ability_talent(&"ability_l3", &"slam_deeper"), "picks slam_deeper")
	_check(c2.try_quake_slam(c2.weapon_type(), 4, 5), "casts Quake Slam (deeper)")
	var reel: ActionReel = c2.turn_reels[c2.turn_reels.size() - 1]
	var checked_success: bool = false
	var checked_crit: bool = false
	for face: ReelFace in reel.faces:
		if face.result_tier == ReelFace.ResultTier.SUCCESS:
			_check(is_equal_approx(face.multiplier, 1.15), "slam_deeper: SUCCESS face multiplier is 1.15 (got %.3f)" % face.multiplier)
			checked_success = true
		elif face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
			_check(is_equal_approx(face.multiplier, 2.30), "slam_deeper: CRIT_SUCCESS face multiplier is 2.30 (got %.3f)" % face.multiplier)
			checked_crit = true
	_check(checked_success and checked_crit, "sanity: both hit tiers exist on the spliced reel to check")

	var c3: Combatant = _mk_vanguard()
	_check(c3.pick_ability_talent(&"ability_l3", &"slam_heavier"), "picks slam_heavier")
	_check(c3.try_quake_slam(c3.weapon_type(), 4, 5), "casts Quake Slam (heavier)")
	var reel3: ActionReel = c3.turn_reels[c3.turn_reels.size() - 1]
	_check(reel3.talent_extra_rider_stack, "slam_heavier: the spliced reel is flagged for a 2nd rider stack")

	var c4: Combatant = _mk_vanguard()
	_check(c4.try_quake_slam(c4.weapon_type(), 4, 5), "casts Quake Slam (baseline)")
	var reel4: ActionReel = c4.turn_reels[c4.turn_reels.size() - 1]
	_check(not reel4.talent_extra_rider_stack, "baseline Quake Slam: no 2nd-stack flag")
	for face4: ReelFace in reel4.faces:
		if face4.result_tier == ReelFace.ResultTier.SUCCESS:
			_check(is_equal_approx(face4.multiplier, 1.0), "baseline Quake Slam: SUCCESS multiplier stays 1.0 (got %.3f)" % face4.multiplier)

func _test_mountain_stance_row() -> void:
	var c: Combatant = _mk_vanguard()
	_check(c.ability_talent_cooldown_delta(&"mountain_stance") == 0, "no Mountain Stance cooldown delta with nothing picked")
	_check(c.pick_ability_talent(&"ability_l4", &"stance_swift"), "picks stance_swift")
	_check(c.ability_talent_cooldown_delta(&"mountain_stance") == -1, "stance_swift: Mountain Stance cooldown is 1 less turn")

	var c2: Combatant = _mk_vanguard()
	_check(c2.pick_ability_talent(&"ability_l4", &"stance_deeper"), "picks stance_deeper")
	_check(c2.apply_mountain_stance(5), "casts Mountain Stance (deeper)")
	_check(is_equal_approx(c2.incoming_damage_multiplier(), 0.4), "stance_deeper: incoming multiplier 0.4 (got %.3f)" % c2.incoming_damage_multiplier())

	var c3: Combatant = _mk_vanguard()
	_check(c3.apply_mountain_stance(5), "casts Mountain Stance (baseline)")
	_check(is_equal_approx(c3.incoming_damage_multiplier(), 0.5), "baseline Mountain Stance: incoming multiplier 0.5")

	var c4: Combatant = _mk_vanguard()
	_check(c4.pick_ability_talent(&"ability_l4", &"stance_thorned"), "picks stance_thorned")
	_check(c4.apply_mountain_stance(5), "casts Mountain Stance (thorned)")
	_check(is_equal_approx(c4.thorns_pct(), 0.15), "stance_thorned: 15%% Thorns while Mountain Stance is up (got %.3f)" % c4.thorns_pct())

func _test_bulwark_row() -> void:
	var c: Combatant = _mk_vanguard()
	c.passive_ability_id = &"bulwark"
	c.max_hp = 100; c.hp = 51
	_check(is_equal_approx(c.passive_incoming_multiplier(), 0.85), "baseline Bulwark: -15% just above 50% HP")

	var c2: Combatant = _mk_vanguard()
	c2.passive_ability_id = &"bulwark"
	c2.max_hp = 100; c2.hp = 51
	_check(c2.pick_ability_talent(&"passive", &"bulwark_deeper"), "picks bulwark_deeper")
	_check(is_equal_approx(c2.passive_incoming_multiplier(), 0.75), "bulwark_deeper: -25%% just above 50%% HP (got %.3f)" % c2.passive_incoming_multiplier())

	# bulwark_wider: implemented literally to the approved 50%->60% number (see this task's
	# Implementation note re: the apparent "active more often" wording mismatch — flagged for the
	# player, not silently changed).
	var c3: Combatant = _mk_vanguard()
	c3.passive_ability_id = &"bulwark"
	c3.max_hp = 100; c3.hp = 55
	_check(is_equal_approx(c3.passive_incoming_multiplier(), 0.85), "sanity: 55%% HP is active under the baseline >50%% threshold")
	_check(c3.pick_ability_talent(&"passive", &"bulwark_wider"), "picks bulwark_wider")
	_check(is_equal_approx(c3.passive_incoming_multiplier(), 1.0), "bulwark_wider: 55%% HP no longer qualifies once the threshold moves to >60%% (see the task's Implementation note)")
	c3.hp = 65
	_check(is_equal_approx(c3.passive_incoming_multiplier(), 0.85), "bulwark_wider: -15%% still applies at 65%% HP (above the moved 60%% threshold)")

	var c4: Combatant = _mk_vanguard()
	c4.passive_ability_id = &"bulwark"
	c4.max_hp = 100; c4.hp = 51
	_check(is_equal_approx(c4.thorns_pct(), 0.0), "baseline Bulwark grants no Thorns")
	_check(c4.pick_ability_talent(&"passive", &"bulwark_thorned"), "picks bulwark_thorned")
	_check(is_equal_approx(c4.thorns_pct(), 0.10), "bulwark_thorned: 10%% Thorns while Bulwark is active (got %.3f)" % c4.thorns_pct())
	c4.hp = 50
	_check(is_equal_approx(c4.thorns_pct(), 0.0), "bulwark_thorned: no Thorns once Bulwark's own 50%% condition drops off")

func _test_rampage_row() -> void:
	var crushing: DamageType = load("res://combat/resources/types/crushing.tres")

	var c: Combatant = _mk_vanguard()
	c.bonus_meter.value = c.bonus_meter.cap
	_check(c.fire_rampage(crushing, 2, 1), "fires Rampage (baseline)")
	_check(c.aoe_spins_remaining == 1, "baseline Rampage: 1 AoE spin (got %d)" % c.aoe_spins_remaining)

	var c2: Combatant = _mk_vanguard()
	c2.bonus_meter.value = c2.bonus_meter.cap
	_check(c2.pick_ability_talent(&"ultimate", &"rampage_deeper"), "picks rampage_deeper")
	_check(c2.fire_rampage(crushing, 2, 1), "fires Rampage (deeper)")
	var added: ActionReel = c2.turn_reels[c2.turn_reels.size() - 1]
	var checked: bool = false
	for face: ReelFace in added.faces:
		if face.result_tier == ReelFace.ResultTier.SUCCESS:
			_check(is_equal_approx(face.multiplier, 1.15), "rampage_deeper: the added reel's SUCCESS multiplier is 1.15 (got %.3f)" % face.multiplier)
			checked = true
	_check(checked, "sanity: a SUCCESS face exists on the added reel to check")

	var c3: Combatant = _mk_vanguard()
	c3.bonus_meter.value = c3.bonus_meter.cap
	_check(c3.pick_ability_talent(&"ultimate", &"rampage_slowing"), "picks rampage_slowing")
	_check(c3.fire_rampage(crushing, 2, 1), "fires Rampage (slowing)")
	_check(c3.is_aoe_active(), "Rampage's AoE is active for combat.gd's rampage_slowing check to read")

	var c4: Combatant = _mk_vanguard()
	c4.bonus_meter.value = c4.bonus_meter.cap
	var plan: MainPhasePlan = MainPhasePlan.new(c4)
	_check(plan.ultimate_id == &"rampage", "sanity: Vanguard's Ultimate id is &rampage")
	plan.toggle_ultimate()
	_check(plan.fire_ultimate_staged, "Rampage ultimate stages when the meter is armed")
	plan.commit()
	_check(c4.aoe_spins_remaining == 1, "without Lasting Rampage, firing Rampage grants 1 AoE spin (got %d)" % c4.aoe_spins_remaining)

	var c5: Combatant = _mk_vanguard()
	c5.bonus_meter.value = c5.bonus_meter.cap
	_check(c5.pick_ability_talent(&"ultimate", &"rampage_lasting"), "picks rampage_lasting")
	var plan2: MainPhasePlan = MainPhasePlan.new(c5)
	plan2.toggle_ultimate()
	plan2.commit()
	_check(c5.aoe_spins_remaining == 2, "rampage_lasting: firing Rampage grants 2 AoE spins (got %d)" % c5.aoe_spins_remaining)

func _init() -> void:
	_test_options_for_shape()
	_test_heft_row()
	_test_bloodwrath_row()
	_test_quake_slam_row()
	_test_mountain_stance_row()
	_test_bulwark_row()
	_test_rampage_row()
	print(("VANGUARD ABILITY TALENTS TEST PASSED" if _failures == 0 else "VANGUARD ABILITY TALENTS TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_vanguard.gd`
Expected: FAIL on essentially every check.

- [ ] **Step 3: Implement**

**(a) `combat/ability_talent_library.gd`** — replace the existing empty stub:

```gdscript
		&"vanguard":
			return []
```

with the full nested match (6 rows × 3 options):

```gdscript
		&"vanguard":
			match row_id:
				&"base_ability":
					var h1: AbilityTalentOption = AbilityTalentOption.new()
					h1.id = &"heft_reinforced"; h1.row_id = row_id
					h1.display_name = "Reinforced Heft"
					h1.description = "Heft also converts up to 1 NEUTRAL face per reel into SUCCESS."
					var h2: AbilityTalentOption = AbilityTalentOption.new()
					h2.id = &"heft_guarding"; h2.row_id = row_id
					h2.display_name = "Guarding Heft"
					h2.description = "Heft also grants self Guarded (x0.9 incoming damage) for 1 turn."
					var h3: AbilityTalentOption = AbilityTalentOption.new()
					h3.id = &"heft_efficient"; h3.row_id = row_id
					h3.display_name = "Efficient Heft"
					h3.description = "Heft's Stamina cost is reduced to 1 (was 2)."
					return [h1, h2, h3]
				&"ability_l2":
					var b1: AbilityTalentOption = AbilityTalentOption.new()
					b1.id = &"wrath_deeper"; b1.row_id = row_id
					b1.display_name = "Deeper Wrath"
					b1.description = "Bloodwrath's missing-HP scaling increases to +1.2%% per 1%% missing (was +1.0%%), cap raised to +60%% (was +50%%)."
					var b2: AbilityTalentOption = AbilityTalentOption.new()
					b2.id = &"wrath_lasting"; b2.row_id = row_id
					b2.display_name = "Lasting Wrath"
					b2.description = "Bloodwrath's Empowered lasts 3 turns (was 2)."
					var b3: AbilityTalentOption = AbilityTalentOption.new()
					b3.id = &"wrath_efficient"; b3.row_id = row_id
					b3.display_name = "Efficient Wrath"
					b3.description = "Bloodwrath's Stamina cost is reduced to 2 (was 3)."
					return [b1, b2, b3]
				&"ability_l3":
					var q1: AbilityTalentOption = AbilityTalentOption.new()
					q1.id = &"slam_deeper"; q1.row_id = row_id
					q1.display_name = "Deeper Slam"
					q1.description = "Quake Slam's own hit deals +15% bonus damage."
					var q2: AbilityTalentOption = AbilityTalentOption.new()
					q2.id = &"slam_heavier"; q2.row_id = row_id
					q2.display_name = "Heavier Slam"
					q2.description = "Quake Slam applies 2 stacks of Slow at once (was 1)."
					var q3: AbilityTalentOption = AbilityTalentOption.new()
					q3.id = &"slam_efficient"; q3.row_id = row_id
					q3.display_name = "Efficient Slam"
					q3.description = "Quake Slam's Stamina cost is reduced to 3 (was 4)."
					return [q1, q2, q3]
				&"ability_l4":
					var m1: AbilityTalentOption = AbilityTalentOption.new()
					m1.id = &"stance_deeper"; m1.row_id = row_id
					m1.display_name = "Deeper Stance"
					m1.description = "Mountain Stance's incoming-damage multiplier improves to x0.4 (was x0.5)."
					var m2: AbilityTalentOption = AbilityTalentOption.new()
					m2.id = &"stance_thorned"; m2.row_id = row_id
					m2.display_name = "Thorned Stance"
					m2.description = "Mountain Stance also grants 15% Thorns for its duration."
					var m3: AbilityTalentOption = AbilityTalentOption.new()
					m3.id = &"stance_swift"; m3.row_id = row_id
					m3.display_name = "Swift Stance"
					m3.description = "Mountain Stance's cooldown is reduced to 3 turns (was 4)."
					return [m1, m2, m3]
				&"passive":
					var k1: AbilityTalentOption = AbilityTalentOption.new()
					k1.id = &"bulwark_deeper"; k1.row_id = row_id
					k1.display_name = "Reinforced Bulwark"
					k1.description = "Bulwark's incoming-damage reduction improves to -25% (was -15%)."
					var k2: AbilityTalentOption = AbilityTalentOption.new()
					k2.id = &"bulwark_wider"; k2.row_id = row_id
					k2.display_name = "Wider Bulwark"
					k2.description = "Bulwark's HP threshold moves to 60% (was 50%)."
					var k3: AbilityTalentOption = AbilityTalentOption.new()
					k3.id = &"bulwark_thorned"; k3.row_id = row_id
					k3.display_name = "Thorned Bulwark"
					k3.description = "While Bulwark is active, attackers also take 10% Thorns."
					return [k1, k2, k3]
				&"ultimate":
					var r1: AbilityTalentOption = AbilityTalentOption.new()
					r1.id = &"rampage_deeper"; r1.row_id = row_id
					r1.display_name = "Deeper Rampage"
					r1.description = "Rampage's added reel deals +15% bonus damage."
					var r2: AbilityTalentOption = AbilityTalentOption.new()
					r2.id = &"rampage_slowing"; r2.row_id = row_id
					r2.display_name = "Slowing Rampage"
					r2.description = "Every enemy hit during Rampage is also Slowed 1 stack."
					var r3: AbilityTalentOption = AbilityTalentOption.new()
					r3.id = &"rampage_lasting"; r3.row_id = row_id
					r3.display_name = "Lasting Rampage"
					r3.description = "Rampage's AoE window lasts 2 spins instead of 1."
					return [r1, r2, r3]
				_:
					return []
```

**(b) `combat/combatant.gd` — `apply_heft()`**, change from:

```gdscript
func apply_heft(cost: int, conversions: int = 3) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	_heft_turn_reels(conversions)
	return true
```

to:

```gdscript
func apply_heft(cost: int, conversions: int = 3) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	_heft_turn_reels(conversions)
	if has_ability_talent(&"heft_guarding"):
		var guard: Effect = EffectLibrary.make(&"guarded")
		guard.magnitude = 0.9
		guard.duration = 1
		attach_effect(guard)
	return true
```

**(c) `combat/combatant.gd` — `_heft_turn_reels()`**, change from:

```gdscript
func _heft_turn_reels(conversions: int) -> void:
	for i: int in range(turn_reels.size()):
		var reel: ActionReel = turn_reels[i].duplicate(true)  # deep: its own faces
		var done: int = 0
		for tier: ReelFace.ResultTier in [ReelFace.ResultTier.FAILURE, ReelFace.ResultTier.CRIT_FAILURE]:
			if done >= conversions:
				break
			for face: ReelFace in reel.faces:
				if done >= conversions:
					break
				if face.result_tier == tier:
					face.result_tier = ReelFace.ResultTier.SUCCESS
					face.multiplier = 1.0
					done += 1
		turn_reels[i] = reel
```

to:

```gdscript
func _heft_turn_reels(conversions: int) -> void:
	# Vanguard "Reinforced Heft" talent (Task 16): checked here, in the SHARED helper, not just
	# apply_heft() — so it also applies when Heft is baked into Rampage (fire_rampage() calls this
	# same method), consistent with the established "Rampage bakes in Heft" rule (2026-06-26). A
	# deliberate, consistent bonus, not an oversight (same reasoning Task 15 used for
	# rend_deeper_cut/rend_lasting_wound amplifying Wild-triggered Bleed stacks).
	var convert_neutral: bool = has_ability_talent(&"heft_reinforced")
	for i: int in range(turn_reels.size()):
		var reel: ActionReel = turn_reels[i].duplicate(true)  # deep: its own faces
		var done: int = 0
		for tier: ReelFace.ResultTier in [ReelFace.ResultTier.FAILURE, ReelFace.ResultTier.CRIT_FAILURE]:
			if done >= conversions:
				break
			for face: ReelFace in reel.faces:
				if done >= conversions:
					break
				if face.result_tier == tier:
					face.result_tier = ReelFace.ResultTier.SUCCESS
					face.multiplier = 1.0
					done += 1
		if convert_neutral:
			var neutral_done: int = 0
			for face: ReelFace in reel.faces:
				if neutral_done >= 1:
					break
				if face.result_tier == ReelFace.ResultTier.NEUTRAL:
					face.result_tier = ReelFace.ResultTier.SUCCESS
					face.multiplier = 1.0
					neutral_done += 1
		turn_reels[i] = reel
```

**(d) `combat/combatant.gd` — `bloodwrath_bonus_pct()` + `apply_bloodwrath()`**, change from:

```gdscript
static func bloodwrath_bonus_pct(missing_pct: float) -> float:
	return minf(missing_pct * 1.0, 0.50)

## Vanguard "Bloodwrath" (L5): self-cast Empowered scaling with missing HP% — a high-risk
## juggernaut buff. [ASSUMPTION] scaling, see bloodwrath_bonus_pct().
func apply_bloodwrath(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	var missing_pct: float = 1.0 - (float(hp) / float(maxi(max_hp, 1)))
	var bonus: float = bloodwrath_bonus_pct(missing_pct)
	var e: Effect = EffectLibrary.make(&"empowered")
	e.magnitude = 1.0 + bonus
	attach_effect(e)
	return true
```

to (new optional `scale`/`cap` params default to the exact old constants, so every pre-existing
single-arg call site keeps compiling and passing unchanged):

```gdscript
static func bloodwrath_bonus_pct(missing_pct: float, scale: float = 1.0, cap: float = 0.50) -> float:
	return minf(missing_pct * scale, cap)

## Vanguard "Bloodwrath" (L5): self-cast Empowered scaling with missing HP% — a high-risk
## juggernaut buff. [ASSUMPTION] scaling, see bloodwrath_bonus_pct().
func apply_bloodwrath(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	var missing_pct: float = 1.0 - (float(hp) / float(maxi(max_hp, 1)))
	var scale: float = 1.2 if has_ability_talent(&"wrath_deeper") else 1.0
	var cap: float = 0.60 if has_ability_talent(&"wrath_deeper") else 0.50
	var bonus: float = bloodwrath_bonus_pct(missing_pct, scale, cap)
	var e: Effect = EffectLibrary.make(&"empowered")
	e.magnitude = 1.0 + bonus
	if has_ability_talent(&"wrath_lasting"):
		e.duration = 3
	attach_effect(e)
	return true
```

**(e) `combat/combatant.gd` — `try_quake_slam()`**, change from:

```gdscript
func try_quake_slam(type: DamageType, cost: int, cap: int) -> bool:
	if turn_reels.size() >= cap:
		return false
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	turn_reels.append(ActionReel.make_rider_attack(type, &"slow"))
	return true
```

to:

```gdscript
func try_quake_slam(type: DamageType, cost: int, cap: int) -> bool:
	if turn_reels.size() >= cap:
		return false
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	var reel: ActionReel = ActionReel.make_rider_attack(type, &"slow")
	if has_ability_talent(&"slam_deeper"):
		# +15% bonus damage on Quake Slam's own hit — scaled directly on THIS reel's face
		# multipliers, not the generic rider_talent_bonus_damage_pct hook: Vanguard's Crushing weapon
		# ALSO carries an inherent &"slow" rider on an ordinary crit-success (DESIGN.md §4.6), so a
		# hook keyed only by rider_id can't distinguish "Quake Slam's hit" from a plain weapon crit
		# for this class (see this task's Implementation note).
		for face: ReelFace in reel.faces:
			face.multiplier *= 1.15
	if has_ability_talent(&"slam_heavier"):
		# Flags THIS reel (same collision reason as above) so combat.gd's rider-attach site attaches
		# a 2nd stack of Slow immediately on a hit.
		reel.talent_extra_rider_stack = true
	turn_reels.append(reel)
	return true
```

**(f) `combat/combatant.gd` — `apply_mountain_stance()`**, change from:

```gdscript
func apply_mountain_stance(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	var guard: Effect = EffectLibrary.make(&"guarded")
	guard.magnitude = 0.5
	guard.duration = 4
	guard.immune_effect_ids = [&"slow", &"rooted"]
	guard.grants_stun_immunity = true
	attach_effect(guard)
	var taunt: Effect = EffectLibrary.make(&"taunt")
	taunt.duration = 4
	attach_effect(taunt)
	return true
```

to:

```gdscript
func apply_mountain_stance(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	var guard: Effect = EffectLibrary.make(&"guarded")
	guard.magnitude = 0.4 if has_ability_talent(&"stance_deeper") else 0.5
	guard.duration = 4
	guard.immune_effect_ids = [&"slow", &"rooted"]
	guard.grants_stun_immunity = true
	if has_ability_talent(&"stance_thorned"):
		guard.thorns_pct = 0.15  # same single-instance pattern as apply_bastion()'s thorns_pct bake-on
	attach_effect(guard)
	var taunt: Effect = EffectLibrary.make(&"taunt")
	taunt.duration = 4
	attach_effect(taunt)
	return true
```

**(g) `combat/combatant.gd` — `passive_incoming_multiplier()`**, change the `&"bulwark":` arm from
(the file already has Task 15's `&"last_stand":` arm right after it — untouched here):

```gdscript
	match passive_ability_id:
		&"bulwark":
			return 0.85 if (float(hp) / float(maxi(max_hp, 1))) > 0.50 else 1.0
		&"last_stand":
			if not has_ability_talent(&"stand_guarded"):
				return 1.0
			return 0.9 if (float(hp) / float(maxi(max_hp, 1))) <= 0.30 else 1.0
		_:
			return 1.0
```

to:

```gdscript
	match passive_ability_id:
		&"bulwark":
			var threshold: float = 0.60 if has_ability_talent(&"bulwark_wider") else 0.50
			var reduction: float = 0.75 if has_ability_talent(&"bulwark_deeper") else 0.85
			# NOTE (flagged, not silently reworded — see this task's Implementation note): the
			# approved design table reads "Bulwark's HP threshold 50%->60% (active more often)", but
			# this arm's condition is `> threshold` (the reduction is active while HEALTHY), so
			# raising the threshold to 60% actually NARROWS the active range — the opposite of "more
			# often." Implemented literally to the approved number; flag to the player at the next
			# playtest checkpoint.
			return reduction if (float(hp) / float(maxi(max_hp, 1))) > threshold else 1.0
		&"last_stand":
			if not has_ability_talent(&"stand_guarded"):
				return 1.0
			return 0.9 if (float(hp) / float(maxi(max_hp, 1))) <= 0.30 else 1.0
		_:
			return 1.0
```

**(h) `combat/combatant.gd` — `thorns_pct()`**, change from:

```gdscript
func thorns_pct() -> float:
	var best: float = 0.0
	for e: Effect in active_effects:
		if e != null and e.thorns_pct > best:
			best = e.thorns_pct
	return best
```

to:

```gdscript
func thorns_pct() -> float:
	var best: float = 0.0
	for e: Effect in active_effects:
		if e != null and e.thorns_pct > best:
			best = e.thorns_pct
	# Vanguard "Thorned Bulwark" talent (Task 16): Bulwark itself is a live HP%-computed passive with
	# no attached Effect to carry a thorns_pct field (unlike Mountain Stance/Bastion's Guarded
	# instance), so this is checked here directly. Shares Bulwark's "passive" row with
	# bulwark_wider/bulwark_deeper (cap 1 pick/row), so this always uses the base 50% threshold
	# regardless of bulwark_wider's own threshold change.
	if class_id == &"vanguard" and passive_ability_id == &"bulwark" and has_ability_talent(&"bulwark_thorned"):
		if (float(hp) / float(maxi(max_hp, 1))) > 0.50 and 0.10 > best:
			best = 0.10
	return best
```

**(i) `combat/combatant.gd` — `fire_rampage()`**, change from:

```gdscript
func fire_rampage(extra_reel_type: DamageType, conversions: int, spins: int) -> bool:
	if bonus_meter == null or not bonus_meter.is_armed():
		return false
	bonus_meter.consume()
	turn_reels.append(ActionReel.make_default(extra_reel_type))  # +1 attack reel for the Rampage turn
	_heft_turn_reels(conversions)                                # Heft bonus on every reel (incl. the new one)
	aoe_spins_remaining = spins
	return true
```

to:

```gdscript
func fire_rampage(extra_reel_type: DamageType, conversions: int, spins: int) -> bool:
	if bonus_meter == null or not bonus_meter.is_armed():
		return false
	bonus_meter.consume()
	var extra_reel: ActionReel = ActionReel.make_default(extra_reel_type)
	if has_ability_talent(&"rampage_deeper"):
		# +15% bonus damage on Rampage's OWN added reel specifically — scaled directly on this
		# reel's face multipliers (Rampage isn't a rider-carrying ability, so the generic
		# rider_talent_bonus_damage_pct hook doesn't apply — see this task's Implementation note).
		for face: ReelFace in extra_reel.faces:
			face.multiplier *= 1.15
	turn_reels.append(extra_reel)  # +1 attack reel for the Rampage turn
	_heft_turn_reels(conversions)  # Heft bonus on every reel (incl. the new one)
	aoe_spins_remaining = spins
	return true
```

**(j) `combat/combatant.gd` — the 2 shared dispatch methods that need a Vanguard arm.** Change each
from its post-Task-15 state:

```gdscript
func ability_talent_cost_delta(ability_id: StringName) -> int:
	match class_id:
		&"warrior":
			match ability_id:
				&"rend":
					return -1 if has_ability_talent(&"rend_efficient") else 0
				&"sundering_strike":
					return -1 if has_ability_talent(&"sunder_efficient") else 0
				_:
					return 0
		_:
			return 0
```

to:

```gdscript
func ability_talent_cost_delta(ability_id: StringName) -> int:
	match class_id:
		&"warrior":
			match ability_id:
				&"rend":
					return -1 if has_ability_talent(&"rend_efficient") else 0
				&"sundering_strike":
					return -1 if has_ability_talent(&"sunder_efficient") else 0
				_:
					return 0
		&"vanguard":
			match ability_id:
				&"heft":
					return -1 if has_ability_talent(&"heft_efficient") else 0
				&"bloodwrath":
					return -1 if has_ability_talent(&"wrath_efficient") else 0
				&"quake_slam":
					return -1 if has_ability_talent(&"slam_efficient") else 0
				_:
					return 0
		_:
			return 0
```

```gdscript
func ability_talent_cooldown_delta(ability_id: StringName) -> int:
	match class_id:
		&"warrior":
			match ability_id:
				&"second_wind":
					return -1 if has_ability_talent(&"wind_swift") else 0
				_:
					return 0
		_:
			return 0
```

to:

```gdscript
func ability_talent_cooldown_delta(ability_id: StringName) -> int:
	match class_id:
		&"warrior":
			match ability_id:
				&"second_wind":
					return -1 if has_ability_talent(&"wind_swift") else 0
				_:
					return 0
		&"vanguard":
			match ability_id:
				&"mountain_stance":
					return -1 if has_ability_talent(&"stance_swift") else 0
				_:
					return 0
		_:
			return 0
```

(`apply_rider_talent_adjustments()` and `rider_talent_bonus_damage_pct()` get **no** `&"vanguard":`
arm — both stay exactly at their Task-14 stub for this class; see the Implementation note.)

**(k) `combat/resources/action_reel.gd`**, add right after the existing `bonus_vs_cc` field:

```gdscript
## True only for the Vanguard's Quake Slam reel when its "Heavier Slam" Ability Talent is picked
## (Task 16): the orchestrator attaches a SECOND stack of this reel's rider effect immediately on a
## hit, rather than the usual single stack. Scoped to this one reel instance (not a generic per-
## rider-id talent hook) because Vanguard's own Crushing weapon shares Quake Slam's &"slow" rider id
## on an ordinary crit-success — a hook keyed only by rider_id can't distinguish the two for this
## class (see this task's Implementation note). False for every other reel.
@export var talent_extra_rider_stack: bool = false
```

**(l) `combat/combat.gd` — the rider-attach block (post-Task-14, already calling
`apply_rider_talent_adjustments`)**, change from:

```gdscript
	if attack.rider_effect_id != &"":
		for t: Combatant in targets:
			var rider: Effect = EffectLibrary.make(attack.rider_effect_id)
			if rider != null:
				if rider.kind == Effect.Kind.DAMAGE_OVER_TIME and _attacker.weapon != null:
					rider.dot_base_damage = _attacker.weapon_effective_base_damage()
				_attacker.apply_rider_talent_adjustments(attack.rider_effect_id, rider, t)
				t.attach_effect(rider)
				_log("  %s is afflicted with %s (%d turns)." % [t.display_name, String(rider.id).to_upper(), rider.duration])
				(_panels[t] as CombatantPanel).refresh_status()
				(_panels[t] as CombatantPanel).refresh_initiative()
		_turn_order_bar.set_order(_turn_manager.get_turn_order())
```

to:

```gdscript
	if attack.rider_effect_id != &"":
		for t: Combatant in targets:
			var rider: Effect = EffectLibrary.make(attack.rider_effect_id)
			if rider != null:
				if rider.kind == Effect.Kind.DAMAGE_OVER_TIME and _attacker.weapon != null:
					rider.dot_base_damage = _attacker.weapon_effective_base_damage()
				_attacker.apply_rider_talent_adjustments(attack.rider_effect_id, rider, t)
				t.attach_effect(rider)
				if attack.source_reel != null and attack.source_reel.talent_extra_rider_stack:
					# Vanguard "Heavier Slam" talent (Task 16): attach_effect() merges by id (the
					# same stacking-debuff primitive every multi-stack debuff already uses), so
					# calling it again with the same `rider` reference reads as "2 stacks landed at
					# once" from Quake Slam's own single hit, not a duplicate/competing instance.
					t.attach_effect(rider)
				_log("  %s is afflicted with %s (%d turns)." % [t.display_name, String(rider.id).to_upper(), rider.duration])
				(_panels[t] as CombatantPanel).refresh_status()
				(_panels[t] as CombatantPanel).refresh_initiative()
		_turn_order_bar.set_order(_turn_manager.get_turn_order())
```

And change the bonus_vs_cc / `rider_talent_bonus_damage_pct` block (post-Task-14) from:

```gdscript
			if attack.source_reel != null and attack.source_reel.bonus_vs_cc:
				if t.has_effect(&"slow") or t.has_effect(&"rooted") or t.stunned_last_turn:
					var bonus: int = ceili(attack.final_damage * 0.5)
					t.take_damage(bonus)
					_log("  🎯 Crippling Shot exploits %s's condition for %d bonus damage." % [t.display_name, bonus])
			if attack.rider_effect_id != &"":
				var talent_bonus_pct: float = _attacker.rider_talent_bonus_damage_pct(attack.rider_effect_id)
				if talent_bonus_pct > 0.0:
					var talent_bonus: int = ceili(attack.final_damage * talent_bonus_pct)
					t.take_damage(talent_bonus)
					_log("  ✦ %s's talent adds %d bonus damage." % [_attacker.display_name, talent_bonus])
```

to (unchanged, plus one new block immediately after it, still inside the same
`for t: Combatant in targets:` loop, still inside `if attack.final_damage > 0:`):

```gdscript
			if attack.source_reel != null and attack.source_reel.bonus_vs_cc:
				if t.has_effect(&"slow") or t.has_effect(&"rooted") or t.stunned_last_turn:
					var bonus: int = ceili(attack.final_damage * 0.5)
					t.take_damage(bonus)
					_log("  🎯 Crippling Shot exploits %s's condition for %d bonus damage." % [t.display_name, bonus])
			if attack.rider_effect_id != &"":
				var talent_bonus_pct: float = _attacker.rider_talent_bonus_damage_pct(attack.rider_effect_id)
				if talent_bonus_pct > 0.0:
					var talent_bonus: int = ceili(attack.final_damage * talent_bonus_pct)
					t.take_damage(talent_bonus)
					_log("  ✦ %s's talent adds %d bonus damage." % [_attacker.display_name, talent_bonus])
			# Vanguard "Slowing Rampage" talent (Task 16): any hit landed while Rampage's AoE window
			# is active also lashes the target with a stack of Slow — mirrors Task 15's Warrior
			# "Bleeding Wild" block (is_aoe_active() is only true during Rampage's own spin(s)).
			if _attacker.class_id == &"vanguard" and _attacker.has_ability_talent(&"rampage_slowing") and _attacker.is_aoe_active():
				t.attach_effect(EffectLibrary.make(&"slow"))
				_log("  🐌 %s's RAMPAGE lashes %s with a stack of SLOW." % [_attacker.display_name, t.display_name])
				(_panels[t] as CombatantPanel).refresh_status()
```

**(m) `combat/main_phase_plan.gd` — `commit()`'s `&"rampage":` arm**, change:

```gdscript
			&"rampage":
				combatant.fire_rampage(combatant.weapon_type(), RAMPAGE_CONVERSIONS, RAMPAGE_SPINS)
```

to:

```gdscript
			&"rampage":
				# Vanguard "Lasting Rampage" talent (Task 16): the AoE window lasts 2 spins instead of 1.
				var spins: int = (RAMPAGE_SPINS + 1) if combatant.has_ability_talent(&"rampage_lasting") else RAMPAGE_SPINS
				combatant.fire_rampage(combatant.weapon_type(), RAMPAGE_CONVERSIONS, spins)
```

**(n) `combat/ui/ability_menu_panel.gd` — `_dynamic_suffix()`**, change from:

```gdscript
static func _dynamic_suffix(id: StringName, c: Combatant) -> String:
	if id == &"bloodwrath" and c != null:
		var missing_pct: float = 1.0 - (float(c.hp) / float(maxi(c.max_hp, 1)))
		var bonus_pct: float = Combatant.bloodwrath_bonus_pct(missing_pct) * 100.0
		return " At your current HP (%d/%d), this grants +%.0f%% damage." % [c.hp, c.max_hp, bonus_pct]
	return ""
```

to:

```gdscript
static func _dynamic_suffix(id: StringName, c: Combatant) -> String:
	if id == &"bloodwrath" and c != null:
		var missing_pct: float = 1.0 - (float(c.hp) / float(maxi(c.max_hp, 1)))
		# Vanguard "Deeper Wrath" talent (Task 16): keep the live tooltip in sync with
		# apply_bloodwrath()'s own scale/cap so the two can never drift apart.
		var scale: float = 1.2 if c.has_ability_talent(&"wrath_deeper") else 1.0
		var cap: float = 0.60 if c.has_ability_talent(&"wrath_deeper") else 0.50
		var bonus_pct: float = Combatant.bloodwrath_bonus_pct(missing_pct, scale, cap) * 100.0
		return " At your current HP (%d/%d), this grants +%.0f%% damage." % [c.hp, c.max_hp, bonus_pct]
	return ""
```

- [ ] **Step 4: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_vanguard.gd`
Expected: all lines print `ok:`.

- [ ] **Step 5: Run the full test suite**

Run every `tests/test_*.gd` file headlessly and confirm exit code 0 for each. The 3 known
pre-existing failures (see Global Constraints) are NOT regressions. Any other nonzero exit is a
real regression and must be root-caused before committing — pay particular attention to
`tests/test_bloodwrath.gd` (the `bloodwrath_bonus_pct()` signature gained 2 optional params) and
anything exercising `ability_menu_panel.gd`'s Bloodwrath tooltip.

- [ ] **Step 6: Commit**

```bash
git add combat/ability_talent_library.gd combat/combatant.gd combat/resources/action_reel.gd combat/combat.gd combat/main_phase_plan.gd combat/ui/ability_menu_panel.gd tests/test_ability_talents_vanguard.gd
git commit -m "feat(talents): Vanguard Ability Talents — 18 options across Heft/Bloodwrath/Quake Slam/Mountain Stance/Bulwark/Rampage"
```

---

## Task 17: Skirmisher Ability Talents (18 options)

> **Implementation note (not a reworded option — all 18 options below are implemented exactly as
> approved):** `try_splice_reel()` (Flurry's own method) is called from exactly one place —
> `main_phase_plan.gd`'s `&"flurry":` arm — so `flurry_deeper`/`flurry_hastening` are checked
> directly inside it with no `class_id` guard needed, the same convention Task 15/16 already used
> for single-caller methods like `apply_heroic_guard()`/`apply_heft()`. `opportunist_charging` is the
> one option this class needs a NEW orchestrator-level check for: Opportunist is a passive outgoing-
> damage multiplier, not a rider, so neither of Task 14's generic per-rider-id hooks
> (`apply_rider_talent_adjustments`/`rider_talent_bonus_damage_pct`) apply. It's wired directly into
> `combat.gd`'s existing Bonus-Meter-charge block in `_apply_attack()`, reusing the exact
> `_defender` reference that block's own damage math already used this spin (`combat.gd`'s
> `dmg_mult = _attacker.outgoing_damage_multiplier(_defender) * ...`, line ~1736) — mirrors Task
> 15/16's Bleeding Wild/Slowing Rampage precedent of a class-specific check added directly at the
> one orchestrator site that needs it, not a new shared dispatch method.

**Files:**
- Modify: `combat/ability_talent_library.gd` (fills in the `&"skirmisher":` branch of `options_for()`)
- Modify: `combat/combatant.gd` (`try_splice_reel()`, `apply_feint_riposte()`, `apply_quickstep()`,
  `fire_riposte_storm()`, `passive_outgoing_multiplier()`'s `&"opportunist":` arm, `fire_sticky_wild()`,
  and the 2 shared dispatch methods that need a `&"skirmisher":` arm)
- Modify: `combat/combat.gd` (`_apply_attack()`'s Bonus-Meter-charge block gains the
  `opportunist_charging` check)
- Modify: `combat/main_phase_plan.gd` (`commit()`'s `&"sticky_wild":` arm gains the `sticky_lasting`
  spin-count branch)
- Test: `tests/test_ability_talents_skirmisher.gd` (new)

**Interfaces:**
- Consumes: Task 14's `Combatant.class_id` / `ability_talent_picks` / `has_ability_talent()` /
  `pick_ability_talent()` / `ability_talent_cost_delta()` / `ability_talent_cooldown_delta()`
  scaffolds, and `AbilityTalentLibrary.options_for()`'s empty `&"skirmisher":` stub. Also consumes
  the existing `EffectLibrary`/`MainPhasePlan` infrastructure: `try_splice_reel`, `apply_feint_riposte`,
  `apply_quickstep`, `fire_riposte_storm`, `fire_sticky_wild`, `gain_riposte_charges`,
  `bonus_meter.add_flat()` (the exact primitive the Chancer's House Edge passive already uses), and
  the `&"haste"`/`&"evasion"`/`&"empowered"`/`&"weakened"`/`&"slow"`/`&"rooted"` `EffectLibrary` entries.
- Produces: 18 populated `AbilityTalentOption` entries for Skirmisher across all 6 rows; talent-aware
  Flurry/Feint & Riposte/Quickstep/Riposte Storm/Opportunist/Sticky Wild behavior.
  `apply_rider_talent_adjustments()` and `rider_talent_bonus_damage_pct()` get **no** Skirmisher arm
  at all — both stay at their Task-14 stub for this class (none of Skirmisher's 18 options are
  rider-shaped; Flurry's added reel is a plain `make_default()` weapon-attack reel, not a
  rider-carrying one).

- [ ] **Step 1: Write the failing test**

Create `tests/test_ability_talents_skirmisher.gd`:

```gdscript
extends SceneTree

# Headless test: the Skirmisher's 18 Ability Talent options (Task 17) — one row of 3 mutually-
# exclusive picks per Skirmisher ability (Flurry / Feint & Riposte / Quickstep / Riposte Storm /
# Opportunist / Sticky Wild). Exercises AbilityTalentLibrary.options_for(&"skirmisher", row_id),
# pick_ability_talent()/has_ability_talent(), the cost/cooldown-delta dispatch methods, and the
# reel-instance-scoped flurry_deeper option (mirrors Task 16's slam_deeper/rampage_deeper precedent).
#
# Charging Opportunist's ACTUAL on-hit Bonus Meter charge lives in combat.gd's _apply_attack() —
# orchestrator-level, requires a running Combat scene — and is NOT headlessly tested here, consistent
# with this codebase's own documented precedent (tests/test_ability_talents_warrior.gd's header
# comment on Bleeding Wild). This test instead proves the precondition state combat.gd's wiring reads.
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_skirmisher.gd

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _mk_skirmisher() -> Combatant:
	var c: Combatant = ClassLibrary.make(&"skirmisher").build_combatant(true)
	c.level = Combatant.MAX_LEVEL  # unlocks every talent row (5/6/7/8/9/10)
	c.resource_pool.stamina = 20
	c.begin_turn()  # populates turn_reels from the 4-reel Slashing Twin Daggers
	return c

func _test_options_for_shape() -> void:
	var rows: Array[StringName] = [&"base_ability", &"ability_l2", &"ability_l3", &"ability_l4", &"passive", &"ultimate"]
	var all_ids: Array[StringName] = [
		&"flurry_deeper", &"flurry_hastening", &"flurry_efficient",
		&"feint_deeper", &"feint_lasting", &"feint_efficient",
		&"step_deeper", &"step_evasive", &"step_efficient",
		&"storm_deeper", &"storm_lasting", &"storm_swift",
		&"opportunist_deeper", &"opportunist_wider", &"opportunist_charging",
		&"sticky_deeper", &"sticky_hastening", &"sticky_lasting",
	]
	var seen: Array[StringName] = []
	for row: StringName in rows:
		var opts: Array[AbilityTalentOption] = AbilityTalentLibrary.options_for(&"skirmisher", row)
		_check(opts.size() == 3, "Skirmisher row %s has exactly 3 options (got %d)" % [row, opts.size()])
		for o: AbilityTalentOption in opts:
			_check(o.row_id == row, "option %s reports its own row_id (%s)" % [o.id, row])
			_check(o.display_name != "" and o.description != "", "option %s has a non-empty display_name/description" % o.id)
			seen.append(o.id)
	for id: StringName in all_ids:
		_check(id in seen, "option %s is present in AbilityTalentLibrary.options_for(&skirmisher, ...)" % id)

func _test_flurry_row() -> void:
	var c: Combatant = _mk_skirmisher()
	_check(c.ability_talent_cost_delta(&"flurry") == 0, "no Flurry cost delta with nothing picked")
	_check(c.pick_ability_talent(&"base_ability", &"flurry_efficient"), "picks flurry_efficient")
	_check(c.ability_talent_cost_delta(&"flurry") == -1, "flurry_efficient: Flurry costs 1 less Stamina")

	var c2: Combatant = _mk_skirmisher()
	_check(c2.pick_ability_talent(&"base_ability", &"flurry_deeper"), "picks flurry_deeper")
	_check(c2.try_splice_reel(c2.weapon_type(), c2.weapon_effective_base_damage(), 2, 5), "casts Flurry (deeper)")
	var reel: ActionReel = c2.turn_reels[c2.turn_reels.size() - 1]
	var checked_success: bool = false
	var checked_crit: bool = false
	for face: ReelFace in reel.faces:
		if face.result_tier == ReelFace.ResultTier.SUCCESS:
			_check(is_equal_approx(face.multiplier, 1.10), "flurry_deeper: SUCCESS face multiplier is 1.10 (got %.3f)" % face.multiplier)
			checked_success = true
		elif face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
			_check(is_equal_approx(face.multiplier, 2.20), "flurry_deeper: CRIT_SUCCESS face multiplier is 2.20 (got %.3f)" % face.multiplier)
			checked_crit = true
	_check(checked_success and checked_crit, "sanity: both hit tiers exist on the spliced reel to check")
	_check(reel.is_weapon_attack, "sanity: Flurry's added reel stays a weapon-attack reel (payline-eligible)")

	var c3: Combatant = _mk_skirmisher()
	_check(c3.try_splice_reel(c3.weapon_type(), c3.weapon_effective_base_damage(), 2, 5), "casts Flurry (baseline)")
	var reel3: ActionReel = c3.turn_reels[c3.turn_reels.size() - 1]
	for face3: ReelFace in reel3.faces:
		if face3.result_tier == ReelFace.ResultTier.SUCCESS:
			_check(is_equal_approx(face3.multiplier, 1.0), "baseline Flurry: SUCCESS multiplier stays 1.0 (got %.3f)" % face3.multiplier)

	var c4: Combatant = _mk_skirmisher()
	_check(c4.pick_ability_talent(&"base_ability", &"flurry_hastening"), "picks flurry_hastening")
	_check(c4.try_splice_reel(c4.weapon_type(), c4.weapon_effective_base_damage(), 2, 5), "casts Flurry (hastening)")
	var haste: Effect = c4._find_effect(&"haste")
	_check(haste != null, "flurry_hastening: Haste attached")
	_check(haste.duration == 1, "flurry_hastening: Haste lasts 1 turn (got %d)" % haste.duration)

	# Mutual exclusion: only 1 pick per row.
	var c5: Combatant = _mk_skirmisher()
	_check(c5.pick_ability_talent(&"base_ability", &"flurry_efficient"), "first pick on the Flurry row succeeds")
	_check(not c5.pick_ability_talent(&"base_ability", &"flurry_deeper"), "a second pick on an already-filled row is rejected (cap of 1/row)")
	_check(c5.has_ability_talent(&"flurry_efficient"), "the row's original pick is still active")

func _test_feint_riposte_row() -> void:
	var c: Combatant = _mk_skirmisher()
	_check(c.ability_talent_cost_delta(&"feint_riposte") == 0, "no Feint & Riposte cost delta with nothing picked")
	_check(c.pick_ability_talent(&"ability_l2", &"feint_efficient"), "picks feint_efficient")
	_check(c.ability_talent_cost_delta(&"feint_riposte") == -1, "feint_efficient: Feint & Riposte costs 1 less Stamina")

	var c2: Combatant = _mk_skirmisher()
	_check(c2.apply_feint_riposte(3), "casts Feint & Riposte (baseline)")
	var e: Effect = c2._find_effect(&"evasion")
	var t: Effect = c2._find_effect(&"taunt")
	_check(e != null and e.duration == 3, "baseline Feint & Riposte: Evasion lasts 3 turns (got %s)" % (str(e.duration) if e != null else "null"))
	_check(t != null and t.duration == 3, "baseline Feint & Riposte: Taunt lasts 3 turns (got %s)" % (str(t.duration) if t != null else "null"))
	_check(c2.riposte_charges == 0, "baseline Feint & Riposte grants no immediate riposte charge")

	var c3: Combatant = _mk_skirmisher()
	_check(c3.pick_ability_talent(&"ability_l2", &"feint_lasting"), "picks feint_lasting")
	_check(c3.apply_feint_riposte(3), "casts Feint & Riposte (lasting)")
	var e3: Effect = c3._find_effect(&"evasion")
	var t3: Effect = c3._find_effect(&"taunt")
	_check(e3.duration == 4, "feint_lasting: Evasion lasts 4 turns (got %d)" % e3.duration)
	_check(t3.duration == 4, "feint_lasting: Taunt lasts 4 turns too (got %d)" % t3.duration)

	var c4: Combatant = _mk_skirmisher()
	_check(c4.pick_ability_talent(&"ability_l2", &"feint_deeper"), "picks feint_deeper")
	_check(c4.riposte_charges == 0, "sanity: no riposte charges before casting")
	_check(c4.apply_feint_riposte(3), "casts Feint & Riposte (deeper)")
	_check(c4.riposte_charges == 1, "feint_deeper: grants +1 riposte charge immediately (got %d)" % c4.riposte_charges)

func _test_quickstep_row() -> void:
	var c: Combatant = _mk_skirmisher()
	_check(c.ability_talent_cost_delta(&"quickstep") == 0, "no Quickstep cost delta with nothing picked")
	_check(c.pick_ability_talent(&"ability_l3", &"step_efficient"), "picks step_efficient")
	_check(c.ability_talent_cost_delta(&"quickstep") == -1, "step_efficient: Quickstep costs 1 less Stamina")

	var c2: Combatant = _mk_skirmisher()
	_check(c2.apply_quickstep(3), "casts Quickstep (baseline)")
	var h: Effect = c2._find_effect(&"haste")
	_check(is_equal_approx(h.magnitude, 20.0), "baseline Quickstep: Haste magnitude is +20 Initiative (got %.1f)" % h.magnitude)
	_check(not c2.has_effect(&"evasion"), "baseline Quickstep grants no Evasion")

	var c3: Combatant = _mk_skirmisher()
	_check(c3.pick_ability_talent(&"ability_l3", &"step_deeper"), "picks step_deeper")
	_check(c3.apply_quickstep(3), "casts Quickstep (deeper)")
	var h3: Effect = c3._find_effect(&"haste")
	_check(is_equal_approx(h3.magnitude, 30.0), "step_deeper: Haste magnitude is +30 Initiative (got %.1f)" % h3.magnitude)

	var c4: Combatant = _mk_skirmisher()
	_check(c4.pick_ability_talent(&"ability_l3", &"step_evasive"), "picks step_evasive")
	_check(c4.apply_quickstep(3), "casts Quickstep (evasive)")
	var e4: Effect = c4._find_effect(&"evasion")
	_check(e4 != null, "step_evasive: Evasion attached")
	_check(e4.duration == 1, "step_evasive: Evasion lasts 1 turn (got %d)" % e4.duration)

func _test_riposte_storm_row() -> void:
	var c: Combatant = _mk_skirmisher()
	_check(c.ability_talent_cooldown_delta(&"riposte_storm") == 0, "no Riposte Storm cooldown delta with nothing picked")
	_check(c.pick_ability_talent(&"ability_l4", &"storm_swift"), "picks storm_swift")
	_check(c.ability_talent_cooldown_delta(&"riposte_storm") == -1, "storm_swift: Riposte Storm cooldown is 1 less turn")

	var c2: Combatant = _mk_skirmisher()
	c2.riposte_charges = 4
	_check(c2.fire_riposte_storm(4), "fires Riposte Storm (baseline, 4 charges)")
	var emp: Effect = c2._find_effect(&"empowered")
	_check(is_equal_approx(emp.magnitude, 1.60), "baseline Riposte Storm: 1.0 + 0.15*4 = 1.60 (got %.3f)" % emp.magnitude)
	_check(emp.duration == 1, "baseline Riposte Storm: Empowered lasts 1 turn (got %d)" % emp.duration)
	_check(c2.riposte_charges == 0, "sanity: charges reset to 0 after firing")

	var c3: Combatant = _mk_skirmisher()
	c3.riposte_charges = 4
	_check(c3.pick_ability_talent(&"ability_l4", &"storm_deeper"), "picks storm_deeper")
	_check(c3.fire_riposte_storm(4), "fires Riposte Storm (deeper, 4 charges)")
	var emp3: Effect = c3._find_effect(&"empowered")
	_check(is_equal_approx(emp3.magnitude, 1.80), "storm_deeper: 1.0 + 0.20*4 = 1.80 (got %.3f)" % emp3.magnitude)

	var c4: Combatant = _mk_skirmisher()
	_check(c4.pick_ability_talent(&"ability_l4", &"storm_lasting"), "picks storm_lasting")
	_check(c4.fire_riposte_storm(4), "fires Riposte Storm (lasting)")
	var emp4: Effect = c4._find_effect(&"empowered")
	_check(emp4.duration == 2, "storm_lasting: Empowered lasts 2 turns (got %d)" % emp4.duration)

func _test_opportunist_row() -> void:
	var c: Combatant = _mk_skirmisher()
	c.passive_ability_id = &"opportunist"
	var slowed: Combatant = _mk_skirmisher()
	slowed.attach_effect(EffectLibrary.make(&"slow"))
	_check(is_equal_approx(c.passive_outgoing_multiplier(slowed), 1.15), "baseline Opportunist: +15% vs a Slowed defender")

	var c2: Combatant = _mk_skirmisher()
	c2.passive_ability_id = &"opportunist"
	_check(c2.pick_ability_talent(&"passive", &"opportunist_deeper"), "picks opportunist_deeper")
	_check(is_equal_approx(c2.passive_outgoing_multiplier(slowed), 1.25), "opportunist_deeper: +25% vs a Slowed defender (got %.3f)" % c2.passive_outgoing_multiplier(slowed))

	var c3: Combatant = _mk_skirmisher()
	c3.passive_ability_id = &"opportunist"
	var weakened: Combatant = _mk_skirmisher()
	weakened.attach_effect(EffectLibrary.make(&"weakened"))
	_check(is_equal_approx(c3.passive_outgoing_multiplier(weakened), 1.0), "sanity: baseline Opportunist does NOT trigger vs a merely-Weakened defender")
	_check(c3.pick_ability_talent(&"passive", &"opportunist_wider"), "picks opportunist_wider")
	_check(is_equal_approx(c3.passive_outgoing_multiplier(weakened), 1.15), "opportunist_wider: now also triggers vs a Weakened defender (got %.3f)" % c3.passive_outgoing_multiplier(weakened))

	# Charging Opportunist's ACTUAL on-hit meter charge lives in combat.gd's _apply_attack() — see
	# the file header comment above. This proves the precondition state combat.gd's wiring reads:
	# the pick itself, and that passive_outgoing_multiplier(defender) > 1.0 is genuinely readable as
	# "did Opportunist just trigger" for that check to use.
	var c4: Combatant = _mk_skirmisher()
	c4.passive_ability_id = &"opportunist"
	_check(c4.pick_ability_talent(&"passive", &"opportunist_charging"), "picks opportunist_charging")
	_check(c4.has_ability_talent(&"opportunist_charging"), "has_ability_talent sees opportunist_charging")
	_check(c4.passive_outgoing_multiplier(slowed) > 1.0, "opportunist_charging precondition: passive_outgoing_multiplier(defender) > 1.0 vs a Slowed defender")

func _test_sticky_wild_row() -> void:
	var c: Combatant = _mk_skirmisher()
	c.bonus_meter.value = c.bonus_meter.cap
	_check(c.fire_sticky_wild(c.weapon.reels.size(), 2), "fires Sticky Wild (baseline)")
	_check(not c.has_effect(&"empowered"), "baseline Sticky Wild grants no Empowered")
	_check(not c.has_effect(&"haste"), "baseline Sticky Wild grants no Haste")

	var c2: Combatant = _mk_skirmisher()
	c2.bonus_meter.value = c2.bonus_meter.cap
	_check(c2.pick_ability_talent(&"ultimate", &"sticky_deeper"), "picks sticky_deeper")
	_check(c2.fire_sticky_wild(c2.weapon.reels.size(), 2), "fires Sticky Wild (deeper)")
	var emp: Effect = c2._find_effect(&"empowered")
	_check(emp != null, "sticky_deeper: Empowered attached")
	_check(is_equal_approx(emp.magnitude, 1.15), "sticky_deeper: Empowered is x1.15 (got %.3f)" % emp.magnitude)
	_check(emp.duration == 2, "sticky_deeper: Empowered lasts the same 2 spins as the wild itself (got %d)" % emp.duration)

	var c3: Combatant = _mk_skirmisher()
	c3.bonus_meter.value = c3.bonus_meter.cap
	_check(c3.pick_ability_talent(&"ultimate", &"sticky_hastening"), "picks sticky_hastening")
	_check(c3.fire_sticky_wild(c3.weapon.reels.size(), 2), "fires Sticky Wild (hastening)")
	var haste: Effect = c3._find_effect(&"haste")
	_check(haste != null, "sticky_hastening: Haste attached")
	_check(haste.duration == 2, "sticky_hastening: Haste lasts the same 2 spins as the wild itself (got %d)" % haste.duration)

	var c4: Combatant = _mk_skirmisher()
	c4.bonus_meter.value = c4.bonus_meter.cap
	var plan: MainPhasePlan = MainPhasePlan.new(c4)
	_check(plan.ultimate_id == &"sticky_wild", "sanity: Skirmisher's Ultimate id is &sticky_wild")
	plan.toggle_ultimate()
	_check(plan.fire_ultimate_staged, "Sticky Wild ultimate stages when the meter is armed")
	plan.commit()
	_check(c4.sticky_wild_spins_remaining == 2, "without Lasting Sticky Wild, firing it grants 2 spins (got %d)" % c4.sticky_wild_spins_remaining)

	var c5: Combatant = _mk_skirmisher()
	c5.bonus_meter.value = c5.bonus_meter.cap
	_check(c5.pick_ability_talent(&"ultimate", &"sticky_lasting"), "picks sticky_lasting")
	var plan2: MainPhasePlan = MainPhasePlan.new(c5)
	plan2.toggle_ultimate()
	plan2.commit()
	_check(c5.sticky_wild_spins_remaining == 3, "sticky_lasting: firing Sticky Wild grants 3 spins (got %d)" % c5.sticky_wild_spins_remaining)

func _init() -> void:
	_test_options_for_shape()
	_test_flurry_row()
	_test_feint_riposte_row()
	_test_quickstep_row()
	_test_riposte_storm_row()
	_test_opportunist_row()
	_test_sticky_wild_row()
	print(("SKIRMISHER ABILITY TALENTS TEST PASSED" if _failures == 0 else "SKIRMISHER ABILITY TALENTS TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_skirmisher.gd`
Expected: FAIL on essentially every check — `AbilityTalentLibrary.options_for(&"skirmisher", ...)` still returns `[]`.

- [ ] **Step 3: Implement**

**(a) `combat/ability_talent_library.gd`** — replace the existing empty stub:

```gdscript
		&"skirmisher":
			return []
```

with the full nested match (6 rows × 3 options):

```gdscript
		&"skirmisher":
			match row_id:
				&"base_ability":
					var f1: AbilityTalentOption = AbilityTalentOption.new()
					f1.id = &"flurry_deeper"; f1.row_id = row_id
					f1.display_name = "Deeper Flurry"
					f1.description = "Flurry's added reel deals +10% bonus damage."
					var f2: AbilityTalentOption = AbilityTalentOption.new()
					f2.id = &"flurry_hastening"; f2.row_id = row_id
					f2.display_name = "Hastening Flurry"
					f2.description = "Flurry also grants self Haste for 1 turn."
					var f3: AbilityTalentOption = AbilityTalentOption.new()
					f3.id = &"flurry_efficient"; f3.row_id = row_id
					f3.display_name = "Efficient Flurry"
					f3.description = "Flurry's Stamina cost is reduced to 1 (was 2)."
					return [f1, f2, f3]
				&"ability_l2":
					var r1: AbilityTalentOption = AbilityTalentOption.new()
					r1.id = &"feint_deeper"; r1.row_id = row_id
					r1.display_name = "Deeper Feint"
					r1.description = "Feint & Riposte grants +1 riposte charge immediately on cast."
					var r2: AbilityTalentOption = AbilityTalentOption.new()
					r2.id = &"feint_lasting"; r2.row_id = row_id
					r2.display_name = "Lasting Feint"
					r2.description = "Feint & Riposte's Evasion and Taunt last 4 turns (was 3)."
					var r3: AbilityTalentOption = AbilityTalentOption.new()
					r3.id = &"feint_efficient"; r3.row_id = row_id
					r3.display_name = "Efficient Feint"
					r3.description = "Feint & Riposte's Stamina cost is reduced to 2 (was 3)."
					return [r1, r2, r3]
				&"ability_l3":
					var s1: AbilityTalentOption = AbilityTalentOption.new()
					s1.id = &"step_deeper"; s1.row_id = row_id
					s1.display_name = "Deeper Quickstep"
					s1.description = "Quickstep's Haste grants +30 Initiative (was +20)."
					var s2: AbilityTalentOption = AbilityTalentOption.new()
					s2.id = &"step_evasive"; s2.row_id = row_id
					s2.display_name = "Evasive Quickstep"
					s2.description = "Quickstep also grants 1 turn of Evasion."
					var s3: AbilityTalentOption = AbilityTalentOption.new()
					s3.id = &"step_efficient"; s3.row_id = row_id
					s3.display_name = "Efficient Quickstep"
					s3.description = "Quickstep's Stamina cost is reduced to 2 (was 3)."
					return [s1, s2, s3]
				&"ability_l4":
					var t1: AbilityTalentOption = AbilityTalentOption.new()
					t1.id = &"storm_deeper"; t1.row_id = row_id
					t1.display_name = "Deeper Storm"
					t1.description = "Riposte Storm's per-charge scaling increases to +20% (was +15%)."
					var t2: AbilityTalentOption = AbilityTalentOption.new()
					t2.id = &"storm_lasting"; t2.row_id = row_id
					t2.display_name = "Lasting Storm"
					t2.description = "Riposte Storm's Empowered lasts 2 turns (was 1)."
					var t3: AbilityTalentOption = AbilityTalentOption.new()
					t3.id = &"storm_swift"; t3.row_id = row_id
					t3.display_name = "Swift Storm"
					t3.description = "Riposte Storm's cooldown is reduced to 2 turns (was 3)."
					return [t1, t2, t3]
				&"passive":
					var p1: AbilityTalentOption = AbilityTalentOption.new()
					p1.id = &"opportunist_deeper"; p1.row_id = row_id
					p1.display_name = "Ruthless Opportunist"
					p1.description = "Opportunist's damage bonus increases to +25% (was +15%)."
					var p2: AbilityTalentOption = AbilityTalentOption.new()
					p2.id = &"opportunist_wider"; p2.row_id = row_id
					p2.display_name = "Wider Opportunist"
					p2.description = "Opportunist's trigger also includes a Weakened defender."
					var p3: AbilityTalentOption = AbilityTalentOption.new()
					p3.id = &"opportunist_charging"; p3.row_id = row_id
					p3.display_name = "Charging Opportunist"
					p3.description = "Landing a hit via Opportunist also grants +1 flat Bonus Meter charge."
					return [p1, p2, p3]
				&"ultimate":
					var u1: AbilityTalentOption = AbilityTalentOption.new()
					u1.id = &"sticky_deeper"; u1.row_id = row_id
					u1.display_name = "Deeper Sticky Wild"
					u1.description = "Sticky Wild also grants self Empowered (x1.15 outgoing damage) for its duration."
					var u2: AbilityTalentOption = AbilityTalentOption.new()
					u2.id = &"sticky_hastening"; u2.row_id = row_id
					u2.display_name = "Hastening Wild"
					u2.description = "Casting Sticky Wild also grants self Haste for its duration."
					var u3: AbilityTalentOption = AbilityTalentOption.new()
					u3.id = &"sticky_lasting"; u3.row_id = row_id
					u3.display_name = "Lasting Sticky Wild"
					u3.description = "Sticky Wild's crit bias lasts 3 spins instead of 2."
					return [u1, u2, u3]
				_:
					return []
```

**(b) `combat/combatant.gd` — `try_splice_reel()`**, change from:

```gdscript
func try_splice_reel(type: DamageType, base_damage: float, cost: int, cap: int) -> bool:
	if turn_reels.size() >= cap:
		return false
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	turn_reels.append(ActionReel.make_default(type))
	return true
```

to:

```gdscript
func try_splice_reel(type: DamageType, base_damage: float, cost: int, cap: int) -> bool:
	if turn_reels.size() >= cap:
		return false
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	var reel: ActionReel = ActionReel.make_default(type)
	if has_ability_talent(&"flurry_deeper"):
		# Skirmisher "Deeper Flurry" talent (Task 17): +10% bonus damage on Flurry's own added reel —
		# scaled directly on this reel's face multipliers, mirroring Vanguard's rampage_deeper
		# precedent (Task 16), since this is a plain make_default() weapon-attack reel with no
		# rider_effect_id for a generic talent hook to key off.
		for face: ReelFace in reel.faces:
			face.multiplier *= 1.10
	turn_reels.append(reel)
	if has_ability_talent(&"flurry_hastening"):
		var haste: Effect = EffectLibrary.make(&"haste")
		haste.duration = 1
		attach_effect(haste)
	return true
```

**(c) `combat/combatant.gd` — `apply_feint_riposte()`**, change from:

```gdscript
func apply_feint_riposte(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	var evasion: Effect = EffectLibrary.make(&"evasion")
	evasion.duration = 3
	attach_effect(evasion)
	var taunt: Effect = EffectLibrary.make(&"taunt")
	taunt.duration = 3
	attach_effect(taunt)
	return true
```

to:

```gdscript
func apply_feint_riposte(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	var dur: int = 4 if has_ability_talent(&"feint_lasting") else 3
	var evasion: Effect = EffectLibrary.make(&"evasion")
	evasion.duration = dur
	attach_effect(evasion)
	var taunt: Effect = EffectLibrary.make(&"taunt")
	taunt.duration = dur
	attach_effect(taunt)
	if has_ability_talent(&"feint_deeper"):
		gain_riposte_charges(1)
	return true
```

**(d) `combat/combatant.gd` — `apply_quickstep()`**, change from:

```gdscript
func apply_quickstep(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	var haste: Effect = EffectLibrary.make(&"haste")
	haste.duration = 3
	attach_effect(haste)
	return true
```

to:

```gdscript
func apply_quickstep(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	var haste: Effect = EffectLibrary.make(&"haste")
	haste.duration = 3
	if has_ability_talent(&"step_deeper"):
		haste.magnitude = 30.0
	attach_effect(haste)
	if has_ability_talent(&"step_evasive"):
		var evasion: Effect = EffectLibrary.make(&"evasion")
		evasion.duration = 1
		attach_effect(evasion)
	return true
```

**(e) `combat/combatant.gd` — `fire_riposte_storm()`**, change from:

```gdscript
func fire_riposte_storm(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	var e: Effect = EffectLibrary.make(&"empowered")
	e.magnitude = 1.0 + 0.15 * mini(riposte_charges, 5)
	e.duration = 1
	attach_effect(e)
	riposte_charges = 0
	return true
```

to:

```gdscript
func fire_riposte_storm(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	var per_charge: float = 0.20 if has_ability_talent(&"storm_deeper") else 0.15
	var e: Effect = EffectLibrary.make(&"empowered")
	e.magnitude = 1.0 + per_charge * mini(riposte_charges, 5)
	e.duration = 2 if has_ability_talent(&"storm_lasting") else 1
	attach_effect(e)
	riposte_charges = 0
	return true
```

**(f) `combat/combatant.gd` — `passive_outgoing_multiplier()`**, change the `&"opportunist":` arm (the
file already has Task 15's `&"last_stand":` arm right before it, and the existing `&"steady_aim":` arm
right after it — both untouched here) from:

```gdscript
		&"opportunist":
			if defender == null:
				return 1.0
			return 1.15 if (defender.has_effect(&"slow") or defender.has_effect(&"rooted") or defender.stunned_last_turn) else 1.0
```

to:

```gdscript
		&"opportunist":
			if defender == null:
				return 1.0
			var triggered: bool = defender.has_effect(&"slow") or defender.has_effect(&"rooted") or defender.stunned_last_turn
			if has_ability_talent(&"opportunist_wider"):
				triggered = triggered or defender.has_effect(&"weakened")
			if not triggered:
				return 1.0
			return 1.25 if has_ability_talent(&"opportunist_deeper") else 1.15
```

**(g) `combat/combatant.gd` — `fire_sticky_wild()`** (post-Task-15 state, which already added the
Warrior `wild_truer` branch)**, change from:

```gdscript
func fire_sticky_wild(reel_count: int, spins: int) -> bool:
	if bonus_meter == null or not bonus_meter.is_armed():
		return false
	bonus_meter.consume()
	sticky_wild_count = reel_count
	sticky_wild_spins_remaining = spins
	if class_id == &"warrior" and has_ability_talent(&"wild_truer"):
		var empowered: Effect = EffectLibrary.make(&"empowered")
		empowered.magnitude = 1.15
		empowered.duration = spins
		attach_effect(empowered)
	return true
```

to:

```gdscript
func fire_sticky_wild(reel_count: int, spins: int) -> bool:
	if bonus_meter == null or not bonus_meter.is_armed():
		return false
	bonus_meter.consume()
	sticky_wild_count = reel_count
	sticky_wild_spins_remaining = spins
	if class_id == &"warrior" and has_ability_talent(&"wild_truer"):
		var empowered: Effect = EffectLibrary.make(&"empowered")
		empowered.magnitude = 1.15
		empowered.duration = spins
		attach_effect(empowered)
	if class_id == &"skirmisher" and has_ability_talent(&"sticky_deeper"):
		var empowered2: Effect = EffectLibrary.make(&"empowered")
		empowered2.magnitude = 1.15
		empowered2.duration = spins
		attach_effect(empowered2)
	if class_id == &"skirmisher" and has_ability_talent(&"sticky_hastening"):
		var haste: Effect = EffectLibrary.make(&"haste")
		haste.duration = spins
		attach_effect(haste)
	return true
```

**(h) `combat/combatant.gd` — the 2 shared dispatch methods that need a Skirmisher arm.** Change each
from its post-Task-16 state:

```gdscript
func ability_talent_cost_delta(ability_id: StringName) -> int:
	match class_id:
		&"warrior":
			match ability_id:
				&"rend":
					return -1 if has_ability_talent(&"rend_efficient") else 0
				&"sundering_strike":
					return -1 if has_ability_talent(&"sunder_efficient") else 0
				_:
					return 0
		&"vanguard":
			match ability_id:
				&"heft":
					return -1 if has_ability_talent(&"heft_efficient") else 0
				&"bloodwrath":
					return -1 if has_ability_talent(&"wrath_efficient") else 0
				&"quake_slam":
					return -1 if has_ability_talent(&"slam_efficient") else 0
				_:
					return 0
		_:
			return 0
```

to:

```gdscript
func ability_talent_cost_delta(ability_id: StringName) -> int:
	match class_id:
		&"warrior":
			match ability_id:
				&"rend":
					return -1 if has_ability_talent(&"rend_efficient") else 0
				&"sundering_strike":
					return -1 if has_ability_talent(&"sunder_efficient") else 0
				_:
					return 0
		&"vanguard":
			match ability_id:
				&"heft":
					return -1 if has_ability_talent(&"heft_efficient") else 0
				&"bloodwrath":
					return -1 if has_ability_talent(&"wrath_efficient") else 0
				&"quake_slam":
					return -1 if has_ability_talent(&"slam_efficient") else 0
				_:
					return 0
		&"skirmisher":
			match ability_id:
				&"flurry":
					return -1 if has_ability_talent(&"flurry_efficient") else 0
				&"feint_riposte":
					return -1 if has_ability_talent(&"feint_efficient") else 0
				&"quickstep":
					return -1 if has_ability_talent(&"step_efficient") else 0
				_:
					return 0
		_:
			return 0
```

```gdscript
func ability_talent_cooldown_delta(ability_id: StringName) -> int:
	match class_id:
		&"warrior":
			match ability_id:
				&"second_wind":
					return -1 if has_ability_talent(&"wind_swift") else 0
				_:
					return 0
		&"vanguard":
			match ability_id:
				&"mountain_stance":
					return -1 if has_ability_talent(&"stance_swift") else 0
				_:
					return 0
		_:
			return 0
```

to:

```gdscript
func ability_talent_cooldown_delta(ability_id: StringName) -> int:
	match class_id:
		&"warrior":
			match ability_id:
				&"second_wind":
					return -1 if has_ability_talent(&"wind_swift") else 0
				_:
					return 0
		&"vanguard":
			match ability_id:
				&"mountain_stance":
					return -1 if has_ability_talent(&"stance_swift") else 0
				_:
					return 0
		&"skirmisher":
			match ability_id:
				&"riposte_storm":
					return -1 if has_ability_talent(&"storm_swift") else 0
				_:
					return 0
		_:
			return 0
```

(`apply_rider_talent_adjustments()` and `rider_talent_bonus_damage_pct()` get **no** `&"skirmisher":`
arm — both stay exactly at their Task-14 stub for this class; none of Skirmisher's 18 options are
rider-shaped.)

- [ ] **Step 4a: `combat/combat.gd` — the Bonus-Meter-charge block in `_apply_attack()`**

Change from:

```gdscript
	# Bonus Meter charge (attacker only). Log BM gains for the player (enemy meter is hidden).
	# A non-charging reel (the Warden's Rallying Cry reel) is skipped — its payoff is the party shield.
	if _attacker.bonus_meter != null and attack.charges_meter:
		var before: int = _attacker.bonus_meter.value
		_attacker.bonus_meter.charge(attack.face.result_tier)
		var added: int = _attacker.bonus_meter.value - before
		if added > 0 and _attacker.bonus_meter.is_visible:
			_log("    BM +%d  (%d/%d)" % [added, _attacker.bonus_meter.value, _attacker.bonus_meter.cap])
```

to:

```gdscript
	# Bonus Meter charge (attacker only). Log BM gains for the player (enemy meter is hidden).
	# A non-charging reel (the Warden's Rallying Cry reel) is skipped — its payoff is the party shield.
	if _attacker.bonus_meter != null and attack.charges_meter:
		var before: int = _attacker.bonus_meter.value
		_attacker.bonus_meter.charge(attack.face.result_tier)
		var added: int = _attacker.bonus_meter.value - before
		if added > 0 and _attacker.bonus_meter.is_visible:
			_log("    BM +%d  (%d/%d)" % [added, _attacker.bonus_meter.value, _attacker.bonus_meter.cap])
		# Skirmisher "Charging Opportunist" talent (Task 17): an extra flat +1 charge whenever this
		# hit actually benefited from the Opportunist passive bonus. outgoing_damage_multiplier() is
		# always computed against the PRIMARY defender only (this file's own dmg_mult line, ~1736,
		# "_attacker.outgoing_damage_multiplier(_defender)") — never per-target — so reading
		# passive_outgoing_multiplier(_defender) here reuses the exact same defender the actual damage
		# math used this spin, consistent even under a Rampage-style AoE spin (mirrors this file's own
		# aoe_tag comment on that same primary-defender-only asymmetry). Opportunist isn't a rider, so
		# neither of Task 14's generic per-rider-id hooks apply — this is checked directly here instead,
		# the same way Task 15/16 added Bleeding Wild/Slowing Rampage directly at their own orchestrator
		# sites.
		if attack.final_damage > 0 and _attacker.class_id == &"skirmisher" and _attacker.has_ability_talent(&"opportunist_charging") and _attacker.passive_outgoing_multiplier(_defender) > 1.0:
			_attacker.bonus_meter.add_flat(1)
			_log("    ⚔ Opportunist strikes true — BM +1  (%d/%d)" % [_attacker.bonus_meter.value, _attacker.bonus_meter.cap])
```

- [ ] **Step 4b: `combat/main_phase_plan.gd` — `commit()`'s `&"sticky_wild":` arm**

Change:

```gdscript
			&"sticky_wild":
				combatant.fire_sticky_wild(_weapon_reel_count(), STICKY_WILD_SPINS)  # two spins (Skirmisher)
```

to:

```gdscript
			&"sticky_wild":
				# Skirmisher "Lasting Sticky Wild" talent (Task 17): the crit bias lasts 3 spins instead of 2.
				var spins: int = (STICKY_WILD_SPINS + 1) if combatant.has_ability_talent(&"sticky_lasting") else STICKY_WILD_SPINS
				combatant.fire_sticky_wild(_weapon_reel_count(), spins)  # two spins (Skirmisher), +1 with Lasting Sticky Wild
```

*(Confirm the exact existing line/variable names — `_weapon_reel_count()`/`STICKY_WILD_SPINS` — against
the real file before editing; if named differently, use the real names, the behavior is what matters.)*

- [ ] **Step 5: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_skirmisher.gd`
Expected: all lines print `ok:`.

- [ ] **Step 6: Run the full test suite**

Run every `tests/test_*.gd` file headlessly and confirm exit code 0 for each. 3 known pre-existing
failures predate this whole effort and are NOT regressions: `test_adventuring_board_panel.gd` (1
internal FAIL line), `test_overworld_demo_npcs.gd` (5), `test_overworld_encounter_variety.gd` (6). Any
OTHER nonzero exit is a real regression and must be root-caused before committing — pay particular
attention to any test exercising the Bonus-Meter-charge block in `combat.gd` (a widely-shared site
every class's every reel passes through) and to `tests/test_ability_talents_warrior.gd`/
`tests/test_ability_talents_vanguard.gd` (confirm the `fire_sticky_wild()`/dispatch-method edits above
didn't disturb their existing Warrior/Vanguard branches).

- [ ] **Step 7: Commit**

```bash
git add combat/ability_talent_library.gd combat/combatant.gd combat/combat.gd combat/main_phase_plan.gd tests/test_ability_talents_skirmisher.gd
git commit -m "feat(talents): Skirmisher Ability Talents — 18 options across Flurry/Feint & Riposte/Quickstep/Riposte Storm/Opportunist/Sticky Wild"
```

---

## Task 18: Chancer Ability Talents (18 options)

> **Implementation / judgment notes (no option required a reword — all 18 below are implemented
> exactly as approved):**
> 1. **`edge_wider`** ("House Edge also triggers on a NEUTRAL-tier utility reel result"): House
>    Edge's existing baseline hook (`passive_on_payline_scored`) already fires on any scored
>    payline, including a NEUTRAL-tier one — so the wording must mean something the baseline doesn't
>    already cover. Chosen reading (per CLAUDE.md §4's own framing — "neutral (utility, no damage,
>    +1 meter)" — NEUTRAL tier itself *is* the "utility" result): **any single reel this Chancer
>    spins that lands NEUTRAL also grants House Edge's flat charge, independent of whether a full
>    payline run forms.** Implemented as one narrowly-scoped block in `combat.gd`'s existing
>    `_apply_attack()` — no shared function touched.
> 2. **`jinx_deeper`/`jinx_lasting`** need no workaround: unlike Vanguard's Quake Slam (Task 16),
>    Jinx the Odds' `&"jinxed"` rider id is unique to this one ability — no other class or passive
>    uses it — so Chancer is simply the first class to populate a real `&"chancer":` arm in BOTH
>    `apply_rider_talent_adjustments()` and `rider_talent_bonus_damage_pct()`, exactly as Task 14
>    intended those hooks to be used.
> 3. `worst_reroll_index()` and `gamble_final_damage()` each gain small optional parameters
>    (mirroring Task 16's `bloodwrath_bonus_pct(scale, cap)` precedent) rather than any new shared
>    abstraction — both keep their single existing call site (`combat.gd`) plus their one
>    pre-existing test file passing unchanged on the new params' defaults.

**Files:**
- Modify: `combat/ability_talent_library.gd` (fills in the `&"chancer":` branch of `options_for()`)
- Modify: `combat/combatant.gd` (`apply_loaded_dice()`, `fire_double_or_nothing()`,
  `passive_on_payline_scored()`, `worst_reroll_index()` [new optional `exclude` param],
  `gamble_final_damage()` [new optional `crit_mult`/`fail_pct` params], new
  `reroll_deeper_damage()` static helper, and the 4 shared dispatch methods gaining a `&"chancer":`
  arm)
- Modify: `combat/combat.gd` (`_apply_post_spin_rerolls()`'s `reroll_pending`/`wildcard_gamble_pending`
  blocks reworked for `reroll_double`/`reroll_deeper`/`wildcard_deeper`/`wildcard_safer`;
  `_apply_attack()` gains the `edge_wider` NEUTRAL-tier check and the `gamble_refunding` double-refund
  line; `_finish_spin()` gains the `wildcard_lucky` refund check)
- Test: `tests/test_ability_talents_chancer.gd` (new)

**Interfaces:**
- Consumes: Task 14's `Combatant.class_id` / `ability_talent_picks` / `has_ability_talent()` /
  `pick_ability_talent()` / `ability_talent_cost_delta()` / `ability_talent_cooldown_delta()` /
  `apply_rider_talent_adjustments()` / `rider_talent_bonus_damage_pct()` scaffolds, and
  `AbilityTalentLibrary.options_for()`'s empty `&"chancer":` stub. Also consumes the existing Chancer
  infrastructure: `stage_reroll`, `refund_reroll`, `apply_loaded_dice`, `try_jinx_the_odds`,
  `fire_double_or_nothing`, `fire_wildcard_gamble`, `passive_on_payline_scored`, `worst_reroll_index`,
  `gamble_final_damage`, `ActionReel.make_gamble`, and the `&"jinxed"`/`&"empowered"` `EffectLibrary`
  entries.
- Produces: 18 populated `AbilityTalentOption` entries for Chancer across all 6 rows; talent-aware
  Re-roll/Loaded Dice/Jinx the Odds/Double or Nothing/House Edge/Wildcard Gamble behavior. Chancer is
  the FIRST class to populate a real `&"chancer":` arm in `apply_rider_talent_adjustments()` AND
  `rider_talent_bonus_damage_pct()` (Warrior/Task 15 populated only the former; Vanguard/Task 16
  populated neither, per its own reel-instance-scoped workaround) — safe here because Jinx the Odds'
  `&"jinxed"` rider id doesn't collide with any other class's rider id (see the notes above).

- [ ] **Step 1: Write the failing test**

Create `tests/test_ability_talents_chancer.gd`:

```gdscript
extends SceneTree

# Headless test: the Chancer's 18 Ability Talent options (Task 18) — one row of 3 mutually-
# exclusive picks per Chancer ability (Re-roll / Loaded Dice / Jinx the Odds / Double or Nothing /
# House Edge / Wildcard Gamble). Exercises AbilityTalentLibrary.options_for(&"chancer", row_id),
# pick_ability_talent()/has_ability_talent(), the cost/cooldown-delta dispatch methods, and the
# GENERIC apply_rider_talent_adjustments()/rider_talent_bonus_damage_pct() hooks (Jinx the Odds'
# &"jinxed" rider id is unique to this ability — unlike Vanguard's Quake Slam, no reel-instance-scoped
# workaround is needed here; see this task's Implementation notes).
#
# reroll_deeper's post-reroll bonus-damage application, reroll_double's/wildcard_gamble's own re-roll
# LOOP, gamble_refunding's per-reel Mana-refund tally, and wildcard_lucky's post-resolve meter refund
# all live in combat.gd's _apply_post_spin_rerolls()/_apply_attack()/_finish_spin() — orchestrator-
# level, requires a running Combat scene — and are NOT headlessly tested here, consistent with this
# codebase's own documented precedent (tests/test_ability_talents_warrior.gd's header comment on
# Bleeding Wild). Where the underlying arithmetic is a genuine pure static helper (reroll_deeper_damage,
# worst_reroll_index's new exclude param, gamble_final_damage's new crit_mult/fail_pct params), this
# test proves that helper directly instead — the actual reusable logic combat.gd's wiring calls.
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_chancer.gd

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _mk_chancer() -> Combatant:
	var c: Combatant = ClassLibrary.make(&"chancer").build_combatant(true)
	c.level = Combatant.MAX_LEVEL  # unlocks every talent row (5/6/7/8/9/10)
	c.resource_pool.mana = c.resource_pool.max_mana
	c.begin_turn()  # populates turn_reels from the 4-reel Storm Sling
	return c

## Mirrors tests/test_reroll_selection.gd's own helper — a bare AttackResult carrying just a tier,
## enough to drive worst_reroll_index()/gamble_final_damage() without a live spin.
func _mk(tier: ReelFace.ResultTier) -> CombatResolver.AttackResult:
	var a: CombatResolver.AttackResult = CombatResolver.AttackResult.new()
	var f: ReelFace = ReelFace.new(); f.result_tier = tier
	a.face = f
	return a

func _count_crit_faces_with_mult(reel: ActionReel, mult: float) -> int:
	var n: int = 0
	for f: ReelFace in reel.faces:
		if f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS and is_equal_approx(f.multiplier, mult):
			n += 1
	return n

func _test_options_for_shape() -> void:
	var rows: Array[StringName] = [&"base_ability", &"ability_l2", &"ability_l3", &"ability_l4", &"passive", &"ultimate"]
	var all_ids: Array[StringName] = [
		&"reroll_deeper", &"reroll_double", &"reroll_efficient",
		&"dice_deeper", &"dice_lucky", &"dice_efficient",
		&"jinx_deeper", &"jinx_lasting", &"jinx_efficient",
		&"gamble_deeper", &"gamble_refunding", &"gamble_swift",
		&"edge_deeper", &"edge_lucky", &"edge_wider",
		&"wildcard_deeper", &"wildcard_safer", &"wildcard_lucky",
	]
	var seen: Array[StringName] = []
	for row: StringName in rows:
		var opts: Array[AbilityTalentOption] = AbilityTalentLibrary.options_for(&"chancer", row)
		_check(opts.size() == 3, "Chancer row %s has exactly 3 options (got %d)" % [row, opts.size()])
		for o: AbilityTalentOption in opts:
			_check(o.row_id == row, "option %s reports its own row_id (%s)" % [o.id, row])
			_check(o.display_name != "" and o.description != "", "option %s has a non-empty display_name/description" % o.id)
			seen.append(o.id)
	for id: StringName in all_ids:
		_check(id in seen, "option %s is present in AbilityTalentLibrary.options_for(&chancer, ...)" % id)

func _test_reroll_row() -> void:
	var c: Combatant = _mk_chancer()
	_check(c.ability_talent_cost_delta(&"reroll") == 0, "no Re-roll cost delta with nothing picked")
	_check(c.pick_ability_talent(&"base_ability", &"reroll_efficient"), "picks reroll_efficient")
	_check(c.ability_talent_cost_delta(&"reroll") == -1, "reroll_efficient: Re-roll costs 1 less Mana")

	# reroll_deeper_damage() is a pure static helper (mirrors bloodwrath_bonus_pct/gamble_final_damage's
	# own static-pure precedent, specifically so it's directly testable) — proves the real +10% math
	# combat.gd's _apply_post_spin_rerolls() calls after a re-roll lands a hit.
	_check(Combatant.reroll_deeper_damage(100) == 110, "reroll_deeper_damage: +10%% bonus damage (got %d)" % Combatant.reroll_deeper_damage(100))
	var c2: Combatant = _mk_chancer()
	_check(c2.pick_ability_talent(&"base_ability", &"reroll_deeper"), "picks reroll_deeper")
	_check(c2.has_ability_talent(&"reroll_deeper"), "has_ability_talent sees reroll_deeper")

	# reroll_double: worst_reroll_index()'s new [param exclude] (Task 18) is the real primitive
	# combat.gd's re-roll loop uses to pick a SECOND reel without re-picking the first.
	var attacks_a: Array = [_mk(ReelFace.ResultTier.CRIT_FAILURE), _mk(ReelFace.ResultTier.FAILURE), _mk(ReelFace.ResultTier.NEUTRAL)]
	_check(Combatant.worst_reroll_index(attacks_a) == 0, "sanity: worst_reroll_index still picks the first crit-fail with no exclusions")
	_check(Combatant.worst_reroll_index(attacks_a, [0]) == 1, "worst_reroll_index skips an excluded index — reroll_double's 2nd pick (got %d)" % Combatant.worst_reroll_index(attacks_a, [0]))
	var c3: Combatant = _mk_chancer()
	_check(c3.pick_ability_talent(&"base_ability", &"reroll_double"), "picks reroll_double")
	_check(c3.has_ability_talent(&"reroll_double"), "has_ability_talent sees reroll_double")

	# Mutual exclusion: only 1 pick per row.
	var c4: Combatant = _mk_chancer()
	_check(c4.pick_ability_talent(&"base_ability", &"reroll_efficient"), "first pick on the Re-roll row succeeds")
	_check(not c4.pick_ability_talent(&"base_ability", &"reroll_deeper"), "a second pick on an already-filled row is rejected (cap of 1/row)")
	_check(c4.has_ability_talent(&"reroll_efficient"), "the row's original pick is still active")

func _test_loaded_dice_row() -> void:
	var c: Combatant = _mk_chancer()
	_check(c.ability_talent_cost_delta(&"loaded_dice") == 0, "no Loaded Dice cost delta with nothing picked")
	_check(c.pick_ability_talent(&"ability_l2", &"dice_efficient"), "picks dice_efficient")
	_check(c.ability_talent_cost_delta(&"loaded_dice") == -1, "dice_efficient: Loaded Dice costs 1 less Mana")

	var c2: Combatant = _mk_chancer()
	_check(_count_crit_faces_with_mult(c2.turn_reels[0], 2.0) == 1, "sanity: a fresh Storm Sling reel has exactly 1 native x2.0 crit face")
	_check(c2.apply_loaded_dice(3), "casts Loaded Dice (baseline)")
	_check(_count_crit_faces_with_mult(c2.turn_reels[0], 2.0) == 2, "baseline Loaded Dice: adds a 2nd x2.0 crit face (got %d)" % _count_crit_faces_with_mult(c2.turn_reels[0], 2.0))

	var c3: Combatant = _mk_chancer()
	_check(c3.pick_ability_talent(&"ability_l2", &"dice_deeper"), "picks dice_deeper")
	_check(c3.apply_loaded_dice(3), "casts Loaded Dice (deeper)")
	_check(_count_crit_faces_with_mult(c3.turn_reels[0], 2.0) == 1, "dice_deeper: the native x2.0 crit face is untouched")
	_check(_count_crit_faces_with_mult(c3.turn_reels[0], 2.25) == 1, "dice_deeper: the ADDED crit face is x2.25 instead (got %d)" % _count_crit_faces_with_mult(c3.turn_reels[0], 2.25))

	var c4: Combatant = _mk_chancer()
	c4.bonus_meter.value = 0
	_check(c4.pick_ability_talent(&"ability_l2", &"dice_lucky"), "picks dice_lucky")
	_check(c4.apply_loaded_dice(3), "casts Loaded Dice (lucky)")
	_check(c4.bonus_meter.value == 1, "dice_lucky: +1 flat Bonus Meter charge on cast (got %d)" % c4.bonus_meter.value)

func _test_jinx_the_odds_row() -> void:
	var c: Combatant = _mk_chancer()
	_check(c.ability_talent_cost_delta(&"jinx_the_odds") == 0, "no Jinx the Odds cost delta with nothing picked")
	_check(c.pick_ability_talent(&"ability_l3", &"jinx_efficient"), "picks jinx_efficient")
	_check(c.ability_talent_cost_delta(&"jinx_the_odds") == -1, "jinx_efficient: Jinx the Odds costs 1 less Mana")

	var c2: Combatant = _mk_chancer()
	_check(c2.pick_ability_talent(&"ability_l3", &"jinx_deeper"), "picks jinx_deeper")
	_check(is_equal_approx(c2.rider_talent_bonus_damage_pct(&"jinxed"), 0.15), "jinx_deeper: +15%% bonus damage on Jinx the Odds' own hit (got %.3f)" % c2.rider_talent_bonus_damage_pct(&"jinxed"))
	_check(is_equal_approx(c2.rider_talent_bonus_damage_pct(&"weakened"), 0.0), "jinx_deeper only applies to the jinxed rider id, not any other")

	var c3: Combatant = _mk_chancer()
	_check(c3.pick_ability_talent(&"ability_l3", &"jinx_lasting"), "picks jinx_lasting")
	var jinxed: Effect = EffectLibrary.make(&"jinxed")
	_check(jinxed.duration == 2, "sanity: Jinxed's baseline duration is 2")
	c3.apply_rider_talent_adjustments(&"jinxed", jinxed, c3)
	_check(jinxed.duration == 3, "jinx_lasting: Jinxed lasts 3 turns (got %d)" % jinxed.duration)

	var c4: Combatant = _mk_chancer()
	_check(c4.try_jinx_the_odds(c4.weapon_type(), 3, 6), "casts Jinx the Odds (sanity: unaffected by talents)")

func _test_double_or_nothing_row() -> void:
	var c: Combatant = _mk_chancer()
	_check(c.ability_talent_cooldown_delta(&"double_or_nothing") == 0, "no Double or Nothing cooldown delta with nothing picked")
	_check(c.pick_ability_talent(&"ability_l4", &"gamble_swift"), "picks gamble_swift")
	_check(c.ability_talent_cooldown_delta(&"double_or_nothing") == -1, "gamble_swift: Double or Nothing's cooldown is 1 less turn")

	var c2: Combatant = _mk_chancer()
	_check(c2.fire_double_or_nothing(c2.weapon_type(), 6), "fires Double or Nothing (baseline)")
	var emp: Effect = c2._find_effect(&"empowered")
	_check(is_equal_approx(emp.magnitude, 2.0), "baseline Double or Nothing: Empowered is x2.0")

	var c3: Combatant = _mk_chancer()
	_check(c3.pick_ability_talent(&"ability_l4", &"gamble_deeper"), "picks gamble_deeper")
	_check(c3.fire_double_or_nothing(c3.weapon_type(), 6), "fires Double or Nothing (deeper)")
	var emp2: Effect = c3._find_effect(&"empowered")
	_check(is_equal_approx(emp2.magnitude, 2.25), "gamble_deeper: Empowered is x2.25 (got %.3f)" % emp2.magnitude)

	# gamble_refunding's actual +1 extra Mana per non-recoil reel is tallied in combat.gd's
	# _apply_attack() per-reel loop — orchestrator-level, NOT headlessly tested here (see this file's
	# header comment).
	var c4: Combatant = _mk_chancer()
	_check(c4.pick_ability_talent(&"ability_l4", &"gamble_refunding"), "picks gamble_refunding")
	_check(c4.has_ability_talent(&"gamble_refunding"), "has_ability_talent sees gamble_refunding")
	_check(c4.fire_double_or_nothing(c4.weapon_type(), 6), "fires Double or Nothing (refunding) — precondition state for combat.gd's wiring")
	_check(c4.double_or_nothing_pending, "Double or Nothing is pending for combat.gd's per-reel refund-accum check to read")

func _test_house_edge_row() -> void:
	var c: Combatant = _mk_chancer()
	c.passive_ability_id = &"house_edge"
	c.bonus_meter.value = 0
	c.passive_on_payline_scored(ReelFace.ResultTier.SUCCESS)
	_check(c.bonus_meter.value == 1, "baseline House Edge: +1 charge on any scored payline (got %d)" % c.bonus_meter.value)

	var c2: Combatant = _mk_chancer()
	c2.passive_ability_id = &"house_edge"
	c2.bonus_meter.value = 0
	_check(c2.pick_ability_talent(&"passive", &"edge_deeper"), "picks edge_deeper")
	c2.passive_on_payline_scored(ReelFace.ResultTier.SUCCESS)
	_check(c2.bonus_meter.value == 2, "edge_deeper: +2 charge on a scored payline (got %d)" % c2.bonus_meter.value)

	# edge_lucky: a genuine 25%% coin flip, not a deterministic branch — checked statistically, the
	# same technique tests/test_ultimate_sticky_wild.gd uses for WILD_CRIT_CHANCE.
	var c3: Combatant = _mk_chancer()
	c3.passive_ability_id = &"house_edge"
	c3.bonus_meter.value = 0
	c3.resource_pool.max_mana = 999
	c3.resource_pool.mana = 0
	_check(c3.pick_ability_talent(&"passive", &"edge_lucky"), "picks edge_lucky")
	var trials: int = 400
	for i: int in range(trials):
		c3.passive_on_payline_scored(ReelFace.ResultTier.SUCCESS)
	var rate: float = float(c3.resource_pool.mana) / float(trials)
	_check(rate >= 0.15 and rate <= 0.35, "edge_lucky: ~25%% of scored paylines also refund 1 Mana (got %.3f)" % rate)

	# edge_wider's actual NEUTRAL-tier-reel trigger lives in combat.gd's _apply_attack() —
	# orchestrator-level, NOT headlessly tested here (see this file's header comment and this task's
	# Implementation notes on the chosen reading of its wording).
	var c4: Combatant = _mk_chancer()
	c4.passive_ability_id = &"house_edge"
	_check(c4.pick_ability_talent(&"passive", &"edge_wider"), "picks edge_wider")
	_check(c4.has_ability_talent(&"edge_wider"), "has_ability_talent sees edge_wider")

	# Mutual exclusion (passive row): only 1 pick per row.
	_check(not c4.pick_ability_talent(&"passive", &"edge_deeper"), "a second pick on an already-filled row is rejected (cap of 1/row)")

func _test_wildcard_gamble_row() -> void:
	var CS := ReelFace.ResultTier.CRIT_SUCCESS
	var F := ReelFace.ResultTier.FAILURE
	var CF := ReelFace.ResultTier.CRIT_FAILURE

	_check(Combatant.gamble_final_damage(CS, 10) == 20, "sanity: baseline gamble_final_damage crit is still x2.0")
	_check(Combatant.gamble_final_damage(CS, 10, 2.25) == 23, "wildcard_deeper: crit reroll multiplies x2.25, rounded up (got %d)" % Combatant.gamble_final_damage(CS, 10, 2.25))

	_check(Combatant.gamble_final_damage(F, 10) == 0, "sanity: baseline gamble_final_damage still zeroes a failed reroll")
	_check(Combatant.gamble_final_damage(F, 10, 2.0, 0.25) == 3, "wildcard_safer: a failed reroll still deals 25%% (ceil, got %d)" % Combatant.gamble_final_damage(F, 10, 2.0, 0.25))
	_check(Combatant.gamble_final_damage(CF, 10, 2.0, 0.25) == 3, "wildcard_safer applies identically to a crit-failed reroll")

	var c: Combatant = _mk_chancer()
	_check(c.pick_ability_talent(&"ultimate", &"wildcard_deeper"), "picks wildcard_deeper")
	_check(c.has_ability_talent(&"wildcard_deeper"), "has_ability_talent sees wildcard_deeper")

	var c2: Combatant = _mk_chancer()
	_check(c2.pick_ability_talent(&"ultimate", &"wildcard_safer"), "picks wildcard_safer")
	_check(c2.has_ability_talent(&"wildcard_safer"), "has_ability_talent sees wildcard_safer")

	# wildcard_lucky's actual +1 Bonus Meter refund lives in combat.gd's _finish_spin() —
	# orchestrator-level, NOT headlessly tested here. This proves fire_wildcard_gamble()'s own
	# precondition state (wildcard_gamble_pending) that _finish_spin's wiring reads.
	var c3: Combatant = _mk_chancer()
	c3.bonus_meter.value = c3.bonus_meter.cap
	_check(c3.pick_ability_talent(&"ultimate", &"wildcard_lucky"), "picks wildcard_lucky")
	_check(c3.fire_wildcard_gamble(), "fires Wildcard Gamble (lucky)")
	_check(c3.wildcard_gamble_pending, "Wildcard Gamble is pending for combat.gd's finish-spin refund check to read")

func _init() -> void:
	_test_options_for_shape()
	_test_reroll_row()
	_test_loaded_dice_row()
	_test_jinx_the_odds_row()
	_test_double_or_nothing_row()
	_test_house_edge_row()
	_test_wildcard_gamble_row()
	print(("CHANCER ABILITY TALENTS TEST PASSED" if _failures == 0 else "CHANCER ABILITY TALENTS TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_chancer.gd`
Expected: FAIL on essentially every check — `AbilityTalentLibrary.options_for(&"chancer", ...)` still returns `[]`, and `reroll_deeper_damage()`/the new optional params don't exist yet.

- [ ] **Step 3: Implement**

**(a) `combat/ability_talent_library.gd`** — replace the existing empty stub:

```gdscript
		&"chancer":
			return []
```

with the full nested match (6 rows × 3 options):

```gdscript
		&"chancer":
			match row_id:
				&"base_ability":
					var rr1: AbilityTalentOption = AbilityTalentOption.new()
					rr1.id = &"reroll_deeper"; rr1.row_id = row_id
					rr1.display_name = "Deeper Re-roll"
					rr1.description = "The re-rolled reel gets +10% bonus damage if it hits."
					var rr2: AbilityTalentOption = AbilityTalentOption.new()
					rr2.id = &"reroll_double"; rr2.row_id = row_id
					rr2.display_name = "Double Re-roll"
					rr2.description = "Re-roll now re-rolls the two worst reels instead of one."
					var rr3: AbilityTalentOption = AbilityTalentOption.new()
					rr3.id = &"reroll_efficient"; rr3.row_id = row_id
					rr3.display_name = "Efficient Re-roll"
					rr3.description = "Re-roll's Mana cost is reduced to 3 (was 4)."
					return [rr1, rr2, rr3]
				&"ability_l2":
					var ld1: AbilityTalentOption = AbilityTalentOption.new()
					ld1.id = &"dice_deeper"; ld1.row_id = row_id
					ld1.display_name = "Loaded Deeper"
					ld1.description = "Loaded Dice's added crit face multiplies x2.25 (was x2.0)."
					var ld2: AbilityTalentOption = AbilityTalentOption.new()
					ld2.id = &"dice_lucky"; ld2.row_id = row_id
					ld2.display_name = "Lucky Dice"
					ld2.description = "Loaded Dice also grants +1 flat Bonus Meter charge on cast."
					var ld3: AbilityTalentOption = AbilityTalentOption.new()
					ld3.id = &"dice_efficient"; ld3.row_id = row_id
					ld3.display_name = "Efficient Dice"
					ld3.description = "Loaded Dice's Mana cost is reduced to 2 (was 3)."
					return [ld1, ld2, ld3]
				&"ability_l3":
					var jo1: AbilityTalentOption = AbilityTalentOption.new()
					jo1.id = &"jinx_deeper"; jo1.row_id = row_id
					jo1.display_name = "Deeper Jinx"
					jo1.description = "Jinx the Odds' own hit deals +15% bonus damage."
					var jo2: AbilityTalentOption = AbilityTalentOption.new()
					jo2.id = &"jinx_lasting"; jo2.row_id = row_id
					jo2.display_name = "Lasting Jinx"
					jo2.description = "Jinxed (from this ability) lasts 3 turns (was 2)."
					var jo3: AbilityTalentOption = AbilityTalentOption.new()
					jo3.id = &"jinx_efficient"; jo3.row_id = row_id
					jo3.display_name = "Efficient Jinx"
					jo3.description = "Jinx the Odds' Mana cost is reduced to 2 (was 3)."
					return [jo1, jo2, jo3]
				&"ability_l4":
					var don1: AbilityTalentOption = AbilityTalentOption.new()
					don1.id = &"gamble_deeper"; don1.row_id = row_id
					don1.display_name = "Deeper Gamble"
					don1.description = "Double or Nothing's Empowered is x2.25 (was x2.0)."
					var don2: AbilityTalentOption = AbilityTalentOption.new()
					don2.id = &"gamble_refunding"; don2.row_id = row_id
					don2.display_name = "Refunding Gamble"
					don2.description = "+1 extra Mana refunded per non-recoil reel."
					var don3: AbilityTalentOption = AbilityTalentOption.new()
					don3.id = &"gamble_swift"; don3.row_id = row_id
					don3.display_name = "Swift Gamble"
					don3.description = "Double or Nothing's cooldown is reduced to 6 turns (was 7)."
					return [don1, don2, don3]
				&"passive":
					var he1: AbilityTalentOption = AbilityTalentOption.new()
					he1.id = &"edge_deeper"; he1.row_id = row_id
					he1.display_name = "Bigger House Edge"
					he1.description = "House Edge's charge increases to +2 (was +1)."
					var he2: AbilityTalentOption = AbilityTalentOption.new()
					he2.id = &"edge_lucky"; he2.row_id = row_id
					he2.display_name = "Lucky Edge"
					he2.description = "House Edge has a 25% chance to also refund 1 Mana."
					var he3: AbilityTalentOption = AbilityTalentOption.new()
					he3.id = &"edge_wider"; he3.row_id = row_id
					he3.display_name = "Wider Edge"
					he3.description = "House Edge also triggers (+1 charge) on any lone NEUTRAL-tier reel result."
					return [he1, he2, he3]
				&"ultimate":
					var wg1: AbilityTalentOption = AbilityTalentOption.new()
					wg1.id = &"wildcard_deeper"; wg1.row_id = row_id
					wg1.display_name = "Deeper Wildcard"
					wg1.description = "A re-rolled crit-success multiplies x2.25 instead of x2.0."
					var wg2: AbilityTalentOption = AbilityTalentOption.new()
					wg2.id = &"wildcard_safer"; wg2.row_id = row_id
					wg2.display_name = "Safer Wildcard"
					wg2.description = "A re-rolled failure deals 25% damage instead of zero."
					var wg3: AbilityTalentOption = AbilityTalentOption.new()
					wg3.id = &"wildcard_lucky"; wg3.row_id = row_id
					wg3.display_name = "Lucky Wildcard"
					wg3.description = "Wildcard Gamble refunds +1 flat Bonus Meter charge after resolving."
					return [wg1, wg2, wg3]
				_:
					return []
```

**(b) `combat/combatant.gd` — `apply_loaded_dice()`**, change from:

```gdscript
func apply_loaded_dice(cost: int) -> bool:
	# Mana, not Stamina — the Chancer moved rails on 2026-07-04 (see class_library.gd).
	if resource_pool == null or not resource_pool.spend({&"mana": cost}):
		return false
	for i: int in range(turn_reels.size()):
		var r: ActionReel = turn_reels[i].duplicate(true)
		var f: ReelFace = ReelFace.new()
		f.result_tier = ReelFace.ResultTier.CRIT_SUCCESS
		f.multiplier = 2.0
		r.faces.append(f)
		r.faces.shuffle()
		turn_reels[i] = r
	loaded_dice_pending = true
	return true
```

to:

```gdscript
func apply_loaded_dice(cost: int) -> bool:
	# Mana, not Stamina — the Chancer moved rails on 2026-07-04 (see class_library.gd).
	if resource_pool == null or not resource_pool.spend({&"mana": cost}):
		return false
	var crit_mult: float = 2.25 if has_ability_talent(&"dice_deeper") else 2.0
	for i: int in range(turn_reels.size()):
		var r: ActionReel = turn_reels[i].duplicate(true)
		var f: ReelFace = ReelFace.new()
		f.result_tier = ReelFace.ResultTier.CRIT_SUCCESS
		f.multiplier = crit_mult
		r.faces.append(f)
		r.faces.shuffle()
		turn_reels[i] = r
	loaded_dice_pending = true
	if has_ability_talent(&"dice_lucky") and bonus_meter != null:
		bonus_meter.add_flat(1)
	return true
```

**(c) `combat/combatant.gd` — `fire_double_or_nothing()`**, change from:

```gdscript
func fire_double_or_nothing(type: DamageType, reel_cap: int) -> bool:
	if resource_pool == null or resource_pool.mana < 1:
		return false
	var cost: int = resource_pool.mana
	resource_pool.spend({&"mana": cost})
	var e: Effect = EffectLibrary.make(&"empowered")
	e.magnitude = 2.0
	e.duration = 1
	attach_effect(e)
	double_or_nothing_pending = true
	double_or_nothing_refund_accum = 0
	# Wild crit-biased spin (playtest 2026-07-04, player-specified 25/10/65 split): converts the
	# EXISTING reels too, not just the 2 bonus ones — a whole-spin effect, matching the ability's
	# original "wild crit biased" framing rather than a partial one.
	turn_reels = gambled_reels(turn_reels)
	for i: int in range(2):
		if turn_reels.size() < reel_cap:
			turn_reels.append(ActionReel.make_gamble(type))
	return true
```

to:

```gdscript
func fire_double_or_nothing(type: DamageType, reel_cap: int) -> bool:
	if resource_pool == null or resource_pool.mana < 1:
		return false
	var cost: int = resource_pool.mana
	resource_pool.spend({&"mana": cost})
	var e: Effect = EffectLibrary.make(&"empowered")
	e.magnitude = 2.25 if has_ability_talent(&"gamble_deeper") else 2.0
	e.duration = 1
	attach_effect(e)
	double_or_nothing_pending = true
	double_or_nothing_refund_accum = 0
	# Wild crit-biased spin (playtest 2026-07-04, player-specified 25/10/65 split): converts the
	# EXISTING reels too, not just the 2 bonus ones — a whole-spin effect, matching the ability's
	# original "wild crit biased" framing rather than a partial one.
	turn_reels = gambled_reels(turn_reels)
	for i: int in range(2):
		if turn_reels.size() < reel_cap:
			turn_reels.append(ActionReel.make_gamble(type))
	return true
```

**(d) `combat/combatant.gd` — `passive_on_payline_scored()`**, change from:

```gdscript
func passive_on_payline_scored(_tier: ReelFace.ResultTier) -> void:
	if level < 5 or passive_ability_id == &"":
		return
	match passive_ability_id:
		&"house_edge":
			if bonus_meter != null:
				bonus_meter.add_flat(1)
		_:
			pass
```

to:

```gdscript
func passive_on_payline_scored(_tier: ReelFace.ResultTier) -> void:
	if level < 5 or passive_ability_id == &"":
		return
	match passive_ability_id:
		&"house_edge":
			if bonus_meter != null:
				bonus_meter.add_flat(2 if has_ability_talent(&"edge_deeper") else 1)
			if has_ability_talent(&"edge_lucky") and resource_pool != null and randf() < 0.25:
				resource_pool.refund({&"mana": 1})
		_:
			pass
```

**(e) `combat/combatant.gd` — `worst_reroll_index()`**, change from:

```gdscript
static func worst_reroll_index(attacks: Array) -> int:
	var priority: Array = [ReelFace.ResultTier.CRIT_FAILURE, ReelFace.ResultTier.FAILURE, ReelFace.ResultTier.NEUTRAL]
	for tier in priority:
		for i: int in range(attacks.size()):
			var a = attacks[i]
			if a != null and a.face != null and a.face.result_tier == tier:
				return i
	return -1
```

to (new optional `exclude` param defaults to `[]`, so every pre-existing single-arg call site — the
production call in `combat.gd` and `tests/test_reroll_selection.gd`'s existing assertions — keeps
compiling and passing unchanged; Chancer "Double Re-roll" (Task 18) is the only caller that ever
passes a non-empty `exclude`):

```gdscript
static func worst_reroll_index(attacks: Array, exclude: Array = []) -> int:
	var priority: Array = [ReelFace.ResultTier.CRIT_FAILURE, ReelFace.ResultTier.FAILURE, ReelFace.ResultTier.NEUTRAL]
	for tier in priority:
		for i: int in range(attacks.size()):
			if i in exclude:
				continue
			var a = attacks[i]
			if a != null and a.face != null and a.face.result_tier == tier:
				return i
	return -1

## Chancer "Deeper Re-roll" talent (Task 18): +10% bonus damage on a post-spin Re-roll reel that
## hits (final_damage > 0). Static + pure (mirrors bloodwrath_bonus_pct/gamble_final_damage's own
## static-pure precedent) so it's directly unit-testable without a live spin. Round-up per project
## convention (memory: round-up-damage-healing).
static func reroll_deeper_damage(final_damage: int) -> int:
	return ceili(final_damage * 1.10)
```

**(f) `combat/combatant.gd` — `gamble_final_damage()`**, change from:

```gdscript
static func gamble_final_damage(rerolled_tier: int, original_final_damage: int) -> int:
	if rerolled_tier == ReelFace.ResultTier.CRIT_SUCCESS:
		return original_final_damage * 2
	if rerolled_tier == ReelFace.ResultTier.FAILURE or rerolled_tier == ReelFace.ResultTier.CRIT_FAILURE:
		return 0
	return original_final_damage
```

to (new optional `crit_mult`/`fail_pct` params default to the exact old constants — `2` and `0` — so
`tests/test_reroll_selection.gd`'s existing 2-arg calls keep compiling and passing unchanged;
Chancer "Deeper Wildcard"/"Safer Wildcard" (Task 18) are the only callers that ever pass non-default
values):

```gdscript
static func gamble_final_damage(rerolled_tier: int, original_final_damage: int, crit_mult: float = 2.0, fail_pct: float = 0.0) -> int:
	if rerolled_tier == ReelFace.ResultTier.CRIT_SUCCESS:
		return ceili(original_final_damage * crit_mult)
	if rerolled_tier == ReelFace.ResultTier.FAILURE or rerolled_tier == ReelFace.ResultTier.CRIT_FAILURE:
		return ceili(original_final_damage * fail_pct)
	return original_final_damage
```

**(g) `combat/combatant.gd` — the 4 shared dispatch methods that need a Chancer arm.** Change each
from its post-Task-17 state (add the `&"chancer":` arm alongside whatever Task 17/Skirmisher already
added — do not disturb the other classes' arms):

```gdscript
func ability_talent_cost_delta(ability_id: StringName) -> int:
	match class_id:
		&"warrior":
			match ability_id:
				&"rend":
					return -1 if has_ability_talent(&"rend_efficient") else 0
				&"sundering_strike":
					return -1 if has_ability_talent(&"sunder_efficient") else 0
				_:
					return 0
		&"vanguard":
			match ability_id:
				&"heft":
					return -1 if has_ability_talent(&"heft_efficient") else 0
				&"bloodwrath":
					return -1 if has_ability_talent(&"wrath_efficient") else 0
				&"quake_slam":
					return -1 if has_ability_talent(&"slam_efficient") else 0
				_:
					return 0
		&"skirmisher":
			match ability_id:
				&"flurry":
					return -1 if has_ability_talent(&"flurry_efficient") else 0
				&"feint_riposte":
					return -1 if has_ability_talent(&"feint_efficient") else 0
				&"quickstep":
					return -1 if has_ability_talent(&"step_efficient") else 0
				_:
					return 0
		_:
			return 0
```

to:

```gdscript
func ability_talent_cost_delta(ability_id: StringName) -> int:
	match class_id:
		&"warrior":
			match ability_id:
				&"rend":
					return -1 if has_ability_talent(&"rend_efficient") else 0
				&"sundering_strike":
					return -1 if has_ability_talent(&"sunder_efficient") else 0
				_:
					return 0
		&"vanguard":
			match ability_id:
				&"heft":
					return -1 if has_ability_talent(&"heft_efficient") else 0
				&"bloodwrath":
					return -1 if has_ability_talent(&"wrath_efficient") else 0
				&"quake_slam":
					return -1 if has_ability_talent(&"slam_efficient") else 0
				_:
					return 0
		&"skirmisher":
			match ability_id:
				&"flurry":
					return -1 if has_ability_talent(&"flurry_efficient") else 0
				&"feint_riposte":
					return -1 if has_ability_talent(&"feint_efficient") else 0
				&"quickstep":
					return -1 if has_ability_talent(&"step_efficient") else 0
				_:
					return 0
		&"chancer":
			match ability_id:
				&"reroll":
					return -1 if has_ability_talent(&"reroll_efficient") else 0
				&"loaded_dice":
					return -1 if has_ability_talent(&"dice_efficient") else 0
				&"jinx_the_odds":
					return -1 if has_ability_talent(&"jinx_efficient") else 0
				_:
					return 0
		_:
			return 0
```

```gdscript
func ability_talent_cooldown_delta(ability_id: StringName) -> int:
	match class_id:
		&"warrior":
			match ability_id:
				&"second_wind":
					return -1 if has_ability_talent(&"wind_swift") else 0
				_:
					return 0
		&"vanguard":
			match ability_id:
				&"mountain_stance":
					return -1 if has_ability_talent(&"stance_swift") else 0
				_:
					return 0
		&"skirmisher":
			match ability_id:
				&"riposte_storm":
					return -1 if has_ability_talent(&"storm_swift") else 0
				_:
					return 0
		_:
			return 0
```

to:

```gdscript
func ability_talent_cooldown_delta(ability_id: StringName) -> int:
	match class_id:
		&"warrior":
			match ability_id:
				&"second_wind":
					return -1 if has_ability_talent(&"wind_swift") else 0
				_:
					return 0
		&"vanguard":
			match ability_id:
				&"mountain_stance":
					return -1 if has_ability_talent(&"stance_swift") else 0
				_:
					return 0
		&"skirmisher":
			match ability_id:
				&"riposte_storm":
					return -1 if has_ability_talent(&"storm_swift") else 0
				_:
					return 0
		&"chancer":
			match ability_id:
				&"double_or_nothing":
					return -1 if has_ability_talent(&"gamble_swift") else 0
				_:
					return 0
		_:
			return 0
```

```gdscript
func apply_rider_talent_adjustments(rider_id: StringName, effect: Effect, target: Combatant) -> void:
	match class_id:
		&"warrior":
			match rider_id:
				&"bleed":
					if has_ability_talent(&"rend_deeper_cut"):
						for i: int in range(effect.dot_fractions.size()):
							effect.dot_fractions[i] *= 1.25
					if has_ability_talent(&"rend_lasting_wound"):
						effect.max_stacks = 4
						if effect.dot_fractions.size() < 4:
							effect.dot_fractions.append(1.55)
				&"sundered":
					if has_ability_talent(&"sunder_deeper"):
						effect.magnitude = 1.35
					if has_ability_talent(&"sunder_lingering"):
						effect.duration = 3
		_:
			pass
```

to (add the Chancer arm alongside Warrior's — Vanguard/Skirmisher deliberately added none here):

```gdscript
func apply_rider_talent_adjustments(rider_id: StringName, effect: Effect, target: Combatant) -> void:
	match class_id:
		&"warrior":
			match rider_id:
				&"bleed":
					if has_ability_talent(&"rend_deeper_cut"):
						for i: int in range(effect.dot_fractions.size()):
							effect.dot_fractions[i] *= 1.25
					if has_ability_talent(&"rend_lasting_wound"):
						effect.max_stacks = 4
						if effect.dot_fractions.size() < 4:
							effect.dot_fractions.append(1.55)
				&"sundered":
					if has_ability_talent(&"sunder_deeper"):
						effect.magnitude = 1.35
					if has_ability_talent(&"sunder_lingering"):
						effect.duration = 3
		&"chancer":
			match rider_id:
				&"jinxed":
					if has_ability_talent(&"jinx_lasting"):
						effect.duration = 3
		_:
			pass
```

```gdscript
func rider_talent_bonus_damage_pct(rider_id: StringName) -> float:
	match class_id:
		_:
			return 0.0
```

to (its Task-14 stub, untouched by Warrior/Vanguard/Skirmisher — Chancer is the first real user):

```gdscript
func rider_talent_bonus_damage_pct(rider_id: StringName) -> float:
	match class_id:
		&"chancer":
			match rider_id:
				&"jinxed":
					return 0.15 if has_ability_talent(&"jinx_deeper") else 0.0
				_:
					return 0.0
		_:
			return 0.0
```

**(h) `combat/combat.gd` — `_apply_post_spin_rerolls()`**, change the `reroll_pending` block from:

```gdscript
	if _attacker.reroll_pending:
		var idx: int = Combatant.worst_reroll_index(attacks)
		if idx >= 0 and idx < reels.size():
			var prev: String = ReelFace.ResultTier.keys()[attacks[idx].face.result_tier]
			attacks[idx] = _resolver.reresolve_reel(reels[idx], base, _defender.defense_type, might)
			changed.append(idx)
			_log("  ♻ %s RE-ROLLS reel %d: was %s → %s." % [_attacker.display_name, idx + 1, prev, ReelFace.ResultTier.keys()[attacks[idx].face.result_tier]])
		else:
			_attacker.refund_reroll()
			_log("  ♻ %s Re-roll: no bad reel to re-roll — %d Stamina refunded." % [_attacker.display_name, _attacker.ability_cost])
			(_panels[_attacker] as CombatantPanel).refresh_resources()
```

to (Chancer "Double Re-roll"/"Deeper Re-roll", Task 18 — identical single-reel behavior/log text when
neither talent is picked):

```gdscript
	if _attacker.reroll_pending:
		var reroll_targets: Array[int] = []
		var first_idx: int = Combatant.worst_reroll_index(attacks)
		if first_idx >= 0 and first_idx < reels.size():
			reroll_targets.append(first_idx)
			if _attacker.has_ability_talent(&"reroll_double"):
				var second_idx: int = Combatant.worst_reroll_index(attacks, [first_idx])
				if second_idx >= 0 and second_idx < reels.size():
					reroll_targets.append(second_idx)
		if reroll_targets.is_empty():
			_attacker.refund_reroll()
			_log("  ♻ %s Re-roll: no bad reel to re-roll — %d Stamina refunded." % [_attacker.display_name, _attacker.ability_cost])
			(_panels[_attacker] as CombatantPanel).refresh_resources()
		else:
			for idx: int in reroll_targets:
				var prev: String = ReelFace.ResultTier.keys()[attacks[idx].face.result_tier]
				attacks[idx] = _resolver.reresolve_reel(reels[idx], base, _defender.defense_type, might)
				if _attacker.has_ability_talent(&"reroll_deeper") and attacks[idx].final_damage > 0:
					attacks[idx].final_damage = Combatant.reroll_deeper_damage(attacks[idx].final_damage)
				changed.append(idx)
				_log("  ♻ %s RE-ROLLS reel %d: was %s → %s." % [_attacker.display_name, idx + 1, prev, ReelFace.ResultTier.keys()[attacks[idx].face.result_tier]])
```

And the `wildcard_gamble_pending` block, from:

```gdscript
	if _attacker.wildcard_gamble_pending:
		for i: int in range(mini(weapon_count, reels.size())):
			if attacks[i].face != null and attacks[i].face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
				continue  # crit reels are not gambled
			var prev_tier: String = ReelFace.ResultTier.keys()[attacks[i].face.result_tier]
			var orig: int = attacks[i].final_damage
			var rolled: CombatResolver.AttackResult = _resolver.reresolve_reel(reels[i], base, _defender.defense_type, might)
			rolled.final_damage = Combatant.gamble_final_damage(rolled.face.result_tier, orig)
			var rolled_tier: String = ReelFace.ResultTier.keys()[rolled.face.result_tier]
			var outcome: String = ("×2" if rolled.face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS else ("lost" if rolled.final_damage == 0 and orig > 0 else "kept"))
			_log("    R%d was %s → gamble → %s (%s)." % [i + 1, prev_tier, rolled_tier, outcome])
			attacks[i] = rolled
			if i not in changed:
				changed.append(i)
		_log("  🎲 %s WILDCARD GAMBLE — every non-crit reel re-rolled (double-or-nothing)!" % _attacker.display_name)
```

to (Chancer Ultimate talents "Deeper Wildcard"/"Safer Wildcard", Task 18):

```gdscript
	if _attacker.wildcard_gamble_pending:
		var crit_mult: float = 2.25 if _attacker.has_ability_talent(&"wildcard_deeper") else 2.0
		var fail_pct: float = 0.25 if _attacker.has_ability_talent(&"wildcard_safer") else 0.0
		for i: int in range(mini(weapon_count, reels.size())):
			if attacks[i].face != null and attacks[i].face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
				continue  # crit reels are not gambled
			var prev_tier: String = ReelFace.ResultTier.keys()[attacks[i].face.result_tier]
			var orig: int = attacks[i].final_damage
			var rolled: CombatResolver.AttackResult = _resolver.reresolve_reel(reels[i], base, _defender.defense_type, might)
			rolled.final_damage = Combatant.gamble_final_damage(rolled.face.result_tier, orig, crit_mult, fail_pct)
			var rolled_tier: String = ReelFace.ResultTier.keys()[rolled.face.result_tier]
			var outcome: String
			if rolled.face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
				outcome = "×%.2f" % crit_mult
			elif rolled.final_damage == 0 and orig > 0:
				outcome = "lost"
			elif rolled.final_damage < orig and orig > 0:
				outcome = "reduced (safer wildcard)"
			else:
				outcome = "kept"
			_log("    R%d was %s → gamble → %s (%s)." % [i + 1, prev_tier, rolled_tier, outcome])
			attacks[i] = rolled
			if i not in changed:
				changed.append(i)
		_log("  🎲 %s WILDCARD GAMBLE — every non-crit reel re-rolled (double-or-nothing)!" % _attacker.display_name)
```

**(i) `combat/combat.gd` — `_apply_attack()`**, the Bonus-Meter-charge block and the Double-or-Nothing
per-reel refund-accum line are stable anchors untouched by Tasks 15-17. Change:

```gdscript
	if _attacker.bonus_meter != null and attack.charges_meter:
		var before: int = _attacker.bonus_meter.value
		_attacker.bonus_meter.charge(attack.face.result_tier)
		var added: int = _attacker.bonus_meter.value - before
		if added > 0 and _attacker.bonus_meter.is_visible:
			_log("    BM +%d  (%d/%d)" % [added, _attacker.bonus_meter.value, _attacker.bonus_meter.cap])
	if attack.rider_effect_id != &"":
```

to (Chancer passive talent "Wider Edge", Task 18 — inserted between the two, still unconditional on
`attack.final_damage`, matching the Bonus-Meter block's own scope; if Task 17's `opportunist_charging`
check already landed inside the Bonus-Meter block by the time this task executes, add this block
immediately after it, not in place of it):

```gdscript
	if _attacker.bonus_meter != null and attack.charges_meter:
		var before: int = _attacker.bonus_meter.value
		_attacker.bonus_meter.charge(attack.face.result_tier)
		var added: int = _attacker.bonus_meter.value - before
		if added > 0 and _attacker.bonus_meter.is_visible:
			_log("    BM +%d  (%d/%d)" % [added, _attacker.bonus_meter.value, _attacker.bonus_meter.cap])
	# Chancer "Wider Edge" talent (Task 18): House Edge's baseline (passive_on_payline_scored) only
	# triggers on a SCORED PAYLINE (a full run across the weapon-attack grid). Once this is picked, a
	# LONE reel landing NEUTRAL also grants House Edge's flat charge without needing to complete a
	# payline — the chosen reading of the approved wording (see this task's Implementation notes:
	# NEUTRAL is itself CLAUDE.md §4's "utility" tier, not a separate reel subtype).
	if attack.face.result_tier == ReelFace.ResultTier.NEUTRAL and _attacker.passive_ability_id == &"house_edge" and _attacker.has_ability_talent(&"edge_wider") and _attacker.bonus_meter != null:
		_attacker.bonus_meter.add_flat(1)
		_log("  🎰 %s's WIDER EDGE triggers — +1 Bonus Meter." % _attacker.display_name)
	if attack.rider_effect_id != &"":
```

And change the Double-or-Nothing refund-accum line, from:

```gdscript
	if _attacker.double_or_nothing_pending:
		if attack.face.result_tier == ReelFace.ResultTier.CRIT_FAILURE:
			_attacker.take_damage(ceili(attack.base_damage))
			_log("  💥 %s's gamble recoils for %d." % [_attacker.display_name, ceili(attack.base_damage)])
		elif attack.face.result_tier != ReelFace.ResultTier.FAILURE:
			_attacker.double_or_nothing_refund_accum += 1
```

to (Chancer "Refunding Gamble", Task 18):

```gdscript
	if _attacker.double_or_nothing_pending:
		if attack.face.result_tier == ReelFace.ResultTier.CRIT_FAILURE:
			_attacker.take_damage(ceili(attack.base_damage))
			_log("  💥 %s's gamble recoils for %d." % [_attacker.display_name, ceili(attack.base_damage)])
		elif attack.face.result_tier != ReelFace.ResultTier.FAILURE:
			_attacker.double_or_nothing_refund_accum += 2 if _attacker.has_ability_talent(&"gamble_refunding") else 1
```

**(j) `combat/combat.gd` — `_finish_spin()`**, change:

```gdscript
	_attacker.clear_reroll_state()  # Chancer reroll/gamble were applied in _do_spin's post-spin pass
```

to (Chancer "Lucky Wildcard", Task 18 — checked BEFORE `clear_reroll_state()` clears
`wildcard_gamble_pending`):

```gdscript
	# Chancer "Lucky Wildcard" talent (Task 18): +1 flat Bonus Meter charge once Wildcard Gamble has
	# fully resolved.
	if _attacker.wildcard_gamble_pending and _attacker.has_ability_talent(&"wildcard_lucky") and _attacker.bonus_meter != null:
		_attacker.bonus_meter.add_flat(1)
		_log("  🍀 %s's Lucky Wildcard refunds +1 Bonus Meter charge." % _attacker.display_name)
	_attacker.clear_reroll_state()  # Chancer reroll/gamble were applied in _do_spin's post-spin pass
```

- [ ] **Step 4: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_chancer.gd`
Expected: all lines print `ok:`.

- [ ] **Step 5: Run the full test suite**

Run every `tests/test_*.gd` file headlessly and confirm exit code 0 for each. Pay particular
attention to `tests/test_reroll_selection.gd` (`worst_reroll_index()`/`gamble_final_damage()` both
gained optional params — its existing 1-arg/2-arg calls must still pass unchanged) and anything
exercising Wildcard Gamble/Double or Nothing/House Edge. The 3 known pre-existing failures predate
this whole effort and are NOT regressions: `test_adventuring_board_panel.gd`, `test_overworld_demo_npcs.gd`,
`test_overworld_encounter_variety.gd`. Any OTHER nonzero exit is a real regression and must be
root-caused before committing.

- [ ] **Step 6: Commit**

```bash
git add combat/ability_talent_library.gd combat/combatant.gd combat/combat.gd tests/test_ability_talents_chancer.gd
git commit -m "feat(talents): Chancer Ability Talents — 18 options across Re-roll/Loaded Dice/Jinx the Odds/Double or Nothing/House Edge/Wildcard Gamble"
```

---
﻿## Note on rewording

None of Ranger's 18 approved options required rewording — every one is implemented exactly as approved in the checkpoint table. Three implementation choices needed judgment calls (all handled the same way Tasks 16–18 handled their own class-specific quirks, via an in-section "Implementation notes" blockquote, not a content change):

1. **`collateral_deeper`** needs a splash-fraction bump on `_splash_half_to_others()`, which I confirmed (by reading `combat/combat.gd`) is shared with Warden's Earthquake (call sites at the Collateral and Earthquake blocks in `_finish_spin()`). Per the cost/scope constraint's own example, I added one optional `fraction: float = 0.5` parameter (default-preserving; Earthquake's call site is untouched) rather than any new shared abstraction.
2. **`crippling_deeper`** bumps an *existing* inline bonus (Crippling Shot's own `bonus_vs_cc` 50% bonus), so it's implemented as a direct inline check at that exact line, not through the generic `rider_talent_bonus_damage_pct()` hook — exactly the reading the task brief itself suggested.
3. I verified `combat/resources/types/piercing.tres` has no `inherent_rider_id` set (unlike Vanguard's Crushing/`&"slow"` collision from Task 16), and Ranger's own two rider ids (`rooted` from Snare Trap, `weakened` from Crippling Shot) don't collide with each other or with the weapon. So Ranger is in the same clean situation as Chancer (Task 18): the generic `apply_rider_talent_adjustments()`/`rider_talent_bonus_damage_pct()` hooks work with no workaround. One exception needed care, not a workaround: Hunter's Mark's own bonus Weakened (from `mark_weakening`) is attached via a plain `EffectLibrary.make()` call that deliberately never passes through `apply_rider_talent_adjustments()`, so it stays decoupled from `crippling_lasting`'s duration bump on Crippling Shot's *own* Weakened application (both use rider id `&"weakened"`, but only one of the two call sites routes through the generic hook).

---

## Task 19: Ranger Ability Talents (18 options)

> **Implementation notes (no option required a reword — all 18 below are implemented exactly as
> approved):**
> 1. **`collateral_deeper`** (splash fraction 1/2→2/3) needs `_splash_half_to_others()` to take a
>    fraction. That helper is shared by Ranger Collateral and Warden Earthquake (both call it from
>    `_finish_spin()`), so it gains one optional `fraction: float = 0.5` parameter — Earthquake's own
>    call site is completely unaffected (it never passes the new argument).
> 2. **`crippling_deeper`** (CC-exploit bonus +50%→+65%) modifies an *existing* inline bonus
>    (`attack.source_reel.bonus_vs_cc`'s own `ceili(attack.final_damage * 0.5)` line) rather than adding
>    a new bonus hit, so it's checked directly at that line — not through the generic
>    `rider_talent_bonus_damage_pct()` hook, which `snare_deeper` uses instead for the opposite reason
>    (it adds a wholly new bonus hit on Snare Trap's own reel).
> 3. **`aim_piercing`** ("Aimed Shot also applies 1 stack of Weakened on this spin's hit") needs to know
>    whether a reel actually connected AFTER Aimed Shot is staged — that can't be known at commit time.
>    A single new one-turn pending flag, `Combatant.aimed_shot_hit_pending`, mirrors the existing
>    `loaded_dice_pending`'s exact same-turn set-then-consume shape (set in `_commit_main1()`,
>    consumed on the first connecting reel in `_apply_attack()`). Not a shared-function signature
>    change — a single new field on `Combatant`, the same weight as every other per-ability pending
>    flag already in this file.
> 4. Verified `combat/resources/types/piercing.tres` has no `inherent_rider_id` set (unlike Vanguard's
>    Crushing/`&"slow"` collision from Task 16) — so Ranger's rider ids (`rooted` from Snare Trap,
>    `weakened` from Crippling Shot) need no reel-instance-scoped workaround; Ranger is in the same
>    clean situation Chancer's Jinx the Odds was in (Task 18). One thing needs care rather than a
>    workaround: Hunter's Mark's own bonus Weakened (`mark_weakening`) is attached via a plain
>    `EffectLibrary.make(&"weakened")` call that deliberately never passes through
>    `apply_rider_talent_adjustments()` — so it stays decoupled from `crippling_lasting`'s duration
>    bump on Crippling Shot's *own* Weakened application, even though both ultimately use rider id
>    `&"weakened"`. Only Crippling Shot's own generic rider-attach call site is affected by
>    `crippling_lasting`.

**Files:**
- Modify: `combat/ability_talent_library.gd` (fills in the `&"ranger":` branch of `options_for()`)
- Modify: `combat/combatant.gd` (new `aimed_shot_hit_pending` field, `passive_outgoing_multiplier()`'s
  `&"steady_aim":` arm, and the 4 shared dispatch methods gaining a `&"ranger":` arm)
- Modify: `combat/combat.gd` (`_commit_main1()`'s `hunters_mark_pending`/`aimed_shot_pending` blocks;
  `_apply_attack()`'s Crippling Shot `bonus_vs_cc` block gains the `crippling_deeper` bump, plus a new
  Piercing Aim on-hit check, plus the Bonus-Meter-charge block gains a `steady_charging` check;
  `_splash_half_to_others()` gains an optional `fraction` param; `_finish_spin()`'s Collateral Damage
  block gains the `collateral_deeper` fraction pick and the `collateral_marking` mark-application loop)
- Modify: `combat/main_phase_plan.gd` (`commit()`'s `&"collateral":` arm gains the `collateral_lasting`
  spin-count branch)
- Test: `tests/test_ability_talents_ranger.gd` (new)

**Interfaces:**
- Consumes: Task 14's `Combatant.class_id` / `ability_talent_picks` / `has_ability_talent()` /
  `pick_ability_talent()` / `ability_talent_cost_delta()` / `ability_talent_cooldown_delta()` /
  `apply_rider_talent_adjustments()` / `rider_talent_bonus_damage_pct()` scaffolds, and
  `AbilityTalentLibrary.options_for()`'s empty `&"ranger":` stub. Also consumes the existing Ranger
  infrastructure: `stage_hunters_mark`, `stage_aimed_shot`, `try_snare_trap`, `try_crippling_shot`,
  `fire_collateral`, `consume_collateral_spin`, `is_collateral_active`, `passive_outgoing_multiplier`,
  and the `&"hunters_mark"`/`&"weakened"`/`&"rooted"`/`&"empowered"` `EffectLibrary` entries.
- Produces: 18 populated `AbilityTalentOption` entries for Ranger across all 6 rows; talent-aware
  Hunter's Mark/Aimed Shot/Snare Trap/Crippling Shot/Steady Aim/Collateral Damage behavior. Ranger is
  the FIRST class to populate a real `&"ranger":` arm in ALL 4 shared dispatch methods (Chancer/Task 18
  populated `apply_rider_talent_adjustments()`/`rider_talent_bonus_damage_pct()`, but not every class
  needed both before now) — safe here because neither of Ranger's own rider ids (`rooted`/`weakened`)
  collides with its own weapon's inherent rider (Piercing has none) or with each other.

- [ ] **Step 1: Write the failing test**

Create `tests/test_ability_talents_ranger.gd`:

```gdscript
extends SceneTree

# Headless test: the Ranger's 18 Ability Talent options (Task 19) — one row of 3 mutually-
# exclusive picks per Ranger ability (Hunter's Mark / Aimed Shot / Snare Trap / Crippling Shot /
# Steady Aim / Collateral Damage). Exercises AbilityTalentLibrary.options_for(&"ranger", row_id),
# pick_ability_talent()/has_ability_talent(), the cost/cooldown-delta dispatch methods, and the
# GENERIC apply_rider_talent_adjustments()/rider_talent_bonus_damage_pct() hooks (neither of
# Ranger's own rider ids collides with its weapon's inherent rider or with each other — unlike
# Vanguard's Quake Slam/Task 16 — so no reel-instance-scoped workaround is needed here; see this
# task's Implementation notes).
#
# Deeper Aim/Piercing Aim's actual magnitude bump and bonus-Weakened attach, Deeper Crippling's
# bump to the existing bonus_vs_cc calculation, Charging Aim's on-hit meter charge, and Marking
# Collateral's mark-application loop all live in combat.gd's _commit_main1()/_apply_attack()/
# _finish_spin() — orchestrator-level, requires a running Combat scene — and are NOT headlessly
# tested here, consistent with this codebase's own documented precedent
# (tests/test_ability_talents_warrior.gd's header comment on Bleeding Wild). Where the underlying
# math is checkable directly (Deeper Collateral's splash-fraction formula, mirroring
# tests/test_collateral.gd's own manual-replication convention) or the precondition state is
# checkable (has_ability_talent, the pending flags combat.gd's wiring reads), this test proves that
# instead.
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_ranger.gd

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _mk_ranger() -> Combatant:
	var c: Combatant = ClassLibrary.make(&"ranger").build_combatant(true)
	c.level = Combatant.MAX_LEVEL  # unlocks every talent row (5/6/7/8/9/10)
	c.resource_pool.stamina = 20
	c.begin_turn()  # populates turn_reels from the 4-reel Piercing Hunting Bow
	return c

func _test_options_for_shape() -> void:
	var rows: Array[StringName] = [&"base_ability", &"ability_l2", &"ability_l3", &"ability_l4", &"passive", &"ultimate"]
	var all_ids: Array[StringName] = [
		&"mark_deeper", &"mark_weakening", &"mark_efficient",
		&"aim_deeper", &"aim_piercing", &"aim_efficient",
		&"snare_deeper", &"snare_lasting", &"snare_efficient",
		&"crippling_deeper", &"crippling_lasting", &"crippling_swift",
		&"steady_deeper", &"steady_wider", &"steady_charging",
		&"collateral_deeper", &"collateral_marking", &"collateral_lasting",
	]
	var seen: Array[StringName] = []
	for row: StringName in rows:
		var opts: Array[AbilityTalentOption] = AbilityTalentLibrary.options_for(&"ranger", row)
		_check(opts.size() == 3, "Ranger row %s has exactly 3 options (got %d)" % [row, opts.size()])
		for o: AbilityTalentOption in opts:
			_check(o.row_id == row, "option %s reports its own row_id (%s)" % [o.id, row])
			_check(o.display_name != "" and o.description != "", "option %s has a non-empty display_name/description" % o.id)
			seen.append(o.id)
	for id: StringName in all_ids:
		_check(id in seen, "option %s is present in AbilityTalentLibrary.options_for(&ranger, ...)" % id)

func _test_hunters_mark_row() -> void:
	var c: Combatant = _mk_ranger()
	_check(c.ability_talent_cost_delta(&"hunters_mark") == 0, "no Hunter's Mark cost delta with nothing picked")
	_check(c.pick_ability_talent(&"base_ability", &"mark_efficient"), "picks mark_efficient")
	_check(c.has_ability_talent(&"mark_efficient"), "has_ability_talent sees mark_efficient")
	_check(c.ability_talent_cost_delta(&"hunters_mark") == -1, "mark_efficient: Hunter's Mark costs 1 less Stamina")

	var c2: Combatant = _mk_ranger()
	_check(c2.pick_ability_talent(&"base_ability", &"mark_deeper"), "picks mark_deeper")
	var mark: Effect = EffectLibrary.make(&"hunters_mark")
	_check(mark.duration == 3, "sanity: Hunter's Mark's baseline duration is 3")
	c2.apply_rider_talent_adjustments(&"hunters_mark", mark, c2)
	_check(mark.duration == 4, "mark_deeper: Hunter's Mark lasts 4 turns (got %d)" % mark.duration)

	var c3: Combatant = _mk_ranger()
	var target: Combatant = _mk_ranger()
	_check(c3.pick_ability_talent(&"base_ability", &"mark_weakening"), "picks mark_weakening")
	var mark3: Effect = EffectLibrary.make(&"hunters_mark")
	_check(not target.has_effect(&"weakened"), "sanity: target starts unweakened")
	c3.apply_rider_talent_adjustments(&"hunters_mark", mark3, target)
	_check(target.has_effect(&"weakened"), "mark_weakening: the target also gets a stack of Weakened")
	_check(mark3.duration == 3, "mark_weakening alone leaves Hunter's Mark's own duration at 3")

	# Mutual exclusion: only 1 pick per row.
	var c4: Combatant = _mk_ranger()
	_check(c4.pick_ability_talent(&"base_ability", &"mark_efficient"), "first pick on the Hunter's Mark row succeeds")
	_check(not c4.pick_ability_talent(&"base_ability", &"mark_deeper"), "a second pick on an already-filled row is rejected (cap of 1/row)")
	_check(c4.has_ability_talent(&"mark_efficient"), "the row's original pick is still active")

func _test_aimed_shot_row() -> void:
	var c: Combatant = _mk_ranger()
	_check(c.ability_talent_cost_delta(&"aimed_shot") == 0, "no Aimed Shot cost delta with nothing picked")
	_check(c.pick_ability_talent(&"ability_l2", &"aim_efficient"), "picks aim_efficient")
	_check(c.ability_talent_cost_delta(&"aimed_shot") == -1, "aim_efficient: Aimed Shot costs 1 less Stamina")

	# Deeper Aim's actual +40%/+70% magnitude bump lives in combat.gd's own _commit_main1() —
	# orchestrator-level (Aimed Shot's whole magnitude computation already lived there before this
	# task, sized by the defender's Mark status) — NOT headlessly tested here (see this file's
	# header comment). This proves the precondition state combat.gd's wiring reads.
	var c2: Combatant = _mk_ranger()
	_check(c2.pick_ability_talent(&"ability_l2", &"aim_deeper"), "picks aim_deeper")
	_check(c2.stage_aimed_shot(3), "stages Aimed Shot (deeper)")
	_check(c2.aimed_shot_pending, "Aimed Shot is pending for combat.gd's commit-time wiring to read")

	# Piercing Aim's actual bonus Weakened application (on this spin's first connecting hit) lives
	# in combat.gd's _apply_attack() — same precedent, not headlessly tested here.
	var c3: Combatant = _mk_ranger()
	_check(c3.pick_ability_talent(&"ability_l2", &"aim_piercing"), "picks aim_piercing")
	_check(c3.has_ability_talent(&"aim_piercing"), "has_ability_talent sees aim_piercing")
	_check(not c3.aimed_shot_hit_pending, "sanity: aimed_shot_hit_pending starts false")
	_check(c3.stage_aimed_shot(3), "stages Aimed Shot (piercing)")
	_check(c3.aimed_shot_pending, "Aimed Shot is pending for combat.gd's commit-time wiring (which sets aimed_shot_hit_pending) to read")

	# Mutual exclusion: only 1 pick per row.
	var c4: Combatant = _mk_ranger()
	_check(c4.pick_ability_talent(&"ability_l2", &"aim_efficient"), "first pick on the Aimed Shot row succeeds")
	_check(not c4.pick_ability_talent(&"ability_l2", &"aim_deeper"), "a second pick on an already-filled row is rejected (cap of 1/row)")

func _test_snare_trap_row() -> void:
	var c: Combatant = _mk_ranger()
	_check(c.ability_talent_cost_delta(&"snare_trap") == 0, "no Snare Trap cost delta with nothing picked")
	_check(c.pick_ability_talent(&"ability_l3", &"snare_efficient"), "picks snare_efficient")
	_check(c.ability_talent_cost_delta(&"snare_trap") == -1, "snare_efficient: Snare Trap costs 1 less Stamina")

	var c2: Combatant = _mk_ranger()
	_check(c2.pick_ability_talent(&"ability_l3", &"snare_deeper"), "picks snare_deeper")
	_check(is_equal_approx(c2.rider_talent_bonus_damage_pct(&"rooted"), 0.15), "snare_deeper: +15%% bonus damage on Snare Trap's own hit (got %.3f)" % c2.rider_talent_bonus_damage_pct(&"rooted"))
	_check(is_equal_approx(c2.rider_talent_bonus_damage_pct(&"weakened"), 0.0), "snare_deeper only applies to the rooted rider id, not any other")

	var c3: Combatant = _mk_ranger()
	_check(c3.pick_ability_talent(&"ability_l3", &"snare_lasting"), "picks snare_lasting")
	var rooted: Effect = EffectLibrary.make(&"rooted")
	_check(rooted.duration == 2, "sanity: Rooted's baseline duration is 2")
	c3.apply_rider_talent_adjustments(&"rooted", rooted, c3)
	_check(rooted.duration == 3, "snare_lasting: Rooted lasts 3 turns (got %d)" % rooted.duration)

	var c4: Combatant = _mk_ranger()
	_check(c4.try_snare_trap(c4.weapon_type(), 4, 6), "casts Snare Trap (sanity: unaffected structurally by talents)")

func _test_crippling_shot_row() -> void:
	var c: Combatant = _mk_ranger()
	_check(c.ability_talent_cooldown_delta(&"crippling_shot") == 0, "no Crippling Shot cooldown delta with nothing picked")
	_check(c.pick_ability_talent(&"ability_l4", &"crippling_swift"), "picks crippling_swift")
	_check(c.ability_talent_cooldown_delta(&"crippling_shot") == -1, "crippling_swift: Crippling Shot's cooldown is 1 less turn")

	var c2: Combatant = _mk_ranger()
	_check(c2.pick_ability_talent(&"ability_l4", &"crippling_lasting"), "picks crippling_lasting")
	var weakened: Effect = EffectLibrary.make(&"weakened")
	_check(weakened.duration == 2, "sanity: Weakened's baseline duration is 2")
	c2.apply_rider_talent_adjustments(&"weakened", weakened, c2)
	_check(weakened.duration == 3, "crippling_lasting: Weakened lasts 3 turns (got %d)" % weakened.duration)

	# Deeper Crippling's actual +65%-instead-of-+50% CC-exploit bonus lives in combat.gd's
	# _apply_attack() — it bumps an EXISTING inline bonus_vs_cc calculation, not a new separate hit,
	# so it's checked directly there rather than through rider_talent_bonus_damage_pct() (see this
	# task's Implementation notes). Orchestrator-level, NOT headlessly tested here.
	var c3: Combatant = _mk_ranger()
	_check(c3.pick_ability_talent(&"ability_l4", &"crippling_deeper"), "picks crippling_deeper")
	_check(c3.has_ability_talent(&"crippling_deeper"), "has_ability_talent sees crippling_deeper")
	_check(c3.try_crippling_shot(c3.weapon_type(), 5, 6), "casts Crippling Shot (sanity: unaffected structurally by talents)")

func _test_steady_aim_row() -> void:
	var c: Combatant = _mk_ranger()
	c.passive_ability_id = &"steady_aim"
	var marked: Combatant = _mk_ranger()
	marked.attach_effect(EffectLibrary.make(&"hunters_mark"))
	_check(is_equal_approx(c.passive_outgoing_multiplier(marked), 1.10), "baseline Steady Aim: +10% vs a Marked defender")

	var c2: Combatant = _mk_ranger()
	c2.passive_ability_id = &"steady_aim"
	_check(c2.pick_ability_talent(&"passive", &"steady_deeper"), "picks steady_deeper")
	_check(is_equal_approx(c2.passive_outgoing_multiplier(marked), 1.20), "steady_deeper: +20% vs a Marked defender (got %.3f)" % c2.passive_outgoing_multiplier(marked))

	var c3: Combatant = _mk_ranger()
	c3.passive_ability_id = &"steady_aim"
	var weakened_defender: Combatant = _mk_ranger()
	weakened_defender.attach_effect(EffectLibrary.make(&"weakened"))
	_check(is_equal_approx(c3.passive_outgoing_multiplier(weakened_defender), 1.0), "sanity: baseline Steady Aim does NOT trigger vs a merely-Weakened defender")
	_check(c3.pick_ability_talent(&"passive", &"steady_wider"), "picks steady_wider")
	_check(is_equal_approx(c3.passive_outgoing_multiplier(weakened_defender), 1.10), "steady_wider: now also triggers vs a Weakened defender (got %.3f)" % c3.passive_outgoing_multiplier(weakened_defender))

	# Charging Aim's ACTUAL on-hit meter charge lives in combat.gd's _apply_attack() — see the file
	# header comment above. This proves the precondition state combat.gd's wiring reads (mirrors
	# Skirmisher's opportunist_charging test exactly).
	var c4: Combatant = _mk_ranger()
	c4.passive_ability_id = &"steady_aim"
	_check(c4.pick_ability_talent(&"passive", &"steady_charging"), "picks steady_charging")
	_check(c4.has_ability_talent(&"steady_charging"), "has_ability_talent sees steady_charging")
	_check(c4.passive_outgoing_multiplier(marked) > 1.0, "steady_charging precondition: passive_outgoing_multiplier(defender) > 1.0 vs a Marked defender")

	# Mutual exclusion (passive row): only 1 pick per row.
	_check(not c4.pick_ability_talent(&"passive", &"steady_deeper"), "a second pick on an already-filled row is rejected (cap of 1/row)")

func _test_collateral_row() -> void:
	# Deeper Collateral's splash-fraction formula (proof of the math, mirroring
	# tests/test_collateral.gd's own convention of replicating the orchestrator's formula directly,
	# since _splash_half_to_others() is a private Combat-scene method with no live scene here).
	_check(ceili(20 * 0.5) == 10, "sanity: baseline (1/2) splash of 20 is 10")
	_check(ceili(20 * (2.0 / 3.0)) == 14, "collateral_deeper: 2/3 splash of 20 is 14, rounded up (got %d)" % ceili(20 * (2.0 / 3.0)))
	var c: Combatant = _mk_ranger()
	_check(c.pick_ability_talent(&"ultimate", &"collateral_deeper"), "picks collateral_deeper")
	_check(c.has_ability_talent(&"collateral_deeper"), "has_ability_talent sees collateral_deeper")

	# Marking Collateral: manually simulates the exact splash+mark loop combat.gd's _finish_spin()
	# performs (mirroring test_collateral.gd's own synthetic-3-enemy manual-simulation technique,
	# since _splash_half_to_others()/its caller are private Combat-scene methods).
	var c2: Combatant = _mk_ranger()
	_check(c2.pick_ability_talent(&"ultimate", &"collateral_marking"), "picks collateral_marking")
	var other_a: Combatant = _mk_ranger()
	var other_b: Combatant = _mk_ranger()
	var splashed: Array[Combatant] = [other_a, other_b]
	_check(not other_a.has_effect(&"hunters_mark") and not other_b.has_effect(&"hunters_mark"), "sanity: neither splashed enemy starts Marked")
	for other: Combatant in splashed:
		if c2.has_ability_talent(&"collateral_marking"):
			other.attach_effect(EffectLibrary.make(&"hunters_mark"))
	_check(other_a.has_effect(&"hunters_mark") and other_b.has_effect(&"hunters_mark"), "collateral_marking: every splashed enemy is also Marked")

	var c3: Combatant = _mk_ranger()
	c3.bonus_meter.value = c3.bonus_meter.cap
	var plan: MainPhasePlan = MainPhasePlan.new(c3)
	_check(plan.ultimate_id == &"collateral", "sanity: Ranger's Ultimate id is &collateral")
	plan.toggle_ultimate()
	_check(plan.fire_ultimate_staged, "Collateral Damage ultimate stages when the meter is armed")
	plan.commit()
	_check(c3.collateral_spins_remaining == 1, "without Lasting Collateral, firing it grants 1 spin (got %d)" % c3.collateral_spins_remaining)

	var c4: Combatant = _mk_ranger()
	c4.bonus_meter.value = c4.bonus_meter.cap
	_check(c4.pick_ability_talent(&"ultimate", &"collateral_lasting"), "picks collateral_lasting")
	var plan2: MainPhasePlan = MainPhasePlan.new(c4)
	plan2.toggle_ultimate()
	plan2.commit()
	_check(c4.collateral_spins_remaining == 2, "collateral_lasting: firing Collateral Damage grants 2 spins (got %d)" % c4.collateral_spins_remaining)

	# Mutual exclusion (ultimate row): only 1 pick per row.
	var c5: Combatant = _mk_ranger()
	_check(c5.pick_ability_talent(&"ultimate", &"collateral_deeper"), "first pick on the Collateral Damage row succeeds")
	_check(not c5.pick_ability_talent(&"ultimate", &"collateral_marking"), "a second pick on an already-filled row is rejected (cap of 1/row)")

func _init() -> void:
	_test_options_for_shape()
	_test_hunters_mark_row()
	_test_aimed_shot_row()
	_test_snare_trap_row()
	_test_crippling_shot_row()
	_test_steady_aim_row()
	_test_collateral_row()
	print(("RANGER ABILITY TALENTS TEST PASSED" if _failures == 0 else "RANGER ABILITY TALENTS TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_ranger.gd`
Expected: FAIL on essentially every check — `AbilityTalentLibrary.options_for(&"ranger", ...)` still returns `[]`, and `aimed_shot_hit_pending` doesn't exist yet.

- [ ] **Step 3: Implement**

**(a) `combat/ability_talent_library.gd`** — replace the existing empty stub:

```gdscript
		&"ranger":
			return []
```

with the full nested match (6 rows × 3 options):

```gdscript
		&"ranger":
			match row_id:
				&"base_ability":
					var m1: AbilityTalentOption = AbilityTalentOption.new()
					m1.id = &"mark_deeper"; m1.row_id = row_id
					m1.display_name = "Deeper Mark"
					m1.description = "Hunter's Mark lasts 4 turns (was 3)."
					var m2: AbilityTalentOption = AbilityTalentOption.new()
					m2.id = &"mark_weakening"; m2.row_id = row_id
					m2.display_name = "Weakening Mark"
					m2.description = "Hunter's Mark also applies a stack of Weakened."
					var m3: AbilityTalentOption = AbilityTalentOption.new()
					m3.id = &"mark_efficient"; m3.row_id = row_id
					m3.display_name = "Efficient Mark"
					m3.description = "Hunter's Mark's Stamina cost is reduced to 2 (was 3)."
					return [m1, m2, m3]
				&"ability_l2":
					var a1: AbilityTalentOption = AbilityTalentOption.new()
					a1.id = &"aim_deeper"; a1.row_id = row_id
					a1.display_name = "Deeper Aim"
					a1.description = "Aimed Shot's damage bonus rises to +40% (unmarked) / +70% (vs a Marked target), was +30%/+60%."
					var a2: AbilityTalentOption = AbilityTalentOption.new()
					a2.id = &"aim_piercing"; a2.row_id = row_id
					a2.display_name = "Piercing Aim"
					a2.description = "Aimed Shot also applies a stack of Weakened on this spin's hit."
					var a3: AbilityTalentOption = AbilityTalentOption.new()
					a3.id = &"aim_efficient"; a3.row_id = row_id
					a3.display_name = "Efficient Aim"
					a3.description = "Aimed Shot's Stamina cost is reduced to 2 (was 3)."
					return [a1, a2, a3]
				&"ability_l3":
					var s1: AbilityTalentOption = AbilityTalentOption.new()
					s1.id = &"snare_deeper"; s1.row_id = row_id
					s1.display_name = "Deeper Snare"
					s1.description = "Snare Trap's own hit deals +15% bonus damage."
					var s2: AbilityTalentOption = AbilityTalentOption.new()
					s2.id = &"snare_lasting"; s2.row_id = row_id
					s2.display_name = "Lasting Snare"
					s2.description = "Rooted (from this ability) lasts 3 turns (was 2)."
					var s3: AbilityTalentOption = AbilityTalentOption.new()
					s3.id = &"snare_efficient"; s3.row_id = row_id
					s3.display_name = "Efficient Snare"
					s3.description = "Snare Trap's Stamina cost is reduced to 3 (was 4)."
					return [s1, s2, s3]
				&"ability_l4":
					var c1: AbilityTalentOption = AbilityTalentOption.new()
					c1.id = &"crippling_deeper"; c1.row_id = row_id
					c1.display_name = "Deeper Crippling"
					c1.description = "Crippling Shot's CC-exploit bonus rises to +65% (was +50%)."
					var c2: AbilityTalentOption = AbilityTalentOption.new()
					c2.id = &"crippling_lasting"; c2.row_id = row_id
					c2.display_name = "Lasting Crippling"
					c2.description = "Weakened (from this ability) lasts 3 turns (was 2)."
					var c3: AbilityTalentOption = AbilityTalentOption.new()
					c3.id = &"crippling_swift"; c3.row_id = row_id
					c3.display_name = "Swift Crippling"
					c3.description = "Crippling Shot's cooldown is reduced to 2 turns (was 3)."
					return [c1, c2, c3]
				&"passive":
					var p1: AbilityTalentOption = AbilityTalentOption.new()
					p1.id = &"steady_deeper"; p1.row_id = row_id
					p1.display_name = "Deadeye"
					p1.description = "Steady Aim's damage bonus increases to +20% (was +10%)."
					var p2: AbilityTalentOption = AbilityTalentOption.new()
					p2.id = &"steady_wider"; p2.row_id = row_id
					p2.display_name = "Wider Aim"
					p2.description = "Steady Aim's bonus also applies vs a Weakened defender."
					var p3: AbilityTalentOption = AbilityTalentOption.new()
					p3.id = &"steady_charging"; p3.row_id = row_id
					p3.display_name = "Charging Aim"
					p3.description = "Landing a hit via Steady Aim also grants +1 flat Bonus Meter charge."
					return [p1, p2, p3]
				&"ultimate":
					var u1: AbilityTalentOption = AbilityTalentOption.new()
					u1.id = &"collateral_deeper"; u1.row_id = row_id
					u1.display_name = "Deeper Collateral"
					u1.description = "Collateral Damage's splash fraction rises to 2/3 of the primary total (was 1/2)."
					var u2: AbilityTalentOption = AbilityTalentOption.new()
					u2.id = &"collateral_marking"; u2.row_id = row_id
					u2.display_name = "Marking Collateral"
					u2.description = "Every enemy splashed by Collateral Damage also gets Hunter's Mark applied."
					var u3: AbilityTalentOption = AbilityTalentOption.new()
					u3.id = &"collateral_lasting"; u3.row_id = row_id
					u3.display_name = "Lasting Collateral"
					u3.description = "Collateral Damage's added reel stays for 2 spins instead of 1."
					return [u1, u2, u3]
				_:
					return []
```

**(b) `combat/combatant.gd` — new field**, add right after the existing `aimed_shot_pending` field:

```gdscript
## Ranger "Aimed Shot" (L5) pending flag: the orchestrator (which knows the defender) attaches
## Empowered with a bonus magnitude if the defender is already Marked (combat.gd, Task 23 wiring).
var aimed_shot_pending: bool = false

## Ranger "Piercing Aim" talent (Task 19) pending flag: set alongside aimed_shot_pending's own
## commit-time attach when the aim_piercing talent is picked. Consumed the first time a reel
## actually connects this same spin (combat.gd's _apply_attack()), which attaches a bonus stack of
## Weakened to the target and clears the flag — mirrors loaded_dice_pending's same-turn
## set-then-consume shape exactly.
var aimed_shot_hit_pending: bool = false
```

**(c) `combat/combatant.gd` — `passive_outgoing_multiplier()`**, change the `&"steady_aim":` arm (the
file already has the Warrior/Skirmisher arms right before it — both untouched here) from:

```gdscript
		&"steady_aim":
			return 1.10 if (defender != null and defender.has_effect(&"hunters_mark")) else 1.0
```

to:

```gdscript
		&"steady_aim":
			if defender == null:
				return 1.0
			var triggered: bool = defender.has_effect(&"hunters_mark")
			if has_ability_talent(&"steady_wider"):
				triggered = triggered or defender.has_effect(&"weakened")
			if not triggered:
				return 1.0
			return 1.20 if has_ability_talent(&"steady_deeper") else 1.10
```

**(d) `combat/combatant.gd` — the 4 shared dispatch methods that need a Ranger arm.** Change each
from its post-Task-18 state (add the `&"ranger":` arm alongside Warrior/Vanguard/Skirmisher/Chancer's
existing arms — do not disturb them):

```gdscript
func ability_talent_cost_delta(ability_id: StringName) -> int:
	match class_id:
		&"warrior":
			match ability_id:
				&"rend":
					return -1 if has_ability_talent(&"rend_efficient") else 0
				&"sundering_strike":
					return -1 if has_ability_talent(&"sunder_efficient") else 0
				_:
					return 0
		&"vanguard":
			match ability_id:
				&"heft":
					return -1 if has_ability_talent(&"heft_efficient") else 0
				&"bloodwrath":
					return -1 if has_ability_talent(&"wrath_efficient") else 0
				&"quake_slam":
					return -1 if has_ability_talent(&"slam_efficient") else 0
				_:
					return 0
		&"skirmisher":
			match ability_id:
				&"flurry":
					return -1 if has_ability_talent(&"flurry_efficient") else 0
				&"feint_riposte":
					return -1 if has_ability_talent(&"feint_efficient") else 0
				&"quickstep":
					return -1 if has_ability_talent(&"step_efficient") else 0
				_:
					return 0
		&"chancer":
			match ability_id:
				&"reroll":
					return -1 if has_ability_talent(&"reroll_efficient") else 0
				&"loaded_dice":
					return -1 if has_ability_talent(&"dice_efficient") else 0
				&"jinx_the_odds":
					return -1 if has_ability_talent(&"jinx_efficient") else 0
				_:
					return 0
		_:
			return 0
```

to:

```gdscript
func ability_talent_cost_delta(ability_id: StringName) -> int:
	match class_id:
		&"warrior":
			match ability_id:
				&"rend":
					return -1 if has_ability_talent(&"rend_efficient") else 0
				&"sundering_strike":
					return -1 if has_ability_talent(&"sunder_efficient") else 0
				_:
					return 0
		&"vanguard":
			match ability_id:
				&"heft":
					return -1 if has_ability_talent(&"heft_efficient") else 0
				&"bloodwrath":
					return -1 if has_ability_talent(&"wrath_efficient") else 0
				&"quake_slam":
					return -1 if has_ability_talent(&"slam_efficient") else 0
				_:
					return 0
		&"skirmisher":
			match ability_id:
				&"flurry":
					return -1 if has_ability_talent(&"flurry_efficient") else 0
				&"feint_riposte":
					return -1 if has_ability_talent(&"feint_efficient") else 0
				&"quickstep":
					return -1 if has_ability_talent(&"step_efficient") else 0
				_:
					return 0
		&"chancer":
			match ability_id:
				&"reroll":
					return -1 if has_ability_talent(&"reroll_efficient") else 0
				&"loaded_dice":
					return -1 if has_ability_talent(&"dice_efficient") else 0
				&"jinx_the_odds":
					return -1 if has_ability_talent(&"jinx_efficient") else 0
				_:
					return 0
		&"ranger":
			match ability_id:
				&"hunters_mark":
					return -1 if has_ability_talent(&"mark_efficient") else 0
				&"aimed_shot":
					return -1 if has_ability_talent(&"aim_efficient") else 0
				&"snare_trap":
					return -1 if has_ability_talent(&"snare_efficient") else 0
				_:
					return 0
		_:
			return 0
```

```gdscript
func ability_talent_cooldown_delta(ability_id: StringName) -> int:
	match class_id:
		&"warrior":
			match ability_id:
				&"second_wind":
					return -1 if has_ability_talent(&"wind_swift") else 0
				_:
					return 0
		&"vanguard":
			match ability_id:
				&"mountain_stance":
					return -1 if has_ability_talent(&"stance_swift") else 0
				_:
					return 0
		&"skirmisher":
			match ability_id:
				&"riposte_storm":
					return -1 if has_ability_talent(&"storm_swift") else 0
				_:
					return 0
		&"chancer":
			match ability_id:
				&"double_or_nothing":
					return -1 if has_ability_talent(&"gamble_swift") else 0
				_:
					return 0
		_:
			return 0
```

to:

```gdscript
func ability_talent_cooldown_delta(ability_id: StringName) -> int:
	match class_id:
		&"warrior":
			match ability_id:
				&"second_wind":
					return -1 if has_ability_talent(&"wind_swift") else 0
				_:
					return 0
		&"vanguard":
			match ability_id:
				&"mountain_stance":
					return -1 if has_ability_talent(&"stance_swift") else 0
				_:
					return 0
		&"skirmisher":
			match ability_id:
				&"riposte_storm":
					return -1 if has_ability_talent(&"storm_swift") else 0
				_:
					return 0
		&"chancer":
			match ability_id:
				&"double_or_nothing":
					return -1 if has_ability_talent(&"gamble_swift") else 0
				_:
					return 0
		&"ranger":
			match ability_id:
				&"crippling_shot":
					return -1 if has_ability_talent(&"crippling_swift") else 0
				_:
					return 0
		_:
			return 0
```

```gdscript
func apply_rider_talent_adjustments(rider_id: StringName, effect: Effect, target: Combatant) -> void:
	match class_id:
		&"warrior":
			match rider_id:
				&"bleed":
					if has_ability_talent(&"rend_deeper_cut"):
						for i: int in range(effect.dot_fractions.size()):
							effect.dot_fractions[i] *= 1.25
					if has_ability_talent(&"rend_lasting_wound"):
						effect.max_stacks = 4
						if effect.dot_fractions.size() < 4:
							effect.dot_fractions.append(1.55)
				&"sundered":
					if has_ability_talent(&"sunder_deeper"):
						effect.magnitude = 1.35
					if has_ability_talent(&"sunder_lingering"):
						effect.duration = 3
		&"chancer":
			match rider_id:
				&"jinxed":
					if has_ability_talent(&"jinx_lasting"):
						effect.duration = 3
		_:
			pass
```

to:

```gdscript
func apply_rider_talent_adjustments(rider_id: StringName, effect: Effect, target: Combatant) -> void:
	match class_id:
		&"warrior":
			match rider_id:
				&"bleed":
					if has_ability_talent(&"rend_deeper_cut"):
						for i: int in range(effect.dot_fractions.size()):
							effect.dot_fractions[i] *= 1.25
					if has_ability_talent(&"rend_lasting_wound"):
						effect.max_stacks = 4
						if effect.dot_fractions.size() < 4:
							effect.dot_fractions.append(1.55)
				&"sundered":
					if has_ability_talent(&"sunder_deeper"):
						effect.magnitude = 1.35
					if has_ability_talent(&"sunder_lingering"):
						effect.duration = 3
		&"chancer":
			match rider_id:
				&"jinxed":
					if has_ability_talent(&"jinx_lasting"):
						effect.duration = 3
		&"ranger":
			match rider_id:
				&"hunters_mark":
					# mark_weakening's OWN bonus Weakened (see combat.gd's hunters_mark_pending block)
					# is attached separately via a plain EffectLibrary.make() call that never routes
					# through this function — so it stays decoupled from crippling_lasting's duration
					# bump below, even though both ultimately use rider id &"weakened".
					if has_ability_talent(&"mark_deeper"):
						effect.duration = 4
					if has_ability_talent(&"mark_weakening"):
						target.attach_effect(EffectLibrary.make(&"weakened"))
				&"rooted":
					if has_ability_talent(&"snare_lasting"):
						effect.duration = 3
				&"weakened":
					if has_ability_talent(&"crippling_lasting"):
						effect.duration = 3
		_:
			pass
```

```gdscript
func rider_talent_bonus_damage_pct(rider_id: StringName) -> float:
	match class_id:
		&"chancer":
			match rider_id:
				&"jinxed":
					return 0.15 if has_ability_talent(&"jinx_deeper") else 0.0
				_:
					return 0.0
		_:
			return 0.0
```

to:

```gdscript
func rider_talent_bonus_damage_pct(rider_id: StringName) -> float:
	match class_id:
		&"chancer":
			match rider_id:
				&"jinxed":
					return 0.15 if has_ability_talent(&"jinx_deeper") else 0.0
				_:
					return 0.0
		&"ranger":
			match rider_id:
				&"rooted":
					return 0.15 if has_ability_talent(&"snare_deeper") else 0.0
				_:
					return 0.0
		_:
			return 0.0
```

**(e) `combat/combat.gd` — the `hunters_mark_pending`/`aimed_shot_pending` blocks in `_commit_main1()`**, change from:

```gdscript
	if _attacker.hunters_mark_pending:
		var mark: Effect = EffectLibrary.make(&"hunters_mark")
		_defender.attach_effect(mark)
		_attacker.hunters_mark_pending = false
		_log("  ⊕ %s MARKS %s — crit-fails become hits vs it (%d turns)." % [_attacker.display_name, _defender.display_name, mark.duration])
		(_panels[_defender] as CombatantPanel).refresh_status()
	# Aimed Shot (Task 23): a self-buff, so the orchestrator sizes it here where the defender's Mark
	# status is known — bigger bonus when the shot is lined up on an already-Marked target.
	if _attacker.aimed_shot_pending:
		var e: Effect = EffectLibrary.make(&"empowered")
		e.magnitude = 1.6 if _defender.has_effect(&"hunters_mark") else 1.3
		e.duration = 1
		_attacker.attach_effect(e)
		_attacker.aimed_shot_pending = false
		_log("  ⊕ %s takes Aimed Shot — damage empowered %.0f%% this turn." % [_attacker.display_name, (e.magnitude - 1.0) * 100.0])
		(_panels[_attacker] as CombatantPanel).refresh_status()
```

to:

```gdscript
	if _attacker.hunters_mark_pending:
		var mark: Effect = EffectLibrary.make(&"hunters_mark")
		# Ranger Ability Talents (Task 19): Deeper Mark (duration) / Weakening Mark (bonus Weakened) —
		# mirrors Warrior's Bleeding Wild precedent (Task 15) of calling apply_rider_talent_adjustments()
		# directly at a bespoke manual-attach site, not only the one generic shared rider-attach site.
		_attacker.apply_rider_talent_adjustments(&"hunters_mark", mark, _defender)
		_defender.attach_effect(mark)
		_attacker.hunters_mark_pending = false
		_log("  ⊕ %s MARKS %s — crit-fails become hits vs it (%d turns)." % [_attacker.display_name, _defender.display_name, mark.duration])
		(_panels[_defender] as CombatantPanel).refresh_status()
	# Aimed Shot (Task 23): a self-buff, so the orchestrator sizes it here where the defender's Mark
	# status is known — bigger bonus when the shot is lined up on an already-Marked target.
	if _attacker.aimed_shot_pending:
		# Ranger "Deeper Aim" talent (Task 19): both bonus tiers rise by +10 points (+30%/+60% ->
		# +40%/+70%).
		var marked_bonus: float = 1.7 if _attacker.has_ability_talent(&"aim_deeper") else 1.6
		var unmarked_bonus: float = 1.4 if _attacker.has_ability_talent(&"aim_deeper") else 1.3
		var e: Effect = EffectLibrary.make(&"empowered")
		e.magnitude = marked_bonus if _defender.has_effect(&"hunters_mark") else unmarked_bonus
		e.duration = 1
		_attacker.attach_effect(e)
		_attacker.aimed_shot_pending = false
		# Ranger "Piercing Aim" talent (Task 19): flags a bonus Weakened application, consumed the
		# first time a reel connects this spin (combat.gd's _apply_attack()).
		if _attacker.has_ability_talent(&"aim_piercing"):
			_attacker.aimed_shot_hit_pending = true
		_log("  ⊕ %s takes Aimed Shot — damage empowered %.0f%% this turn." % [_attacker.display_name, (e.magnitude - 1.0) * 100.0])
		(_panels[_attacker] as CombatantPanel).refresh_status()
```

**(f) `combat/combat.gd` — the Crippling Shot `bonus_vs_cc` block + rider-bonus block in
`_apply_attack()`** (post-Task-14 state), change from:

```gdscript
			if attack.source_reel != null and attack.source_reel.bonus_vs_cc:
				# stunned_this_turn is only ever true DURING the bearer's own turn (set by evaluate_stun
				# at their turn start, cleared by their own on_end) — checked here on the RANGER's turn,
				# against another combatant, it is always false by construction and the bonus would never
				# fire for a stunned target (playtest audit 2026-07-02). stunned_last_turn is the field
				# that's actually observable from outside the bearer's own turn: true from the moment
				# their stunned turn ends until their own NEXT on_end, which is exactly the window a
				# called shot like this should be able to exploit.
				if t.has_effect(&"slow") or t.has_effect(&"rooted") or t.stunned_last_turn:
					var bonus: int = ceili(attack.final_damage * 0.5)
					t.take_damage(bonus)
					_log("  🎯 Crippling Shot exploits %s's condition for %d bonus damage." % [t.display_name, bonus])
			if attack.rider_effect_id != &"":
				var talent_bonus_pct: float = _attacker.rider_talent_bonus_damage_pct(attack.rider_effect_id)
				if talent_bonus_pct > 0.0:
					var talent_bonus: int = ceili(attack.final_damage * talent_bonus_pct)
					t.take_damage(talent_bonus)
					_log("  ✦ %s's talent adds %d bonus damage." % [_attacker.display_name, talent_bonus])
```

to:

```gdscript
			if attack.source_reel != null and attack.source_reel.bonus_vs_cc:
				# stunned_this_turn is only ever true DURING the bearer's own turn (set by evaluate_stun
				# at their turn start, cleared by their own on_end) — checked here on the RANGER's turn,
				# against another combatant, it is always false by construction and the bonus would never
				# fire for a stunned target (playtest audit 2026-07-02). stunned_last_turn is the field
				# that's actually observable from outside the bearer's own turn: true from the moment
				# their stunned turn ends until their own NEXT on_end, which is exactly the window a
				# called shot like this should be able to exploit.
				if t.has_effect(&"slow") or t.has_effect(&"rooted") or t.stunned_last_turn:
					# Ranger "Deeper Crippling" talent (Task 19): bumps this EXISTING bonus from 50% to
					# 65% — modifying an existing bonus rather than adding a new one, so this is a direct
					# inline check rather than the generic rider_talent_bonus_damage_pct hook (Deeper
					# Snare uses that hook instead, for the opposite reason: it adds a NEW bonus hit).
					var cc_bonus_pct: float = 0.65 if _attacker.has_ability_talent(&"crippling_deeper") else 0.5
					var bonus: int = ceili(attack.final_damage * cc_bonus_pct)
					t.take_damage(bonus)
					_log("  🎯 Crippling Shot exploits %s's condition for %d bonus damage." % [t.display_name, bonus])
			if attack.rider_effect_id != &"":
				var talent_bonus_pct: float = _attacker.rider_talent_bonus_damage_pct(attack.rider_effect_id)
				if talent_bonus_pct > 0.0:
					var talent_bonus: int = ceili(attack.final_damage * talent_bonus_pct)
					t.take_damage(talent_bonus)
					_log("  ✦ %s's talent adds %d bonus damage." % [_attacker.display_name, talent_bonus])
			# Ranger "Piercing Aim" talent (Task 19): the first reel that actually connects this spin
			# (while Aimed Shot's bonus is pending from this same turn's cast) also lashes the target
			# with a bonus stack of Weakened. Consumed once (aimed_shot_hit_pending cleared here) so a
			# 4-reel spin doesn't re-log the same debuff attach on every subsequent connecting reel.
			if _attacker.aimed_shot_hit_pending and attack.final_damage > 0:
				var piercing_weak: Effect = EffectLibrary.make(&"weakened")
				t.attach_effect(piercing_weak)
				_attacker.aimed_shot_hit_pending = false
				_log("  🏹 Piercing Aim: %s is WEAKENED." % t.display_name)
				if _panels.has(t):
					(_panels[t] as CombatantPanel).refresh_status()
```

**(g) `combat/combat.gd` — the Bonus-Meter-charge block in `_apply_attack()`** (post-Task-17 state),
change from:

```gdscript
	if _attacker.bonus_meter != null and attack.charges_meter:
		var before: int = _attacker.bonus_meter.value
		_attacker.bonus_meter.charge(attack.face.result_tier)
		var added: int = _attacker.bonus_meter.value - before
		if added > 0 and _attacker.bonus_meter.is_visible:
			_log("    BM +%d  (%d/%d)" % [added, _attacker.bonus_meter.value, _attacker.bonus_meter.cap])
		if attack.final_damage > 0 and _attacker.class_id == &"skirmisher" and _attacker.has_ability_talent(&"opportunist_charging") and _attacker.passive_outgoing_multiplier(_defender) > 1.0:
			_attacker.bonus_meter.add_flat(1)
			_log("    ⚔ Opportunist strikes true — BM +1  (%d/%d)" % [_attacker.bonus_meter.value, _attacker.bonus_meter.cap])
```

to:

```gdscript
	if _attacker.bonus_meter != null and attack.charges_meter:
		var before: int = _attacker.bonus_meter.value
		_attacker.bonus_meter.charge(attack.face.result_tier)
		var added: int = _attacker.bonus_meter.value - before
		if added > 0 and _attacker.bonus_meter.is_visible:
			_log("    BM +%d  (%d/%d)" % [added, _attacker.bonus_meter.value, _attacker.bonus_meter.cap])
		if attack.final_damage > 0 and _attacker.class_id == &"skirmisher" and _attacker.has_ability_talent(&"opportunist_charging") and _attacker.passive_outgoing_multiplier(_defender) > 1.0:
			_attacker.bonus_meter.add_flat(1)
			_log("    ⚔ Opportunist strikes true — BM +1  (%d/%d)" % [_attacker.bonus_meter.value, _attacker.bonus_meter.cap])
		# Ranger "Charging Aim" talent (Task 19): an extra flat +1 charge whenever this hit actually
		# benefited from the Steady Aim passive bonus — mirrors Skirmisher's Charging Opportunist
		# precedent (Task 17) exactly, reading passive_outgoing_multiplier(_defender) against the same
		# primary defender the actual damage math used this spin.
		if attack.final_damage > 0 and _attacker.class_id == &"ranger" and _attacker.has_ability_talent(&"steady_charging") and _attacker.passive_outgoing_multiplier(_defender) > 1.0:
			_attacker.bonus_meter.add_flat(1)
			_log("    🏹 Steady Aim strikes true — BM +1  (%d/%d)" % [_attacker.bonus_meter.value, _attacker.bonus_meter.cap])
```

**(h) `combat/combat.gd` — `_splash_half_to_others()`**, change from:

```gdscript
## Splashes ceil([param total] / 2) damage to every OTHER living enemy of [param attacker] (every enemy
## except the primary [member _defender]) and logs each with [param type_label]. Off the type chart (flat
## half) — the deferred N-vs-M per-target-type simplification. Returns the enemies actually damaged (for
## Earthquake's follow-up force-stun). Shared by Ranger Collateral and Warden Earthquake. 1v1 → no-op.
func _splash_half_to_others(attacker: Combatant, total: int, type_label: String) -> Array[Combatant]:
	var damaged: Array[Combatant] = []
	var splash: int = ceili(total / 2.0)
	if splash <= 0:
		return damaged
	for other: Combatant in _enemies_of(attacker):
		if other == _defender:
			continue
		other.take_damage(splash)
		damaged.append(other)
		_log("  💥 splash → %s takes %d %s (half of %d)." % [other.display_name, splash, type_label, total])
		if _panels.has(other):
			(_panels[other] as CombatantPanel).refresh_status()
	return damaged
```

to:

```gdscript
## Splashes ceil([param total] * [param fraction]) damage to every OTHER living enemy of [param attacker]
## (every enemy except the primary [member _defender]) and logs each with [param type_label]. Off the
## type chart (flat fraction) — the deferred N-vs-M per-target-type simplification. Returns the enemies
## actually damaged (for Earthquake's follow-up force-stun, and now Ranger's Marking Collateral talent).
## Shared by Ranger Collateral and Warden Earthquake — [param fraction] defaults to 0.5 (the original,
## unchanged behavior), so Earthquake's own call site needs no edit; only Ranger's "Deeper Collateral"
## talent (Task 19) ever passes a non-default value. 1v1 → no-op.
func _splash_half_to_others(attacker: Combatant, total: int, type_label: String, fraction: float = 0.5) -> Array[Combatant]:
	var damaged: Array[Combatant] = []
	var splash: int = ceili(total * fraction)
	if splash <= 0:
		return damaged
	for other: Combatant in _enemies_of(attacker):
		if other == _defender:
			continue
		other.take_damage(splash)
		damaged.append(other)
		_log("  💥 splash → %s takes %d %s (%.0f%% of %d)." % [other.display_name, splash, type_label, fraction * 100.0, total])
		if _panels.has(other):
			(_panels[other] as CombatantPanel).refresh_status()
	return damaged
```

**(i) `combat/combat.gd` — the Collateral Damage block in `_finish_spin()`**, change from:

```gdscript
	if _attacker.is_collateral_active():
		_splash_half_to_others(_attacker, _collateral_total, "Piercing")
		_attacker.consume_collateral_spin()
```

to:

```gdscript
	if _attacker.is_collateral_active():
		# Ranger "Deeper Collateral" talent (Task 19): the splash fraction of the primary total rises
		# from 1/2 to 2/3. _splash_half_to_others()'s new optional fraction param defaults to 0.5, so
		# Warden's Earthquake call site below is completely unaffected.
		var collateral_fraction: float = (2.0 / 3.0) if _attacker.has_ability_talent(&"collateral_deeper") else 0.5
		var splashed: Array[Combatant] = _splash_half_to_others(_attacker, _collateral_total, "Piercing", collateral_fraction)
		# Ranger "Marking Collateral" talent (Task 19): every enemy the splash actually hit also gets
		# Hunter's Mark — reuses _splash_half_to_others()'s existing return value (already there for
		# Earthquake's own force-stun follow-up below), so no extra enemy-iteration logic is needed.
		if _attacker.has_ability_talent(&"collateral_marking"):
			for other: Combatant in splashed:
				other.attach_effect(EffectLibrary.make(&"hunters_mark"))
				_log("  ⊕ Marking Collateral: %s is also MARKED." % other.display_name)
				if _panels.has(other):
					(_panels[other] as CombatantPanel).refresh_status()
		_attacker.consume_collateral_spin()
```

**(j) `combat/main_phase_plan.gd` — `commit()`'s `&"collateral":` arm**, change:

```gdscript
			&"collateral":
				combatant.fire_collateral(combatant.weapon_type(), COLLATERAL_SPINS)  # +1 reel; orchestrator splashes
```

to:

```gdscript
			&"collateral":
				# Ranger "Lasting Collateral" talent (Task 19): the added reel stays for 2 spins instead of 1.
				var spins: int = (COLLATERAL_SPINS + 1) if combatant.has_ability_talent(&"collateral_lasting") else COLLATERAL_SPINS
				combatant.fire_collateral(combatant.weapon_type(), spins)  # +1 reel; orchestrator splashes, +1 spin with Lasting Collateral
```

*(Confirm the exact existing line/variable name — `COLLATERAL_SPINS` — against the real file before
editing; if named differently, use the real name, the behavior is what matters.)*

- [ ] **Step 4: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_ranger.gd`
Expected: all lines print `ok:`.

- [ ] **Step 5: Run the full test suite**

Run every `tests/test_*.gd` file headlessly and confirm exit code 0 for each. 3 known pre-existing
failures predate this whole effort and are NOT regressions: `test_adventuring_board_panel.gd` (1
internal FAIL line), `test_overworld_demo_npcs.gd` (5), `test_overworld_encounter_variety.gd` (6). Any
OTHER nonzero exit is a real regression and must be root-caused before committing — pay particular
attention to: `tests/test_collateral.gd` (confirm `_splash_half_to_others()`'s new optional `fraction`
param didn't change the default-path 1/2-splash math or its return value), `tests/test_earthquake.gd`/
`tests/test_darkness_rampage.gd` (confirm Warden's Earthquake call site, which never passes the new
`fraction` argument, still splashes exactly half), and every prior class's own
`tests/test_ability_talents_*.gd` (confirm the shared dispatch-method edits above didn't disturb their
existing arms).

- [ ] **Step 6: Commit**

```bash
git add combat/ability_talent_library.gd combat/combatant.gd combat/combat.gd combat/main_phase_plan.gd tests/test_ability_talents_ranger.gd
git commit -m "feat(talents): Ranger Ability Talents — 18 options across Hunter's Mark/Aimed Shot/Snare Trap/Crippling Shot/Steady Aim/Collateral Damage"
```
---

None of Seer's 18 approved options required rewording under the cost/scope constraint — all are implemented exactly as approved. Two implementation-approach clarifications (not wording changes) are called out in the task's own "Implementation notes" block below: `fate_deeper`/`fate_wilder` are handled via direct reel-instance construction-time edits (no rider to key a generic hook off), and Foresight/Big Bang's orchestrator-level math is extracted into small `Combatant` helper methods (mirroring Vanguard's `bloodwrath_bonus_pct()` precedent) so it stays unit-testable. I verified `combat/resources/types/mystic.tres` has no `inherent_rider_id` set (only Crushing does, per Task 16's finding) — so unlike Vanguard, Seer's own rider id (`&"cursed"`, from Hex) collides with nothing, and the generic dispatch hooks work cleanly.

---

## Task 20: Seer Ability Talents (18 options)

> **Implementation notes (no option required a reword — all 18 below are implemented exactly as
> approved):**
> 1. Verified `combat/resources/types/mystic.tres` has no `inherent_rider_id` set (only
>    `combat/resources/types/crushing.tres` does, `&"slow"`, per Task 16's Vanguard finding) — so
>    Hex's own `&"cursed"` rider id needs no reel-instance-scoped workaround; Seer is in the same
>    clean situation Ranger (Task 19) was in. `apply_rider_talent_adjustments()` gets a normal
>    `&"seer":` arm keyed by rider_id.
> 2. **`fate_deeper`/`fate_wilder`** aren't rider-carrying at all — Select your Fate's added reel is a
>    plain `ActionReel.make_default()` weapon-attack reel with no `rider_effect_id`, so the generic
>    `rider_talent_bonus_damage_pct()`/`apply_rider_talent_adjustments()` hooks (both keyed by
>    rider_id) have nothing to key off. Implemented directly inside `apply_select_fate()` by mutating
>    the newly-constructed reel's own face multipliers (`fate_deeper`) and appending a temporary
>    crit-success face to every one of this turn's reels (`fate_wilder`) — the same
>    reel-instance-scoped, no-shared-hook-change approach Vanguard's Task 16 established for
>    `slam_deeper`/`rampage_deeper`, applied here for the same underlying reason (no rider to key
>    off), not a rider-id collision. `fate_wilder`'s scope reads "this spin" as EVERY one of this
>    turn's reels (mirroring the existing `apply_loaded_dice()` mechanism: add 1 temp crit-success
>    face to each turn reel, then reshuffle) — the row's other two options are explicitly scoped to
>    "the added reel," which is what distinguishes `fate_wilder`'s broader reading.
> 3. Foresight's shield amount/duration and The Big Bang's heal fraction/shield-duration bonus are
>    entirely orchestrator-level (`combat.gd`), same as Aimed Shot/Collateral Damage before them.
>    Extracted into 4 small `Combatant` helper methods (`foresight_shield_amount()`/
>    `foresight_shield_duration()`/`big_bang_heal_divisor()`/`big_bang_shield_duration_bonus()`)
>    mirroring Vanguard's `bloodwrath_bonus_pct()` precedent (Task 16), so the math stays directly
>    unit-testable without instantiating a running Combat scene.
> 4. **`reservoir_efficient`** ("All of this Seer's ability Mana costs are reduced by 1") is broader
>    than every other class's single-ability "Efficient X" pattern — it reduces `select_fate`/`hex`/
>    `foresight`/`mana_surge` all at once. Expressed inside `ability_talent_cost_delta()`'s `&"seer":`
>    arm as a shared `reservoir_bonus` local added into each of the 4 ability arms — each ability's
>    OWN "_efficient" talent (e.g. `hex_efficient`) stays additive and independent, since it lives in
>    a different row and can be picked simultaneously with `reservoir_efficient`.
> 5. **`bigbang_curing`** ("also cleanses 1 debuff from each healed ally") reuses the existing full
>    `cleanse()` primitive, same precedent as Warrior's `guard_cleansing`/Second Wind (Task 15) —
>    there's no "remove exactly 1 debuff" primitive in this codebase.
> 6. Unlike every prior class task, **no `main_phase_plan.gd` change is needed** — none of these 18
>    options adjust a spin count or reel count at `commit()`'s Ultimate-dispatch call site (contrast
>    Warrior's `wild_lasting`, Vanguard's `rampage_lasting`, Ranger's `collateral_lasting`).

**Files:**
- Modify: `combat/ability_talent_library.gd` (fills in the `&"seer":` branch of `options_for()`)
- Modify: `combat/combatant.gd` (`apply_select_fate()`, `apply_mana_surge()`,
  `passive_max_mana_multiplier()`'s `&"arcane_reservoir":` arm, `apply_stats()`'s `mana_regen_per_turn`
  line, 4 new helper methods — `foresight_shield_amount()`/`foresight_shield_duration()`/
  `big_bang_heal_divisor()`/`big_bang_shield_duration_bonus()` — and the 3 (of 4) shared dispatch
  methods that need a `&"seer":` arm)
- Modify: `combat/combat.gd` (`_commit_main1()`'s `foresight_pending` block; the Big Bang
  `is_big_bang_active()` heal block)
- Test: `tests/test_ability_talents_seer.gd` (new)

**Interfaces:**
- Consumes: Task 14's `Combatant.class_id` / `ability_talent_picks` / `has_ability_talent()` /
  `pick_ability_talent()` / `ability_talent_cost_delta()` / `ability_talent_cooldown_delta()` /
  `apply_rider_talent_adjustments()` scaffolds, and `AbilityTalentLibrary.options_for()`'s empty
  `&"seer":` stub. Also consumes the existing Seer infrastructure: `try_hex`, `apply_select_fate`,
  `stage_foresight`, `apply_mana_surge`, `fire_big_bang`, `is_big_bang_active`,
  `consume_big_bang_spin`, `_lowest_hp_pct_ally`, `cleanse()`, `apply_shield()`, and the
  `&"cursed"`/`&"empowered"` `EffectLibrary` entries.
- Produces: 18 populated `AbilityTalentOption` entries for Seer across all 6 rows; talent-aware
  Select your Fate/Hex/Foresight/Mana Surge/Arcane Reservoir/The Big Bang behavior; 4 new small
  `Combatant` helpers mirroring Vanguard's `bloodwrath_bonus_pct()` precedent.
  `rider_talent_bonus_damage_pct()` gets **no** `&"seer":` arm at all — none of these 18 options are
  an own-hit-bonus-damage shape (Hex's `hex_deeper` amplifies its DoT, not its own hit, unlike Quake
  Slam/Jinx the Odds/Snare Trap/Entangle/Snare Trap's `_deeper` options).

- [ ] **Step 1: Write the failing test**

Create `tests/test_ability_talents_seer.gd`:

```gdscript
extends SceneTree

# Headless test: the Seer's 18 Ability Talent options (Task 20) — one row of 3 mutually-exclusive
# picks per Seer ability (Select your Fate! / Hex / Foresight / Mana Surge / Arcane Reservoir /
# The Big Bang). Exercises AbilityTalentLibrary.options_for(&"seer", row_id),
# pick_ability_talent()/has_ability_talent(), the cost/cooldown-delta dispatch methods, and
# apply_rider_talent_adjustments() for the Cursed rider (no reel-instance-scoped workaround needed —
# Mystic has no inherent_rider_id, unlike Vanguard's Crushing/Task 16 — see this task's
# Implementation notes).
#
# fate_deeper/fate_wilder are tested directly against apply_select_fate()'s own constructed reel(s)
# (no rider to key a generic hook off — see Implementation note 2). Foresight's shield amount/
# duration and Big Bang's heal-divisor/shield-duration-bonus are tested via 4 small Combatant helper
# methods (foresight_shield_amount/duration, big_bang_heal_divisor, big_bang_shield_duration_bonus)
# that combat.gd's orchestrator-level blocks read — mirrors Vanguard's bloodwrath_bonus_pct()
# precedent (Task 16), so this math is unit-testable without a running Combat scene. bigbang_curing's
# actual cleanse-on-heal is proven by directly replicating the two orchestrator primitives it chains
# (heal() then cleanse()) — mirrors tests/test_ability_talents_ranger.gd's own "manual-replication"
# convention for an orchestrator-level effect whose underlying primitives are directly callable
# outside a running Combat scene.
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_seer.gd

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _mk_seer() -> Combatant:
	var c: Combatant = ClassLibrary.make(&"seer").build_combatant(true)
	c.level = Combatant.MAX_LEVEL  # unlocks every talent row (5/6/7/8/9/10)
	c.resource_pool.mana = c.resource_pool.max_mana
	c.begin_turn()  # populates turn_reels from the 2-reel Mystic War Staff
	return c

func _test_options_for_shape() -> void:
	var rows: Array[StringName] = [&"base_ability", &"ability_l2", &"ability_l3", &"ability_l4", &"passive", &"ultimate"]
	var all_ids: Array[StringName] = [
		&"fate_deeper", &"fate_wilder", &"fate_efficient",
		&"hex_deeper", &"hex_lasting", &"hex_efficient",
		&"foresight_deeper", &"foresight_lasting", &"foresight_efficient",
		&"surge_deeper", &"surge_refunding", &"surge_swift",
		&"reservoir_deeper", &"reservoir_regen", &"reservoir_efficient",
		&"bigbang_deeper", &"bigbang_curing", &"bigbang_shielding",
	]
	var seen: Array[StringName] = []
	for row: StringName in rows:
		var opts: Array[AbilityTalentOption] = AbilityTalentLibrary.options_for(&"seer", row)
		_check(opts.size() == 3, "Seer row %s has exactly 3 options (got %d)" % [row, opts.size()])
		for o: AbilityTalentOption in opts:
			_check(o.row_id == row, "option %s reports its own row_id (%s)" % [o.id, row])
			_check(o.display_name != "" and o.description != "", "option %s has a non-empty display_name/description" % o.id)
			seen.append(o.id)
	for id: StringName in all_ids:
		_check(id in seen, "option %s is present in AbilityTalentLibrary.options_for(&seer, ...)" % id)

func _test_select_fate_row() -> void:
	var c: Combatant = _mk_seer()
	_check(c.ability_talent_cost_delta(&"select_fate") == 0, "no Select your Fate cost delta with nothing picked")
	_check(c.pick_ability_talent(&"base_ability", &"fate_efficient"), "picks fate_efficient")
	_check(c.ability_talent_cost_delta(&"select_fate") == -1, "fate_efficient: Select your Fate costs 1 less Mana")

	var c2: Combatant = _mk_seer()
	var reels_before2: int = c2.turn_reels.size()
	_check(c2.pick_ability_talent(&"base_ability", &"fate_deeper"), "picks fate_deeper")
	_check(c2.apply_select_fate(c2.weapon_type(), 6), "casts Select your Fate (deeper)")
	_check(c2.turn_reels.size() == reels_before2 + 1, "sanity: Select your Fate adds exactly 1 reel")
	var added: ActionReel = c2.turn_reels[reels_before2]
	var hit_faces_checked: int = 0
	for f: ReelFace in added.faces:
		if f.result_tier == ReelFace.ResultTier.SUCCESS:
			hit_faces_checked += 1
			_check(is_equal_approx(f.multiplier, 1.15), "fate_deeper: added reel's SUCCESS multiplier is +15%% (got %.4f)" % f.multiplier)
		elif f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
			hit_faces_checked += 1
			_check(is_equal_approx(f.multiplier, 2.3), "fate_deeper: added reel's CRIT_SUCCESS multiplier is +15%% (got %.4f)" % f.multiplier)
	_check(hit_faces_checked > 0, "sanity: the added reel has at least one hit face to check")

	var c3: Combatant = _mk_seer()
	_check(c3.pick_ability_talent(&"base_ability", &"fate_wilder"), "picks fate_wilder")
	_check(c3.apply_select_fate(c3.weapon_type(), 6), "casts Select your Fate (wilder)")
	for r: ActionReel in c3.turn_reels:
		var crit_count: int = 0
		for f: ReelFace in r.faces:
			if f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
				crit_count += 1
		_check(crit_count == 2, "fate_wilder: every one of this turn's reels gained an extra temporary crit face (1 baseline + 1 added, got %d)" % crit_count)

	# Mutual exclusion: only 1 pick per row.
	var c4: Combatant = _mk_seer()
	_check(c4.pick_ability_talent(&"base_ability", &"fate_deeper"), "first pick on the Select your Fate row succeeds")
	_check(not c4.pick_ability_talent(&"base_ability", &"fate_wilder"), "a second pick on an already-filled row is rejected (cap of 1/row)")
	_check(c4.has_ability_talent(&"fate_deeper"), "the row's original pick is still active")

func _test_hex_row() -> void:
	var c: Combatant = _mk_seer()
	_check(c.ability_talent_cost_delta(&"hex") == 0, "no Hex cost delta with nothing picked")
	_check(c.pick_ability_talent(&"ability_l2", &"hex_efficient"), "picks hex_efficient")
	_check(c.ability_talent_cost_delta(&"hex") == -1, "hex_efficient: Hex costs 1 less Mana")

	var c2: Combatant = _mk_seer()
	_check(c2.pick_ability_talent(&"ability_l2", &"hex_deeper"), "picks hex_deeper")
	var cursed: Effect = EffectLibrary.make(&"cursed")
	var base_fractions: Array = cursed.dot_fractions.duplicate()
	c2.apply_rider_talent_adjustments(&"cursed", cursed, c2)
	for i: int in range(base_fractions.size()):
		_check(is_equal_approx(cursed.dot_fractions[i], base_fractions[i] * 1.25),
			"hex_deeper: Cursed fraction %d is +25%% (got %.4f, want %.4f)" % [i, cursed.dot_fractions[i], base_fractions[i] * 1.25])
	_check(cursed.max_stacks == 3, "hex_deeper alone leaves max_stacks at 3")

	var c3: Combatant = _mk_seer()
	_check(c3.pick_ability_talent(&"ability_l2", &"hex_lasting"), "picks hex_lasting")
	var cursed2: Effect = EffectLibrary.make(&"cursed")
	c3.apply_rider_talent_adjustments(&"cursed", cursed2, c3)
	_check(cursed2.max_stacks == 4, "hex_lasting: Cursed max_stacks is 4 (got %d)" % cursed2.max_stacks)
	_check(cursed2.dot_fractions.size() == 4, "hex_lasting: Cursed gained a 4th stack fraction (got %d entries)" % cursed2.dot_fractions.size())
	_check(is_equal_approx(cursed2.dot_fractions[3], 1.55), "hex_lasting: 4th stack fraction is 1.55 (got %.4f)" % cursed2.dot_fractions[3])

	# Mutual exclusion.
	var c4: Combatant = _mk_seer()
	_check(c4.pick_ability_talent(&"ability_l2", &"hex_efficient"), "first pick on the Hex row succeeds")
	_check(not c4.pick_ability_talent(&"ability_l2", &"hex_deeper"), "a second pick on an already-filled row is rejected")

func _test_foresight_row() -> void:
	var c: Combatant = _mk_seer()
	_check(c.ability_talent_cost_delta(&"foresight") == 0, "no Foresight cost delta with nothing picked")
	_check(c.pick_ability_talent(&"ability_l3", &"foresight_efficient"), "picks foresight_efficient")
	_check(c.ability_talent_cost_delta(&"foresight") == -1, "foresight_efficient: Foresight costs 1 less Mana")

	var c2: Combatant = _mk_seer()
	var mm: int = c2.resource_pool.max_mana
	_check(c2.foresight_shield_amount() == ceili(mm * 0.15), "baseline Foresight shields 15%% of max Mana (got %d)" % c2.foresight_shield_amount())
	_check(c2.pick_ability_talent(&"ability_l3", &"foresight_deeper"), "picks foresight_deeper")
	_check(c2.foresight_shield_amount() == ceili(mm * 0.20), "foresight_deeper: shields 20%% of max Mana (got %d)" % c2.foresight_shield_amount())
	_check(c2.foresight_shield_duration() == 3, "foresight_deeper alone leaves duration at 3")

	var c3: Combatant = _mk_seer()
	_check(c3.pick_ability_talent(&"ability_l3", &"foresight_lasting"), "picks foresight_lasting")
	_check(c3.foresight_shield_duration() == 4, "foresight_lasting: shield lasts 4 turns (got %d)" % c3.foresight_shield_duration())

func _test_mana_surge_row() -> void:
	var c: Combatant = _mk_seer()
	_check(c.ability_talent_cooldown_delta(&"mana_surge") == 0, "no Mana Surge cooldown delta with nothing picked")
	_check(c.apply_mana_surge(c.weapon_type(), 6, 5), "casts Mana Surge (baseline)")
	var emp: Effect = c._find_effect(&"empowered")
	_check(emp != null, "sanity: Empowered attached")
	_check(is_equal_approx(emp.magnitude, 1.6), "baseline Mana Surge: Empowered x1.6 (got %.3f)" % emp.magnitude)

	var c2: Combatant = _mk_seer()
	_check(c2.pick_ability_talent(&"ability_l4", &"surge_deeper"), "picks surge_deeper")
	_check(c2.apply_mana_surge(c2.weapon_type(), 6, 5), "casts Mana Surge (deeper)")
	var emp2: Effect = c2._find_effect(&"empowered")
	_check(is_equal_approx(emp2.magnitude, 1.75), "surge_deeper: Empowered x1.75 (got %.3f)" % emp2.magnitude)

	var c3: Combatant = _mk_seer()
	_check(c3.pick_ability_talent(&"ability_l4", &"surge_refunding"), "picks surge_refunding")
	var mana_before: int = c3.resource_pool.mana
	_check(c3.apply_mana_surge(c3.weapon_type(), 8, 5), "casts Mana Surge (refunding, 8-cost cast)")
	_check(c3.resource_pool.mana == mana_before - 8 + 2, "surge_refunding: refunds 25%% of the 8-cost cast (2 Mana), net -6 (got %d, expected %d)" % [c3.resource_pool.mana, mana_before - 8 + 2])

	var c4: Combatant = _mk_seer()
	_check(c4.pick_ability_talent(&"ability_l4", &"surge_swift"), "picks surge_swift")
	_check(c4.ability_talent_cooldown_delta(&"mana_surge") == -1, "surge_swift: Mana Surge cooldown is 1 less turn")

func _test_arcane_reservoir_row() -> void:
	var c: Combatant = _mk_seer()
	c.apply_stats()
	var baseline_max_mana: int = c.resource_pool.max_mana
	_check(is_equal_approx(c.passive_max_mana_multiplier(), 1.2), "baseline Arcane Reservoir: x1.2 max Mana")
	_check(c.pick_ability_talent(&"passive", &"reservoir_deeper"), "picks reservoir_deeper")
	_check(is_equal_approx(c.passive_max_mana_multiplier(), 1.35), "reservoir_deeper: x1.35 max Mana (got %.3f)" % c.passive_max_mana_multiplier())
	c.apply_stats()  # a real respec (TalentMenuPanel, a later task) re-derives stats the same way gear equip/unequip already does
	_check(c.resource_pool.max_mana > baseline_max_mana, "reservoir_deeper: max Mana increases once apply_stats() re-derives it (got %d, was %d)" % [c.resource_pool.max_mana, baseline_max_mana])

	var c2: Combatant = _mk_seer()
	c2.apply_stats()
	var before_regen: int = c2.resource_pool.mana_regen_per_turn
	_check(c2.pick_ability_talent(&"passive", &"reservoir_regen"), "picks reservoir_regen")
	c2.apply_stats()
	_check(c2.resource_pool.mana_regen_per_turn == before_regen + 1, "reservoir_regen: +1 flat Mana regen per Upkeep (got %d, was %d)" % [c2.resource_pool.mana_regen_per_turn, before_regen])

	var c3: Combatant = _mk_seer()
	_check(c3.pick_ability_talent(&"passive", &"reservoir_efficient"), "picks reservoir_efficient")
	_check(c3.ability_talent_cost_delta(&"select_fate") == -1, "reservoir_efficient: Select your Fate costs 1 less Mana")
	_check(c3.ability_talent_cost_delta(&"hex") == -1, "reservoir_efficient: Hex costs 1 less Mana")
	_check(c3.ability_talent_cost_delta(&"foresight") == -1, "reservoir_efficient: Foresight costs 1 less Mana")
	_check(c3.ability_talent_cost_delta(&"mana_surge") == -1, "reservoir_efficient: Mana Surge costs 1 less Mana")

	# Stacks with an ability's OWN "_efficient" pick — different rows, both allowed.
	var c4: Combatant = _mk_seer()
	_check(c4.pick_ability_talent(&"base_ability", &"fate_efficient"), "picks fate_efficient (base_ability row)")
	_check(c4.pick_ability_talent(&"passive", &"reservoir_efficient"), "also picks reservoir_efficient (passive row — different row, both allowed)")
	_check(c4.ability_talent_cost_delta(&"select_fate") == -2, "fate_efficient + reservoir_efficient stack: Select your Fate costs 2 less Mana")

func _test_big_bang_row() -> void:
	var c: Combatant = _mk_seer()
	_check(is_equal_approx(c.big_bang_heal_divisor(), 6.0), "baseline Big Bang heals 1/6 of spin total")
	_check(c.big_bang_shield_duration_bonus() == 0, "baseline Big Bang: no shield-duration bonus")
	_check(not c.has_ability_talent(&"bigbang_curing"), "baseline Big Bang: no cleanse-on-heal")

	var c2: Combatant = _mk_seer()
	_check(c2.pick_ability_talent(&"ultimate", &"bigbang_deeper"), "picks bigbang_deeper")
	_check(is_equal_approx(c2.big_bang_heal_divisor(), 5.0), "bigbang_deeper: heals 1/5 of spin total (got %.3f)" % c2.big_bang_heal_divisor())

	var c3: Combatant = _mk_seer()
	_check(c3.pick_ability_talent(&"ultimate", &"bigbang_shielding"), "picks bigbang_shielding")
	_check(c3.big_bang_shield_duration_bonus() == 1, "bigbang_shielding: overflow shield lasts 1 turn longer")

	# bigbang_curing: replicate the exact two orchestrator primitives combat.gd's is_big_bang_active()
	# block chains (heal() then, if the talent is picked, cleanse()) — mirrors
	# tests/test_ability_talents_ranger.gd's own manual-replication convention.
	var c4: Combatant = _mk_seer()
	_check(c4.pick_ability_talent(&"ultimate", &"bigbang_curing"), "picks bigbang_curing")
	var ally: Combatant = _mk_seer()
	ally.max_hp = 100; ally.hp = 50
	var slow: Effect = EffectLibrary.make(&"slow")
	ally.attach_effect(slow)
	_check(ally.has_effect(&"slow"), "sanity: ally carries a debuff before the heal")
	ally.heal(10)
	if c4.has_ability_talent(&"bigbang_curing"):
		ally.cleanse()
	_check(not ally.has_effect(&"slow"), "bigbang_curing: the healed ally's debuff is cleansed")

	# Mutual exclusion within the ultimate row.
	var c5: Combatant = _mk_seer()
	_check(c5.pick_ability_talent(&"ultimate", &"bigbang_deeper"), "first pick on the ultimate row succeeds")
	_check(not c5.pick_ability_talent(&"ultimate", &"bigbang_shielding"), "a second pick on an already-filled row is rejected")

func _init() -> void:
	_test_options_for_shape()
	_test_select_fate_row()
	_test_hex_row()
	_test_foresight_row()
	_test_mana_surge_row()
	_test_arcane_reservoir_row()
	_test_big_bang_row()
	print(("SEER ABILITY TALENTS TEST PASSED" if _failures == 0 else "SEER ABILITY TALENTS TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_seer.gd`
Expected: FAIL on essentially every check — `AbilityTalentLibrary.options_for(&"seer", ...)` still returns `[]`, and none of `foresight_shield_amount()`/`foresight_shield_duration()`/`big_bang_heal_divisor()`/`big_bang_shield_duration_bonus()` exist yet.

- [ ] **Step 3: Implement**

**(a) `combat/ability_talent_library.gd`** — replace the existing empty stub:

```gdscript
		&"seer":
			return []
```

with the full nested match (6 rows × 3 options):

```gdscript
		&"seer":
			match row_id:
				&"base_ability":
					var f1: AbilityTalentOption = AbilityTalentOption.new()
					f1.id = &"fate_deeper"; f1.row_id = row_id
					f1.display_name = "Deeper Fate"
					f1.description = "Select your Fate's added reel deals +15% bonus damage."
					var f2: AbilityTalentOption = AbilityTalentOption.new()
					f2.id = &"fate_wilder"; f2.row_id = row_id
					f2.display_name = "Wilder Fate"
					f2.description = "Select your Fate also grants +1 temporary crit-success face to every reel this spin."
					var f3: AbilityTalentOption = AbilityTalentOption.new()
					f3.id = &"fate_efficient"; f3.row_id = row_id
					f3.display_name = "Efficient Fate"
					f3.description = "Select your Fate's Mana cost is reduced to 5 (was 6)."
					return [f1, f2, f3]
				&"ability_l2":
					var h1: AbilityTalentOption = AbilityTalentOption.new()
					h1.id = &"hex_deeper"; h1.row_id = row_id
					h1.display_name = "Deeper Hex"
					h1.description = "Hex's Cursed DoT deals +25% damage."
					var h2: AbilityTalentOption = AbilityTalentOption.new()
					h2.id = &"hex_lasting"; h2.row_id = row_id
					h2.display_name = "Lasting Hex"
					h2.description = "Hex's Cursed can stack up to 4 times (was 3)."
					var h3: AbilityTalentOption = AbilityTalentOption.new()
					h3.id = &"hex_efficient"; h3.row_id = row_id
					h3.display_name = "Efficient Hex"
					h3.description = "Hex's Mana cost is reduced to 3 (was 4)."
					return [h1, h2, h3]
				&"ability_l3":
					var fo1: AbilityTalentOption = AbilityTalentOption.new()
					fo1.id = &"foresight_deeper"; fo1.row_id = row_id
					fo1.display_name = "Deeper Foresight"
					fo1.description = "Foresight's shield is 20% of max Mana (was 15%)."
					var fo2: AbilityTalentOption = AbilityTalentOption.new()
					fo2.id = &"foresight_lasting"; fo2.row_id = row_id
					fo2.display_name = "Lasting Foresight"
					fo2.description = "Foresight's shield lasts 4 turns (was 3)."
					var fo3: AbilityTalentOption = AbilityTalentOption.new()
					fo3.id = &"foresight_efficient"; fo3.row_id = row_id
					fo3.display_name = "Efficient Foresight"
					fo3.description = "Foresight's Mana cost is reduced to 3 (was 4)."
					return [fo1, fo2, fo3]
				&"ability_l4":
					var ms1: AbilityTalentOption = AbilityTalentOption.new()
					ms1.id = &"surge_deeper"; ms1.row_id = row_id
					ms1.display_name = "Deeper Surge"
					ms1.description = "Mana Surge's Empowered is x1.75 (was x1.6)."
					var ms2: AbilityTalentOption = AbilityTalentOption.new()
					ms2.id = &"surge_refunding"; ms2.row_id = row_id
					ms2.display_name = "Refunding Surge"
					ms2.description = "Mana Surge refunds 25% of its own Mana cost on cast."
					var ms3: AbilityTalentOption = AbilityTalentOption.new()
					ms3.id = &"surge_swift"; ms3.row_id = row_id
					ms3.display_name = "Swift Surge"
					ms3.description = "Mana Surge's cooldown is reduced to 3 turns (was 4)."
					return [ms1, ms2, ms3]
				&"passive":
					var rv1: AbilityTalentOption = AbilityTalentOption.new()
					rv1.id = &"reservoir_deeper"; rv1.row_id = row_id
					rv1.display_name = "Overflowing Reservoir"
					rv1.description = "Arcane Reservoir's max Mana bonus increases to +35% (was +20%)."
					var rv2: AbilityTalentOption = AbilityTalentOption.new()
					rv2.id = &"reservoir_regen"; rv2.row_id = row_id
					rv2.display_name = "Flowing Reservoir"
					rv2.description = "Arcane Reservoir also grants +1 flat Mana regen per Upkeep."
					var rv3: AbilityTalentOption = AbilityTalentOption.new()
					rv3.id = &"reservoir_efficient"; rv3.row_id = row_id
					rv3.display_name = "Efficient Reservoir"
					rv3.description = "All of this Seer's ability Mana costs (Select your Fate, Hex, Foresight, Mana Surge) are reduced by 1."
					return [rv1, rv2, rv3]
				&"ultimate":
					var bb1: AbilityTalentOption = AbilityTalentOption.new()
					bb1.id = &"bigbang_deeper"; bb1.row_id = row_id
					bb1.display_name = "Deeper Bang"
					bb1.description = "The Big Bang heals each ally 1/5 of the spin's total damage (was 1/6)."
					var bb2: AbilityTalentOption = AbilityTalentOption.new()
					bb2.id = &"bigbang_curing"; bb2.row_id = row_id
					bb2.display_name = "Curing Bang"
					bb2.description = "The Big Bang also cleanses each healed ally's active debuffs."
					var bb3: AbilityTalentOption = AbilityTalentOption.new()
					bb3.id = &"bigbang_shielding"; bb3.row_id = row_id
					bb3.display_name = "Shielding Bang"
					bb3.description = "The Big Bang's overflow shield lasts 1 turn longer."
					return [bb1, bb2, bb3]
				_:
					return []
```

**(b) `combat/combatant.gd` — `apply_select_fate()`**, change from:

```gdscript
func apply_select_fate(chosen_type: DamageType, cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"mana": cost}):
		return false
	turn_reels.append(ActionReel.make_default(chosen_type))  # +1 weapon-attack reel (joins paylines)
	convert_turn_reels_to(chosen_type)
	return true
```

to:

```gdscript
func apply_select_fate(chosen_type: DamageType, cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"mana": cost}):
		return false
	var extra: ActionReel = ActionReel.make_default(chosen_type)
	if has_ability_talent(&"fate_deeper"):
		# The added reel isn't rider-carrying, so there's nothing for the generic
		# rider_talent_bonus_damage_pct() hook to key off — scale this freshly-constructed reel's own
		# hit faces directly (reel-instance-scoped, same approach Vanguard's Task 16 used for
		# slam_deeper/rampage_deeper, for the same underlying reason: no rider to key a shared hook off).
		for f: ReelFace in extra.faces:
			if f.result_tier == ReelFace.ResultTier.SUCCESS or f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
				f.multiplier *= 1.15
	turn_reels.append(extra)  # +1 weapon-attack reel (joins paylines)
	if has_ability_talent(&"fate_wilder"):
		# Mirrors apply_loaded_dice's exact mechanism: add 1 temporary crit-success face to EACH of
		# this turn's reels (including the one just appended), deep-copying so the underlying weapon
		# is never mutated.
		for i: int in range(turn_reels.size()):
			var r: ActionReel = turn_reels[i].duplicate(true)
			var f: ReelFace = ReelFace.new()
			f.result_tier = ReelFace.ResultTier.CRIT_SUCCESS
			f.multiplier = 2.0
			r.faces.append(f)
			r.faces.shuffle()
			turn_reels[i] = r
	convert_turn_reels_to(chosen_type)
	return true
```

**(c) `combat/combatant.gd` — `apply_mana_surge()`**, change from:

```gdscript
func apply_mana_surge(type: DamageType, cost: int, reel_cap: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"mana": cost}):
		return false
	var e: Effect = EffectLibrary.make(&"empowered")
	e.magnitude = 1.6
	e.duration = 1
	attach_effect(e)
	for i: int in range(2):
		if turn_reels.size() < reel_cap:
			turn_reels.append(ActionReel.make_default(type))
	return true
```

to:

```gdscript
func apply_mana_surge(type: DamageType, cost: int, reel_cap: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"mana": cost}):
		return false
	if has_ability_talent(&"surge_refunding"):
		resource_pool.refund({&"mana": ceili(cost * 0.25)})
	var e: Effect = EffectLibrary.make(&"empowered")
	e.magnitude = 1.75 if has_ability_talent(&"surge_deeper") else 1.6
	e.duration = 1
	attach_effect(e)
	for i: int in range(2):
		if turn_reels.size() < reel_cap:
			turn_reels.append(ActionReel.make_default(type))
	return true
```

**(d) `combat/combatant.gd` — `passive_max_mana_multiplier()`**, change the `&"arcane_reservoir":` arm from:

```gdscript
	match passive_ability_id:
		&"arcane_reservoir":
			return 1.2
		_:
			return 1.0
```

to:

```gdscript
	match passive_ability_id:
		&"arcane_reservoir":
			return 1.35 if has_ability_talent(&"reservoir_deeper") else 1.2
		_:
			return 1.0
```

**(e) `combat/combatant.gd` — `apply_stats()`**, change the mana-regen line from:

```gdscript
		if base_max_mana > 0:
			resource_pool.mana_regen_per_turn = base_mana_regen + focus_regen_bonus
```

to:

```gdscript
		if base_max_mana > 0:
			var reservoir_regen_bonus: int = 1 if (class_id == &"seer" and has_ability_talent(&"reservoir_regen")) else 0
			resource_pool.mana_regen_per_turn = base_mana_regen + focus_regen_bonus + reservoir_regen_bonus
```

**(f) `combat/combatant.gd` — 4 new helper methods** (near `thorns_pct()`/`passive_max_mana_multiplier()`):

```gdscript
## Seer "Foresight" (L7) shield amount: 20% of max Mana with Deeper Foresight, else 15%. Read by
## combat.gd's foresight_pending block (Task 20) so the math stays directly unit-testable.
func foresight_shield_amount() -> int:
	var pct: float = 0.20 if has_ability_talent(&"foresight_deeper") else 0.15
	return ceili(float(resource_pool.max_mana) * pct)

## Seer "Foresight" shield duration: 4 turns with Lasting Foresight, else 3.
func foresight_shield_duration() -> int:
	return 4 if has_ability_talent(&"foresight_lasting") else 3

## Seer "The Big Bang" heal-fraction divisor: heals ceil(total / this) to each ally. 5.0 (1/5) with
## Deeper Bang, else 6.0 (1/6). Read by combat.gd's is_big_bang_active() block (Task 20).
func big_bang_heal_divisor() -> float:
	return 5.0 if has_ability_talent(&"bigbang_deeper") else 6.0

## Seer "The Big Bang" overflow-shield duration BONUS (turns added on top of BIG_BANG_SHIELD_TURNS).
## 1 with Shielding Bang, else 0.
func big_bang_shield_duration_bonus() -> int:
	return 1 if has_ability_talent(&"bigbang_shielding") else 0
```

**(g) `combat/combatant.gd` — the 3 shared dispatch methods that need a Seer arm.** Change each from
its post-Task-19 state (add the `&"seer":` arm alongside Warrior/Vanguard/Skirmisher/Chancer/Ranger's
existing arms — do not disturb them):

```gdscript
func ability_talent_cost_delta(ability_id: StringName) -> int:
	match class_id:
		&"warrior":
			match ability_id:
				&"rend":
					return -1 if has_ability_talent(&"rend_efficient") else 0
				&"sundering_strike":
					return -1 if has_ability_talent(&"sunder_efficient") else 0
				_:
					return 0
		&"vanguard":
			match ability_id:
				&"heft":
					return -1 if has_ability_talent(&"heft_efficient") else 0
				&"bloodwrath":
					return -1 if has_ability_talent(&"wrath_efficient") else 0
				&"quake_slam":
					return -1 if has_ability_talent(&"slam_efficient") else 0
				_:
					return 0
		&"skirmisher":
			match ability_id:
				&"flurry":
					return -1 if has_ability_talent(&"flurry_efficient") else 0
				&"feint_riposte":
					return -1 if has_ability_talent(&"feint_efficient") else 0
				&"quickstep":
					return -1 if has_ability_talent(&"step_efficient") else 0
				_:
					return 0
		&"chancer":
			match ability_id:
				&"reroll":
					return -1 if has_ability_talent(&"reroll_efficient") else 0
				&"loaded_dice":
					return -1 if has_ability_talent(&"dice_efficient") else 0
				&"jinx_the_odds":
					return -1 if has_ability_talent(&"jinx_efficient") else 0
				_:
					return 0
		&"ranger":
			match ability_id:
				&"hunters_mark":
					return -1 if has_ability_talent(&"mark_efficient") else 0
				&"aimed_shot":
					return -1 if has_ability_talent(&"aim_efficient") else 0
				&"snare_trap":
					return -1 if has_ability_talent(&"snare_efficient") else 0
				_:
					return 0
		_:
			return 0
```

to:

```gdscript
func ability_talent_cost_delta(ability_id: StringName) -> int:
	match class_id:
		&"warrior":
			match ability_id:
				&"rend":
					return -1 if has_ability_talent(&"rend_efficient") else 0
				&"sundering_strike":
					return -1 if has_ability_talent(&"sunder_efficient") else 0
				_:
					return 0
		&"vanguard":
			match ability_id:
				&"heft":
					return -1 if has_ability_talent(&"heft_efficient") else 0
				&"bloodwrath":
					return -1 if has_ability_talent(&"wrath_efficient") else 0
				&"quake_slam":
					return -1 if has_ability_talent(&"slam_efficient") else 0
				_:
					return 0
		&"skirmisher":
			match ability_id:
				&"flurry":
					return -1 if has_ability_talent(&"flurry_efficient") else 0
				&"feint_riposte":
					return -1 if has_ability_talent(&"feint_efficient") else 0
				&"quickstep":
					return -1 if has_ability_talent(&"step_efficient") else 0
				_:
					return 0
		&"chancer":
			match ability_id:
				&"reroll":
					return -1 if has_ability_talent(&"reroll_efficient") else 0
				&"loaded_dice":
					return -1 if has_ability_talent(&"dice_efficient") else 0
				&"jinx_the_odds":
					return -1 if has_ability_talent(&"jinx_efficient") else 0
				_:
					return 0
		&"ranger":
			match ability_id:
				&"hunters_mark":
					return -1 if has_ability_talent(&"mark_efficient") else 0
				&"aimed_shot":
					return -1 if has_ability_talent(&"aim_efficient") else 0
				&"snare_trap":
					return -1 if has_ability_talent(&"snare_efficient") else 0
				_:
					return 0
		&"seer":
			# reservoir_efficient (passive row) reduces ALL FOUR Seer abilities by 1 at once — broader
			# than every other class's single-ability "Efficient X" shape (Task 20's Implementation
			# note 4). Each ability's OWN "_efficient" talent lives in a different row and stacks with it.
			var reservoir_bonus: int = -1 if has_ability_talent(&"reservoir_efficient") else 0
			match ability_id:
				&"select_fate":
					return reservoir_bonus + (-1 if has_ability_talent(&"fate_efficient") else 0)
				&"hex":
					return reservoir_bonus + (-1 if has_ability_talent(&"hex_efficient") else 0)
				&"foresight":
					return reservoir_bonus + (-1 if has_ability_talent(&"foresight_efficient") else 0)
				&"mana_surge":
					return reservoir_bonus
				_:
					return 0
		_:
			return 0
```

```gdscript
func ability_talent_cooldown_delta(ability_id: StringName) -> int:
	match class_id:
		&"warrior":
			match ability_id:
				&"second_wind":
					return -1 if has_ability_talent(&"wind_swift") else 0
				_:
					return 0
		&"vanguard":
			match ability_id:
				&"mountain_stance":
					return -1 if has_ability_talent(&"stance_swift") else 0
				_:
					return 0
		&"skirmisher":
			match ability_id:
				&"riposte_storm":
					return -1 if has_ability_talent(&"storm_swift") else 0
				_:
					return 0
		&"chancer":
			match ability_id:
				&"double_or_nothing":
					return -1 if has_ability_talent(&"gamble_swift") else 0
				_:
					return 0
		&"ranger":
			match ability_id:
				&"crippling_shot":
					return -1 if has_ability_talent(&"crippling_swift") else 0
				_:
					return 0
		_:
			return 0
```

to:

```gdscript
func ability_talent_cooldown_delta(ability_id: StringName) -> int:
	match class_id:
		&"warrior":
			match ability_id:
				&"second_wind":
					return -1 if has_ability_talent(&"wind_swift") else 0
				_:
					return 0
		&"vanguard":
			match ability_id:
				&"mountain_stance":
					return -1 if has_ability_talent(&"stance_swift") else 0
				_:
					return 0
		&"skirmisher":
			match ability_id:
				&"riposte_storm":
					return -1 if has_ability_talent(&"storm_swift") else 0
				_:
					return 0
		&"chancer":
			match ability_id:
				&"double_or_nothing":
					return -1 if has_ability_talent(&"gamble_swift") else 0
				_:
					return 0
		&"ranger":
			match ability_id:
				&"crippling_shot":
					return -1 if has_ability_talent(&"crippling_swift") else 0
				_:
					return 0
		&"seer":
			match ability_id:
				&"mana_surge":
					return -1 if has_ability_talent(&"surge_swift") else 0
				_:
					return 0
		_:
			return 0
```

```gdscript
func apply_rider_talent_adjustments(rider_id: StringName, effect: Effect, target: Combatant) -> void:
	match class_id:
		&"warrior":
			match rider_id:
				&"bleed":
					if has_ability_talent(&"rend_deeper_cut"):
						for i: int in range(effect.dot_fractions.size()):
							effect.dot_fractions[i] *= 1.25
					if has_ability_talent(&"rend_lasting_wound"):
						effect.max_stacks = 4
						if effect.dot_fractions.size() < 4:
							effect.dot_fractions.append(1.55)
				&"sundered":
					if has_ability_talent(&"sunder_deeper"):
						effect.magnitude = 1.35
					if has_ability_talent(&"sunder_lingering"):
						effect.duration = 3
		&"chancer":
			match rider_id:
				&"jinxed":
					if has_ability_talent(&"jinx_lasting"):
						effect.duration = 3
		&"ranger":
			match rider_id:
				&"hunters_mark":
					if has_ability_talent(&"mark_deeper"):
						effect.duration = 4
					if has_ability_talent(&"mark_weakening"):
						target.attach_effect(EffectLibrary.make(&"weakened"))
				&"rooted":
					if has_ability_talent(&"snare_lasting"):
						effect.duration = 3
				&"weakened":
					if has_ability_talent(&"crippling_lasting"):
						effect.duration = 3
		_:
			pass
```

to:

```gdscript
func apply_rider_talent_adjustments(rider_id: StringName, effect: Effect, target: Combatant) -> void:
	match class_id:
		&"warrior":
			match rider_id:
				&"bleed":
					if has_ability_talent(&"rend_deeper_cut"):
						for i: int in range(effect.dot_fractions.size()):
							effect.dot_fractions[i] *= 1.25
					if has_ability_talent(&"rend_lasting_wound"):
						effect.max_stacks = 4
						if effect.dot_fractions.size() < 4:
							effect.dot_fractions.append(1.55)
				&"sundered":
					if has_ability_talent(&"sunder_deeper"):
						effect.magnitude = 1.35
					if has_ability_talent(&"sunder_lingering"):
						effect.duration = 3
		&"chancer":
			match rider_id:
				&"jinxed":
					if has_ability_talent(&"jinx_lasting"):
						effect.duration = 3
		&"ranger":
			match rider_id:
				&"hunters_mark":
					if has_ability_talent(&"mark_deeper"):
						effect.duration = 4
					if has_ability_talent(&"mark_weakening"):
						target.attach_effect(EffectLibrary.make(&"weakened"))
				&"rooted":
					if has_ability_talent(&"snare_lasting"):
						effect.duration = 3
				&"weakened":
					if has_ability_talent(&"crippling_lasting"):
						effect.duration = 3
		&"seer":
			match rider_id:
				&"cursed":
					if has_ability_talent(&"hex_deeper"):
						for i: int in range(effect.dot_fractions.size()):
							effect.dot_fractions[i] *= 1.25
					if has_ability_talent(&"hex_lasting"):
						effect.max_stacks = 4
						if effect.dot_fractions.size() < 4:
							effect.dot_fractions.append(1.55)
		_:
			pass
```

`rider_talent_bonus_damage_pct()` is **not** modified by this task — Seer has no own-hit-bonus-damage
option (see the Interfaces note above).

**(h) `combat/combat.gd` — the `foresight_pending` block in `_commit_main1()`**, change from:

```gdscript
	if _attacker.foresight_pending:
		var ally: Combatant = _lowest_hp_pct_ally(_attacker)
		if ally != null:
			var amount: int = ceili(_attacker.resource_pool.max_mana * 0.15)
			ally.apply_shield(amount, 3)
			_log("  🔮 %s grants Foresight — %s shields %d HP." % [_attacker.display_name, ally.display_name, amount])
		_attacker.foresight_pending = false
```

to:

```gdscript
	if _attacker.foresight_pending:
		var ally: Combatant = _lowest_hp_pct_ally(_attacker)
		if ally != null:
			# Seer Ability Talents (Task 20): Deeper Foresight (shield %) / Lasting Foresight (duration)
			# are read via two small Combatant helpers (mirrors Vanguard's bloodwrath_bonus_pct()
			# precedent, Task 16) so the math stays directly unit-testable.
			var amount: int = _attacker.foresight_shield_amount()
			ally.apply_shield(amount, _attacker.foresight_shield_duration())
			_log("  🔮 %s grants Foresight — %s shields %d HP." % [_attacker.display_name, ally.display_name, amount])
		_attacker.foresight_pending = false
```

**(i) `combat/combat.gd` — the Big Bang heal block**, change from:

```gdscript
	if _attacker.is_big_bang_active():
		var heal_amt: int = ceili(_big_bang_total / 6.0)
		_log("  ✶ THE BIG BANG: %d total damage → heal %d to each ally (1/6)." % [_big_bang_total, heal_amt])
		for ally: Combatant in _allies_of(_attacker):
			var overflow: int = ally.heal(heal_amt)
			var restored: int = heal_amt - overflow
			if overflow > 0:
				ally.apply_shield(overflow, BIG_BANG_SHIELD_TURNS)
				_log("    %s +%d HP, excess %d → SHIELD %d (%d turns)." % [ally.display_name, restored, overflow, ally.shield_hp, ally.shield_turns])
			elif restored > 0:
				_log("    %s +%d HP." % [ally.display_name, restored])
			if _panels.has(ally):
				(_panels[ally] as CombatantPanel).refresh_status()
				(_panels[ally] as CombatantPanel).refresh_shield()
		_attacker.consume_big_bang_spin()
```

to:

```gdscript
	if _attacker.is_big_bang_active():
		# Seer Ability Talents (Task 20): Deeper Bang's heal fraction and Shielding Bang's extra shield
		# duration are read via two small Combatant helpers (same bloodwrath_bonus_pct() precedent as
		# the Foresight block above).
		var heal_divisor: float = _attacker.big_bang_heal_divisor()
		var heal_amt: int = ceili(_big_bang_total / heal_divisor)
		var shield_turns: int = BIG_BANG_SHIELD_TURNS + _attacker.big_bang_shield_duration_bonus()
		_log("  ✶ THE BIG BANG: %d total damage → heal %d to each ally (1/%d)." % [_big_bang_total, heal_amt, int(heal_divisor)])
		for ally: Combatant in _allies_of(_attacker):
			var overflow: int = ally.heal(heal_amt)
			var restored: int = heal_amt - overflow
			if overflow > 0:
				ally.apply_shield(overflow, shield_turns)
				_log("    %s +%d HP, excess %d → SHIELD %d (%d turns)." % [ally.display_name, restored, overflow, ally.shield_hp, ally.shield_turns])
			elif restored > 0:
				_log("    %s +%d HP." % [ally.display_name, restored])
			# Curing Bang: cleanse a debuff from every ally this heal reaches. No "remove exactly 1"
			# primitive exists in this codebase — reuses the same full-cleanse() precedent as Warrior's
			# guard_cleansing / Second Wind (Task 15's own comment).
			if _attacker.has_ability_talent(&"bigbang_curing"):
				ally.cleanse()
			if _panels.has(ally):
				(_panels[ally] as CombatantPanel).refresh_status()
				(_panels[ally] as CombatantPanel).refresh_shield()
		_attacker.consume_big_bang_spin()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_seer.gd`
Expected: all lines print `ok:`.

- [ ] **Step 5: Run the full test suite**

Run every `tests/test_*.gd` file headlessly and confirm exit code 0 for each. The 3 known
pre-existing failures predate this whole effort and are NOT regressions: `test_adventuring_board_panel.gd`
(1 internal FAIL line), `test_overworld_demo_npcs.gd` (5), `test_overworld_encounter_variety.gd` (6).
Any other nonzero exit is a real regression and must be root-caused before committing — give this run
extra scrutiny on `apply_stats()`/`passive_max_mana_multiplier()` (shared, widely-called) and the two
`combat.gd` orchestrator blocks touched here.

- [ ] **Step 6: Commit**

```bash
git add combat/ability_talent_library.gd combat/combatant.gd combat/combat.gd tests/test_ability_talents_seer.gd
git commit -m "feat(talents): Seer Ability Talents — 18 options across Select your Fate/Hex/Foresight/Mana Surge/Arcane Reservoir/The Big Bang"
```

---
## Implementation note (no reword needed)

All 18 approved Warden options are implemented exactly as specified in Task 12's checkpoint table — no cost/scope reword was required. Verified before writing anything:

- `combat/resources/types/earth.tres` has **no `inherent_rider_id`** set (absent from the `.tres`, so it defaults to `DamageType`'s `&""`). Unlike Vanguard's Crushing/`&"slow"` collision (Task 16), Warden's own rider ids (`&"rooted"` from Entangle, `&"regen"` from Regrowth) don't collide with the weapon's own inherent rider or with each other — Warden is in the same clean situation Chancer (Task 18) and Ranger (Task 19) were in, so `apply_rider_talent_adjustments()`/`rider_talent_bonus_damage_pct()` get real, generic Warden arms with no reel-instance-scoped workaround.
- `quake_deeper` reuses `_splash_half_to_others()`'s optional `fraction: float = 0.5` parameter, which **already exists** — added by Task 19 for Ranger's Deeper Collateral. No second parameter is invented; Warden's own call site just passes a non-default value when the talent is picked.
- `cry_deeper`/`cry_lasting` (Rallying Cry's shield amount/duration) are applied at the shield-computation site inside `combat.gd`'s `_finish_spin()`, not a `Combatant` method — Rallying Cry's shield math has always lived at the orchestrator level (it reads the reel's post-spin tier, which only the orchestrator knows). This is a small inline-check addition at an existing site, the same weight as the Wild/Collateral/Rampage lasting-spin edits already in this plan.
- `quake_rooting`'s new Rooted attaches are routed through `apply_rider_talent_adjustments(&"rooted", ...)`, so a Warden who's also picked `entangle_lasting` gets the 3-turn Rooted duration on Earthquake's splash too — a deliberate, consistent bonus, mirroring Warrior's Bleeding Wild precedent (Task 15) exactly.

---

## Task 21: Warden Ability Talents (18 options)

**Files:**
- Modify: `combat/ability_talent_library.gd` (fills in the `&"warden":` branch of `options_for()`)
- Modify: `combat/combatant.gd` (`apply_bastion()`, `passive_dot_damage_multiplier()`'s `&"deep_roots":` arm, `passive_upkeep_heal_amount()`'s `&"deep_roots":` arm, `thorns_pct()`, and the 4 shared dispatch methods gaining a `&"warden":` arm)
- Modify: `combat/combat.gd` (`_commit_main1()`'s `regrowth_pending` block gains an `apply_rider_talent_adjustments()` call; `_finish_spin()`'s Rallying Cry shield block gains the `cry_deeper`/`cry_lasting` checks; `_finish_spin()`'s Earthquake block gains the `quake_deeper` fraction pick and the `quake_rooting` Rooted-application loop)
- Modify: `combat/main_phase_plan.gd` (`commit()`'s `&"earthquake":` arm gains the `quake_lasting` spin-count branch)
- Test: `tests/test_ability_talents_warden.gd` (new)

**Interfaces:**
- Consumes: Task 14's `Combatant.class_id` / `ability_talent_picks` / `has_ability_talent()` /
  `pick_ability_talent()` / `ability_talent_cost_delta()` / `ability_talent_cooldown_delta()` /
  `apply_rider_talent_adjustments()` / `rider_talent_bonus_damage_pct()` scaffolds, and
  `AbilityTalentLibrary.options_for()`'s empty `&"warden":` fallback. Reuses Task 19's
  `_splash_half_to_others(attacker, total, type_label, fraction: float = 0.5)` signature directly (no
  second fraction param invented). Also consumes the existing Warden infrastructure:
  `apply_rallying_cry`, `try_entangle`, `stage_regrowth`, `apply_bastion`, `fire_earthquake`,
  `is_earthquake_active`, `consume_earthquake_spin`, `passive_dot_damage_multiplier`,
  `passive_upkeep_heal_amount`, `thorns_pct`, and the `&"rooted"`/`&"regen"`/`&"guarded"`/`&"taunt"`
  `EffectLibrary` entries.
- Produces: 18 populated `AbilityTalentOption` entries for Warden across all 6 rows; talent-aware
  Rallying Cry/Entangle/Regrowth/Bastion/Deep Roots/Earthquake behavior. Confirms (verified against
  `combat/resources/types/earth.tres`) that Earth carries no `inherent_rider_id`, so — unlike
  Vanguard (Task 16) — Warden needs no reel-instance-scoped workaround for `entangle_deeper`/
  `regrowth_deeper`/`regrowth_lasting`; both generic dispatch hooks get real `&"warden":` arms.

- [ ] **Step 1: Write the failing test**

Create `tests/test_ability_talents_warden.gd`:

```gdscript
extends SceneTree

# Headless test: the Warden's 18 Ability Talent options (Task 21) — one row of 3 mutually-
# exclusive picks per Warden ability (Rallying Cry / Entangle / Regrowth / Bastion / Deep Roots /
# Earthquake). Exercises AbilityTalentLibrary.options_for(&"warden", row_id),
# pick_ability_talent()/has_ability_talent(), the cost/cooldown-delta dispatch methods, and the
# GENERIC apply_rider_talent_adjustments()/rider_talent_bonus_damage_pct() hooks — Warden's Earth
# weapon type carries no inherent_rider_id (verified against combat/resources/types/earth.tres), so
# unlike Vanguard's Quake Slam (Task 16) neither of Warden's own rider ids (rooted from Entangle,
# regen from Regrowth) needs a reel-instance-scoped workaround; Warden is in the same clean
# situation Chancer (Task 18) and Ranger (Task 19) were in.
#
# Deeper Cry/Lasting Cry's actual shield-amount/duration math (Rallying Cry's shield has always been
# computed at the orchestrator level, in combat.gd's own _finish_spin() — not a Combatant method,
# distinct from every other ability in this plan so far) and Rooting Quake's actual on-splash Rooted
# attach both live in combat.gd — orchestrator-level, require a running Combat scene — and are NOT
# headlessly tested here, consistent with this codebase's own documented precedent
# (tests/test_ability_talents_warrior.gd's header comment on Bleeding Wild). Where the underlying
# math is checkable directly (Deeper Quake's splash-fraction formula, mirroring
# tests/test_ability_talents_ranger.gd's own manual-replication convention for Deeper Collateral) or
# a manually-simulated loop is checkable (Rooting Quake's exact splash+root loop, has_ability_talent,
# the pending flags combat.gd's wiring reads), this test proves that instead.
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_warden.gd

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _mk_warden() -> Combatant:
	var c: Combatant = ClassLibrary.make(&"warden").build_combatant(true)
	c.level = Combatant.MAX_LEVEL  # unlocks every talent row (5/6/7/8/9/10)
	c.resource_pool.mana = 20
	return c

func _test_options_for_shape() -> void:
	var rows: Array[StringName] = [&"base_ability", &"ability_l2", &"ability_l3", &"ability_l4", &"passive", &"ultimate"]
	var all_ids: Array[StringName] = [
		&"cry_deeper", &"cry_lasting", &"cry_efficient",
		&"entangle_deeper", &"entangle_lasting", &"entangle_efficient",
		&"regrowth_deeper", &"regrowth_lasting", &"regrowth_efficient",
		&"bastion_deeper", &"bastion_reinforced", &"bastion_swift",
		&"roots_deeper", &"roots_regen", &"roots_thorned",
		&"quake_deeper", &"quake_rooting", &"quake_lasting",
	]
	var seen: Array[StringName] = []
	for row: StringName in rows:
		var opts: Array[AbilityTalentOption] = AbilityTalentLibrary.options_for(&"warden", row)
		_check(opts.size() == 3, "Warden row %s has exactly 3 options (got %d)" % [row, opts.size()])
		for o: AbilityTalentOption in opts:
			_check(o.row_id == row, "option %s reports its own row_id (%s)" % [o.id, row])
			_check(o.display_name != "" and o.description != "", "option %s has a non-empty display_name/description" % o.id)
			seen.append(o.id)
	for id: StringName in all_ids:
		_check(id in seen, "option %s is present in AbilityTalentLibrary.options_for(&warden, ...)" % id)

func _test_rallying_cry_row() -> void:
	var c: Combatant = _mk_warden()
	_check(c.ability_talent_cost_delta(&"rallying_cry") == 0, "no Rallying Cry cost delta with nothing picked")
	_check(c.pick_ability_talent(&"base_ability", &"cry_efficient"), "picks cry_efficient")
	_check(c.has_ability_talent(&"cry_efficient"), "has_ability_talent sees cry_efficient")
	_check(c.ability_talent_cost_delta(&"rallying_cry") == -1, "cry_efficient: Rallying Cry costs 1 less Mana")

	# Deeper Cry/Lasting Cry's actual shield-amount/duration math lives in combat.gd's own
	# _finish_spin() (see this task's Implementation note) — NOT headlessly tested here, consistent
	# with this file's own header comment. This proves the precondition state combat.gd's wiring reads.
	var c2: Combatant = _mk_warden()
	_check(c2.pick_ability_talent(&"base_ability", &"cry_deeper"), "picks cry_deeper")
	_check(c2.apply_rallying_cry(4, 6), "casts Rallying Cry (deeper)")
	_check(c2.rallying_cry_reel != null, "Rallying Cry's reel is recorded for combat.gd's wiring to read")

	var c3: Combatant = _mk_warden()
	_check(c3.pick_ability_talent(&"base_ability", &"cry_lasting"), "picks cry_lasting")
	_check(c3.apply_rallying_cry(4, 6), "casts Rallying Cry (lasting)")
	_check(c3.has_ability_talent(&"cry_lasting"), "has_ability_talent sees cry_lasting")

	# Mutual exclusion: only 1 pick per row.
	var c4: Combatant = _mk_warden()
	_check(c4.pick_ability_talent(&"base_ability", &"cry_efficient"), "first pick on the Rallying Cry row succeeds")
	_check(not c4.pick_ability_talent(&"base_ability", &"cry_deeper"), "a second pick on an already-filled row is rejected (cap of 1/row)")

func _test_entangle_row() -> void:
	var c: Combatant = _mk_warden()
	_check(c.ability_talent_cost_delta(&"entangle") == 0, "no Entangle cost delta with nothing picked")
	_check(c.pick_ability_talent(&"ability_l2", &"entangle_efficient"), "picks entangle_efficient")
	_check(c.ability_talent_cost_delta(&"entangle") == -1, "entangle_efficient: Entangle costs 1 less Mana")

	var c2: Combatant = _mk_warden()
	_check(c2.pick_ability_talent(&"ability_l2", &"entangle_deeper"), "picks entangle_deeper")
	_check(is_equal_approx(c2.rider_talent_bonus_damage_pct(&"rooted"), 0.15), "entangle_deeper: +15%% bonus damage on Entangle's own hit (got %.3f)" % c2.rider_talent_bonus_damage_pct(&"rooted"))
	_check(is_equal_approx(c2.rider_talent_bonus_damage_pct(&"regen"), 0.0), "entangle_deeper only applies to the rooted rider id, not any other")

	var c3: Combatant = _mk_warden()
	_check(c3.pick_ability_talent(&"ability_l2", &"entangle_lasting"), "picks entangle_lasting")
	var rooted: Effect = EffectLibrary.make(&"rooted")
	_check(rooted.duration == 2, "sanity: Rooted's baseline duration is 2")
	c3.apply_rider_talent_adjustments(&"rooted", rooted, c3)
	_check(rooted.duration == 3, "entangle_lasting: Rooted lasts 3 turns (got %d)" % rooted.duration)

	var c4: Combatant = _mk_warden()
	_check(c4.try_entangle(c4.weapon_type(), 4, 6), "casts Entangle (sanity: unaffected structurally by talents)")

	# Mutual exclusion: only 1 pick per row.
	var c5: Combatant = _mk_warden()
	_check(c5.pick_ability_talent(&"ability_l2", &"entangle_efficient"), "first pick on the Entangle row succeeds")
	_check(not c5.pick_ability_talent(&"ability_l2", &"entangle_deeper"), "a second pick on an already-filled row is rejected (cap of 1/row)")

func _test_regrowth_row() -> void:
	var c: Combatant = _mk_warden()
	_check(c.ability_talent_cost_delta(&"regrowth") == 0, "no Regrowth cost delta with nothing picked")
	_check(c.pick_ability_talent(&"ability_l3", &"regrowth_efficient"), "picks regrowth_efficient")
	_check(c.ability_talent_cost_delta(&"regrowth") == -1, "regrowth_efficient: Regrowth costs 1 less Mana")

	var c2: Combatant = _mk_warden()
	_check(c2.pick_ability_talent(&"ability_l3", &"regrowth_deeper"), "picks regrowth_deeper")
	var regen: Effect = EffectLibrary.make(&"regen")
	var base_fractions: Array = regen.dot_fractions.duplicate()
	c2.apply_rider_talent_adjustments(&"regen", regen, c2)
	for i: int in range(base_fractions.size()):
		_check(is_equal_approx(regen.dot_fractions[i], base_fractions[i] * 1.25),
			"regrowth_deeper: Regen fraction %d is +25%% (got %.4f, want %.4f)" % [i, regen.dot_fractions[i], base_fractions[i] * 1.25])
	_check(regen.max_stacks == 3, "regrowth_deeper alone leaves max_stacks at 3")

	var c3: Combatant = _mk_warden()
	_check(c3.pick_ability_talent(&"ability_l3", &"regrowth_lasting"), "picks regrowth_lasting")
	var regen2: Effect = EffectLibrary.make(&"regen")
	c3.apply_rider_talent_adjustments(&"regen", regen2, c3)
	_check(regen2.max_stacks == 4, "regrowth_lasting: Regen max_stacks is 4 (got %d)" % regen2.max_stacks)
	_check(regen2.dot_fractions.size() == 4, "regrowth_lasting: Regen gained a 4th stack fraction (got %d entries)" % regen2.dot_fractions.size())
	_check(is_equal_approx(regen2.dot_fractions[3], 1.55), "regrowth_lasting: 4th stack fraction is 1.55 (got %.4f)" % regen2.dot_fractions[3])

	var c4: Combatant = _mk_warden()
	_check(c4.stage_regrowth(4), "stages Regrowth (sanity: unaffected structurally by talents)")
	_check(c4.regrowth_pending, "Regrowth is pending for combat.gd's commit-time wiring to read")

	# Mutual exclusion: only 1 pick per row.
	var c5: Combatant = _mk_warden()
	_check(c5.pick_ability_talent(&"ability_l3", &"regrowth_efficient"), "first pick on the Regrowth row succeeds")
	_check(not c5.pick_ability_talent(&"ability_l3", &"regrowth_deeper"), "a second pick on an already-filled row is rejected (cap of 1/row)")

func _test_bastion_row() -> void:
	var c: Combatant = _mk_warden()
	_check(c.apply_bastion(6), "casts Bastion (baseline)")
	var g: Effect = c._find_effect(&"guarded")
	_check(g != null, "sanity: Guarded attached")
	_check(is_equal_approx(g.magnitude, 0.5), "baseline Bastion: Guarded magnitude 0.5")
	_check(is_equal_approx(g.thorns_pct, 0.20), "baseline Bastion: Thorns 20%%")

	var c2: Combatant = _mk_warden()
	_check(c2.pick_ability_talent(&"ability_l4", &"bastion_deeper"), "picks bastion_deeper")
	_check(c2.apply_bastion(6), "casts Bastion (deeper)")
	var g2: Effect = c2._find_effect(&"guarded")
	_check(is_equal_approx(g2.thorns_pct, 0.30), "bastion_deeper: Thorns is 30%% (got %.3f)" % g2.thorns_pct)

	var c3: Combatant = _mk_warden()
	_check(c3.pick_ability_talent(&"ability_l4", &"bastion_reinforced"), "picks bastion_reinforced")
	_check(c3.apply_bastion(6), "casts Bastion (reinforced)")
	var g3: Effect = c3._find_effect(&"guarded")
	_check(is_equal_approx(g3.magnitude, 0.4), "bastion_reinforced: Guarded magnitude 0.4 (got %.3f)" % g3.magnitude)

	var c4: Combatant = _mk_warden()
	_check(c4.ability_talent_cooldown_delta(&"bastion") == 0, "no Bastion cooldown delta with nothing picked")
	_check(c4.pick_ability_talent(&"ability_l4", &"bastion_swift"), "picks bastion_swift")
	_check(c4.ability_talent_cooldown_delta(&"bastion") == -1, "bastion_swift: Bastion's cooldown is 1 less turn")

	# Mutual exclusion: only 1 pick per row.
	var c5: Combatant = _mk_warden()
	_check(c5.pick_ability_talent(&"ability_l4", &"bastion_deeper"), "first pick on the Bastion row succeeds")
	_check(not c5.pick_ability_talent(&"ability_l4", &"bastion_reinforced"), "a second pick on an already-filled row is rejected (cap of 1/row)")

func _test_deep_roots_row() -> void:
	var c: Combatant = _mk_warden()
	c.passive_ability_id = &"deep_roots"
	c.max_hp = 160
	_check(is_equal_approx(c.passive_dot_damage_multiplier(), 0.85), "baseline Deep Roots: -15% incoming DoT damage")
	_check(c.passive_upkeep_heal_amount() == 10, "baseline Deep Roots: Upkeep heal is ceil(160/16) = 10 (got %d)" % c.passive_upkeep_heal_amount())
	_check(is_equal_approx(c.thorns_pct(), 0.0), "baseline Deep Roots grants no Thorns")

	var c2: Combatant = _mk_warden()
	c2.passive_ability_id = &"deep_roots"
	_check(c2.pick_ability_talent(&"passive", &"roots_deeper"), "picks roots_deeper")
	_check(is_equal_approx(c2.passive_dot_damage_multiplier(), 0.75), "roots_deeper: -25%% incoming DoT damage (got %.3f)" % c2.passive_dot_damage_multiplier())

	var c3: Combatant = _mk_warden()
	c3.passive_ability_id = &"deep_roots"
	c3.max_hp = 144
	_check(c3.pick_ability_talent(&"passive", &"roots_regen"), "picks roots_regen")
	_check(c3.passive_upkeep_heal_amount() == 12, "roots_regen: Upkeep heal is ceil(144/12) = 12 (got %d)" % c3.passive_upkeep_heal_amount())

	var c4: Combatant = _mk_warden()
	c4.passive_ability_id = &"deep_roots"
	_check(c4.pick_ability_talent(&"passive", &"roots_thorned"), "picks roots_thorned")
	_check(is_equal_approx(c4.thorns_pct(), 0.10), "roots_thorned: 10%% passive Thorns at all times (got %.3f)" % c4.thorns_pct())

	# Mutual exclusion (passive row): only 1 pick per row.
	_check(not c4.pick_ability_talent(&"passive", &"roots_deeper"), "a second pick on an already-filled row is rejected (cap of 1/row)")

func _test_earthquake_row() -> void:
	# Deeper Quake's splash-fraction formula (mirrors Ranger's collateral_deeper math-only convention;
	# _splash_half_to_others() is a private Combat-scene method with no live scene here).
	_check(ceili(20 * 0.5) == 10, "sanity: baseline (1/2) splash of 20 is 10")
	_check(ceili(20 * (2.0 / 3.0)) == 14, "quake_deeper: 2/3 splash of 20 is 14, rounded up (got %d)" % ceili(20 * (2.0 / 3.0)))
	var c: Combatant = _mk_warden()
	_check(c.pick_ability_talent(&"ultimate", &"quake_deeper"), "picks quake_deeper")
	_check(c.has_ability_talent(&"quake_deeper"), "has_ability_talent sees quake_deeper")

	# Rooting Quake: manually simulates the exact splash+root loop combat.gd's _finish_spin() performs
	# (mirroring test_ability_talents_ranger.gd's collateral_marking convention, since
	# _splash_half_to_others()/its caller are private Combat-scene methods) — including the
	# apply_rider_talent_adjustments() routing so a Warden who ALSO picked entangle_lasting gets the
	# 3-turn Rooted duration on Earthquake's splash too (see this task's Implementation note).
	var c2: Combatant = _mk_warden()
	_check(c2.pick_ability_talent(&"ultimate", &"quake_rooting"), "picks quake_rooting")
	var primary: Combatant = _mk_warden()
	var other_a: Combatant = _mk_warden()
	var other_b: Combatant = _mk_warden()
	var quaked: Array[Combatant] = [other_a, other_b]
	_check(not primary.has_effect(&"rooted") and not other_a.has_effect(&"rooted"), "sanity: nobody starts Rooted")
	if c2.has_ability_talent(&"quake_rooting"):
		var rooted_primary: Effect = EffectLibrary.make(&"rooted")
		c2.apply_rider_talent_adjustments(&"rooted", rooted_primary, primary)
		primary.attach_effect(rooted_primary)
		for other: Combatant in quaked:
			var rooted_other: Effect = EffectLibrary.make(&"rooted")
			c2.apply_rider_talent_adjustments(&"rooted", rooted_other, other)
			other.attach_effect(rooted_other)
	_check(primary.has_effect(&"rooted"), "quake_rooting: the primary target is also Rooted")
	_check(other_a.has_effect(&"rooted") and other_b.has_effect(&"rooted"), "quake_rooting: every splashed enemy is also Rooted")

	# Lasting Quake: fire_earthquake's spin count, via MainPhasePlan (mirrors Wild/Collateral's own
	# lasting-spin test pattern exactly).
	var c3: Combatant = _mk_warden()
	c3.bonus_meter.value = c3.bonus_meter.cap
	var plan: MainPhasePlan = MainPhasePlan.new(c3)
	_check(plan.ultimate_id == &"earthquake", "sanity: Warden's Ultimate id is &earthquake")
	plan.toggle_ultimate()
	_check(plan.fire_ultimate_staged, "Earthquake ultimate stages when the meter is armed")
	plan.commit()
	_check(c3.earthquake_spins_remaining == 1, "without Lasting Quake, firing Earthquake grants 1 spin (got %d)" % c3.earthquake_spins_remaining)

	var c4: Combatant = _mk_warden()
	c4.bonus_meter.value = c4.bonus_meter.cap
	_check(c4.pick_ability_talent(&"ultimate", &"quake_lasting"), "picks quake_lasting")
	var plan2: MainPhasePlan = MainPhasePlan.new(c4)
	plan2.toggle_ultimate()
	plan2.commit()
	_check(c4.earthquake_spins_remaining == 2, "quake_lasting: firing Earthquake grants 2 spins (got %d)" % c4.earthquake_spins_remaining)

	# Mutual exclusion (ultimate row): only 1 pick per row.
	var c5: Combatant = _mk_warden()
	_check(c5.pick_ability_talent(&"ultimate", &"quake_deeper"), "first pick on the Earthquake row succeeds")
	_check(not c5.pick_ability_talent(&"ultimate", &"quake_rooting"), "a second pick on an already-filled row is rejected (cap of 1/row)")

func _init() -> void:
	_test_options_for_shape()
	_test_rallying_cry_row()
	_test_entangle_row()
	_test_regrowth_row()
	_test_bastion_row()
	_test_deep_roots_row()
	_test_earthquake_row()
	print(("WARDEN ABILITY TALENTS TEST PASSED" if _failures == 0 else "WARDEN ABILITY TALENTS TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_warden.gd`
Expected: FAIL on essentially every check — `AbilityTalentLibrary.options_for(&"warden", ...)` still returns `[]`.

- [ ] **Step 3: Implement**

**(a) `combat/ability_talent_library.gd`** — add a new `&"warden":` arm to the existing `match class_id:` block in `options_for()`, inserted immediately before the trailing `_: return []` fallback (Warden currently falls through to that shared fallback, exactly like every other not-yet-implemented class did before its own task added a real arm — do not disturb the `&"warrior":`/`&"vanguard":`/`&"skirmisher":`/`&"chancer":`/`&"ranger":` arms already there from Tasks 15-19):

```gdscript
		&"warden":
			match row_id:
				&"base_ability":
					var r1: AbilityTalentOption = AbilityTalentOption.new()
					r1.id = &"cry_deeper"; r1.row_id = row_id
					r1.display_name = "Deeper Cry"
					r1.description = "Rallying Cry's shield amount (both tiers) is 20% bigger."
					var r2: AbilityTalentOption = AbilityTalentOption.new()
					r2.id = &"cry_lasting"; r2.row_id = row_id
					r2.display_name = "Lasting Cry"
					r2.description = "Rallying Cry's shield lasts 1 turn longer."
					var r3: AbilityTalentOption = AbilityTalentOption.new()
					r3.id = &"cry_efficient"; r3.row_id = row_id
					r3.display_name = "Efficient Cry"
					r3.description = "Rallying Cry's Mana cost is reduced to 3 (was 4)."
					return [r1, r2, r3]
				&"ability_l2":
					var e1: AbilityTalentOption = AbilityTalentOption.new()
					e1.id = &"entangle_deeper"; e1.row_id = row_id
					e1.display_name = "Deeper Entangle"
					e1.description = "Entangle's own hit deals +15% bonus damage."
					var e2: AbilityTalentOption = AbilityTalentOption.new()
					e2.id = &"entangle_lasting"; e2.row_id = row_id
					e2.display_name = "Lasting Entangle"
					e2.description = "Rooted (from this ability) lasts 3 turns (was 2)."
					var e3: AbilityTalentOption = AbilityTalentOption.new()
					e3.id = &"entangle_efficient"; e3.row_id = row_id
					e3.display_name = "Efficient Entangle"
					e3.description = "Entangle's Mana cost is reduced to 3 (was 4)."
					return [e1, e2, e3]
				&"ability_l3":
					var g1: AbilityTalentOption = AbilityTalentOption.new()
					g1.id = &"regrowth_deeper"; g1.row_id = row_id
					g1.display_name = "Deeper Regrowth"
					g1.description = "Regrowth's heal-over-time is 25% bigger per tick."
					var g2: AbilityTalentOption = AbilityTalentOption.new()
					g2.id = &"regrowth_lasting"; g2.row_id = row_id
					g2.display_name = "Lasting Regrowth"
					g2.description = "Regrowth can stack up to 4 times (was 3)."
					var g3: AbilityTalentOption = AbilityTalentOption.new()
					g3.id = &"regrowth_efficient"; g3.row_id = row_id
					g3.display_name = "Efficient Regrowth"
					g3.description = "Regrowth's Mana cost is reduced to 3 (was 4)."
					return [g1, g2, g3]
				&"ability_l4":
					var b1: AbilityTalentOption = AbilityTalentOption.new()
					b1.id = &"bastion_deeper"; b1.row_id = row_id
					b1.display_name = "Deeper Bastion"
					b1.description = "Bastion's Thorns rises to 30% (was 20%)."
					var b2: AbilityTalentOption = AbilityTalentOption.new()
					b2.id = &"bastion_reinforced"; b2.row_id = row_id
					b2.display_name = "Reinforced Bastion"
					b2.description = "Bastion reduces incoming damage to 40% (was 50%)."
					var b3: AbilityTalentOption = AbilityTalentOption.new()
					b3.id = &"bastion_swift"; b3.row_id = row_id
					b3.display_name = "Swift Bastion"
					b3.description = "Bastion's cooldown is reduced to 3 turns (was 4)."
					return [b1, b2, b3]
				&"passive":
					var d1: AbilityTalentOption = AbilityTalentOption.new()
					d1.id = &"roots_deeper"; d1.row_id = row_id
					d1.display_name = "Ancient Roots"
					d1.description = "Deep Roots reduces incoming DoT damage by 25% (was 15%)."
					var d2: AbilityTalentOption = AbilityTalentOption.new()
					d2.id = &"roots_regen"; d2.row_id = row_id
					d2.display_name = "Flourishing Roots"
					d2.description = "Deep Roots' Upkeep heal rises to 1/12 of max HP (was 1/16)."
					var d3: AbilityTalentOption = AbilityTalentOption.new()
					d3.id = &"roots_thorned"; d3.row_id = row_id
					d3.display_name = "Thorned Roots"
					d3.description = "Deep Roots also grants a passive 10% Thorns at all times."
					return [d1, d2, d3]
				&"ultimate":
					var q1: AbilityTalentOption = AbilityTalentOption.new()
					q1.id = &"quake_deeper"; q1.row_id = row_id
					q1.display_name = "Deeper Quake"
					q1.description = "Earthquake's splash fraction rises to 2/3 of the primary total (was 1/2)."
					var q2: AbilityTalentOption = AbilityTalentOption.new()
					q2.id = &"quake_rooting"; q2.row_id = row_id
					q2.display_name = "Rooting Quake"
					q2.description = "Every enemy hit by Earthquake also gets Rooted applied."
					var q3: AbilityTalentOption = AbilityTalentOption.new()
					q3.id = &"quake_lasting"; q3.row_id = row_id
					q3.display_name = "Lasting Quake"
					q3.description = "Earthquake's crit bias lasts 2 spins instead of 1."
					return [q1, q2, q3]
				_:
					return []
```

**(b) `combat/combatant.gd` — `apply_bastion()`**, change from:

```gdscript
func apply_bastion(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"mana": cost}):
		return false
	var guard: Effect = EffectLibrary.make(&"guarded")
	guard.magnitude = 0.5
	guard.duration = 4
	guard.thorns_pct = 0.20
	attach_effect(guard)
	var taunt: Effect = EffectLibrary.make(&"taunt")
	taunt.duration = 4
	attach_effect(taunt)
	return true
```

to:

```gdscript
func apply_bastion(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"mana": cost}):
		return false
	var guard: Effect = EffectLibrary.make(&"guarded")
	guard.magnitude = 0.4 if has_ability_talent(&"bastion_reinforced") else 0.5
	guard.duration = 4
	guard.thorns_pct = 0.30 if has_ability_talent(&"bastion_deeper") else 0.20
	attach_effect(guard)
	var taunt: Effect = EffectLibrary.make(&"taunt")
	taunt.duration = 4
	attach_effect(taunt)
	return true
```

**(c) `combat/combatant.gd` — `passive_dot_damage_multiplier()`**, change the `&"deep_roots":` arm from:

```gdscript
func passive_dot_damage_multiplier() -> float:
	if level < 5 or passive_ability_id == &"":
		return 1.0
	match passive_ability_id:
		&"deep_roots":
			return 0.85
		_:
			return 1.0
```

to:

```gdscript
func passive_dot_damage_multiplier() -> float:
	if level < 5 or passive_ability_id == &"":
		return 1.0
	match passive_ability_id:
		&"deep_roots":
			return 0.75 if has_ability_talent(&"roots_deeper") else 0.85
		_:
			return 1.0
```

**(d) `combat/combatant.gd` — `passive_upkeep_heal_amount()`**, change the `&"deep_roots":` arm from:

```gdscript
func passive_upkeep_heal_amount() -> int:
	if level < 5 or passive_ability_id == &"":
		return 0
	match passive_ability_id:
		&"deep_roots":
			return ceili(float(max_hp) / 16.0)
		_:
			return 0
```

to:

```gdscript
func passive_upkeep_heal_amount() -> int:
	if level < 5 or passive_ability_id == &"":
		return 0
	match passive_ability_id:
		&"deep_roots":
			var divisor: float = 12.0 if has_ability_talent(&"roots_regen") else 16.0
			return ceili(float(max_hp) / divisor)
		_:
			return 0
```

**(e) `combat/combatant.gd` — `thorns_pct()`** (post-Task-16 state, the file already has the Vanguard
`bulwark_thorned` block right before the `return best` — untouched here), change from:

```gdscript
func thorns_pct() -> float:
	var best: float = 0.0
	for e: Effect in active_effects:
		if e != null and e.thorns_pct > best:
			best = e.thorns_pct
	# Vanguard "Thorned Bulwark" talent (Task 16): Bulwark itself is a live HP%-computed passive with
	# no attached Effect to carry a thorns_pct field (unlike Mountain Stance/Bastion's Guarded
	# instance), so this is checked here directly. Shares Bulwark's "passive" row with
	# bulwark_wider/bulwark_deeper (cap 1 pick/row), so this always uses the base 50% threshold
	# regardless of bulwark_wider's own threshold change.
	if class_id == &"vanguard" and passive_ability_id == &"bulwark" and has_ability_talent(&"bulwark_thorned"):
		if (float(hp) / float(maxi(max_hp, 1))) > 0.50 and 0.10 > best:
			best = 0.10
	return best
```

to:

```gdscript
func thorns_pct() -> float:
	var best: float = 0.0
	for e: Effect in active_effects:
		if e != null and e.thorns_pct > best:
			best = e.thorns_pct
	# Vanguard "Thorned Bulwark" talent (Task 16): Bulwark itself is a live HP%-computed passive with
	# no attached Effect to carry a thorns_pct field (unlike Mountain Stance/Bastion's Guarded
	# instance), so this is checked here directly. Shares Bulwark's "passive" row with
	# bulwark_wider/bulwark_deeper (cap 1 pick/row), so this always uses the base 50% threshold
	# regardless of bulwark_wider's own threshold change.
	if class_id == &"vanguard" and passive_ability_id == &"bulwark" and has_ability_talent(&"bulwark_thorned"):
		if (float(hp) / float(maxi(max_hp, 1))) > 0.50 and 0.10 > best:
			best = 0.10
	# Warden "Thorned Roots" talent (Task 21): Deep Roots grants a passive 10% Thorns at ALL times —
	# no HP-condition gate (unlike Bulwark's own conditional passive above), same shape otherwise:
	# Deep Roots has no attached Effect instance to carry a thorns_pct field.
	if class_id == &"warden" and passive_ability_id == &"deep_roots" and has_ability_talent(&"roots_thorned"):
		if 0.10 > best:
			best = 0.10
	return best
```

**(f) `combat/combatant.gd` — the 4 shared dispatch methods that need a Warden arm.** Change each
from its post-Task-19 state (add the `&"warden":` arm alongside Warrior/Vanguard/Skirmisher/Chancer/
Ranger's existing arms — do not disturb them):

```gdscript
func ability_talent_cost_delta(ability_id: StringName) -> int:
	match class_id:
		&"warrior":
			match ability_id:
				&"rend":
					return -1 if has_ability_talent(&"rend_efficient") else 0
				&"sundering_strike":
					return -1 if has_ability_talent(&"sunder_efficient") else 0
				_:
					return 0
		&"vanguard":
			match ability_id:
				&"heft":
					return -1 if has_ability_talent(&"heft_efficient") else 0
				&"bloodwrath":
					return -1 if has_ability_talent(&"wrath_efficient") else 0
				&"quake_slam":
					return -1 if has_ability_talent(&"slam_efficient") else 0
				_:
					return 0
		&"skirmisher":
			match ability_id:
				&"flurry":
					return -1 if has_ability_talent(&"flurry_efficient") else 0
				&"feint_riposte":
					return -1 if has_ability_talent(&"feint_efficient") else 0
				&"quickstep":
					return -1 if has_ability_talent(&"step_efficient") else 0
				_:
					return 0
		&"chancer":
			match ability_id:
				&"reroll":
					return -1 if has_ability_talent(&"reroll_efficient") else 0
				&"loaded_dice":
					return -1 if has_ability_talent(&"dice_efficient") else 0
				&"jinx_the_odds":
					return -1 if has_ability_talent(&"jinx_efficient") else 0
				_:
					return 0
		&"ranger":
			match ability_id:
				&"hunters_mark":
					return -1 if has_ability_talent(&"mark_efficient") else 0
				&"aimed_shot":
					return -1 if has_ability_talent(&"aim_efficient") else 0
				&"snare_trap":
					return -1 if has_ability_talent(&"snare_efficient") else 0
				_:
					return 0
		_:
			return 0
```

to:

```gdscript
func ability_talent_cost_delta(ability_id: StringName) -> int:
	match class_id:
		&"warrior":
			match ability_id:
				&"rend":
					return -1 if has_ability_talent(&"rend_efficient") else 0
				&"sundering_strike":
					return -1 if has_ability_talent(&"sunder_efficient") else 0
				_:
					return 0
		&"vanguard":
			match ability_id:
				&"heft":
					return -1 if has_ability_talent(&"heft_efficient") else 0
				&"bloodwrath":
					return -1 if has_ability_talent(&"wrath_efficient") else 0
				&"quake_slam":
					return -1 if has_ability_talent(&"slam_efficient") else 0
				_:
					return 0
		&"skirmisher":
			match ability_id:
				&"flurry":
					return -1 if has_ability_talent(&"flurry_efficient") else 0
				&"feint_riposte":
					return -1 if has_ability_talent(&"feint_efficient") else 0
				&"quickstep":
					return -1 if has_ability_talent(&"step_efficient") else 0
				_:
					return 0
		&"chancer":
			match ability_id:
				&"reroll":
					return -1 if has_ability_talent(&"reroll_efficient") else 0
				&"loaded_dice":
					return -1 if has_ability_talent(&"dice_efficient") else 0
				&"jinx_the_odds":
					return -1 if has_ability_talent(&"jinx_efficient") else 0
				_:
					return 0
		&"ranger":
			match ability_id:
				&"hunters_mark":
					return -1 if has_ability_talent(&"mark_efficient") else 0
				&"aimed_shot":
					return -1 if has_ability_talent(&"aim_efficient") else 0
				&"snare_trap":
					return -1 if has_ability_talent(&"snare_efficient") else 0
				_:
					return 0
		&"warden":
			match ability_id:
				&"rallying_cry":
					return -1 if has_ability_talent(&"cry_efficient") else 0
				&"entangle":
					return -1 if has_ability_talent(&"entangle_efficient") else 0
				&"regrowth":
					return -1 if has_ability_talent(&"regrowth_efficient") else 0
				_:
					return 0
		_:
			return 0
```

```gdscript
func ability_talent_cooldown_delta(ability_id: StringName) -> int:
	match class_id:
		&"warrior":
			match ability_id:
				&"second_wind":
					return -1 if has_ability_talent(&"wind_swift") else 0
				_:
					return 0
		&"vanguard":
			match ability_id:
				&"mountain_stance":
					return -1 if has_ability_talent(&"stance_swift") else 0
				_:
					return 0
		&"skirmisher":
			match ability_id:
				&"riposte_storm":
					return -1 if has_ability_talent(&"storm_swift") else 0
				_:
					return 0
		&"chancer":
			match ability_id:
				&"double_or_nothing":
					return -1 if has_ability_talent(&"gamble_swift") else 0
				_:
					return 0
		&"ranger":
			match ability_id:
				&"crippling_shot":
					return -1 if has_ability_talent(&"crippling_swift") else 0
				_:
					return 0
		_:
			return 0
```

to:

```gdscript
func ability_talent_cooldown_delta(ability_id: StringName) -> int:
	match class_id:
		&"warrior":
			match ability_id:
				&"second_wind":
					return -1 if has_ability_talent(&"wind_swift") else 0
				_:
					return 0
		&"vanguard":
			match ability_id:
				&"mountain_stance":
					return -1 if has_ability_talent(&"stance_swift") else 0
				_:
					return 0
		&"skirmisher":
			match ability_id:
				&"riposte_storm":
					return -1 if has_ability_talent(&"storm_swift") else 0
				_:
					return 0
		&"chancer":
			match ability_id:
				&"double_or_nothing":
					return -1 if has_ability_talent(&"gamble_swift") else 0
				_:
					return 0
		&"ranger":
			match ability_id:
				&"crippling_shot":
					return -1 if has_ability_talent(&"crippling_swift") else 0
				_:
					return 0
		&"warden":
			match ability_id:
				&"bastion":
					return -1 if has_ability_talent(&"bastion_swift") else 0
				_:
					return 0
		_:
			return 0
```

```gdscript
func apply_rider_talent_adjustments(rider_id: StringName, effect: Effect, target: Combatant) -> void:
	match class_id:
		&"warrior":
			match rider_id:
				&"bleed":
					if has_ability_talent(&"rend_deeper_cut"):
						for i: int in range(effect.dot_fractions.size()):
							effect.dot_fractions[i] *= 1.25
					if has_ability_talent(&"rend_lasting_wound"):
						effect.max_stacks = 4
						if effect.dot_fractions.size() < 4:
							effect.dot_fractions.append(1.55)
				&"sundered":
					if has_ability_talent(&"sunder_deeper"):
						effect.magnitude = 1.35
					if has_ability_talent(&"sunder_lingering"):
						effect.duration = 3
		&"chancer":
			match rider_id:
				&"jinxed":
					if has_ability_talent(&"jinx_lasting"):
						effect.duration = 3
		&"ranger":
			match rider_id:
				&"hunters_mark":
					# mark_weakening's OWN bonus Weakened (see combat.gd's hunters_mark_pending block)
					# is attached separately via a plain EffectLibrary.make() call that never routes
					# through this function — so it stays decoupled from crippling_lasting's duration
					# bump below, even though both ultimately use rider id &"weakened".
					if has_ability_talent(&"mark_deeper"):
						effect.duration = 4
					if has_ability_talent(&"mark_weakening"):
						target.attach_effect(EffectLibrary.make(&"weakened"))
				&"rooted":
					if has_ability_talent(&"snare_lasting"):
						effect.duration = 3
				&"weakened":
					if has_ability_talent(&"crippling_lasting"):
						effect.duration = 3
		_:
			pass
```

to:

```gdscript
func apply_rider_talent_adjustments(rider_id: StringName, effect: Effect, target: Combatant) -> void:
	match class_id:
		&"warrior":
			match rider_id:
				&"bleed":
					if has_ability_talent(&"rend_deeper_cut"):
						for i: int in range(effect.dot_fractions.size()):
							effect.dot_fractions[i] *= 1.25
					if has_ability_talent(&"rend_lasting_wound"):
						effect.max_stacks = 4
						if effect.dot_fractions.size() < 4:
							effect.dot_fractions.append(1.55)
				&"sundered":
					if has_ability_talent(&"sunder_deeper"):
						effect.magnitude = 1.35
					if has_ability_talent(&"sunder_lingering"):
						effect.duration = 3
		&"chancer":
			match rider_id:
				&"jinxed":
					if has_ability_talent(&"jinx_lasting"):
						effect.duration = 3
		&"ranger":
			match rider_id:
				&"hunters_mark":
					# mark_weakening's OWN bonus Weakened (see combat.gd's hunters_mark_pending block)
					# is attached separately via a plain EffectLibrary.make() call that never routes
					# through this function — so it stays decoupled from crippling_lasting's duration
					# bump below, even though both ultimately use rider id &"weakened".
					if has_ability_talent(&"mark_deeper"):
						effect.duration = 4
					if has_ability_talent(&"mark_weakening"):
						target.attach_effect(EffectLibrary.make(&"weakened"))
				&"rooted":
					if has_ability_talent(&"snare_lasting"):
						effect.duration = 3
				&"weakened":
					if has_ability_talent(&"crippling_lasting"):
						effect.duration = 3
		&"warden":
			match rider_id:
				&"rooted":
					# Also fires when Earthquake's own "Rooting Quake" talent applies Rooted (see
					# combat.gd's Earthquake block below) — a deliberate, consistent bonus, not an
					# oversight (mirrors Warrior's Bleeding Wild precedent, Task 15).
					if has_ability_talent(&"entangle_lasting"):
						effect.duration = 3
				&"regen":
					if has_ability_talent(&"regrowth_deeper"):
						for i: int in range(effect.dot_fractions.size()):
							effect.dot_fractions[i] *= 1.25
					if has_ability_talent(&"regrowth_lasting"):
						effect.max_stacks = 4
						if effect.dot_fractions.size() < 4:
							effect.dot_fractions.append(1.55)
		_:
			pass
```

```gdscript
func rider_talent_bonus_damage_pct(rider_id: StringName) -> float:
	match class_id:
		&"chancer":
			match rider_id:
				&"jinxed":
					return 0.15 if has_ability_talent(&"jinx_deeper") else 0.0
				_:
					return 0.0
		&"ranger":
			match rider_id:
				&"rooted":
					return 0.15 if has_ability_talent(&"snare_deeper") else 0.0
				_:
					return 0.0
		_:
			return 0.0
```

to:

```gdscript
func rider_talent_bonus_damage_pct(rider_id: StringName) -> float:
	match class_id:
		&"chancer":
			match rider_id:
				&"jinxed":
					return 0.15 if has_ability_talent(&"jinx_deeper") else 0.0
				_:
					return 0.0
		&"ranger":
			match rider_id:
				&"rooted":
					return 0.15 if has_ability_talent(&"snare_deeper") else 0.0
				_:
					return 0.0
		&"warden":
			match rider_id:
				&"rooted":
					return 0.15 if has_ability_talent(&"entangle_deeper") else 0.0
				_:
					return 0.0
		_:
			return 0.0
```

**(g) `combat/combat.gd` — the `regrowth_pending` block in `_commit_main1()`**, change from:

```gdscript
	# Regrowth (Task 30): mirrors Foresight — the orchestrator auto-picks the lowest-HP% living
	# ally (including the caster) and grants Regen instead of a shield.
	if _attacker.regrowth_pending:
		var ally: Combatant = _lowest_hp_pct_ally(_attacker)
		if ally != null:
			var regen: Effect = EffectLibrary.make(&"regen")
			# Seed the heal-over-time amount from the caster's weapon base, mirroring the DoT-rider
			# pattern above (rider.dot_base_damage) — without this, dot_base_damage stays at the
			# Effect default of 0.0 and every Regen tick heals ceili(0.0 * fraction) = 0 (dead ability).
			if _attacker.weapon != null:
				regen.dot_base_damage = _attacker.weapon_effective_base_damage()
			ally.attach_effect(regen)
			_log("  🌿 %s grants Regrowth to %s." % [_attacker.display_name, ally.display_name])
		_attacker.regrowth_pending = false
```

to:

```gdscript
	# Regrowth (Task 30): mirrors Foresight — the orchestrator auto-picks the lowest-HP% living
	# ally (including the caster) and grants Regen instead of a shield.
	if _attacker.regrowth_pending:
		var ally: Combatant = _lowest_hp_pct_ally(_attacker)
		if ally != null:
			var regen: Effect = EffectLibrary.make(&"regen")
			# Seed the heal-over-time amount from the caster's weapon base, mirroring the DoT-rider
			# pattern above (rider.dot_base_damage) — without this, dot_base_damage stays at the
			# Effect default of 0.0 and every Regen tick heals ceili(0.0 * fraction) = 0 (dead ability).
			if _attacker.weapon != null:
				regen.dot_base_damage = _attacker.weapon_effective_base_damage()
			# Warden Ability Talents (Task 21): Deeper Regrowth (+25% per tick) / Lasting Regrowth
			# (max stacks 3->4) — mirrors Ranger's Hunter's Mark precedent (Task 19) of calling
			# apply_rider_talent_adjustments() directly at a bespoke manual-attach site, not only the
			# one generic shared rider-attach site.
			_attacker.apply_rider_talent_adjustments(&"regen", regen, ally)
			ally.attach_effect(regen)
			_log("  🌿 %s grants Regrowth to %s." % [_attacker.display_name, ally.display_name])
		_attacker.regrowth_pending = false
```

**(h) `combat/combat.gd` — the Rallying Cry shield block in `_finish_spin()`**, change from:

```gdscript
	# Warden Rallying Cry (spec 2026-06-29 §3): read the utility reel's tier and shield every ally.
	# SUCCESS → half-weapon shield, CRIT_SUCCESS → full-weapon shield, RALLYING_CRY_SHIELD_TURNS
	# turns, higher-total-overrides.
	if _attacker.rallying_cry_reel != null and _rallying_cry_tier != -1:
		var base: float = _attacker.weapon_effective_base_damage()
		var amount: int = 0
		if _rallying_cry_tier == ReelFace.ResultTier.CRIT_SUCCESS:
			amount = ceili(base)
		elif _rallying_cry_tier == ReelFace.ResultTier.SUCCESS:
			amount = ceili(base * 0.5)
		if amount > 0:
			_log("  ⛨ RALLYING CRY → %d shield to all allies (%d turns)." % [amount, RALLYING_CRY_SHIELD_TURNS])
			for ally: Combatant in _allies_of(_attacker):
				ally.apply_shield(amount, RALLYING_CRY_SHIELD_TURNS)
				if _panels.has(ally):
					(_panels[ally] as CombatantPanel).refresh_status()
					(_panels[ally] as CombatantPanel).refresh_shield()
```

to:

```gdscript
	# Warden Rallying Cry (spec 2026-06-29 §3): read the utility reel's tier and shield every ally.
	# SUCCESS → half-weapon shield, CRIT_SUCCESS → full-weapon shield, RALLYING_CRY_SHIELD_TURNS
	# turns, higher-total-overrides.
	if _attacker.rallying_cry_reel != null and _rallying_cry_tier != -1:
		var base: float = _attacker.weapon_effective_base_damage()
		var amount: int = 0
		if _rallying_cry_tier == ReelFace.ResultTier.CRIT_SUCCESS:
			amount = ceili(base)
		elif _rallying_cry_tier == ReelFace.ResultTier.SUCCESS:
			amount = ceili(base * 0.5)
		# Warden "Deeper Cry" talent (Task 21): both shield tiers are 20% bigger.
		if amount > 0 and _attacker.has_ability_talent(&"cry_deeper"):
			amount = ceili(amount * 1.2)
		if amount > 0:
			# Warden "Lasting Cry" talent (Task 21): the shield lasts 1 turn longer.
			var shield_turns: int = (RALLYING_CRY_SHIELD_TURNS + 1) if _attacker.has_ability_talent(&"cry_lasting") else RALLYING_CRY_SHIELD_TURNS
			_log("  ⛨ RALLYING CRY → %d shield to all allies (%d turns)." % [amount, shield_turns])
			for ally: Combatant in _allies_of(_attacker):
				ally.apply_shield(amount, shield_turns)
				if _panels.has(ally):
					(_panels[ally] as CombatantPanel).refresh_status()
					(_panels[ally] as CombatantPanel).refresh_shield()
```

**(i) `combat/combat.gd` — the Earthquake block in `_finish_spin()`**, change from:

```gdscript
	# Earthquake (Warden Ultimate, spec 2026-06-29 §4): the primary took full per-reel damage; now splash
	# half (ceil) to every OTHER enemy as Earth, then STUN every enemy this spin damaged — without touching
	# their Initiative (force_stun_next_turn; they keep their queue position and roll the d100 gate on their
	# turn). "Successful attack" = the spin dealt that enemy > 0 damage.
	if _attacker.is_earthquake_active():
		var quaked: Array[Combatant] = _splash_half_to_others(_attacker, _earthquake_total, "Earth")
		if _earthquake_total > 0 and _defender.is_alive():
			_defender.force_stun_next_turn = true
			_log("  ☷ EARTHQUAKE → %s is STUNNED next turn (initiative unchanged)." % _defender.display_name)
		for other: Combatant in quaked:
			if other.is_alive():
				other.force_stun_next_turn = true
				_log("  ☷ EARTHQUAKE → %s is STUNNED next turn (initiative unchanged)." % other.display_name)
		_attacker.consume_earthquake_spin()
```

to:

```gdscript
	# Earthquake (Warden Ultimate, spec 2026-06-29 §4): the primary took full per-reel damage; now splash
	# half (ceil) to every OTHER enemy as Earth, then STUN every enemy this spin damaged — without touching
	# their Initiative (force_stun_next_turn; they keep their queue position and roll the d100 gate on their
	# turn). "Successful attack" = the spin dealt that enemy > 0 damage.
	if _attacker.is_earthquake_active():
		# Warden "Deeper Quake" talent (Task 21): the splash fraction of the primary total rises from
		# 1/2 to 2/3, reusing _splash_half_to_others()'s optional fraction param (added by Ranger's
		# Deeper Collateral, Task 19) directly — no second parameter invented.
		var earthquake_fraction: float = (2.0 / 3.0) if _attacker.has_ability_talent(&"quake_deeper") else 0.5
		var quaked: Array[Combatant] = _splash_half_to_others(_attacker, _earthquake_total, "Earth", earthquake_fraction)
		# Warden "Rooting Quake" talent (Task 21): every enemy Earthquake actually hit (primary +
		# splashed) also gets Rooted. Routed through apply_rider_talent_adjustments() so a Warden who
		# ALSO picked "Lasting Entangle" gets the 3-turn Rooted duration here too — a deliberate,
		# consistent bonus, mirroring Warrior's Bleeding Wild precedent (Task 15).
		if _earthquake_total > 0 and _defender.is_alive():
			_defender.force_stun_next_turn = true
			_log("  ☷ EARTHQUAKE → %s is STUNNED next turn (initiative unchanged)." % _defender.display_name)
			if _attacker.has_ability_talent(&"quake_rooting"):
				var rooted_primary: Effect = EffectLibrary.make(&"rooted")
				_attacker.apply_rider_talent_adjustments(&"rooted", rooted_primary, _defender)
				_defender.attach_effect(rooted_primary)
				_log("  🌱 Rooting Quake → %s is ROOTED." % _defender.display_name)
				if _panels.has(_defender):
					(_panels[_defender] as CombatantPanel).refresh_status()
		for other: Combatant in quaked:
			if other.is_alive():
				other.force_stun_next_turn = true
				_log("  ☷ EARTHQUAKE → %s is STUNNED next turn (initiative unchanged)." % other.display_name)
				if _attacker.has_ability_talent(&"quake_rooting"):
					var rooted_other: Effect = EffectLibrary.make(&"rooted")
					_attacker.apply_rider_talent_adjustments(&"rooted", rooted_other, other)
					other.attach_effect(rooted_other)
					_log("  🌱 Rooting Quake → %s is ROOTED." % other.display_name)
					if _panels.has(other):
						(_panels[other] as CombatantPanel).refresh_status()
		_attacker.consume_earthquake_spin()
```

**(j) `combat/main_phase_plan.gd` — `commit()`'s `&"earthquake":` arm**, change:

```gdscript
			&"earthquake":
				combatant.fire_earthquake(combatant.weapon_type(), EARTHQUAKE_SPINS)  # +1 WILD reel; orchestrator splashes + stuns
```

to:

```gdscript
			&"earthquake":
				# Warden "Lasting Quake" talent (Task 21): the crit bias lasts 2 spins instead of 1.
				var spins: int = (EARTHQUAKE_SPINS + 1) if combatant.has_ability_talent(&"quake_lasting") else EARTHQUAKE_SPINS
				combatant.fire_earthquake(combatant.weapon_type(), spins)  # +1 WILD reel; orchestrator splashes + stuns, +1 spin with Lasting Quake
```

*(Confirm the exact existing constant name — `EARTHQUAKE_SPINS` — against the real file before
editing; if named differently, use the real name, the behavior is what matters.)*

- [ ] **Step 4: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_warden.gd`
Expected: all lines print `ok:`.

- [ ] **Step 5: Run the full test suite**

Run every `tests/test_*.gd` file headlessly and confirm exit code 0 for each. 3 known pre-existing
failures predate this whole effort and are NOT regressions: `test_adventuring_board_panel.gd` (1
internal FAIL line), `test_overworld_demo_npcs.gd` (5), `test_overworld_encounter_variety.gd` (6). Any
OTHER nonzero exit is a real regression and must be root-caused before committing — pay particular
attention to: `tests/test_earthquake.gd` (confirm the default no-talent splash fraction/stun behavior
is unchanged, and Deeper Quake's fraction pick / Rooting Quake's talent-gated addition don't fire for a
Warden with nothing picked), `tests/test_rallying_cry.gd`/`tests/test_rallying_cry_reel.gd` (confirm
the default no-talent shield amount/duration is unchanged), `tests/test_regrowth.gd` (confirm the
default no-talent Regen heal-over-time is unchanged), `tests/test_bastion.gd` (confirm the default
no-talent Guarded magnitude/Thorns are unchanged), `tests/test_entangle.gd` (confirm Entangle's own
reel-append/cost-gate behavior is unchanged), `tests/test_passive_deep_roots.gd` (confirm the default
no-talent DoT-reduction/Upkeep-heal values are unchanged), `tests/test_warden_class.gd`/
`tests/test_warden_effects.gd`/`tests/test_warden_acolyte_abilities.gd`/
`tests/test_hollow_warden_full_sequence.gd` (broader Warden-adjacent coverage — confirm none of it
regresses), and every prior class's own `tests/test_ability_talents_*.gd` (confirm the shared
dispatch-method edits above didn't disturb their existing arms).

- [ ] **Step 6: Commit**

```bash
git add combat/ability_talent_library.gd combat/combatant.gd combat/combat.gd combat/main_phase_plan.gd tests/test_ability_talents_warden.gd
git commit -m "feat(talents): Warden Ability Talents — 18 options across Rallying Cry/Entangle/Regrowth/Bastion/Deep Roots/Earthquake"
```

---

## Task 22: `TalentMenuPanel` UI (both tracks)

**Files:**
- Create: `combat/ui/talent_menu_panel.gd`
- Test: `tests/test_talent_menu_panel.gd` (new)

**Interfaces:**
- Consumes: `Combatant.class_id`/`ability_talent_picks`/`has_ability_talent()`/
  `pick_ability_talent()`/`unpick_ability_talent()`/`ability_talent_row_unlock_level()`/
  `ability_talent_row_unlocked()` (Task 14), `AbilityTalentLibrary.options_for()` (Tasks 14-21, now
  fully populated for all 7 classes), `Combatant.talent_perks`/`universal_points_earned()`/
  `universal_points_available()`/`pick_talent_perk()`/`unpick_talent_perk()` (Task 13),
  `TalentPerkLibrary.universal_perks()` (Task 13).
- Produces: `TalentMenuPanel` (`combat/ui/talent_menu_panel.gd`), `open_for(c: Combatant,
  respec_available: bool = true) -> void`, `close() -> void`. Consumed by Task 23's world-scene
  wiring.

Built the same way `AbilityMenuPanel`/`InventoryMenuPanel`/`TypeChartPanel` already are (per the
locked spec §2 UI decision): manually positioned child `Control`s, no `.tscn`, no drag-and-drop,
click-to-pick/click-to-swap only, `_for_test()`-style hooks so headless tests can press buttons
programmatically without a running scene tree event loop.

- [ ] **Step 1: Write the failing test**

Create `tests/test_talent_menu_panel.gd`:

```gdscript
extends SceneTree

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _mk_warrior_at(level: int) -> Combatant:
	var c: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	c.level = level
	return c

func _init() -> void:
	var panel: TalentMenuPanel = TalentMenuPanel.new()

	# All 6 Ability Talent rows render for the viewed character's class, even locked ones.
	var c: Combatant = _mk_warrior_at(5)  # only base_ability row unlocked
	panel.open_for(c, true)
	_check(panel.row_button_count(&"base_ability") == 3, "base_ability row (unlocked at L5) shows 3 option buttons")
	_check(panel.row_button_count(&"ultimate") == 3, "ultimate row (locked until L10) STILL shows 3 option buttons — locked rows are shown, not hidden")
	_check(not panel.is_row_interactive(&"ultimate"), "a locked row's buttons are disabled")
	_check(panel.is_row_interactive(&"base_ability"), "an unlocked row's buttons are enabled")
	_check(panel.locked_row_label(&"ultimate") == "Unlocks at Level 10", "a locked row shows its unlock level (got '%s')" % panel.locked_row_label(&"ultimate"))
	panel.close()

	# Picking via the panel calls through to the real Combatant methods (no separate pick state).
	var c2: Combatant = _mk_warrior_at(10)
	panel.open_for(c2, true)
	_check(panel.press_option_for_test(&"base_ability", &"rend_efficient"), "pressing an option button picks it")
	_check(c2.has_ability_talent(&"rend_efficient"), "the real Combatant now has the talent picked")
	_check(panel.is_option_selected(&"base_ability", &"rend_efficient"), "the panel shows the picked option as selected")
	panel.close()

	# Respec gating: town (respec_available=true) allows swapping an already-spent row; overworld/
	# dungeon (false) shows the pick but disables the swap action — mirrors InventoryMenuPanel's
	# existing vault_available convention exactly.
	var c3: Combatant = _mk_warrior_at(10)
	c3.pick_ability_talent(&"base_ability", &"rend_efficient")
	panel.open_for(c3, false)
	_check(panel.is_option_selected(&"base_ability", &"rend_efficient"), "an already-spent pick is still shown outside a safe zone")
	_check(not panel.is_row_interactive(&"base_ability"), "an already-spent row's buttons are disabled outside a safe zone (view-only)")
	panel.close()

	panel.open_for(c3, true)
	_check(panel.is_row_interactive(&"base_ability"), "the same already-spent row IS interactive in town (respec_available=true)")
	_check(panel.press_option_for_test(&"base_ability", &"rend_deeper_cut"), "town respec: picking a different option in an already-spent row succeeds (unpick + repick)")
	_check(c3.has_ability_talent(&"rend_deeper_cut"), "the swap actually changed the Combatant's pick")
	_check(not c3.has_ability_talent(&"rend_efficient"), "the old pick is cleared")
	panel.close()

	# Universal Perk section: 5 milestone slots, shown-when-reached (unlike the Ability Talent grid's
	# always-shown rows), one-time-pick enforcement carried straight through to TalentPerkLibrary.
	var c4: Combatant = _mk_warrior_at(4)
	panel.open_for(c4, true)
	_check(panel.universal_slot_count() == 1, "L4: only the L2 milestone has been reached (1 slot shown, got %d)" % panel.universal_slot_count())
	panel.close()

	var c5: Combatant = _mk_warrior_at(10)
	panel.open_for(c5, true)
	_check(panel.universal_slot_count() == 5, "L10: all 5 milestones reached (got %d)" % panel.universal_slot_count())
	_check(panel.press_universal_perk_for_test(&"vigor_boost"), "picking a universal perk succeeds")
	_check(c5.has_ability_talent(&"") == false, "sanity: has_ability_talent is unrelated to talent_perks")
	_check(&"vigor_boost" in c5.talent_perks, "the real Combatant now carries the picked universal perk")
	panel.close()

	print(("TALENT MENU PANEL TEST PASSED" if _failures == 0 else "TALENT MENU PANEL TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_talent_menu_panel.gd`
Expected: FAIL / parse error — `TalentMenuPanel` doesn't exist yet.

- [ ] **Step 3: Implement**

Create `combat/ui/talent_menu_panel.gd`:

```gdscript
class_name TalentMenuPanel
extends Panel

## Non-modal floating panel presenting BOTH talent tracks for one viewed Combatant (spec
## 2026-07-24-ability-talent-track-redesign-design.md): the 6-row-by-3-option Ability Talent grid
## for that character's own class (Track A), and the 5-milestone Universal Perk list (Track B).
## Built the same way AbilityMenuPanel/InventoryMenuPanel/TypeChartPanel are: manual Control
## layout, no .tscn, no drag-and-drop, click-to-pick/click-to-swap only, with _for_test() hooks so
## headless tests can drive it without a live scene tree event loop.

const ROW_IDS: Array[StringName] = [&"base_ability", &"ability_l2", &"ability_l3", &"ability_l4", &"passive", &"ultimate"]
const ROW_LABELS: Dictionary = {
	&"base_ability": "Base Ability", &"ability_l2": "Level 2 Ability", &"ability_l3": "Level 3 Ability",
	&"ability_l4": "Level 4 Ability", &"passive": "Passive", &"ultimate": "Ultimate",
}

const PANEL_W: float = 620.0
const PANEL_H: float = 560.0
const PAD: float = 12.0
const ROW_H: float = 56.0
const OPTION_BTN_W: float = 190.0
const OPTION_BTN_H: float = 22.0
const UNIVERSAL_ROW_H: float = 24.0

var _combatant: Combatant
var _respec_available: bool = true
var _row_option_buttons: Dictionary = {}   # row_id -> Array[Button] (index-aligned with that row's options)
var _row_locked_labels: Dictionary = {}    # row_id -> Label
var _universal_buttons: Array[Button] = [] # index-aligned with the earned-milestone slots shown
var _universal_perk_ids_shown: Array[StringName] = []
var _close_button: Button

func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	size = Vector2(PANEL_W, PANEL_H)

func _clear() -> void:
	for child: Node in get_children():
		child.queue_free()
	_row_option_buttons.clear()
	_row_locked_labels.clear()
	_universal_buttons.clear()
	_universal_perk_ids_shown.clear()

## Opens the panel for [param c] — shows [param c]'s own class's 6-row Ability Talent grid plus the
## shared Universal Perk milestone list. [param respec_available] mirrors InventoryMenuPanel's
## vault_available convention exactly: false shows every already-spent pick (still presented, per
## this project's "still an option, just restricted" rule) but disables the swap/pick action on any
## row/slot that already has a pick, or any not-yet-reached-but-unlocked row a player could newly
## spend a point on outside a safe zone.
func open_for(c: Combatant, respec_available: bool = true) -> void:
	_clear()
	_combatant = c
	_respec_available = respec_available
	show()

	var title: Label = Label.new()
	title.text = "Talents"
	title.position = Vector2(PAD, PAD)
	add_child(title)

	_close_button = Button.new()
	_close_button.text = "✕"
	_close_button.position = Vector2(PANEL_W - PAD - 24.0, PAD)
	_close_button.size = Vector2(24.0, 24.0)
	_close_button.pressed.connect(close)
	add_child(_close_button)

	var y: float = PAD + 36.0
	for row_id: StringName in ROW_IDS:
		_build_row(row_id, y)
		y += ROW_H

	y += 8.0
	var universal_title: Label = Label.new()
	universal_title.text = "Universal Perks"
	universal_title.position = Vector2(PAD, y)
	add_child(universal_title)
	y += 22.0
	_build_universal_section(y)

func close() -> void:
	hide()

func _build_row(row_id: StringName, y: float) -> void:
	var unlocked: bool = _combatant.ability_talent_row_unlocked(row_id)
	var label: Label = Label.new()
	label.text = String(ROW_LABELS.get(row_id, row_id))
	label.position = Vector2(PAD, y)
	add_child(label)

	if not unlocked:
		var locked: Label = Label.new()
		locked.text = "Unlocks at Level %d" % _combatant.ability_talent_row_unlock_level(row_id)
		locked.position = Vector2(PAD, y + 16.0)
		locked.modulate = Color(0.6, 0.6, 0.6)
		add_child(locked)
		_row_locked_labels[row_id] = locked

	var opts: Array[AbilityTalentOption] = AbilityTalentLibrary.options_for(_combatant.class_id, row_id)
	var buttons: Array[Button] = []
	var current_pick: StringName = _combatant.ability_talent_picks.get(row_id, &"")
	var row_has_pick: bool = current_pick != &""
	# Interactive only if: the row is unlocked, AND (it has no pick yet, OR a pick exists but we're
	# in a respec-available safe zone).
	var interactive: bool = unlocked and (not row_has_pick or _respec_available)
	for i: int in range(opts.size()):
		var opt: AbilityTalentOption = opts[i]
		var btn: Button = Button.new()
		btn.text = opt.display_name
		btn.tooltip_text = opt.description
		btn.position = Vector2(PAD + float(i) * (OPTION_BTN_W + 8.0), y + 30.0)
		btn.size = Vector2(OPTION_BTN_W, OPTION_BTN_H)
		btn.toggle_mode = true
		btn.button_pressed = (current_pick == opt.id)
		btn.disabled = not interactive
		btn.pressed.connect(_on_option_pressed.bind(row_id, opt.id))
		add_child(btn)
		buttons.append(btn)
	_row_option_buttons[row_id] = buttons

func _on_option_pressed(row_id: StringName, option_id: StringName) -> void:
	var current_pick: StringName = _combatant.ability_talent_picks.get(row_id, &"")
	if current_pick == option_id:
		return  # already this option — no-op (re-pressing a toggled button shouldn't unpick it)
	if current_pick != &"":
		if not _respec_available:
			return
		_combatant.unpick_ability_talent(row_id)
	_combatant.pick_ability_talent(row_id, option_id)
	open_for(_combatant, _respec_available)  # rebuild to reflect the new selection state

func _build_universal_section(y: float) -> void:
	var earned: int = _combatant.universal_points_earned()
	var perks: Array[TalentPerkDef] = TalentPerkLibrary.universal_perks()
	var picked: Array[StringName] = _combatant.talent_perks
	var available: int = _combatant.universal_points_available()
	# One slot per earned milestone (spec 2026-07-24 §2's shown-when-reached rule — this section, unlike
	# the Ability Talent grid above, does NOT preview not-yet-reached milestones).
	for slot: int in range(earned):
		var row_y: float = y + float(slot) * (UNIVERSAL_ROW_H + 4.0)
		var already_picked: bool = slot < picked.size()
		var perk_id: StringName = picked[slot] if already_picked else &""
		var btn: Button = Button.new()
		if already_picked:
			var def: TalentPerkDef = TalentPerkLibrary.find_perk(perk_id)
			btn.text = def.display_name if def != null else String(perk_id)
			btn.tooltip_text = def.description if def != null else ""
		else:
			btn.text = "— pick a perk —"
		btn.position = Vector2(PAD, row_y)
		btn.size = Vector2(240.0, UNIVERSAL_ROW_H)
		btn.disabled = already_picked and not _respec_available
		if not already_picked and available <= 0:
			btn.disabled = true
		btn.pressed.connect(_on_universal_slot_pressed.bind(slot, perk_id))
		add_child(btn)
		_universal_buttons.append(btn)
		_universal_perk_ids_shown.append(perk_id)

func _on_universal_slot_pressed(_slot: int, existing_perk_id: StringName) -> void:
	# A minimal picker: opening this panel again with a perk explicitly requested via
	# press_universal_perk_for_test() is how tests drive a real pick; a live player-facing perk
	# SELECTION sub-menu (choosing WHICH of the 10 to spend a slot on) is the same kind of small
	# secondary popup InventoryMenuPanel's own Bag-tab item-detail view already uses — deferred to
	# whoever polishes this panel's live-game presentation, not required for the data flow to work.
	if existing_perk_id != &"" and _respec_available:
		_combatant.unpick_talent_perk(existing_perk_id)
		open_for(_combatant, _respec_available)

## --- Test hooks (mirror AbilityMenuPanel's _for_test() convention) ---

func row_button_count(row_id: StringName) -> int:
	return (_row_option_buttons.get(row_id, []) as Array).size()

func is_row_interactive(row_id: StringName) -> bool:
	var buttons: Array = _row_option_buttons.get(row_id, [])
	if buttons.is_empty():
		return false
	return not (buttons[0] as Button).disabled

func locked_row_label(row_id: StringName) -> String:
	var lbl: Label = _row_locked_labels.get(row_id, null)
	return lbl.text if lbl != null else ""

func is_option_selected(row_id: StringName, option_id: StringName) -> bool:
	return _combatant.ability_talent_picks.get(row_id, &"") == option_id

## Presses the button for [param option_id] in [param row_id] (headless test hook — no real click
## event needed). Returns false if the row/option doesn't exist or the button is disabled.
func press_option_for_test(row_id: StringName, option_id: StringName) -> bool:
	var opts: Array[AbilityTalentOption] = AbilityTalentLibrary.options_for(_combatant.class_id, row_id)
	var idx: int = -1
	for i: int in range(opts.size()):
		if opts[i].id == option_id:
			idx = i
			break
	if idx < 0:
		return false
	var buttons: Array = _row_option_buttons.get(row_id, [])
	if idx >= buttons.size() or (buttons[idx] as Button).disabled:
		return false
	_on_option_pressed(row_id, option_id)
	return true

func universal_slot_count() -> int:
	return _universal_buttons.size()

## Picks [param perk_id] into the first still-empty, non-disabled Universal Perk slot (headless test
## hook). Returns false if there's no such slot.
func press_universal_perk_for_test(perk_id: StringName) -> bool:
	if TalentPerkLibrary.find_perk(perk_id) == null:
		return false
	if not _combatant.pick_talent_perk(perk_id):
		return false
	open_for(_combatant, _respec_available)
	return true
```

- [ ] **Step 4: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_talent_menu_panel.gd`
Expected: all lines print `ok:`.

- [ ] **Step 5: Run the full test suite**

Run every `tests/test_*.gd` file headlessly and confirm exit code 0 for each. This task creates a
new, self-contained UI file with no shared-function edits — the 3 known pre-existing failures (see
Global Constraints) are the only expected non-passing files.

- [ ] **Step 6: Commit**

```bash
git add combat/ui/talent_menu_panel.gd tests/test_talent_menu_panel.gd
git commit -m "feat(talents): TalentMenuPanel UI — Ability Talent grid + Universal Perk list"
```

---

## Task 23: Input action + world-scene wiring

**Files:**
- Modify: `project.godot` (new `toggle_talents` input action)
- Modify: `world/town_demo.gd` (opens `TalentMenuPanel` with `respec_available = true`)
- Modify: `world/overworld_demo.gd` (opens it with `respec_available = false`)
- Modify: `world/dungeon_demo.gd` (opens it with `respec_available = false`)
- Test: `tests/test_town_demo_talents.gd`, `tests/test_overworld_demo_talents.gd`,
  `tests/test_dungeon_demo_talents.gd` (new — one per scene, mirroring the existing
  `tests/test_town_demo_inventory.gd`/`tests/test_overworld_demo_inventory.gd`-style real-scene
  wiring tests)

**Interfaces:**
- Consumes: Task 22's `TalentMenuPanel.open_for(c, respec_available)`/`close()`.
- Produces: a live `N` keybinding toggling `TalentMenuPanel` in all 3 world scenes, following the
  exact `toggle_inventory`/`toggle_stats`/`toggle_event_log` precedent already in each of these
  files (pause PC movement while open, block `interact` while open, guard against stacking with
  dialogue/board/other panels in both directions).

- [ ] **Step 1: Add the input action**

In `project.godot`'s `[input]` section, add (physical keycode 78 = `N`, confirmed free against
every existing bound action per the locked spec):

```
toggle_talents={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":78,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
```

*(Match the exact key-value formatting of the existing `toggle_stats`/`toggle_event_log` entries
already in this file — copy one of those blocks and change only `physical_keycode` if the literal
syntax above doesn't match this Godot version's serialization exactly.)*

- [ ] **Step 2: Write the failing tests**

Create `tests/test_town_demo_talents.gd` (mirrors `tests/test_town_demo_inventory.gd`'s exact
structure):

```gdscript
extends SceneTree

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _init() -> void:
	var scene: PackedScene = load("res://world/town_demo.tscn")
	var instance: Node = scene.instantiate()
	get_root().add_child(instance)
	await process_frame
	await process_frame

	var town: Node = instance  # town_demo.gd's class_name, whatever it is — confirm against the real file
	_check(town.has_method("_toggle_talents"), "town_demo has a _toggle_talents method")
	var pc: PCController = town.get("_pc")
	_check(not pc.is_movement_paused(), "sanity: PC movement isn't paused before opening Talents")
	town._toggle_talents()
	_check(pc.is_movement_paused(), "opening Talents pauses PC movement")
	var panel: TalentMenuPanel = town.get("_talent_panel")
	_check(panel.visible, "the Talents panel is now visible")
	town._toggle_talents()
	_check(not pc.is_movement_paused(), "closing Talents resumes PC movement")
	_check(not panel.visible, "the Talents panel is now hidden")

	instance.queue_free()
	print(("TOWN TALENTS TEST PASSED" if _failures == 0 else "TOWN TALENTS TEST FAILED: %d" % _failures))
	quit(_failures)
```

Create `tests/test_overworld_demo_talents.gd`/`tests/test_dungeon_demo_talents.gd` identically,
substituting `res://world/overworld_demo.tscn`/`res://world/dungeon_demo.tscn` and each scene's own
local var name for the driving node — read each real file's existing `_toggle_inventory`/
`_toggle_stats` methods first to confirm the exact node/method naming convention before writing
these 1:1 (this plan cannot know their exact private field names without reading the current file,
which may have shifted since this plan was written).

- [ ] **Step 3: Run tests to verify they fail**

Run each of the 3 new test files. Expected: FAIL / parse error — `_toggle_talents`/`_talent_panel`
don't exist yet on any of the 3 scenes.

- [ ] **Step 4: Implement**

In each of `world/town_demo.gd`/`world/overworld_demo.gd`/`world/dungeon_demo.gd`:

1. Add a `var _talent_panel: TalentMenuPanel` field, alongside the existing `_inventory_panel`.
2. In the scene's build step (wherever `_inventory_panel = InventoryMenuPanel.new()` /
   `_ui_layer.add_child(_inventory_panel)` already happens), add the mirrored construction:

```gdscript
	_talent_panel = TalentMenuPanel.new()
	_talent_panel.position = Vector2(140, 60)
	_talent_panel.hide()
	_ui_layer.add_child(_talent_panel)
```

3. Add a `_toggle_talents()` method, mirroring `_toggle_stats()`'s exact shape (town passes
   `respec_available = true`; overworld/dungeon pass `false`):

```gdscript
## Talents (Task 23, spec 2026-07-24 §2/§6) — bound to 'N'. Same toggle semantics as
## _toggle_inventory()/_toggle_stats(): pause PC movement while open, resume on close.
func _toggle_talents() -> void:
	if _talent_panel.visible:
		_talent_panel.close()
		_pc.set_movement_paused(false)
	else:
		_talent_panel.open_for(_pc_combatant, true)   # town = safe zone, respec available
		_pc.set_movement_paused(true)
```

(`overworld_demo.gd`/`dungeon_demo.gd`'s versions pass `false` instead of `true` — mirrors exactly
how those two files already pass `false` for `vault_available` to `InventoryMenuPanel.open_for()`.)

4. In each scene's `_unhandled_input(event)` (or equivalent), add:

```gdscript
	if event.is_action_pressed("toggle_talents"):
		_toggle_talents()
```

5. **Guard against stacking with other modal panels, both directions** — mirror however this
   codebase's existing `_toggle_inventory()`/`_toggle_stats()`/dialogue/board guards already
   prevent two panels being open simultaneously (read the current file's own guard pattern first;
   it has evolved across several playtest-fix passes documented in this project's history — do not
   reinvent it, extend whatever the real current guard shape is to also check `_talent_panel`).

- [ ] **Step 5: Run tests to verify they pass**

Run all 3 new test files. Expected: all lines print `ok:`.

- [ ] **Step 6: Run the full test suite**

Run every `tests/test_*.gd` file headlessly and confirm exit code 0 for each. The 3 known
pre-existing failures (see Global Constraints) are the only expected non-passing files. Pay
particular attention to any existing test asserting an exhaustive list of input actions or an exact
count of `_ui_layer` children.

- [ ] **Step 7: Commit**

```bash
git add project.godot world/town_demo.gd world/overworld_demo.gd world/dungeon_demo.gd tests/test_town_demo_talents.gd tests/test_overworld_demo_talents.gd tests/test_dungeon_demo_talents.gd
git commit -m "feat(talents): wire toggle_talents (N) into town/overworld/dungeon"
```

---

## Task 24: Final whole-suite verification

**Files:** none (verification only).

**Interfaces:** none.

- [ ] **Step 1: Run the entire headless test suite**

```bash
for f in tests/test_*.gd; do
  ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script "res://$f"
done
```

Confirm every file exits 0 except the 3 known pre-existing failures (`test_adventuring_board_panel.gd`,
`test_overworld_demo_npcs.gd`, `test_overworld_encounter_variety.gd`) — confirmed unrelated to this
whole plan via an isolated-worktree check before Task 7 of the prior (passives) plan.

- [ ] **Step 2: Spot-check cross-task consistency**

Read the final state of `combat/combatant.gd`'s 4 shared dispatch methods
(`ability_talent_cost_delta`/`ability_talent_cooldown_delta`/`apply_rider_talent_adjustments`/
`rider_talent_bonus_damage_pct`) and confirm all 7 classes' arms (Tasks 15-21) are present, none were
accidentally overwritten by a later task, and the trailing `_: return 0`/`0.0`/`pass` fallback is
still intact.

- [ ] **Step 3: Confirm the two content checkpoints' approved tables match the shipped code**

Spot-check a handful of entries from Task 12's 126-option table (say, 2 per class) against the
actual `AbilityTalentLibrary.options_for()` implementation, and Task 4's/original-Task-12's 10
Universal Perks against `TalentPerkLibrary.universal_perks()` — confirm no drift between what was
approved and what shipped.

- [ ] **Step 4: Report**

Summarize to the player: total tasks shipped (Tasks 1-24 across both plans), test count, the 3 known
pre-existing failures (still open, unrelated), and that a human has not yet playtested the two new
talent tracks live — recommend that as the next step (open Talents in `town_demo.tscn`, pick a row
option and a universal perk, confirm both apply in a real fight, confirm the town-only respec gate).

---
