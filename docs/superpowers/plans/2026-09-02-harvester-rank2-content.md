# Harvester Rank-2 Content Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Author and wire the rank-2 (level 5-8), passive-amplified (level 9), and Ultimate
rank-2 (level 10) numbers for all four Harvester minions, the Harvest's Favor passive, and the
Grand Sacrifice Ultimate — plus a new Mutual Exhaustion Nightshade talent — using the
already-shipped `Combatant.ability_talent_row_rank()` / `Combatant.ability_magnitude_multiplier()`
infrastructure, which no ability currently consumes.

**Architecture:** Each minion's stage function and the Ultimate's variant dispatcher already
receive the casting `Combatant` as a parameter. Every task adds a rank-2 constant (or constant
set) alongside the existing rank-1 constant, reads `caster.ability_talent_row_rank(<row_id>)` to
pick which one applies, then multiplies the selected magnitude by
`caster.ability_magnitude_multiplier()` before use — this applies at EVERY rank, not just rank 2
(see Global Constraints). No new systems; this is pure content-authoring + call-site wiring on
top of shipped infrastructure.

**Tech Stack:** Godot 4.6.3, GDScript, headless SceneTree test scripts (no test framework/GUT).

**Spec:** `docs/superpowers/specs/2026-09-02-harvester-rank2-content-design.md`

## Global Constraints

- Engine: Godot 4.6+ (built/tested on 4.6.3-stable). GDScript only — never C#.
- Prefer static typing (typed vars, typed signatures) throughout.
- All combat damage/healing math rounds UP (`ceili()`/`ceil()`), never down or nearest.
- Stat scaling (`ability_magnitude_multiplier()`) applies at EVERY rank, including rank 1 — it is
  a separate, always-on axis from rank-up, not something that switches on only at rank 2+.
- Every hand-authored magnitude in this plan is `[ASSUMPTION]` per CLAUDE.md §4 — tune by
  playtest later; do not second-guess the exact numbers during implementation, they were agreed
  with the player during brainstorming.
- Player-facing minion names are Touch-Me-Not / Lotus / Nightshade / Wheat. `ember`/`dew`/
  `misfortune`/`hasty` are internal `minion_type`/row-content identifiers only — keep using them
  in code (matches existing convention), but comments/log lines should read naturally either way,
  matching the existing style already in the touched functions.
- Run any single test file with:
  `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_<name>.gd`
  (the Godot executable lives one directory above this repo, at
  `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe`).
- Grep actual output for `SCRIPT ERROR`/`FAIL`, not just the process exit code — a thrown error
  mid-`_process()`/`_init()` can kill the rest of a frame's checks while the process still exits 0.

---

### Task 1: Touch-Me-Not (Ember) rank-2 stage damage + stat scaling

**Files:**
- Modify: `combat/combat.gd:893` (constants), `combat/combat.gd:902-903` (`_run_ember_stage`)
- Test: Create `tests/test_ember_minion_rank2.gd`

**Interfaces:**
- Consumes: `Combatant.ability_talent_row_rank(row_id: StringName) -> int` (existing, row id
  `&"base_ability"` for this minion per the spec's §0 mapping), `Combatant.
  ability_magnitude_multiplier() -> float` (existing).
- Produces: nothing new consumed by later tasks — this is a self-contained content change.

- [ ] **Step 1: Write the failing test**

Create `tests/test_ember_minion_rank2.gd`:

```gdscript
extends SceneTree

# Headless test: Touch-Me-Not (Ember) minion rank-2 stage damage + stat scaling
# (2026-09-02 harvester-rank2-content spec §2.1). Verifies rank-1 values are unchanged
# (regression) and rank-2 values + ability_magnitude_multiplier() apply once level >= 5
# (base_ability's rank-2 threshold, per ability_talent_row_unlock_level()).
#
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ember_minion_rank2.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

## Builds a real Combat instance via CombatHandoff (mirrors every existing minion test file's
## harness, e.g. tests/test_dew_minion.gd's _new_summoner_encounter) with a Summoner PC at
## [param level] and one rat enemy. Returns [inst, pc, enemy]. Doesn't drive to any particular
## turn/spin window — direct stage-function calls below don't need one.
func _build_encounter(level: int) -> Array:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()
	var pc: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	pc.level = level
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	CombatHandoff.begin_encounter(pc, [], inv, vault, [&"rat"], &"EmberRank2Test", "res://world/overworld_demo.tscn", Vector2.ZERO)
	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame
	inst.roll_initiative_for_test()
	var enemy: Combatant = inst._enemies[0]
	return [inst, pc, enemy]

func _cleanup(inst: Combat) -> void:
	inst.queue_free()
	await process_frame
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

## Case 1: level 4 (below base_ability's rank-2 threshold of 5) -> rank-1 stage damage unchanged.
func _run_rank1_regression() -> void:
	var setup: Array = await _build_encounter(4)
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	var enemy: Combatant = setup[2]
	pc.base_stats.focus = 0
	var minion: Combatant = MinionLibrary.make(false, &"ember")
	inst._turn_manager.combatants.append(minion)

	for stage: int in [1, 2, 3]:
		var hp_before: int = enemy.hp
		inst._run_ember_stage(minion, stage, pc)
		var expected: int = Combat.MINION_BASE_STAGE_DAMAGE * stage
		_check(enemy.hp == hp_before - expected, "level 4 stage %d: rank-1 damage %d unchanged (hp %d -> %d)" % [stage, expected, hp_before, enemy.hp])

	await _cleanup(inst)

## Case 2: level 5+ (base_ability rank 2) -> rank-2 per-stage constants apply. Focus zeroed so this
## case isolates rank-up from stat scaling (checked separately in case 3).
func _run_rank2_values() -> void:
	var setup: Array = await _build_encounter(5)
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	var enemy: Combatant = setup[2]
	pc.base_stats.focus = 0
	var minion: Combatant = MinionLibrary.make(false, &"ember")
	inst._turn_manager.combatants.append(minion)

	var expected_rank2: Array[int] = [12, 22, 32]
	for i: int in range(3):
		var stage: int = i + 1
		var hp_before: int = enemy.hp
		inst._run_ember_stage(minion, stage, pc)
		_check(enemy.hp == hp_before - expected_rank2[i], "level 5 stage %d: rank-2 damage %d applied (hp %d -> %d)" % [stage, expected_rank2[i], hp_before, enemy.hp])

	await _cleanup(inst)

## Case 3: rank-2 damage additionally scales with Focus via ability_magnitude_multiplier() —
## Focus 4 -> StatScaling.multiplier(4) == 1.5 (matches tests/test_stat_scaling.gd's own fixture).
func _run_rank2_stat_scaling() -> void:
	var setup: Array = await _build_encounter(5)
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	var enemy: Combatant = setup[2]
	pc.base_stats.focus = 4
	_check(is_equal_approx(pc.ability_magnitude_multiplier(), 1.5), "sanity: Focus 4 -> ability_magnitude_multiplier() 1.5 (got %f)" % pc.ability_magnitude_multiplier())
	var minion: Combatant = MinionLibrary.make(false, &"ember")
	inst._turn_manager.combatants.append(minion)

	var hp_before: int = enemy.hp
	inst._run_ember_stage(minion, 1, pc)
	var expected: int = ceili(12 * 1.5)
	_check(enemy.hp == hp_before - expected, "level 5, Focus 4, stage 1: rank-2 damage (12) scaled by 1.5 -> %d (hp %d -> %d)" % [expected, hp_before, enemy.hp])

	await _cleanup(inst)

func _initialize() -> void:
	await _run_rank1_regression()
	await _run_rank2_values()
	await _run_rank2_stat_scaling()
	print(("EMBER MINION RANK-2 TEST PASSED" if _failures == 0 else "EMBER MINION RANK-2 TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ember_minion_rank2.gd`
Expected: FAIL on case 2/3 — rank-2 damage doesn't exist yet, stage damage is still the flat
`MINION_BASE_STAGE_DAMAGE * stage` for every level.

- [ ] **Step 3: Implement rank-2 constants + rank-aware, stat-scaled stage damage**

In `combat/combat.gd`, right after the existing `const MINION_BASE_STAGE_DAMAGE: int = 8` (line 893):

```gdscript
## Rank-2 (level 5+) per-stage damage (2026-09-02 harvester-rank2-content spec §2.1) — not a clean
## per-stage multiple of one scalar (12/22/32 isn't N * stage for any integer N), so an explicit
## per-stage array unlike rank 1's `MINION_BASE_STAGE_DAMAGE * stage`.
const MINION_EMBER_STAGE_DAMAGE_RANK2: Array[int] = [12, 22, 32]
```

Then replace the first line of `_run_ember_stage()` (`var amount: int = MINION_BASE_STAGE_DAMAGE * stage`):

```gdscript
func _run_ember_stage(minion: Combatant, stage: int, caster: Combatant = null) -> void:
	var rank: int = caster.ability_talent_row_rank(&"base_ability") if caster != null else 1
	var base_amount: int = MINION_EMBER_STAGE_DAMAGE_RANK2[stage - 1] if rank >= 2 else MINION_BASE_STAGE_DAMAGE * stage
	var stat_mult: float = caster.ability_magnitude_multiplier() if caster != null else 1.0
	var amount: int = ceili(base_amount * stat_mult)
	var overripe: bool = caster != null and caster.has_ability_talent(&"ember_overripe")
```

(The rest of the function — `overgrown_roots`, `delayed_bloom`, the enemy loop, splash, and the
log line — is unchanged; they all already reference `amount`.)

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ember_minion_rank2.gd`
Expected: `EMBER MINION RANK-2 TEST PASSED`

- [ ] **Step 5: Commit**

```bash
git add combat/combat.gd tests/test_ember_minion_rank2.gd
git commit -m "feat(harvester): Touch-Me-Not rank-2 stage damage + stat scaling"
```

---

### Task 2: Lotus (Dew) rank-2 heal values + stat scaling

**Files:**
- Modify: `combat/combat.gd:933-935` (constants), `combat/combat.gd:957` (`_run_dew_stage`)
- Test: Create `tests/test_dew_minion_rank2.gd`

**Interfaces:**
- Consumes: same two `Combatant` methods as Task 1, row id `&"ability_l2"`.
- Produces: nothing new for later tasks.

- [ ] **Step 1: Write the failing test**

Create `tests/test_dew_minion_rank2.gd`:

```gdscript
extends SceneTree

# Headless test: Lotus (Dew) minion rank-2 heal values + stat scaling
# (2026-09-02 harvester-rank2-content spec §2.2).
#
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dew_minion_rank2.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _build_encounter(level: int) -> Array:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()
	var pc: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	pc.level = level
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	CombatHandoff.begin_encounter(pc, [], inv, vault, [&"rat"], &"DewRank2Test", "res://world/overworld_demo.tscn", Vector2.ZERO)
	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame
	inst.roll_initiative_for_test()
	var enemy: Combatant = inst._enemies[0]
	return [inst, pc, enemy]

func _cleanup(inst: Combat) -> void:
	inst.queue_free()
	await process_frame
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

## Case 1: level 5 (below ability_l2's rank-2 threshold of 6) -> rank-1 heals unchanged.
func _run_rank1_regression() -> void:
	var setup: Array = await _build_encounter(5)
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	pc.base_stats.focus = 0
	var minion: Combatant = MinionLibrary.make(false, &"dew")
	inst._turn_manager.combatants.append(minion)

	var expected_rank1: Array[int] = [8, 12, 16]
	for i: int in range(3):
		var stage: int = i + 1
		pc.take_damage(30)
		var hp_before: int = pc.hp
		inst._run_dew_stage(minion, stage, pc)
		_check(pc.hp == mini(hp_before + expected_rank1[i], pc.max_hp), "level 5 stage %d: rank-1 heal %d unchanged (hp %d -> %d)" % [stage, expected_rank1[i], hp_before, pc.hp])

	await _cleanup(inst)

## Case 2: level 6+ (ability_l2 rank 2) -> rank-2 per-stage heals apply (Focus zeroed to isolate
## rank-up from stat scaling, checked separately in case 3).
func _run_rank2_values() -> void:
	var setup: Array = await _build_encounter(6)
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	pc.base_stats.focus = 0
	var minion: Combatant = MinionLibrary.make(false, &"dew")
	inst._turn_manager.combatants.append(minion)

	var expected_rank2: Array[int] = [12, 18, 24]
	for i: int in range(3):
		var stage: int = i + 1
		pc.take_damage(30)
		var hp_before: int = pc.hp
		inst._run_dew_stage(minion, stage, pc)
		_check(pc.hp == mini(hp_before + expected_rank2[i], pc.max_hp), "level 6 stage %d: rank-2 heal %d applied (hp %d -> %d)" % [stage, expected_rank2[i], hp_before, pc.hp])

	await _cleanup(inst)

## Case 3: rank-2 heal additionally scales with Focus via ability_magnitude_multiplier().
func _run_rank2_stat_scaling() -> void:
	var setup: Array = await _build_encounter(6)
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	pc.base_stats.focus = 4
	var minion: Combatant = MinionLibrary.make(false, &"dew")
	inst._turn_manager.combatants.append(minion)

	pc.take_damage(30)
	var hp_before: int = pc.hp
	inst._run_dew_stage(minion, 1, pc)
	var expected: int = ceili(12 * 1.5)
	_check(pc.hp == mini(hp_before + expected, pc.max_hp), "level 6, Focus 4, stage 1: rank-2 heal (12) scaled by 1.5 -> %d (hp %d -> %d)" % [expected, hp_before, pc.hp])

	await _cleanup(inst)

func _initialize() -> void:
	await _run_rank1_regression()
	await _run_rank2_values()
	await _run_rank2_stat_scaling()
	print(("DEW MINION RANK-2 TEST PASSED" if _failures == 0 else "DEW MINION RANK-2 TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dew_minion_rank2.gd`
Expected: FAIL on case 2/3 — heals are still the flat rank-1 values at every level.

- [ ] **Step 3: Implement rank-2 constants + rank-aware, stat-scaled heal**

In `combat/combat.gd`, after the existing `const DEW_STAGE3_HEAL: int = 16` (line 935):

```gdscript
## Rank-2 (level 6+) per-stage heals (2026-09-02 harvester-rank2-content spec §2.2) — +4/+6/+8
## over rank 1, the reference delta pattern the other three minions' rank-2 values also follow.
const DEW_STAGE1_HEAL_RANK2: int = 12
const DEW_STAGE2_HEAL_RANK2: int = 18
const DEW_STAGE3_HEAL_RANK2: int = 24
```

Then in `_run_dew_stage()`, replace the existing heal-amount line
(`var heal_amount: int = DEW_STAGE3_HEAL if stage == 3 else (DEW_STAGE2_HEAL if stage == 2 else DEW_STAGE1_HEAL)`)
with:

```gdscript
	var rank: int = caster.ability_talent_row_rank(&"ability_l2") if caster != null else 1
	var heal_amount: int
	if rank >= 2:
		heal_amount = DEW_STAGE3_HEAL_RANK2 if stage == 3 else (DEW_STAGE2_HEAL_RANK2 if stage == 2 else DEW_STAGE1_HEAL_RANK2)
	else:
		heal_amount = DEW_STAGE3_HEAL if stage == 3 else (DEW_STAGE2_HEAL if stage == 2 else DEW_STAGE1_HEAL)
	var stat_mult: float = caster.ability_magnitude_multiplier() if caster != null else 1.0
	heal_amount = ceili(heal_amount * stat_mult)
```

This must land AFTER the existing `if stage >= 4: ... return` early-out (Evergreen Bloom's looping
heal, `DEW_EVERGREEN_LOOP_HEAL`, stays untouched by rank/stat scaling per the spec) and BEFORE the
`for ally: Combatant in _allies_of(minion):` loop that consumes `heal_amount`. Everything else in
the function (cleanse count, Thorns, Guardian Bloom) is unchanged.

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dew_minion_rank2.gd`
Expected: `DEW MINION RANK-2 TEST PASSED`

- [ ] **Step 5: Commit**

```bash
git add combat/combat.gd tests/test_dew_minion_rank2.gd
git commit -m "feat(harvester): Lotus rank-2 heal values + stat scaling"
```

---

### Task 3: Nightshade (Misfortune) rank-2 curse damage + Mutual Exhaustion talent

**Files:**
- Modify: `combat/combat.gd:991` (constant area), `combat/combat.gd:993-1017` (`_run_misfortune_stage`)
- Modify: `combat/effect_library.gd` (add `&"exhausted_weakened"`/`&"exhausted_sundered"`)
- Modify: `combat/ability_talent_library.gd:663-666` (swap Creeping Blight for Mutual Exhaustion)
- Modify: `combat/combatant.gd` (confirm `remove_effect()` exists — it does, line 1529; no change needed there)
- Test: Create `tests/test_misfortune_minion_rank2.gd`

**Interfaces:**
- Consumes: `Combatant.ability_talent_row_rank(&"ability_l3")`, `Combatant.ability_magnitude_multiplier()`,
  `Combatant.has_effect(id) -> bool`, `Combatant.remove_effect(id) -> void`, `Combatant.attach_effect(Effect) -> void`
  (all existing), `EffectLibrary.make(id: StringName) -> Effect` extended with two new ids.
- Produces: two new effect ids (`&"exhausted_weakened"`, `&"exhausted_sundered"`) other classes'
  future rank-2 passes MAY reuse later (explicitly out of scope to design further now, per spec).

- [ ] **Step 1: Write the failing test**

Create `tests/test_misfortune_minion_rank2.gd`:

```gdscript
extends SceneTree

# Headless test: Nightshade (Misfortune) minion rank-2 curse damage + the Mutual Exhaustion talent
# (2026-09-02 harvester-rank2-content spec §2.3).
#
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_misfortune_minion_rank2.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _build_encounter(level: int) -> Array:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()
	var pc: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	pc.level = level
	pc.base_stats.focus = 0
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	CombatHandoff.begin_encounter(pc, [], inv, vault, [&"rat"], &"MisfortuneRank2Test", "res://world/overworld_demo.tscn", Vector2.ZERO)
	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame
	inst.roll_initiative_for_test()
	var enemy: Combatant = inst._enemies[0]
	return [inst, pc, enemy]

func _cleanup(inst: Combat) -> void:
	inst.queue_free()
	await process_frame
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

## Case 1: level 6 (below ability_l3's rank-2 threshold of 7) -> rank-1 curse (12.0) unchanged,
## and stage 3 does NOT reapply Weakened/Sundered without the (now-removed) Creeping Blight talent.
func _run_rank1_regression() -> void:
	var setup: Array = await _build_encounter(6)
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	var enemy: Combatant = setup[2]
	var minion: Combatant = MinionLibrary.make(false, &"misfortune")
	inst._turn_manager.combatants.append(minion)

	inst._run_misfortune_stage(minion, 1, pc)
	inst._run_misfortune_stage(minion, 2, pc)
	enemy.remove_effect(&"weakened")
	enemy.remove_effect(&"sundered")
	inst._run_misfortune_stage(minion, 3, pc)

	var curse: Effect = enemy._find_effect(&"cursed")
	_check(curse != null and is_equal_approx(curse.dot_base_damage, 12.0), "level 6: rank-1 curse dot_base_damage 12.0 unchanged (got %s)" % [curse.dot_base_damage if curse != null else "null"])
	_check(not enemy.has_effect(&"weakened"), "level 6: stage 3 does not reapply Weakened (no talent picked)")

	await _cleanup(inst)

## Case 2: level 7+ (ability_l3 rank 2), no Mutual Exhaustion talent -> curse bumps to 18.0 AND
## stage 3's now-unconditional baseline reapplies Weakened + Sundered.
func _run_rank2_baseline() -> void:
	var setup: Array = await _build_encounter(7)
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	var enemy: Combatant = setup[2]
	var minion: Combatant = MinionLibrary.make(false, &"misfortune")
	inst._turn_manager.combatants.append(minion)

	inst._run_misfortune_stage(minion, 1, pc)
	inst._run_misfortune_stage(minion, 2, pc)
	enemy.remove_effect(&"weakened")
	enemy.remove_effect(&"sundered")
	inst._run_misfortune_stage(minion, 3, pc)

	var curse: Effect = enemy._find_effect(&"cursed")
	_check(curse != null and is_equal_approx(curse.dot_base_damage, 18.0), "level 7: rank-2 curse dot_base_damage 18.0 (got %s)" % [curse.dot_base_damage if curse != null else "null"])
	_check(enemy.has_effect(&"weakened") and enemy.has_effect(&"sundered"), "level 7: rank-2 baseline reapplies Weakened + Sundered at stage 3 without the talent")
	_check(not enemy.has_effect(&"exhausted_weakened"), "level 7: no Mutual Exhaustion talent picked -> no Exhausted merge")

	await _cleanup(inst)

## Case 3: level 7+, Mutual Exhaustion picked, target already Weakened + Sundered from stage 2 ->
## stage 3 merges them into Exhausted (+ Slow) instead of a plain reapply.
func _run_mutual_exhaustion_merge() -> void:
	var setup: Array = await _build_encounter(7)
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	var enemy: Combatant = setup[2]
	pc.ability_talent_picks[&"ability_l3"] = &"misfortune_mutual_exhaustion"
	var minion: Combatant = MinionLibrary.make(false, &"misfortune")
	inst._turn_manager.combatants.append(minion)

	inst._run_misfortune_stage(minion, 1, pc)
	inst._run_misfortune_stage(minion, 2, pc)
	_check(enemy.has_effect(&"weakened") and enemy.has_effect(&"sundered"), "setup: enemy carries both Weakened and Sundered after stage 2")
	inst._run_misfortune_stage(minion, 3, pc)

	_check(not enemy.has_effect(&"weakened"), "merge: plain Weakened was removed")
	_check(not enemy.has_effect(&"sundered"), "merge: plain Sundered was removed")
	_check(enemy.has_effect(&"exhausted_weakened"), "merge: Exhausted's outgoing half is active")
	_check(enemy.has_effect(&"exhausted_sundered"), "merge: Exhausted's incoming half is active")
	_check(enemy.has_effect(&"slow"), "merge: Slow was bundled in")

	# Stacking: a LATER plain Weakened application must multiply on top of Exhausted, not no-op.
	var mult_before: float = enemy.outgoing_damage_multiplier()
	enemy.attach_effect(EffectLibrary.make(&"weakened"))
	var mult_after: float = enemy.outgoing_damage_multiplier()
	_check(mult_after < mult_before, "stacking: a later plain Weakened multiplies further on top of Exhausted's outgoing reduction (%f -> %f)" % [mult_before, mult_after])

	await _cleanup(inst)

func _initialize() -> void:
	await _run_rank1_regression()
	await _run_rank2_baseline()
	await _run_mutual_exhaustion_merge()
	print(("MISFORTUNE MINION RANK-2 TEST PASSED" if _failures == 0 else "MISFORTUNE MINION RANK-2 TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_misfortune_minion_rank2.gd`
Expected: FAIL — `misfortune_mutual_exhaustion` isn't a real talent id yet (case 3's pick is a
no-op against `pick_ability_talent`'s validation, but this test writes directly into
`ability_talent_picks` to bypass that gate and drive `has_ability_talent()` — it will still fail
on the curse-damage and reapply-baseline assertions since none of the rank-2 code exists yet).

- [ ] **Step 3: Add the two new Exhausted effect definitions**

In `combat/effect_library.gd`, add two new cases to the `match id:` block (alongside the existing
`&"weakened"`/`&"sundered"` cases — same shape, distinct ids so `attach_effect()`'s merge-by-id
never collapses them into a later plain Weakened/Sundered reapplication):

```gdscript
		&"exhausted_weakened":
			# Mutual Exhaustion's outgoing half (2026-09-02 harvester-rank2-content spec §2.3) — same
			# magnitude as plain "weakened" but a DISTINCT id, so a later plain Weakened application
			# stacks multiplicatively on top instead of merge-by-id absorbing it (see attach_effect()).
			var e: Effect = Effect.new()
			e.id = &"exhausted_weakened"; e.kind = Effect.Kind.MULTIPLIER_EDIT; e.magnitude = 0.75
			e.affects_incoming = false; e.duration = 2; e.beneficial = false
			return e
		&"exhausted_sundered":
			# Mutual Exhaustion's incoming half — same rationale as exhausted_weakened above.
			var e: Effect = Effect.new()
			e.id = &"exhausted_sundered"; e.kind = Effect.Kind.MULTIPLIER_EDIT; e.magnitude = 1.25
			e.affects_incoming = true; e.duration = 2; e.beneficial = false
			return e
```

- [ ] **Step 4: Swap Creeping Blight for Mutual Exhaustion in the talent library**

In `combat/ability_talent_library.gd`, replace the `m2` option (lines 663-666):

```gdscript
					var m2: AbilityTalentOption = AbilityTalentOption.new()
					m2.id = &"misfortune_creeping_blight"; m2.row_id = row_id
					m2.display_name = "Creeping Blight"
					m2.description = "Nightshade's stage 3 also reapplies Weakened and Sundered alongside Cursed."
```

with:

```gdscript
					var m2: AbilityTalentOption = AbilityTalentOption.new()
					m2.id = &"misfortune_mutual_exhaustion"; m2.row_id = row_id
					m2.display_name = "Mutual Exhaustion"
					m2.description = "If Nightshade's stage 3 finds a target already Weakened AND Sundered, both merge into Exhausted (same combined effect) plus Slow — reapplying either later stacks even further."
```

(Creeping Blight's old "always reapply Weakened + Sundered at stage 3" behavior is absorbed into
the rank-2 baseline unconditionally in Step 5 below — it no longer needs its own talent.)

- [ ] **Step 5: Wire rank-2 curse damage + the rank-2 baseline reapply + Mutual Exhaustion merge**

In `combat/combat.gd`, replace `_run_misfortune_stage()` in full:

```gdscript
func _run_misfortune_stage(minion: Combatant, stage: int, caster: Combatant = null) -> void:
	var withering_touch: bool = caster != null and caster.has_ability_talent(&"misfortune_withering_touch")
	var mutual_exhaustion: bool = caster != null and caster.has_ability_talent(&"misfortune_mutual_exhaustion")
	var ill_fortune: bool = caster != null and caster.has_ability_talent(&"misfortune_ill_fortune")
	var rank: int = caster.ability_talent_row_rank(&"ability_l3") if caster != null else 1
	var stat_mult: float = caster.ability_magnitude_multiplier() if caster != null else 1.0
	for enemy: Combatant in _enemies_of(minion):
		if not enemy.is_alive():
			continue
		if stage == 1 or stage == 2:
			enemy.attach_effect(EffectLibrary.make(&"weakened"))
		if stage == 2:
			enemy.attach_effect(EffectLibrary.make(&"sundered"))
			if ill_fortune:
				enemy.attach_effect(EffectLibrary.make(&"jinxed"))
		if stage == 3:
			# Rank 2 (2026-09-02 harvester-rank2-content spec §2.3): stage 3 now unconditionally
			# reapplies Weakened + Sundered (absorbing the old misfortune_creeping_blight talent's
			# behavior into the baseline) — UNLESS Mutual Exhaustion is picked and the target
			# already carries both, in which case they merge into Exhausted + Slow instead.
			if rank >= 2:
				if mutual_exhaustion and enemy.has_effect(&"weakened") and enemy.has_effect(&"sundered"):
					enemy.remove_effect(&"weakened")
					enemy.remove_effect(&"sundered")
					enemy.attach_effect(EffectLibrary.make(&"exhausted_weakened"))
					enemy.attach_effect(EffectLibrary.make(&"exhausted_sundered"))
					enemy.attach_effect(EffectLibrary.make(&"slow"))
					_log("  🌑 Nightshade merges %s's Weakened + Sundered into EXHAUSTED (+ Slow)." % enemy.display_name)
				else:
					enemy.attach_effect(EffectLibrary.make(&"weakened"))
					enemy.attach_effect(EffectLibrary.make(&"sundered"))
			var curse: Effect = EffectLibrary.make(&"cursed")
			curse.dot_base_damage = (18.0 if rank >= 2 else 12.0) * stat_mult
			if withering_touch:
				curse.heal_multiplier = MISFORTUNE_WITHERING_TOUCH_HEAL_MULT
			enemy.attach_effect(curse)
		if _panels.has(enemy):
			(_panels[enemy] as CombatantPanel).refresh_status()
	_log("  🌑 Nightshade (stage %d) afflicts every enemy." % stage)
```

- [ ] **Step 6: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_misfortune_minion_rank2.gd`
Expected: `MISFORTUNE MINION RANK-2 TEST PASSED`

- [ ] **Step 7: Commit**

```bash
git add combat/combat.gd combat/effect_library.gd combat/ability_talent_library.gd tests/test_misfortune_minion_rank2.gd
git commit -m "feat(harvester): Nightshade rank-2 curse damage + Mutual Exhaustion talent"
```

---

### Task 4: Wheat (Hasty) rank-2 buff values + stat scaling

**Files:**
- Modify: `combat/combat.gd:1023-1029` (constants), `combat/combat.gd:1031-1075` (`_run_hasty_stage`)
- Test: Create `tests/test_hasty_minion_rank2.gd`

**Interfaces:**
- Consumes: `Combatant.ability_talent_row_rank(&"ability_l4")`, `Combatant.ability_magnitude_multiplier()`.
- Produces: `HASTY_REGEN_BONUS_RANK2` — Task 6 (Grand Sacrifice) reuses this exact constant for its
  own Wheat variant's regen bonus, per the spec's §4 note ("regen bonus stays tied to
  `HASTY_REGEN_BONUS`, rank-aware").

- [ ] **Step 1: Write the failing test**

Create `tests/test_hasty_minion_rank2.gd`:

```gdscript
extends SceneTree

# Headless test: Wheat (Hasty) minion rank-2 buff values + stat scaling
# (2026-09-02 harvester-rank2-content spec §2.4).
#
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_hasty_minion_rank2.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _build_encounter(level: int) -> Array:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()
	var pc: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	pc.level = level
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	CombatHandoff.begin_encounter(pc, [], inv, vault, [&"rat"], &"HastyRank2Test", "res://world/overworld_demo.tscn", Vector2.ZERO)
	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame
	inst.roll_initiative_for_test()
	return [inst, pc]

func _cleanup(inst: Combat) -> void:
	inst.queue_free()
	await process_frame
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

## Case 1: level 7 (below ability_l4's rank-2 threshold of 8) -> rank-1 values unchanged.
func _run_rank1_regression() -> void:
	var setup: Array = await _build_encounter(7)
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	pc.base_stats.focus = 0
	var minion: Combatant = MinionLibrary.make(false, &"hasty")
	inst._turn_manager.combatants.append(minion)

	inst._run_hasty_stage(minion, 1, pc)
	var haste: Effect = pc._find_effect(&"hasty_initiative")
	_check(haste != null and is_equal_approx(haste.magnitude, 20.0), "level 7 stage 1: rank-1 Initiative bonus 20.0 unchanged (got %s)" % [haste.magnitude if haste != null else "null"])

	inst._run_hasty_stage(minion, 2, pc)
	var regen: Effect = pc._find_effect(&"hasty_regen")
	_check(regen != null and regen.regen_bonus == 3, "level 7 stage 2: rank-1 regen bonus 3 unchanged (got %s)" % [regen.regen_bonus if regen != null else "null"])

	inst._run_hasty_stage(minion, 3, pc)
	var empowered: Effect = pc._find_effect(&"empowered")
	_check(empowered != null and empowered.duration == 1, "level 7 stage 3: rank-1 Empowered duration 1 turn unchanged (got %s)" % [empowered.duration if empowered != null else "null"])

	await _cleanup(inst)

## Case 2: level 8+ (ability_l4 rank 2) -> rank-2 values apply (Focus zeroed to isolate rank-up
## from stat scaling, checked separately in case 3).
func _run_rank2_values() -> void:
	var setup: Array = await _build_encounter(8)
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	pc.base_stats.focus = 0
	var minion: Combatant = MinionLibrary.make(false, &"hasty")
	inst._turn_manager.combatants.append(minion)

	inst._run_hasty_stage(minion, 1, pc)
	var haste: Effect = pc._find_effect(&"hasty_initiative")
	_check(haste != null and is_equal_approx(haste.magnitude, 24.0), "level 8 stage 1: rank-2 Initiative bonus 24.0 (got %s)" % [haste.magnitude if haste != null else "null"])

	inst._run_hasty_stage(minion, 2, pc)
	var regen: Effect = pc._find_effect(&"hasty_regen")
	_check(regen != null and regen.regen_bonus == 5, "level 8 stage 2: rank-2 regen bonus 5 (got %s)" % [regen.regen_bonus if regen != null else "null"])

	inst._run_hasty_stage(minion, 3, pc)
	var empowered: Effect = pc._find_effect(&"empowered")
	_check(empowered != null and empowered.duration == 2, "level 8 stage 3: rank-2 Empowered duration 2 turns (got %s)" % [empowered.duration if empowered != null else "null"])

	await _cleanup(inst)

## Case 3: rank-2 regen bonus additionally scales with Focus via ability_magnitude_multiplier();
## Initiative bonus and Empowered duration are NOT magnitude-multiplied (spec §2.4).
func _run_rank2_stat_scaling() -> void:
	var setup: Array = await _build_encounter(8)
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	pc.base_stats.focus = 4
	var minion: Combatant = MinionLibrary.make(false, &"hasty")
	inst._turn_manager.combatants.append(minion)

	inst._run_hasty_stage(minion, 1, pc)
	var haste: Effect = pc._find_effect(&"hasty_initiative")
	_check(haste != null and is_equal_approx(haste.magnitude, 24.0), "level 8, Focus 4, stage 1: Initiative bonus stays 24.0, not magnitude-multiplied (got %s)" % [haste.magnitude if haste != null else "null"])

	inst._run_hasty_stage(minion, 2, pc)
	var regen: Effect = pc._find_effect(&"hasty_regen")
	var expected: int = ceili(5 * 1.5)
	_check(regen != null and regen.regen_bonus == expected, "level 8, Focus 4, stage 2: regen bonus (5) scaled by 1.5 -> %d (got %s)" % [expected, regen.regen_bonus if regen != null else "null"])

	await _cleanup(inst)

func _initialize() -> void:
	await _run_rank1_regression()
	await _run_rank2_values()
	await _run_rank2_stat_scaling()
	print(("HASTY MINION RANK-2 TEST PASSED" if _failures == 0 else "HASTY MINION RANK-2 TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_hasty_minion_rank2.gd`
Expected: FAIL on case 2/3 — values stay at rank-1 numbers at every level.

- [ ] **Step 3: Implement rank-2 constants + rank-aware, partially-stat-scaled buffs**

In `combat/combat.gd`, after the existing `const HASTY_BOUNTIFUL_HARVEST_REFUND: int = 2` (line 1029):

```gdscript
## Rank-2 (level 8+) values (2026-09-02 harvester-rank2-content spec §2.4). Only the regen bonus
## is magnitude-multiplied by ability_magnitude_multiplier() — Initiative bonus and Empowered's
## duration are turn-count/Initiative-system values, not damage/heal-shaped magnitudes, matching
## the convention StatScaling already follows elsewhere.
const HASTY_INITIATIVE_BONUS_RANK2: float = 24.0
const HASTY_REGEN_BONUS_RANK2: int = 5
const HASTY_EMPOWERED_TURNS_RANK2: int = 2
```

Then replace `_run_hasty_stage()` in full:

```gdscript
func _run_hasty_stage(minion: Combatant, stage: int, caster: Combatant = null) -> void:
	var bountiful_harvest: bool = caster != null and caster.has_ability_talent(&"hasty_bountiful_harvest")
	var unshakeable_roots: bool = caster != null and caster.has_ability_talent(&"hasty_unshakeable_roots")
	var rank: int = caster.ability_talent_row_rank(&"ability_l4") if caster != null else 1
	var stat_mult: float = caster.ability_magnitude_multiplier() if caster != null else 1.0
	var initiative_bonus: float = HASTY_INITIATIVE_BONUS_RANK2 if rank >= 2 else HASTY_INITIATIVE_BONUS
	var regen_bonus: int = ceili((HASTY_REGEN_BONUS_RANK2 if rank >= 2 else HASTY_REGEN_BONUS) * stat_mult)
	var empowered_turns: int = HASTY_EMPOWERED_TURNS_RANK2 if rank >= 2 else 1
	for ally: Combatant in _allies_of(minion):
		if not ally.is_alive():
			continue
		if stage == 1:
			var haste := Effect.new()
			haste.id = &"hasty_initiative"
			haste.kind = Effect.Kind.INITIATIVE_MOD
			haste.magnitude = initiative_bonus
			haste.duration = HASTY_INITIATIVE_TURNS + (1 if ally == caster else 0)
			haste.beneficial = true
			if unshakeable_roots:
				haste.immune_effect_ids = [&"slow", &"rooted"]
			ally.attach_effect(haste)
		if stage == 2:
			var regen := Effect.new()
			regen.id = &"hasty_regen"
			regen.kind = Effect.Kind.REEL_FACE_EDIT
			regen.regen_bonus = regen_bonus
			regen.duration = HASTY_REGEN_TURNS
			regen.beneficial = true
			ally.attach_effect(regen)
			_log("  💨 Wheat grants %s +%d resource regen (%d turns)." % [ally.display_name, regen_bonus, HASTY_REGEN_TURNS])
			if bountiful_harvest and ally.resource_pool != null:
				ally.resource_pool.pending_ability_refund = HASTY_BOUNTIFUL_HARVEST_REFUND
		if stage == 3:
			var empowered: Effect = EffectLibrary.make(&"empowered")
			empowered.duration = empowered_turns
			ally.attach_effect(empowered)
			var surge := Effect.new()
			surge.id = &"reel_surge"
			surge.kind = Effect.Kind.REEL_FACE_EDIT
			surge.duration = HASTY_REEL_SURGE_TURNS
			surge.beneficial = true
			ally.attach_effect(surge)
		if _panels.has(ally):
			(_panels[ally] as CombatantPanel).refresh_status()
	_log("  💨 Wheat (stage %d) buffs the party." % stage)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_hasty_minion_rank2.gd`
Expected: `HASTY MINION RANK-2 TEST PASSED`

- [ ] **Step 5: Commit**

```bash
git add combat/combat.gd tests/test_hasty_minion_rank2.gd
git commit -m "feat(harvester): Wheat rank-2 buff values + stat scaling"
```

---

### Task 5: Harvest's Favor passive amplification (level 9)

**Files:**
- Modify: `combat/combatant.gd:203-204` (constants), `combat/combatant.gd:1332-1365` (`harvest_favor_on_hit`)
- Test: Create `tests/test_harvest_favor_rank2.gd`

**Interfaces:**
- Consumes: `Combatant.ability_talent_row_rank(&"passive")`, `Combatant.ability_magnitude_multiplier()`.
- Produces: nothing new for later tasks.

- [ ] **Step 1: Write the failing test**

Create `tests/test_harvest_favor_rank2.gd`. Unlike the minion tests, `harvest_favor_on_hit()` is a
pure `Combatant` method — it touches no `Combat`/scene state, so no CombatHandoff/scene harness is
needed at all:

```gdscript
extends SceneTree

# Headless test: Harvest's Favor passive amplification at level 9
# (2026-09-02 harvester-rank2-content spec §3). harvest_favor_on_hit() is a pure Combatant method
# (no Combat/scene dependency), so this test builds bare Combatants directly.
#
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_harvest_favor_rank2.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

## Builds a Harvester with an active minion of [param minion_type] at [param level], Focus zeroed
## (isolates rank-up from stat scaling — tested separately).
func _harvester(level: int, minion_type: StringName) -> Combatant:
	var c: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	c.level = level
	c.base_stats.focus = 0
	c.active_minion = MinionLibrary.make(false, minion_type)
	return c

func _run_rank1_regression() -> void:
	var caster: Combatant = _harvester(8, &"ember")
	var target: Combatant = EnemyLibrary.make(&"rat")
	var hp_before: int = target.hp
	caster.harvest_favor_on_hit(target, [caster])
	_check(target.hp == hp_before - 4, "level 8: rank-1 Ember bonus damage 4 unchanged (hp %d -> %d)" % [hp_before, target.hp])

	var dew_caster: Combatant = _harvester(8, &"dew")
	dew_caster.take_damage(30)
	var hp_before_heal: int = dew_caster.hp
	dew_caster.harvest_favor_on_hit(null, [dew_caster])
	_check(dew_caster.hp == hp_before_heal + 3, "level 8: rank-1 Dew heal 3 unchanged (hp %d -> %d)" % [hp_before_heal, dew_caster.hp])

func _run_amplified_values() -> void:
	var caster: Combatant = _harvester(9, &"ember")
	var target: Combatant = EnemyLibrary.make(&"rat")
	var hp_before: int = target.hp
	caster.harvest_favor_on_hit(target, [caster])
	_check(target.hp == hp_before - 8, "level 9: amplified Ember bonus damage 8 (hp %d -> %d)" % [hp_before, target.hp])

	var dew_caster: Combatant = _harvester(9, &"dew")
	dew_caster.take_damage(30)
	var hp_before_heal: int = dew_caster.hp
	dew_caster.harvest_favor_on_hit(null, [dew_caster])
	_check(dew_caster.hp == hp_before_heal + 6, "level 9: amplified Dew heal 6 (hp %d -> %d)" % [hp_before_heal, dew_caster.hp])

	var misfortune_caster: Combatant = _harvester(9, &"misfortune")
	var enemy: Combatant = EnemyLibrary.make(&"rat")
	var weak: Effect = EffectLibrary.make(&"weakened")
	weak.duration = 2
	enemy.attach_effect(weak)
	misfortune_caster.harvest_favor_on_hit(enemy, [misfortune_caster])
	_check(enemy._find_effect(&"weakened").duration == 4, "level 9: amplified Misfortune duration extension +2 turns (got %d)" % enemy._find_effect(&"weakened").duration)

func _run_amplified_stat_scaling() -> void:
	var caster: Combatant = _harvester(9, &"ember")
	caster.base_stats.focus = 4
	var target: Combatant = EnemyLibrary.make(&"rat")
	var hp_before: int = target.hp
	caster.harvest_favor_on_hit(target, [caster])
	var expected: int = ceili(8 * 1.5)
	_check(target.hp == hp_before - expected, "level 9, Focus 4: amplified Ember damage (8) scaled by 1.5 -> %d (hp %d -> %d)" % [expected, hp_before, target.hp])

func _initialize() -> void:
	_run_rank1_regression()
	_run_amplified_values()
	_run_amplified_stat_scaling()
	print(("HARVEST FAVOR RANK-2 TEST PASSED" if _failures == 0 else "HARVEST FAVOR RANK-2 TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_harvest_favor_rank2.gd`
Expected: FAIL on the level-9 cases — values stay at the rank-1 constants at every level, and
Ember/Dew branches aren't yet stat-scaled at all.

- [ ] **Step 3: Implement amplified constants + rank-aware, stat-scaled passive**

In `combat/combatant.gd`, after the existing `const HARVEST_FAVOR_DEW_HEAL: int = 3` (line 204):

```gdscript
## Amplified (level 9+) values (2026-09-02 harvester-rank2-content spec §3).
const HARVEST_FAVOR_EMBER_BONUS_DAMAGE_AMPLIFIED: int = 8
const HARVEST_FAVOR_DEW_HEAL_AMPLIFIED: int = 6
const HARVEST_FAVOR_DURATION_EXTENSION_AMPLIFIED: int = 2
```

Then replace `harvest_favor_on_hit()` in full:

```gdscript
func harvest_favor_on_hit(target: Combatant, allies: Array[Combatant], is_neutral: bool = false) -> void:
	if passive_ability_id != &"harvest_favor" or active_minion == null or not active_minion.is_alive():
		return
	if is_neutral and not has_ability_talent(&"harvest_favor_unleashed"):
		return
	var amplified: bool = ability_talent_row_rank(&"passive") >= 2
	var scale: float = HARVEST_FAVOR_UNLEASHED_FRACTION if is_neutral else 1.0
	if has_ability_talent(&"harvest_favor_amplified_bond"):
		scale *= float(active_minion.minion_stage)
	var duration_extension: int = HARVEST_FAVOR_DURATION_EXTENSION_AMPLIFIED if amplified else 1
	var stat_mult: float = ability_magnitude_multiplier()
	match active_minion.minion_type:
		&"ember":
			if target != null and target.is_alive():
				var base_dmg: int = HARVEST_FAVOR_EMBER_BONUS_DAMAGE_AMPLIFIED if amplified else HARVEST_FAVOR_EMBER_BONUS_DAMAGE
				target.take_damage(ceili(base_dmg * scale * stat_mult))
		&"dew":
			var lowest: Combatant = null
			for a: Combatant in allies:
				if a == null or not a.is_alive() or a.is_minion:
					continue
				if lowest == null or a.hp < lowest.hp:
					lowest = a
			if lowest != null:
				var base_heal: int = HARVEST_FAVOR_DEW_HEAL_AMPLIFIED if amplified else HARVEST_FAVOR_DEW_HEAL
				lowest.heal(ceili(base_heal * scale * stat_mult))
		&"misfortune":
			if target == null or not target.is_alive():
				return
			for debuff_id: StringName in [&"weakened", &"sundered", &"cursed"]:
				var e: Effect = target._find_effect(debuff_id)
				if e != null:
					e.duration += duration_extension
			if has_ability_talent(&"misfortune_ill_fortune"):
				target.attach_effect(EffectLibrary.make(&"jinxed"))
		&"hasty":
			for e: Effect in active_effects:
				if e != null and e.beneficial:
					e.duration += duration_extension
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_harvest_favor_rank2.gd`
Expected: `HARVEST FAVOR RANK-2 TEST PASSED`

- [ ] **Step 5: Commit**

```bash
git add combat/combatant.gd tests/test_harvest_favor_rank2.gd
git commit -m "feat(harvester): Harvest's Favor amplified at level 9 + stat scaling"
```

---

### Task 6: Grand Sacrifice / Strawfellow's Due rank-2 (level 10)

**Files:**
- Modify: `combat/combat.gd:1082-1088` (constants), `combat/combat.gd:1090-1194` (`_apply_grand_sacrifice`)
- Test: Create `tests/test_grand_sacrifice_rank2.gd`

**Interfaces:**
- Consumes: `Combatant.ability_talent_row_rank(&"ultimate")`, `Combatant.ability_magnitude_multiplier()`,
  `HASTY_REGEN_BONUS_RANK2` (produced by Task 4).
- Produces: nothing new for later tasks — this is the last task.

- [ ] **Step 1: Write the failing test**

Create `tests/test_grand_sacrifice_rank2.gd`:

```gdscript
extends SceneTree

# Headless test: Grand Sacrifice / Strawfellow's Due rank-2 at level 10
# (2026-09-02 harvester-rank2-content spec §4).
#
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_grand_sacrifice_rank2.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _build_encounter(level: int) -> Array:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()
	var pc: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	pc.level = level
	pc.base_stats.focus = 0
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	CombatHandoff.begin_encounter(pc, [], inv, vault, [&"rat"], &"GrandSacrificeRank2Test", "res://world/overworld_demo.tscn", Vector2.ZERO)
	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame
	inst.roll_initiative_for_test()
	var enemy: Combatant = inst._enemies[0]
	return [inst, pc, enemy]

func _cleanup(inst: Combat) -> void:
	inst.queue_free()
	await process_frame
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

## Case 1: level 9 (below ultimate's rank-2 threshold of 10) -> rank-1 values unchanged (Ember
## variant checked as the representative case for the flat-burst shape; Dew/Misfortune/Hasty
## follow the identical rank-lookup pattern, covered by case 2's rank-2 checks below).
func _run_rank1_regression() -> void:
	var setup: Array = await _build_encounter(9)
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	var enemy: Combatant = setup[2]
	inst._defender = enemy
	var hp_before: int = enemy.hp
	inst._apply_grand_sacrifice(pc, &"ember")
	_check(enemy.hp == hp_before - 40, "level 9: rank-1 Ember burst 40 unchanged (hp %d -> %d)" % [hp_before, enemy.hp])

	await _cleanup(inst)

## Case 2: level 10 (ultimate rank 2) -> rank-2 values apply across all four variants.
func _run_rank2_values() -> void:
	# Ember burst.
	var setup: Array = await _build_encounter(10)
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	var enemy: Combatant = setup[2]
	inst._defender = enemy
	var hp_before: int = enemy.hp
	inst._apply_grand_sacrifice(pc, &"ember")
	_check(enemy.hp == hp_before - 60, "level 10: rank-2 Ember burst 60 (hp %d -> %d)" % [hp_before, enemy.hp])
	await _cleanup(inst)

	# Dew heal + Thorns + duration.
	setup = await _build_encounter(10)
	inst = setup[0]
	pc = setup[1]
	pc.take_damage(50)
	var hp_before_heal: int = pc.hp
	inst._apply_grand_sacrifice(pc, &"dew")
	_check(pc.hp == mini(hp_before_heal + 45, pc.max_hp), "level 10: rank-2 Dew heal 45 (hp %d -> %d)" % [hp_before_heal, pc.hp])
	var thorns: Effect = pc._find_effect(&"grand_sacrifice_thorns")
	_check(thorns != null and is_equal_approx(thorns.thorns_pct, 0.45), "level 10: rank-2 Dew Thorns 45%% (got %s)" % [thorns.thorns_pct if thorns != null else "null"])
	_check(thorns != null and thorns.duration == 4, "level 10: rank-2 Dew Thorns duration 3 turns + caster's own +1 = 4 (got %s)" % [thorns.duration if thorns != null else "null"])
	await _cleanup(inst)

	# Misfortune curse damage + durations.
	setup = await _build_encounter(10)
	inst = setup[0]
	pc = setup[1]
	enemy = setup[2]
	inst._apply_grand_sacrifice(pc, &"misfortune")
	var curse: Effect = enemy._find_effect(&"cursed")
	_check(curse != null and is_equal_approx(curse.dot_base_damage, 22.0), "level 10: rank-2 Misfortune curse dot_base_damage 22.0 (got %s)" % [curse.dot_base_damage if curse != null else "null"])
	_check(curse != null and curse.duration == 4, "level 10: rank-2 Misfortune curse duration 4 turns (got %s)" % [curse.duration if curse != null else "null"])
	var jinx: Effect = enemy._find_effect(&"jinxed")
	_check(jinx != null and jinx.duration == 3, "level 10: rank-2 Misfortune Jinxed duration 3 turns (got %s)" % [jinx.duration if jinx != null else "null"])
	await _cleanup(inst)

	# Hasty regen/Empowered/surge duration.
	setup = await _build_encounter(10)
	inst = setup[0]
	pc = setup[1]
	inst._apply_grand_sacrifice(pc, &"hasty")
	var regen: Effect = pc._find_effect(&"grand_sacrifice_regen")
	_check(regen != null and regen.regen_bonus == 5, "level 10: rank-2 Hasty regen bonus 5 (rank-2 HASTY_REGEN_BONUS, got %s)" % [regen.regen_bonus if regen != null else "null"])
	_check(regen != null and regen.duration == 4, "level 10: rank-2 Hasty duration 3 turns + caster's own +1 = 4 (got %s)" % [regen.duration if regen != null else "null"])
	await _cleanup(inst)

func _initialize() -> void:
	await _run_rank1_regression()
	await _run_rank2_values()
	print(("GRAND SACRIFICE RANK-2 TEST PASSED" if _failures == 0 else "GRAND SACRIFICE RANK-2 TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_grand_sacrifice_rank2.gd`
Expected: FAIL on case 2 — every variant still uses its rank-1 value at level 10.

- [ ] **Step 3: Implement rank-2 constants + rank-aware, stat-scaled Grand Sacrifice**

In `combat/combat.gd`, after the existing `const GRAND_SACRIFICE_HASTY_TURNS: int = 2` (line 1088):

```gdscript
## Rank-2 (level 10+) values (2026-09-02 harvester-rank2-content spec §4).
const GRAND_SACRIFICE_EMBER_BURST_RANK2: int = 60
const GRAND_SACRIFICE_DEW_HEAL_RANK2: int = 45
const GRAND_SACRIFICE_DEW_THORNS_PCT_RANK2: float = 0.45
const GRAND_SACRIFICE_DEW_TURNS_RANK2: int = 3
const GRAND_SACRIFICE_MISFORTUNE_CURSE_RANK2: float = 22.0
const GRAND_SACRIFICE_MISFORTUNE_TURNS_RANK2: int = 3
const GRAND_SACRIFICE_CURSE_TURNS_RANK2: int = 4
const GRAND_SACRIFICE_HASTY_TURNS_RANK2: int = 3
```

Then replace `_apply_grand_sacrifice()` in full:

```gdscript
func _apply_grand_sacrifice(caster: Combatant, variant: StringName) -> void:
	var rank: int = caster.ability_talent_row_rank(&"ultimate")
	var stat_mult: float = caster.ability_magnitude_multiplier()
	match variant:
		&"ember":
			var burst: int = ceili((GRAND_SACRIFICE_EMBER_BURST_RANK2 if rank >= 2 else GRAND_SACRIFICE_EMBER_BURST) * stat_mult)
			if _defender == null or not _defender.is_alive():
				_defender = Combat.first_living(_enemies_of(caster))
			if _defender != null:
				_defender.take_damage(burst)
				if caster.has_ability_talent(&"strawfellow_petrifying_burst"):
					_defender.force_stun_next_turn = true
				var splashed: Array[Combatant] = _splash_half_to_others(caster, burst, "Piercing", 0.5)
				_log("  💥 Strawfellow's Due (Touch-Me-Not): %d burst damage, splashed to %d other enemies." % [burst, splashed.size()])
				if _panels.has(_defender):
					(_panels[_defender] as CombatantPanel).refresh_status()
				_refresh_target_highlight()
			else:
				_log("  💥 Strawfellow's Due (Touch-Me-Not) whiffs: no living enemy to burst.")
		&"dew":
			var heal: int = ceili((GRAND_SACRIFICE_DEW_HEAL_RANK2 if rank >= 2 else GRAND_SACRIFICE_DEW_HEAL) * stat_mult)
			var thorns_pct: float = GRAND_SACRIFICE_DEW_THORNS_PCT_RANK2 if rank >= 2 else GRAND_SACRIFICE_DEW_THORNS_PCT
			var turns: int = GRAND_SACRIFICE_DEW_TURNS_RANK2 if rank >= 2 else GRAND_SACRIFICE_DEW_TURNS
			for ally: Combatant in _allies_of(caster):
				if not ally.is_alive():
					continue
				ally.heal(heal)
				var thorns := Effect.new()
				thorns.id = &"grand_sacrifice_thorns"
				thorns.kind = Effect.Kind.REEL_FACE_EDIT
				thorns.thorns_pct = thorns_pct
				thorns.duration = turns
				if ally == caster:
					thorns.duration += 1
				thorns.beneficial = true
				ally.attach_effect(thorns)
				var cleanse := Effect.new()
				cleanse.id = &"grand_sacrifice_cleanse"
				cleanse.kind = Effect.Kind.REEL_FACE_EDIT
				cleanse.duration = turns
				if ally == caster:
					cleanse.duration += 1
				cleanse.beneficial = true
				ally.attach_effect(cleanse)
				if caster.has_ability_talent(&"strawfellow_undying_bloom"):
					ally.cleanse()
				if _panels.has(ally):
					(_panels[ally] as CombatantPanel).refresh_status()
			_log("  💧 Strawfellow's Due (Lotus): large party heal + improved Thorns + repeating cleanse.")
		&"misfortune":
			var misfortune_turns: int = GRAND_SACRIFICE_MISFORTUNE_TURNS_RANK2 if rank >= 2 else GRAND_SACRIFICE_MISFORTUNE_TURNS
			var curse_turns: int = GRAND_SACRIFICE_CURSE_TURNS_RANK2 if rank >= 2 else GRAND_SACRIFICE_CURSE_TURNS
			var curse_base: float = (GRAND_SACRIFICE_MISFORTUNE_CURSE_RANK2 if rank >= 2 else 15.0) * stat_mult
			for enemy: Combatant in _enemies_of(caster):
				if not enemy.is_alive():
					continue
				var jinx: Effect = EffectLibrary.make(&"jinxed")
				jinx.duration = misfortune_turns
				enemy.attach_effect(jinx)
				var curse: Effect = EffectLibrary.make(&"cursed")
				curse.dot_base_damage = curse_base
				if caster.has_ability_talent(&"strawfellow_withering_doom") and (enemy.has_effect(&"weakened") or enemy.has_effect(&"sundered")):
					curse.dot_base_damage *= 2.0
				curse.duration = curse_turns
				curse.add_stack()
				curse.add_stack()
				enemy.attach_effect(curse)
				if _panels.has(enemy):
					(_panels[enemy] as CombatantPanel).refresh_status()
			_log("  🌑 Strawfellow's Due (Nightshade): Jinxed + improved Curse on every enemy.")
		&"hasty":
			var hasty_turns: int = GRAND_SACRIFICE_HASTY_TURNS_RANK2 if rank >= 2 else GRAND_SACRIFICE_HASTY_TURNS
			var regen_bonus: int = ceili((HASTY_REGEN_BONUS_RANK2 if rank >= 2 else HASTY_REGEN_BONUS) * stat_mult)
			for ally: Combatant in _allies_of(caster):
				if not ally.is_alive():
					continue
				var bonus_turns: int = 1 if ally == caster else 0
				var regen := Effect.new()
				regen.id = &"grand_sacrifice_regen"
				regen.kind = Effect.Kind.REEL_FACE_EDIT
				regen.regen_bonus = regen_bonus
				regen.duration = hasty_turns + bonus_turns
				regen.beneficial = true
				ally.attach_effect(regen)
				var empowered: Effect = EffectLibrary.make(&"empowered")
				empowered.duration = hasty_turns + bonus_turns
				ally.attach_effect(empowered)
				var surge := Effect.new()
				surge.id = &"reel_surge"
				surge.kind = Effect.Kind.REEL_FACE_EDIT
				surge.duration = hasty_turns + bonus_turns
				surge.beneficial = true
				ally.attach_effect(surge)
				if _panels.has(ally):
					(_panels[ally] as CombatantPanel).refresh_status()
			_log("  💨 Strawfellow's Due (Wheat): party-wide regen + Empowered + reel surge, %d turns." % hasty_turns)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_grand_sacrifice_rank2.gd`
Expected: `GRAND SACRIFICE RANK-2 TEST PASSED`

- [ ] **Step 5: Commit**

```bash
git add combat/combat.gd tests/test_grand_sacrifice_rank2.gd
git commit -m "feat(harvester): Grand Sacrifice rank-2 at level 10 + stat scaling"
```

---

## Final Verification

After all 6 tasks are committed, run the full existing Harvester/minion/talent-tree test suite to
confirm nothing regressed (each of these already existed before this plan and must stay green):

```bash
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_minion_lifecycle.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dew_minion.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_misfortune_minion.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_hasty_minion.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_summoner_class.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_summoner_meter_economy.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talent_row_rank.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_magnitude_multiplier.gd
```

Grep the output of each for `SCRIPT ERROR`/`FAIL` (not just the exit code) per CLAUDE.md's
silent-script-error-exits-zero gotcha. This is a real, un-playtested balance/behavior change
(rank-2 numbers land the first time any Harvester reaches level 5+) — flag to the player that a
human playtest of a leveled-up Harvester is the natural next step after merge, same as the base
stat-scaling infrastructure's own still-open playtest item.
