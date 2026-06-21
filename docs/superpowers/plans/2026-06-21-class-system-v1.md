# Class System v1 (Warrior / Vanguard / Skirmisher) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a thin `CharacterClass` resource and three playable classes — Warrior, Vanguard, Skirmisher — to the combat prototype, each with its own stats, weapon, the built Sticky-Wild Ultimate, and a distinct thematic Main-1 base ability, selectable in `combat.tscn`.

**Architecture:** A `CharacterClass` (`Resource`) is a data bundle that stamps a `Combatant` via `build_combatant()` (mirrors the existing inline `_make_combatant`). A code-side `ClassLibrary` holds the three v1 classes (consistent with the existing `EffectLibrary` pattern; `CharacterClass` stays a `Resource` so classes can move to `.tres` later). The per-class **base ability** is generalized onto `MainPhasePlan` (today hard-wired to one Storm splice) as an `ability_id` dispatched at `commit()`: `flurry` (splice an own-type reel — reuses `try_splice_reel`), `heft` (edit this turn's reels — new `Combatant.apply_heft`), `rallying_cry` (buff all allies — reuses the built `inspirational` Effect, applied by the orchestrator). `combat.gd` builds the PC from a selected class and relabels/rewires its single ability button.

**Tech Stack:** Godot 4.6.3-stable, GDScript (no C#), `Resource`-based data, headless `SceneTree` tests.

## Global Constraints

- **Engine: Godot 4.6.3-stable. Language: GDScript only — no C#.** (CLAUDE.md §2)
- **Naming:** Classes/Resources `PascalCase`; files `snake_case`; signals `snake_case` past-tense; handlers `_on_<emitter>_<signal>`. (CLAUDE.md §2)
- **All damage/heal math rounds UP (`ceil`).** (project memory; already in `CombatResolver`)
- **Balance numbers are `[ASSUMPTION]` placeholders** — make them editable data, do not hard-balance. (CLAUDE.md §4)
- **Stat→lever mappings (built, flat 1:1):** Might→+dmg/hit, Finesse→+init/tie-break, Vigor→+max HP, Focus→+max Stamina, Grit→+meter floor, Luck→+crit faces (`apply_luck`).
- **Reel band 2–5; abilities are ADDITIVE to the weapon baseline, never overwrite.** (DESIGN §4.3, §4.8)
- **Each Action reel resolves as an independent attack.** (DESIGN §4.5)
- **N-vs-M ready:** never assume 1v1; ally-targeting reads the combatant list. (CLAUDE.md §7)
- **Spec:** `docs/superpowers/specs/2026-06-21-class-system-v1-design.md` (§2 roster, §3 stat spreads, §4A base abilities, §5 weapons).
- **Test runner (from the project root that contains `project.godot`):**
  `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/<file>.gd`
  After adding a NEW `class_name`, refresh the class cache once first or `--script` can't resolve it:
  `Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`

---

## File Structure

**Create:**
- `combat/resources/character_class.gd` — `class_name CharacterClass extends Resource`. The thin class data bundle + `build_combatant()`.
- `combat/class_library.gd` — `class_name ClassLibrary extends RefCounted`. Static factory returning fresh `CharacterClass` instances by id (`&"warrior"`, `&"vanguard"`, `&"skirmisher"`).
- `tests/test_character_class.gd` — `build_combatant()` produces the right derived state.
- `tests/test_class_library.gd` — each v1 class matches the spec (stats, reel count, ability id, defense).
- `tests/test_heft.gd` — `Combatant.apply_heft` edits the per-turn reels only (weapon untouched).
- `tests/test_class_abilities_plan.gd` — `MainPhasePlan` previews/commits each ability id correctly.

**Modify:**
- `combat/combatant.gd` — add `ability_id` field; add `apply_heft(cost)`; add `weapon_type()` helper.
- `combat/main_phase_plan.gd` — generalize the hard-wired splice into a dispatched `ability_id`.
- `combat/combat.gd` — build PC from a `CharacterClass`; add a 3-way class picker; relabel/rewire the ability button per class; apply `rallying_cry` to allies on commit.
- `tests/test_main_phase_plan.gd`, `tests/test_reel_splice.gd` — update for the generalized ability field (Warrior's ability is now an own-type "flurry" splice, not Storm).

> **Naming deviation (flagged):** the class resource is `CharacterClass`, not DESIGN/CLAUDE's `Class`.
> `class` is a GDScript keyword and `Class` as a `class_name` is confusing/risky to reference
> (`var c: Class`). If you prefer the literal `Class`, rename in Task 1 — nothing downstream depends
> on the spelling beyond the import.

---

## Task 1: `CharacterClass` resource + `build_combatant()`

**Files:**
- Create: `combat/resources/character_class.gd`
- Test: `tests/test_character_class.gd`

**Interfaces:**
- Consumes: `Stats`, `Weapon`, `ActionReel`, `DamageType`, `Combatant`, `BonusMeter`, `ResourcePool` (all existing).
- Produces:
  - `class_name CharacterClass extends Resource`
  - exports: `display_name: String`, `species: String`, `base_stats: Stats`, `weapon_base_damage: float`, `weapon_type: DamageType`, `reel_count: int`, `defense_type: DamageType`, `base_max_hp: int`, `base_max_stamina: int`, `base_meter_floor: int`, `meter_cap: int`, `ability_id: StringName`, `start_stamina: int`, `stamina_regen: int`
  - `func build_combatant(is_player: bool) -> Combatant`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_character_class.gd
extends SceneTree

# Headless test: CharacterClass.build_combatant() stamps a Combatant with stat-derived state.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_character_class.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")
	var cc: CharacterClass = CharacterClass.new()
	cc.display_name = "Test Warrior"
	cc.species = "Mouse"
	var s: Stats = Stats.new(); s.might = 3; s.vigor = 3; s.focus = 1; s.grit = 2; s.luck = 1
	cc.base_stats = s
	cc.weapon_base_damage = 8.0
	cc.weapon_type = slashing
	cc.reel_count = 3
	cc.defense_type = slashing
	cc.base_max_hp = 100
	cc.base_max_stamina = 5
	cc.base_meter_floor = 3
	cc.meter_cap = 15
	cc.ability_id = &"flurry"
	cc.start_stamina = 3
	cc.stamina_regen = 1

	var c: Combatant = cc.build_combatant(true)
	_check(c.display_name == "Test Warrior", "display_name copied")
	_check(c.is_player == true, "is_player set")
	_check(c.weapon != null and c.weapon.reels.size() == 3, "weapon has reel_count=3 reels (got %d)" % (c.weapon.reels.size() if c.weapon else -1))
	_check(c.weapon.base_damage == 8.0, "weapon base_damage copied")
	_check(c.defense_type == slashing, "defense_type set")
	_check(c.ability_id == &"flurry", "ability_id set")
	# Derived: max_hp = base 100 + vigor 3 = 103; max_stamina = base 5 + focus 1 = 6; floor = 3 + grit 2 = 5.
	_check(c.max_hp == 103, "max_hp = 100 + vigor 3 = 103 (got %d)" % c.max_hp)
	_check(c.resource_pool != null and c.resource_pool.max_stamina == 6, "max_stamina = 5 + focus 1 = 6 (got %d)" % (c.resource_pool.max_stamina if c.resource_pool else -1))
	_check(c.bonus_meter != null and c.bonus_meter.floor == 5, "meter floor = 3 + grit 2 = 5 (got %d)" % (c.bonus_meter.floor if c.bonus_meter else -1))
	_check(c.bonus_meter.cap == 15, "meter cap copied")
	_check(c.hp == c.max_hp, "start_combat seeded full HP")
	# Luck 1 added 1 crit face per reel.
	var crit: int = 0
	for f: ReelFace in c.weapon.reels[0].faces:
		if f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS: crit += 1
	_check(crit == 2, "apply_luck added 1 crit face (1 default + 1 = 2; got %d)" % crit)

	print(("CHARACTER CLASS TEST PASSED" if _failures == 0 else "CHARACTER CLASS TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_character_class.gd`
Expected: FAIL — `CharacterClass` is an unknown class (parse error / can't resolve). (If it parse-errors before running, that still counts as the expected red.)

- [ ] **Step 3: Write the implementation**

```gdscript
# combat/resources/character_class.gd
class_name CharacterClass
extends Resource

## A thin class definition (DESIGN.md §8 "Class"; spec 2026-06-21). Data bundle that stamps a
## [Combatant]. Resource-based so it can become an inspector-authored .tres later; for v1 the three
## starter classes are built in code by [ClassLibrary]. Balance fields are [ASSUMPTION] placeholders.

@export var display_name: String = ""
@export var species: String = ""

## Innate stats (gear stacks on top at the Combatant level).
@export var base_stats: Stats

## Weapon profile — built into a [Weapon] of [member reel_count] reels of [member weapon_type].
@export var weapon_base_damage: float = 10.0
@export var weapon_type: DamageType
@export_range(2, 5) var reel_count: int = 3

## The type incoming attacks resolve against (this class's defensive type).
@export var defense_type: DamageType

## Pre-stat seeds; live max_hp / max_stamina / meter floor are derived in Combatant.apply_stats().
@export var base_max_hp: int = 100
@export var base_max_stamina: int = 5
@export var base_meter_floor: int = 3
@export var meter_cap: int = 15

## Starting / regenerating Stamina (Main-1 economy).
@export var start_stamina: int = 3
@export var stamina_regen: int = 1

## The class's Main-1 base ability (spec §4A): &"flurry" / &"heft" / &"rallying_cry".
@export var ability_id: StringName = &""

## Stamps a fresh [Combatant] from this class. Mirrors combat.gd's former inline _make_combatant:
## derive stats, edit reels for Luck, seed full HP. [param is_player] toggles meter visibility +
## the Stamina pool (enemies have neither in the prototype).
func build_combatant(is_player: bool) -> Combatant:
	var c: Combatant = Combatant.new()
	c.display_name = display_name
	c.is_player = is_player
	c.defense_type = defense_type
	c.ability_id = ability_id
	c.base_stats = base_stats

	var w: Weapon = Weapon.new()
	w.base_damage = weapon_base_damage
	for i: int in range(reel_count):
		w.reels.append(ActionReel.make_default(weapon_type))
	c.weapon = w

	c.base_max_hp = base_max_hp
	c.base_meter_floor = base_meter_floor
	var meter: BonusMeter = BonusMeter.new()
	meter.cap = meter_cap
	meter.is_visible = is_player
	c.bonus_meter = meter

	if is_player:
		var pool: ResourcePool = ResourcePool.new()
		pool.stamina = start_stamina
		pool.regen_per_turn = stamina_regen
		c.resource_pool = pool
		c.base_max_stamina = base_max_stamina

	c.apply_stats()   # derive max_hp / max_stamina / meter.floor BEFORE seeding hp
	c.apply_luck()    # edit weapon reels: +1 crit face per Luck. ONCE — not idempotent.
	c.start_combat()
	return c
```

Also add the `ability_id` field to `combat/combatant.gd` (consumed above; see Task 3 for its use). Add near the identity block (after `var is_player`):

```gdscript
## The class's Main-1 base ability id (spec §4A). Drives MainPhasePlan dispatch. Empty = none.
var ability_id: StringName = &""
```

- [ ] **Step 4: Refresh the class cache, then run the test to verify it passes**

Run (once, to register the new `class_name`s): `Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`
Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_character_class.gd`
Expected: `CHARACTER CLASS TEST PASSED` and exit 0.

- [ ] **Step 5: Commit**

```bash
git add combat/resources/character_class.gd combat/combatant.gd tests/test_character_class.gd
git commit -m "feat(class): CharacterClass resource + build_combatant"
```

---

## Task 2: `ClassLibrary` — the three v1 classes

**Files:**
- Create: `combat/class_library.gd`
- Test: `tests/test_class_library.gd`

**Interfaces:**
- Consumes: `CharacterClass` (Task 1), `Stats`, the type `.tres` under `res://combat/resources/types/`.
- Produces:
  - `class_name ClassLibrary extends RefCounted`
  - `static func make(id: StringName) -> CharacterClass` — returns a fresh class for `&"warrior"`, `&"vanguard"`, `&"skirmisher"`; `null` otherwise.
  - `const IDS: Array[StringName] = [&"warrior", &"vanguard", &"skirmisher"]`

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_class_library.gd
extends SceneTree

# Headless test: the three v1 classes match the design spec (§2 roster, §3 stats, §4A ability).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_class_library.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var warrior: CharacterClass = ClassLibrary.make(&"warrior")
	_check(warrior != null, "warrior exists")
	_check(warrior.reel_count == 3 and warrior.base_stats.might == 3, "warrior: 3 reels, Might 3")
	_check(warrior.ability_id == &"flurry", "warrior ability = flurry")
	_check(warrior.display_name == "Martin (Mouse)", "warrior is Martin")

	var vanguard: CharacterClass = ClassLibrary.make(&"vanguard")
	_check(vanguard.reel_count == 2 and vanguard.base_stats.vigor == 5, "vanguard: 2 reels, Vigor 5")
	_check(vanguard.ability_id == &"heft", "vanguard ability = heft")
	_check(vanguard.base_stats.grit == 3, "vanguard high Grit 3 (meter carryover)")

	var skirmisher: CharacterClass = ClassLibrary.make(&"skirmisher")
	_check(skirmisher.reel_count == 5 and skirmisher.base_stats.finesse == 5, "skirmisher: 5 reels, Finesse 5")
	_check(skirmisher.ability_id == &"rallying_cry", "skirmisher ability = rallying_cry")

	_check(ClassLibrary.make(&"nope") == null, "unknown id -> null")
	_check(ClassLibrary.IDS.size() == 3, "3 v1 classes registered")

	print(("CLASS LIBRARY TEST PASSED" if _failures == 0 else "CLASS LIBRARY TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_class_library.gd`
Expected: FAIL — `ClassLibrary` unknown.

- [ ] **Step 3: Write the implementation**

```gdscript
# combat/class_library.gd
class_name ClassLibrary
extends RefCounted

## Code registry of the v1 starter classes (spec 2026-06-21 §2/§3/§4A). Mirrors EffectLibrary:
## returns a FRESH CharacterClass each call. Values are [ASSUMPTION] placeholders — tune by playtest.
## (CharacterClass is a Resource, so these can migrate to authored .tres later.)

const IDS: Array[StringName] = [&"warrior", &"vanguard", &"skirmisher"]

static func _stats(mi: int, fi: int, vi: int, fo: int, gr: int, lu: int) -> Stats:
	var s: Stats = Stats.new()
	s.might = mi; s.finesse = fi; s.vigor = vi; s.focus = fo; s.grit = gr; s.luck = lu
	return s

static func make(id: StringName) -> CharacterClass:
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")
	var crushing: DamageType = load("res://combat/resources/types/crushing.tres")
	match id:
		&"warrior":
			var c: CharacterClass = CharacterClass.new()
			c.display_name = "Martin (Mouse)"; c.species = "Mouse"
			c.base_stats = _stats(3, 2, 3, 1, 2, 1)
			c.weapon_base_damage = 8.0; c.weapon_type = slashing; c.reel_count = 3
			c.defense_type = slashing
			c.base_max_hp = 100; c.base_max_stamina = 5; c.base_meter_floor = 3; c.meter_cap = 15
			c.start_stamina = 3; c.stamina_regen = 1
			c.ability_id = &"flurry"
			return c
		&"vanguard":
			var c: CharacterClass = CharacterClass.new()
			c.display_name = "Sunflash (Badger)"; c.species = "Badger"
			c.base_stats = _stats(4, 0, 5, 0, 3, 0)
			c.weapon_base_damage = 15.0; c.weapon_type = crushing; c.reel_count = 2
			c.defense_type = crushing
			c.base_max_hp = 130; c.base_max_stamina = 5; c.base_meter_floor = 3; c.meter_cap = 15
			c.start_stamina = 3; c.stamina_regen = 1
			c.ability_id = &"heft"
			return c
		&"skirmisher":
			var c: CharacterClass = CharacterClass.new()
			c.display_name = "Basil Stag Hare"; c.species = "Hare"
			c.base_stats = _stats(1, 5, 2, 2, 1, 1)
			c.weapon_base_damage = 5.0; c.weapon_type = slashing; c.reel_count = 5
			c.defense_type = slashing
			c.base_max_hp = 90; c.base_max_stamina = 5; c.base_meter_floor = 3; c.meter_cap = 15
			c.start_stamina = 3; c.stamina_regen = 1
			c.ability_id = &"rallying_cry"
			return c
		_:
			return null
```

- [ ] **Step 4: Refresh cache + run the test**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`
Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_class_library.gd`
Expected: `CLASS LIBRARY TEST PASSED`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add combat/class_library.gd tests/test_class_library.gd
git commit -m "feat(class): ClassLibrary with Warrior/Vanguard/Skirmisher v1 configs"
```

---

## Task 3: `Combatant.apply_heft` (the Vanguard reel-edit ability)

**Files:**
- Modify: `combat/combatant.gd` (add `apply_heft` and `weapon_type` near the per-turn reel section)
- Test: `tests/test_heft.gd`

**Interfaces:**
- Consumes: `turn_reels` (set by `begin_turn`), `resource_pool`, `ActionReel`, `ReelFace`.
- Produces:
  - `func weapon_type() -> DamageType` — the weapon's first reel's type (for Flurry's own-type splice).
  - `func apply_heft(cost: int) -> bool` — spends `cost` Stamina; on each `turn_reels` reel, deep-copies it and converts its first FAILURE face to a SUCCESS face (mult 1.0). Returns false (no change) if unaffordable.

> **Critical gotcha:** `begin_turn` does `turn_reels = weapon.reels.duplicate()` — a SHALLOW copy, so
> the `ActionReel` objects (and their `ReelFace`es) are SHARED with the weapon. `apply_heft` must
> deep-duplicate each reel before editing a face, or it permanently mutates the weapon. (Splice is
> unaffected — it only appends new reels.)

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_heft.gd
extends SceneTree

# Headless test: apply_heft converts one FAILURE->SUCCESS per turn-reel, spends Stamina, and does
# NOT mutate the underlying weapon reels (deep-copy guard).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_heft.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _count(reel: ActionReel, tier: ReelFace.ResultTier) -> int:
	var n: int = 0
	for f: ReelFace in reel.faces:
		if f.result_tier == tier: n += 1
	return n

func _initialize() -> void:
	var crushing: DamageType = load("res://combat/resources/types/crushing.tres")
	var c: Combatant = Combatant.new()
	var w: Weapon = Weapon.new(); w.base_damage = 15.0
	w.reels.append(ActionReel.make_default(crushing))
	w.reels.append(ActionReel.make_default(crushing))
	c.weapon = w
	c.resource_pool = ResourcePool.new(); c.resource_pool.stamina = 3; c.resource_pool.max_stamina = 5

	var fail_before: int = _count(w.reels[0], ReelFace.ResultTier.FAILURE)
	var succ_before: int = _count(w.reels[0], ReelFace.ResultTier.SUCCESS)

	c.begin_turn()
	var ok: bool = c.apply_heft(2)
	_check(ok, "apply_heft succeeded with 3 stamina")
	_check(c.resource_pool.stamina == 1, "spent 2 stamina -> 1 left (got %d)" % c.resource_pool.stamina)
	_check(_count(c.turn_reels[0], ReelFace.ResultTier.FAILURE) == fail_before - 1, "turn reel 0: one fewer FAILURE")
	_check(_count(c.turn_reels[0], ReelFace.ResultTier.SUCCESS) == succ_before + 1, "turn reel 0: one more SUCCESS")
	_check(_count(c.turn_reels[1], ReelFace.ResultTier.SUCCESS) == succ_before + 1, "turn reel 1 also hefted")
	# Weapon untouched (deep-copy guard).
	_check(_count(w.reels[0], ReelFace.ResultTier.FAILURE) == fail_before, "WEAPON reel 0 FAILURE unchanged (got %d, want %d)" % [_count(w.reels[0], ReelFace.ResultTier.FAILURE), fail_before])

	# Unaffordable -> no change.
	var d: Combatant = Combatant.new()
	d.weapon = w
	d.resource_pool = ResourcePool.new(); d.resource_pool.stamina = 1
	d.begin_turn()
	_check(d.apply_heft(2) == false, "apply_heft fails with 1 stamina")
	_check(d.resource_pool.stamina == 1, "no stamina spent on failed heft")

	print(("HEFT TEST PASSED" if _failures == 0 else "HEFT TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_heft.gd`
Expected: FAIL — `apply_heft` not found (or returns nothing).

- [ ] **Step 3: Write the implementation**

In `combat/combatant.gd`, add to the "Per-turn reel loadout" section (after `try_splice_reel`):

```gdscript
## The weapon's own damage type (its first reel's type), or null. Used by the Warrior's Flurry to
## splice an own-type extra reel.
func weapon_type() -> DamageType:
	if weapon != null and not weapon.reels.is_empty():
		return weapon.reels[0].damage_type
	return null

## Vanguard "Heft" (spec §4A): spends [param cost] Stamina and, on each reel of THIS turn, converts
## its first FAILURE face into a SUCCESS face (mult 1.0) — fewer whiffs from the heavy hits. Edits a
## DEEP copy of each reel so the underlying weapon is never mutated (begin_turn's duplicate is shallow).
## Returns false and changes nothing if unaffordable.
func apply_heft(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	for i: int in range(turn_reels.size()):
		var reel: ActionReel = turn_reels[i].duplicate(true)  # deep: own faces
		for face: ReelFace in reel.faces:
			if face.result_tier == ReelFace.ResultTier.FAILURE:
				face.result_tier = ReelFace.ResultTier.SUCCESS
				face.multiplier = 1.0
				break
		turn_reels[i] = reel
	return true
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_heft.gd`
Expected: `HEFT TEST PASSED`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add combat/combatant.gd tests/test_heft.gd
git commit -m "feat(class): Combatant.apply_heft (Vanguard reel-edit) + weapon_type helper"
```

---

## Task 4: Generalize `MainPhasePlan` to dispatch a per-class ability

**Files:**
- Modify: `combat/main_phase_plan.gd`
- Modify: `tests/test_main_phase_plan.gd`, `tests/test_reel_splice.gd` (update for the generalized field)
- Test: `tests/test_class_abilities_plan.gd`

**Interfaces:**
- Consumes: `Combatant` (`ability_id`, `try_splice_reel`, `apply_heft`, `weapon_type`, `fire_sticky_wild`), `DamageType`.
- Produces (new `MainPhasePlan` shape):
  - `_init(c, p_ability_cost := 2, p_reel_cap := 5, p_wild_spins := 2)` — no more `splice_type`/`wild_reel`; the ability comes from `c.ability_id`, the splice type from `c.weapon_type()`.
  - `ability_id: StringName` (mirrors `combatant.ability_id`), `ability_staged: bool`, `fire_ultimate_staged: bool`.
  - `can_stage_ability() -> bool`, `toggle_ability()`, `preview_reels()`, `preview_stamina()`, `will_consume_meter()`, `effective_wild_indices()`, `commit()`.
  - `committed_rally: bool` — set true by `commit()` when a `rallying_cry` was committed, so the orchestrator applies the ally buff.
  - `ADDS_REEL := {&"flurry": true}` semantics via `_ability_changes_reels()`.

> **Why:** today the plan hard-codes one Storm splice. Each class now has its own ability
> (`flurry`/`heft`/`rallying_cry`). The plan reads `combatant.ability_id` and dispatches at commit.
> `flurry` and `heft` change the attacker's own reels (previewable); `rallying_cry` changes allies
> (not previewable in reels — orchestrator applies it), so `commit()` flags `committed_rally`.

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_class_abilities_plan.gd
extends SceneTree

# Headless test: MainPhasePlan previews/commits each base ability by the combatant's ability_id.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_class_abilities_plan.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _pc(ability: StringName, reel_count: int, type: DamageType) -> Combatant:
	var c: Combatant = Combatant.new()
	c.ability_id = ability
	var w: Weapon = Weapon.new(); w.base_damage = 10.0
	for i: int in range(reel_count): w.reels.append(ActionReel.make_default(type))
	c.weapon = w
	c.resource_pool = ResourcePool.new(); c.resource_pool.stamina = 3; c.resource_pool.max_stamina = 5
	c.begin_turn()
	return c

func _initialize() -> void:
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")
	var crushing: DamageType = load("res://combat/resources/types/crushing.tres")

	# FLURRY: previews +1 own-type reel; commit appends it and spends stamina.
	var w: Combatant = _pc(&"flurry", 3, slashing)
	var pf: MainPhasePlan = MainPhasePlan.new(w, 2, 5, 2)
	pf.toggle_ability()
	_check(pf.preview_reels().size() == 4, "flurry preview: 3 -> 4 reels (got %d)" % pf.preview_reels().size())
	_check(pf.preview_reels()[3].damage_type == slashing, "flurry splice is own (Slashing) type")
	pf.commit()
	_check(w.turn_reels.size() == 4 and w.resource_pool.stamina == 1, "flurry commit: 4 reels, 2 STA spent")

	# HEFT: preview reels unchanged in COUNT but show one more SUCCESS after commit.
	var v: Combatant = _pc(&"heft", 2, crushing)
	var ph: MainPhasePlan = MainPhasePlan.new(v, 2, 5, 2)
	ph.toggle_ability()
	_check(ph.preview_reels().size() == 2, "heft preview keeps 2 reels")
	ph.commit()
	_check(v.resource_pool.stamina == 1, "heft commit spent 2 STA")
	var has_no_fail_first := true  # at least one reel got a FAILURE->SUCCESS swap; smoke check count
	_check(v.turn_reels.size() == 2, "heft commit keeps 2 reels")

	# RALLYING CRY: no reel change; commit flags committed_rally for the orchestrator.
	var s: Combatant = _pc(&"rallying_cry", 5, slashing)
	var pr: MainPhasePlan = MainPhasePlan.new(s, 2, 5, 2)
	pr.toggle_ability()
	_check(pr.preview_reels().size() == 5, "rally preview keeps 5 reels")
	pr.commit()
	_check(pr.committed_rally == true, "rally commit flags committed_rally")
	_check(s.resource_pool.stamina == 1, "rally commit spent 2 STA")

	print(("CLASS ABILITIES PLAN TEST PASSED" if _failures == 0 else "CLASS ABILITIES PLAN TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_class_abilities_plan.gd`
Expected: FAIL — `MainPhasePlan.new` arity / `toggle_ability` / `committed_rally` don't exist yet.

- [ ] **Step 3: Rewrite `combat/main_phase_plan.gd`**

```gdscript
class_name MainPhasePlan
extends RefCounted

## The staged, not-yet-committed Main-Phase-1 choices for one combatant's turn
## (spec 2026-06-19-main1-staging; generalized 2026-06-21 for per-class base abilities, spec §4A).
## Toggling only updates a PREVIEW — nothing is spent/applied until [method commit] on SPIN.
## The base ability is read from [member Combatant.ability_id]: flurry (own-type splice) / heft
## (reel-edit) / rallying_cry (ally buff — orchestrator applies it; see [member committed_rally]).

var combatant: Combatant
var ability_id: StringName
var ability_cost: int
var reel_cap: int
var wild_spins: int

var ability_staged: bool = false
var fire_ultimate_staged: bool = false

## Set true by [method commit] when a rallying_cry was committed, so the orchestrator buffs allies.
var committed_rally: bool = false

func _init(c: Combatant, p_ability_cost: int = 2, p_reel_cap: int = 5, p_wild_spins: int = 2) -> void:
	combatant = c
	ability_id = c.ability_id if c != null else &""
	ability_cost = p_ability_cost
	reel_cap = p_reel_cap
	wild_spins = p_wild_spins

## Whether this ability adds/edits the attacker's own reels (previewable in the strips).
func _ability_adds_reel() -> bool:
	return ability_id == &"flurry"

## True if the ability can be newly STAGED: affordable, and (for reel-adding abilities) under the cap.
func can_stage_ability() -> bool:
	if combatant == null or combatant.resource_pool == null or ability_id == &"":
		return false
	if not combatant.resource_pool.can_afford({&"stamina": ability_cost}):
		return false
	if _ability_adds_reel() and combatant.turn_reels.size() >= reel_cap:
		return false
	return true

func can_stage_ultimate() -> bool:
	return combatant != null and combatant.bonus_meter != null and combatant.bonus_meter.is_armed()

func toggle_ability() -> void:
	if ability_staged:
		ability_staged = false
	elif can_stage_ability():
		ability_staged = true

func toggle_ultimate() -> void:
	if fire_ultimate_staged:
		fire_ultimate_staged = false
	elif can_stage_ultimate():
		fire_ultimate_staged = true

## The reels the spin WOULD use. Flurry adds a previewed own-type reel; heft/rally don't change the
## COUNT here (heft's face edits are applied on commit — the count preview is what the strips show).
func preview_reels() -> Array[ActionReel]:
	var reels: Array[ActionReel] = combatant.turn_reels.duplicate()
	if ability_staged and _ability_adds_reel() and reels.size() < reel_cap:
		reels.append(ActionReel.make_default(combatant.weapon_type()))
	return reels

func preview_stamina() -> int:
	if combatant == null or combatant.resource_pool == null:
		return 0
	var s: int = combatant.resource_pool.stamina
	return (s - ability_cost) if ability_staged else s

func will_consume_meter() -> bool:
	return fire_ultimate_staged

func effective_wild_indices() -> Array[int]:
	var out: Array[int] = combatant.wild_reel_indices().duplicate()
	if fire_ultimate_staged:
		for i: int in range(_weapon_reel_count()):
			if not (i in out):
				out.append(i)
		out.sort()
	return out

func _weapon_reel_count() -> int:
	if combatant == null or combatant.weapon == null:
		return 0
	return combatant.weapon.reels.size()

## Applies staged choices via committed Combatant methods. Called once, on SPIN.
func commit() -> void:
	if ability_staged:
		match ability_id:
			&"flurry":
				combatant.try_splice_reel(combatant.weapon_type(), combatant.weapon.base_damage, ability_cost, reel_cap)
			&"heft":
				combatant.apply_heft(ability_cost)
			&"rallying_cry":
				if combatant.resource_pool != null and combatant.resource_pool.spend({&"stamina": ability_cost}):
					committed_rally = true
	if fire_ultimate_staged:
		combatant.fire_sticky_wild(_weapon_reel_count(), wild_spins)
```

- [ ] **Step 4: Update the two existing tests for the new shape**

In `tests/test_main_phase_plan.gd` and `tests/test_reel_splice.gd`, replace any `MainPhasePlan.new(c, storm_type, 2, 5, 0, 2)` with `MainPhasePlan.new(c, 2, 5, 2)`, set the combatant's `ability_id = &"flurry"` before constructing the plan, and rename `splice_staged`/`toggle_splice`/`can_stage_splice` references to `ability_staged`/`toggle_ability`/`can_stage_ability`. (Open each file, apply the renames, keep every assertion otherwise identical.)

- [ ] **Step 5: Run all four affected suites to verify they pass**

Run each:
```
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_class_abilities_plan.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_main_phase_plan.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_reel_splice.gd
```
Expected: each prints `… TEST PASSED`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add combat/main_phase_plan.gd tests/test_class_abilities_plan.gd tests/test_main_phase_plan.gd tests/test_reel_splice.gd
git commit -m "feat(class): generalize MainPhasePlan to dispatch per-class base ability"
```

---

## Task 5: Wire classes + a class picker into `combat.gd`

**Files:**
- Modify: `combat/combat.gd`

**Interfaces:**
- Consumes: `ClassLibrary` (Task 2), `CharacterClass.build_combatant` (Task 1), generalized `MainPhasePlan` (Task 4), `EffectLibrary.make(&"inspirational")` + `_allies_of` (existing).
- Produces: a playable scene where the PC is any of the three classes, its ability button reflects the class, and `rallying_cry` buffs allies on commit.

> This task is scene wiring; it is verified by a headless **scene-load** (no script errors) plus the
> human play-test (CLAUDE.md §5 — the fun call). No new unit test asserts "feel."

- [ ] **Step 1: Replace the hard-coded PC build with a class-driven build**

In `_build_scenario`, delete the inline `jerkin`/`_pc = _make_combatant(...)` block and build from the selected class. Add a member `var _pc_class_id: StringName = &"warrior"` at the top, and:

```gdscript
	# Player: built from the selected CharacterClass (default Warrior). Gear is deferred to a later pass.
	_pc = ClassLibrary.make(_pc_class_id).build_combatant(true)
	# Enemy unchanged: Crushing weapon (2 reels), defends as Earth.
	_enemy = _make_combatant("Cluny's Rat", false, 100, earth, _make_weapon(8.0, crushing, 2), false, Stats.new(), [])
```

Keep `_make_combatant` / `_make_weapon` for the enemy. (The PC no longer uses them.)

- [ ] **Step 2: Update the `MainPhasePlan` construction + ability button to be class-driven**

In `_on_turn_started`, replace the plan construction with the new arity:

```gdscript
	_plan = MainPhasePlan.new(c, 2, 5, 2)  # ability cost 2, reel cap 5, Ultimate 2 spins
```

Set the ability button's label from the attacker's ability id. Add a helper and call it where the buttons are set up (e.g. start of `_on_turn_started` for the player, and in `_refresh_main1_preview`):

```gdscript
func _ability_label(id: StringName) -> String:
	match id:
		&"flurry": return "Flurry: +1 Slashing reel (2 STA)"
		&"heft": return "Heft: steady the reels (2 STA)"
		&"rallying_cry": return "Rallying Cry: allies +5 init (2 STA)"
		_: return "Ability"
```

Rename `_splice_button` usages to drive this generic ability button: set `_splice_button.text = _ability_label(c.ability_id)` when the player's turn starts. (Keep the variable name `_splice_button` or rename to `_ability_button` consistently — rename is cleaner; do it across the file.)

- [ ] **Step 3: Rewire the ability button + preview to the generalized plan**

Replace `_on_splice_pressed` with `_on_ability_pressed` calling `_plan.toggle_ability()` then `_refresh_main1_preview()`. In `_refresh_main1_preview`, replace `_plan.splice_staged`/`can_stage_splice` with `ability_staged`/`can_stage_ability`. The Ultimate button wiring is unchanged.

- [ ] **Step 4: Apply `rallying_cry` to allies after commit**

In `_on_spin_pressed`, right after `_plan.commit()`, apply the ally buff if a rally committed:

```gdscript
		if _plan.committed_rally:
			for ally: Combatant in _allies_of(_attacker):
				var insp: Effect = EffectLibrary.make(&"inspirational")
				if ally == _attacker:
					insp.duration += 1  # caster's own End ticks once this turn — keep 2 fresh turns
				ally.attach_effect(insp)
				(_panels[ally] as CombatantPanel).refresh_status()
				(_panels[ally] as CombatantPanel).refresh_initiative()
			_log("  ✦ Rallying Cry! Allies +5 initiative.")
			_turn_order_bar.set_order(_turn_manager.get_turn_order())
```

(The enemy AI does not use a base ability in v1 — only the player's class drives `_plan`. The enemy's `_plan` is still constructed but it never toggles an ability, matching today's behavior.)

- [ ] **Step 5: Add a 3-button class picker on the result overlay (so each class is play-testable)**

In `_build_overlay`, under the "Fight again" button, add three small buttons that set `_pc_class_id` and reload:

```gdscript
	const PICK_SIZE := Vector2(120, 36)
	var ids: Array[StringName] = ClassLibrary.IDS
	for i: int in range(ids.size()):
		var id: StringName = ids[i]
		var b := Button.new()
		b.text = String(id).capitalize()
		b.position = Vector2(20 + i * 132, 156)
		b.custom_minimum_size = PICK_SIZE
		b.pressed.connect(func() -> void:
			_pc_class_id = id
			get_tree().reload_current_scene())
		_overlay.add_child(b)
```

Also surface the current class at combat start: in `_start_combat`, `_log("Playing as: %s" % _pc.display_name)`. (For a first play-through before any victory/defeat, the default Warrior loads; the picker appears on the end card to switch and replay. If you'd rather pick BEFORE the first fight, that's a flagged fast-follow — a pre-combat menu.)

- [ ] **Step 6: Verify the scene loads headless with no script errors**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --quit-after 3 res://combat/combat.tscn`
Expected: the scene instantiates and the process exits cleanly with **no** `SCRIPT ERROR` / parse errors in output. (Combat won't fully play headless without input — we're checking for load/parse errors only.)

- [ ] **Step 7: Run the FULL test suite to confirm no regressions**

Run each suite listed in `HANDOFF.md §5` plus the four new ones. Expected: every suite prints `… TEST PASSED` and exits 0. Any red → fix before commit.

- [ ] **Step 8: Commit**

```bash
git add combat/combat.gd
git commit -m "feat(class): build PC from CharacterClass + class picker + per-class ability button"
```

---

## Task 6: Docs — update HANDOFF / DECISIONS-LOG / CLAUDE status

**Files:**
- Modify: `HANDOFF.md`, `docs/superpowers/DECISIONS-LOG.md`, `CLAUDE.md` §8 status

- [ ] **Step 1: Record the new systems**

- `HANDOFF.md §2/§6`: note the `CharacterClass`/`ClassLibrary` layer, the 3 playable classes, the per-class base abilities, and the class picker; move "design classes" from the open list to done (for the first 3).
- `DECISIONS-LOG.md`: a dated entry for the `[ASSUMPTION]` stat spreads, weapon base-damage values, ability cost (2 STA), `CharacterClass` vs `Class` naming deviation, and "all 3 launch with Sticky-Wild placeholder Ultimate."
- `CLAUDE.md §8`: add the class system + the 4 new test suites to the "Done" list and update the test count.

- [ ] **Step 2: Commit**

```bash
git add HANDOFF.md docs/superpowers/DECISIONS-LOG.md CLAUDE.md
git commit -m "docs: record class system v1 (3 classes + base abilities + picker)"
```

---

## Self-Review (completed during authoring)

- **Spec coverage:** §1 thin resource → Task 1; §2 roster (3 classes) → Task 2; §3 stat spreads →
  Task 2 data + Task 1 derivation test; §4A base abilities → Task 3 (heft), Task 4 (dispatch),
  Task 5 (flurry/rally wiring); §5 weapons (the 3 picks: One-Handed Sword 3 / Great Maul 2 / Sabre 5)
  → Task 2 weapon fields; §6 "test like Martin" → headless suites (Tasks 1–4) + scene play-test
  (Task 5). Deferred-by-design (other 4 classes, 6 new Ultimate archetypes, weapon riders, gear) are
  out of this plan's scope per §9 locks.
- **Placeholder scan:** no TBD/TODO; every code step shows full code; balance numbers are explicit
  `[ASSUMPTION]` values in `ClassLibrary`.
- **Type consistency:** `ability_id` is `StringName` everywhere; `MainPhasePlan.new(c, cost, cap, spins)`
  arity is consistent across Tasks 4 & 5; `apply_heft(cost)`, `weapon_type()`, `committed_rally`,
  `build_combatant(is_player)` signatures match between definition and call sites.

---

## Open seams handed to the executor (decide inline, don't block)

1. **Martin's HP/weapon:** plan sets Warrior to 100 base HP + an 8-base 3-reel Slashing sword (keeps
   the demo near today's feel). The old demo used a 10-base sword + a Jerkin granting +3 Might/+2
   Finesse/+1 Luck; v1 folds rough equivalents into innate stats and drops gear (deferred). Feel may
   differ slightly — expected, it's the human's tuning call post-build.
2. **Enemy stays Crushing/Earth** (unchanged) so the existing type-chart demo and Slow rider keep
   working while we eyeball the new classes.
3. **Class picker placement** (end-card vs pre-combat menu): plan ships the end-card picker (cheapest);
   a pre-combat menu is a flagged fast-follow.
