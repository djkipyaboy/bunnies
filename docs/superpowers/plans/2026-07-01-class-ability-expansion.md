# Class Ability Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Grow every one of the 7 classes from 1 base ability + 1 Ultimate to 4 base abilities + 1
Ultimate (3 new abilities each, unlocked at levels 5/7/9), backed by new level/cooldown/effect
infrastructure, 11 new shared status effects, EnemyAI Taunt-awareness, and an ENDGAME tester.

**Architecture:** Additive, not destructive. The existing single `ability_id`/`ability_cost`/
`ability_resource` fields (the L1 ability) and the existing Ultimate dispatch are UNTOUCHED. A
parallel `extra_abilities: Array[AbilityDef]` on `CharacterClass`/`Combatant` carries the 3 new
per-class abilities; `MainPhasePlan` gets a second, parallel staging slot (`staged_extra_ability_id`)
alongside the existing `ability_staged` bool, mutually exclusive with it. This means every existing
test and behavior for the current 7 base abilities + 7 Ultimates is provably unaffected — new code
only ever ADDS a case to a match statement or a field to a class.

**Tech Stack:** Godot 4.6 GDScript, headless `SceneTree` tests (no test framework), `Resource`-based
data (per CLAUDE.md §2).

## Global Constraints

- GDScript only, no C# (CLAUDE.md §2).
- Static typing on new vars/functions (CLAUDE.md §2).
- Signals: snake_case, past-tense, no `on_` prefix on the signal itself (CLAUDE.md §2).
- All damage/heal math rounds UP (`ceili`) — project-wide convention (memory: round-up-damage-healing).
- Numeric magnitudes are `[ASSUMPTION]` placeholders — do not hand-tune by feel; note them in code
  comments so they're greppable for the eventual playtest pass (CLAUDE.md §4).
- Every existing test (69 suites) must stay green throughout — this plan only adds fields/cases,
  never renames or removes an existing one.
- Test pattern: `extends SceneTree`, manual `_check(cond, label)` printing "ok"/"FAIL", run via
  `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_<name>.gd`.

---

## Corrections to the locked spec (discovered during implementation grounding)

The spec (`docs/superpowers/specs/2026-07-01-class-ability-expansion-design.md`) is the design
source of truth; these are IMPLEMENTATION-LEVEL refinements that change HOW it's built, not WHAT it
builds:

1. **`ability_id` stays singular.** Restructuring it into an array (as the spec's §2.1 sketch
   suggested) would touch all 7 `ClassLibrary` entries, `MainPhasePlan`, and every existing test.
   Instead, a parallel `extra_abilities` array carries only the 3 NEW abilities. Net effect (4
   selectable abilities, gated by level) is identical; blast radius is far smaller.
2. **STUNNED is not an `Effect`.** `Combatant.stunned_this_turn`/`stunned_last_turn` are plain bools
   (see `combatant.gd:148-149`), never attached via `attach_effect`. Mountain Stance's "immune to
   Slow/Stunned/Rooted" therefore needs TWO mechanisms: `immune_effect_ids` (blocks `slow`/`rooted`
   attach) AND a new `Effect.grants_stun_immunity: bool` checked directly inside `evaluate_stun()`.
3. **"Haste" wasn't in the final 10-effect table** (only in the very first brainstorm bench list) but
   Quickstep needs it. Added as an 11th shared effect: `INITIATIVE_MOD +20`, beneficial, duration 2,
   non-stacking — the positive mirror of Slow's first tier.
4. **`MULTIPLIER_EDIT` is currently inert** (effect.gd's own doc comment: "Only INITIATIVE_MOD is
   exercised in the prototype"). A new outgoing/incoming multiplier hook must be built before ANY
   ability using Sundered/Weakened/Guarded/Empowered can do anything (Task 5).
5. **Crippling Shot's "bonus vs CC'd target"** needs `CombatResolver.AttackResult` to carry a
   reference to its source reel, so the orchestrator can special-case just that one ability's reel
   post-resolution. New field, `AttackResult.source_reel`.

---

## File Structure

New files:
- `combat/resources/ability_def.gd` — `AbilityDef` resource (id/unlock_level/cost/resource/cooldown).

Modified files (touched across multiple tasks below, listed once for orientation):
- `combat/resources/effect.gd` — `immune_effect_ids`, `thorns_pct`, `affects_incoming`, `grants_stun_immunity`.
- `combat/effect_library.gd` — 11 new effect defs.
- `combat/resources/combatant.gd` — `level`, `extra_abilities`, `cooldowns`, `riposte_charges`,
  pending flags, 21 new ability methods, multiplier/immunity/thorns query methods.
- `combat/resources/character_class.gd` — `extra_abilities` export + copy in `build_combatant`.
- `combat/class_library.gd` — populate `extra_abilities` for all 7 classes.
- `combat/main_phase_plan.gd` — extra-ability staging/cooldown-gating/preview/commit dispatch.
- `combat/resources/action_reel.gd` — `make_rider_attack()` factory, `bonus_vs_cc` field.
- `combat/combat_resolver.gd` — `damage_multiplier` param, `AttackResult.source_reel`.
- `combat/payline_library.gd` — `bonus_line()`.
- `combat/enemy_ai.gd` — Taunt pre-filter.
- `combat/combat.gd` — orchestrator wiring for every pending-flag ability, thorns reflection,
  Double-or-Nothing refund/recoil, Foresight/Regrowth ally targeting.

---

## Task 1: `AbilityDef` resource

**Files:**
- Create: `combat/resources/ability_def.gd`
- Test: `tests/test_ability_def.gd`

**Interfaces:**
- Produces: `AbilityDef` with `id: StringName`, `unlock_level: int`, `cost: int`,
  `resource: StringName`, `cooldown_turns: int`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var a: AbilityDef = AbilityDef.new()
	a.id = &"sundering_strike"
	a.unlock_level = 5
	a.cost = 3
	a.resource = &"stamina"
	a.cooldown_turns = 0
	_check(a.id == &"sundering_strike", "id set")
	_check(a.unlock_level == 5, "unlock_level set")
	_check(a.cooldown_turns == 0, "cooldown default path set")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_def.gd`
Expected: FAIL to even load — `AbilityDef` class does not exist.

- [ ] **Step 3: Write minimal implementation**

```gdscript
class_name AbilityDef
extends Resource

## One NEW (L5/L7/L9) per-class ability's data (spec 2026-07-01). Parallel to the existing single
## CharacterClass.ability_id/ability_cost/ability_resource fields (the L1 ability), which are
## untouched — see plan "Corrections to the locked spec" §1.

@export var id: StringName = &""
@export var unlock_level: int = 1
@export var cost: int = 2
@export var resource: StringName = &"stamina"

## 0 = no cooldown (L5/L7 abilities). L9 abilities set this (spec §4).
@export var cooldown_turns: int = 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_def.gd`
Expected: three "ok" lines.

- [ ] **Step 5: Commit**

```bash
git add combat/resources/ability_def.gd tests/test_ability_def.gd
git commit -m "feat(abilities): add AbilityDef resource for L5/L7/L9 ability data"
```

---

## Task 2: Character level + `extra_abilities` roster data (all 7 classes)

**Files:**
- Modify: `combat/resources/combatant.gd` (add fields near `ability_id`, ~line 35)
- Modify: `combat/resources/character_class.gd` (add export + copy in `build_combatant`)
- Modify: `combat/class_library.gd` (add `extra_abilities` to all 7 `match` branches)
- Test: `tests/test_character_level.gd`

**Interfaces:**
- Consumes: `AbilityDef` (Task 1).
- Produces: `Combatant.level: int`, `Combatant.extra_abilities: Array[AbilityDef]`,
  `Combatant.unlocked_extra_abilities() -> Array[AbilityDef]`, `Combatant.find_extra_ability(id: StringName) -> AbilityDef`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var c: Combatant = Combatant.new()
	c.level = 5
	var a5: AbilityDef = AbilityDef.new(); a5.id = &"a5"; a5.unlock_level = 5
	var a7: AbilityDef = AbilityDef.new(); a7.id = &"a7"; a7.unlock_level = 7
	var a9: AbilityDef = AbilityDef.new(); a9.id = &"a9"; a9.unlock_level = 9
	c.extra_abilities = [a5, a7, a9]
	var unlocked: Array[AbilityDef] = c.unlocked_extra_abilities()
	_check(unlocked.size() == 1 and unlocked[0].id == &"a5", "level 5 unlocks only a5")
	c.level = 9
	_check(c.unlocked_extra_abilities().size() == 3, "level 9 unlocks all three")
	_check(c.find_extra_ability(&"a7").cost == 2, "find_extra_ability returns the def (default cost 2)")
	_check(c.find_extra_ability(&"nope") == null, "find_extra_ability null for unknown id")

	var cc: CharacterClass = ClassLibrary.make(&"warrior")
	_check(cc.extra_abilities.size() == 3, "Warrior has 3 extra_abilities authored")
	var pc: Combatant = cc.build_combatant(true)
	_check(pc.extra_abilities.size() == 3, "build_combatant copies extra_abilities")
	_check(pc.level == 1, "build_combatant defaults level to 1")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_character_level.gd`
Expected: FAIL — `Combatant` has no `level`/`extra_abilities`/`unlocked_extra_abilities`.

- [ ] **Step 3: Write minimal implementation**

In `combat/resources/combatant.gd`, immediately after the existing `ultimate_id` field (~line 43):

```gdscript
## Character level — gates extra_abilities (spec 2026-07-01). Default 1 = only the L1 base ability
## + nothing extra. NOT a real progression system yet (no XP) — a test/tester knob until the
## design-bible leveling system lands.
var level: int = 1

## The class's 3 NEW (L5/L7/L9) abilities, parallel to the single ability_id (untouched — plan
## "Corrections to the locked spec" §1). Empty for a combatant with no extra kit (e.g. enemies).
var extra_abilities: Array[AbilityDef] = []

## cooldown_turns remaining per extra-ability id, decremented in on_upkeep (Task 3).
var cooldowns: Dictionary = {}
```

Add these two methods near `unlocked_ability_ids`-adjacent effect helpers (after `cleanse()`, ~line 318):

```gdscript
## The extra_abilities unlocked at this combatant's current level, in authored order.
func unlocked_extra_abilities() -> Array[AbilityDef]:
	return extra_abilities.filter(func(a: AbilityDef) -> bool: return a != null and level >= a.unlock_level)

## The extra_abilities entry with [param id], or null if not present (locked or nonexistent).
func find_extra_ability(id: StringName) -> AbilityDef:
	for a: AbilityDef in extra_abilities:
		if a != null and a.id == id:
			return a
	return null
```

In `combat/resources/character_class.gd`, after the existing `ultimate_id` export (~line 53):

```gdscript
## The class's 3 NEW abilities (L5/L7/L9), parallel to ability_id (spec 2026-07-01). Authored per
## class in ClassLibrary.
@export var extra_abilities: Array[AbilityDef] = []
```

And in `build_combatant()` (~line 73, right after `c.ultimate_id = ultimate_id`):

```gdscript
	c.extra_abilities = extra_abilities.duplicate()
```

In `combat/class_library.gd`, add one line to each of the 7 `match` branches (placed right after
that class's existing `c.ability_id = ...; c.ability_cost = ...` lines). Full roster data (costs/
levels/cooldowns per the locked spec §4; magnitudes are handled by the per-ability tasks, not here):

```gdscript
			&"warrior":
				# ... existing lines unchanged ...
				c.extra_abilities = [
					_ability(&"sundering_strike", 5, 3, &"stamina", 0),
					_ability(&"heroic_guard", 7, 3, &"stamina", 0),
					_ability(&"second_wind", 9, 5, &"stamina", 4),
				]
				return c
			&"vanguard":
				# ... existing lines unchanged ...
				c.extra_abilities = [
					_ability(&"bloodwrath", 5, 3, &"stamina", 0),
					_ability(&"quake_slam", 7, 4, &"stamina", 0),
					_ability(&"mountain_stance", 9, 5, &"stamina", 4),
				]
				return c
			&"skirmisher":
				# ... existing lines unchanged ...
				c.extra_abilities = [
					_ability(&"feint_riposte", 5, 3, &"stamina", 0),
					_ability(&"quickstep", 7, 3, &"stamina", 0),
					_ability(&"riposte_storm", 9, 4, &"stamina", 3),
				]
				return c
			&"chancer":
				# ... existing lines unchanged ...
				c.extra_abilities = [
					_ability(&"loaded_dice", 5, 3, &"stamina", 0),
					_ability(&"jinx_the_odds", 7, 3, &"stamina", 0),
					_ability(&"double_or_nothing", 9, 0, &"stamina", 7),  # cost computed at cast time (Task 24)
				]
				return c
			&"ranger":
				# ... existing lines unchanged ...
				c.extra_abilities = [
					_ability(&"aimed_shot", 5, 3, &"stamina", 0),
					_ability(&"snare_trap", 7, 4, &"stamina", 0),
					_ability(&"crippling_shot", 9, 5, &"stamina", 3),
				]
				return c
			&"seer":
				# ... existing lines unchanged ...
				c.extra_abilities = [
					_ability(&"hex", 5, 4, &"mana", 0),
					_ability(&"foresight", 7, 4, &"mana", 0),
					_ability(&"mana_surge", 9, 6, &"mana", 4),
				]
				return c
			&"warden":
				# ... existing lines unchanged ...
				c.extra_abilities = [
					_ability(&"entangle", 5, 4, &"mana", 0),
					_ability(&"regrowth", 7, 4, &"mana", 0),
					_ability(&"bastion", 9, 6, &"mana", 4),
				]
				return c
```

And a small private helper above `make()` in the same file:

```gdscript
static func _ability(id: StringName, unlock_level: int, cost: int, resource: StringName, cooldown_turns: int) -> AbilityDef:
	var a: AbilityDef = AbilityDef.new()
	a.id = id; a.unlock_level = unlock_level; a.cost = cost; a.resource = resource; a.cooldown_turns = cooldown_turns
	return a
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_character_level.gd`
Expected: five "ok" lines.

- [ ] **Step 5: Run full regression**

Run every existing test under `tests/` (or the project's existing batch-run command) and confirm all
69 prior suites are still green — `class_library.gd` and `character_class.gd` changes are additive
but touch every class branch, so this is the highest-risk-of-regression step in the whole plan.

- [ ] **Step 6: Commit**

```bash
git add combat/resources/combatant.gd combat/resources/character_class.gd combat/class_library.gd tests/test_character_level.gd
git commit -m "feat(abilities): add character level + extra_abilities roster data for all 7 classes"
```

---

## Task 3: Cooldowns + `MainPhasePlan` extra-ability staging scaffold

**Files:**
- Modify: `combat/resources/combatant.gd` (`on_upkeep`, cooldown helpers)
- Modify: `combat/main_phase_plan.gd` (new staging slot, gating, mutual exclusivity)
- Test: `tests/test_ability_cooldown.gd`

**Interfaces:**
- Consumes: `Combatant.extra_abilities`/`unlocked_extra_abilities()`/`cooldowns` (Task 2).
- Produces: `Combatant.tick_cooldowns()`, `Combatant.is_on_cooldown(id) -> bool`,
  `Combatant.start_cooldown(id, turns)`; `MainPhasePlan.staged_extra_ability_id: StringName`,
  `MainPhasePlan.toggle_extra_ability(id: StringName)`, `MainPhasePlan.can_stage_extra_ability(id: StringName) -> bool`.
  Later tasks (4+) add cases to `MainPhasePlan.commit()`'s extra-ability match and to
  `_extra_ability_adds_reel()` — both are created here as empty/false-returning stubs that only
  reference REAL ability ids from Task 2's data (never a placeholder id), so nothing here is dead
  code waiting on undefined behavior.

- [ ] **Step 1: Write the failing test**

```gdscript
extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var c: Combatant = Combatant.new()
	c.level = 9
	c.resource_pool = ResourcePool.new()
	c.resource_pool.stamina = 5; c.resource_pool.max_stamina = 5
	var a: AbilityDef = AbilityDef.new(); a.id = &"second_wind"; a.unlock_level = 9; a.cost = 5; a.resource = &"stamina"; a.cooldown_turns = 4
	c.extra_abilities = [a]

	_check(not c.is_on_cooldown(&"second_wind"), "not on cooldown initially")
	c.start_cooldown(&"second_wind", 4)
	_check(c.is_on_cooldown(&"second_wind"), "on cooldown after start_cooldown")
	for i in range(3):
		c.tick_cooldowns()
	_check(c.is_on_cooldown(&"second_wind"), "still on cooldown after 3 ticks (started at 4)")
	c.tick_cooldowns()
	_check(not c.is_on_cooldown(&"second_wind"), "off cooldown after the 4th tick")

	var plan: MainPhasePlan = MainPhasePlan.new(c)
	_check(plan.can_stage_extra_ability(&"second_wind"), "stageable: unlocked, affordable, no CD")
	c.start_cooldown(&"second_wind", 4)
	_check(not plan.can_stage_extra_ability(&"second_wind"), "not stageable while on cooldown")
	c.cooldowns.clear()
	c.level = 1
	_check(not plan.can_stage_extra_ability(&"second_wind"), "not stageable below unlock level")
	c.level = 9
	plan.toggle_extra_ability(&"second_wind")
	_check(plan.staged_extra_ability_id == &"second_wind", "toggle stages the extra ability")
	plan.toggle_ability()  # staging the (empty) base ability slot must clear the extra slot
	_check(plan.staged_extra_ability_id == &"", "staging the base ability clears the extra slot")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_cooldown.gd`
Expected: FAIL — none of the new methods exist yet.

- [ ] **Step 3: Write minimal implementation**

In `combat/resources/combatant.gd`, add near the effect helpers:

```gdscript
## True while [param id] still has cooldown turns remaining.
func is_on_cooldown(id: StringName) -> bool:
	return int(cooldowns.get(id, 0)) > 0

## Sets a fresh cooldown of [param turns] on ability [param id] (overwrites, never stacks).
func start_cooldown(id: StringName, turns: int) -> void:
	if turns > 0:
		cooldowns[id] = turns

## Decrements every tracked cooldown by one bearer-turn, dropping entries that reach 0.
func tick_cooldowns() -> void:
	var next: Dictionary = {}
	for id in cooldowns:
		var remaining: int = int(cooldowns[id]) - 1
		if remaining > 0:
			next[id] = remaining
	cooldowns = next
```

In `on_upkeep()` (~line 485), add the tick alongside the existing regen call:

```gdscript
func on_upkeep() -> void:
	if resource_pool != null:
		resource_pool.regen()
	tick_cooldowns()
	recompute_initiative()
```

In `combat/main_phase_plan.gd`, add a field near `ability_staged` (~line 39):

```gdscript
## The currently-staged NEW (L5/L7/L9) ability id, or "" for none. Mutually exclusive with
## [member ability_staged] — staging one clears the other (spec 2026-07-01).
var staged_extra_ability_id: StringName = &""
```

Add these methods after `can_stage_ability()` (~line 75):

```gdscript
## True if [param id] can be newly staged: unlocked at this combatant's level, affordable on its
## rail, and not on cooldown. Un-staging (passing the already-staged id to toggle) is always allowed.
func can_stage_extra_ability(id: StringName) -> bool:
	if combatant == null or combatant.resource_pool == null:
		return false
	var def: AbilityDef = combatant.find_extra_ability(id)
	if def == null or combatant.level < def.unlock_level:
		return false
	if combatant.is_on_cooldown(id):
		return false
	return combatant.resource_pool.can_afford({def.resource: def.cost})

func toggle_extra_ability(id: StringName) -> void:
	if staged_extra_ability_id == id:
		staged_extra_ability_id = &""
	elif can_stage_extra_ability(id):
		staged_extra_ability_id = id
		ability_staged = false  # mutually exclusive with the base ability slot
```

And make the existing `toggle_ability()` clear the new slot (edit its body, ~line 117):

```gdscript
func toggle_ability() -> void:
	if ability_is_free() or ability_locked_by_ultimate():
		return
	if ability_staged:
		ability_staged = false
		selected_fate_type = null
	elif ability_id == &"select_fate":
		return
	elif can_stage_ability():
		ability_staged = true
		staged_extra_ability_id = &""  # mutually exclusive with an extra-ability slot
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_cooldown.gd`
Expected: eight "ok" lines.

- [ ] **Step 5: Commit**

```bash
git add combat/resources/combatant.gd combat/main_phase_plan.gd tests/test_ability_cooldown.gd
git commit -m "feat(abilities): cooldown tracking + extra-ability staging scaffold"
```

---

## Task 4: Effect resource extensions (immunity, thorns, stun-immunity, incoming/outgoing flag)

**Files:**
- Modify: `combat/resources/effect.gd`
- Modify: `combat/resources/combatant.gd` (`attach_effect` guard, `evaluate_stun` guard)
- Test: `tests/test_effect_immunity.gd`

**Interfaces:**
- Produces: `Effect.immune_effect_ids: Array[StringName]`, `Effect.thorns_pct: float`,
  `Effect.affects_incoming: bool`, `Effect.grants_stun_immunity: bool`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var c: Combatant = Combatant.new()
	var guard: Effect = Effect.new()
	guard.id = &"mountain_stance"; guard.kind = Effect.Kind.MULTIPLIER_EDIT; guard.magnitude = 0.5
	guard.duration = 3; guard.beneficial = true
	guard.immune_effect_ids = [&"slow", &"rooted"]
	guard.grants_stun_immunity = true
	c.attach_effect(guard)

	var slow: Effect = EffectLibrary.make(&"slow")
	c.attach_effect(slow)
	_check(not c.has_effect(&"slow"), "immune_effect_ids blocks slow while active")

	c.base_initiative = 0
	c.stunned_last_turn = false
	var stunned: bool = c.evaluate_stun(50)
	_check(not stunned, "grants_stun_immunity blocks evaluate_stun even with low initiative")

	c.active_effects.clear()  # immunity gone
	c.attach_effect(EffectLibrary.make(&"slow"))
	_check(c.has_effect(&"slow"), "slow attaches normally once immunity is gone")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_effect_immunity.gd`
Expected: FAIL — `Effect` has no `immune_effect_ids`/`grants_stun_immunity`; nothing blocks the attach.

- [ ] **Step 3: Write minimal implementation**

In `combat/resources/effect.gd`, add after `dot_fractions` (~line 43):

```gdscript
## While this effect is active on a bearer, [method Combatant.attach_effect] refuses to attach any
## incoming effect whose id is in this list. Powers e.g. Mountain Stance's CC immunity. Empty = no
## immunity granted. [ASSUMPTION] data — authored per effect.
@export var immune_effect_ids: Array[StringName] = []

## While active, [param 1 - thorns_pct] ... i.e. an attacker who damages this bearer takes back
## thorns_pct of the damage dealt, same type (Task 6). 0 = no thorns. [ASSUMPTION] data.
@export var thorns_pct: float = 0.0

## MULTIPLIER_EDIT only: false (default) = an OUTGOING multiplier the bearer applies when IT is the
## attacker (Empowered/Bloodwrath). true = an INCOMING multiplier applied when the bearer is the
## DEFENDER (Sundered/Guarded). See Combatant.outgoing_damage_multiplier / incoming_damage_multiplier.
@export var affects_incoming: bool = false

## STUNNED is a per-turn bool condition, not an attached Effect (see Combatant.stunned_this_turn) —
## immune_effect_ids can't block it. This flag lets a buff (Mountain Stance) suppress it directly;
## checked in Combatant.evaluate_stun.
@export var grants_stun_immunity: bool = false
```

In `combat/resources/combatant.gd`, edit `attach_effect()` (~line 274) to check immunity before the
existing merge-by-id logic:

```gdscript
func attach_effect(effect: Effect) -> void:
	if effect == null:
		return
	for active: Effect in active_effects:
		if active != null and effect.id in active.immune_effect_ids:
			return  # an active immunity (Mountain Stance) blocks this attach entirely
	var existing: Effect = _find_effect(effect.id)
	# ... rest unchanged ...
```

Edit `evaluate_stun()` (~line 505) to check immunity right after consuming the forced flag:

```gdscript
func evaluate_stun(threshold: int) -> bool:
	var forced: bool = force_stun_next_turn
	force_stun_next_turn = false
	for e: Effect in active_effects:
		if e != null and e.grants_stun_immunity:
			stunned_this_turn = false
			return false
	var by_initiative: bool = current_initiative < threshold and not stunned_last_turn
	stunned_this_turn = forced or by_initiative
	return stunned_this_turn
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_effect_immunity.gd`
Expected: three "ok" lines.

- [ ] **Step 5: Run regression**

Re-run `test_bleed.gd`, `test_enemy_ai.gd` and any other existing effect/stun tests to confirm the
new immunity/stun-immunity checks are no-ops when nothing grants them (both default to
empty/false, so pre-existing behavior is unchanged).

- [ ] **Step 6: Commit**

```bash
git add combat/resources/effect.gd combat/resources/combatant.gd tests/test_effect_immunity.gd
git commit -m "feat(effects): add immunity, thorns, and stun-immunity fields to Effect"
```

---

## Task 5: Outgoing/incoming damage-multiplier hook

**Files:**
- Modify: `combat/resources/combatant.gd`
- Modify: `combat/combat_resolver.gd`
- Modify: `combat/combat.gd` (the `resolve_combat_phase` call site)
- Test: `tests/test_damage_multiplier.gd`

**Interfaces:**
- Consumes: `Effect.affects_incoming` (Task 4).
- Produces: `Combatant.outgoing_damage_multiplier() -> float`, `Combatant.incoming_damage_multiplier() -> float`,
  `CombatResolver.resolve_combat_phase(..., damage_multiplier: float = 1.0)`,
  `CombatResolver._resolve_single(..., damage_multiplier: float = 1.0)`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var c: Combatant = Combatant.new()
	_check(is_equal_approx(c.outgoing_damage_multiplier(), 1.0), "no effects -> outgoing 1.0")
	_check(is_equal_approx(c.incoming_damage_multiplier(), 1.0), "no effects -> incoming 1.0")

	var emp: Effect = Effect.new()
	emp.id = &"empowered"; emp.kind = Effect.Kind.MULTIPLIER_EDIT; emp.magnitude = 1.5
	emp.affects_incoming = false; emp.beneficial = true; emp.duration = 2
	c.attach_effect(emp)
	_check(is_equal_approx(c.outgoing_damage_multiplier(), 1.5), "empowered raises outgoing to 1.5")
	_check(is_equal_approx(c.incoming_damage_multiplier(), 1.0), "empowered does not affect incoming")

	var guard: Effect = Effect.new()
	guard.id = &"guarded"; guard.kind = Effect.Kind.MULTIPLIER_EDIT; guard.magnitude = 0.5
	guard.affects_incoming = true; guard.beneficial = true; guard.duration = 2
	c.attach_effect(guard)
	_check(is_equal_approx(c.incoming_damage_multiplier(), 0.5), "guarded halves incoming")

	var resolver: CombatResolver = CombatResolver.new()
	var reel: ActionReel = ActionReel.new()
	reel.faces = [ReelFace.new()]
	reel.faces[0].result_tier = ReelFace.ResultTier.SUCCESS
	reel.faces[0].multiplier = 1.0
	var attack: CombatResolver.AttackResult = resolver._resolve_single(reel, 10.0, null, false, 0, 2.0)
	_check(attack.final_damage == 20, "damage_multiplier 2.0 doubles a 10-base success hit")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_damage_multiplier.gd`
Expected: FAIL — none of the multiplier methods/params exist.

- [ ] **Step 3: Write minimal implementation**

In `combat/resources/combatant.gd`, add near `recompute_initiative()`:

```gdscript
## Product of every active OUTGOING MULTIPLIER_EDIT effect's magnitude (Empowered, Bloodwrath).
## 1.0 (neutral) when none are active.
func outgoing_damage_multiplier() -> float:
	var total: float = 1.0
	for e: Effect in active_effects:
		if e != null and e.kind == Effect.Kind.MULTIPLIER_EDIT and not e.affects_incoming:
			total *= e.effective_magnitude()
	return total

## Product of every active INCOMING MULTIPLIER_EDIT effect's magnitude (Sundered raises it, Guarded
## lowers it). 1.0 (neutral) when none are active.
func incoming_damage_multiplier() -> float:
	var total: float = 1.0
	for e: Effect in active_effects:
		if e != null and e.kind == Effect.Kind.MULTIPLIER_EDIT and e.affects_incoming:
			total *= e.effective_magnitude()
	return total
```

Note: `Effect.effective_magnitude()` already exists (effect.gd:59) and returns flat `magnitude` for
non-stacking effects (every effect this plan adds is non-stacking except the two already-stacking
DoTs), so it slots in with no change to that method.

In `combat/combat_resolver.gd`, add the `source_reel` field to `AttackResult` (~line 17) and thread
`damage_multiplier` through both resolve functions:

```gdscript
class AttackResult:
	var face: ReelFace
	var damage_type: DamageType
	var base_damage: float = 0.0
	var final_damage: int = 0
	var meter_gain: int = 0
	var rider_effect_id: StringName = &""
	var landed_index: int = -1
	var charges_meter: bool = true
	var source_reel: ActionReel = null  # Task 8/15: lets the orchestrator special-case one reel's ability
```

```gdscript
func resolve_combat_phase(reels: Array[ActionReel], base_damage: float, target_type: DamageType = null, wild_reel_indices: Array[int] = [], weapon_reel_count: int = -1, flat_damage_bonus: int = 0, extra_lines: Array = [], defer_paylines: bool = false, damage_multiplier: float = 1.0) -> Array[AttackResult]:
	spin_started.emit()
	var attacks: Array[AttackResult] = []
	var total_meter: int = 0
	for i: int in range(reels.size()):
		var is_wild: bool = i in wild_reel_indices
		var attack: AttackResult = _resolve_single(reels[i], base_damage, target_type, is_wild, flat_damage_bonus, damage_multiplier)
		total_meter += attack.meter_gain
		attacks.append(attack)
		damage_applied.emit(attack)
	# ... rest unchanged ...
```

```gdscript
func _resolve_single(reel: ActionReel, base_damage: float, target_type: DamageType, is_wild: bool = false, flat_damage_bonus: int = 0, damage_multiplier: float = 1.0) -> AttackResult:
	var face: ReelFace
	var index: int
	if is_wild and randf() < WILD_CRIT_CHANCE:
		face = _crit_face(reel)
		index = reel.faces.find(face)
	else:
		face = reel.spin()
		index = reel.get_last_index()

	var attack: AttackResult = AttackResult.new()
	attack.face = face
	attack.damage_type = reel.damage_type
	attack.base_damage = base_damage
	attack.landed_index = index
	attack.charges_meter = reel.charges_meter
	attack.source_reel = reel

	if face != null:
		if face.deals_damage() and face.multiplier > 0.0:
			var raw: float = base_damage * face.multiplier
			var type_mult: float = reel.damage_type.multiplier_against(target_type) if reel.damage_type != null else 1.0
			attack.final_damage = ceili(raw * type_mult * damage_multiplier) + flat_damage_bonus
		attack.meter_gain = _meter_gain_for(face.result_tier) if reel.charges_meter else 0
		if face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS and reel.damage_type != null and reel.damage_type.inherent_rider_id != &"":
			attack.rider_effect_id = reel.damage_type.inherent_rider_id
		if face.rider_effect_id != &"" and (face.result_tier == ReelFace.ResultTier.SUCCESS or face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS):
			attack.rider_effect_id = face.rider_effect_id
	return attack
```

Also update `reresolve_reel()`'s call to `_resolve_single` to pass a trailing `1.0` (no change in
behavior — re-rolls don't currently interact with multipliers):

```gdscript
func reresolve_reel(reel: ActionReel, base_damage: float, target_type: DamageType, flat_damage_bonus: int = 0) -> AttackResult:
	return _resolve_single(reel, base_damage, target_type, false, flat_damage_bonus, 1.0)
```

In `combat/combat.gd`, find the `resolve_combat_phase(...)` call inside `_on_spin_pressed` and add
the multiplier argument (attacker's outgoing × defender's incoming):

```gdscript
	var dmg_mult: float = _attacker.outgoing_damage_multiplier() * _defender.incoming_damage_multiplier()
	# ... existing call, with damage_multiplier: dmg_mult appended as the trailing argument ...
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_damage_multiplier.gd`
Expected: five "ok" lines.

- [ ] **Step 5: Run regression**

Run `test_combat_roles.gd`, `test_enemy_combat_actions.gd`, and any resolver-touching suite —
`damage_multiplier` defaults to `1.0` everywhere it isn't explicitly passed, so undamaged paths
must show byte-identical output.

- [ ] **Step 6: Commit**

```bash
git add combat/resources/combatant.gd combat/combat_resolver.gd combat/combat.gd tests/test_damage_multiplier.gd
git commit -m "feat(combat): wire MULTIPLIER_EDIT effects into damage resolution"
```

---

## Task 6: Thorns reflection hook

**Files:**
- Modify: `combat/combat.gd` (`_apply_attack`)
- Test: `tests/test_effect_thorns.gd`

**Interfaces:**
- Consumes: `Effect.thorns_pct` (Task 4).
- Produces: `Combatant.thorns_pct() -> float` (max active thorns_pct, 0.0 if none).

- [ ] **Step 1: Write the failing test**

```gdscript
extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var c: Combatant = Combatant.new()
	_check(is_equal_approx(c.thorns_pct(), 0.0), "no effects -> 0 thorns")
	var bastion: Effect = Effect.new()
	bastion.id = &"guarded"; bastion.kind = Effect.Kind.MULTIPLIER_EDIT; bastion.magnitude = 0.5
	bastion.affects_incoming = true; bastion.beneficial = true; bastion.duration = 3
	bastion.thorns_pct = 0.2
	c.attach_effect(bastion)
	_check(is_equal_approx(c.thorns_pct(), 0.2), "guarded-with-thorns reports 0.2")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_effect_thorns.gd`
Expected: FAIL — `thorns_pct()` doesn't exist.

- [ ] **Step 3: Write minimal implementation**

In `combat/resources/combatant.gd`, add next to `incoming_damage_multiplier()`:

```gdscript
## The highest thorns_pct among active effects, or 0.0 if none carry it (Bastion, Task 22).
func thorns_pct() -> float:
	var best: float = 0.0
	for e: Effect in active_effects:
		if e != null and e.thorns_pct > best:
			best = e.thorns_pct
	return best
```

In `combat/combat.gd`'s `_apply_attack()`, right after the existing `t.take_damage(attack.final_damage)`
loop (~line 1258), add the reflection (only meaningful in the single-target, non-AoE case — an AoE
spin already fans out `_apply_attack` per attack, and `_attacker` here is always well-defined):

```gdscript
	if attack.final_damage > 0:
		for t: Combatant in targets:
			t.take_damage(attack.final_damage)
			var thorns: float = t.thorns_pct()
			if thorns > 0.0 and _attacker.is_alive():
				var reflected: int = ceili(attack.final_damage * thorns)
				_attacker.take_damage(reflected)
				_log("  🌵 %s's thorns reflect %d %s back to %s." % [t.display_name, reflected, _type_name(attack.damage_type), _attacker.display_name])
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_effect_thorns.gd`
Expected: two "ok" lines.

- [ ] **Step 5: Commit**

```bash
git add combat/resources/combatant.gd combat/combat.gd tests/test_effect_thorns.gd
git commit -m "feat(combat): add thorns damage-reflection hook"
```

---

## Task 7: 11 new shared effects in `EffectLibrary`

**Files:**
- Modify: `combat/effect_library.gd`
- Test: `tests/test_new_effects.gd`

**Interfaces:**
- Produces: `EffectLibrary.make()` cases for `&"sundered"`, `&"weakened"`, `&"jinxed"`, `&"rooted"`,
  `&"guarded"`, `&"taunt"`, `&"empowered"`, `&"evasion"`, `&"regen"`, `&"cursed"`, `&"haste"`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var ids: Array[StringName] = [&"sundered", &"weakened", &"jinxed", &"rooted", &"guarded", &"taunt", &"empowered", &"evasion", &"regen", &"cursed", &"haste"]
	for id in ids:
		var e: Effect = EffectLibrary.make(id)
		_check(e != null, "EffectLibrary.make(%s) returns non-null" % id)
		_check(e.id == id, "%s: id round-trips" % id)

	var sundered: Effect = EffectLibrary.make(&"sundered")
	_check(sundered.kind == Effect.Kind.MULTIPLIER_EDIT and sundered.affects_incoming and not sundered.beneficial, "sundered: incoming debuff multiplier")
	var guarded: Effect = EffectLibrary.make(&"guarded")
	_check(guarded.kind == Effect.Kind.MULTIPLIER_EDIT and guarded.affects_incoming and guarded.beneficial, "guarded: incoming buff multiplier")
	var empowered: Effect = EffectLibrary.make(&"empowered")
	_check(empowered.kind == Effect.Kind.MULTIPLIER_EDIT and not empowered.affects_incoming and empowered.beneficial, "empowered: outgoing buff multiplier")
	var rooted: Effect = EffectLibrary.make(&"rooted")
	_check(rooted.kind == Effect.Kind.INITIATIVE_MOD and rooted.magnitude < -20.0, "rooted: heavier init hit than slow tier 1")
	var haste: Effect = EffectLibrary.make(&"haste")
	_check(haste.kind == Effect.Kind.INITIATIVE_MOD and haste.magnitude > 0.0 and haste.beneficial, "haste: positive init, beneficial")
	var regen: Effect = EffectLibrary.make(&"regen")
	_check(regen.kind == Effect.Kind.DAMAGE_OVER_TIME and regen.beneficial, "regen: beneficial DoT (heal)")
	var cursed: Effect = EffectLibrary.make(&"cursed")
	_check(cursed.kind == Effect.Kind.DAMAGE_OVER_TIME and not cursed.beneficial, "cursed: debuff DoT")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_new_effects.gd`
Expected: FAIL — `EffectLibrary.make()` returns null for all 11 new ids.

- [ ] **Step 3: Write minimal implementation**

In `combat/effect_library.gd`, add 11 new branches to the `match id:` in `make()`, before the final
`_:` fallback:

```gdscript
		&"sundered":
			var e: Effect = Effect.new()
			e.id = &"sundered"; e.kind = Effect.Kind.MULTIPLIER_EDIT; e.magnitude = 1.25
			e.affects_incoming = true; e.duration = 2; e.beneficial = false
			return e
		&"weakened":
			var e: Effect = Effect.new()
			e.id = &"weakened"; e.kind = Effect.Kind.MULTIPLIER_EDIT; e.magnitude = 0.75
			e.affects_incoming = false; e.duration = 2; e.beneficial = false
			return e
		&"jinxed":
			# Downgrades the BEARER's own success/crit-success faces (applied by the attacker's-turn
			# orchestrator check, mirroring Hunter's Mark's REEL_FACE_EDIT precedent — no numeric payload).
			var e: Effect = Effect.new()
			e.id = &"jinxed"; e.kind = Effect.Kind.REEL_FACE_EDIT; e.duration = 2; e.beneficial = false
			return e
		&"rooted":
			var e: Effect = Effect.new()
			e.id = &"rooted"; e.kind = Effect.Kind.INITIATIVE_MOD; e.magnitude = -30.0
			e.duration = 2; e.max_stacks = 1; e.beneficial = false
			return e
		&"guarded":
			var e: Effect = Effect.new()
			e.id = &"guarded"; e.kind = Effect.Kind.MULTIPLIER_EDIT; e.magnitude = 0.75
			e.affects_incoming = true; e.duration = 2; e.beneficial = true
			return e
		&"taunt":
			# Pure marker (mirrors hunters_mark's "kind chosen loosely" precedent) — read via has_effect
			# by EnemyAI (Task 10), never edits a face.
			var e: Effect = Effect.new()
			e.id = &"taunt"; e.kind = Effect.Kind.REEL_FACE_EDIT; e.duration = 2; e.beneficial = true
			return e
		&"empowered":
			var e: Effect = Effect.new()
			e.id = &"empowered"; e.kind = Effect.Kind.MULTIPLIER_EDIT; e.magnitude = 1.4
			e.affects_incoming = false; e.duration = 2; e.beneficial = true
			return e
		&"evasion":
			var e: Effect = Effect.new()
			e.id = &"evasion"; e.kind = Effect.Kind.REEL_FACE_EDIT; e.duration = 2; e.beneficial = true
			return e
		&"regen":
			var e: Effect = Effect.new()
			e.id = &"regen"; e.kind = Effect.Kind.DAMAGE_OVER_TIME; e.duration = 3
			e.max_stacks = 3; e.dot_fractions = [0.50, 0.80, 1.15]; e.beneficial = true
			return e
		&"cursed":
			var e: Effect = Effect.new()
			e.id = &"cursed"; e.kind = Effect.Kind.DAMAGE_OVER_TIME; e.duration = 3
			e.max_stacks = 3; e.dot_fractions = [0.50, 0.80, 1.15]; e.beneficial = false
			return e
		&"haste":
			var e: Effect = Effect.new()
			e.id = &"haste"; e.kind = Effect.Kind.INITIATIVE_MOD; e.magnitude = 20.0
			e.duration = 2; e.beneficial = true
			return e
```

Note: `regen`/`cursed`'s `dot_damage()` returns a POSITIVE number regardless of `beneficial` (effect.gd:71-75
has no beneficial branch) — Task 21 (Regrowth) and Task 16 (Hex) must call `heal()` vs `take_damage()`
respectively based on `beneficial`, not assume `_apply_dot` (combat.gd:910) handles it. Check
`combat.gd:910-918`'s `_apply_dot` in Task 16/21 and extend it to branch on `e.beneficial` (heal
instead of damage) — this is shared plumbing, implement it once in Task 16 (the first DoT consumer)
and reuse for Task 21.

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_new_effects.gd`
Expected: 18 "ok" lines.

- [ ] **Step 5: Commit**

```bash
git add combat/effect_library.gd tests/test_new_effects.gd
git commit -m "feat(effects): add 11 shared effects (sundered/weakened/jinxed/rooted/guarded/taunt/empowered/evasion/regen/cursed/haste)"
```

---

## Task 8: `ActionReel.make_rider_attack()` factory

**Files:**
- Modify: `combat/resources/action_reel.gd`
- Test: `tests/test_rider_attack_reel.gd`

**Interfaces:**
- Produces: `ActionReel.make_rider_attack(type: DamageType, rider_id: StringName, bonus_vs_cc: bool = false) -> ActionReel`.
  Unlike `make_rend` (multiplier zeroed, `is_weapon_attack = false`), this factory keeps REAL
  weapon damage on hit faces AND attaches a rider — for abilities that are a genuine attack, not a
  pure debuff-applicator (Sundering Strike, Quake Slam, Jinx the Odds, Snare Trap, Crippling Shot,
  Hex, Entangle — 7 of the plan's 21 new abilities; Riposte Storm uses the multiplier hook instead,
  see Task 17).

- [ ] **Step 1: Write the failing test**

```gdscript
extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var reel: ActionReel = ActionReel.make_rider_attack(null, &"sundered")
	_check(reel.is_weapon_attack, "make_rider_attack reel joins paylines (unlike Rend)")
	var hit_count: int = 0
	for f: ReelFace in reel.faces:
		if f.result_tier == ReelFace.ResultTier.SUCCESS or f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
			hit_count += 1
			_check(f.multiplier > 0.0, "hit face keeps real damage multiplier")
			_check(f.rider_effect_id == &"sundered", "hit face carries the requested rider")
	_check(hit_count == 5, "5 hit faces (4 success + 1 crit-success), matching DEFAULT_COMPOSITION")

	var cc_reel: ActionReel = ActionReel.make_rider_attack(null, &"weakened", true)
	_check(cc_reel.bonus_vs_cc, "bonus_vs_cc flag set when requested")
	var plain_reel: ActionReel = ActionReel.make_rider_attack(null, &"rooted")
	_check(not plain_reel.bonus_vs_cc, "bonus_vs_cc defaults false")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_rider_attack_reel.gd`
Expected: FAIL — `make_rider_attack` and `bonus_vs_cc` don't exist.

- [ ] **Step 3: Write minimal implementation**

In `combat/resources/action_reel.gd`, add the field near `charges_meter` (~line 30):

```gdscript
## True only for the Ranger's Crippling Shot reel (Task 15): the orchestrator adds bonus damage
## when this reel's hit lands on a target that's Slowed/Rooted/Stunned. False for every other reel.
@export var bonus_vs_cc: bool = false
```

And the factory after `make_rend()` (~line 69):

```gdscript
## Builds a real weapon-attack reel (same tier spread as make_default — the reel IS the dice, no
## odds change) whose SUCCESS/CRIT_SUCCESS faces ALSO carry [param rider_id]. Unlike make_rend
## (multiplier zeroed, utility-only), this keeps real damage: the attack itself both hits AND
## applies its rider on a hit. Used by Sundering Strike / Quake Slam / Jinx the Odds / Snare Trap /
## Hex / Entangle / Crippling Shot (spec 2026-07-01 §4).
static func make_rider_attack(type: DamageType, rider_id: StringName, bonus_vs_cc: bool = false) -> ActionReel:
	var reel: ActionReel = make_default(type)
	reel.bonus_vs_cc = bonus_vs_cc
	for face: ReelFace in reel.faces:
		if face.result_tier == ReelFace.ResultTier.SUCCESS or face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
			face.rider_effect_id = rider_id
	return reel
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_rider_attack_reel.gd`
Expected: 13 "ok" lines (5 hit faces × 2 checks each + 3 top-level).

- [ ] **Step 5: Commit**

```bash
git add combat/resources/action_reel.gd tests/test_rider_attack_reel.gd
git commit -m "feat(reels): add make_rider_attack factory for real-damage-plus-rider reels"
```

---

## Task 9: `PaylineLibrary.bonus_line()` + `Combatant` Evasion/Riposte-charge plumbing

**Files:**
- Modify: `combat/payline_library.gd`
- Modify: `combat/resources/combatant.gd`
- Test: `tests/test_evasion_and_bonus_line.gd`

**Interfaces:**
- Produces: `PaylineLibrary.bonus_line(width: int) -> Array`, `Combatant.evasion_reels(reels: Array) -> Array[ActionReel]` (static),
  `Combatant.gain_riposte_charges(n: int) -> void`, `Combatant.riposte_charges: int`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var line: Array = PaylineLibrary.bonus_line(4)
	_check(line.size() == 4, "bonus_line(4) has 4 cells")
	_check(line[0] == Vector2i(0, 0) and line[1] == Vector2i(1, 2), "bonus_line alternates rows 0/2")
	for casino_pat in PaylineLibrary.casino_lines(4):
		_check(casino_pat != line, "bonus_line is distinct from every casino_lines(4) pattern")

	var attack_reel: ActionReel = ActionReel.make_default(null)
	var edited: Array[ActionReel] = Combatant.evasion_reels([attack_reel])
	var downgraded: bool = true
	for f: ReelFace in edited[0].faces:
		if f.result_tier == ReelFace.ResultTier.SUCCESS or f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
			downgraded = false
	_check(downgraded, "evasion_reels converts every success/crit-success face on a weapon-attack reel")
	_check(attack_reel.faces[0].result_tier != ReelFace.ResultTier.FAILURE or true, "original reel untouched (deep-copy)")

	var c: Combatant = Combatant.new()
	c.gain_riposte_charges(2)
	c.gain_riposte_charges(3)
	_check(c.riposte_charges == 5, "riposte charges accumulate")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_evasion_and_bonus_line.gd`
Expected: FAIL — none of these exist.

- [ ] **Step 3: Write minimal implementation**

In `combat/payline_library.gd`, add after `casino_lines()`:

```gdscript
## An extra alternating-row line (top/bottom/top/bottom...) not present in either lines_for() or
## casino_lines() — the Chancer's Loaded Dice (Task 20) lights this as its bonus payline.
static func bonus_line(width: int) -> Array:
	var line: Array = []
	for c: int in range(width):
		line.append(Vector2i(c, 0 if c % 2 == 0 else 2))
	return line
```

In `combat/resources/combatant.gd`, add the field near `hunters_mark_pending` (~line 121):

```gdscript
## Skirmisher Riposte Storm (Task 18) charge count: +1 per weapon-attack reel an enemy spins
## against this combatant while Evasion is active (spec 2026-07-01 §4). Reset to 0 on use.
var riposte_charges: int = 0

func gain_riposte_charges(n: int) -> void:
	riposte_charges += n
```

Add the static transform near `hunters_mark_reels()` (~line 419):

```gdscript
## Evasion (Skirmisher Feint & Riposte, Task 16) reel transform: returns a copy of [param reels] in
## which every WEAPON-ATTACK reel's SUCCESS/CRIT_SUCCESS faces are converted to a miss (FAILURE,
## multiplier 0) — the defender is too slippery to be hit clean. Mirrors hunters_mark_reels exactly
## (deep-copies only weapon-attack reels; utility reels pass through). Static + pure.
static func evasion_reels(reels: Array) -> Array[ActionReel]:
	var out: Array[ActionReel] = []
	for r: ActionReel in reels:
		if r != null and r.is_weapon_attack:
			var copy: ActionReel = r.duplicate(true)
			for f: ReelFace in copy.faces:
				if f.result_tier == ReelFace.ResultTier.SUCCESS or f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
					f.result_tier = ReelFace.ResultTier.FAILURE
					f.multiplier = 0.0
			out.append(copy)
		else:
			out.append(r)
	return out
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_evasion_and_bonus_line.gd`
Expected: all "ok" (20+ lines from the casino_lines loop + the fixed checks).

- [ ] **Step 5: Wire into the orchestrator (needed for Task 16 to matter — do now while context is fresh)**

In `combat/combat.gd`, find the existing Hunter's Mark reel-swap block (~line 1152:
`_attacker.turn_reels = Combatant.hunters_mark_reels(_attacker.turn_reels)`) and add a parallel
Evasion check right after it:

```gdscript
	if _defender.has_effect(&"evasion") and _attacker.is_player != _defender.is_player:
		var weapon_reel_count: int = 0
		for r: ActionReel in _attacker.turn_reels:
			if r.is_weapon_attack:
				weapon_reel_count += 1
		_defender.gain_riposte_charges(weapon_reel_count)
		_attacker.turn_reels = Combatant.evasion_reels(_attacker.turn_reels)
```

- [ ] **Step 6: Commit**

```bash
git add combat/payline_library.gd combat/resources/combatant.gd combat/combat.gd tests/test_evasion_and_bonus_line.gd
git commit -m "feat(combat): add Evasion reel transform, Riposte charge accrual, and payline bonus_line"
```

---

## Task 10: EnemyAI Taunt-awareness

**Files:**
- Modify: `combat/enemy_ai.gd`
- Test: `tests/test_enemy_ai_taunt.gd`

**Interfaces:**
- Consumes: `&"taunt"` effect (Task 7), `Combatant.has_effect()` (existing).
- Produces: updated `EnemyAI.pick_target()` behavior (signature unchanged).

- [ ] **Step 1: Write the failing test**

```gdscript
extends SceneTree

func _mk_pc(name: String, hp: int, def_type: DamageType) -> Combatant:
	var c: Combatant = Combatant.new()
	c.display_name = name; c.is_player = true
	c.defense_type = def_type; c.max_hp = hp; c.hp = hp
	return c

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")
	var attacker: Combatant = Combatant.new()
	attacker.weapon = Weapon.new()
	attacker.weapon.reels = [ActionReel.make_default(slashing)]

	var low_hp: Combatant = _mk_pc("Low", 10, slashing)
	var taunter: Combatant = _mk_pc("Taunter", 300, slashing)
	taunter.attach_effect(EffectLibrary.make(&"taunt"))
	var pcs: Array[Combatant] = [low_hp, taunter]

	var target: Combatant = EnemyAI.pick_target(attacker, pcs)
	_check(target == taunter, "AI targets the taunter even though another PC has lower HP")

	var t2: Combatant = _mk_pc("Taunter2", 50, slashing)
	t2.attach_effect(EffectLibrary.make(&"taunt"))
	target = EnemyAI.pick_target(attacker, [low_hp, taunter, t2])
	_check(target == t2, "among two taunters, existing lowest-HP tie-break still applies")

	var no_taunt: Array[Combatant] = [low_hp, _mk_pc("Other", 200, slashing)]
	target = EnemyAI.pick_target(attacker, no_taunt)
	_check(target == low_hp, "no taunters -> unchanged existing behavior")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_enemy_ai_taunt.gd`
Expected: FAIL on the first check — the AI currently ignores Taunt entirely.

- [ ] **Step 3: Write minimal implementation**

In `combat/enemy_ai.gd`, edit `pick_target()` to filter to taunters first:

```gdscript
static func pick_target(attacker: Combatant, pcs: Array[Combatant]) -> Combatant:
	if attacker == null or attacker.weapon_type() == null:
		return null
	var candidates: Array[Combatant] = []
	for pc: Combatant in pcs:
		if pc != null and pc.is_alive() and pc.has_effect(&"taunt"):
			candidates.append(pc)
	if candidates.is_empty():
		candidates = pcs
	var atk: DamageType = attacker.weapon_type()
	var supereff: Array[Combatant] = []
	var neutral: Array[Combatant] = []
	var resisted: Array[Combatant] = []
	for pc: Combatant in candidates:
		if pc == null or not pc.is_alive():
			continue
		var m: float = atk.multiplier_against(pc.defense_type)
		if m > 1.0 and not is_equal_approx(m, 1.0):
			supereff.append(pc)
		elif is_equal_approx(m, 1.0):
			neutral.append(pc)
		else:
			resisted.append(pc)
	var tier: Array[Combatant] = supereff if not supereff.is_empty() else (neutral if not neutral.is_empty() else resisted)
	return _lowest_hp(tier)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_enemy_ai_taunt.gd`
Expected: three "ok" lines.

- [ ] **Step 5: Run regression**

Run `test_enemy_ai.gd` (the pre-existing suite) to confirm the no-taunt path is byte-identical.

- [ ] **Step 6: Commit**

```bash
git add combat/enemy_ai.gd tests/test_enemy_ai_taunt.gd
git commit -m "feat(ai): prioritize Taunting PCs before the existing type/HP tiering"
```

---

## Tasks 11–31: the 21 new per-class abilities

**Shared shape.** All foundation infra (Tasks 1–10) is now in place. Each of the following tasks
follows the SAME five-step pattern: write a failing test against a new `Combatant` method (and, for
reel-adding abilities, a `MainPhasePlan` staging/commit case), implement it, verify, commit. To keep
this plan scannable, each task below states ONLY what differs: the method, its body, the
`MainPhasePlan` wiring it needs (if any), and its test assertions. Follow the exact test-file/step
scaffolding from Tasks 1–10 for the parts not restated (the `extends SceneTree` / `_check` header,
run/verify steps, commit step).

**`MainPhasePlan` wiring pattern (reel-adding abilities — Tasks 11, 13, 20, 23, 25, 28, 29):**
add one `&"<id>"` case to `preview_reels()`'s existing `if ability_staged and _ability_adds_reel()`
block is WRONG — that block is for the base ability. Instead add a NEW parallel block reading
`staged_extra_ability_id`, and a matching cap-check in `can_stage_extra_ability`. Because this
exact plumbing is shared by 7 of the 21 tasks, it is built ONCE here (Task 11) and each subsequent
reel-adding task just adds its own `match` arm to the same two functions.

---

### Task 11: Warrior L5 — Sundering Strike (+ the shared reel-adding `MainPhasePlan` plumbing)

**Files:** Modify `combat/resources/combatant.gd`, `combat/main_phase_plan.gd`; Test `tests/test_sundering_strike.gd`

- [ ] Combatant method (mirrors `try_rend_reel`, ~line 346):

```gdscript
## Warrior "Sundering Strike" (spec §4, L5): splices one [param type]-typed reel that deals REAL
## damage and applies SUNDERED on a hit (unlike Rend, which deals none). Respects the reel [param cap].
func try_sundering_strike(type: DamageType, cost: int, cap: int) -> bool:
	if turn_reels.size() >= cap:
		return false
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	turn_reels.append(ActionReel.make_rider_attack(type, &"sundered"))
	return true
```

- [ ] `MainPhasePlan` plumbing (new, generic to every reel-adding extra ability). Add a set constant
  and extend `can_stage_extra_ability`, `preview_reels`, and `commit`:

```gdscript
## Extra-ability ids that append a reel to this turn's loadout (mirrors _ability_adds_reel for the
## base-ability slot). Grown by each reel-adding ability task.
const REEL_ADDING_EXTRA_IDS: Array[StringName] = [&"sundering_strike"]
```

Edit `can_stage_extra_ability` to add the cap check (after the cost/cooldown checks):

```gdscript
func can_stage_extra_ability(id: StringName) -> bool:
	if combatant == null or combatant.resource_pool == null:
		return false
	var def: AbilityDef = combatant.find_extra_ability(id)
	if def == null or combatant.level < def.unlock_level:
		return false
	if combatant.is_on_cooldown(id):
		return false
	if not combatant.resource_pool.can_afford({def.resource: def.cost}):
		return false
	if id in REEL_ADDING_EXTRA_IDS and combatant.turn_reels.size() >= reel_cap:
		return false
	return true
```

Edit `preview_reels()` to add a parallel block right after the existing base-ability block:

```gdscript
	if staged_extra_ability_id != &"" and staged_extra_ability_id in REEL_ADDING_EXTRA_IDS and reels.size() < reel_cap:
		match staged_extra_ability_id:
			&"sundering_strike":
				reels.append(ActionReel.make_rider_attack(combatant.weapon_type(), &"sundered"))
```

Edit `commit()` to add the extra-ability dispatch block (new, parallel to the existing base-ability
`match ability_id:` block):

```gdscript
	if staged_extra_ability_id != &"":
		var def: AbilityDef = combatant.find_extra_ability(staged_extra_ability_id)
		match staged_extra_ability_id:
			&"sundering_strike":
				combatant.try_sundering_strike(combatant.weapon_type(), def.cost, reel_cap)
		if def != null and def.cooldown_turns > 0:
			combatant.start_cooldown(staged_extra_ability_id, def.cooldown_turns)
```

- [ ] Test (`test_sundering_strike.gd`): build a Warrior via `ClassLibrary.make(&"warrior").build_combatant(true)`,
  set `level = 5`, call `MainPhasePlan.new(c)`, `toggle_extra_ability(&"sundering_strike")`, `commit()`,
  assert `c.turn_reels.size()` grew by 1, the new reel's `is_weapon_attack == true`, and its
  SUCCESS face's `rider_effect_id == &"sundered"`. Also assert `can_stage_extra_ability` is false
  below level 5 and after stamina is drained to 0.

- [ ] Run, verify, commit as in prior tasks (message: `feat(warrior): add Sundering Strike (L5) + reel-adding extra-ability plumbing`).

---

### Task 12: Warrior L7 — Heroic Guard

**Files:** Modify `combatant.gd`, `main_phase_plan.gd`; Test `tests/test_heroic_guard.gd`

- [ ] Combatant method:

```gdscript
## Warrior "Heroic Guard" (L7): self-cast, no reel. Grants Guarded + Taunt so he pulls fire off
## fragile allies. Returns false (no change) if unaffordable.
func apply_heroic_guard(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	attach_effect(EffectLibrary.make(&"guarded"))
	attach_effect(EffectLibrary.make(&"taunt"))
	return true
```

- [ ] `MainPhasePlan`: `heroic_guard` is NOT in `REEL_ADDING_EXTRA_IDS` (no cap check, no preview
  reel). Add its `commit()` case only:

```gdscript
			&"heroic_guard":
				combatant.apply_heroic_guard(def.cost)
```

- [ ] Test: stage + commit at level 7, assert `c.has_effect(&"guarded")` and `c.has_effect(&"taunt")`
  and stamina was spent; assert `can_stage_extra_ability(&"heroic_guard")` false below level 7.

- [ ] Commit: `feat(warrior): add Heroic Guard (L7)`

---

### Task 13: Warrior L9 — Second Wind

**Files:** Modify `combatant.gd`, `main_phase_plan.gd`; Test `tests/test_second_wind.gd`

- [ ] Combatant method:

```gdscript
## Warrior "Second Wind" (L9, ultimate-tier, 4-turn CD): heals 30% max HP (ceil), Cleanses every
## debuff, and grants Guarded — he comes back hardened, not just patched up.
func apply_second_wind(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	heal(ceili(max_hp * 0.30))
	cleanse()
	attach_effect(EffectLibrary.make(&"guarded"))
	return true
```

- [ ] `MainPhasePlan` `commit()` case:

```gdscript
			&"second_wind":
				combatant.apply_second_wind(def.cost)
```

- [ ] Test: damage the combatant first (`c.hp = 10` with `max_hp = 300`), attach a `slow` debuff,
  stage/commit `second_wind` at level 9, assert `hp == 10 + ceili(300*0.30)`, `not c.has_effect(&"slow")`,
  `c.has_effect(&"guarded")`, and `c.is_on_cooldown(&"second_wind")` afterward (verify `commit()`'s
  cooldown-setting line from Task 11 fires for every extra ability, not just Sundering Strike).

- [ ] Commit: `feat(warrior): add Second Wind (L9, ultimate-tier)`

---

### Task 14: Vanguard L5 — Bloodwrath

**Files:** Modify `combatant.gd`, `main_phase_plan.gd`; Test `tests/test_bloodwrath.gd`

- [ ] Combatant method:

```gdscript
## Vanguard "Bloodwrath" (L5): self-cast Empowered scaling with missing HP% (+1% dmg per 2% HP
## missing, capped +40%) — a high-risk juggernaut buff. [ASSUMPTION] scaling.
func apply_bloodwrath(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	var missing_pct: float = 1.0 - (float(hp) / float(maxi(max_hp, 1)))
	var bonus: float = minf(missing_pct * 0.5, 0.40)
	var e: Effect = EffectLibrary.make(&"empowered")
	e.magnitude = 1.0 + bonus
	attach_effect(e)
	return true
```

- [ ] `MainPhasePlan` `commit()` case: `&"bloodwrath": combatant.apply_bloodwrath(def.cost)`.

- [ ] Test: set `hp = max_hp` (0% missing) → assert magnitude ≈ 1.0 after attach (find the effect
  via a new-or-existing accessor — `c.active_effects` is public, so
  `for e in c.active_effects: if e.id == &"empowered": assert magnitude`); set `hp = 1` on a
  `max_hp = 300` combatant (99.7% missing) → assert magnitude ≈ 1.40 (capped).

- [ ] Commit: `feat(vanguard): add Bloodwrath (L5)`

---

### Task 15: Vanguard L7 — Quake Slam

**Files:** Modify `combatant.gd`, `main_phase_plan.gd`; Test `tests/test_quake_slam.gd`

- [ ] Combatant method (reel-adding — add `&"quake_slam"` to `REEL_ADDING_EXTRA_IDS`):

```gdscript
## Vanguard "Quake Slam" (L7): splices a real-damage reel that reliably applies SLOW on a hit.
func try_quake_slam(type: DamageType, cost: int, cap: int) -> bool:
	if turn_reels.size() >= cap:
		return false
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	turn_reels.append(ActionReel.make_rider_attack(type, &"slow"))
	return true
```

- [ ] `MainPhasePlan`: add `&"quake_slam"` to `REEL_ADDING_EXTRA_IDS`; add its `preview_reels()` arm
  (`ActionReel.make_rider_attack(combatant.weapon_type(), &"slow")`) and its `commit()` case
  (`combatant.try_quake_slam(combatant.weapon_type(), def.cost, reel_cap)`).

- [ ] Test: mirrors Task 11's shape with rider `&"slow"` instead of `&"sundered"`.

- [ ] Commit: `feat(vanguard): add Quake Slam (L7)`

---

### Task 16: Vanguard L9 — Mountain Stance

**Files:** Modify `combatant.gd`, `main_phase_plan.gd`; Test `tests/test_mountain_stance.gd`

- [ ] Combatant method:

```gdscript
## Vanguard "Mountain Stance" (L9, ultimate-tier, 4-turn CD): heavy Guarded + full immunity to
## Slow/Rooted/Stunned + Taunt for 3 turns — an unmovable, unlockable-down anchor.
func apply_mountain_stance(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	var guard: Effect = EffectLibrary.make(&"guarded")
	guard.magnitude = 0.5
	guard.duration = 3
	guard.immune_effect_ids = [&"slow", &"rooted"]
	guard.grants_stun_immunity = true
	attach_effect(guard)
	var taunt: Effect = EffectLibrary.make(&"taunt")
	taunt.duration = 3
	attach_effect(taunt)
	return true
```

- [ ] `MainPhasePlan` `commit()` case: `&"mountain_stance": combatant.apply_mountain_stance(def.cost)`.

- [ ] Test: stage/commit at level 9; assert `c.incoming_damage_multiplier() == 0.5`; try
  `c.attach_effect(EffectLibrary.make(&"slow"))` and assert `not c.has_effect(&"slow")`; call
  `c.base_initiative = 0; c.evaluate_stun(999)` and assert it returns `false` despite the low
  initiative.

- [ ] Commit: `feat(vanguard): add Mountain Stance (L9, ultimate-tier)`

---

### Task 17: Skirmisher L5 — Feint & Riposte

**Files:** Modify `combatant.gd`, `main_phase_plan.gd`; Test `tests/test_feint_riposte.gd`

- [ ] Combatant method:

```gdscript
## Skirmisher "Feint & Riposte" (L5): self-cast Evasion + Taunt — baits attacks he'll dodge, and
## feeds Riposte Storm's charge counter (Task 18) while it's up.
func apply_feint_riposte(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	attach_effect(EffectLibrary.make(&"evasion"))
	attach_effect(EffectLibrary.make(&"taunt"))
	return true
```

- [ ] `MainPhasePlan` `commit()` case: `&"feint_riposte": combatant.apply_feint_riposte(def.cost)`.

- [ ] Test: stage/commit at level 5; assert `has_effect(&"evasion")` and `has_effect(&"taunt")`.

- [ ] Commit: `feat(skirmisher): add Feint & Riposte (L5) — now grants Taunt alongside Evasion`

---

### Task 18: Skirmisher L7 — Quickstep

**Files:** Modify `combatant.gd`, `main_phase_plan.gd`; Test `tests/test_quickstep.gd`

- [ ] Combatant method:

```gdscript
## Skirmisher "Quickstep" (L7): self-cast Haste (a one-time +20 initiative bump, mirrors Slow's
## first tier inverted).
func apply_quickstep(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	attach_effect(EffectLibrary.make(&"haste"))
	return true
```

- [ ] `MainPhasePlan` `commit()` case: `&"quickstep": combatant.apply_quickstep(def.cost)`.

- [ ] Test: record `current_initiative` before commit, stage/commit at level 7, assert
  `current_initiative` rose by 20 after `recompute_initiative()` (already called inside `attach_effect`).

- [ ] Commit: `feat(skirmisher): add Quickstep (L7)`

---

### Task 19: Skirmisher L9 — Riposte Storm

**Files:** Modify `combatant.gd`, `main_phase_plan.gd`; Test `tests/test_riposte_storm.gd`

- [ ] Combatant method (uses the multiplier hook, not a new reel — see plan's Task 9 design note):

```gdscript
## Skirmisher "Riposte Storm" (L9, ultimate-tier, 3-turn CD): detonates accumulated riposte_charges
## (built by Evasion, Task 9) as a temporary Empowered on this turn's normal reels — +15% per
## charge, capped at 5 charges (+75% max). Fires at baseline (no bonus) with 0 charges. Resets
## charges on use.
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

- [ ] `MainPhasePlan` `commit()` case: `&"riposte_storm": combatant.fire_riposte_storm(def.cost)`.

- [ ] Test: set `riposte_charges = 3`, stage/commit at level 9; assert the attached `empowered`
  magnitude ≈ `1.45`; assert `riposte_charges == 0` after; assert `c.is_on_cooldown(&"riposte_storm")`.

- [ ] Commit: `feat(skirmisher): add Riposte Storm (L9, ultimate-tier)`

---

### Task 20: Chancer L5 — Loaded Dice

**Files:** Modify `combatant.gd`, `combat.gd`, `main_phase_plan.gd`; Test `tests/test_loaded_dice.gd`

- [ ] Combatant fields + method:

```gdscript
## Chancer "Loaded Dice" (L5) pending flag: the orchestrator lights PaylineLibrary.bonus_line for
## this spin (combat.gd, Task 20 wiring) then clears it. Set here; consumed post-commit.
var loaded_dice_pending: bool = false

## Adds one crit-success face (mult 2.0, mirrors apply_luck) to each of THIS turn's reels — a
## temporary Luck point for one spin only — and flags the bonus payline. Deep-copies so the
## underlying weapon is never mutated (apply_luck's own-reels mutation is permanent; this is not).
func apply_loaded_dice(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
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

- [ ] `MainPhasePlan` `commit()` case: `&"loaded_dice": combatant.apply_loaded_dice(def.cost)`.

- [ ] `combat.gd` wiring: at the `resolve_combat_phase(...)` call site (same spot edited in Task 5),
  build `extra_lines` from the flag and clear it after the call:

```gdscript
	var extra_lines: Array = []
	if _attacker.loaded_dice_pending:
		extra_lines.append(PaylineLibrary.bonus_line(weapon_reel_count_used_in_this_call))
	# ... pass extra_lines into the existing resolve_combat_phase call ...
	_attacker.loaded_dice_pending = false
```

  (Use whatever local variable the existing call already computes for the weapon-reel-count
  argument — do not introduce a second count.)

- [ ] Test: stage/commit `loaded_dice` at level 5 on a combatant with 2 turn_reels; assert each
  reel's face count grew by 1 and the last-added face is `CRIT_SUCCESS`/mult 2.0; assert
  `loaded_dice_pending == true` after commit (orchestrator-side clearing is exercised by the scene,
  not this headless unit test — note that in a comment).

- [ ] Commit: `feat(chancer): add Loaded Dice (L5) — crit faces + bonus payline`

---

### Task 21: Chancer L7 — Jinx the Odds

**Files:** Modify `combatant.gd`, `main_phase_plan.gd`; Test `tests/test_jinx_the_odds.gd`

- [ ] Combatant method (reel-adding — add `&"jinx_the_odds"` to `REEL_ADDING_EXTRA_IDS`):

```gdscript
## Chancer "Jinx the Odds" (L7): splices a real-damage reel that curses the target with JINXED.
func try_jinx_the_odds(type: DamageType, cost: int, cap: int) -> bool:
	if turn_reels.size() >= cap:
		return false
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	turn_reels.append(ActionReel.make_rider_attack(type, &"jinxed"))
	return true
```

- [ ] `MainPhasePlan`: add to `REEL_ADDING_EXTRA_IDS`; `preview_reels()` arm + `commit()` case as in Task 15.

- [ ] Test: mirrors Task 11/15's shape with rider `&"jinxed"`.

- [ ] **Note for a later task (not blocking this one):** `jinxed`'s actual face-downgrade behavior
  (bearer's own success→neutral, crit-success→success) needs an orchestrator check on the
  ATTACKER's own turn (symmetric to how Evasion/Hunter's Mark are checked on the DEFENDER). Add this
  to `combat.gd` alongside the Task 9 Evasion block: `if _attacker.has_effect(&"jinxed"): downgrade
  _attacker.turn_reels' success/crit-success faces by one tier` (a new
  `Combatant.jinxed_reels(reels) -> Array[ActionReel]` static, same shape as `evasion_reels`, but
  downgrading CRIT_SUCCESS→SUCCESS and SUCCESS→NEUTRAL/mult 0 instead of to FAILURE). Implement this
  as part of THIS task (Step 3, alongside the splice method) so the ability doesn't ship inert:

```gdscript
## Jinxed (Task 7) reel transform: downgrades a bearer's own SUCCESS faces to NEUTRAL (mult 0) and
## CRIT_SUCCESS faces to SUCCESS (mult 1.0) on weapon-attack reels — bad luck given form. Static + pure.
static func jinxed_reels(reels: Array) -> Array[ActionReel]:
	var out: Array[ActionReel] = []
	for r: ActionReel in reels:
		if r != null and r.is_weapon_attack:
			var copy: ActionReel = r.duplicate(true)
			for f: ReelFace in copy.faces:
				if f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
					f.result_tier = ReelFace.ResultTier.SUCCESS
					f.multiplier = 1.0
				elif f.result_tier == ReelFace.ResultTier.SUCCESS:
					f.result_tier = ReelFace.ResultTier.NEUTRAL
					f.multiplier = 0.0
			out.append(copy)
		else:
			out.append(r)
	return out
```

  And in `combat.gd`, next to the Evasion block: `if _attacker.has_effect(&"jinxed"): _attacker.turn_reels = Combatant.jinxed_reels(_attacker.turn_reels)`.
  Add `test_jinxed_reels.gd` covering the transform directly (CRIT_SUCCESS→SUCCESS, SUCCESS→NEUTRAL,
  other tiers untouched).

- [ ] Commit: `feat(chancer): add Jinx the Odds (L7) + the Jinxed reel-downgrade transform`

---

### Task 22: Chancer L9 — Double or Nothing

**Files:** Modify `combatant.gd`, `combat.gd`, `main_phase_plan.gd`; Test `tests/test_double_or_nothing.gd`

- [ ] Combatant fields + method:

```gdscript
## Chancer "Double or Nothing" (L9) post-spin bookkeeping (combat.gd applies these per-reel, then
## clears both): pending flags the crit-fail-recoils/refund resolution; accum tallies the refund.
var double_or_nothing_pending: bool = false
var double_or_nothing_refund_accum: int = 0

## All-in gamble (L9, ultimate-tier, 7-turn CD): spends 100% of current Stamina (must have at least
## 1) for a big Empowered on the next spin; a crit-fail on that spin recoils as self-damage, a
## non-fail reel refunds Stamina (combat.gd, Task 22 wiring). Returns false if Stamina is 0.
func fire_double_or_nothing() -> bool:
	if resource_pool == null or resource_pool.stamina < 1:
		return false
	var cost: int = resource_pool.stamina
	resource_pool.spend({&"stamina": cost})
	var e: Effect = EffectLibrary.make(&"empowered")
	e.magnitude = 1.5
	e.duration = 1
	attach_effect(e)
	double_or_nothing_pending = true
	double_or_nothing_refund_accum = 0
	return true
```

- [ ] `MainPhasePlan`: `double_or_nothing`'s `AbilityDef.cost` is `0` (Task 2's data table) because
  the real cost is computed at cast time — override `can_stage_extra_ability` for this one id to
  check `stamina >= 1` instead of `can_afford({resource: def.cost})`:

```gdscript
	if id == &"double_or_nothing":
		return combatant.level >= def.unlock_level and not combatant.is_on_cooldown(id) and combatant.resource_pool.stamina >= 1
```

  (Insert this as an early branch inside `can_stage_extra_ability`, before the generic
  `can_afford` check, guarded by `def != null`.) `commit()` case:

```gdscript
			&"double_or_nothing":
				combatant.fire_double_or_nothing()
```

- [ ] `combat.gd` wiring in `_apply_attack()`, right after the existing rider-application block
  (~line 1286), accumulate per-reel, and at `_finish_spin()` (or wherever the spin's last reel is
  detected — reuse the existing `_pending_strips <= 0` check at the end of `_apply_attack`) apply +
  clear:

```gdscript
	if _attacker.double_or_nothing_pending:
		if attack.face.result_tier == ReelFace.ResultTier.CRIT_FAILURE:
			_attacker.take_damage(ceili(attack.base_damage))
			_log("  💥 %s's gamble recoils for %d." % [_attacker.display_name, ceili(attack.base_damage)])
		elif attack.face.result_tier != ReelFace.ResultTier.FAILURE:
			_attacker.double_or_nothing_refund_accum += 1

	_pending_strips -= 1
	if _pending_strips <= 0:
		if _attacker.double_or_nothing_pending:
			_attacker.resource_pool.refund({&"stamina": _attacker.double_or_nothing_refund_accum})
			_attacker.double_or_nothing_pending = false
			_attacker.double_or_nothing_refund_accum = 0
		_finish_spin()
```

  (Merge this into the existing `_pending_strips -= 1 / if _pending_strips <= 0: _finish_spin()`
  block at the end of `_apply_attack` rather than duplicating it.)

- [ ] Test: set `resource_pool.stamina = 4, max_stamina = 10`; call `fire_double_or_nothing()`;
  assert `stamina == 0` and the attached `empowered` magnitude is `1.5`; assert
  `fire_double_or_nothing()` returns `false` when `stamina == 0` (no more all-in gambles until
  regen). The post-spin refund/recoil path is orchestrator-level (scene), covered by manual
  playtest per CLAUDE.md §5's hard ceiling, not a headless unit test — note this in the test file's
  header comment.

- [ ] Commit: `feat(chancer): add Double or Nothing (L9, ultimate-tier) — all-in cost + refund/recoil`

---

### Task 23: Ranger L5 — Aimed Shot

**Files:** Modify `combatant.gd`, `combat.gd`, `main_phase_plan.gd`; Test `tests/test_aimed_shot.gd`

- [ ] Combatant field + method (mirrors `hunters_mark_pending` exactly):

```gdscript
## Ranger "Aimed Shot" (L5) pending flag: the orchestrator (which knows the defender) attaches
## Empowered with a bonus magnitude if the defender is already Marked (combat.gd, Task 23 wiring).
var aimed_shot_pending: bool = false

func stage_aimed_shot(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	aimed_shot_pending = true
	return true
```

- [ ] `MainPhasePlan` `commit()` case: `&"aimed_shot": combatant.stage_aimed_shot(def.cost)`.

- [ ] `combat.gd` wiring, alongside the existing Hunter's Mark attach block (~line 1131):

```gdscript
	if _attacker.aimed_shot_pending:
		var e: Effect = EffectLibrary.make(&"empowered")
		e.magnitude = 1.6 if _defender.has_effect(&"hunters_mark") else 1.3
		e.duration = 1
		_attacker.attach_effect(e)
		_attacker.aimed_shot_pending = false
```

- [ ] Test: `stage_aimed_shot` spends the cost and sets the flag (headless-testable); the
  Mark-dependent magnitude branch is orchestrator-level — note in the test header, same as Task 22.

- [ ] Commit: `feat(ranger): add Aimed Shot (L5)`

---

### Task 24: Ranger L7 — Snare Trap

**Files:** Modify `combatant.gd`, `main_phase_plan.gd`; Test `tests/test_snare_trap.gd`

- [ ] Combatant method (reel-adding — add `&"snare_trap"` to `REEL_ADDING_EXTRA_IDS`):

```gdscript
## Ranger "Snare Trap" (L7): splices a real-damage reel that Roots the target on a hit.
func try_snare_trap(type: DamageType, cost: int, cap: int) -> bool:
	if turn_reels.size() >= cap:
		return false
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	turn_reels.append(ActionReel.make_rider_attack(type, &"rooted"))
	return true
```

- [ ] `MainPhasePlan`: add to `REEL_ADDING_EXTRA_IDS`; `preview_reels()` arm + `commit()` case.

- [ ] Test: mirrors Task 11/15's shape with rider `&"rooted"`.

- [ ] Commit: `feat(ranger): add Snare Trap (L7)`

---

### Task 25: Ranger L9 — Crippling Shot

**Files:** Modify `combatant.gd`, `combat.gd`, `main_phase_plan.gd`; Test `tests/test_crippling_shot.gd`

- [ ] Combatant method (reel-adding, `bonus_vs_cc = true` — add `&"crippling_shot"` to `REEL_ADDING_EXTRA_IDS`):

```gdscript
## Ranger "Crippling Shot" (L9, ultimate-tier, 3-turn CD): a called shot that Weakens the target
## AND (combat.gd wiring) deals +50% bonus damage if the target is already Slowed/Rooted/Stunned.
func try_crippling_shot(type: DamageType, cost: int, cap: int) -> bool:
	if turn_reels.size() >= cap:
		return false
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	turn_reels.append(ActionReel.make_rider_attack(type, &"weakened", true))
	return true
```

- [ ] `MainPhasePlan`: add to `REEL_ADDING_EXTRA_IDS`; `preview_reels()` arm using
  `ActionReel.make_rider_attack(combatant.weapon_type(), &"weakened", true)`; `commit()` case
  calling `try_crippling_shot`.

- [ ] `combat.gd` wiring in `_apply_attack()`, right after `t.take_damage(attack.final_damage)` /
  the Task 6 thorns block:

```gdscript
			if attack.source_reel != null and attack.source_reel.bonus_vs_cc:
				if t.has_effect(&"slow") or t.has_effect(&"rooted") or t.stunned_this_turn:
					var bonus: int = ceili(attack.final_damage * 0.5)
					t.take_damage(bonus)
					_log("  🎯 Crippling Shot exploits %s's condition for %d bonus damage." % [t.display_name, bonus])
```

  (Note the `t.stunned_this_turn` check, NOT `has_effect(&"stunned")` — STUNNED is a plain bool per
  the plan's spec-correction §2, not an attachable Effect.)

- [ ] Test: reel/rider assertions as in Task 15; a dedicated
  `test_crippling_shot_bonus.gd` unit-tests the CC-check logic in isolation if `_apply_attack` is
  reachable headlessly, otherwise note the bonus-damage branch as orchestrator-level (scene-verified)
  like Tasks 22/23.

- [ ] Commit: `feat(ranger): add Crippling Shot (L9, ultimate-tier) — bonus damage vs CC'd targets`

---

### Task 26: Seer L5 — Hex (+ shared beneficial-DoT healing branch in `_apply_dot`)

**Files:** Modify `combatant.gd`, `combat.gd`, `main_phase_plan.gd`; Test `tests/test_hex.gd`

- [ ] Combatant method (reel-adding — add `&"hex"` to `REEL_ADDING_EXTRA_IDS`):

```gdscript
## Seer "Hex" (L5): splices a real-Mystic-damage reel that Curses the target (a Mystic DoT).
func try_hex(type: DamageType, cost: int, cap: int) -> bool:
	if turn_reels.size() >= cap:
		return false
	if resource_pool == null or not resource_pool.spend({&"mana": cost}):
		return false
	turn_reels.append(ActionReel.make_rider_attack(type, &"cursed"))
	return true
```

- [ ] `MainPhasePlan`: add to `REEL_ADDING_EXTRA_IDS`; `preview_reels()` arm + `commit()` case
  (spends `&"mana"`, matching the Seer's resource — `commit()`'s generic dispatch already reads
  `def.resource`/`def.cost` from the `AbilityDef`, so no special-casing needed there, only in the
  Combatant method itself which hardcodes `&"mana"` for this Seer-only ability).

- [ ] `combat.gd`: extend the existing `_apply_dot()` (~line 910) to branch on `beneficial` — this
  is the first NEW DoT this plan adds (`regen` in Task 27 also needs it), so build it once here:

```gdscript
func _apply_dot(c: Combatant) -> void:
	for e: Effect in c.active_effects:
		if e.kind == Effect.Kind.DAMAGE_OVER_TIME:
			var amount: int = e.dot_damage()
			if amount <= 0:
				continue
			if e.beneficial:
				c.heal(amount)
				_log("  %s regenerates %d HP from %s." % [c.display_name, amount, String(e.id).to_upper()])
			else:
				c.take_damage(amount)
				# existing bleed/cursed log line stays as-is here
```

  (Preserve whatever the existing non-beneficial log line says — only ADD the `if e.beneficial`
  branch above it; do not change Bleed's existing behavior/wording.)

- [ ] Test: reel/rider assertions as in Task 15, rider `&"cursed"`, resource `&"mana"`.

- [ ] Commit: `feat(seer): add Hex (L5) + beneficial-DoT healing branch in _apply_dot`

---

### Task 27: Seer L7 — Foresight

**Files:** Modify `combatant.gd`, `combat.gd`, `main_phase_plan.gd`; Test `tests/test_foresight.gd`

- [ ] Combatant field + method:

```gdscript
## Seer "Foresight" (L7) pending flag: the orchestrator picks the lowest-HP% living ally
## (combat.gd, Task 27 wiring) and shields them.
var foresight_pending: bool = false

func stage_foresight(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"mana": cost}):
		return false
	foresight_pending = true
	return true
```

- [ ] `MainPhasePlan` `commit()` case: `&"foresight": combatant.stage_foresight(def.cost)`.

- [ ] `combat.gd` wiring: add a small helper and the resolution block (near the existing
  `_lowest_hp`-style helpers / `_enemies_of`):

```gdscript
## The living ally (including [param caster] itself) with the lowest HP%, for support abilities
## that need an auto-picked target (Foresight, Regrowth — spec 2026-07-01 §4, YAGNI: no ally-click
## targeting UI yet).
func _lowest_hp_pct_ally(caster: Combatant) -> Combatant:
	var best: Combatant = null
	var best_pct: float = 2.0
	for c: Combatant in _turn_manager.combatants:
		if c.is_player == caster.is_player and c.is_alive():
			var pct: float = float(c.hp) / float(maxi(c.max_hp, 1))
			if pct < best_pct:
				best_pct = pct
				best = c
	return best
```

  And at commit-resolution time (alongside the Hunter's Mark / Aimed Shot blocks):

```gdscript
	if _attacker.foresight_pending:
		var ally: Combatant = _lowest_hp_pct_ally(_attacker)
		if ally != null:
			var amount: int = ceili(_attacker.resource_pool.max_mana * 0.15)
			ally.apply_shield(amount, 2)
			_log("  🔮 %s grants Foresight — %s shields %d HP." % [_attacker.display_name, ally.display_name, amount])
		_attacker.foresight_pending = false
```

- [ ] Test: `stage_foresight` spends mana + sets the flag (headless); the ally-picking/shield
  application is orchestrator-level (scene-verified), noted per Task 22/23's pattern.

- [ ] Commit: `feat(seer): add Foresight (L7) — auto-targets the lowest-HP% ally`

---

### Task 28: Seer L9 — Mana Surge

**Files:** Modify `combatant.gd`, `main_phase_plan.gd`; Test `tests/test_mana_surge.gd`

- [ ] Combatant method:

```gdscript
## Seer "Mana Surge" (L9, ultimate-tier, 4-turn CD): a massive Empowered on this turn's own heavy
## reels only (duration 1 = expires at this turn's on_end).
func apply_mana_surge(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"mana": cost}):
		return false
	var e: Effect = EffectLibrary.make(&"empowered")
	e.magnitude = 1.6
	e.duration = 1
	attach_effect(e)
	return true
```

- [ ] `MainPhasePlan` `commit()` case: `&"mana_surge": combatant.apply_mana_surge(def.cost)`.

- [ ] Test: stage/commit at level 9; assert `outgoing_damage_multiplier() ≈ 1.6`; call `on_end()`
  once and assert the effect expired (`outgoing_damage_multiplier() == 1.0` again).

- [ ] Commit: `feat(seer): add Mana Surge (L9, ultimate-tier)`

---

### Task 29: Warden L5 — Entangle

**Files:** Modify `combatant.gd`, `main_phase_plan.gd`; Test `tests/test_entangle.gd`

- [ ] Combatant method (reel-adding — add `&"entangle"` to `REEL_ADDING_EXTRA_IDS`):

```gdscript
## Warden "Entangle" (L5): splices a real-Earth-damage reel that Roots the target on a hit.
func try_entangle(type: DamageType, cost: int, cap: int) -> bool:
	if turn_reels.size() >= cap:
		return false
	if resource_pool == null or not resource_pool.spend({&"mana": cost}):
		return false
	turn_reels.append(ActionReel.make_rider_attack(type, &"rooted"))
	return true
```

- [ ] `MainPhasePlan`: add to `REEL_ADDING_EXTRA_IDS`; `preview_reels()` arm + `commit()` case.

- [ ] Test: mirrors Task 15/24's shape, resource `&"mana"`.

- [ ] Commit: `feat(warden): add Entangle (L5)`

---

### Task 30: Warden L7 — Regrowth

**Files:** Modify `combatant.gd`, `combat.gd`, `main_phase_plan.gd`; Test `tests/test_regrowth.gd`

- [ ] Combatant field + method (mirrors Foresight/Task 27 exactly, different rider):

```gdscript
## Warden "Regrowth" (L7) pending flag: the orchestrator picks the lowest-HP% living ally
## (combat.gd, reusing Task 27's _lowest_hp_pct_ally) and grants them Regen.
var regrowth_pending: bool = false

func stage_regrowth(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"mana": cost}):
		return false
	regrowth_pending = true
	return true
```

- [ ] `MainPhasePlan` `commit()` case: `&"regrowth": combatant.stage_regrowth(def.cost)`.

- [ ] `combat.gd` wiring, reusing `_lowest_hp_pct_ally` from Task 27:

```gdscript
	if _attacker.regrowth_pending:
		var ally: Combatant = _lowest_hp_pct_ally(_attacker)
		if ally != null:
			ally.attach_effect(EffectLibrary.make(&"regen"))
			_log("  🌿 %s grants Regrowth to %s." % [_attacker.display_name, ally.display_name])
		_attacker.regrowth_pending = false
```

- [ ] Test: `stage_regrowth` spends mana + sets the flag (headless); ally-targeting/attach is
  orchestrator-level, noted per pattern.

- [ ] Commit: `feat(warden): add Regrowth (L7)`

---

### Task 31: Warden L9 — Bastion

**Files:** Modify `combatant.gd`, `main_phase_plan.gd`; Test `tests/test_bastion.gd`

- [ ] Combatant method:

```gdscript
## Warden "Bastion" (L9, ultimate-tier, 4-turn CD): heavy Guarded (with Thorns baked onto the same
## effect instance) + Taunt for 3 turns — the wall that bites back.
func apply_bastion(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"mana": cost}):
		return false
	var guard: Effect = EffectLibrary.make(&"guarded")
	guard.magnitude = 0.5
	guard.duration = 3
	guard.thorns_pct = 0.20
	attach_effect(guard)
	var taunt: Effect = EffectLibrary.make(&"taunt")
	taunt.duration = 3
	attach_effect(taunt)
	return true
```

- [ ] `MainPhasePlan` `commit()` case: `&"bastion": combatant.apply_bastion(def.cost)`.

- [ ] Test: stage/commit at level 9; assert `incoming_damage_multiplier() == 0.5`,
  `thorns_pct() == 0.2`, `has_effect(&"taunt")`.

- [ ] Commit: `feat(warden): add Bastion (L9, ultimate-tier)`

---

## Task 32: ENDGAME combat tester

**Files:**
- Modify: the start-of-encounter selection scene/script (wherever the existing party/enemy roster
  picker lives — locate via `Grep` for `"Choose your Party"` before starting this task, per the
  spec's §5; the exact file wasn't in this plan's architecture audit and must be re-confirmed at
  execution time since it's a scene-level UI file, not a `combat/` logic file).
- Test: `tests/test_endgame_level.gd` (pure logic: spawning at level 9 unlocks everything).

**Interfaces:**
- Consumes: `Combatant.level`, `unlocked_extra_abilities()` (Task 2).
- Produces: an "ENDGAME" toggle on the selection screen that sets `level = 9` on every spawned
  `Combatant` instead of the default `1`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	for id in ClassLibrary.IDS:
		var cc: CharacterClass = ClassLibrary.make(id)
		var c: Combatant = cc.build_combatant(true)
		c.level = 9
		_check(c.unlocked_extra_abilities().size() == cc.extra_abilities.size(), "%s: level 9 unlocks all extra_abilities" % id)
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_endgame_level.gd`
Expected: FAIL only if any class's `extra_abilities` count mismatches 3 (a regression check on
Task 2's data, not new behavior — should already pass; if it does, this step doubles as the
verification that all 7 classes are fully wired before touching UI).

- [ ] **Step 3: Write minimal implementation**

Locate the selection screen's "BEGIN FIGHT" handler (per HANDOFF.md: a start-of-session overlay
with party/enemy pickers + a dummy toggle). Add an "ENDGAME" `CheckBox` next to the existing dummy
toggle, and in the same function that currently does `pc.level = 1` (or, if `level` isn't set at
all yet there, right after `CharacterClass.build_combatant()` is called for each PC), add:

```gdscript
	if _endgame_toggle.button_pressed:
		pc.level = 9
```

Apply to PCs only (enemies don't have `extra_abilities` populated, per spec §5 and the locked
design's PC-only scope — `unlocked_extra_abilities()` on an enemy safely returns `[]` regardless of
level since `extra_abilities` stays empty for them).

- [ ] **Step 4: Manual verification (UI, not headless-testable)**

Per CLAUDE.md §5's hard ceiling: run the scene, toggle ENDGAME, start a fight, and confirm all 4
ability buttons + the Ultimate button are visible/stageable for the selected PC. This is a human
playtest step, not an automated one — flag it back to the user rather than claiming done from
running the headless suite alone.

- [ ] **Step 5: Commit**

```bash
git add tests/test_endgame_level.gd <selection-screen-file>
git commit -m "feat(ui): add ENDGAME toggle — spawns PCs at level 9 with every ability unlocked"
```

---

## Task 33: Full regression + HANDOFF/CLAUDE.md status update

**Files:**
- Modify: `HANDOFF.md`, `CLAUDE.md` §8 (per this project's convention of narrating shipped work).

- [ ] **Step 1:** Run every test file under `tests/` (all ~100 suites: 69 pre-existing + ~31 new)
  headlessly and confirm 100% green. If the project has a batch-run script, use it; otherwise loop
  `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/<name>.gd` over
  `Glob("tests/test_*.gd")`.
- [ ] **Step 2:** Update `CLAUDE.md` §8 and `HANDOFF.md` with a summary matching this project's
  existing narration style (see the "SHIPPED 2026-06-29" / "SHIPPED 2026-06-28" entries for the
  expected format/detail level) — new suite count, the 21 abilities, the ENDGAME tester, and an
  explicit "still needs human playtest" callout per the §5 hard ceiling (Double or Nothing's
  refund/recoil, Aimed Shot's Mark bonus, Foresight/Regrowth's auto-targeting, Crippling Shot's
  bonus damage, and the whole ENDGAME kit generally — none of the orchestrator-level wiring in
  Tasks 20–31 has a human eyes-on-the-screen pass yet).
- [ ] **Step 3: Commit**

```bash
git add HANDOFF.md CLAUDE.md
git commit -m "docs: class ability expansion shipped — 21 new abilities + ENDGAME tester, 100+ suites green"
```
