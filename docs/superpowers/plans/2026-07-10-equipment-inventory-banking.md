# Equipment / Inventory / Banking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the data layer and combat-math hooks specified in
`docs/superpowers/specs/2026-07-10-equipment-inventory-banking-design.md`: a 6-slot equipment
loadout with a shared 5-tier WoW-style rarity ladder, a reworked Might/Vigor/Focus/Luck stat
translation, a per-PC shared inventory, an account-wide bank, and the loot-roll mechanism.

**Architecture:** Extend existing `combat/resources/` (`Gear`, `Weapon`) and `combat/combatant.gd`
in place, following the established pattern of pre-stat "seed" fields (`base_max_hp` etc.) derived
by `apply_stats()`. Add a new static `RarityVisuals` helper mirroring the existing
`TypeVisuals`/`RoleVisuals` convention. Add a new `economy/resources/` folder (parallel to
`combat/`/`world/`) for `PartyInventory`, `Vault`, and `LootTable` — these aren't turn-resolution
concerns so they don't belong in `combat/`.

**Tech Stack:** Godot 4.6.3-stable, GDScript, headless `SceneTree`-script tests under `tests/`
(existing `extends SceneTree` + `_check()` pattern — no test framework dependency).

## Global Constraints

- Engine: Godot 4.6+ (built/tested on 4.6.3-stable). Language: GDScript only, no C# (CLAUDE.md §2).
- Prefer static typing (typed vars, typed signatures).
- All new numeric magnitudes are `[ASSUMPTION]` — tunable, never treated as final balance (CLAUDE.md §4).
- All combat damage/heal math rounds UP (`ceili`), project-wide convention — apply to every new
  formula that produces damage/heal amounts.
- No new UI screens this pass (see spec §8) — data + pure logic only, verified by headless tests.
- Every task must leave all existing headless suites green (currently 107 suites) in addition to
  its own new test.
- Test runner: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_<name>.gd`
  (run from the `bunnies/` project root, i.e. `C:\bunnies\bunnies-main\bunnies`).

---

## Task 1: `RarityVisuals` static helper

**Files:**
- Create: `combat/rarity_visuals.gd`
- Test: `tests/test_rarity_visuals.gd`

**Interfaces:**
- Produces: `RarityVisuals.Rarity` enum (`COMMON, UNCOMMON, RARE, EPIC, LEGENDARY`),
  `RarityVisuals.min_level_for(rarity) -> int`, `RarityVisuals.display_name(rarity) -> String`,
  `RarityVisuals.color(rarity) -> Color`, `RarityVisuals.max_stat_affixes(rarity) -> int`,
  `RarityVisuals.max_reel_affixes(rarity) -> int`, `RarityVisuals.rarity_for_level(level) -> Rarity`.
  Every later task that touches rarity/level-gating depends on these.

- [ ] **Step 1: Write the failing test**

```gdscript
extends SceneTree

# Headless test: RarityVisuals lookup tables (min level / affix counts / inverse level lookup).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_rarity_visuals.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var R := RarityVisuals.Rarity
	_check(RarityVisuals.min_level_for(R.COMMON) == 1, "Common min level 1")
	_check(RarityVisuals.min_level_for(R.UNCOMMON) == 3, "Uncommon min level 3")
	_check(RarityVisuals.min_level_for(R.RARE) == 5, "Rare min level 5")
	_check(RarityVisuals.min_level_for(R.EPIC) == 7, "Epic min level 7")
	_check(RarityVisuals.min_level_for(R.LEGENDARY) == 9, "Legendary min level 9")

	_check(RarityVisuals.display_name(R.RARE) == "Rare", "display_name Rare")

	_check(RarityVisuals.max_stat_affixes(R.COMMON) == 1, "Common 1 stat affix")
	_check(RarityVisuals.max_stat_affixes(R.UNCOMMON) == 2, "Uncommon 2 stat affixes")
	_check(RarityVisuals.max_stat_affixes(R.RARE) == 1, "Rare 1 stat affix")
	_check(RarityVisuals.max_stat_affixes(R.EPIC) == 2, "Epic 2 stat affixes")
	_check(RarityVisuals.max_stat_affixes(R.LEGENDARY) == 2, "Legendary 2 stat affixes")

	_check(RarityVisuals.max_reel_affixes(R.COMMON) == 0, "Common 0 reel affixes")
	_check(RarityVisuals.max_reel_affixes(R.UNCOMMON) == 0, "Uncommon 0 reel affixes")
	_check(RarityVisuals.max_reel_affixes(R.RARE) == 1, "Rare 1 reel affix")
	_check(RarityVisuals.max_reel_affixes(R.EPIC) == 1, "Epic 1 reel affix")
	_check(RarityVisuals.max_reel_affixes(R.LEGENDARY) == 2, "Legendary 2 reel affixes")

	# Inverse lookup: highest tier whose min_level_for() <= level.
	_check(RarityVisuals.rarity_for_level(1) == R.COMMON, "level 1 -> Common")
	_check(RarityVisuals.rarity_for_level(2) == R.COMMON, "level 2 -> still Common")
	_check(RarityVisuals.rarity_for_level(3) == R.UNCOMMON, "level 3 -> Uncommon")
	_check(RarityVisuals.rarity_for_level(4) == R.UNCOMMON, "level 4 -> still Uncommon")
	_check(RarityVisuals.rarity_for_level(5) == R.RARE, "level 5 -> Rare")
	_check(RarityVisuals.rarity_for_level(7) == R.EPIC, "level 7 -> Epic")
	_check(RarityVisuals.rarity_for_level(9) == R.LEGENDARY, "level 9 -> Legendary")
	_check(RarityVisuals.rarity_for_level(20) == R.LEGENDARY, "level 20 -> still Legendary (cap)")

	print(("RARITY VISUALS TEST PASSED" if _failures == 0 else "RARITY VISUALS TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_rarity_visuals.gd`
Expected: FAIL — "Identifier 'RarityVisuals' not declared" (class doesn't exist yet).

- [ ] **Step 3: Write minimal implementation**

Create `combat/rarity_visuals.gd`:

```gdscript
class_name RarityVisuals
extends RefCounted

## Shared presentation + level-gate lookups for the 5-tier WoW-style rarity ladder shared by
## Gear and Weapon (spec 2026-07-10 §3.2). Pure + static — no state, trivially testable.
## [ASSUMPTION] exact color values (approximating WoW's item-quality palette).

enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

## The level required to equip a piece of this rarity (also its level-gate).
static func min_level_for(rarity: Rarity) -> int:
	match rarity:
		Rarity.COMMON: return 1
		Rarity.UNCOMMON: return 3
		Rarity.RARE: return 5
		Rarity.EPIC: return 7
		Rarity.LEGENDARY: return 9
		_: return 1

static func display_name(rarity: Rarity) -> String:
	match rarity:
		Rarity.COMMON: return "Common"
		Rarity.UNCOMMON: return "Uncommon"
		Rarity.RARE: return "Rare"
		Rarity.EPIC: return "Epic"
		Rarity.LEGENDARY: return "Legendary"
		_: return "Common"

## WoW's actual item-quality palette (white/green/blue/purple/orange).
static func color(rarity: Rarity) -> Color:
	match rarity:
		Rarity.COMMON: return Color(1.0, 1.0, 1.0)
		Rarity.UNCOMMON: return Color(0.12, 0.8, 0.12)
		Rarity.RARE: return Color(0.2, 0.4, 1.0)
		Rarity.EPIC: return Color(0.64, 0.2, 0.93)
		Rarity.LEGENDARY: return Color(1.0, 0.5, 0.0)
		_: return Color(1.0, 1.0, 1.0)

static func max_stat_affixes(rarity: Rarity) -> int:
	match rarity:
		Rarity.COMMON: return 1
		Rarity.UNCOMMON: return 2
		Rarity.RARE: return 1
		Rarity.EPIC: return 2
		Rarity.LEGENDARY: return 2
		_: return 1

static func max_reel_affixes(rarity: Rarity) -> int:
	match rarity:
		Rarity.COMMON: return 0
		Rarity.UNCOMMON: return 0
		Rarity.RARE: return 1
		Rarity.EPIC: return 1
		Rarity.LEGENDARY: return 2
		_: return 0

## Inverse of min_level_for: the highest tier whose min_level_for() <= level. Drives the weapon
## empowerment layer's displayed tier (spec §3.4).
static func rarity_for_level(level: int) -> Rarity:
	var best: Rarity = Rarity.COMMON
	for r: Rarity in [Rarity.COMMON, Rarity.UNCOMMON, Rarity.RARE, Rarity.EPIC, Rarity.LEGENDARY]:
		if level >= min_level_for(r):
			best = r
	return best
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_rarity_visuals.gd`
Expected: PASS — "RARITY VISUALS TEST PASSED"

- [ ] **Step 5: Commit**

```bash
git add combat/rarity_visuals.gd tests/test_rarity_visuals.gd
git commit -m "feat(equipment): add RarityVisuals shared rarity ladder helper"
```

---

## Task 2: `Gear` slot/rarity rework + `ReelAffix`

**Files:**
- Create: `combat/resources/reel_affix.gd`
- Modify: `combat/resources/gear.gd`
- Modify: `tests/test_stats.gd:24-26` (fixes a break caused by removing `Slot.ARMOR`)
- Test: `tests/test_gear_rarity.gd`

**Interfaces:**
- Consumes: `RarityVisuals.Rarity` (Task 1).
- Produces: `Gear.Slot` enum (`HEADWEAR, CLOAK, CHEST, HANDS, CHARM` — `ARMOR`/`TRINKET` removed),
  `Gear.rarity: RarityVisuals.Rarity`, `Gear.reel_affixes: Array[ReelAffix]`, `ReelAffix` resource
  with `Kind` enum (`ADD_FACE, ADD_REEL, TIER_BIAS`). Task 4 (equip validation) consumes
  `Gear.rarity`/`Gear.reel_affixes`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends SceneTree

# Headless test: Gear's new 5-slot taxonomy + rarity/reel_affixes fields, and ReelAffix's shape.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_gear_rarity.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var g: Gear = Gear.new()
	_check(g.rarity == RarityVisuals.Rarity.COMMON, "Gear defaults to Common rarity")
	_check(g.reel_affixes.size() == 0, "Gear defaults to no reel affixes")
	_check(g.slot == Gear.Slot.CHEST, "Gear defaults to Chest slot")

	# The 5 non-weapon slots exist; ARMOR/TRINKET no longer do (compile-time — this line would fail
	# to parse if the enum still had them removed/renamed differently).
	var slots: Array = [Gear.Slot.HEADWEAR, Gear.Slot.CLOAK, Gear.Slot.CHEST, Gear.Slot.HANDS, Gear.Slot.CHARM]
	_check(slots.size() == 5, "5 non-weapon Gear slots exist")

	var affix: ReelAffix = ReelAffix.new()
	_check(affix.kind == ReelAffix.Kind.ADD_FACE, "ReelAffix defaults to ADD_FACE")
	affix.kind = ReelAffix.Kind.TIER_BIAS
	affix.bias_pct = 0.1
	_check(affix.kind == ReelAffix.Kind.TIER_BIAS and is_equal_approx(affix.bias_pct, 0.1), "ReelAffix fields settable")

	print(("GEAR RARITY TEST PASSED" if _failures == 0 else "GEAR RARITY TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_gear_rarity.gd`
Expected: FAIL — "Identifier 'ReelAffix' not declared" (and `Gear.rarity` doesn't exist yet).

- [ ] **Step 3: Write minimal implementation**

Create `combat/resources/reel_affix.gd`:

```gdscript
class_name ReelAffix
extends Resource

## A reel-editing affix an equipped item can carry (spec 2026-07-10 §3.3). Shape only this pass —
## no resolver wiring, since no items are authored yet (loot tables are explicitly deferred).

enum Kind { ADD_FACE, ADD_REEL, TIER_BIAS }

@export var kind: Kind = Kind.ADD_FACE
@export var damage_type_id: StringName = &""                                    # ADD_FACE / ADD_REEL
@export var result_tier: ReelFace.ResultTier = ReelFace.ResultTier.SUCCESS       # ADD_FACE
@export var multiplier: float = 1.0                                             # ADD_FACE
@export var bias_pct: float = 0.0                                               # TIER_BIAS
```

Modify `combat/resources/gear.gd` (replace the whole file):

```gdscript
class_name Gear
extends Resource

## An equippable item (spec 2026-07-10 §3.1). 5 non-weapon slots — the weapon itself lives on
## Combatant.weapon (a Weapon, not a Gear) and is never in this enum. Carries stat bonuses
## (Combatant.effective_stats() reads them, unchanged) plus reel affixes (shape only — no resolver
## wiring yet, no items authored).

enum Slot { HEADWEAR, CLOAK, CHEST, HANDS, CHARM }

@export var display_name: String = ""
@export var slot: Slot = Slot.CHEST
@export var rarity: RarityVisuals.Rarity = RarityVisuals.Rarity.COMMON
@export var stat_bonuses: Stats
@export var reel_affixes: Array[ReelAffix] = []
```

- [ ] **Step 4: Fix the break in `tests/test_stats.gd`**

`Gear.Slot.ARMOR` no longer exists. In `tests/test_stats.gd`, change:

```gdscript
	jerkin.slot = Gear.Slot.ARMOR
```

to:

```gdscript
	jerkin.slot = Gear.Slot.CHEST
```

(This is the only other reference to the old `ARMOR`/`TRINKET` values in the codebase outside historical plan docs — confirmed by grep.)

- [ ] **Step 5: Run both tests to verify they pass**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_gear_rarity.gd`
Expected: PASS — "GEAR RARITY TEST PASSED"

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_stats.gd`
Expected: PASS — "STATS TEST PASSED" (regression check)

- [ ] **Step 6: Commit**

```bash
git add combat/resources/gear.gd combat/resources/reel_affix.gd tests/test_gear_rarity.gd tests/test_stats.gd
git commit -m "feat(equipment): rework Gear to 5-slot taxonomy + rarity + ReelAffix shape"
```

---

## Task 3: Weapon empowerment layer

**Files:**
- Modify: `combat/resources/weapon.gd`
- Modify: `combat/combatant.gd` (add `weapon_effective_base_damage()`)
- Modify: `combat/combat.gd:1309,1256,1375,1457,1539,1645`
- Modify: `combat/main_phase_plan.gd:346`
- Test: `tests/test_weapon_empowerment.gd`

**Interfaces:**
- Consumes: `RarityVisuals.Rarity` (Task 1), `Combatant.level` (existing field).
- Produces: `Weapon.rarity: RarityVisuals.Rarity`, `Combatant.weapon_effective_base_damage() -> float`.
  Later tasks don't depend on this, but every combat-math call site that reads weapon damage
  switches to it for consistency (empowerment applies everywhere, not just the main spin).

- [ ] **Step 1: Write the failing test**

```gdscript
extends SceneTree

# Headless test: weapon empowerment layer — level-derived damage scaling, neutral at level 1,
# recomputed live from Combatant.level (not a persisted "weapon level").
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_weapon_empowerment.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var w: Weapon = Weapon.new()
	w.base_damage = 10.0
	w.rarity = RarityVisuals.Rarity.LEGENDARY   # authored affix budget — untouched by level

	var c: Combatant = Combatant.new()
	c.weapon = w

	# Level 1 (the default for every existing combatant): exactly neutral, no bonus.
	_check(c.level == 1, "Combatant defaults to level 1")
	_check(is_equal_approx(c.weapon_effective_base_damage(), 10.0), "level 1 -> no empowerment bonus (got %f)" % c.weapon_effective_base_damage())

	# Level 9: +3%/level for 8 levels above 1 = +24%.
	c.level = 9
	_check(is_equal_approx(c.weapon_effective_base_damage(), 12.4), "level 9 -> 10 * 1.24 = 12.4 (got %f)" % c.weapon_effective_base_damage())

	# Instant rescale: dropping level back down rescales down immediately (no persisted state).
	c.level = 1
	_check(is_equal_approx(c.weapon_effective_base_damage(), 10.0), "rescales back down instantly on level change")

	# A weapon's own rarity (affix budget) is untouched by level — it's a separate concern from the
	# level-derived damage/tier display (spec §3.4).
	_check(w.rarity == RarityVisuals.Rarity.LEGENDARY, "authored weapon rarity unaffected by level")
	_check(RarityVisuals.rarity_for_level(9) == RarityVisuals.Rarity.LEGENDARY, "displayed tier at level 9 is Legendary")
	_check(RarityVisuals.rarity_for_level(1) == RarityVisuals.Rarity.COMMON, "displayed tier at level 1 is Common (independent of the Legendary weapon's own affixes)")

	# No weapon equipped -> 0, not a crash.
	var bare: Combatant = Combatant.new()
	_check(bare.weapon_effective_base_damage() == 0.0, "no weapon -> 0.0")

	print(("WEAPON EMPOWERMENT TEST PASSED" if _failures == 0 else "WEAPON EMPOWERMENT TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_weapon_empowerment.gd`
Expected: FAIL — "Invalid assignment... rarity" / "Invalid call... weapon_effective_base_damage" (neither exists yet).

- [ ] **Step 3: Write minimal implementation**

Modify `combat/resources/weapon.gd` — add one field:

```gdscript
@export var rarity: RarityVisuals.Rarity = RarityVisuals.Rarity.COMMON   # authored loot identity — sets affix budget, fixed, never changed by level
```

Modify `combat/combatant.gd` — add a constant near the top of the file (right after the class doc
comment block, before the Signals section) and a new method near `apply_luck()`:

```gdscript
# ---------------------------------------------------------------------------
# Tunable constants (spec 2026-07-10 §5 — all [ASSUMPTION], tuned post-playtest)
# ---------------------------------------------------------------------------

## Weapon empowerment layer: +3%/level ABOVE level 1 (so level 1 is exactly neutral — no
## existing test or combatant, which all default to level 1, sees any change).
const WEAPON_LEVEL_DAMAGE_PCT: float = 0.03
```

Add this method (near `apply_luck()`):

```gdscript
## The equipped weapon's damage, scaled by the empowerment layer (spec §3.4): recomputed live from
## [member level] every call — NOT a persisted "weapon level" — so swapping weapons or changing
## level is always instantly reflected, never punished. Level 1 (the default) is exactly neutral.
func weapon_effective_base_damage() -> float:
	if weapon == null:
		return 0.0
	return weapon.base_damage * (1.0 + (level - 1) * WEAPON_LEVEL_DAMAGE_PCT)
```

Modify `combat/combat.gd` — replace every direct `_attacker.weapon.base_damage` read used for an
actual damage/rider-seed calculation with `_attacker.weapon_effective_base_damage()` (6 call
sites; each replacement is a same-line substitution, all other code on the line is unchanged):

- Line 1256: `regen.dot_base_damage = _attacker.weapon.base_damage` → `regen.dot_base_damage = _attacker.weapon_effective_base_damage()`
- Line 1309: `_resolver.resolve_combat_phase(reels, _attacker.weapon.base_damage, ...)` → `_resolver.resolve_combat_phase(reels, _attacker.weapon_effective_base_damage(), ...)`
- Line 1375: `var base: float = _attacker.weapon.base_damage` → `var base: float = _attacker.weapon_effective_base_damage()`
- Line 1457: `rider.dot_base_damage = _attacker.weapon.base_damage` → `rider.dot_base_damage = _attacker.weapon_effective_base_damage()`
- Line 1539: `var bonus: int = ceili(_attacker.weapon.base_damage * (float(hit.length) / 3.0) * type_mult)` → `var bonus: int = ceili(_attacker.weapon_effective_base_damage() * (float(hit.length) / 3.0) * type_mult)`
- Line 1645: `var base: float = _attacker.weapon.base_damage` → `var base: float = _attacker.weapon_effective_base_damage()`

Modify `combat/main_phase_plan.gd:346`:

```gdscript
				combatant.try_splice_reel(combatant.weapon_type(), combatant.weapon.base_damage, ability_cost, reel_cap)
```

→

```gdscript
				combatant.try_splice_reel(combatant.weapon_type(), combatant.weapon_effective_base_damage(), ability_cost, reel_cap)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_weapon_empowerment.gd`
Expected: PASS — "WEAPON EMPOWERMENT TEST PASSED"

- [ ] **Step 5: Run the full existing regression suite**

Every existing headless test defaults `Combatant.level` to 1 in every damage-asserting scenario
(confirmed by audit: no headless test both sets `level` away from 1 AND asserts an exact damage
number derived from `weapon.base_damage` through these 7 call sites — the tests that do set
`level = 5/7/9` test ability-unlock/effect logic directly, not these orchestrator call sites, which
are only reached by the live `combat.tscn` scene). Because level 1 is mathematically neutral
(`1.0 + (1-1)*0.03 == 1.0`), every existing suite's expected numbers are unchanged. Run the full
suite directory (or each suite individually) and confirm all stay green — this is a real
verification step, not a placeholder, precisely because the neutral-at-level-1 property makes it
safe to predict in advance.

- [ ] **Step 6: Commit**

```bash
git add combat/resources/weapon.gd combat/combatant.gd combat/combat.gd combat/main_phase_plan.gd tests/test_weapon_empowerment.gd
git commit -m "feat(equipment): add weapon empowerment layer (level-derived damage, neutral at L1)"
```

---

## Task 4: Equip validation (level-gate + Resonance cap)

**Files:**
- Modify: `combat/combatant.gd` (add `can_equip()`)
- Test: `tests/test_gear_equip_validation.gd`

**Interfaces:**
- Consumes: `Gear.rarity`/`Gear.reel_affixes` (Task 2), `RarityVisuals.min_level_for()` (Task 1),
  `Combatant.level` (existing), `Combatant.gear: Array[Gear]` (existing).
- Produces: `Combatant.can_equip(g: Gear) -> bool` — the gate any future equip-UI calls before
  adding an item to `Combatant.gear`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends SceneTree

# Headless test: Combatant.can_equip() enforces the rarity level-gate and the per-item Resonance cap.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_gear_equip_validation.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _reel_affixed_gear() -> Gear:
	var g: Gear = Gear.new()
	g.rarity = RarityVisuals.Rarity.RARE
	g.reel_affixes = [ReelAffix.new()]
	return g

func _initialize() -> void:
	# Level-gate: a level 1 combatant cannot equip a Rare (min level 5) item.
	var c: Combatant = Combatant.new()
	c.level = 1
	var rare: Gear = _reel_affixed_gear()
	_check(not c.can_equip(rare), "level 1 cannot equip Rare (min level 5)")

	c.level = 5
	_check(c.can_equip(rare), "level 5 can equip Rare")

	# Resonance cap: 2 reel-affix items equipped allows a 3rd only after freeing a slot.
	var c2: Combatant = Combatant.new()
	c2.level = 9
	var first: Gear = _reel_affixed_gear()
	var second: Gear = _reel_affixed_gear()
	var third: Gear = _reel_affixed_gear()
	c2.gear = [first, second]
	_check(not c2.can_equip(third), "3rd reel-affix item refused at the Resonance cap of 2")
	c2.gear = [first]
	_check(c2.can_equip(third), "3rd reel-affix item allowed once a slot is freed")

	# A Legendary item with 2 reel affixes still only costs 1 Resonance slot (per-item, not per-affix).
	var legendary: Gear = Gear.new()
	legendary.rarity = RarityVisuals.Rarity.LEGENDARY
	legendary.reel_affixes = [ReelAffix.new(), ReelAffix.new()]
	var c3: Combatant = Combatant.new()
	c3.level = 9
	c3.gear = [first]   # 1 reel-affix item already equipped
	_check(c3.can_equip(legendary), "Legendary (2 reel affixes, 1 item) still fits within the cap of 2 items")

	# Stat-only gear (no reel affixes) never touches the Resonance cap.
	var stat_only: Gear = Gear.new()
	stat_only.rarity = RarityVisuals.Rarity.COMMON
	var c4: Combatant = Combatant.new()
	c4.level = 1
	c4.gear = [first, second]   # Resonance cap already full
	_check(c4.can_equip(stat_only), "stat-only gear ignores the Resonance cap")

	print(("GEAR EQUIP VALIDATION TEST PASSED" if _failures == 0 else "GEAR EQUIP VALIDATION TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_gear_equip_validation.gd`
Expected: FAIL — "Invalid call... can_equip" (method doesn't exist yet).

- [ ] **Step 3: Write minimal implementation**

Add to `combat/combatant.gd` (near `effective_stats()`):

```gdscript
## True if this combatant may equip [param g]: meets the rarity level-gate, and — if [param g]
## carries any reel affixes — doesn't exceed the Resonance cap of 2 reel-affix ITEMS equipped
## (spec §3.5; per-item, not per-affix, so a Legendary's 2 reel affixes still cost only 1 slot).
const RESONANCE_CAP: int = 2

func can_equip(g: Gear) -> bool:
	if level < RarityVisuals.min_level_for(g.rarity):
		return false
	if g.reel_affixes.size() > 0:
		var resonance_count: int = 0
		for existing: Gear in gear:
			if existing != g and existing.reel_affixes.size() > 0:
				resonance_count += 1
		if resonance_count >= RESONANCE_CAP:
			return false
	return true
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_gear_equip_validation.gd`
Expected: PASS — "GEAR EQUIP VALIDATION TEST PASSED"

- [ ] **Step 5: Commit**

```bash
git add combat/combatant.gd tests/test_gear_equip_validation.gd
git commit -m "feat(equipment): add Combatant.can_equip() level-gate + Resonance cap validation"
```

---

## Task 5: Might rework — reel-count-normalized Power

**Files:**
- Modify: `combat/combatant.gd` (add constant + `might_damage_bonus_per_reel()`)
- Modify: `combat/combat.gd:1309` (the line as left by Task 3)
- Modify: `tests/test_combat_loop.gd:55` (fidelity fix, no numeric change)
- Test: `tests/test_might_scaling.gd`

**Interfaces:**
- Consumes: `Combatant.effective_stats()` (existing).
- Produces: `Combatant.might_damage_bonus_per_reel(active_reel_count: int) -> int`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends SceneTree

# Headless test: Might converts to reel-count-normalized flat damage (WoW AP-normalized-by-speed
# analog, reel-count instead of weapon speed).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_might_scaling.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var c: Combatant = Combatant.new()
	var s: Stats = Stats.new(); s.might = 3   # power = 3 * 2.0 = 6.0
	c.base_stats = s

	# 2-reel "heavy" loadout: 6.0 / 2 = 3 per reel.
	_check(c.might_damage_bonus_per_reel(2) == 3, "2 reels -> 3 dmg/reel (got %d)" % c.might_damage_bonus_per_reel(2))
	# 3-reel "typical" loadout: ceil(6.0 / 3) = 2 per reel.
	_check(c.might_damage_bonus_per_reel(3) == 2, "3 reels -> 2 dmg/reel (got %d)" % c.might_damage_bonus_per_reel(3))
	# 5-reel "rapid" loadout: ceil(6.0 / 5) = 2 per reel (smaller share, but more procs).
	_check(c.might_damage_bonus_per_reel(5) == 2, "5 reels -> 2 dmg/reel (got %d)" % c.might_damage_bonus_per_reel(5))

	# 0 Might -> 0 bonus regardless of reel count.
	var zero: Combatant = Combatant.new()
	_check(zero.might_damage_bonus_per_reel(3) == 0, "0 Might -> 0 bonus")

	print(("MIGHT SCALING TEST PASSED" if _failures == 0 else "MIGHT SCALING TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_might_scaling.gd`
Expected: FAIL — "Invalid call... might_damage_bonus_per_reel" (method doesn't exist yet).

- [ ] **Step 3: Write minimal implementation**

Add to `combat/combatant.gd`'s constants section (next to `WEAPON_LEVEL_DAMAGE_PCT`):

```gdscript
## Might -> Power ratio (WoW's 2 AP/Strength for plate/strength classes).
const MIGHT_TO_POWER_RATIO: float = 2.0
```

Add this method (near `apply_luck()`/`weapon_effective_base_damage()`):

```gdscript
## Might's reel/spin hook (spec §5.1): funnels through a hidden derived "Power" value, then
## converts to a flat damage bonus PER REEL, normalized by the active reel count — the reel-count
## analog of WoW's Attack-Power-normalized-by-weapon-speed. A low-reel-count ("heavy") loadout gets
## a bigger per-reel bonus from the same Might than a high-reel-count ("rapid") one; the total
## Might-derived damage for the turn stays roughly conserved either way.
func might_damage_bonus_per_reel(active_reel_count: int) -> int:
	var power: float = effective_stats().might * MIGHT_TO_POWER_RATIO
	return ceili(power / maxf(active_reel_count, 1))
```

Modify `combat/combat.gd:1309` — this line was already changed by Task 3 to read
`_attacker.weapon_effective_base_damage()` for its base-damage argument; now change its
flat-damage-bonus argument too:

```gdscript
	var attacks: Array[CombatResolver.AttackResult] = _resolver.resolve_combat_phase(reels, _attacker.weapon_effective_base_damage(), _defender.defense_type, _attacker.wild_reel_indices(), weapon_count, _attacker.effective_stats().might, extra_lines, true, dmg_mult)
```

→

```gdscript
	var attacks: Array[CombatResolver.AttackResult] = _resolver.resolve_combat_phase(reels, _attacker.weapon_effective_base_damage(), _defender.defense_type, _attacker.wild_reel_indices(), weapon_count, _attacker.might_damage_bonus_per_reel(reels.size()), extra_lines, true, dmg_mult)
```

Modify `tests/test_combat_loop.gd:55` (fidelity fix — this integration harness's header claims to
mirror "the same wiring combat.gd uses"; `_pc`/`_enemy` never get `base_stats` set in this file so
Might is 0 either way and no assertion changes, but the call should match real wiring):

```gdscript
	var attacks: Array = _resolver.resolve_combat_phase(c.turn_reels, c.weapon.base_damage, defender.defense_type, c.wild_reel_indices(), c.weapon.reels.size(), c.effective_stats().might)
```

→

```gdscript
	var attacks: Array = _resolver.resolve_combat_phase(c.turn_reels, c.weapon_effective_base_damage(), defender.defense_type, c.wild_reel_indices(), c.weapon.reels.size(), c.might_damage_bonus_per_reel(c.weapon.reels.size()))
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_might_scaling.gd`
Expected: PASS — "MIGHT SCALING TEST PASSED"

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_combat_loop.gd`
Expected: PASS — "...loop terminated..." style checks all green (regression; no numeric assertions on damage in this file, so unaffected).

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_might_damage.gd`
Expected: PASS — untouched (this test exercises `CombatResolver.resolve_combat_phase`'s `flat_damage_bonus` parameter directly with literal values, never through `Combatant`, so it's unaffected by this task).

- [ ] **Step 5: Commit**

```bash
git add combat/combatant.gd combat/combat.gd tests/test_might_scaling.gd tests/test_combat_loop.gd
git commit -m "feat(stats): rework Might into reel-count-normalized Power (WoW AP analog)"
```

---

## Task 6: Vigor rework — DoT damage resistance

**Files:**
- Modify: `combat/combatant.gd` (add constants + `dot_damage_multiplier()`)
- Modify: `combat/combat.gd:948-961` (`_apply_dot`)
- Test: `tests/test_vigor_dot_resist.gd`

**Interfaces:**
- Consumes: `Combatant.effective_stats()` (existing).
- Produces: `Combatant.dot_damage_multiplier() -> float`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends SceneTree

# Headless test: Vigor reduces incoming DoT tick damage (spec §5.2), with a floor so it's never
# full immunity, and never touches beneficial ticks (Regen/HoT).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_vigor_dot_resist.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var zero: Combatant = Combatant.new()
	_check(is_equal_approx(zero.dot_damage_multiplier(), 1.0), "0 Vigor -> 1.0 (no resist)")

	var some: Combatant = Combatant.new()
	var s: Stats = Stats.new(); s.vigor = 4
	some.base_stats = s
	_check(is_equal_approx(some.dot_damage_multiplier(), 0.8), "4 Vigor -> 1.0 - 4*0.05 = 0.8 (got %f)" % some.dot_damage_multiplier())

	var capped: Combatant = Combatant.new()
	var s2: Stats = Stats.new(); s2.vigor = 20   # would be 0.0 uncapped
	capped.base_stats = s2
	_check(is_equal_approx(capped.dot_damage_multiplier(), 0.4), "20 Vigor hits the 0.4 floor (got %f)" % capped.dot_damage_multiplier())

	print(("VIGOR DOT RESIST TEST PASSED" if _failures == 0 else "VIGOR DOT RESIST TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_vigor_dot_resist.gd`
Expected: FAIL — "Invalid call... dot_damage_multiplier" (method doesn't exist yet).

- [ ] **Step 3: Write minimal implementation**

Add to `combat/combatant.gd`'s constants section:

```gdscript
const VIGOR_DOT_RESIST_PER_POINT: float = 0.05   # 5%/point
const VIGOR_DOT_RESIST_FLOOR: float = 0.4        # never below 40% damage taken
```

Add this method:

```gdscript
## Vigor's reel/spin hook (spec §5.2): reduces incoming DAMAGE_OVER_TIME tick damage. Floored so
## Vigor never grants full DoT immunity.
func dot_damage_multiplier() -> float:
	return clampf(1.0 - effective_stats().vigor * VIGOR_DOT_RESIST_PER_POINT, VIGOR_DOT_RESIST_FLOOR, 1.0)
```

Modify `combat/combat.gd`'s `_apply_dot` (currently lines 948-961):

```gdscript
func _apply_dot(c: Combatant) -> void:
	if c == null or not c.is_alive():
		return
	for e: Effect in c.active_effects:
		if e.kind == Effect.Kind.DAMAGE_OVER_TIME:
			var amount: int = e.dot_damage()
			if amount > 0:
				if e.beneficial:
					c.heal(amount)
					_log("  %s regenerates %d HP from %s." % [c.display_name, amount, String(e.id).to_upper()])
				else:
					c.take_damage(amount)
					_log("  %s suffers %d %s damage (×%d)." % [c.display_name, amount, String(e.id).to_upper(), e.stacks])
	(_panels[c] as CombatantPanel).refresh_status()
```

→

```gdscript
func _apply_dot(c: Combatant) -> void:
	if c == null or not c.is_alive():
		return
	for e: Effect in c.active_effects:
		if e.kind == Effect.Kind.DAMAGE_OVER_TIME:
			var amount: int = e.dot_damage()
			if amount > 0:
				if e.beneficial:
					c.heal(amount)
					_log("  %s regenerates %d HP from %s." % [c.display_name, amount, String(e.id).to_upper()])
				else:
					var resisted: int = ceili(amount * c.dot_damage_multiplier())
					c.take_damage(resisted)
					_log("  %s suffers %d %s damage (×%d)." % [c.display_name, resisted, String(e.id).to_upper(), e.stacks])
	(_panels[c] as CombatantPanel).refresh_status()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_vigor_dot_resist.gd`
Expected: PASS — "VIGOR DOT RESIST TEST PASSED"

- [ ] **Step 5: Run regression on existing DoT-related suites**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_crushing_slow.gd`
Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_hex.gd`
Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_entangle.gd`

Expected: all PASS. These tests exercise Bleed/Cursed/etc. stacking and effect-attach logic
directly on `Effect`/`Combatant`, not through `combat.gd`'s `_apply_dot()` (which is only reached
via the live scene), so they're unaffected — this step confirms that assumption rather than
guessing at it.

- [ ] **Step 6: Commit**

```bash
git add combat/combatant.gd combat/combat.gd tests/test_vigor_dot_resist.gd
git commit -m "feat(stats): rework Vigor to reduce incoming DoT damage (was: enemy crit reduction)"
```

---

## Task 7: Focus rework — per-Upkeep regen bonus

**Files:**
- Modify: `combat/combatant.gd` (new seed fields + `apply_stats()` derivation)
- Modify: `combat/resources/character_class.gd:99-108`
- Modify: `combat/enemy_library.gd:64-69`
- Modify: `combat/combat.gd:210-218` (`_make_combatant`)
- Modify: `tests/test_mana_derivation.gd:48` (fixes a break: Focus now adds regen too)
- Modify: `tests/test_seer_class.gd:32` (same break)
- Test: `tests/test_focus_regen.gd`

**Interfaces:**
- Consumes: `Combatant.apply_stats()` (existing, extended in place).
- Produces: `Combatant.base_stamina_regen: int`, `Combatant.base_mana_regen: int` (new pre-stat
  seed fields, same pattern as `base_max_hp`).

- [ ] **Step 1: Write the failing test**

```gdscript
extends SceneTree

# Headless test: Focus adds to the per-Upkeep resource regen tick (spec §5.3), on top of its
# existing max-pool role. Derivation must be idempotent (apply_stats can run more than once).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_focus_regen.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var c: Combatant = Combatant.new()
	c.base_max_stamina = 5
	c.base_stamina_regen = 1
	c.resource_pool = ResourcePool.new()
	var s: Stats = Stats.new(); s.focus = 6
	c.base_stats = s
	c.apply_stats()
	# regen = base 1 + floor(6 * 0.5) = 1 + 3 = 4.
	_check(c.resource_pool.regen_per_turn == 4, "stamina regen = 1 base + Focus 6 bonus 3 = 4 (got %d)" % c.resource_pool.regen_per_turn)

	# Idempotency: calling apply_stats() again must not compound the bonus.
	c.apply_stats()
	_check(c.resource_pool.regen_per_turn == 4, "apply_stats is idempotent for regen (got %d)" % c.resource_pool.regen_per_turn)

	# Mana rail, same derivation.
	var m: Combatant = Combatant.new()
	m.base_max_mana = 9
	m.base_mana_regen = 1
	m.resource_pool = ResourcePool.new()
	var s2: Stats = Stats.new(); s2.focus = 6
	m.base_stats = s2
	m.apply_stats()
	_check(m.resource_pool.mana_regen_per_turn == 4, "mana regen = 1 base + Focus 6 bonus 3 = 4 (got %d)" % m.resource_pool.mana_regen_per_turn)

	# 0 Focus -> base regen unchanged.
	var zero: Combatant = Combatant.new()
	zero.base_max_stamina = 5
	zero.base_stamina_regen = 2
	zero.resource_pool = ResourcePool.new()
	zero.apply_stats()
	_check(zero.resource_pool.regen_per_turn == 2, "0 Focus -> base regen unchanged (got %d)" % zero.resource_pool.regen_per_turn)

	print(("FOCUS REGEN TEST PASSED" if _failures == 0 else "FOCUS REGEN TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_focus_regen.gd`
Expected: FAIL — "Invalid assignment... base_stamina_regen" (field doesn't exist yet).

- [ ] **Step 3: Write minimal implementation**

Add two fields to `combat/combatant.gd`, alongside the existing pre-stat seeds (`base_max_hp` etc.,
currently lines 82-85):

```gdscript
var base_stamina_regen: int = 0
var base_mana_regen: int = 0
```

Add a constant next to `MIGHT_TO_POWER_RATIO`:

```gdscript
const FOCUS_REGEN_PER_POINT: float = 0.5
```

Modify `apply_stats()` (currently):

```gdscript
func apply_stats() -> void:
	var s: Stats = effective_stats()
	max_hp = base_max_hp + s.vigor
	if resource_pool != null:
		# Focus boosts only the rail(s) the class actually USES (base > 0): a stamina class gets no phantom
		# mana pool, and a mana-only caster (Seer, base_max_stamina = 0) gets no phantom stamina rail.
		resource_pool.max_stamina = (base_max_stamina + s.focus) if base_max_stamina > 0 else 0
		resource_pool.stamina = mini(resource_pool.stamina, resource_pool.max_stamina)
		resource_pool.max_mana = (base_max_mana + s.focus) if base_max_mana > 0 else 0
		resource_pool.mana = mini(resource_pool.mana, resource_pool.max_mana)
	if bonus_meter != null:
		bonus_meter.floor = base_meter_floor + s.grit
```

→

```gdscript
func apply_stats() -> void:
	var s: Stats = effective_stats()
	max_hp = base_max_hp + s.vigor
	if resource_pool != null:
		# Focus boosts only the rail(s) the class actually USES (base > 0): a stamina class gets no phantom
		# mana pool, and a mana-only caster (Seer, base_max_stamina = 0) gets no phantom stamina rail.
		resource_pool.max_stamina = (base_max_stamina + s.focus) if base_max_stamina > 0 else 0
		resource_pool.stamina = mini(resource_pool.stamina, resource_pool.max_stamina)
		resource_pool.max_mana = (base_max_mana + s.focus) if base_max_mana > 0 else 0
		resource_pool.mana = mini(resource_pool.mana, resource_pool.max_mana)
		# Focus also adds to the per-Upkeep regen tick (spec §5.3), same base>0 rail-gating as above.
		var focus_regen_bonus: int = floori(s.focus * FOCUS_REGEN_PER_POINT)
		if base_max_stamina > 0:
			resource_pool.regen_per_turn = base_stamina_regen + focus_regen_bonus
		if base_max_mana > 0:
			resource_pool.mana_regen_per_turn = base_mana_regen + focus_regen_bonus
	if bonus_meter != null:
		bonus_meter.floor = base_meter_floor + s.grit
```

Modify `combat/resources/character_class.gd` (currently lines 99-108):

```gdscript
	if is_player:
		var pool: ResourcePool = ResourcePool.new()
		pool.stamina = start_stamina
		pool.regen_per_turn = stamina_regen
		pool.mana = start_mana
		pool.mana_regen_per_turn = mana_regen
		c.resource_pool = pool
		c.base_max_stamina = base_max_stamina
		c.base_max_mana = base_max_mana

	c.apply_stats()   # derive max_hp / max_stamina / meter.floor BEFORE seeding hp
```

→

```gdscript
	if is_player:
		var pool: ResourcePool = ResourcePool.new()
		pool.stamina = start_stamina
		pool.mana = start_mana
		c.resource_pool = pool
		c.base_max_stamina = base_max_stamina
		c.base_max_mana = base_max_mana
		c.base_stamina_regen = stamina_regen
		c.base_mana_regen = mana_regen

	c.apply_stats()   # derive max_hp / max_stamina / regen / meter.floor BEFORE seeding hp
```

Modify `combat/enemy_library.gd` (currently lines 64-69):

```gdscript
		c.base_max_stamina = maxi(5, ability_cost)
		var pool: ResourcePool = ResourcePool.new()
		pool.stamina = ability_cost          # enough to fire turn 1
		pool.regen_per_turn = ability_cost   # refreshes each turn so the greedy AI can re-fire
		c.resource_pool = pool
```

→

```gdscript
		c.base_max_stamina = maxi(5, ability_cost)
		var pool: ResourcePool = ResourcePool.new()
		pool.stamina = ability_cost          # enough to fire turn 1
		c.resource_pool = pool
		c.base_stamina_regen = ability_cost  # refreshes each turn so the greedy AI can re-fire
```

Modify `combat/combat.gd`'s `_make_combatant` (currently lines 210-218):

```gdscript
	if is_player:
		var pool: ResourcePool = ResourcePool.new()
		pool.stamina = 3
		pool.regen_per_turn = 1
		c.resource_pool = pool
		c.base_max_stamina = 5
	c.base_stats = base_stats
	c.gear = items
	c.apply_stats()       # derive max_hp / max_stamina / meter.floor from stats BEFORE seeding hp
```

→

```gdscript
	if is_player:
		var pool: ResourcePool = ResourcePool.new()
		pool.stamina = 3
		c.resource_pool = pool
		c.base_max_stamina = 5
		c.base_stamina_regen = 1
	c.base_stats = base_stats
	c.gear = items
	c.apply_stats()       # derive max_hp / max_stamina / regen / meter.floor from stats BEFORE seeding hp
```

- [ ] **Step 4: Fix the two existing tests this changes**

`tests/test_mana_derivation.gd:48` — Focus 6 now also adds `floor(6*0.5) = 3` to the built
caster's mana regen (base `mana_regen = 1`), so the total becomes 4:

```gdscript
	_check(built.resource_pool.mana_regen_per_turn == 1, "built mana regen 1 (got %d)" % built.resource_pool.mana_regen_per_turn)
```

→

```gdscript
	_check(built.resource_pool.mana_regen_per_turn == 4, "built mana regen = 1 base + Focus 6 bonus 3 = 4 (got %d)" % built.resource_pool.mana_regen_per_turn)
```

`tests/test_seer_class.gd:32` — Seer's base `mana_regen = 2` + Focus 6 bonus 3 = 5:

```gdscript
	_check(c.resource_pool.mana_regen_per_turn == 2, "mana regen 2/turn (playtest tuning, got %d)" % c.resource_pool.mana_regen_per_turn)
```

→

```gdscript
	_check(c.resource_pool.mana_regen_per_turn == 5, "mana regen = 2 base + Focus 6 bonus 3 = 5 (playtest tuning, got %d)" % c.resource_pool.mana_regen_per_turn)
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_focus_regen.gd`
Expected: PASS — "FOCUS REGEN TEST PASSED"

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_mana_derivation.gd`
Expected: PASS

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_seer_class.gd`
Expected: PASS

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_character_class.gd`
Expected: PASS (regression — this file asserts `max_stamina`, not `regen_per_turn`, so it's unaffected)

- [ ] **Step 6: Commit**

```bash
git add combat/combatant.gd combat/resources/character_class.gd combat/enemy_library.gd combat/combat.gd tests/test_focus_regen.gd tests/test_mana_derivation.gd tests/test_seer_class.gd
git commit -m "feat(stats): rework Focus to also boost per-Upkeep resource regen"
```

---

## Task 8: Luck rework — threshold crit faces + extra payline lines

**Files:**
- Modify: `combat/combatant.gd` (`apply_luck()` threshold + new `luck_extra_lines()`)
- Modify: `combat/combat.gd:1306-1308` (extra_lines construction)
- Modify: `tests/test_stats.gd` (fixes a break: Luck 2 no longer adds 2 crit faces)
- Modify: `tests/test_character_class.gd:16` (fixes a break: Luck 1 no longer adds a crit face)
- Test: `tests/test_luck_threshold.gd`

**Interfaces:**
- Consumes: `Combatant.effective_stats()` (existing), `PaylineLibrary.bonus_line()` (existing,
  already used by Loaded Dice).
- Produces: `Combatant.luck_extra_lines(weapon_reel_count: int) -> Array` (the previously-reserved
  `extra_lines`/Luck hook, now wired).

- [ ] **Step 1: Write the failing test**

```gdscript
extends SceneTree

# Headless test: Luck needs multiple points per crit face (threshold, not 1:1), and separately
# grants extra scored payline lines via the extra_lines hook (spec §5.4).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_luck_threshold.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _crit_faces(w: Weapon) -> int:
	var n: int = 0
	for f: ReelFace in w.reels[0].faces:
		if f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS: n += 1
	return n

func _initialize() -> void:
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")

	# Below threshold (Luck 2, needs 3): no crit face added.
	var w1: Weapon = Weapon.new(); w1.reels.append(ActionReel.make_default(slashing))
	var base_crit: int = _crit_faces(w1)
	var c1: Combatant = Combatant.new(); c1.weapon = w1
	var s1: Stats = Stats.new(); s1.luck = 2
	c1.base_stats = s1
	c1.apply_luck()
	_check(_crit_faces(w1) == base_crit, "Luck 2 (below threshold 3) adds 0 crit faces")

	# At the threshold (Luck 7 -> floor(7/3) = 2 faces).
	var w2: Weapon = Weapon.new(); w2.reels.append(ActionReel.make_default(slashing))
	var base_crit2: int = _crit_faces(w2)
	var c2: Combatant = Combatant.new(); c2.weapon = w2
	var s2: Stats = Stats.new(); s2.luck = 7
	c2.base_stats = s2
	c2.apply_luck()
	_check(_crit_faces(w2) == base_crit2 + 2, "Luck 7 -> floor(7/3) = 2 crit faces added (got %d, base %d)" % [_crit_faces(w2), base_crit2])

	# Extra payline lines: Luck 4 -> floor(4/4) = 1 extra line; Luck 3 -> 0.
	var c3: Combatant = Combatant.new()
	var s3: Stats = Stats.new(); s3.luck = 4
	c3.base_stats = s3
	_check(c3.luck_extra_lines(3).size() == 1, "Luck 4 -> 1 extra payline line (got %d)" % c3.luck_extra_lines(3).size())

	var c4: Combatant = Combatant.new()
	var s4: Stats = Stats.new(); s4.luck = 3
	c4.base_stats = s4
	_check(c4.luck_extra_lines(3).size() == 0, "Luck 3 (below threshold 4) -> 0 extra lines")

	print(("LUCK THRESHOLD TEST PASSED" if _failures == 0 else "LUCK THRESHOLD TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_luck_threshold.gd`
Expected: FAIL — the crit-face assertions fail against the current 1:1 `apply_luck()` (Luck 2
currently adds 2 faces, not 0), and `luck_extra_lines` doesn't exist yet.

- [ ] **Step 3: Write minimal implementation**

Add constants to `combat/combatant.gd`:

```gdscript
const LUCK_PER_CRIT_FACE: int = 3
const LUCK_PER_EXTRA_LINE: int = 4
```

Modify `apply_luck()` (currently):

```gdscript
func apply_luck() -> void:
	if weapon == null:
		return
	var n: int = effective_stats().luck
	if n <= 0:
		return
	for reel: ActionReel in weapon.reels:
		for i: int in range(n):
			var f: ReelFace = ReelFace.new()
			f.result_tier = ReelFace.ResultTier.CRIT_SUCCESS
			f.multiplier = 2.0
			reel.faces.append(f)
		reel.faces.shuffle()
```

→ (only the `n` computation changes, integer division floors for non-negative ints):

```gdscript
func apply_luck() -> void:
	if weapon == null:
		return
	var n: int = effective_stats().luck / LUCK_PER_CRIT_FACE
	if n <= 0:
		return
	for reel: ActionReel in weapon.reels:
		for i: int in range(n):
			var f: ReelFace = ReelFace.new()
			f.result_tier = ReelFace.ResultTier.CRIT_SUCCESS
			f.multiplier = 2.0
			reel.faces.append(f)
		reel.faces.shuffle()
```

Add this method (near `apply_luck()`):

```gdscript
## Luck's payline hook (spec §5.4) — the extra_lines mechanism was reserved for Luck but never
## wired (only Loaded Dice used it). Every LUCK_PER_EXTRA_LINE points grants one additional scored
## payline line, stacking alongside any ability-granted extra lines (e.g. Loaded Dice).
func luck_extra_lines(weapon_reel_count: int) -> Array:
	var n: int = effective_stats().luck / LUCK_PER_EXTRA_LINE
	var lines: Array = []
	for i: int in range(n):
		lines.append(PaylineLibrary.bonus_line(weapon_reel_count))
	return lines
```

Modify `combat/combat.gd` (currently lines 1306-1308):

```gdscript
	var extra_lines: Array = []
	if _attacker.loaded_dice_pending:
		extra_lines.append(PaylineLibrary.bonus_line(weapon_count))
```

→

```gdscript
	var extra_lines: Array = []
	if _attacker.loaded_dice_pending:
		extra_lines.append(PaylineLibrary.bonus_line(weapon_count))
	extra_lines.append_array(_attacker.luck_extra_lines(weapon_count))
```

- [ ] **Step 4: Fix the two existing tests this changes**

`tests/test_stats.gd` — the Luck block (currently `ls.luck = 2` expecting `+2` crit faces).
Change:

```gdscript
	var ls: Stats = Stats.new(); ls.luck = 2
	_check(ls.plus(Stats.new()).luck == 2, "Stats.plus sums luck")
```

→

```gdscript
	var ls: Stats = Stats.new(); ls.luck = 7
	_check(ls.plus(Stats.new()).luck == 7, "Stats.plus sums luck")
```

And change the assertion further down:

```gdscript
	_check(new_crit == base_crit + 2, "apply_luck adds 2 crit faces (Luck 2): %d -> %d" % [base_crit, new_crit])
```

→

```gdscript
	_check(new_crit == base_crit + 2, "apply_luck adds floor(7/3)=2 crit faces (Luck 7): %d -> %d" % [base_crit, new_crit])
```

`tests/test_character_class.gd:16` — bump the shared test Stats' Luck from 1 to 3 (a clean
multiple of the new threshold; the final assertion on line 47 stays numerically identical —
`crit == 2` — since `floor(3/3) = 1` added face, same as the old `1` default + `1` before):

```gdscript
	var s: Stats = Stats.new(); s.might = 3; s.vigor = 3; s.focus = 1; s.grit = 2; s.luck = 1
```

→

```gdscript
	var s: Stats = Stats.new(); s.might = 3; s.vigor = 3; s.focus = 1; s.grit = 2; s.luck = 3
```

And update the comment on line 47 for accuracy (the assertion itself, `crit == 2`, is unchanged):

```gdscript
	_check(crit == 2, "apply_luck added 1 crit face (1 default + 1 = 2; got %d)" % crit)
```

→

```gdscript
	_check(crit == 2, "apply_luck added floor(3/3)=1 crit face (1 default + 1 = 2; got %d)" % crit)
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_luck_threshold.gd`
Expected: PASS — "LUCK THRESHOLD TEST PASSED"

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_stats.gd`
Expected: PASS

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_character_class.gd`
Expected: PASS

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_loaded_dice.gd`
Expected: PASS (regression — Loaded Dice's own `extra_lines.append(...)` call is untouched; this
task only appends Luck's lines alongside it, and the roster classes used in that test have Luck 0
per `test_seer_class.gd`-style profiles, so `luck_extra_lines()` contributes an empty array there).

- [ ] **Step 6: Commit**

```bash
git add combat/combatant.gd combat/combat.gd tests/test_luck_threshold.gd tests/test_stats.gd tests/test_character_class.gd
git commit -m "feat(stats): rework Luck to a threshold crit-face conversion + wire extra_lines payline hook"
```

---

## Task 9: `PartyInventory` resource

**Files:**
- Create: `economy/resources/party_inventory.gd`
- Test: `tests/test_party_inventory.gd`

**Interfaces:**
- Consumes: `Gear` (existing/Task 2).
- Produces: `PartyInventory` with `gear_capacity() -> int`, `can_add_gear() -> bool`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends SceneTree

# Headless test: PartyInventory's Gear-tab cap (20 + 10/unlocked companion slot); other tabs uncapped.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_party_inventory.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var inv: PartyInventory = PartyInventory.new()
	_check(inv.gear_capacity() == 20, "0 companion slots -> 20 base capacity (got %d)" % inv.gear_capacity())

	inv.unlocked_companion_slots = 1
	_check(inv.gear_capacity() == 30, "1 companion slot -> 30 capacity (got %d)" % inv.gear_capacity())

	inv.unlocked_companion_slots = 2
	_check(inv.gear_capacity() == 40, "2 companion slots -> 40 capacity (got %d)" % inv.gear_capacity())

	# Capacity is slot-unlock-driven, not active-headcount-driven — filling the array to capacity
	# blocks further adds regardless of how many companions are CURRENTLY active.
	for i: int in range(40):
		inv.gear.append(Gear.new())
	_check(not inv.can_add_gear(), "Gear tab full at capacity refuses further adds")
	inv.gear.pop_back()
	_check(inv.can_add_gear(), "Gear tab under capacity allows adds")

	# Other tabs are uncapped.
	for i: int in range(500):
		inv.materials.append(Resource.new())
	_check(inv.materials.size() == 500, "Materials tab uncapped (got %d)" % inv.materials.size())

	print(("PARTY INVENTORY TEST PASSED" if _failures == 0 else "PARTY INVENTORY TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_party_inventory.gd`
Expected: FAIL — "Identifier 'PartyInventory' not declared" (class doesn't exist yet).

- [ ] **Step 3: Write minimal implementation**

Create `economy/resources/party_inventory.gd`:

```gdscript
class_name PartyInventory
extends Resource

## One shared inventory per PC (not per-companion) — spec 2026-07-10 §4.1. Weightless; only the
## Gear tab is slot-capped (a soft friction lever toward banking/selling, not a hard wall).
## Materials/Reel-Mods/Quest stay uncapped. `unlocked_companion_slots` increments PERMANENTLY at
## story beats regardless of whether a companion currently occupies the slot.

const BASE_GEAR_CAPACITY: int = 20
const GEAR_CAPACITY_PER_SLOT: int = 10

@export var gear: Array[Gear] = []
@export var reel_mods: Array[Resource] = []    # uncapped; shape TBD when 27-crafting is designed
@export var materials: Array[Resource] = []    # uncapped, stacking
@export var quest_items: Array[Resource] = []  # uncapped; never banked (per-playthrough only)
@export var gold: int = 0
@export var unlocked_companion_slots: int = 0  # 0-2, story-gated

func gear_capacity() -> int:
	return BASE_GEAR_CAPACITY + GEAR_CAPACITY_PER_SLOT * unlocked_companion_slots

func can_add_gear() -> bool:
	return gear.size() < gear_capacity()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_party_inventory.gd`
Expected: PASS — "PARTY INVENTORY TEST PASSED"

- [ ] **Step 5: Commit**

```bash
git add economy/resources/party_inventory.gd tests/test_party_inventory.gd
git commit -m "feat(economy): add PartyInventory with the capped Gear tab"
```

---

## Task 10: `Vault` resource

**Files:**
- Create: `economy/resources/vault.gd`
- Test: `tests/test_vault.gd`

**Interfaces:**
- Consumes: `Gear` (existing/Task 2).
- Produces: `Vault` with `capacity_for(tab) -> int`, `can_add(tab, list) -> bool`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends SceneTree

# Headless test: Vault's finite, per-tab, expandable capacity (spec §4.2). No Quest tab exists —
# quest items are per-playthrough and never cross the party<->bank boundary.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_vault.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var v: Vault = Vault.new()
	_check(v.capacity_for(&"gear") == 0, "no tab capacity until expanded (got %d)" % v.capacity_for(&"gear"))

	v.tab_capacity[&"gear"] = 10
	_check(v.capacity_for(&"gear") == 10, "capacity reads back after expansion (got %d)" % v.capacity_for(&"gear"))
	_check(v.can_add(&"gear", v.gear), "empty gear list under capacity 10 can add")

	for i: int in range(10):
		v.gear.append(Gear.new())
	_check(not v.can_add(&"gear", v.gear), "gear list at capacity 10 refuses further adds")

	# Expansion (the dual-sink economy) simply raises the number — content/costs are out of scope.
	v.tab_capacity[&"gear"] = 11
	_check(v.can_add(&"gear", v.gear), "expanding the tab immediately allows one more add")

	# Materials/Reel-Mods tabs are independent capacities.
	v.tab_capacity[&"materials"] = 5
	_check(v.capacity_for(&"materials") == 5, "materials tab has its own independent capacity")
	_check(v.capacity_for(&"reel_mods") == 0, "reel_mods tab still unexpanded (got %d)" % v.capacity_for(&"reel_mods"))

	print(("VAULT TEST PASSED" if _failures == 0 else "VAULT TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_vault.gd`
Expected: FAIL — "Identifier 'Vault' not declared" (class doesn't exist yet).

- [ ] **Step 3: Write minimal implementation**

Create `economy/resources/vault.gd`:

```gdscript
class_name Vault
extends Resource

## The account-wide, cross-character bank (spec §4.2) — the ONE thing shared across a player's
## multiple WoW-alt-style PCs. Finite, tab-based, expandable via a dual sink (story/mastery-earned
## early tabs, gold-bought later tabs — costs are content, out of scope this pass). No Quest tab:
## quest items are per-playthrough and never cross the party<->bank boundary.

@export var gear: Array[Gear] = []
@export var reel_mods: Array[Resource] = []
@export var materials: Array[Resource] = []
@export var tab_capacity: Dictionary = {}   # StringName tab name -> int capacity

func capacity_for(tab: StringName) -> int:
	return tab_capacity.get(tab, 0)

func can_add(tab: StringName, list: Array) -> bool:
	return list.size() < capacity_for(tab)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_vault.gd`
Expected: PASS — "VAULT TEST PASSED"

- [ ] **Step 5: Commit**

```bash
git add economy/resources/vault.gd tests/test_vault.gd
git commit -m "feat(economy): add Vault, the finite account-wide cross-character bank"
```

---

## Task 11: Loot generation mechanism (`LootEntry`/`LootTable`)

**Files:**
- Create: `economy/resources/loot_entry.gd`
- Create: `economy/resources/loot_table.gd`
- Modify: `combat/enemy_library.gd` (optional `loot_table` field, no tables authored)
- Test: `tests/test_loot_table.gd`

**Interfaces:**
- Produces: `LootEntry` (`item: Resource`, `drop_chance: float`), `LootTable.roll() -> Array`
  (static, independent per-entry rolls — WoW-style, not a single weighted pick).

- [ ] **Step 1: Write the failing test**

```gdscript
extends SceneTree

# Headless test: LootTable rolls are INDEPENDENT per entry (WoW-style), not a single weighted pick.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_loot_table.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _entry(item: Resource, chance: float) -> LootEntry:
	var e: LootEntry = LootEntry.new()
	e.item = item
	e.drop_chance = chance
	return e

func _initialize() -> void:
	var item_a: Resource = Resource.new()
	var item_b: Resource = Resource.new()

	# Two 100% entries: both always drop together (proves independence, not a single pick).
	var certain: LootTable = LootTable.new()
	certain.entries = [_entry(item_a, 1.0), _entry(item_b, 1.0)]
	var drops: Array = LootTable.roll(certain)
	_check(drops.size() == 2 and item_a in drops and item_b in drops, "two 100%% entries both always drop (got %d)" % drops.size())

	# One 0%, one 100%: exactly the 100% one drops, every time.
	var mixed: LootTable = LootTable.new()
	mixed.entries = [_entry(item_a, 0.0), _entry(item_b, 1.0)]
	for i: int in range(20):
		var d: Array = LootTable.roll(mixed)
		_check(d.size() == 1 and d[0] == item_b, "0%% never drops, 100%% always does (trial %d)" % i)

	# Empty table -> empty drops, no crash.
	var empty: LootTable = LootTable.new()
	_check(LootTable.roll(empty).size() == 0, "empty table -> no drops")

	print(("LOOT TABLE TEST PASSED" if _failures == 0 else "LOOT TABLE TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_loot_table.gd`
Expected: FAIL — "Identifier 'LootEntry' not declared" (classes don't exist yet).

- [ ] **Step 3: Write minimal implementation**

Create `economy/resources/loot_entry.gd`:

```gdscript
class_name LootEntry
extends Resource

## One line of a LootTable: an item and its OWN independent drop chance (spec §4.3).

@export var item: Resource
@export var drop_chance: float = 0.0   # 0.0-1.0, rolled independently of every other entry
```

Create `economy/resources/loot_table.gd`:

```gdscript
class_name LootTable
extends Resource

## WoW-style loot generation: every entry rolls INDEPENDENTLY (spec §4.3) — a kill can drop zero,
## one, or several items, never a single weighted pick. No tables are authored this pass; this
## locks the mechanism only, per the deferred-content direction (loot tables come after more of the
## game's systems exist).

@export var entries: Array[LootEntry] = []

static func roll(table: LootTable) -> Array:
	var drops: Array = []
	for e: LootEntry in table.entries:
		if randf() < e.drop_chance:
			drops.append(e.item)
	return drops
```

Modify `combat/enemy_library.gd` — add one optional field to whatever struct/dictionary
`EnemyLibrary` uses to describe an enemy (defaults to `null`, unused until real content exists):

```gdscript
## Optional loot table (spec §4.3) — null until real items/tables are authored. Hook only.
var loot_table: LootTable = null
```

(If `EnemyLibrary` builds enemies through a single function rather than per-enemy instance fields,
add `loot_table: LootTable = null` as an optional parameter to that builder instead, defaulting to
`null` and otherwise unused this pass — the exact insertion point depends on `EnemyLibrary`'s
current shape; read the file before applying this step to match its actual pattern.)

- [ ] **Step 4: Run test to verify it passes**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_loot_table.gd`
Expected: PASS — "LOOT TABLE TEST PASSED"

- [ ] **Step 5: Run full regression**

Run every existing test file under `tests/` (107+ suites) and confirm all stay green, alongside the
11 new suites added by this plan. This closes out the implementation pass.

- [ ] **Step 6: Commit**

```bash
git add economy/resources/loot_entry.gd economy/resources/loot_table.gd combat/enemy_library.gd tests/test_loot_table.gd
git commit -m "feat(economy): add LootEntry/LootTable independent-roll loot generation mechanism"
```

---

## Self-Review Notes

**Spec coverage:** §3.1-3.3 (Gear/RarityVisuals/ReelAffix) → Tasks 1-2. §3.4 (weapon empowerment)
→ Task 3. §3.5 (equip validation) → Task 4. §5.1-5.4 (stat rework) → Tasks 5-8. §4.1 (PartyInventory)
→ Task 9. §4.2 (Vault) → Task 10. §4.3 (loot mechanism) → Task 11. §6 (multi-character) is
context-only, no code, correctly has no task. §8 (explicitly out of scope) correctly has no tasks.

**Placeholder scan:** no TBD/TODO remain except the single explicitly-flagged conditional note in
Task 11 Step 3 (EnemyLibrary's exact shape needs a read-before-edit since it wasn't fully audited
during planning) — this is a real instruction with a concrete fallback, not an empty placeholder.

**Type consistency:** `RarityVisuals.Rarity` used consistently everywhere (Gear, Weapon, tests) —
never a bare `Rarity` outside `RarityVisuals` itself. `weapon_effective_base_damage()`,
`might_damage_bonus_per_reel()`, `dot_damage_multiplier()`, `luck_extra_lines()`, `can_equip()` are
each defined once (Combatant) and referenced identically at every call site across tasks.
`base_stamina_regen`/`base_mana_regen` are set at exactly 3 call sites (character_class.gd,
enemy_library.gd, combat.gd `_make_combatant`) before their respective `apply_stats()` call, matching
the existing `base_max_hp` seed-then-derive pattern already used by every other stat hook.

**Regression audit performed during planning (not left to chance):** every existing test file
touching `Gear.Slot`, `apply_luck`, `regen_per_turn`/`mana_regen_per_turn`, and `weapon.base_damage`
combat-math call sites was individually read and either confirmed unaffected or given an explicit
fix step above (`test_stats.gd`, `test_character_class.gd`, `test_mana_derivation.gd`,
`test_seer_class.gd`, `test_combat_loop.gd`). The weapon-empowerment formula deliberately uses
`(level - 1)` rather than `level` specifically so every existing combatant (which all default to
level 1) sees zero behavior change from Task 3's 7 call-site rewire.
