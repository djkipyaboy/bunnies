# Combat Open Threads Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the four open combat-prototype threads — `Effect`/Crushing→Slow, `ResourcePool`, Main-Phase reel splice, and the Sticky-Wild Ultimate — each test-first, in dependency order.

**Architecture:** Pure-logic cores live on `Resource`/`RefCounted` data classes and the `CombatResolver` (all headless-testable); the `Combat` scene orchestrator applies results and owns the view (CLAUDE.md §5 — Claude builds the loop, the human judges feel). `CombatResolver` stays the result authority (ARCHITECTURE §2): it computes outcomes and *reports* riders; the orchestrator *applies* them. `current_initiative` becomes a derived sort key (`base_initiative` + active modifiers) so turn-order effects never need manual reversal.

**Tech Stack:** Godot 4.6.3-stable, GDScript (static-typed). Data is `Resource`-based for inspector editing. Headless `SceneTree` test scripts under `tests/`.

## Global Constraints

- **Engine: Godot 4.6.3-stable. Language: GDScript only — never C#/.NET.** (CLAUDE.md §2)
- **Data objects are `Resource`-based; logic uses `RefCounted`/`Node`.** Prefer static typing everywhere. (CLAUDE.md §2)
- **Naming (LOCKED):** classes `PascalCase`, files `snake_case`, signals `snake_case` **past-tense** (never `on_`-prefixed), handlers `_on_<emitter>_<signal>`. (CLAUDE.md §2)
- **Balance numbers are `[ASSUMPTION]` placeholders** — keep them as editable data, never hard-balance. (CLAUDE.md §4)
- **Reel band is 2–5; Main-Phase reel changes are ADDITIVE to the weapon baseline, never overwrite.** (DESIGN §4.3, §4.8)
- **Ultimate costs ONLY the Bonus Meter** — never the `ResourcePool`. The two economies are independent. (DESIGN §4.9, §10 Dec 6)
- **Run a test (from the project root — the worktree dir):**
  `Godot_v4.6.3-stable_win64 --headless --path . --script res://tests/test_<name>.gd`
  Each suite prints `… TEST PASSED/FAILED` and exits non-zero on failure.
- **After adding a NEW `class_name`, refresh the class cache before `--script` can resolve it:**
  `Godot_v4.6.3-stable_win64 --headless --path . --editor --quit`
  (This also surfaces parse/compile errors across the project — use it as the script/scene compile check.)
- Source of truth for design = `DESIGN.md`; this plan implements `docs/superpowers/specs/2026-06-19-combat-open-threads-design.md`. If code and `DESIGN.md` disagree, `DESIGN.md` wins.

---

## File Structure

**New files:**
- `combat/resources/effect.gd` — `Effect` Resource (buff/debuff/rider definition + live duration).
- `combat/effect_library.gd` — `EffectLibrary`; resolves a rider `StringName` → a fresh `Effect`.
- `combat/resource_pool.gd` — `ResourcePool` (Stamina only for the prototype).
- `tests/test_effect.gd`, `tests/test_resource_pool.gd`, `tests/test_crushing_slow.gd`,
  `tests/test_reel_splice.gd`, `tests/test_ultimate_sticky_wild.gd`.

**Modified files:**
- `combat/combatant.gd` — derived initiative, effects, resource pool, per-turn reels, sticky-wild state, Upkeep/End hooks.
- `combat/combat_resolver.gd` — `AttackResult.rider_effect_id`; rider reporting on crit-success; wild-reel override.
- `combat/turn_manager.gd` — `roll_initiative` sets `base_initiative` then recomputes.
- `combat/phase_manager.gd` — Main-1 pause: `start_turn` stops at Main 1; new `proceed_to_combat`.
- `combat/combat.gd` — orchestrator wiring for all four features + UI (Stamina, Slow pip, WILD glow, Main-1 buttons).
- `tests/test_phase_manager.gd` — updated to the new pause contract.
- `tests/test_combat_loop.gd` — integration drives the revised per-turn flow.

---

## WAVE A — `Effect` system + Crushing → Slow

### Task A1: `Effect` resource + `EffectLibrary`

**Files:**
- Create: `combat/resources/effect.gd`
- Create: `combat/effect_library.gd`
- Test: `tests/test_effect.gd` (this task adds the library/effect-level checks; Task A2 appends combatant-level checks to the same file)

**Interfaces:**
- Produces:
  - `Effect` (extends Resource): `enum Kind { INITIATIVE_MOD, DAMAGE_OVER_TIME, MULTIPLIER_EDIT, REEL_FACE_EDIT }`; `@export var id: StringName`, `@export var kind: Kind`, `@export var magnitude: float`, `@export var duration: int`; `func tick() -> void`; `func is_expired() -> bool`.
  - `EffectLibrary` (extends RefCounted): `static func make(id: StringName) -> Effect` — returns a fresh (non-shared) `Effect`, or `null` for an unknown id.

- [ ] **Step 1: Write the failing test** — create `tests/test_effect.gd`:

```gdscript
extends SceneTree

# Headless unit test for Effect + EffectLibrary (DESIGN.md §4.1, §4.6; ARCHITECTURE §7).
# Run: Godot_v4.6.3-stable_win64 --headless --path . --script res://tests/test_effect.gd

var _failures: int = 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _initialize() -> void:
	# --- EffectLibrary builds the Slow rider with the [ASSUMPTION] values ---
	var slow: Effect = EffectLibrary.make(&"slow")
	_check(slow != null, "library returns an Effect for &\"slow\"")
	_check(slow.kind == Effect.Kind.INITIATIVE_MOD, "slow is an INITIATIVE_MOD")
	_check(is_equal_approx(slow.magnitude, -20.0), "slow magnitude is -20 (got %s)" % str(slow.magnitude))
	_check(slow.duration == 2, "slow duration is 2 (got %d)" % slow.duration)
	_check(slow.id == &"slow", "slow id round-trips")

	# --- Unknown id yields null ---
	_check(EffectLibrary.make(&"nonesuch") == null, "unknown id -> null")

	# --- Each make() is independent (no shared mutable state) ---
	var a: Effect = EffectLibrary.make(&"slow")
	var b: Effect = EffectLibrary.make(&"slow")
	a.tick()
	_check(a.duration == 1 and b.duration == 2, "two builds are independent (a=%d, b=%d)" % [a.duration, b.duration])

	# --- tick() counts down; is_expired() at 0 ---
	var e: Effect = EffectLibrary.make(&"slow")
	_check(not e.is_expired(), "fresh effect not expired (duration %d)" % e.duration)
	e.tick(); e.tick()
	_check(e.duration == 0 and e.is_expired(), "expired after 2 ticks (duration %d)" % e.duration)

	print(("EFFECT TEST PASSED" if _failures == 0 else "EFFECT TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Refresh the class cache, then run the test to verify it fails**

Run: `Godot_v4.6.3-stable_win64 --headless --path . --editor --quit`
then: `Godot_v4.6.3-stable_win64 --headless --path . --script res://tests/test_effect.gd`
Expected: FAIL — `Effect`/`EffectLibrary` are not yet defined (parse error or `EFFECT TEST FAILED`).

- [ ] **Step 3: Write `combat/resources/effect.gd`**

```gdscript
class_name Effect
extends Resource

## A buff/debuff/rider applied BY a reel face or weapon type (DESIGN.md §4.1, §4.6; ARCHITECTURE §7).
## Reel faces/types APPLY effects; they don't contain them. The first target rider is Crushing→Slow,
## an INITIATIVE_MOD that lowers the bearer's current_initiative for [member duration] of its turns.
##
## This is a DEFINITION carrying its own live countdown — always attach a duplicate() so two
## combatants never share one duration counter (see EffectLibrary / Combatant.attach_effect).

enum Kind { INITIATIVE_MOD, DAMAGE_OVER_TIME, MULTIPLIER_EDIT, REEL_FACE_EDIT }

## Stable id used by riders to reference this effect (e.g. DamageType.inherent_rider_id = &"slow").
@export var id: StringName = &""

## Which family of effect this is. Only INITIATIVE_MOD is exercised in the prototype.
@export var kind: Kind = Kind.INITIATIVE_MOD

## Signed magnitude (INITIATIVE_MOD: added to current_initiative — negative = Slow). [ASSUMPTION] data.
@export var magnitude: float = 0.0

## Remaining turns on the bearer. Ticks down in Combatant.on_end(); removed when it hits 0.
@export var duration: int = 1

## Decrements the remaining duration by one bearer-turn (clamped at 0).
func tick() -> void:
	duration = maxi(duration - 1, 0)

## True once the effect has run out and should be detached.
func is_expired() -> bool:
	return duration <= 0
```

- [ ] **Step 4: Write `combat/effect_library.gd`**

```gdscript
class_name EffectLibrary
extends RefCounted

## Resolves a rider id (DamageType.inherent_rider_id / ReelFace.rider_effect_id) into a FRESH
## Effect instance. For the prototype this is a small code registry holding the one rider we need —
## Crushing → Slow. Authorable as .tres later (YAGNI: one rider needs no asset pipeline yet).
##
## Always returns a new Effect (never a shared reference) so each bearer owns its own countdown.

## [ASSUMPTION] placeholder values — tune by playtest (CLAUDE.md §4).
static func make(id: StringName) -> Effect:
	match id:
		&"slow":
			var e: Effect = Effect.new()
			e.id = &"slow"
			e.kind = Effect.Kind.INITIATIVE_MOD
			e.magnitude = -20.0
			e.duration = 2
			return e
		_:
			return null
```

- [ ] **Step 5: Refresh the class cache, then run the test to verify it passes**

Run: `Godot_v4.6.3-stable_win64 --headless --path . --editor --quit`
then: `Godot_v4.6.3-stable_win64 --headless --path . --script res://tests/test_effect.gd`
Expected: PASS — `EFFECT TEST PASSED`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add combat/resources/effect.gd combat/effect_library.gd tests/test_effect.gd
git commit -m "feat(combat): add Effect resource + EffectLibrary (Crushing->Slow rider)"
```

---

### Task A2: `Combatant` effect integration + Upkeep/End hooks

**Files:**
- Modify: `combat/combatant.gd`
- Test: `tests/test_effect.gd` (append combatant-level checks)

**Interfaces:**
- Consumes: `Effect`, `EffectLibrary` (Task A1).
- Produces, on `Combatant`:
  - `var base_initiative: int` — raw rolled value; `current_initiative` is derived from it.
  - `var active_effects: Array[Effect]`
  - `func recompute_initiative() -> void` — `current_initiative = base_initiative + Σ INITIATIVE_MOD magnitudes`.
  - `func attach_effect(effect: Effect) -> void` — append + recompute.
  - `func tick_effects() -> void` — tick all, drop expired, recompute.
  - `func on_upkeep() -> void` / `func on_end() -> void` — per-phase hooks (regen wired in Wave B; Slow ticks in `on_end`).

- [ ] **Step 1: Write the failing test** — append to `tests/test_effect.gd`, inside `_initialize()` just before the final `print(...)`:

```gdscript
	# --- Combatant: attaching Slow lowers derived current_initiative; expiry restores it ---
	var c: Combatant = Combatant.new()
	c.display_name = "Martin"
	c.max_hp = 40
	c.base_initiative = 50
	c.recompute_initiative()
	_check(c.current_initiative == 50, "current_initiative derives from base (got %d)" % c.current_initiative)

	c.attach_effect(EffectLibrary.make(&"slow"))
	_check(c.current_initiative == 30, "Slow -20 -> current_initiative 30 (got %d)" % c.current_initiative)

	c.on_end()  # tick 1: duration 2 -> 1, still attached
	_check(c.current_initiative == 30, "still slowed after 1 turn (got %d)" % c.current_initiative)
	_check(c.active_effects.size() == 1, "slow still attached after 1 tick (got %d)" % c.active_effects.size())

	c.on_end()  # tick 2: duration 1 -> 0, expires and detaches
	_check(c.current_initiative == 50, "initiative restored after Slow expires (got %d)" % c.current_initiative)
	_check(c.active_effects.is_empty(), "slow detached on expiry (got %d)" % c.active_effects.size())

	# --- Two combatants don't share a duration counter ---
	var c1: Combatant = Combatant.new(); c1.base_initiative = 50; c1.recompute_initiative()
	var c2: Combatant = Combatant.new(); c2.base_initiative = 50; c2.recompute_initiative()
	c1.attach_effect(EffectLibrary.make(&"slow"))
	c2.attach_effect(EffectLibrary.make(&"slow"))
	c1.on_end()
	_check(c2.active_effects[0].duration == 2, "c2 slow unaffected by c1 tick (got %d)" % c2.active_effects[0].duration)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Godot_v4.6.3-stable_win64 --headless --path . --script res://tests/test_effect.gd`
Expected: FAIL — `base_initiative`/`recompute_initiative`/`attach_effect`/`on_end` not defined.

- [ ] **Step 3: Modify `combat/combatant.gd`** — add the live-state fields after the existing `current_initiative` declaration:

Find:
```gdscript
## The live turn-order sort key (DESIGN.md §4.1). Effects modify this with a duration.
var current_initiative: int = 0
```
Replace with:
```gdscript
## The live turn-order sort key (DESIGN.md §4.1) — DERIVED: base_initiative + active modifiers.
## Set via [method recompute_initiative]; never mutated directly by effects.
var current_initiative: int = 0

## The raw rolled Initiative (TurnManager.roll_initiative). current_initiative builds on this.
var base_initiative: int = 0

## Active buffs/debuffs/riders (DESIGN.md §4.1, A4). Ticked in [method on_end]; own copies (duplicated).
var active_effects: Array[Effect] = []
```

Then add this Public-API block at the end of the file:
```gdscript
# ---------------------------------------------------------------------------
# Effects & turn-order
# ---------------------------------------------------------------------------

## Recomputes current_initiative as base + the sum of active INITIATIVE_MOD magnitudes (rounded).
func recompute_initiative() -> void:
	var total: float = 0.0
	for e: Effect in active_effects:
		if e != null and e.kind == Effect.Kind.INITIATIVE_MOD:
			total += e.magnitude
	current_initiative = base_initiative + int(roundf(total))

## Attaches an effect (already a fresh/duplicated instance) and updates the derived sort key.
func attach_effect(effect: Effect) -> void:
	if effect == null:
		return
	active_effects.append(effect)
	recompute_initiative()

## Ticks every active effect one bearer-turn, drops the expired ones, and recomputes initiative.
func tick_effects() -> void:
	for e: Effect in active_effects:
		e.tick()
	active_effects = active_effects.filter(func(e: Effect) -> bool: return not e.is_expired())
	recompute_initiative()

# ---------------------------------------------------------------------------
# Per-turn phase hooks (called by the orchestrator off PhaseManager.phase_changed)
# ---------------------------------------------------------------------------

## Start-of-turn bookkeeping: resource regen (Wave B) + refresh the derived sort key.
func on_upkeep() -> void:
	recompute_initiative()

## End-of-turn bookkeeping: tick effect durations (Slow counts down here — DESIGN.md §4.8).
func on_end() -> void:
	tick_effects()
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `Godot_v4.6.3-stable_win64 --headless --path . --script res://tests/test_effect.gd`
Expected: PASS — `EFFECT TEST PASSED`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add combat/combatant.gd tests/test_effect.gd
git commit -m "feat(combat): derive current_initiative; add effect attach/tick + phase hooks"
```

---

### Task A3: `TurnManager` rolls into `base_initiative`

**Files:**
- Modify: `combat/turn_manager.gd:44-48`
- Test: `tests/test_turn_manager.gd` (existing — must stay green; add one assertion)

**Interfaces:**
- Consumes: `Combatant.base_initiative`, `Combatant.recompute_initiative()` (Task A2).
- Produces: `roll_initiative()` now sets `base_initiative` and derives `current_initiative` (range unchanged, 1–100).

- [ ] **Step 1: Add the failing assertion** — in `tests/test_turn_manager.gd`, inside section A's loop body, after the existing range check append:

Find:
```gdscript
		for c: Combatant in tm.combatants:
			if c.current_initiative < 1 or c.current_initiative > 100:
				out_of_range += 1
```
Replace with:
```gdscript
		for c: Combatant in tm.combatants:
			if c.current_initiative < 1 or c.current_initiative > 100:
				out_of_range += 1
			if c.base_initiative != c.current_initiative:
				out_of_range += 1  # with no effects, current must equal base
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Godot_v4.6.3-stable_win64 --headless --path . --script res://tests/test_turn_manager.gd`
Expected: FAIL — `base_initiative` is still 0 while `current_initiative` is rolled (counts as out-of-range).

- [ ] **Step 3: Modify `combat/turn_manager.gd`** — in `roll_initiative()`:

Find:
```gdscript
	for c: Combatant in combatants:
		var value: int = InitiativeReel.roll_percentile(_initiative_tens, _initiative_ones)
		c.current_initiative = value
		initiative_rolled.emit(c, value)
```
Replace with:
```gdscript
	for c: Combatant in combatants:
		var value: int = InitiativeReel.roll_percentile(_initiative_tens, _initiative_ones)
		c.base_initiative = value
		c.recompute_initiative()
		initiative_rolled.emit(c, value)
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `Godot_v4.6.3-stable_win64 --headless --path . --script res://tests/test_turn_manager.gd`
Expected: PASS — `TURN MANAGER TEST PASSED`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add combat/turn_manager.gd tests/test_turn_manager.gd
git commit -m "feat(combat): roll_initiative seeds base_initiative + derived current"
```

---

### Task A4: `CombatResolver` reports the Crushing rider on crit-success

**Files:**
- Modify: `combat/combat_resolver.gd` (`AttackResult`, `_resolve_single`)
- Test: `tests/test_crushing_slow.gd` (new — resolver half this task; TurnManager re-sort half in Task A5's integration check, but the deterministic logic lives here)

**Interfaces:**
- Consumes: `ReelFace`, `ActionReel`, `DamageType.inherent_rider_id`.
- Produces: `AttackResult.rider_effect_id: StringName` — set to the reel type's `inherent_rider_id` ONLY when the landed face is `CRIT_SUCCESS`; empty otherwise.

- [ ] **Step 1: Write the failing test** — create `tests/test_crushing_slow.gd`:

```gdscript
extends SceneTree

# Headless test: a Crushing crit-success reports the Slow rider; ordinary hits do not.
# Also verifies the end-to-end re-sort: applying Slow drops the bearer in get_turn_order().
# Run: Godot_v4.6.3-stable_win64 --headless --path . --script res://tests/test_crushing_slow.gd

var _failures: int = 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _one_face_reel(tier: ReelFace.ResultTier, mult: float, type: DamageType) -> ActionReel:
	var r: ActionReel = ActionReel.new()
	r.damage_type = type
	var f: ReelFace = ReelFace.new()
	f.result_tier = tier
	f.multiplier = mult
	r.faces.append(f)
	return r

func _initialize() -> void:
	var crushing: DamageType = load("res://combat/resources/types/crushing.tres")
	var earth: DamageType = load("res://combat/resources/types/earth.tres")
	_check(crushing.inherent_rider_id == &"slow", "crushing.tres carries the slow rider id")

	var resolver: CombatResolver = CombatResolver.new()

	# --- Crit-success on a Crushing reel reports the slow rider ---
	var crit_reels: Array[ActionReel] = [_one_face_reel(ReelFace.ResultTier.CRIT_SUCCESS, 2.0, crushing)]
	var crit: Array = resolver.resolve_combat_phase(crit_reels, 8.0, earth)
	_check(crit[0].rider_effect_id == &"slow", "crit-success Crushing -> rider 'slow' (got %s)" % str(crit[0].rider_effect_id))

	# --- An ordinary success does NOT report a rider (rider is crit-only) ---
	var hit_reels: Array[ActionReel] = [_one_face_reel(ReelFace.ResultTier.SUCCESS, 1.0, crushing)]
	var hit: Array = resolver.resolve_combat_phase(hit_reels, 8.0, earth)
	_check(hit[0].rider_effect_id == &"", "plain success Crushing -> no rider (got %s)" % str(hit[0].rider_effect_id))

	# --- End-to-end: applying the rider drops the bearer in turn order ---
	var pc: Combatant = Combatant.new(); pc.display_name = "Martin"; pc.is_player = true; pc.max_hp = 40
	pc.base_initiative = 60; pc.recompute_initiative(); pc.start_combat()
	var enemy: Combatant = Combatant.new(); enemy.display_name = "Rat"; enemy.is_player = false; enemy.max_hp = 30
	enemy.base_initiative = 55; enemy.recompute_initiative(); enemy.start_combat()
	var tm: TurnManager = TurnManager.new(); tm.combatants = [pc, enemy]

	var before: Array[Combatant] = tm.get_turn_order()
	_check(before[0] == pc, "before Slow: Martin (60) acts first")

	pc.attach_effect(EffectLibrary.make(&"slow"))  # 60 - 20 = 40, now below the Rat's 55
	var after: Array[Combatant] = tm.get_turn_order()
	_check(after[0] == enemy, "after Slow: Rat (55) now acts before Martin (40)")
	_check(pc.current_initiative == 40, "Martin slowed to 40 (got %d)" % pc.current_initiative)

	print(("CRUSHING SLOW TEST PASSED" if _failures == 0 else "CRUSHING SLOW TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Godot_v4.6.3-stable_win64 --headless --path . --script res://tests/test_crushing_slow.gd`
Expected: FAIL — `AttackResult` has no `rider_effect_id`.

- [ ] **Step 3: Modify `combat/combat_resolver.gd`** — add the field to `AttackResult`:

Find:
```gdscript
	var final_damage: int = 0                ## After multiplier + type chart, rounded.
	var meter_gain: int = 0                  ## Bonus-Meter charge this face contributed.
```
Replace with:
```gdscript
	var final_damage: int = 0                ## After multiplier + type chart, rounded.
	var meter_gain: int = 0                  ## Bonus-Meter charge this face contributed.
	var rider_effect_id: StringName = &""    ## Rider to apply (crit-success of a riding type); empty = none.
```

Then in `_resolve_single`, find:
```gdscript
		if face.deals_damage():
			var raw: float = base_damage * face.multiplier
			var type_mult: float = reel.damage_type.multiplier_against(target_type) if reel.damage_type != null else 1.0
			attack.final_damage = int(roundf(raw * type_mult))
		attack.meter_gain = _meter_gain_for(face.result_tier)
```
Replace with:
```gdscript
		if face.deals_damage():
			var raw: float = base_damage * face.multiplier
			var type_mult: float = reel.damage_type.multiplier_against(target_type) if reel.damage_type != null else 1.0
			attack.final_damage = int(roundf(raw * type_mult))
		attack.meter_gain = _meter_gain_for(face.result_tier)
		# Crit-success of a type that carries an inherent rider (Crushing → Slow) reports it.
		# The resolver only REPORTS; the orchestrator attaches the Effect (ARCHITECTURE §2).
		if face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS and reel.damage_type != null and reel.damage_type.inherent_rider_id != &"":
			attack.rider_effect_id = reel.damage_type.inherent_rider_id
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `Godot_v4.6.3-stable_win64 --headless --path . --script res://tests/test_crushing_slow.gd`
Expected: PASS — `CRUSHING SLOW TEST PASSED`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add combat/combat_resolver.gd tests/test_crushing_slow.gd
git commit -m "feat(combat): resolver reports crit-success rider (Crushing->Slow)"
```

---

### Task A5: Orchestrator applies Slow + surfaces it (Upkeep/End hooks, pip, re-sort)

**Files:**
- Modify: `combat/combat.gd`
- Modify: `combat/ui/combatant_panel.gd` (add a status line)
- Test: `tests/test_combat_loop.gd` (drive the per-turn hooks; integration smoke)

**Interfaces:**
- Consumes: `Combatant.on_upkeep/on_end/attach_effect`, `EffectLibrary.make`, `AttackResult.rider_effect_id`, `TurnManager.get_turn_order`.
- Produces: no new public API — wiring + view only. Verified by integration + headless scene compile; the *feel* (pip clarity, the order visibly reshuffling) is the human's call (CLAUDE.md §5).

- [ ] **Step 1: Update the integration test to drive the new per-turn flow** — in `tests/test_combat_loop.gd`, find `_on_turn_started`:

```gdscript
	var defender: Combatant = _enemy if c == _pc else _pc
	var attacks: Array = _resolver.resolve_combat_phase(c.weapon.reels, c.weapon.base_damage, defender.defense_type)
	for a in attacks:
		defender.take_damage(a.final_damage)
		c.bonus_meter.charge(a.face.result_tier)
	_tm.advance_turn()
```
Replace with:
```gdscript
	var defender: Combatant = _enemy if c == _pc else _pc
	c.on_upkeep()
	var attacks: Array = _resolver.resolve_combat_phase(c.weapon.reels, c.weapon.base_damage, defender.defense_type)
	for a in attacks:
		defender.take_damage(a.final_damage)
		c.bonus_meter.charge(a.face.result_tier)
		if a.rider_effect_id != &"":
			defender.attach_effect(EffectLibrary.make(a.rider_effect_id))
	c.on_end()
	_tm.advance_turn()
```

- [ ] **Step 2: Run the integration test to verify it still passes** (the flow change must not break the loop)

Run: `Godot_v4.6.3-stable_win64 --headless --path . --script res://tests/test_combat_loop.gd`
Expected: PASS — `COMBAT LOOP TEST PASSED`, exit 0. (Slow may or may not proc with random reels; the fight must still resolve to a winner within 200 turns.)

- [ ] **Step 3: Wire the phase hooks in `combat/combat.gd`** — in `_on_phase_changed`:

Find:
```gdscript
func _on_phase_changed(phase: PhaseManager.Phase) -> void:
	_phase_label.text = "Phase: %s" % PhaseManager.Phase.keys()[phase]
```
Replace with:
```gdscript
func _on_phase_changed(phase: PhaseManager.Phase) -> void:
	_phase_label.text = "Phase: %s" % PhaseManager.Phase.keys()[phase]
	if _attacker == null:
		return
	if phase == PhaseManager.Phase.UPKEEP:
		_attacker.on_upkeep()
		(_panels[_attacker] as CombatantPanel).refresh_status()
	elif phase == PhaseManager.Phase.END:
		_attacker.on_end()
		(_panels[_attacker] as CombatantPanel).refresh_status()
```

- [ ] **Step 4: Apply the rider in `combat/combat.gd._apply_attack`** — find:

```gdscript
	if _attacker.bonus_meter != null:
		_attacker.bonus_meter.charge(attack.face.result_tier)
```
Replace with:
```gdscript
	if _attacker.bonus_meter != null:
		_attacker.bonus_meter.charge(attack.face.result_tier)
	if attack.rider_effect_id != &"":
		var rider: Effect = EffectLibrary.make(attack.rider_effect_id)
		if rider != null:
			_defender.attach_effect(rider)
			_log("  %s is afflicted with %s (%d turns)." % [_defender.display_name, String(rider.id).to_upper(), rider.duration])
			(_panels[_defender] as CombatantPanel).refresh_status()
			_turn_order_bar.set_order(_turn_manager.get_turn_order())
```

- [ ] **Step 5: Add a status line to `combat/ui/combatant_panel.gd`** — add a `Label` child in its builder and this method (match the file's existing node-creation style; the exact layout is cosmetic):

```gdscript
## Refreshes the active-effect line (e.g. "SLOW -20 (1)"). Called by the orchestrator on
## Upkeep/End and when a rider is applied. Empty when no effects are active.
func refresh_status() -> void:
	if _combatant == null or _status_label == null:
		return
	var parts: PackedStringArray = []
	for e: Effect in _combatant.active_effects:
		parts.append("%s %d (%d)" % [String(e.id).to_upper(), int(e.magnitude), e.duration])
	_status_label.text = ", ".join(parts)
```
(Declare `var _status_label: Label`, create it in the panel builder near the HP/meter bars, and store the bound combatant as `_combatant` if the panel does not already. Follow the panel's existing `bind()` pattern.)

- [ ] **Step 6: Headless compile + scene check, then full suite**

Run: `Godot_v4.6.3-stable_win64 --headless --path . --editor --quit`
Expected: exits 0 with no parse/script errors.
Then run all suites:
```bash
for t in effect crushing_slow turn_manager combatant phase_manager bonus_meter combat_loop action_reel; do
  Godot_v4.6.3-stable_win64 --headless --path . --script res://tests/test_$t.gd || echo "FAILED: $t"
done
```
Expected: every suite prints `… TEST PASSED`.

- [ ] **Step 7: Commit**

```bash
git add combat/combat.gd combat/ui/combatant_panel.gd tests/test_combat_loop.gd
git commit -m "feat(combat): apply Crushing->Slow in orchestrator + status pip + re-sort"
```

> **WAVE A REVIEW CHECKPOINT** — request code review (superpowers:requesting-code-review) before Wave B. Human play-test: a rat crit on its Crushing reel should slow Martin and visibly drop him in the turn-order bar next round.

---

## WAVE B — `ResourcePool` (Stamina only)

### Task B1: `ResourcePool` data class

**Files:**
- Create: `combat/resource_pool.gd`
- Test: `tests/test_resource_pool.gd`

**Interfaces:**
- Produces: `ResourcePool` (extends RefCounted): `var stamina: int`, `var max_stamina: int`, `var regen_per_turn: int`; `signal pool_changed(kind: StringName, value: int, max: int)`; `func can_afford(cost: Dictionary) -> bool`; `func spend(cost: Dictionary) -> bool`; `func regen() -> void`. `cost` is keyed by resource StringName, e.g. `{&"stamina": 2}`.

- [ ] **Step 1: Write the failing test** — create `tests/test_resource_pool.gd`:

```gdscript
extends SceneTree

# Headless unit test for ResourcePool (DESIGN.md §10 Dec 6; ARCHITECTURE §7).
# Stamina-only for the prototype. Run:
# Godot_v4.6.3-stable_win64 --headless --path . --script res://tests/test_resource_pool.gd

var _failures: int = 0
var _changed_count: int = 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _on_pool_changed(_kind: StringName, _value: int, _max: int) -> void:
	_changed_count += 1

func _mk() -> ResourcePool:
	var p: ResourcePool = ResourcePool.new()
	p.max_stamina = 5
	p.stamina = 3
	p.regen_per_turn = 1
	return p

func _initialize() -> void:
	var p: ResourcePool = _mk()
	_check(p.can_afford({&"stamina": 2}), "can afford 2 of 3")
	_check(not p.can_afford({&"stamina": 4}), "cannot afford 4 of 3")

	p.pool_changed.connect(_on_pool_changed)

	# --- spend deducts and signals ---
	_check(p.spend({&"stamina": 2}), "spend(2) succeeds")
	_check(p.stamina == 1, "stamina 3 -> 1 (got %d)" % p.stamina)
	_check(_changed_count == 1, "pool_changed fired on spend (got %d)" % _changed_count)

	# --- spend refuses when short: no mutation, no signal ---
	_check(not p.spend({&"stamina": 2}), "spend(2) refused at stamina 1")
	_check(p.stamina == 1, "stamina unchanged after refused spend (got %d)" % p.stamina)
	_check(_changed_count == 1, "no signal on refused spend (got %d)" % _changed_count)

	# --- regen adds and clamps at max ---
	p.regen()
	_check(p.stamina == 2, "regen +1 -> 2 (got %d)" % p.stamina)
	p.stamina = 5
	p.regen()
	_check(p.stamina == 5, "regen clamps at max 5 (got %d)" % p.stamina)

	print(("RESOURCE POOL TEST PASSED" if _failures == 0 else "RESOURCE POOL TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Refresh class cache, run the test to verify it fails**

Run: `Godot_v4.6.3-stable_win64 --headless --path . --editor --quit`
then: `Godot_v4.6.3-stable_win64 --headless --path . --script res://tests/test_resource_pool.gd`
Expected: FAIL — `ResourcePool` not defined.

- [ ] **Step 3: Write `combat/resource_pool.gd`**

```gdscript
class_name ResourcePool
extends RefCounted

## Stamina/Focus/Mana spent in Main Phase 1 to pay for abilities and reel-count edits
## (DESIGN.md §4.8, §10 Dec 6). FULLY INDEPENDENT of BonusMeter — the Ultimate never touches this.
##
## The prototype uses STAMINA ONLY (a 1v1 duelist is physical; Focus/Mana are unbuilt until a
## class needs them — YAGNI, CLAUDE.md §7). cost dictionaries are keyed by resource StringName
## (e.g. {&"stamina": 2}) so Focus/Mana slot in later without changing signatures.

## Emitted whenever a resource value changes, for UI binding.
signal pool_changed(kind: StringName, value: int, max: int)

## [ASSUMPTION] placeholder economy — partial regen is what makes spending a trade-off (CLAUDE.md §4).
var stamina: int = 0
var max_stamina: int = 0
var regen_per_turn: int = 0

## True if every entry in [param cost] is currently affordable.
func can_afford(cost: Dictionary) -> bool:
	return stamina >= int(cost.get(&"stamina", 0))

## Spends [param cost] atomically. Returns false and changes nothing if unaffordable.
func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	var amount: int = int(cost.get(&"stamina", 0))
	if amount == 0:
		return true  # nothing to spend, no signal churn
	stamina -= amount
	pool_changed.emit(&"stamina", stamina, max_stamina)
	return true

## Upkeep regeneration: adds [member regen_per_turn], clamped at [member max_stamina].
func regen() -> void:
	var before: int = stamina
	stamina = mini(stamina + regen_per_turn, max_stamina)
	if stamina != before:
		pool_changed.emit(&"stamina", stamina, max_stamina)
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `Godot_v4.6.3-stable_win64 --headless --path . --script res://tests/test_resource_pool.gd`
Expected: PASS — `RESOURCE POOL TEST PASSED`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add combat/resource_pool.gd tests/test_resource_pool.gd
git commit -m "feat(combat): add ResourcePool (Stamina-only prototype economy)"
```

---

### Task B2: Wire `ResourcePool` onto `Combatant` + Upkeep regen + panel display

**Files:**
- Modify: `combat/combatant.gd` (field + regen in `on_upkeep`)
- Modify: `combat/combat.gd` (`_make_combatant` seeds the pool; panel shows it)
- Modify: `combat/ui/combatant_panel.gd` (Stamina line)
- Test: `tests/test_effect.gd` (append: `on_upkeep` regenerates the pool)

**Interfaces:**
- Consumes: `ResourcePool` (Task B1).
- Produces: `Combatant.resource_pool: ResourcePool`; `on_upkeep()` now calls `resource_pool.regen()` when present.

- [ ] **Step 1: Write the failing test** — append to `tests/test_effect.gd`, just before the final `print(...)`:

```gdscript
	# --- on_upkeep regenerates the resource pool when present ---
	var rc: Combatant = Combatant.new()
	rc.base_initiative = 50
	rc.resource_pool = ResourcePool.new()
	rc.resource_pool.max_stamina = 5
	rc.resource_pool.stamina = 1
	rc.resource_pool.regen_per_turn = 1
	rc.on_upkeep()
	_check(rc.resource_pool.stamina == 2, "on_upkeep regens stamina 1 -> 2 (got %d)" % rc.resource_pool.stamina)

	# --- on_upkeep is safe when no pool is attached ---
	var np: Combatant = Combatant.new()
	np.base_initiative = 50
	np.on_upkeep()
	_check(np.resource_pool == null, "on_upkeep no-ops without a pool")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Godot_v4.6.3-stable_win64 --headless --path . --script res://tests/test_effect.gd`
Expected: FAIL — `Combatant.resource_pool` not defined.

- [ ] **Step 3: Modify `combat/combatant.gd`** — add the field after `bonus_meter`:

Find:
```gdscript
## The Bonus Meter (PCs + Elite/Boss only; null for trash enemies).
var bonus_meter: BonusMeter
```
Replace with:
```gdscript
## The Bonus Meter (PCs + Elite/Boss only; null for trash enemies).
var bonus_meter: BonusMeter

## Stamina/Focus/Mana spent in Main 1 (DESIGN.md §10 Dec 6). Null = no resource economy.
var resource_pool: ResourcePool
```

Then update `on_upkeep`:
```gdscript
func on_upkeep() -> void:
	if resource_pool != null:
		resource_pool.regen()
	recompute_initiative()
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `Godot_v4.6.3-stable_win64 --headless --path . --script res://tests/test_effect.gd`
Expected: PASS — `EFFECT TEST PASSED`, exit 0.

- [ ] **Step 5: Seed the pool in `combat/combat.gd._make_combatant`** — find:

```gdscript
	var meter: BonusMeter = BonusMeter.new()
	meter.cap = 10
	meter.floor = 3
	meter.is_visible = meter_visible
	c.bonus_meter = meter
	c.start_combat()
	return c
```
Replace with:
```gdscript
	var meter: BonusMeter = BonusMeter.new()
	meter.cap = 10
	meter.floor = 3
	meter.is_visible = meter_visible
	c.bonus_meter = meter
	# [ASSUMPTION] Stamina economy — only the player uses Main-1 actions in the prototype.
	if is_player:
		var pool: ResourcePool = ResourcePool.new()
		pool.max_stamina = 5
		pool.stamina = 3
		pool.regen_per_turn = 1
		c.resource_pool = pool
	c.start_combat()
	return c
```

- [ ] **Step 6: Show Stamina in `combat/ui/combatant_panel.gd`** — add a `_stamina_label: Label` child and refresh it in `bind()` / a `refresh_status()` extension:

```gdscript
## Updates the Stamina readout (blank when the combatant has no pool). Call from bind()+on_upkeep.
func refresh_resources() -> void:
	if _stamina_label == null:
		return
	if _combatant == null or _combatant.resource_pool == null:
		_stamina_label.text = ""
		return
	_stamina_label.text = "STA %d/%d" % [_combatant.resource_pool.stamina, _combatant.resource_pool.max_stamina]
```
Call `refresh_resources()` from `bind()`, and add a `refresh_resources()` call alongside the existing `refresh_status()` calls in `combat.gd._on_phase_changed`.

- [ ] **Step 7: Headless compile + run effect + scene check**

Run: `Godot_v4.6.3-stable_win64 --headless --path . --editor --quit`
Expected: exits 0, no errors.
Then: `Godot_v4.6.3-stable_win64 --headless --path . --script res://tests/test_effect.gd` → PASS.

- [ ] **Step 8: Commit**

```bash
git add combat/combatant.gd combat/combat.gd combat/ui/combatant_panel.gd tests/test_effect.gd
git commit -m "feat(combat): attach ResourcePool to player; regen in Upkeep; show Stamina"
```

> **WAVE B REVIEW CHECKPOINT** — request code review before Wave C. (No new player verb yet; the Stamina bar should tick +1 each of the player's Upkeeps, capped at 5.)

---

## WAVE C — Main-Phase reel splice

### Task C1: `PhaseManager` Main-1 pause contract

**Files:**
- Modify: `combat/phase_manager.gd`
- Test: `tests/test_phase_manager.gd` (rewrite to the new contract)

**Interfaces:**
- Produces: `start_turn()` runs Upkeep → Main 1, then **pauses**; new `proceed_to_combat()` enters Combat then pauses; `resume_after_combat()` unchanged (Main 2 → End → `turn_finished`).

- [ ] **Step 1: Rewrite the test to the new contract** — replace the body of `_initialize()` in `tests/test_phase_manager.gd`:

```gdscript
func _initialize() -> void:
	var pm: PhaseManager = PhaseManager.new()
	pm.phase_changed.connect(_on_phase_changed)
	pm.turn_finished.connect(_on_turn_finished)

	# start_turn() runs Upkeep -> Main 1, then PAUSES for the player's Main-1 actions.
	pm.start_turn()
	_check(_phase_log == [PhaseManager.Phase.UPKEEP, PhaseManager.Phase.MAIN_1],
		"start_turn pauses at Main 1: %s" % str(_phase_log))
	_check(pm.current_phase == PhaseManager.Phase.MAIN_1, "current_phase is MAIN_1 while paused")

	# proceed_to_combat() enters Combat and pauses for the spin.
	pm.proceed_to_combat()
	_check(_phase_log == [PhaseManager.Phase.UPKEEP, PhaseManager.Phase.MAIN_1, PhaseManager.Phase.COMBAT],
		"proceed_to_combat enters Combat: %s" % str(_phase_log))
	_check(pm.current_phase == PhaseManager.Phase.COMBAT, "current_phase is COMBAT while paused")
	_check(_turn_finished_count == 0, "turn not finished before spin resolves")

	# resume_after_combat() finishes Main 2 -> End and ends the turn.
	pm.resume_after_combat()
	_check(_phase_log == [
			PhaseManager.Phase.UPKEEP, PhaseManager.Phase.MAIN_1, PhaseManager.Phase.COMBAT,
			PhaseManager.Phase.MAIN_2, PhaseManager.Phase.END],
		"full phase order: %s" % str(_phase_log))
	_check(_turn_finished_count == 1, "turn_finished fired once (got %d)" % _turn_finished_count)

	print(("PHASE MANAGER TEST PASSED" if _failures == 0 else "PHASE MANAGER TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Godot_v4.6.3-stable_win64 --headless --path . --script res://tests/test_phase_manager.gd`
Expected: FAIL — `start_turn` still advances to Combat; `proceed_to_combat` undefined.

- [ ] **Step 3: Modify `combat/phase_manager.gd`** — replace `start_turn()`:

Find:
```gdscript
## Runs Upkeep and Main 1, then stops on Combat awaiting the spin.
func start_turn() -> void:
	_enter(Phase.UPKEEP)
	_enter(Phase.MAIN_1)
	_enter(Phase.COMBAT)
```
Replace with:
```gdscript
## Runs Upkeep and Main 1, then PAUSES — the player acts in Main 1 (splice reels, fire Ultimate)
## before committing to the spin via [method proceed_to_combat].
func start_turn() -> void:
	_enter(Phase.UPKEEP)
	_enter(Phase.MAIN_1)

## Commits Main 1 and enters the Combat phase, pausing for the spin (DESIGN.md §4.8).
func proceed_to_combat() -> void:
	_enter(Phase.COMBAT)
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `Godot_v4.6.3-stable_win64 --headless --path . --script res://tests/test_phase_manager.gd`
Expected: PASS — `PHASE MANAGER TEST PASSED`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add combat/phase_manager.gd tests/test_phase_manager.gd
git commit -m "feat(combat): PhaseManager pauses at Main 1; add proceed_to_combat"
```

---

### Task C2: `Combatant` per-turn reels + Storm splice

**Files:**
- Modify: `combat/combatant.gd`
- Test: `tests/test_reel_splice.gd`

**Interfaces:**
- Consumes: `Weapon.reels`, `ActionReel.make_default`, `DamageType`, `ResourcePool`.
- Produces, on `Combatant`:
  - `var turn_reels: Array[ActionReel]`
  - `func begin_turn() -> void` — `turn_reels = weapon.reels.duplicate()`.
  - `func try_splice_reel(type: DamageType, base_damage: float, cost: int, cap: int) -> bool` — if affordable AND `turn_reels.size() < cap`: spend, append `ActionReel.make_default(type)`, return true; else false (no mutation).

- [ ] **Step 1: Write the failing test** — create `tests/test_reel_splice.gd`:

```gdscript
extends SceneTree

# Headless test: Main-1 reel splice is additive, costs Stamina, and respects the 5-reel band.
# Run: Godot_v4.6.3-stable_win64 --headless --path . --script res://tests/test_reel_splice.gd

var _failures: int = 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _mk_pc(stamina: int) -> Combatant:
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")
	var w: Weapon = Weapon.new()
	w.base_damage = 10.0
	for i: int in range(3):
		w.reels.append(ActionReel.make_default(slashing))
	var c: Combatant = Combatant.new()
	c.weapon = w
	c.resource_pool = ResourcePool.new()
	c.resource_pool.max_stamina = 5
	c.resource_pool.stamina = stamina
	return c

func _initialize() -> void:
	var storm: DamageType = load("res://combat/resources/types/storm.tres")

	# --- begin_turn copies the weapon loadout (does not alias it) ---
	var c: Combatant = _mk_pc(3)
	c.begin_turn()
	_check(c.turn_reels.size() == 3, "begin_turn -> 3 turn reels (got %d)" % c.turn_reels.size())

	# --- splice appends one Storm reel and costs 2 Stamina ---
	var ok: bool = c.try_splice_reel(storm, c.weapon.base_damage, 2, 5)
	_check(ok, "splice succeeds with 3 stamina")
	_check(c.turn_reels.size() == 4, "splice -> 4 turn reels (got %d)" % c.turn_reels.size())
	_check(c.turn_reels[3].damage_type == storm, "spliced reel is Storm-typed")
	_check(c.resource_pool.stamina == 1, "splice cost 2 stamina (3 -> %d)" % c.resource_pool.stamina)
	_check(c.weapon.reels.size() == 3, "weapon loadout untouched (additive only, got %d)" % c.weapon.reels.size())

	# --- second splice refused: cannot afford (1 < 2), no mutation ---
	var ok2: bool = c.try_splice_reel(storm, c.weapon.base_damage, 2, 5)
	_check(not ok2, "second splice refused at 1 stamina")
	_check(c.turn_reels.size() == 4, "no reel added on refused splice (got %d)" % c.turn_reels.size())
	_check(c.resource_pool.stamina == 1, "stamina unchanged on refused splice (got %d)" % c.resource_pool.stamina)

	# --- band ceiling: cannot exceed 5 reels even with stamina to spare ---
	var c2: Combatant = _mk_pc(5)
	c2.begin_turn()
	_check(c2.try_splice_reel(storm, 10.0, 1, 5), "splice 4th reel ok")
	_check(c2.try_splice_reel(storm, 10.0, 1, 5), "splice 5th reel ok")
	_check(not c2.try_splice_reel(storm, 10.0, 1, 5), "6th splice refused at 5-reel cap")
	_check(c2.turn_reels.size() == 5, "capped at 5 reels (got %d)" % c2.turn_reels.size())

	# --- next turn resets the loadout (splice is this-turn-only) ---
	c.begin_turn()
	_check(c.turn_reels.size() == 3, "begin_turn resets to 3 (got %d)" % c.turn_reels.size())

	print(("REEL SPLICE TEST PASSED" if _failures == 0 else "REEL SPLICE TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Godot_v4.6.3-stable_win64 --headless --path . --script res://tests/test_reel_splice.gd`
Expected: FAIL — `begin_turn`/`try_splice_reel`/`turn_reels` not defined.

- [ ] **Step 3: Modify `combat/combatant.gd`** — add the field after `active_effects`:

```gdscript
## The reels actually spun this Combat Phase: a per-turn copy of weapon.reels that Main-1 actions
## edit ADDITIVELY (DESIGN.md §8 "resolved set of reels"). Reset each turn by [method begin_turn].
var turn_reels: Array[ActionReel] = []
```

Then add to the Public API:
```gdscript
# ---------------------------------------------------------------------------
# Per-turn reel loadout (Main-Phase editing — DESIGN.md §4.8)
# ---------------------------------------------------------------------------

## Resets this turn's reel set to the weapon baseline. Call at the start of the turn (Upkeep/Main 1).
func begin_turn() -> void:
	turn_reels = weapon.reels.duplicate() if weapon != null else []

## Splices one extra [param type]-typed reel onto THIS turn (additive, never overwrites the weapon).
## Spends [param cost] Stamina and respects the [param cap]-reel band ceiling. Returns false (and
## changes nothing) if unaffordable or already at the cap (DESIGN.md §4.3, §4.8).
func try_splice_reel(type: DamageType, base_damage: float, cost: int, cap: int) -> bool:
	if turn_reels.size() >= cap:
		return false
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	turn_reels.append(ActionReel.make_default(type))
	return true
```

> Implementer note: `ActionReel.make_default(type)` builds the default 10-face composition typed
> `type`. The spliced reel's damage uses the spinning weapon's `base_damage` at resolve time (the
> resolver takes `base_damage` as a parameter), so nothing per-reel needs storing here. `base_damage`
> stays in the signature for forward-compatibility with future per-reel base damage.

- [ ] **Step 4: Run the test to verify it passes**

Run: `Godot_v4.6.3-stable_win64 --headless --path . --script res://tests/test_reel_splice.gd`
Expected: PASS — `REEL SPLICE TEST PASSED`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add combat/combatant.gd tests/test_reel_splice.gd
git commit -m "feat(combat): per-turn reel loadout + additive Storm splice"
```

---

### Task C3: Orchestrator — interactive Main 1, splice button, spin from `turn_reels`

**Files:**
- Modify: `combat/combat.gd`
- Test: `tests/test_combat_loop.gd` (drive `begin_turn` + spin from `turn_reels`)

**Interfaces:**
- Consumes: `Combatant.begin_turn/try_splice_reel/turn_reels`, `PhaseManager.proceed_to_combat`.
- Produces: view/wiring only. SPIN reframed as "commit Main 1 and spin"; new "Splice Storm reel (2 STA)" button; spin resolves `_attacker.turn_reels`.

- [ ] **Step 1: Update the integration test to spin from `turn_reels`** — in `tests/test_combat_loop.gd._on_turn_started`, change the resolve call:

Find:
```gdscript
	c.on_upkeep()
	var attacks: Array = _resolver.resolve_combat_phase(c.weapon.reels, c.weapon.base_damage, defender.defense_type)
```
Replace with:
```gdscript
	c.on_upkeep()
	c.begin_turn()
	var attacks: Array = _resolver.resolve_combat_phase(c.turn_reels, c.weapon.base_damage, defender.defense_type)
```

- [ ] **Step 2: Run the integration test to verify it still passes**

Run: `Godot_v4.6.3-stable_win64 --headless --path . --script res://tests/test_combat_loop.gd`
Expected: PASS — `COMBAT LOOP TEST PASSED` (spinning `turn_reels` == `weapon.reels` here, so the fight still resolves).

- [ ] **Step 3: Reframe the turn flow in `combat/combat.gd`** — three edits.

(a) In `_on_turn_started`, after `_phase_manager.start_turn()` the manager now pauses at Main 1 (not Combat). Initialize the per-turn reels and prepare strips from them. Find:
```gdscript
	_phase_manager.start_turn()  # runs Upkeep → Main 1 → Combat, pauses for the spin
	_prepare_strips(c.weapon.reels)
```
Replace with:
```gdscript
	c.begin_turn()
	_phase_manager.start_turn()  # runs Upkeep → Main 1, pauses for Main-1 actions
	_prepare_strips(c.turn_reels)
	_refresh_main1_actions()
```

(b) In `_on_spin_pressed` (the player's commit), enter Combat before spinning. Find:
```gdscript
func _on_spin_pressed() -> void:
	if not _awaiting_player_spin:
		return
	_awaiting_player_spin = false
	_spin_button.disabled = true
	_do_spin()
```
Replace with:
```gdscript
func _on_spin_pressed() -> void:
	if not _awaiting_player_spin:
		return
	_awaiting_player_spin = false
	_spin_button.disabled = true
	_splice_button.disabled = true
	_phase_manager.proceed_to_combat()  # commit Main 1 → enter Combat
	_do_spin()
```

(c) In `_do_spin`, the enemy path must also enter Combat first, and the spin resolves `turn_reels`. Find:
```gdscript
func _do_spin() -> void:
	var reels: Array[ActionReel] = _attacker.weapon.reels
	var attacks: Array = _resolver.resolve_combat_phase(reels, _attacker.weapon.base_damage, _defender.defense_type)
```
Replace with:
```gdscript
func _do_spin() -> void:
	if _phase_manager.current_phase != PhaseManager.Phase.COMBAT:
		_phase_manager.proceed_to_combat()  # enemy auto-commit (player committed in _on_spin_pressed)
	var reels: Array[ActionReel] = _attacker.turn_reels
	var attacks: Array = _resolver.resolve_combat_phase(reels, _attacker.weapon.base_damage, _defender.defense_type)
```

- [ ] **Step 4: Add the Splice button** — in `_build_ui()`, after the END TURN button is created, add:

```gdscript
	_splice_button = Button.new()
	_splice_button.text = "Splice Storm reel (2 STA)"
	_splice_button.position = Vector2(900, 392)
	_splice_button.custom_minimum_size = Vector2(210, 52)
	_splice_button.disabled = true
	add_child(_splice_button)
```
Declare `var _splice_button: Button` with the other button vars, connect it in `_bind_signals()`:
```gdscript
	_splice_button.pressed.connect(_on_splice_pressed)
```
Load Storm once in `_build_scenario` alongside the other types: `var storm: DamageType = load("res://combat/resources/types/storm.tres")` and store it: declare `var _storm_type: DamageType` and set `_storm_type = storm`.

Add the handler and the Main-1 refresh helper:
```gdscript
## [ASSUMPTION] splice cost 2 Stamina, band ceiling 5 (CLAUDE.md §4).
func _on_splice_pressed() -> void:
	if not _awaiting_player_spin:
		return
	if _attacker.try_splice_reel(_storm_type, _attacker.weapon.base_damage, 2, 5):
		_prepare_strips(_attacker.turn_reels)
		_log("  %s splices a Storm reel (now %d reels)." % [_attacker.display_name, _attacker.turn_reels.size()])
		(_panels[_attacker] as CombatantPanel).refresh_resources()
	_refresh_main1_actions()

## Enables/disables the Main-1 action buttons for the current player turn.
func _refresh_main1_actions() -> void:
	var is_player_main1: bool = _awaiting_player_spin and _attacker != null and _attacker.is_player
	var pool: ResourcePool = _attacker.resource_pool if _attacker != null else null
	_splice_button.disabled = not (is_player_main1 and pool != null \
		and pool.can_afford({&"stamina": 2}) and _attacker.turn_reels.size() < 5)
```
Call `_refresh_main1_actions()` at the end of `_on_turn_started` (already added in Step 3a) and after the spin completes set `_splice_button.disabled = true` in `_finish_spin`.

- [ ] **Step 5: Headless compile + full suite**

Run: `Godot_v4.6.3-stable_win64 --headless --path . --editor --quit` → exits 0.
Then run every suite (effect, resource_pool, crushing_slow, reel_splice, turn_manager, combatant, phase_manager, bonus_meter, combat_loop, action_reel) → all `… TEST PASSED`.

- [ ] **Step 6: Commit**

```bash
git add combat/combat.gd tests/test_combat_loop.gd
git commit -m "feat(combat): interactive Main 1 + Storm splice button; spin from turn_reels"
```

> **WAVE C REVIEW CHECKPOINT** — request code review before Wave D. Human play-test: in Main 1 the player can spend 2 STA to add a 4th (Storm-colored) reel before pressing SPIN; the extra reel resolves as its own independent attack.

---

## WAVE D — Sticky-Wild Ultimate

### Task D1: `Combatant` sticky-wild state + `CombatResolver` wild override

**Files:**
- Modify: `combat/combatant.gd` (sticky-wild fields + methods)
- Modify: `combat/combat_resolver.gd` (`wild_reel_indices` param + forced crit face)
- Test: `tests/test_ultimate_sticky_wild.gd`

**Interfaces:**
- Consumes: `BonusMeter.is_armed/consume`, `ActionReel`, `ReelFace`.
- Produces:
  - On `Combatant`: `var sticky_wild_reel: int` (−1 none), `var sticky_wild_spins_remaining: int`; `func fire_sticky_wild(reel_index: int, spins: int) -> bool` (requires armed meter; consumes it; sets state); `func wild_reel_indices() -> Array[int]`; `func consume_wild_spin() -> void`.
  - On `CombatResolver`: `resolve_combat_phase(reels, base_damage, target_type=null, wild_reel_indices: Array[int] = [])` — a wild reel returns its crit-success face instead of a random spin.

- [ ] **Step 1: Write the failing test** — create `tests/test_ultimate_sticky_wild.gd`:

```gdscript
extends SceneTree

# Headless test: Sticky-Wild Ultimate — arm/fire/consume, forced crit for 2 spins, then revert.
# Run: Godot_v4.6.3-stable_win64 --headless --path . --script res://tests/test_ultimate_sticky_wild.gd

var _failures: int = 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _mk_pc() -> Combatant:
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")
	var w: Weapon = Weapon.new()
	w.base_damage = 10.0
	for i: int in range(3):
		w.reels.append(ActionReel.make_default(slashing))
	var c: Combatant = Combatant.new()
	c.weapon = w
	c.bonus_meter = BonusMeter.new()
	c.bonus_meter.cap = 10
	return c

func _initialize() -> void:
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")

	# --- Cannot fire while the meter is not armed ---
	var c: Combatant = _mk_pc()
	c.bonus_meter.value = 9
	_check(not c.fire_sticky_wild(0, 2), "cannot fire below cap")
	_check(c.sticky_wild_spins_remaining == 0, "no wild armed on failed fire")

	# --- Firing consumes the full meter and arms the wild ---
	c.bonus_meter.value = 10
	_check(c.bonus_meter.is_armed(), "meter armed at cap")
	_check(c.fire_sticky_wild(0, 2), "fire succeeds when armed")
	_check(c.bonus_meter.value == 0, "fire consumes the meter (got %d)" % c.bonus_meter.value)
	_check(c.wild_reel_indices() == [0], "reel 0 is wild after firing (got %s)" % str(c.wild_reel_indices()))

	# --- Resolver forces crit-success on the wild reel ---
	var resolver: CombatResolver = CombatResolver.new()
	c.begin_turn()
	var a1: Array = resolver.resolve_combat_phase(c.turn_reels, c.weapon.base_damage, null, c.wild_reel_indices())
	_check(a1[0].face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS, "wild reel forces crit-success (spin 1)")
	c.consume_wild_spin()
	_check(c.sticky_wild_spins_remaining == 1, "1 wild spin left (got %d)" % c.sticky_wild_spins_remaining)

	# --- Second spin still wild, then it reverts ---
	c.begin_turn()
	var a2: Array = resolver.resolve_combat_phase(c.turn_reels, c.weapon.base_damage, null, c.wild_reel_indices())
	_check(a2[0].face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS, "wild reel forces crit-success (spin 2)")
	c.consume_wild_spin()
	_check(c.sticky_wild_spins_remaining == 0, "wild exhausted (got %d)" % c.sticky_wild_spins_remaining)
	_check(c.wild_reel_indices() == [], "no wild reels after exhaustion (got %s)" % str(c.wild_reel_indices()))
	_check(c.sticky_wild_reel == -1, "wild reel cleared on exhaustion (got %d)" % c.sticky_wild_reel)

	# --- Firing never touches the ResourcePool (independent economies) ---
	var c2: Combatant = _mk_pc()
	c2.resource_pool = ResourcePool.new(); c2.resource_pool.max_stamina = 5; c2.resource_pool.stamina = 4
	c2.bonus_meter.value = 10
	c2.fire_sticky_wild(0, 2)
	_check(c2.resource_pool.stamina == 4, "fire does not spend stamina (got %d)" % c2.resource_pool.stamina)

	print(("STICKY WILD TEST PASSED" if _failures == 0 else "STICKY WILD TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Godot_v4.6.3-stable_win64 --headless --path . --script res://tests/test_ultimate_sticky_wild.gd`
Expected: FAIL — `fire_sticky_wild`/`wild_reel_indices`/wild param not defined.

- [ ] **Step 3: Modify `combat/combatant.gd`** — add fields after `turn_reels`:

```gdscript
## Sticky-Wild Ultimate state (DESIGN.md §4.9). sticky_wild_reel = the reel forced to crit-success;
## -1 = none. sticky_wild_spins_remaining counts the spins the wild still applies for.
var sticky_wild_reel: int = -1
var sticky_wild_spins_remaining: int = 0
```

Add to the Public API:
```gdscript
# ---------------------------------------------------------------------------
# Sticky-Wild Ultimate (DESIGN.md §4.9) — costs ONLY the Bonus Meter
# ---------------------------------------------------------------------------

## Fires the Sticky-Wild Ultimate if the meter is armed: consumes the full meter and forces the
## designated reel to land crit-success for the next [param spins] spins. Returns false if not armed.
func fire_sticky_wild(reel_index: int, spins: int) -> bool:
	if bonus_meter == null or not bonus_meter.is_armed():
		return false
	bonus_meter.consume()
	sticky_wild_reel = reel_index
	sticky_wild_spins_remaining = spins
	return true

## The reels currently forced to crit-success (for the resolver). Empty when no wild is active.
func wild_reel_indices() -> Array[int]:
	if sticky_wild_spins_remaining > 0 and sticky_wild_reel >= 0:
		return [sticky_wild_reel]
	return []

## Consumes one sticky-wild spin; clears the wild when exhausted. Call once per resolved spin.
func consume_wild_spin() -> void:
	if sticky_wild_spins_remaining > 0:
		sticky_wild_spins_remaining -= 1
		if sticky_wild_spins_remaining == 0:
			sticky_wild_reel = -1
```

- [ ] **Step 4: Modify `combat/combat_resolver.gd`** — thread the wild param through. Replace `resolve_combat_phase`:

Find:
```gdscript
func resolve_combat_phase(reels: Array[ActionReel], base_damage: float, target_type: DamageType = null) -> Array[AttackResult]:
	spin_started.emit()

	var attacks: Array[AttackResult] = []
	var total_meter: int = 0

	for reel: ActionReel in reels:
		var attack: AttackResult = _resolve_single(reel, base_damage, target_type)
		total_meter += attack.meter_gain
		attacks.append(attack)
		damage_applied.emit(attack)
```
Replace with:
```gdscript
func resolve_combat_phase(reels: Array[ActionReel], base_damage: float, target_type: DamageType = null, wild_reel_indices: Array[int] = []) -> Array[AttackResult]:
	spin_started.emit()

	var attacks: Array[AttackResult] = []
	var total_meter: int = 0

	for i: int in range(reels.size()):
		var is_wild: bool = i in wild_reel_indices
		var attack: AttackResult = _resolve_single(reels[i], base_damage, target_type, is_wild)
		total_meter += attack.meter_gain
		attacks.append(attack)
		damage_applied.emit(attack)
```

Then replace `_resolve_single`'s signature and face selection. Find:
```gdscript
func _resolve_single(reel: ActionReel, base_damage: float, target_type: DamageType) -> AttackResult:
	var face: ReelFace = reel.spin()
```
Replace with:
```gdscript
func _resolve_single(reel: ActionReel, base_damage: float, target_type: DamageType, is_wild: bool = false) -> AttackResult:
	var face: ReelFace = _crit_face(reel) if is_wild else reel.spin()
```

Add the helper at the end of the file:
```gdscript
## Returns the reel's first crit-success face (the Sticky-Wild target). Falls back to a normal
## spin if the reel has no crit-success face, so a wild never crashes on an odd strip.
func _crit_face(reel: ActionReel) -> ReelFace:
	for face: ReelFace in reel.faces:
		if face != null and face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
			return face
	return reel.spin()
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `Godot_v4.6.3-stable_win64 --headless --path . --script res://tests/test_ultimate_sticky_wild.gd`
Expected: PASS — `STICKY WILD TEST PASSED`, exit 0.

- [ ] **Step 6: Run the prior resolver test to confirm no regression**

Run: `Godot_v4.6.3-stable_win64 --headless --path . --script res://tests/test_crushing_slow.gd`
Expected: PASS (the optional `wild_reel_indices` param defaults to empty — existing callers unaffected).

- [ ] **Step 7: Commit**

```bash
git add combat/combatant.gd combat/combat_resolver.gd tests/test_ultimate_sticky_wild.gd
git commit -m "feat(combat): Sticky-Wild Ultimate state + resolver wild override"
```

---

### Task D2: Orchestrator — Fire Ultimate button, WILD glow, consume per spin

**Files:**
- Modify: `combat/combat.gd`
- Modify: `combat/ui/reel_strip.gd` (a `set_wild(on)` highlight) and `combat/ui/combatant_panel.gd` (meter "ARMED" hint — optional)
- Test: `tests/test_combat_loop.gd` (pass `wild_reel_indices` + `consume_wild_spin` in the loop)

**Interfaces:**
- Consumes: `Combatant.fire_sticky_wild/wild_reel_indices/consume_wild_spin`, `BonusMeter.is_armed`.
- Produces: view/wiring only. "Fire Ultimate" Main-1 button (enabled only when armed); the wild reel glows; the spin passes `wild_reel_indices()` and calls `consume_wild_spin()` after it resolves.

- [ ] **Step 1: Update the integration loop to honor wilds** — in `tests/test_combat_loop.gd._on_turn_started`, replace the resolve + post-spin block:

Find:
```gdscript
	c.on_upkeep()
	c.begin_turn()
	var attacks: Array = _resolver.resolve_combat_phase(c.turn_reels, c.weapon.base_damage, defender.defense_type)
	for a in attacks:
		defender.take_damage(a.final_damage)
		c.bonus_meter.charge(a.face.result_tier)
		if a.rider_effect_id != &"":
			defender.attach_effect(EffectLibrary.make(a.rider_effect_id))
	c.on_end()
	_tm.advance_turn()
```
Replace with:
```gdscript
	c.on_upkeep()
	c.begin_turn()
	var attacks: Array = _resolver.resolve_combat_phase(c.turn_reels, c.weapon.base_damage, defender.defense_type, c.wild_reel_indices())
	c.consume_wild_spin()
	for a in attacks:
		defender.take_damage(a.final_damage)
		c.bonus_meter.charge(a.face.result_tier)
		if a.rider_effect_id != &"":
			defender.attach_effect(EffectLibrary.make(a.rider_effect_id))
	c.on_end()
	_tm.advance_turn()
```

- [ ] **Step 2: Run the integration test to verify it still passes**

Run: `Godot_v4.6.3-stable_win64 --headless --path . --script res://tests/test_combat_loop.gd`
Expected: PASS — `COMBAT LOOP TEST PASSED` (no meter ever fires here, but the wild-aware path must not break the loop).

- [ ] **Step 3: Add the Fire Ultimate button in `combat/combat.gd`** — in `_build_ui()`, after the splice button:

```gdscript
	_ultimate_button = Button.new()
	_ultimate_button.text = "Fire Ultimate (WILD)"
	_ultimate_button.position = Vector2(900, 328)
	_ultimate_button.custom_minimum_size = Vector2(210, 52)
	_ultimate_button.disabled = true
	add_child(_ultimate_button)
```
Declare `var _ultimate_button: Button`; connect in `_bind_signals()`:
```gdscript
	_ultimate_button.pressed.connect(_on_ultimate_pressed)
```

Add the handler:
```gdscript
## Fires the Sticky-Wild Ultimate on reel 0 for 2 spins (auto-target — DESIGN spec §6). Armed only.
## [ASSUMPTION] reel 0, 2 spins (CLAUDE.md §4).
func _on_ultimate_pressed() -> void:
	if not _awaiting_player_spin:
		return
	if _attacker.fire_sticky_wild(0, 2):
		_log("  %s fires the Ultimate — reel 1 is WILD for 2 spins!" % _attacker.display_name)
		(_panels[_attacker] as CombatantPanel).bind(_attacker)  # refresh meter to 0
		_highlight_wild_strips()
	_refresh_main1_actions()
```

Extend `_refresh_main1_actions()` to also gate the Ultimate button:
```gdscript
	_ultimate_button.disabled = not (is_player_main1 and _attacker.bonus_meter != null \
		and _attacker.bonus_meter.is_armed())
```

Add the strip highlight + use it when preparing strips:
```gdscript
## Glows the reel strips that are currently WILD (forced crit-success) for the active attacker.
func _highlight_wild_strips() -> void:
	var wild: Array[int] = _attacker.wild_reel_indices() if _attacker != null else []
	var strips: Array = _strips_box.get_children()
	for i: int in range(strips.size()):
		(strips[i] as ReelStrip).set_wild(i in wild)
```
Call `_highlight_wild_strips()` at the end of `_prepare_strips(...)` and after firing.

In `_do_spin`, pass the wild indices, and after the spin fully resolves consume one wild spin. Change the resolve call:
```gdscript
	var attacks: Array = _resolver.resolve_combat_phase(reels, _attacker.weapon.base_damage, _defender.defense_type, _attacker.wild_reel_indices())
```
In `_finish_spin`, before the player/enemy branching, add:
```gdscript
	_attacker.consume_wild_spin()
	_highlight_wild_strips()
```

- [ ] **Step 4: Add `set_wild` to `combat/ui/reel_strip.gd`** — a minimal highlight (exact styling cosmetic):

```gdscript
## Toggles the WILD highlight on this strip (Sticky-Wild Ultimate target). Cosmetic only.
func set_wild(on: bool) -> void:
	modulate = Color(1.6, 1.4, 0.4) if on else Color(1, 1, 1)
```

- [ ] **Step 5: Headless compile + full suite**

Run: `Godot_v4.6.3-stable_win64 --headless --path . --editor --quit` → exits 0.
Then run all suites (effect, resource_pool, crushing_slow, reel_splice, ultimate_sticky_wild, turn_manager, combatant, phase_manager, bonus_meter, combat_loop, action_reel) → all `… TEST PASSED`.

- [ ] **Step 6: Commit**

```bash
git add combat/combat.gd combat/ui/reel_strip.gd combat/ui/combatant_panel.gd tests/test_combat_loop.gd
git commit -m "feat(combat): Fire Ultimate button + WILD reel glow; consume wild per spin"
```

> **WAVE D REVIEW CHECKPOINT** — request code review. Human play-test: charge the meter to 10, fire in Main 1, watch reel 1 glow and land crit-success for two of the player's spins, then revert. Confirm firing did not spend Stamina.

---

## Final verification

- [ ] **Run the whole suite green:**
```bash
for t in effect resource_pool crushing_slow reel_splice ultimate_sticky_wild turn_manager combatant phase_manager bonus_meter action_reel combat_loop; do
  Godot_v4.6.3-stable_win64 --headless --path . --script res://tests/test_$t.gd || echo "FAILED: $t"
done
```
Expected: every line prints `… TEST PASSED`, no `FAILED:` lines.

- [ ] **Scene compiles clean:** `Godot_v4.6.3-stable_win64 --headless --path . --editor --quit` exits 0 with no errors.

- [ ] **Human play-test pass (CLAUDE.md §5 — the spin/feel is the human's call):** play `combat.tscn` and judge: does losing initiative to a Crushing crit sting and read clearly? Is spending Stamina to splice a reel a real decision? Does firing the Ultimate feel like pressing an advantage? Tune the `[ASSUMPTION]` numbers (spec §8) from there.

- [ ] **Update `ARCHITECTURE.md` and `CLAUDE.md §8` status** to record the four threads as built (mark the stubs in ARCHITECTURE §7 as implemented; move them out of "NOT yet built").

---

## Self-review notes (author)

- **Spec coverage:** Wave A → spec §3 (Tasks A1–A5); Wave B → spec §4 (B1–B2); Wave C → spec §2 + §5 (C1–C3); Wave D → spec §6 (D1–D2). Shared Main-1 flow (spec §2) = Task C1 + C3. Testing (spec §7) = the per-task TDD + final suite. `[ASSUMPTION]` table (spec §8) = values seeded in `EffectLibrary` (A1), `_make_combatant` (B2), splice handler (C3), ultimate handler (D2).
- **Type consistency:** `try_splice_reel(type, base_damage, cost, cap)`, `fire_sticky_wild(reel_index, spins)`, `wild_reel_indices() -> Array[int]`, `consume_wild_spin()`, `resolve_combat_phase(reels, base_damage, target_type, wild_reel_indices)`, `AttackResult.rider_effect_id` — used identically in every task and test that references them.
- **Out of scope (spec §9):** Focus/Mana, other `Effect.Kind`s, other Ultimate archetypes, reel-pick UI, PC Crushing, enemy Main-1 AI — none introduced.
