# Summoner Bonus Meter Economy Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the Summoner class three new, small Bonus Meter charge sources — a reduced flat charge on every minion-summon cast, a bonus on a minion's natural stage-3 expiry, and a bonus when Grand Sacrifice consumes a minion — so a Summoner who plays their kit as designed (casting minion abilities instead of attacking) can actually reach cap during a fight, not just at floor-collapse time after it.

**Architecture:** All three charge sources are flat `BonusMeter.add_flat()` calls layered onto the existing minion-summon/minion-lifecycle/Grand-Sacrifice code paths in `combat/combat.gd` and `combat/combatant.gd` — no changes to `BonusMeter` itself, no new signals, no changes to `ActionReel.make_summon_reel()` (it stays `charges_meter = false`; the new charge is a separate, smaller, flat award rather than routing through the normal per-tier `charge_weights` path, which would otherwise credit a full attack-sized 2–3 charge per summon). A new `Combatant.minion_caster` back-reference (mirroring the existing `active_minion` forward-reference) lets the minion's own stage-3 expiry (which runs on the minion's turn, not the caster's) credit the right combatant's meter.

**Tech Stack:** Godot 4.6.3, GDScript, headless `SceneTree` test scripts (existing project convention — see `tests/test_grand_sacrifice.gd`).

**Spec:** This conversation (2026-08-18, following on from `docs/superpowers/../memory` note `summoner-playtest-round2-new-bugs-2026-08-18` item A). No separate spec doc — the design was worked out directly with the player: reduced-weight charge on summon casts (Option 2) + a charge bonus on natural minion expiry and on Grand Sacrifice consumption (Option 3), combined.

## Global Constraints

- GDScript only, static typing throughout (project convention, CLAUDE.md §2).
- All new numeric constants are **placeholders** — flag them `[ASSUMPTION]` in their doc comments, matching every other Bonus Meter/Grand Sacrifice constant in this codebase (CLAUDE.md §4: "Do not 'balance' them — they get tuned by playtest after the spin is fun").
- `BonusMeter`/Grand Sacrifice logic must stay class-agnostic — no `if class_id == "summoner"` branching. The new charge sources apply generically to "a minion's caster" and "an Ultimate that consumes a minion," which today only the Summoner has, but the code should read as generic mechanics, not a Summoner special-case, in case a future class reuses minions.
- Do not touch the `resolve_post_combat()` floor/cap formula itself — this plan is scoped to increasing in-combat charge, not to changing carryover math (that's the explicitly-deferred, not-yet-decided piece of the original design question).
- Every new behavior needs a passing test before commit (TDD per CLAUDE.md §5.3).

---

## File Structure

- **Modify `combat/combatant.gd`**:
  - New field `minion_caster: Combatant = null`, documented next to `active_minion`/`minion_type` — set only on a minion, points back to the combatant who summoned it.
  - New constant `GRAND_SACRIFICE_CONSUME_BM_BONUS`.
  - `fire_grand_sacrifice()` awards that bonus to `self.bonus_meter` right after `consume()`.
- **Modify `combat/combat.gd`**:
  - New constants `SUMMON_CAST_BM_CHARGE` and `MINION_NATURAL_EXPIRY_BM_BONUS` (near the existing `MINION_BASE_STAGE_DAMAGE`/`GRAND_SACRIFICE_*` constants).
  - The Ember Minion summon-payoff block (`_finish_spin`'s summon branch, ~combat.gd:3119-3132): set `minion.minion_caster = _attacker` and award `_attacker.bonus_meter.add_flat(SUMMON_CAST_BM_CHARGE)`.
  - `_run_minion_stage()`'s stage-3 expiry branch (~combat.gd:830-834): award `minion.minion_caster.bonus_meter.add_flat(MINION_NATURAL_EXPIRY_BM_BONUS)` before/around the existing `force_expire()` call.
- **Modify `tests/test_grand_sacrifice.gd`**: 3 existing assertions (`pc.bonus_meter.value == 0` after firing) become `== Combatant.GRAND_SACRIFICE_CONSUME_BM_BONUS`, since firing no longer leaves the meter at a literal 0.
- **Create `tests/test_summoner_meter_economy.gd`**: new dedicated test file covering all three charge sources together (they're one cohesive design change from one conversation — keeping them in one file matches "files/tests that change together live together").

---

### Task 1: `minion_caster` back-reference + reduced-weight charge on summon cast

**Files:**
- Modify: `combat/combatant.gd` (add field, near `active_minion` at combatant.gd:373-376)
- Modify: `combat/combat.gd` (constant + summon-payoff block, combat.gd:3119-3132)
- Test: `tests/test_summoner_meter_economy.gd` (new file)

**Interfaces:**
- Produces: `Combatant.minion_caster: Combatant` (null unless this combatant is a minion with a known summoner) — consumed by Task 2.
- Produces: `Combat.SUMMON_CAST_BM_CHARGE: int` constant, readable by tests as `Combat.SUMMON_CAST_BM_CHARGE`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_summoner_meter_economy.gd`:

```gdscript
extends SceneTree

# Headless test for the Summoner Bonus Meter economy fix (2026-08-18, following the 2026-08-18
# playtest note on the Summoner's meter rarely reaching cap): three new flat charge sources layered
# on top of the existing minion-summon/minion-lifecycle/Grand-Sacrifice code paths in combat.gd/
# combatant.gd — a reduced charge on every summon-ability cast (make_summon_reel() itself stays
# charges_meter = false; this is a separate, smaller, flat award), a bonus when a minion completes
# its stage-3 expiry naturally, and a bonus when Grand Sacrifice consumes a minion. None of these
# touch BonusMeter.resolve_post_combat()'s floor/cap formula itself.
#
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_summoner_meter_economy.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _make_summoner() -> Combatant:
	var c: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	c.bonus_meter.cap = 15
	c.bonus_meter.value = 0
	c.begin_turn()
	return c

## Wires a real Combat instance's minimal state so _finish_spin()'s summon-payoff branch and
## _run_minion_stage() run for real. Mirrors tests/test_grand_sacrifice.gd's _build_combat().
func _build_combat(pc: Combatant, enemies: Array[Combatant]) -> Combat:
	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame
	inst._pcs = [pc]
	inst._enemies = enemies
	inst._dummies = []
	var all: Array[Combatant] = [pc]
	all.append_array(enemies)
	inst._turn_manager.combatants = all
	for c: Combatant in all:
		inst._panels[c] = CombatantPanel.new()
	inst._attacker = pc
	inst._defender = enemies[0] if enemies.size() > 0 else null
	inst._plan = MainPhasePlan.new(pc, pc.ability_cost, 5, 2)
	return inst

func _free_combat(inst: Combat) -> void:
	inst.queue_free()
	await process_frame

# --- Summoning a minion sets minion_caster AND awards the reduced flat charge ---
func _run_summon_cast_charges_meter_and_sets_caster() -> void:
	var pc: Combatant = _make_summoner()
	var enemy: Combatant = Combatant.new(); enemy.base_max_hp = 300; enemy.apply_stats(); enemy.start_combat()
	var inst: Combat = await _build_combat(pc, [enemy])

	pc.apply_summon_minion()  # base ability: stages the Ember Minion summon_reel
	inst._summon_tier = ReelFace.ResultTier.SUCCESS  # force a baseline (non-crit) summon result
	inst._finish_spin_summon_payoff_for_test()

	_check(pc.active_minion != null and pc.active_minion.is_alive(), "sanity: a minion was summoned")
	_check(pc.active_minion.minion_caster == pc, "the summoned minion's minion_caster points back to its summoner")
	_check(pc.bonus_meter.value == Combat.SUMMON_CAST_BM_CHARGE, "summoning charges the caster's meter by the reduced flat amount (got %d, want %d)" % [pc.bonus_meter.value, Combat.SUMMON_CAST_BM_CHARGE])

	await _free_combat(inst)

func _initialize() -> void:
	await _run_summon_cast_charges_meter_and_sets_caster()

	print(("SUMMONER METER ECONOMY TEST PASSED" if _failures == 0 else "SUMMONER METER ECONOMY TEST FAILED: %d" % _failures))
	quit(_failures)
```

Note: this first test step calls a not-yet-existing test seam `inst._finish_spin_summon_payoff_for_test()`. Real minion summoning normally happens inside `_finish_spin()`'s huge post-spin dispatch after a real spin settles (too much machinery to drive from a unit test, per `test_grand_sacrifice.gd`'s own precedent of calling the narrow `_commit_main1()`/orchestrator entry points directly instead of a full spin). Rather than invent a fake seam, use the REAL summon-payoff code path by extracting it into its own named method in Step 3 below (`_apply_minion_summon_payoff(_summon_tier: int) -> void`), which the test calls directly. Delete the `_finish_spin_summon_payoff_for_test()` line above and replace it with `inst._apply_minion_summon_payoff(ReelFace.ResultTier.SUCCESS)` before running the test.

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_summoner_meter_economy.gd` (from the `bunnies/` project directory; the executable lives one directory above, per CLAUDE.md's gotchas list).
Expected: FAIL/parse error — `_apply_minion_summon_payoff` does not exist yet, and `Combat.SUMMON_CAST_BM_CHARGE` is undefined.

- [ ] **Step 3: Extract the summon-payoff block and add the charge + caster back-reference**

In `combat/combat.gd`, find the existing inline block at combat.gd:3119-3132 (inside `_finish_spin()`, guarded by `if _attacker.summon_reel != null and _summon_tier != -1:`). Extract its body into a new method, and call that method from the original site:

```gdscript
	if _attacker.summon_reel != null and _summon_tier != -1:
		_apply_minion_summon_payoff(_attacker, _summon_tier)
```

New method (place it directly below `_finish_spin()`, or wherever `_run_minion_stage()` and its neighbors already live — keep summon/minion-lifecycle code grouped):

```gdscript
## Extracted from _finish_spin()'s summon-payoff block (2026-08-18 Bonus Meter economy fix) so a
## test can drive the real summon path without a full spin. Builds the new minion (SUCCESS =
## baseline, CRIT_SUCCESS = the tankier variant), expires any existing minion first, and awards the
## caster a reduced flat Bonus Meter charge — make_summon_reel() itself stays charges_meter = false
## (a summon reel has no fail tiers, so routing it through the normal per-tier charge_weights path
## would credit a full attack-sized 2-3 charge; this flat award is deliberately smaller, per the
## 2026-08-18 "Option 2" design direction).
func _apply_minion_summon_payoff(caster: Combatant, summon_tier: int) -> void:
	if caster.active_minion != null and caster.active_minion.is_alive():
		caster.active_minion.take_damage(caster.active_minion.hp)
		_turn_manager.remove_dead_combatant(caster.active_minion)
	var tanky: bool = summon_tier == ReelFace.ResultTier.CRIT_SUCCESS
	var minion: Combatant = MinionLibrary.make(tanky, caster.pending_minion_type)
	minion.minion_caster = caster
	caster.active_minion = minion
	_turn_manager.roll_initiative_for(minion)
	_turn_manager.combatants.append(minion)  # NOT insert_acting_this_round() — see original comment
	_build_minion_panel(minion)
	var tier_text: String = "CRITICAL SUCCESS — a stronger" if tanky else "SUCCESS — a"
	_log("  🔥 %s summons %s — %s minion appears! (%d HP)" % [caster.display_name, minion.display_name, tier_text, minion.max_hp])
	_run_minion_stage(minion, 1, caster)
	minion.minion_stage = 1  # stage 1 has now run; the own-turn handler does `+= 1` to reach stage 2 next
	if caster.bonus_meter != null:
		caster.bonus_meter.add_flat(SUMMON_CAST_BM_CHARGE)
		if caster.bonus_meter.is_visible:
			_log("    BM +%d  (%d/%d)  — minion summoned" % [SUMMON_CAST_BM_CHARGE, caster.bonus_meter.value, caster.bonus_meter.cap])
```

Add the new constant near `MINION_BASE_STAGE_DAMAGE` (combat.gd, just above `_run_minion_stage()`):

```gdscript
## [ASSUMPTION] Flat Bonus Meter charge awarded when a minion-summon ability cast lands (2026-08-18
## Summoner meter economy fix). Deliberately smaller than a normal hit's tier-based charge (2 for
## SUCCESS / 3 for CRIT_SUCCESS via charge_weights) since a summon reel can never fail — tune by
## playtest.
const SUMMON_CAST_BM_CHARGE: int = 1
```

Add `minion_caster` to `combat/combatant.gd`, directly below the existing `active_minion` doc block (combatant.gd:373-376):

```gdscript
## Set on a minion (is_minion == true) to the combatant who summoned it, or null (2026-08-18
## Summoner meter economy fix). The forward reference (active_minion, above) lets the CASTER find
## its minion; this back-reference lets code running on the MINION'S OWN turn (its stage-3 natural
## expiry, which the caster isn't present for — see combat.gd's _run_minion_stage()) find the right
## combatant to credit a Bonus Meter bonus to. Meaningless/unused on a non-minion combatant.
var minion_caster: Combatant = null
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_summoner_meter_economy.gd`
Expected: `SUMMONER METER ECONOMY TEST PASSED`

- [ ] **Step 5: Commit**

```bash
git add combat/combat.gd combat/combatant.gd tests/test_summoner_meter_economy.gd
git commit -m "feat(summoner): reduced Bonus Meter charge on minion-summon cast + minion_caster back-reference"
```

---

### Task 2: Bonus Meter award on a minion's natural stage-3 expiry

**Files:**
- Modify: `combat/combat.gd` (`_run_minion_stage()`, combat.gd:822-834, and the new constant)
- Test: `tests/test_summoner_meter_economy.gd`

**Interfaces:**
- Consumes: `Combatant.minion_caster` (Task 1).
- Produces: `Combat.MINION_NATURAL_EXPIRY_BM_BONUS: int` constant.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_summoner_meter_economy.gd` (before the `_initialize()` function):

```gdscript
# --- A minion's natural stage-3 expiry credits its caster's meter, on top of the summon charge ---
func _run_natural_expiry_credits_caster() -> void:
	var pc: Combatant = _make_summoner()
	var enemy: Combatant = Combatant.new(); enemy.base_max_hp = 300; enemy.apply_stats(); enemy.start_combat()
	var inst: Combat = await _build_combat(pc, [enemy])

	pc.apply_summon_minion()
	inst._apply_minion_summon_payoff(pc, ReelFace.ResultTier.SUCCESS)
	var minion: Combatant = pc.active_minion
	var value_after_summon: int = pc.bonus_meter.value
	_check(value_after_summon == Combat.SUMMON_CAST_BM_CHARGE, "sanity: summon charge already applied")

	inst._run_minion_stage(minion, 2)  # minion's own 1st real turn
	_check(minion.is_alive(), "sanity: minion survives stage 2")
	inst._run_minion_stage(minion, 3)  # minion's own 2nd real turn — completes and expires

	_check(not minion.is_alive(), "the minion is dead after its stage-3 expiry")
	var expected: int = Combat.SUMMON_CAST_BM_CHARGE + Combat.MINION_NATURAL_EXPIRY_BM_BONUS
	_check(pc.bonus_meter.value == expected, "natural stage-3 expiry adds the expiry bonus on top of the summon charge (got %d, want %d)" % [pc.bonus_meter.value, expected])

	await _free_combat(inst)
```

Wire it into `_initialize()`:

```gdscript
func _initialize() -> void:
	await _run_summon_cast_charges_meter_and_sets_caster()
	await _run_natural_expiry_credits_caster()

	print(("SUMMONER METER ECONOMY TEST PASSED" if _failures == 0 else "SUMMONER METER ECONOMY TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_summoner_meter_economy.gd`
Expected: FAIL — `pc.bonus_meter.value` stays at `Combat.SUMMON_CAST_BM_CHARGE` (no expiry bonus applied yet), or a parse error on the undefined `Combat.MINION_NATURAL_EXPIRY_BM_BONUS` constant.

- [ ] **Step 3: Implement the expiry bonus**

Add the constant next to `SUMMON_CAST_BM_CHARGE` in `combat/combat.gd`:

```gdscript
## [ASSUMPTION] Flat Bonus Meter bonus awarded to a minion's caster when that minion completes its
## stage-3 action and expires NATURALLY (2026-08-18 Summoner meter economy fix) — rewards playing a
## minion out to its full 3-stage lifecycle rather than overwriting it early with a new summon
## (which does NOT award this; see _apply_minion_summon_payoff's take_damage() early-expire branch).
## Not awarded when a minion is sacrificed by Grand Sacrifice — see
## Combatant.GRAND_SACRIFICE_CONSUME_BM_BONUS for that separate, Ultimate-specific bonus. Tune by
## playtest.
const MINION_NATURAL_EXPIRY_BM_BONUS: int = 2
```

Update `_run_minion_stage()` (combat.gd:822-834) — the existing stage-3 branch:

```gdscript
func _run_minion_stage(minion: Combatant, stage: int, caster: Combatant = null) -> void:
	match minion.minion_type:
		&"dew":
			_run_dew_stage(minion, stage)
		&"misfortune":
			_run_misfortune_stage(minion, stage)
		&"hasty":
			_run_hasty_stage(minion, stage, caster)
		_:
			_run_ember_stage(minion, stage)
	if stage >= 3 and minion.is_alive():
		_log("  %s completes its final stage and fades away." % minion.display_name)
		minion.force_expire()
		_turn_manager.remove_dead_combatant(minion)
		if minion.minion_caster != null and minion.minion_caster.is_alive() and minion.minion_caster.bonus_meter != null:
			minion.minion_caster.bonus_meter.add_flat(MINION_NATURAL_EXPIRY_BM_BONUS)
			if minion.minion_caster.bonus_meter.is_visible:
				_log("    BM +%d  (%d/%d)  — %s's minion completed its lifecycle" % [MINION_NATURAL_EXPIRY_BM_BONUS, minion.minion_caster.bonus_meter.value, minion.minion_caster.bonus_meter.cap, minion.minion_caster.display_name])
```

(Only the `if stage >= 3 and minion.is_alive():` block's body changes — everything above it is unchanged.)

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_summoner_meter_economy.gd`
Expected: `SUMMONER METER ECONOMY TEST PASSED`

- [ ] **Step 5: Run the full minion regression set to check for interaction bugs**

Run each of these and confirm no new failures (they exercise `_run_minion_stage()`'s stage-3 branch, now with the added caster-credit logic):

```bash
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dew_minion.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_hasty_minion.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_misfortune_minion.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_minion_lifecycle.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_stale_active_minion_reset.gd
```

Expected: all still print their own "... TEST PASSED" line. These tests summon minions directly via `MinionLibrary.make()` rather than through `_apply_minion_summon_payoff()`, so most will have `minion_caster == null` — the new `if minion.minion_caster != null` guard makes that a safe no-op, not a crash. If any of them independently exercise the real summon-payoff path (check for calls to `_finish_spin()` or the old inline block) and assert an exact `bonus_meter.value`, update that assertion the same way Task 3 updates `test_grand_sacrifice.gd`.

- [ ] **Step 6: Commit**

```bash
git add combat/combat.gd tests/test_summoner_meter_economy.gd
git commit -m "feat(summoner): Bonus Meter bonus on a minion's natural stage-3 expiry"
```

---

### Task 3: Bonus Meter award on Grand Sacrifice consumption

**Files:**
- Modify: `combat/combatant.gd` (`fire_grand_sacrifice()`, combatant.gd:2298-2302, and the new constant)
- Modify: `tests/test_grand_sacrifice.gd` (3 stale assertions)
- Test: `tests/test_summoner_meter_economy.gd`

**Interfaces:**
- Produces: `Combatant.GRAND_SACRIFICE_CONSUME_BM_BONUS: int` constant.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_summoner_meter_economy.gd` (before `_initialize()`):

```gdscript
# --- Firing Grand Sacrifice credits a small Bonus Meter bonus, on top of consume()'s reset to 0 ---
func _run_grand_sacrifice_consumption_credits_bonus() -> void:
	var pc: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	pc.ultimate_id = &"grand_sacrifice"
	pc.bonus_meter.cap = 15
	pc.bonus_meter.value = 15
	pc.begin_turn()
	pc.active_minion = MinionLibrary.make(false, &"ember")
	var minion: Combatant = pc.active_minion

	pc.fire_grand_sacrifice()

	_check(not minion.is_alive(), "sanity: the sacrificed minion is dead")
	_check(pc.bonus_meter.value == Combatant.GRAND_SACRIFICE_CONSUME_BM_BONUS, "firing Grand Sacrifice leaves the meter at the small consumption bonus, not a literal 0 (got %d, want %d)" % [pc.bonus_meter.value, Combatant.GRAND_SACRIFICE_CONSUME_BM_BONUS])

func _initialize() -> void:
	await _run_summon_cast_charges_meter_and_sets_caster()
	await _run_natural_expiry_credits_caster()
	_run_grand_sacrifice_consumption_credits_bonus()

	print(("SUMMONER METER ECONOMY TEST PASSED" if _failures == 0 else "SUMMONER METER ECONOMY TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_summoner_meter_economy.gd`
Expected: FAIL — `pc.bonus_meter.value` is `0`, not `Combatant.GRAND_SACRIFICE_CONSUME_BM_BONUS` (undefined constant causes a parse error until Step 3).

- [ ] **Step 3: Implement the consumption bonus**

In `combat/combatant.gd`, add the constant near the other Summoner-section constants, directly above `fire_grand_sacrifice()` (combatant.gd:~2286-2298):

```gdscript
## [ASSUMPTION] Flat Bonus Meter bonus credited immediately after Grand Sacrifice consumes the full
## meter (2026-08-18 Summoner meter economy fix) — a small head-start on the NEXT Ultimate cycle,
## separate from Combat.MINION_NATURAL_EXPIRY_BM_BONUS (that one rewards a minion completing its
## own lifecycle; this one rewards spending the Ultimate at all). Tune by playtest.
const GRAND_SACRIFICE_CONSUME_BM_BONUS: int = 2
```

Update `fire_grand_sacrifice()`:

```gdscript
func fire_grand_sacrifice() -> void:
	bonus_meter.consume()
	bonus_meter.add_flat(GRAND_SACRIFICE_CONSUME_BM_BONUS)
	grand_sacrifice_variant_pending = active_minion.minion_type
	active_minion.take_damage(active_minion.hp)
	active_minion = null
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_summoner_meter_economy.gd`
Expected: `SUMMONER METER ECONOMY TEST PASSED`

- [ ] **Step 5: Update the 3 now-stale assertions in `tests/test_grand_sacrifice.gd`**

Firing Grand Sacrifice no longer leaves `bonus_meter.value` at a literal `0` — it's `Combatant.GRAND_SACRIFICE_CONSUME_BM_BONUS`. Update:

- Line 91: `_check(pc.bonus_meter.value == 0, "firing Grand Sacrifice consumes the full meter")` → `_check(pc.bonus_meter.value == Combatant.GRAND_SACRIFICE_CONSUME_BM_BONUS, "firing Grand Sacrifice consumes the full meter, then credits the small consumption bonus")`
- Line 108: `_check(pc.bonus_meter.value == 0, "ember: meter consumed")` → `_check(pc.bonus_meter.value == Combatant.GRAND_SACRIFICE_CONSUME_BM_BONUS, "ember: meter consumed, then credited the consumption bonus")`
- Line 131: `_check(pc.bonus_meter.value == 0, "ember fallback: meter still consumed even though _defender was dead")` → `_check(pc.bonus_meter.value == Combatant.GRAND_SACRIFICE_CONSUME_BM_BONUS, "ember fallback: meter still consumed (down to the bonus amount) even though _defender was dead")`

- [ ] **Step 6: Run the full Grand Sacrifice regression suite**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_grand_sacrifice.gd`
Expected: `GRAND SACRIFICE TEST PASSED`

- [ ] **Step 7: Commit**

```bash
git add combat/combatant.gd tests/test_grand_sacrifice.gd tests/test_summoner_meter_economy.gd
git commit -m "feat(summoner): Bonus Meter bonus on Grand Sacrifice consumption"
```

---

### Task 4: Final full-suite regression pass

**Files:** none (verification only)

- [ ] **Step 1: Run the complete test suite**

Godot has no built-in "run every `tests/*.gd`" command in this project — run each file individually (or reuse whatever CI/local script already exists for this, if one does; check for it before doing 100+ manual invocations). At minimum, re-run every file this plan's diffs could plausibly affect:

```bash
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_summoner_meter_economy.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_summoner_class.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_grand_sacrifice.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dew_minion.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_hasty_minion.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_misfortune_minion.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_minion_lifecycle.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_minion_library.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_stale_active_minion_reset.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_bonus_meter.gd
```

Expected: every file prints its own "... PASSED" line, with **zero** occurrences of `SCRIPT ERROR` or `FAIL` in the combined output (per CLAUDE.md's "silent script-error-exits-zero" gotcha — grep the actual text output, don't trust exit codes alone).

- [ ] **Step 2: Report the final flow to the player for human playtest**

Summarize in plain language (for a non-engineer read): a Summoner now gains +1 Bonus Meter for every minion-summon cast (Ember/Dew/Misfortune/Hasty), +2 more when a minion completes its full 3-stage lifecycle and fades away on its own, and firing Grand Sacrifice leaves +2 in the meter afterward instead of a hard 0. Ask the player to playtest a full fight or two and report whether the meter now reaches cap at a reasonable pace, and whether the 3 new numbers (1 / 2 / 2) feel right or need tuning — this plan intentionally does not touch `resolve_post_combat()`'s floor/cap carryover formula itself, which was the original open design question and remains a separate follow-up.

---

## Self-Review Notes

- **Spec coverage:** Option 2 (reduced-weight charge on summon cast) → Task 1. Option 3's two triggers (natural minion expiry → Task 2; Grand Sacrifice consumption → Task 3) → both covered. Regression safety for the pre-existing `_run_minion_stage()` callers and `test_grand_sacrifice.gd`'s stale assertions → Task 2 Step 5 and Task 3 Step 5.
- **Placeholder scan:** all three new constants have concrete starting values (1, 2, 2) with `[ASSUMPTION]` doc comments, not "TBD" — consistent with `GRAND_SACRIFICE_EMBER_BURST`-style existing constants in this file.
- **Type consistency:** `minion_caster: Combatant`, `_apply_minion_summon_payoff(caster: Combatant, summon_tier: int) -> void`, `SUMMON_CAST_BM_CHARGE`/`MINION_NATURAL_EXPIRY_BM_BONUS` (both `Combat`-scoped `int` consts), `GRAND_SACRIFICE_CONSUME_BM_BONUS` (`Combatant`-scoped `int` const) — used identically across Tasks 1-4 and in the test file.
