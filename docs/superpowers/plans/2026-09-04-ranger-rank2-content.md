# Ranger Rank-2 Content Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Author and wire the rank-2 (levels 5-8), passive-amplified (level 9), and Ultimate
rank-2 (level 10) content for all 6 Ranger ability rows — Hunter's Mark, Aimed Shot, Snare Trap,
Crippling Shot (+ a same-session Harvester retrofit), Steady Aim, Collateral Damage — using the
already-shipped `Combatant.ability_talent_row_rank()` / `Combatant.ability_magnitude_multiplier()`
infrastructure (introduced by the Harvester's own rank-2 pass), which no Ranger ability currently
consumes.

**Architecture:** Every mechanic in this plan is a call-site edit inside `combat/combat.gd`
(`_commit_main1()`, `_apply_attack()`, `_finish_spin()`, `_fire_marksmans_call()`) or
`combat/combatant.gd` (`passive_outgoing_multiplier()`), reading
`caster.ability_talent_row_rank(<row_id>)` to pick the rank-1 vs rank-2 behavior. Two brand-new
pieces of state: a `Combatant.aimed_shot_stacks: int` field (Aimed Shot's stacking counter) and a
new standalone `EffectLibrary` case `&"wounded"` (a healing-reduction debuff, shared between
Crippling Shot's own rank-2 wrinkle and a same-session retrofit of Harvester's already-shipped
Nightshade "Withering Touch" talent). No new systems — pure content-authoring + call-site wiring on
top of shipped infrastructure, plus one small refactor of existing Harvester code.

**Tech Stack:** Godot 4.6.3, GDScript, headless SceneTree test scripts (no test framework/GUT).

**Spec:** `docs/superpowers/specs/2026-09-04-ranger-rank2-content-design.md` (commit `c616ab6`,
player-approved).

## Global Constraints

- Engine: Godot 4.6+ (built/tested on 4.6.3-stable). GDScript only — never C#.
- Prefer static typing (typed vars, typed signatures) throughout.
- All combat damage/healing math rounds UP (`ceili()`/`ceil()`), never down or nearest.
- `ability_magnitude_multiplier()` applies at EVERY rank, including rank 1 — turn-count/duration/
  stack-count values are NOT stat-scaled (this pass introduces no new stat-scaled flat numbers of
  its own — see the spec's §1 note — every task below is either a duration/stun/splash-fraction
  value or a brand-new mechanic, not a fresh damage/heal constant).
- Every hand-authored number in this plan is `[ASSUMPTION]` per CLAUDE.md §4 — tune by playtest
  later; do not second-guess the exact numbers during implementation, they were agreed with the
  player during brainstorming.
- This codebase has an established, twice-precedented convention (see
  `tests/test_ability_talents_ranger.gd` and `tests/test_snare_trap.gd`'s own header comments):
  mechanics living inside `_apply_attack()`'s per-target attack-resolution loop or
  `_fire_marksmans_call()` are orchestrator-level and are NOT headlessly driven end-to-end (no
  existing test builds a live spin to reach them). Where this plan's own mechanic lives there
  (Snare Trap's stun, Crippling Shot's Wounded attach, the Deadeye/Marksman's Call bridge), the test
  proves the precondition/rank-gate and manually replicates the orchestrator's own exact formula —
  mirroring `tests/test_collateral.gd`'s established "replicate the formula directly" convention —
  full behavior is deferred to playtest, matching the spec's own §8 wording for those mechanics.
  Mechanics living inside `_commit_main1()` (Hunter's Mark's duration bump, Aimed Shot's stacking)
  DO have an established live-scene precedent (`tests/test_regrowth.gd`, `tests/test_grand_
  sacrifice.gd`, `tests/test_hollow_warden_full_sequence.gd`) — those get real end-to-end tests via
  a manually-wired `Combat` instance's `_commit_main1()`, not just preconditions.
- Run any single test file with:
  `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_<name>.gd`
  (the Godot executable lives one directory above this repo, at
  `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe`).
- Grep actual output for `SCRIPT ERROR`/`FAIL`, not just the process exit code — a thrown error
  mid-`_process()`/`_init()` can kill the rest of a frame's checks while the process still exits 0.

---

### Task 1: Hunter's Mark rank-2 (level 5) — duration bump + ally-crit meter-charge precondition

**Files:**
- Modify: `combat/combat.gd` — `_commit_main1()`'s `if _attacker.hunters_mark_pending:` block
  (currently ~line 2530); `_apply_attack()`'s per-target loop, right after the existing Marksman's
  Mark block (currently ~line 2919, right before the Warrior "Bleeding Wild" comment).
- Test: Create `tests/test_hunters_mark_rank2.gd`

**Interfaces:**
- Consumes: `Combatant.ability_talent_row_rank(row_id: StringName) -> int` (existing, row id
  `&"base_ability"` per the spec's §0 mapping), `Combatant.bonus_meter.add_flat(int) -> void`
  (existing, same call already used by Steady Aim's/Opportunist's own meter-charge blocks in this
  same file), `_allies_of(c: Combatant) -> Array[Combatant]` (existing, combat.gd).
- Produces: nothing new consumed by later tasks — self-contained.

- [ ] **Step 1: Write the failing test**

Create `tests/test_hunters_mark_rank2.gd`:

```gdscript
extends SceneTree

# Headless test: Ranger "Hunter's Mark" rank-2 (level 5+) duration bump (2026-09-04
# ranger-rank2-content spec §2.1) — verified end-to-end via a real Combat instance's
# _commit_main1(), mirroring tests/test_grand_sacrifice.gd's manual-wiring technique (fires for
# real without driving a full turn/spin). Hunter's Mark's own rank-1 baseline (duration 3), the
# hunters_mark_pending flag, and the crit-fail->hit reel-swap math are already covered by
# tests/test_hunters_mark.gd and are NOT re-tested here. The rank-2 ally-crit Bonus-Meter-charge
# mechanic (spec §2.2) needs live per-hit state across TWO combatants inside _apply_attack() —
# orchestrator-level, precondition-only below (this codebase's established convention for that kind
# of mechanic — see tests/test_ability_talents_ranger.gd's own header comment), full behavior
# deferred to playtest.
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_hunters_mark_rank2.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

## Wires a real Combat instance's minimal state so _commit_main1() runs for real (mirrors
## tests/test_grand_sacrifice.gd's _build_combat), without driving a full turn/spin.
func _build_combat(ranger: Combatant, target: Combatant) -> Combat:
	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame
	inst._turn_manager.combatants = [ranger, target]
	inst._panels[ranger] = CombatantPanel.new()
	inst._panels[target] = CombatantPanel.new()
	inst._attacker = ranger
	inst._defender = target
	inst._plan = MainPhasePlan.new(ranger, 0, 5, 2, null)
	return inst

func _free_combat(inst: Combat) -> void:
	inst.queue_free()
	await process_frame

## Case 1: level 4 (below base_ability's rank-2 threshold of 5) -> duration stays the rank-1 baseline (3).
func _run_rank1_regression() -> void:
	var ranger: Combatant = ClassLibrary.make(&"ranger").build_combatant(true)
	ranger.level = 4
	var target: Combatant = ClassLibrary.make(&"ranger").build_combatant(true)
	var inst: Combat = await _build_combat(ranger, target)

	inst._plan.toggle_ability()
	inst._commit_main1()
	var mark: Effect = target._find_effect(&"hunters_mark")
	_check(mark != null and mark.duration == 3, "level 4 (rank 1): Hunter's Mark duration stays 3 (got %s)" % [mark.duration if mark != null else "null"])

	await _free_combat(inst)

## Case 2: level 5+ (base_ability rank 2) -> duration bumps to 4.
func _run_rank2_duration() -> void:
	var ranger: Combatant = ClassLibrary.make(&"ranger").build_combatant(true)
	ranger.level = 5
	var target: Combatant = ClassLibrary.make(&"ranger").build_combatant(true)
	var inst: Combat = await _build_combat(ranger, target)

	inst._plan.toggle_ability()
	inst._commit_main1()
	var mark: Effect = target._find_effect(&"hunters_mark")
	_check(mark != null and mark.duration == 4, "level 5 (rank 2): Hunter's Mark duration bumps to 4 (got %s)" % [mark.duration if mark != null else "null"])
	_check(ranger.ability_talent_row_rank(&"base_ability") == 2, "sanity: level 5 reads rank 2 on the base_ability row (the same read _apply_attack() gates the ally-crit meter-charge mechanic on, spec §2.2)")

	await _free_combat(inst)

func _initialize() -> void:
	await _run_rank1_regression()
	await _run_rank2_duration()
	print(("HUNTERS MARK RANK-2 TEST PASSED" if _failures == 0 else "HUNTERS MARK RANK-2 TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_hunters_mark_rank2.gd`
Expected: FAIL on case 2 — the mark's duration stays 3 at every level (no rank-2 bump exists yet).

- [ ] **Step 3: Implement the rank-2 duration bump**

In `combat/combat.gd`, find the `if _attacker.hunters_mark_pending:` block inside `_commit_main1()`:

```gdscript
	if _attacker.hunters_mark_pending:
		var mark: Effect = EffectLibrary.make(&"hunters_mark")
		# Ranger Hunter's Mark row talent (2026-09-03 ranger-talent-tree spec §3): Rooting Mark also
```

Insert a new line right after `var mark: Effect = EffectLibrary.make(&"hunters_mark")` and before
the existing "Rooting Mark" comment:

```gdscript
	if _attacker.hunters_mark_pending:
		var mark: Effect = EffectLibrary.make(&"hunters_mark")
		# Rank 2 (2026-09-04 ranger-rank2-content spec §2.1): duration bumps 3 -> 4 turns. Applied
		# here (not in EffectLibrary.make()) since the effect has no access to the caster's level.
		if _attacker.ability_talent_row_rank(&"base_ability") >= 2:
			mark.duration = 4
		# Ranger Hunter's Mark row talent (2026-09-03 ranger-talent-tree spec §3): Rooting Mark also
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_hunters_mark_rank2.gd`
Expected: `HUNTERS MARK RANK-2 TEST PASSED`

- [ ] **Step 5: Implement the rank-2 ally-crit meter-charge mechanic**

In `combat/combat.gd`'s `_apply_attack()`, find the Marksman's Mark block (immediately preceded by
the Deadeye block):

```gdscript
			if _attacker.class_id == &"ranger" and _attacker.has_ability_talent(&"mark_marksman") and t.has_effect(&"hunters_mark") and attack.final_damage > 0:
				var marksman_bonus: int = ceili(attack.final_damage * 0.20)
				t.take_damage(marksman_bonus)
				_log("  🎯 %s's Marksman's Mark adds %d bonus damage." % [_attacker.display_name, marksman_bonus])
			# Warrior "Bleeding Wild" talent (Task 15): any hit landed while the Wild Ultimate is
```

Insert a new block between the Marksman's Mark block and the Warrior comment:

```gdscript
			if _attacker.class_id == &"ranger" and _attacker.has_ability_talent(&"mark_marksman") and t.has_effect(&"hunters_mark") and attack.final_damage > 0:
				var marksman_bonus: int = ceili(attack.final_damage * 0.20)
				t.take_damage(marksman_bonus)
				_log("  🎯 %s's Marksman's Mark adds %d bonus damage." % [_attacker.display_name, marksman_bonus])
			# Ranger Hunter's Mark rank-2 (2026-09-04 ranger-rank2-content spec §2.2): any ALLY's
			# CRIT_SUCCESS landed on a rank-2 Ranger's Marked target feeds that Ranger's own Bonus
			# Meter — a low-stakes resource trickle, uncapped, excluding the Ranger's own hits (those
			# already get plenty of separate bonuses above).
			if attack.face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS and attack.final_damage > 0 and t.has_effect(&"hunters_mark"):
				for ally: Combatant in _allies_of(_attacker):
					if ally != _attacker and ally.class_id == &"ranger" and ally.is_alive() and ally.ability_talent_row_rank(&"base_ability") >= 2 and ally.bonus_meter != null:
						ally.bonus_meter.add_flat(1)
						_log("  🏹 %s's Marked target is struck true — BM +1  (%d/%d)" % [ally.display_name, ally.bonus_meter.value, ally.bonus_meter.cap])
						if _panels.has(ally):
							(_panels[ally] as CombatantPanel).refresh_resources()
			# Warrior "Bleeding Wild" talent (Task 15): any hit landed while the Wild Ultimate is
```

- [ ] **Step 6: Re-run the test suite (no new assertions — this step has no live-scene test per the
Global Constraints; the rank gate is already covered by Step 1's `ability_talent_row_rank` sanity
check)**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_hunters_mark_rank2.gd`
Expected: `HUNTERS MARK RANK-2 TEST PASSED` (unchanged from Step 4 — this step adds no new
assertions, only production code)

- [ ] **Step 7: Commit**

```bash
git add combat/combat.gd tests/test_hunters_mark_rank2.gd
git commit -m "feat(ranger): Hunter's Mark rank-2 duration bump + ally-crit meter charge"
```

---

### Task 2: Aimed Shot rank-2 (level 6) — recast-while-Empowered stacking

**Files:**
- Modify: `combat/combatant.gd` — new field near `aimed_shot_pending` (currently ~line 325).
- Modify: `combat/combat.gd` — `_commit_main1()`'s `if _attacker.aimed_shot_pending:` block
  (currently ~line 2543).
- Test: Create `tests/test_aimed_shot_rank2.gd`

**Interfaces:**
- Consumes: `Combatant.ability_talent_row_rank(&"ability_l2")`, `Combatant.has_effect(&"empowered")`
  (existing).
- Produces: `Combatant.aimed_shot_stacks: int` — a new field, read/written only inside this same
  `_commit_main1()` block; no other task in this plan touches it.

- [ ] **Step 1: Write the failing test**

Create `tests/test_aimed_shot_rank2.gd`:

```gdscript
extends SceneTree

# Headless test: Ranger "Aimed Shot" rank-2 (level 6+) stacking mechanic (2026-09-04
# ranger-rank2-content spec §3.1) — recasting while Empowered is still active stacks the bonus
# magnitude (+0.10/stack, capped at 2 additional stacks = 3 total applications) instead of
# refreshing it. Verified via a real Combat instance's _commit_main1(), mirroring
# tests/test_grand_sacrifice.gd's manual-wiring technique. Aimed Shot's own rank-1 baseline
# (stage_aimed_shot spends Stamina + flags pending) is already covered by
# tests/test_aimed_shot.gd and is NOT re-tested here.
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_aimed_shot_rank2.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _build_combat(ranger: Combatant, target: Combatant) -> Combat:
	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame
	inst._turn_manager.combatants = [ranger, target]
	inst._panels[ranger] = CombatantPanel.new()
	inst._panels[target] = CombatantPanel.new()
	inst._attacker = ranger
	inst._defender = target
	return inst

func _free_combat(inst: Combat) -> void:
	inst.queue_free()
	await process_frame

## Directly stages Aimed Shot on [param ranger] (bypassing MainPhasePlan's cooldown/reel-cap
## gating, exactly like tests/test_aimed_shot.gd's own precedent) and commits it on [param inst],
## returning the resulting Empowered effect.
func _cast_aimed_shot(inst: Combat, ranger: Combatant) -> Effect:
	ranger.aimed_shot_pending = true
	inst._plan = MainPhasePlan.new(ranger, 0, 5, 2, null)
	inst._commit_main1()
	return ranger._find_effect(&"empowered")

## Case 1: rank < 2 (level 5, below ability_l2's rank-2 threshold of 6) — recasting while Empowered
## is still active just REFRESHES to the same base magnitude, never stacks.
func _run_rank1_regression() -> void:
	var ranger: Combatant = ClassLibrary.make(&"ranger").build_combatant(true)
	ranger.level = 5
	var target: Combatant = ClassLibrary.make(&"ranger").build_combatant(true)  # unmarked -> base 1.3
	var inst: Combat = await _build_combat(ranger, target)

	var e1: Effect = _cast_aimed_shot(inst, ranger)
	_check(e1 != null and is_equal_approx(e1.magnitude, 1.3), "level 5 cast 1: base magnitude 1.3 (got %s)" % [e1.magnitude if e1 != null else "null"])
	var e2: Effect = _cast_aimed_shot(inst, ranger)
	_check(e2 != null and is_equal_approx(e2.magnitude, 1.3), "level 5 (rank 1) recast while still Empowered: still 1.3, no stacking (got %s)" % [e2.magnitude if e2 != null else "null"])
	_check(ranger.aimed_shot_stacks == 0, "rank 1: aimed_shot_stacks never increments (got %d)" % ranger.aimed_shot_stacks)

	await _free_combat(inst)

## Case 2: rank 2 (level 6+), target UNMARKED -> base 1.3, stacks 1.3 -> 1.4 -> 1.5 -> capped 1.5.
func _run_rank2_stacking_unmarked() -> void:
	var ranger: Combatant = ClassLibrary.make(&"ranger").build_combatant(true)
	ranger.level = 6
	var target: Combatant = ClassLibrary.make(&"ranger").build_combatant(true)
	var inst: Combat = await _build_combat(ranger, target)

	var expected: Array[float] = [1.3, 1.4, 1.5, 1.5]
	for i: int in range(4):
		var e: Effect = _cast_aimed_shot(inst, ranger)
		_check(e != null and is_equal_approx(e.magnitude, expected[i]), "level 6 unmarked cast %d: magnitude %.1f (got %s)" % [i + 1, expected[i], e.magnitude if e != null else "null"])

	await _free_combat(inst)

## Case 3: rank 2, target MARKED -> base 1.6, stacks 1.6 -> 1.7 -> 1.8 -> capped 1.8.
func _run_rank2_stacking_marked() -> void:
	var ranger: Combatant = ClassLibrary.make(&"ranger").build_combatant(true)
	ranger.level = 6
	var target: Combatant = ClassLibrary.make(&"ranger").build_combatant(true)
	target.attach_effect(EffectLibrary.make(&"hunters_mark"))
	var inst: Combat = await _build_combat(ranger, target)

	var expected: Array[float] = [1.6, 1.7, 1.8, 1.8]
	for i: int in range(4):
		var e: Effect = _cast_aimed_shot(inst, ranger)
		_check(e != null and is_equal_approx(e.magnitude, expected[i]), "level 6 marked cast %d: magnitude %.1f (got %s)" % [i + 1, expected[i], e.magnitude if e != null else "null"])

	await _free_combat(inst)

## Case 4: a fresh cast AFTER Empowered has expired resets to the base magnitude, not continuing
## the old stack count (remove_effect() simulates natural expiry without waiting out real turns).
func _run_reset_after_expiry() -> void:
	var ranger: Combatant = ClassLibrary.make(&"ranger").build_combatant(true)
	ranger.level = 6
	var target: Combatant = ClassLibrary.make(&"ranger").build_combatant(true)
	var inst: Combat = await _build_combat(ranger, target)

	_cast_aimed_shot(inst, ranger)
	_cast_aimed_shot(inst, ranger)
	_check(ranger.aimed_shot_stacks == 1, "sanity: 2 casts in a row leave 1 stack")
	ranger.remove_effect(&"empowered")  # simulate the buff naturally expiring
	var e: Effect = _cast_aimed_shot(inst, ranger)
	_check(e != null and is_equal_approx(e.magnitude, 1.3), "fresh cast after expiry resets to the base magnitude (got %s)" % [e.magnitude if e != null else "null"])
	_check(ranger.aimed_shot_stacks == 0, "fresh cast after expiry resets aimed_shot_stacks to 0 (got %d)" % ranger.aimed_shot_stacks)

	await _free_combat(inst)

func _initialize() -> void:
	await _run_rank1_regression()
	await _run_rank2_stacking_unmarked()
	await _run_rank2_stacking_marked()
	await _run_reset_after_expiry()
	print(("AIMED SHOT RANK-2 TEST PASSED" if _failures == 0 else "AIMED SHOT RANK-2 TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_aimed_shot_rank2.gd`
Expected: FAIL — `Combatant.aimed_shot_stacks` doesn't exist yet (parse error) and no stacking logic exists.

- [ ] **Step 3: Add the new `aimed_shot_stacks` field**

In `combat/combatant.gd`, find:

```gdscript
## Ranger "Aimed Shot" (L5) pending flag: the orchestrator (which knows the defender) attaches
## Empowered with a bonus magnitude if the defender is already Marked (combat.gd, Task 23 wiring).
var aimed_shot_pending: bool = false

## Ranger "Weakening Aim" talent pending flag: set alongside aimed_shot_pending's own
```

Insert a new field between them:

```gdscript
## Ranger "Aimed Shot" (L5) pending flag: the orchestrator (which knows the defender) attaches
## Empowered with a bonus magnitude if the defender is already Marked (combat.gd, Task 23 wiring).
var aimed_shot_pending: bool = false

## Ranger "Aimed Shot" rank-2 (2026-09-04 ranger-rank2-content spec §3.1): live stack count for the
## "recast while still Empowered stacks instead of refreshing" mechanic. Read/written only in
## combat.gd's _commit_main1() aimed_shot_pending block — has_effect(&"empowered") at cast time IS
## the "is a stack still live" test, so an expired buff naturally resets this to 0 on the next cast
## (no separate expiry hook needed). Capped at 2 (base cast + 2 stacks = 3 total applications).
var aimed_shot_stacks: int = 0

## Ranger "Weakening Aim" talent pending flag: set alongside aimed_shot_pending's own
```

- [ ] **Step 4: Wire the stacking magnitude into `_commit_main1()`**

In `combat/combat.gd`, replace the `if _attacker.aimed_shot_pending:` block in full:

```gdscript
	if _attacker.aimed_shot_pending:
		var target_marked: bool = _defender.has_effect(&"hunters_mark")
		var e: Effect = EffectLibrary.make(&"empowered")
		var base_magnitude: float = 1.6 if target_marked else 1.3
		# Rank 2 (2026-09-04 ranger-rank2-content spec §3.1): recasting while the Ranger's OWN
		# Empowered buff is still active STACKS the magnitude (+0.10/stack) instead of just
		# refreshing it. has_effect(&"empowered") at cast time doubles as "is a stack still live" —
		# an expired buff naturally resets aimed_shot_stacks to 0 here. Capped at 2 additional
		# stacks (base cast + 2 = 3 total applications).
		if _attacker.ability_talent_row_rank(&"ability_l2") >= 2 and _attacker.has_effect(&"empowered"):
			_attacker.aimed_shot_stacks = mini(_attacker.aimed_shot_stacks + 1, 2)
		else:
			_attacker.aimed_shot_stacks = 0
		e.magnitude = base_magnitude + 0.10 * _attacker.aimed_shot_stacks
		# Ranger "Practiced Aim" talent (2026-09-03 ranger-talent-tree spec §4.3): the Empowered
		# buff lasts an extra turn when the target is already Marked.
		e.duration = 2 if (target_marked and _attacker.has_ability_talent(&"aim_practiced")) else 1
		_attacker.attach_effect(e)
		_attacker.aimed_shot_pending = false
		# Ranger "Weakening Aim" talent (was "Piercing Aim"): flags a bonus Weakened application,
		# consumed the first time a reel connects this spin (combat.gd's _apply_attack()).
		if _attacker.has_ability_talent(&"aim_weakening"):
			_attacker.aimed_shot_hit_pending = true
		# Ranger "Rooting Aim" talent (2026-09-03 ranger-talent-tree spec §4.1): mirrors Weakening
		# Aim's own pending-flag shape exactly, but applies Rooted instead of Weakened.
		if _attacker.has_ability_talent(&"aim_rooting"):
			_attacker.aimed_shot_root_pending = true
		_log("  ⊕ %s takes Aimed Shot — damage empowered %.0f%% this turn." % [_attacker.display_name, (e.magnitude - 1.0) * 100.0])
		(_panels[_attacker] as CombatantPanel).refresh_status()
```

- [ ] **Step 5: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_aimed_shot_rank2.gd`
Expected: `AIMED SHOT RANK-2 TEST PASSED`

- [ ] **Step 6: Commit**

```bash
git add combat/combatant.gd combat/combat.gd tests/test_aimed_shot_rank2.gd
git commit -m "feat(ranger): Aimed Shot rank-2 recast-while-Empowered stacking"
```

---

### Task 3: Snare Trap rank-2 (level 7) — primary-target stun

**Files:**
- Modify: `combat/combat.gd` — `_apply_attack()`'s "Ranger Snare Trap additions" block (currently
  ~line 3077).
- Test: Create `tests/test_snare_trap_rank2.gd`

**Interfaces:**
- Consumes: `Combatant.ability_talent_row_rank(&"ability_l3")`, `Combatant.force_stun_next_turn`
  (existing field, same mechanism Warden's Earthquake already uses).
- Produces: nothing new for later tasks.

- [ ] **Step 1: Write the failing test**

Create `tests/test_snare_trap_rank2.gd`:

```gdscript
extends SceneTree

# Headless test: Ranger "Snare Trap" rank-2 (level 7+) — the primary target ALSO gets
# force_stun_next_turn = true, stacked on top of the existing 2-turn Rooted (2026-09-04
# ranger-rank2-content spec §4.1). combat.gd's _apply_attack() applies this for real — orchestrator-
# level (needs a running Combat scene's live per-hit attack resolution), NOT headlessly tested here,
# consistent with this codebase's own established convention for Snare Trap's other rider/splash
# logic (see tests/test_ability_talents_ranger.gd / tests/test_snare_trap.gd's own header comments).
# This test proves the RANK GATE itself and manually replicates the exact conditional
# _apply_attack() runs, mirroring tests/test_collateral.gd's own "replicate the orchestrator's
# formula directly" convention.
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_snare_trap_rank2.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _mk_ranger() -> Combatant:
	return ClassLibrary.make(&"ranger").build_combatant(true)

## Manually replicates combat.gd's _apply_attack() rank-2 conditional exactly (spec §4.1): the
## PRIMARY target only gets force_stun_next_turn when ability_talent_row_rank(&"ability_l3") >= 2.
func _apply_rank2_stun(ranger: Combatant, primary: Combatant) -> void:
	if ranger.ability_talent_row_rank(&"ability_l3") >= 2:
		primary.force_stun_next_turn = true

func _init() -> void:
	# --- rank < 2 (level 6, below ability_l3's rank-2 threshold of 7): primary NOT stunned ---
	var c1: Combatant = _mk_ranger()
	c1.level = 6
	var primary1: Combatant = _mk_ranger()
	_check(not primary1.force_stun_next_turn, "sanity: primary starts unstunned")
	_apply_rank2_stun(c1, primary1)
	_check(not primary1.force_stun_next_turn, "level 6 (rank 1): primary target NOT stunned")

	# --- rank 2 (level 7+): primary IS stunned ---
	var c2: Combatant = _mk_ranger()
	c2.level = 7
	var primary2: Combatant = _mk_ranger()
	_apply_rank2_stun(c2, primary2)
	_check(primary2.force_stun_next_turn, "level 7 (rank 2): primary target force_stun_next_turn is set")

	# --- splash targets are unaffected: in combat.gd's real "for t in targets" loop the rank-2 stun
	# is only ever applied to the PRIMARY target — a splashed enemy from _splash_half_to_others() is
	# a separate array this rank-2 check never iterates. ---
	var splash_target: Combatant = _mk_ranger()
	_check(not splash_target.force_stun_next_turn, "splash targets are never touched by the rank-2 stun (only the primary-target loop is)")

	print(("SNARE TRAP RANK-2 TEST PASSED" if _failures == 0 else "SNARE TRAP RANK-2 TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_snare_trap_rank2.gd`
Expected: FAIL — the level-7 case fails since `_apply_rank2_stun` (a helper that mirrors production
code you haven't written yet) is a no-op at every rank until Step 3 is done. (`_apply_rank2_stun`
itself is test-only scaffolding; production code lives in combat.gd, see Step 3.)

- [ ] **Step 3: Implement the rank-2 stun in `_apply_attack()`**

In `combat/combat.gd`, find the "Ranger Snare Trap additions" block:

```gdscript
	if _attacker.class_id == &"ranger" and attack.rider_effect_id == &"rooted" and attack.final_damage > 0:
		for t: Combatant in targets:
			# Hunter "Marking Snare" talent (§5.2): auto-applies Hunter's Mark to the PRIMARY
			# target only (does not apply to splash targets below).
			if _attacker.has_ability_talent(&"snare_marking"):
```

Insert a new rank-2 check as the first statement inside the `for t: Combatant in targets:` loop,
before the existing Marking Snare check:

```gdscript
	if _attacker.class_id == &"ranger" and attack.rider_effect_id == &"rooted" and attack.final_damage > 0:
		for t: Combatant in targets:
			# Rank 2 (2026-09-04 ranger-rank2-content spec §4.1): the PRIMARY target also gets
			# stunned next turn (force_stun_next_turn, the same mechanism Warden's Earthquake uses),
			# stacked on top of the existing 2-turn Rooted. Splash targets (the loop below) are
			# unaffected.
			if _attacker.ability_talent_row_rank(&"ability_l3") >= 2:
				t.force_stun_next_turn = true
				_log("  🪤 Snare Trap (rank 2) → %s is STUNNED next turn (initiative unchanged)." % t.display_name)
			# Hunter "Marking Snare" talent (§5.2): auto-applies Hunter's Mark to the PRIMARY
			# target only (does not apply to splash targets below).
			if _attacker.has_ability_talent(&"snare_marking"):
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_snare_trap_rank2.gd`
Expected: `SNARE TRAP RANK-2 TEST PASSED` (this test never calls the production code directly per
the Global Constraints' orchestrator-level convention — Step 3's edit is proven correct by manual
code review against the test's own replicated conditional, and by the Final Verification's full
regression pass).

- [ ] **Step 5: Commit**

```bash
git add combat/combat.gd tests/test_snare_trap_rank2.gd
git commit -m "feat(ranger): Snare Trap rank-2 primary-target stun"
```

---

### Task 4: Crippling Shot rank-2 (level 8) — standalone Wounded effect + Withering Touch retrofit

**Files:**
- Modify: `combat/effect_library.gd` — add the new `&"wounded"` case.
- Modify: `combat/combat.gd`:
  - `_apply_attack()`'s generic rider-attach loop (currently ~line 3051-3060).
  - `_run_misfortune_stage()` (currently ~line 1021-1057) and its doc comment/retired constant
    (currently ~line 1010-1019).
- Modify: `tests/test_nightshade_talents.gd` — update the Withering Touch regression assertion for
  the retrofit (this file already exists and currently asserts the OLD `curse.heal_multiplier`
  behavior directly — it WILL fail after the retrofit unless updated here).
- Test: Create `tests/test_crippling_shot_rank2.gd`

**Interfaces:**
- Consumes: `Combatant.ability_talent_row_rank(&"ability_l4")`, `EffectLibrary.make(id) -> Effect`
  (extended with `&"wounded"`), `Combatant.attach_effect()`/`has_effect()`/`_find_effect()`
  (existing).
- Produces: `EffectLibrary.make(&"wounded")` — a new effect id other classes' future rank-2 passes
  MAY reuse later (explicitly out of scope to design further now, per spec).

- [ ] **Step 1: Write the failing test**

Create `tests/test_crippling_shot_rank2.gd`:

```gdscript
extends SceneTree

# Headless test: Ranger "Crippling Shot" rank-2 (level 8+) — a standalone "Wounded" heal-reduction
# debuff attached alongside Weakened (2026-09-04 ranger-rank2-content spec §5.1). The actual
# rider-attach application lives in combat.gd's _apply_attack() generic rider-attach loop —
# orchestrator-level (needs a running Combat scene's live per-hit attack resolution), NOT headlessly
# tested here, consistent with this codebase's own established convention for Crippling Shot's other
# rider logic (see tests/test_ability_talents_ranger.gd's own header comment). This test proves the
# Wounded effect's own shape (EffectLibrary.make) and the rank gate/duration-matching precondition
# by manually replicating _apply_attack()'s exact conditional, mirroring
# tests/test_collateral.gd's own "replicate the orchestrator's formula directly" convention.
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_crippling_shot_rank2.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _mk_ranger() -> Combatant:
	return ClassLibrary.make(&"ranger").build_combatant(true)

## Manually replicates combat.gd's _apply_attack() generic rider-attach loop's rank-2 conditional
## exactly (spec §5.1): a fresh Wounded effect, duration matching [param weakened_duration] (the
## duration Weakened's own rider got this cast, after apply_rider_talent_adjustments), attached only
## when Crippling Shot's rider (&"weakened") lands on a rank-2 Ranger's hit.
func _apply_rank2_wounded(ranger: Combatant, target: Combatant, weakened_duration: int) -> void:
	if ranger.ability_talent_row_rank(&"ability_l4") >= 2:
		var wounded: Effect = EffectLibrary.make(&"wounded")
		wounded.duration = weakened_duration
		target.attach_effect(wounded)

func _init() -> void:
	# --- the Wounded effect's own shape ---
	var e: Effect = EffectLibrary.make(&"wounded")
	_check(e != null, "EffectLibrary makes wounded")
	_check(e.id == &"wounded", "id is wounded")
	_check(e.kind == Effect.Kind.MULTIPLIER_EDIT, "kind is MULTIPLIER_EDIT (neutral 1.0, the real payload is heal_multiplier)")
	_check(is_equal_approx(e.magnitude, 1.0), "magnitude is neutral (1.0) — does not itself change incoming damage math")
	_check(e.affects_incoming, "affects_incoming is true (matches Hunter's Mark-style 'kind chosen loosely' precedent)")
	_check(is_equal_approx(e.heal_multiplier, 0.5), "heal_multiplier is 0.5 (the real payload, read directly by Combatant.heal())")
	_check(not e.beneficial, "is a debuff")

	# --- rank < 2 (level 7, below ability_l4's rank-2 threshold of 8): Wounded is NOT attached ---
	var c1: Combatant = _mk_ranger()
	c1.level = 7
	var target1: Combatant = _mk_ranger()
	target1.attach_effect(EffectLibrary.make(&"weakened"))
	_apply_rank2_wounded(c1, target1, target1._find_effect(&"weakened").duration)
	_check(not target1.has_effect(&"wounded"), "level 7 (rank 1): target only carries weakened, no wounded")
	_check(target1.has_effect(&"weakened"), "sanity: weakened is still attached")

	# --- rank 2 (level 8+), baseline 2-turn Weakened: Wounded attaches with a MATCHING 2-turn duration ---
	var c2: Combatant = _mk_ranger()
	c2.level = 8
	var target2: Combatant = _mk_ranger()
	target2.attach_effect(EffectLibrary.make(&"weakened"))
	var weakened2: Effect = target2._find_effect(&"weakened")
	_check(weakened2.duration == 2, "sanity: baseline Weakened duration is 2")
	_apply_rank2_wounded(c2, target2, weakened2.duration)
	_check(target2.has_effect(&"weakened") and target2.has_effect(&"wounded"), "level 8 (rank 2): target carries BOTH weakened and wounded")
	_check(target2._find_effect(&"wounded").duration == 2, "level 8: wounded duration matches the baseline 2-turn Weakened (got %d)" % target2._find_effect(&"wounded").duration)

	# --- rank 2, Lasting Crippling picked -> Weakened's own duration is 3, Wounded matches that ---
	var c3: Combatant = _mk_ranger()
	c3.level = 8
	_check(c3.pick_ability_talent(&"ability_l4", &"crippling_lasting"), "picks crippling_lasting")
	var target3: Combatant = _mk_ranger()
	var weakened3: Effect = EffectLibrary.make(&"weakened")
	c3.apply_rider_talent_adjustments(&"weakened", weakened3, target3)
	target3.attach_effect(weakened3)
	_check(target3._find_effect(&"weakened").duration == 3, "sanity: crippling_lasting bumps Weakened's own duration to 3")
	_apply_rank2_wounded(c3, target3, target3._find_effect(&"weakened").duration)
	_check(target3._find_effect(&"wounded").duration == 3, "level 8 + Lasting Crippling: wounded duration matches the extended 3-turn Weakened (got %d)" % target3._find_effect(&"wounded").duration)

	print(("CRIPPLING SHOT RANK-2 TEST PASSED" if _failures == 0 else "CRIPPLING SHOT RANK-2 TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_crippling_shot_rank2.gd`
Expected: FAIL — `EffectLibrary.make(&"wounded")` returns `null` (no such case yet).

- [ ] **Step 3: Add the `&"wounded"` EffectLibrary case**

In `combat/effect_library.gd`, find the `&"weakened"` case:

```gdscript
		&"weakened":
			var e: Effect = Effect.new()
			e.id = &"weakened"; e.kind = Effect.Kind.MULTIPLIER_EDIT; e.magnitude = 0.75
			e.affects_incoming = false; e.duration = 2; e.beneficial = false
			return e
```

Insert a new case right after it:

```gdscript
		&"weakened":
			var e: Effect = Effect.new()
			e.id = &"weakened"; e.kind = Effect.Kind.MULTIPLIER_EDIT; e.magnitude = 0.75
			e.affects_incoming = false; e.duration = 2; e.beneficial = false
			return e
		&"wounded":
			# Standalone healing-reduction debuff (2026-09-04 ranger-rank2-content spec §5.1) —
			# Ranger Crippling Shot's rank-2 wrinkle, and the retrofitted target of Harvester's
			# Nightshade "Withering Touch" talent (previously a heal_multiplier set directly on the
			# Cursed DoT — see combat.gd's _run_misfortune_stage()). MULTIPLIER_EDIT/magnitude 1.0 is
			# a neutral, "chosen loosely" kind/magnitude pair (same convention as Hunter's Mark/
			# Taunt's own inert kinds) — the real payload is heal_multiplier, read directly by
			# Combatant.heal() regardless of kind. Deliberately a STANDALONE, separately
			# has_effect()-checkable debuff (not a field bundled onto Weakened or Cursed) so a future
			# class's "damage scales with debuff count" mechanic can count it. No duration set here —
			# every caller sets it explicitly (no single correct default to bake in).
			var e: Effect = Effect.new()
			e.id = &"wounded"; e.kind = Effect.Kind.MULTIPLIER_EDIT; e.magnitude = 1.0
			e.affects_incoming = true; e.heal_multiplier = 0.5; e.beneficial = false
			return e
```

- [ ] **Step 4: Run test to verify it now partially passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_crippling_shot_rank2.gd`
Expected: the "Wounded effect's own shape" checks now PASS; the rank-gated attach checks still
PASS too, since `_apply_rank2_wounded()` is test-local scaffolding that already reads the real
`ability_talent_row_rank()` — this step doesn't touch combat.gd yet, only effect_library.gd. Full
`CRIPPLING SHOT RANK-2 TEST PASSED`.

- [ ] **Step 5: Wire the real rider-attach in `_apply_attack()`**

In `combat/combat.gd`, find the generic rider-attach loop:

```gdscript
	if attack.rider_effect_id != &"":
		for t: Combatant in targets:
			var rider: Effect = EffectLibrary.make(attack.rider_effect_id)
			if rider != null:
				# A DoT (the Warrior's Rend → BLEED) bakes the caster's weapon base damage at apply time,
				# so its per-turn damage scales off the attacker's weapon (spec §4B). Off the type chart.
				if rider.kind == Effect.Kind.DAMAGE_OVER_TIME and _attacker.weapon != null:
					rider.dot_base_damage = _attacker.weapon_effective_base_damage()
				_attacker.apply_rider_talent_adjustments(attack.rider_effect_id, rider, t)
				t.attach_effect(rider)
				if attack.source_reel != null and attack.source_reel.talent_extra_rider_stack:
```

Insert a new block right after `t.attach_effect(rider)`, before the existing
`talent_extra_rider_stack` check:

```gdscript
	if attack.rider_effect_id != &"":
		for t: Combatant in targets:
			var rider: Effect = EffectLibrary.make(attack.rider_effect_id)
			if rider != null:
				# A DoT (the Warrior's Rend → BLEED) bakes the caster's weapon base damage at apply time,
				# so its per-turn damage scales off the attacker's weapon (spec §4B). Off the type chart.
				if rider.kind == Effect.Kind.DAMAGE_OVER_TIME and _attacker.weapon != null:
					rider.dot_base_damage = _attacker.weapon_effective_base_damage()
				_attacker.apply_rider_talent_adjustments(attack.rider_effect_id, rider, t)
				t.attach_effect(rider)
				# Ranger Crippling Shot rank-2 (2026-09-04 ranger-rank2-content spec §5.1): a
				# standalone Wounded debuff, attached ALONGSIDE Weakened (not instead of it).
				# Duration mirrors whatever duration Weakened's own rider just got THIS cast
				# (rider.duration already reflects the Lasting Crippling adjustment from
				# apply_rider_talent_adjustments above), read directly rather than round-tripped
				# through a second effect instance.
				if _attacker.class_id == &"ranger" and attack.rider_effect_id == &"weakened" and _attacker.ability_talent_row_rank(&"ability_l4") >= 2 and attack.final_damage > 0:
					var wounded: Effect = EffectLibrary.make(&"wounded")
					wounded.duration = rider.duration
					t.attach_effect(wounded)
					_log("  🤕 %s is WOUNDED — healing reduced (%d turns)." % [t.display_name, wounded.duration])
					if _panels.has(t):
						(_panels[t] as CombatantPanel).refresh_status()
				if attack.source_reel != null and attack.source_reel.talent_extra_rider_stack:
```

- [ ] **Step 6: Retrofit Withering Touch to attach Wounded instead of setting `heal_multiplier` directly**

In `combat/combat.gd`, find the doc comment + retired constant right before
`_run_misfortune_stage()`:

```gdscript
## Misfortune Minion's 3-stage effect (2026-08-16 spec §2): a Weakened debuff on every enemy at
## stage 1, adds Sundered at stage 2, applies Cursed (flat-scaled, not weapon-scaled, since the
## minion itself is weaponless — mirrors the existing Warden-Acolyte "curse the party" pattern's
## flat dot_base_damage convention) at stage 3. Rank 2 (ability_talent_row_rank(&"ability_l3") >= 2,
## 2026-09-02 harvester-rank2-content spec §2.3) bumps Cursed's dot_base_damage 12.0 -> 18.0 (scaled
## by ability_magnitude_multiplier()) and makes stage 3's Weakened/Sundered reapply unconditional —
## unless the Mutual Exhaustion talent is picked and the target already carries both, in which case
## they merge into Exhausted (+ Slow) instead.
## [ASSUMPTION] Withering Touch's heal-reduction on the target while Cursed — tune by playtest.
const MISFORTUNE_WITHERING_TOUCH_HEAL_MULT: float = 0.5

func _run_misfortune_stage(minion: Combatant, stage: int, caster: Combatant = null) -> void:
```

Replace it (removing the now-dead constant, updating the doc comment):

```gdscript
## Misfortune Minion's 3-stage effect (2026-08-16 spec §2): a Weakened debuff on every enemy at
## stage 1, adds Sundered at stage 2, applies Cursed (flat-scaled, not weapon-scaled, since the
## minion itself is weaponless — mirrors the existing Warden-Acolyte "curse the party" pattern's
## flat dot_base_damage convention) at stage 3. Rank 2 (ability_talent_row_rank(&"ability_l3") >= 2,
## 2026-09-02 harvester-rank2-content spec §2.3) bumps Cursed's dot_base_damage 12.0 -> 18.0 (scaled
## by ability_magnitude_multiplier()) and makes stage 3's Weakened/Sundered reapply unconditional —
## unless the Mutual Exhaustion talent is picked and the target already carries both, in which case
## they merge into Exhausted (+ Slow) instead. Withering Touch's heal-reduction (2026-09-04
## ranger-rank2-content spec §5.2 retrofit) now attaches the standalone &"wounded" effect instead of
## setting heal_multiplier directly on Cursed — see the withering_touch branch below.

func _run_misfortune_stage(minion: Combatant, stage: int, caster: Combatant = null) -> void:
```

Then, inside `_run_misfortune_stage()`, find:

```gdscript
			var curse: Effect = EffectLibrary.make(&"cursed")
			curse.dot_base_damage = (18.0 if rank >= 2 else 12.0) * stat_mult
			if withering_touch:
				curse.heal_multiplier = MISFORTUNE_WITHERING_TOUCH_HEAL_MULT
			enemy.attach_effect(curse)
```

Replace it:

```gdscript
			var curse: Effect = EffectLibrary.make(&"cursed")
			curse.dot_base_damage = (18.0 if rank >= 2 else 12.0) * stat_mult
			enemy.attach_effect(curse)
			# Retrofit (2026-09-04 ranger-rank2-content spec §5.2): Withering Touch now attaches the
			# same standalone Wounded effect Ranger's Crippling Shot rank-2 introduced, instead of
			# setting heal_multiplier directly on the Cursed DoT. Behavior-preserving — same 50% heal
			# reduction, duration matched to this cast's own Cursed duration (a flat 3, unmodified by
			# any Nightshade talent) — its only observable difference is has_effect(&"wounded") now
			# also returns true on a Withering-Touch-cursed target.
			if withering_touch:
				var wounded: Effect = EffectLibrary.make(&"wounded")
				wounded.duration = curse.duration
				enemy.attach_effect(wounded)
```

- [ ] **Step 7: Update the existing Withering Touch regression test**

`tests/test_nightshade_talents.gd`'s `_test_withering_touch_reduces_healing()` currently asserts
the OLD behavior directly on `curse.heal_multiplier` — this WILL fail after Step 6 unless updated.
Find:

```gdscript
	inst._run_minion_stage(minion, 3, pc)
	var curse: Effect = enemy._find_effect(&"cursed")
	_check(curse != null and curse.heal_multiplier < 1.0, "misfortune_withering_touch: Cursed carries a heal_multiplier below 1.0 (got %.2f)" % (curse.heal_multiplier if curse != null else -1.0))
	var before: int = enemy.hp
	enemy.heal(20)
	_check(enemy.hp < before + 20, "misfortune_withering_touch: heal() actually respects heal_multiplier (healed to %d, expected less than %d)" % [enemy.hp, before + 20])
```

Replace it:

```gdscript
	inst._run_minion_stage(minion, 3, pc)
	var curse: Effect = enemy._find_effect(&"cursed")
	_check(curse != null, "misfortune_withering_touch: Cursed is attached")
	# Retrofit (2026-09-04 ranger-rank2-content spec §5.2): Withering Touch now attaches the
	# standalone &"wounded" effect instead of setting heal_multiplier directly on Cursed — Cursed
	# itself stays at the neutral default (1.0).
	_check(curse != null and is_equal_approx(curse.heal_multiplier, 1.0), "misfortune_withering_touch: Cursed no longer carries its own heal_multiplier (got %.2f)" % (curse.heal_multiplier if curse != null else -1.0))
	var wounded: Effect = enemy._find_effect(&"wounded")
	_check(wounded != null and is_equal_approx(wounded.heal_multiplier, 0.5), "misfortune_withering_touch: a standalone Wounded effect (heal_multiplier 0.5) is attached (got %.2f)" % (wounded.heal_multiplier if wounded != null else -1.0))
	_check(wounded != null and curse != null and wounded.duration == curse.duration, "misfortune_withering_touch: Wounded's duration matches Cursed's own duration (got %d vs %d)" % [wounded.duration if wounded != null else -1, curse.duration if curse != null else -1])
	var before: int = enemy.hp
	enemy.heal(20)
	_check(enemy.hp < before + 20, "misfortune_withering_touch: heal() actually respects Wounded's heal_multiplier (healed to %d, expected less than %d) — behavior-preserving regression for Harvester" % [enemy.hp, before + 20])
```

- [ ] **Step 8: Run both tests to verify everything passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_crippling_shot_rank2.gd`
Expected: `CRIPPLING SHOT RANK-2 TEST PASSED`

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_nightshade_talents.gd`
Expected: `NIGHTSHADE TALENTS TEST PASSED` (grep the actual output — this file's own print banner
text may differ slightly; check for `FAIL`/`SCRIPT ERROR` per the Global Constraints regardless of
the exact banner)

- [ ] **Step 9: Commit**

```bash
git add combat/effect_library.gd combat/combat.gd tests/test_crippling_shot_rank2.gd tests/test_nightshade_talents.gd
git commit -m "feat(ranger): Crippling Shot rank-2 Wounded debuff + Withering Touch retrofit"
```

---

### Task 5: Steady Aim amplifies at level 9 — +20% baseline + Deadeye/Marksman's Call bridge

**Files:**
- Modify: `combat/combatant.gd` — `passive_outgoing_multiplier()`'s `&"steady_aim"` arm (currently
  ~line 1240-1250).
- Modify: `combat/combat.gd` — `_fire_marksmans_call()` (currently ~line 3297-3310).
- Test: Create `tests/test_steady_aim_rank2.gd`

**Interfaces:**
- Consumes: `Combatant.ability_talent_row_rank(&"passive")`, `Combatant.has_ability_talent(&"steady_deadeye")`.
- Produces: nothing new for later tasks.

- [ ] **Step 1: Write the failing test**

Create `tests/test_steady_aim_rank2.gd`:

```gdscript
extends SceneTree

# Headless test: Ranger "Steady Aim" amplified (level 9+) passive (2026-09-04 ranger-rank2-content
# spec §6) — the +10%-vs-Marked baseline bumps to +20%, and (with Deadeye picked) Marksman's Call's
# independently-resolved reel gains Deadeye's own +15%-on-crit-vs-Marked bonus, which it previously
# never received (a gap the talent-tree rework's final review flagged). The Deadeye/Marksman's Call
# bridge itself lives in combat.gd's _fire_marksmans_call() — orchestrator-level (needs a running
# Combat scene's _resolver), NOT headlessly tested here, consistent with this codebase's own
# established convention for Marksman's Call's other math (see
# tests/test_ability_talents_ranger.gd's own header comment: "Marksman's Call's own resolver math is
# covered in tests/test_marksmans_call.gd"). This test proves the rank gate itself.
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_steady_aim_rank2.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _mk_ranger() -> Combatant:
	var c: Combatant = ClassLibrary.make(&"ranger").build_combatant(true)
	c.passive_ability_id = &"steady_aim"
	return c

func _init() -> void:
	# --- rank < 2 (level 8, below passive's amplified threshold of 9): stays +10% ---
	var c1: Combatant = _mk_ranger()
	c1.level = 8
	var marked1: Combatant = _mk_ranger()
	marked1.attach_effect(EffectLibrary.make(&"hunters_mark"))
	_check(is_equal_approx(c1.passive_outgoing_multiplier(marked1), 1.10), "level 8 (rank 1): Steady Aim stays +10%% vs a Marked defender (got %.3f)" % c1.passive_outgoing_multiplier(marked1))

	# --- amplified (level 9+): +20% ---
	var c2: Combatant = _mk_ranger()
	c2.level = 9
	var marked2: Combatant = _mk_ranger()
	marked2.attach_effect(EffectLibrary.make(&"hunters_mark"))
	_check(is_equal_approx(c2.passive_outgoing_multiplier(marked2), 1.20), "level 9 (amplified): Steady Aim is +20%% vs a Marked defender (got %.3f)" % c2.passive_outgoing_multiplier(marked2))

	# --- the trigger-widening talents (Controlled Aim / Wider Aim) are unaffected by amplification —
	# they still only decide WHETHER the bonus fires, now at the bigger +20% magnitude. ---
	var c3: Combatant = _mk_ranger()
	c3.level = 9
	_check(c3.pick_ability_talent(&"passive", &"steady_wider"), "picks steady_wider")
	var weakened3: Combatant = _mk_ranger()
	weakened3.attach_effect(EffectLibrary.make(&"weakened"))
	_check(is_equal_approx(c3.passive_outgoing_multiplier(weakened3), 1.20), "level 9 + steady_wider vs a merely-Weakened defender: +20%% (got %.3f)" % c3.passive_outgoing_multiplier(weakened3))

	# --- amplified-rank + Deadeye bridge precondition (spec §6.2): the exact gate combat.gd's
	# _fire_marksmans_call() reads — full application deferred to playtest. ---
	var c4: Combatant = _mk_ranger()
	c4.level = 9
	_check(c4.pick_ability_talent(&"passive", &"steady_deadeye"), "picks steady_deadeye")
	_check(c4.ability_talent_row_rank(&"passive") >= 2 and c4.has_ability_talent(&"steady_deadeye"), "sanity: the Marksman's Call/Deadeye bridge's own gate reads true at level 9 with Deadeye picked")
	var c5: Combatant = _mk_ranger()
	c5.level = 8
	_check(c5.pick_ability_talent(&"passive", &"steady_deadeye"), "picks steady_deadeye")
	_check(not (c5.ability_talent_row_rank(&"passive") >= 2 and c5.has_ability_talent(&"steady_deadeye")), "sanity: the bridge's gate reads false below level 9 even with Deadeye picked")

	print(("STEADY AIM RANK-2 TEST PASSED" if _failures == 0 else "STEADY AIM RANK-2 TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_steady_aim_rank2.gd`
Expected: FAIL on the level-9 case — the multiplier stays 1.10 at every level.

- [ ] **Step 3: Implement the amplified baseline bump**

In `combat/combatant.gd`, find the `&"steady_aim"` arm of `passive_outgoing_multiplier()`:

```gdscript
		&"steady_aim":
			if defender == null:
				return 1.0
			var triggered: bool = defender.has_effect(&"hunters_mark")
			if has_ability_talent(&"steady_wider"):
				triggered = triggered or defender.has_effect(&"weakened")
			if has_ability_talent(&"steady_controlled"):
				triggered = triggered or defender.has_effect(&"rooted") or defender.has_effect(&"slow") or defender.stunned_last_turn
			if not triggered:
				return 1.0
			return 1.10
```

Replace the final `return 1.10` line:

```gdscript
		&"steady_aim":
			if defender == null:
				return 1.0
			var triggered: bool = defender.has_effect(&"hunters_mark")
			if has_ability_talent(&"steady_wider"):
				triggered = triggered or defender.has_effect(&"weakened")
			if has_ability_talent(&"steady_controlled"):
				triggered = triggered or defender.has_effect(&"rooted") or defender.has_effect(&"slow") or defender.stunned_last_turn
			if not triggered:
				return 1.0
			# Amplified (level 9+, 2026-09-04 ranger-rank2-content spec §6.1): +10% -> +20%. The
			# trigger-widening talents above are unaffected — they only decide WHETHER this fires.
			return 1.20 if ability_talent_row_rank(&"passive") >= 2 else 1.10
```

- [ ] **Step 4: Run test to verify progress**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_steady_aim_rank2.gd`
Expected: still FAIL — the Deadeye-bridge sanity checks (they only read `ability_talent_row_rank`/
`has_ability_talent`, no combat.gd change needed for those specific assertions) should already pass,
but re-run to confirm the multiplier assertions now pass too before moving on.

- [ ] **Step 5: Implement the Deadeye/Marksman's Call bridge**

In `combat/combat.gd`, find `_fire_marksmans_call()`:

```gdscript
func _fire_marksmans_call(ranger: Combatant, target: Combatant) -> void:
	var reel: ActionReel = ActionReel.make_ability_attack(ranger.weapon_type())
	var dmg_mult: float = ranger.outgoing_damage_multiplier(target) * target.incoming_damage_multiplier()
	var attack: CombatResolver.AttackResult = _resolver.resolve_single_reel(reel, ranger.weapon_effective_base_damage(), target.defense_type, ranger.might_damage_bonus_per_reel(1), dmg_mult)
	if attack.final_damage > 0:
		target.take_damage(attack.final_damage)
		var mult: float = reel.damage_type.multiplier_against(target.defense_type) if reel.damage_type != null else 1.0
		_log("  🏹 %s's MARKSMAN'S CALL adds a bow shot on %s for %d damage.  %s" % [ranger.display_name, target.display_name, attack.final_damage, TypeVisuals.effectiveness_tag(mult)])
	if ranger.bonus_meter != null and attack.charges_meter:
```

Insert a new block right after the `_log(...)` line, still inside the `if attack.final_damage > 0:` body:

```gdscript
func _fire_marksmans_call(ranger: Combatant, target: Combatant) -> void:
	var reel: ActionReel = ActionReel.make_ability_attack(ranger.weapon_type())
	var dmg_mult: float = ranger.outgoing_damage_multiplier(target) * target.incoming_damage_multiplier()
	var attack: CombatResolver.AttackResult = _resolver.resolve_single_reel(reel, ranger.weapon_effective_base_damage(), target.defense_type, ranger.might_damage_bonus_per_reel(1), dmg_mult)
	if attack.final_damage > 0:
		target.take_damage(attack.final_damage)
		var mult: float = reel.damage_type.multiplier_against(target.defense_type) if reel.damage_type != null else 1.0
		_log("  🏹 %s's MARKSMAN'S CALL adds a bow shot on %s for %d damage.  %s" % [ranger.display_name, target.display_name, attack.final_damage, TypeVisuals.effectiveness_tag(mult)])
		# Steady Aim amplified (2026-09-04 ranger-rank2-content spec §6.2): bridges Deadeye's own
		# +15%-on-crit-vs-Marked bonus (see _apply_attack()'s own Deadeye block) onto Marksman's
		# Call's independently-resolved reel — a gap the talent-tree rework's final review flagged
		# as a playtest note. Below level 9, or without Deadeye picked, the gap remains exactly as
		# documented — intentionally gated to the amplified rank, not made permanently on.
		if ranger.ability_talent_row_rank(&"passive") >= 2 and ranger.has_ability_talent(&"steady_deadeye") and attack.face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS and attack.final_damage > 0:
			var deadeye_bonus: int = ceili(attack.final_damage * 0.15)
			target.take_damage(deadeye_bonus)
			_log("  🎯 %s's Deadeye adds %d bonus damage to Marksman's Call." % [ranger.display_name, deadeye_bonus])
	if ranger.bonus_meter != null and attack.charges_meter:
```

- [ ] **Step 6: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_steady_aim_rank2.gd`
Expected: `STEADY AIM RANK-2 TEST PASSED`

- [ ] **Step 7: Commit**

```bash
git add combat/combatant.gd combat/combat.gd tests/test_steady_aim_rank2.gd
git commit -m "feat(ranger): Steady Aim amplified +20% baseline + Deadeye/Marksman's Call bridge"
```

---

### Task 6: Collateral Damage rank-2 (level 10) — 2/3 splash fraction + Weakened-on-splash

**Files:**
- Modify: `combat/combat.gd` — `_finish_spin()`'s Collateral Damage block (currently ~line 3360-3371).
- Test: Create `tests/test_collateral_rank2.gd`

**Interfaces:**
- Consumes: `Combatant.ability_talent_row_rank(&"ultimate")`, `_splash_half_to_others()` (existing,
  already takes an optional `fraction` param per the Warden Earthquake precedent).
- Produces: nothing new for later tasks.

- [ ] **Step 1: Write the failing test**

Create `tests/test_collateral_rank2.gd`:

```gdscript
extends SceneTree

# Headless test: Ranger "Collateral Damage" Ultimate rank-2 (level 10) — splash fraction 0.5 -> 2/3,
# and every splashed enemy also gets Weakened, unconditional (2026-09-04 ranger-rank2-content spec
# §7). The real application lives in combat.gd's _finish_spin(), which calls the private
# _splash_half_to_others() — no live scene reference here, mirroring tests/test_collateral.gd's own
# "replicate the orchestrator's formula directly" convention (that file covers the rank-1 splash
# math and fire_collateral() itself; not re-tested here).
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_collateral_rank2.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _mk_ranger() -> Combatant:
	return ClassLibrary.make(&"ranger").build_combatant(true)

func _init() -> void:
	# --- rank < 2 (level 9, below ultimate's rank-2 threshold of 10): splash fraction stays 0.5 ---
	var c1: Combatant = _mk_ranger()
	c1.level = 9
	_check(c1.ability_talent_row_rank(&"ultimate") == 1, "sanity: level 9 reads rank 1 on the ultimate row")
	_check(ceili(21 * 0.5) == 11, "rank 1: splash fraction stays 1/2 -> ceil(21 * 0.5) = 11")

	# --- rank 2 (level 10): splash fraction becomes 2/3 ---
	var c2: Combatant = _mk_ranger()
	c2.level = 10
	_check(c2.ability_talent_row_rank(&"ultimate") == 2, "sanity: level 10 reads rank 2 on the ultimate row")
	_check(ceili(21 * (2.0 / 3.0)) == 14, "rank 2: splash fraction is 2/3 -> ceil(21 * 2/3) = 14")

	# --- rank 2: every splashed enemy also gets Weakened, independent of Marking Collateral (manual
	# simulation of _finish_spin()'s loop, mirroring test_ability_talents_ranger.gd's own Marking
	# Collateral simulation) ---
	var other_a: Combatant = _mk_ranger()
	var other_b: Combatant = _mk_ranger()
	var splashed: Array[Combatant] = [other_a, other_b]
	_check(not other_a.has_effect(&"weakened") and not other_b.has_effect(&"weakened"), "sanity: neither splashed enemy starts Weakened")
	var collateral_rank2: bool = c2.ability_talent_row_rank(&"ultimate") >= 2
	if collateral_rank2:
		for other: Combatant in splashed:
			other.attach_effect(EffectLibrary.make(&"weakened"))
	_check(other_a.has_effect(&"weakened") and other_b.has_effect(&"weakened"), "rank 2: every splashed enemy is also Weakened")

	# --- rank 2 + Marking Collateral picked: both Weakened AND Hunter's Mark land on the same
	# splashed enemies (independent effects, not mutually exclusive) ---
	var c3: Combatant = _mk_ranger()
	c3.level = 10
	_check(c3.pick_ability_talent(&"ultimate", &"collateral_marking"), "picks collateral_marking")
	var other_c: Combatant = _mk_ranger()
	other_c.attach_effect(EffectLibrary.make(&"weakened"))  # the rank-2 wrinkle, simulated above
	if c3.has_ability_talent(&"collateral_marking"):
		other_c.attach_effect(EffectLibrary.make(&"hunters_mark"))
	_check(other_c.has_effect(&"weakened") and other_c.has_effect(&"hunters_mark"), "rank 2 + Marking Collateral: a splashed enemy carries BOTH Weakened and Hunter's Mark")

	print(("COLLATERAL DAMAGE RANK-2 TEST PASSED" if _failures == 0 else "COLLATERAL DAMAGE RANK-2 TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_collateral_rank2.gd`
Expected: this test file has no production-code dependency other than `ability_talent_row_rank()`
(already shipped) and `EffectLibrary.make(&"weakened")` (already shipped) — it should already PASS
as written, since it's a pure formula/manual-simulation test. Run it anyway to confirm before
touching combat.gd, matching TDD discipline; if it passes immediately, proceed straight to Step 3
(the production wiring still needs to exist for the real game to behave correctly, even though this
particular test can't observe combat.gd directly per the Global Constraints).

- [ ] **Step 3: Implement the rank-2 splash fraction + Weakened-on-splash in `_finish_spin()`**

In `combat/combat.gd`, find the Collateral Damage block:

```gdscript
	if _attacker.is_collateral_active():
		var splashed: Array[Combatant] = _splash_half_to_others(_attacker, _collateral_total, "Piercing", 0.5)
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

Replace it:

```gdscript
	if _attacker.is_collateral_active():
		# Rank 2 (2026-09-04 ranger-rank2-content spec §7.1): splash fraction 0.5 -> 2/3, a
		# deliberate callback to exactly what the now-retired collateral_deeper talent used to do,
		# now automatic baseline growth instead of a pick.
		var collateral_rank2: bool = _attacker.ability_talent_row_rank(&"ultimate") >= 2
		var splash_fraction: float = (2.0 / 3.0) if collateral_rank2 else 0.5
		var splashed: Array[Combatant] = _splash_half_to_others(_attacker, _collateral_total, "Piercing", splash_fraction)
		# Rank 2 (spec §7.2): every splashed enemy also gets a stack of Weakened, unconditional and
		# independent of the Marking Collateral talent below (both can apply to the same enemies).
		if collateral_rank2:
			for other: Combatant in splashed:
				if other.is_alive():
					other.attach_effect(EffectLibrary.make(&"weakened"))
					_log("  🎯 Collateral Damage (rank 2): %s is also WEAKENED." % other.display_name)
					if _panels.has(other):
						(_panels[other] as CombatantPanel).refresh_status()
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

- [ ] **Step 4: Run test to verify it still passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_collateral_rank2.gd`
Expected: `COLLATERAL DAMAGE RANK-2 TEST PASSED`

- [ ] **Step 5: Commit**

```bash
git add combat/combat.gd tests/test_collateral_rank2.gd
git commit -m "feat(ranger): Collateral Damage rank-2 2/3 splash + Weakened-on-splash"
```

---

## Final Verification

After all 6 tasks are committed, run the full existing Ranger/effect test suite to confirm nothing
regressed (each of these already existed before this plan and must stay green):

```bash
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_hunters_mark.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_aimed_shot.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_snare_trap.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_crippling_shot.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_collateral.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_marksmans_call.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ranger_class.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_ranger.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_nightshade_talents.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_misfortune_minion.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_misfortune_minion_rank2.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_attach_effect_merge_strength.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talent_row_rank.gd
```

Plus every new test this plan adds:

```bash
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_hunters_mark_rank2.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_aimed_shot_rank2.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_snare_trap_rank2.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_crippling_shot_rank2.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_steady_aim_rank2.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_collateral_rank2.gd
```

Grep the output of each for `SCRIPT ERROR`/`FAIL` (not just the exit code) per CLAUDE.md's
silent-script-error-exits-zero gotcha. This is a real, un-playtested balance/mechanic change (rank-2
content lands the first time any Ranger reaches level 5+) — flag to the player that a human
playtest of a leveled-up Ranger (mirroring the still-open Harvester/Warrior rank-2 playtest items)
is the natural next step after merge. The Withering Touch retrofit (Task 4) additionally touches
ALREADY-SHIPPED Harvester code — confirm `test_nightshade_talents.gd` specifically stays green, not
just the new Ranger files, since that's the one regression risk outside Ranger's own kit.
