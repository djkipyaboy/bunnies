# Warrior Rank-2 Content Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement all 6 locked rank-2 content rows for the Warrior class (Rend, Sundering Strike,
Heroic Guard, Second Wind, Last Stand, and the Ultimate renamed Wild → Devastating Strikes), per the
approved design spec.

**Architecture:** Each row's rank-2 content reads `Combatant.ability_talent_row_rank(row_id)` (already
shipped, returns 1 or 2 off `level`) at the exact call site that currently authors that ability's
rank-1 numbers — no new gating infrastructure needed. Two rows need a small new reel-builder function
(`ActionReel.make_rend()` gets a new param; a new `ActionReel.make_sundering_strike()` is added). Two
rows add new orchestrator-level (`combat.gd`) per-hit checks alongside the existing Twist the
Knife/Vicious Return pattern. The Ultimate rename touches 8 files' worth of string literals plus its
own rank-2 mechanic (a caller-side reel top-up in `main_phase_plan.gd`, never touching the shared
`fire_sticky_wild()` plumbing Skirmisher also depends on).

**Tech Stack:** Godot 4.6, GDScript, headless `SceneTree`-based tests run via
`Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/<file>.gd`.

**Spec:** `docs/superpowers/specs/2026-09-06-warrior-rank2-content-design.md`

## Global Constraints

- Round up all damage/healing (`ceili()`), project-wide convention (CLAUDE.md, memory
  `round-up-damage-healing`).
- Every number in the spec is an `[ASSUMPTION]` placeholder (CLAUDE.md §4) — implement as plain data
  (constants/literals), not anything requiring a config file; playtest will retune later.
- Do NOT modify `Combatant.fire_sticky_wild()`, the `sticky_wild_count`/`sticky_wild_spins_remaining`
  fields, or `combat_resolver.gd`'s `WILD_CRIT_CHANCE` — all shared with the Skirmisher's own Ultimate.
  Every Devastating-Strikes-specific rank-2 change lives at the CALL SITE (`main_phase_plan.gd`) or in
  a class-id-gated check (`combat.gd`), never inside that shared function.
- GDScript static typing: typed vars/params/returns throughout (existing codebase convention).
- Run each task's test file after every code change with the Godot headless command above; a test
  file exiting non-zero (or printing `SCRIPT ERROR`/`FAIL` even at exit 0 — see CLAUDE.md's
  silent-script-error-exits-zero gotcha) means the task is not done.

---

## Task 1: Rend rank-2 (accuracy, stacks/curve, meter charge)

**Files:**
- Modify: `combat/resources/action_reel.gd:75` (`make_rend`)
- Modify: `combat/combatant.gd:1646-1652` (`try_rend_reel`), `combat/combatant.gd:993-1004`
  (`apply_rider_talent_adjustments`'s `&"bleed"` arm)
- Modify: `combat/combat.gd:3092-3101` (generic rider-attach block, Bleed meter-charge hook)
- Test: `tests/test_rend_reel.gd`, `tests/test_ability_talents_warrior.gd`

**Interfaces:**
- Consumes: `Combatant.ability_talent_row_rank(row_id: StringName) -> int` (already shipped).
- Produces: `ActionReel.make_rend(type: DamageType = null, rank2: bool = false) -> ActionReel` — the
  `rank2` param is new; existing callers (the test file's `ActionReel.make_rend(slashing)`) are
  unaffected since it defaults to `false`.

- [ ] **Step 1: Write the failing test — Rend's own reel at rank 2**

Append to `tests/test_rend_reel.gd`, right before the final `print(...)`/`quit(...)` lines:

```gdscript
	# Rank 2 (2026-09-06 warrior-rank2-content spec §2.1): the 5 crit-fail faces convert to
	# success faces (still 0-multiplier, still bleed-riddled) — 70% -> 80% hit rate.
	var rend2: ActionReel = ActionReel.make_rend(slashing, true)
	var hit_faces2: int = 0
	var crit_fail_faces2: int = 0
	for f: ReelFace in rend2.faces:
		if f.result_tier == ReelFace.ResultTier.CRIT_FAILURE:
			crit_fail_faces2 += 1
		if f.result_tier == ReelFace.ResultTier.SUCCESS or f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
			hit_faces2 += 1
			_check(f.multiplier == 0.0, "rend rank 2 hit face has 0 multiplier")
			_check(f.rider_effect_id == &"bleed", "rend rank 2 hit face carries bleed rider")
	_check(crit_fail_faces2 == 0, "rend rank 2 has 0 crit-fail faces (converted to success)")
	_check(hit_faces2 == 40, "rend rank 2 has 40 hit faces (80%% hit rate, got %d)" % hit_faces2)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_rend_reel.gd`
Expected: FAIL/SCRIPT ERROR — `make_rend()` doesn't accept a second argument yet.

- [ ] **Step 3: Implement `make_rend`'s rank-2 param**

In `combat/resources/action_reel.gd`, replace the existing `make_rend`:

```gdscript
static func make_rend(type: DamageType = null) -> ActionReel:
	var reel: ActionReel = make_ability_attack(type)
	reel.is_weapon_attack = false  # Rend hits apply BLEED (a debuff), not a weapon swing — out of paylines
	for face: ReelFace in reel.faces:
		if face.result_tier == ReelFace.ResultTier.SUCCESS or face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
			face.multiplier = 0.0
			face.rider_effect_id = &"bleed"
	return reel
```

with:

```gdscript
## [param rank2] (2026-09-06 warrior-rank2-content spec §2.1): at rank 2, converts every CRIT_FAILURE
## face into a SUCCESS face BEFORE the hit-face loop below zeroes its multiplier and attaches the
## bleed rider — so the converted faces become full hit faces too, taking the composition from
## 70% -> 80% hit rate (5 crit-fail/10 fail/30 success/5 crit-success -> 0/10/35/5).
static func make_rend(type: DamageType = null, rank2: bool = false) -> ActionReel:
	var reel: ActionReel = make_ability_attack(type)
	reel.is_weapon_attack = false  # Rend hits apply BLEED (a debuff), not a weapon swing — out of paylines
	if rank2:
		for face: ReelFace in reel.faces:
			if face.result_tier == ReelFace.ResultTier.CRIT_FAILURE:
				face.result_tier = ReelFace.ResultTier.SUCCESS
	for face: ReelFace in reel.faces:
		if face.result_tier == ReelFace.ResultTier.SUCCESS or face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
			face.multiplier = 0.0
			face.rider_effect_id = &"bleed"
	return reel
```

- [ ] **Step 4: Wire the rank check into `try_rend_reel`**

In `combat/combatant.gd`, replace:

```gdscript
func try_rend_reel(type: DamageType, cost: int, cap: int) -> bool:
	if turn_reels.size() >= cap:
		return false
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	turn_reels.append(ActionReel.make_rend(type))
	return true
```

with:

```gdscript
func try_rend_reel(type: DamageType, cost: int, cap: int) -> bool:
	if turn_reels.size() >= cap:
		return false
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	turn_reels.append(ActionReel.make_rend(type, ability_talent_row_rank(&"base_ability") >= 2))
	return true
```

- [ ] **Step 5: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_rend_reel.gd`
Expected: `REND REEL TEST PASSED`

- [ ] **Step 6: Commit**

```bash
git add combat/resources/action_reel.gd combat/combatant.gd tests/test_rend_reel.gd
git commit -m "feat(warrior): Rend rank-2 own-reel accuracy bump (70%% -> 80%%)"
```

- [ ] **Step 7: Write the failing test — Bleed's rank-2 curve/stacks**

`tests/test_ability_talents_warrior.gd`'s `_test_rend_row()` currently asserts rank-1 numbers using
`_mk_warrior()` (which sets `level = Combatant.MAX_LEVEL = 10` — ABOVE `base_ability`'s rank-2
threshold of level 5, so every existing assertion in this function is actually already running in
rank-2 territory and must be corrected, not just extended). Replace the entire `_test_rend_row()`
function body with:

```gdscript
func _test_rend_row() -> void:
	var c2: Combatant = _mk_warrior()
	_check(c2.pick_ability_talent(&"base_ability", &"rend_deeper_cut"), "picks rend_deeper_cut")
	var bleed: Effect = EffectLibrary.make(&"bleed")
	c2.apply_rider_talent_adjustments(&"bleed", bleed, c2)
	var rank2_base: Array = [0.60, 0.95, 1.35, 1.70, 2.25]
	for i: int in range(rank2_base.size()):
		_check(is_equal_approx(bleed.dot_fractions[i], rank2_base[i] * 1.35),
			"rend_deeper_cut (rank 2): Bleed fraction %d is the rank-2 curve +35%% (got %.4f, want %.4f)" % [i, bleed.dot_fractions[i], rank2_base[i] * 1.35])
	_check(bleed.max_stacks == 4, "rend_deeper_cut alone (rank 2, no rend_lasting_wound): max_stacks is 4 (got %d)" % bleed.max_stacks)

	var c3: Combatant = _mk_warrior()
	_check(c3.pick_ability_talent(&"base_ability", &"rend_lasting_wound"), "picks rend_lasting_wound")
	var bleed2: Effect = EffectLibrary.make(&"bleed")
	c3.apply_rider_talent_adjustments(&"bleed", bleed2, c3)
	_check(bleed2.max_stacks == 5, "rend_lasting_wound (rank 2): Bleed max_stacks is 5 (got %d)" % bleed2.max_stacks)
	_check(bleed2.dot_fractions.size() == 5, "rend_lasting_wound (rank 2): Bleed curve has 5 entries (got %d)" % bleed2.dot_fractions.size())
	_check(is_equal_approx(bleed2.dot_fractions[4], 2.25), "rend_lasting_wound (rank 2): 5th stack fraction is the deliberate spike, 2.25 (got %.4f)" % bleed2.dot_fractions[4])

	# Salted Wound: bonus only fires if the TARGET already carries Sundered.
	var c4: Combatant = _mk_warrior()
	_check(c4.pick_ability_talent(&"base_ability", &"rend_salted_wound"), "picks rend_salted_wound")
	var target_plain: Combatant = _mk_warrior()
	var bleed3: Effect = EffectLibrary.make(&"bleed")
	c4.apply_rider_talent_adjustments(&"bleed", bleed3, target_plain)
	for i: int in range(rank2_base.size()):
		_check(is_equal_approx(bleed3.dot_fractions[i], rank2_base[i]),
			"rend_salted_wound (rank 2): no bonus vs. a target with no Sundered (fraction %d unchanged from the rank-2 curve)" % i)

	var c5: Combatant = _mk_warrior()
	_check(c5.pick_ability_talent(&"base_ability", &"rend_salted_wound"), "picks rend_salted_wound")
	var target_sundered: Combatant = _mk_warrior()
	target_sundered.attach_effect(EffectLibrary.make(&"sundered"))
	var bleed4: Effect = EffectLibrary.make(&"bleed")
	c5.apply_rider_talent_adjustments(&"bleed", bleed4, target_sundered)
	for i: int in range(rank2_base.size()):
		_check(is_equal_approx(bleed4.dot_fractions[i], rank2_base[i] * 1.25),
			"rend_salted_wound (rank 2): +25%% vs. a Sundered target (fraction %d got %.4f, want %.4f)" % [i, bleed4.dot_fractions[i], rank2_base[i] * 1.25])

	# Mutual exclusion: only 1 pick per row.
	var c6: Combatant = _mk_warrior()
	_check(c6.pick_ability_talent(&"base_ability", &"rend_deeper_cut"), "first pick on the Rend row succeeds")
	_check(not c6.pick_ability_talent(&"base_ability", &"rend_lasting_wound"), "a second pick on an already-filled row is rejected (cap of 1/row)")
	_check(c6.has_ability_talent(&"rend_deeper_cut"), "the row's original pick is still active")

	# Rank<2 regression: below base_ability's rank-2/talent threshold (level 5), the OLD rank-1
	# curve/cap still apply (no talent can be picked this low, so this proves the untouched branch).
	var c7: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	c7.level = 1
	var bleed5: Effect = EffectLibrary.make(&"bleed")
	var rank1_base: Array = bleed5.dot_fractions.duplicate()
	c7.apply_rider_talent_adjustments(&"bleed", bleed5, c7)
	_check(rank1_base == [0.50, 0.80, 1.15], "sanity: EffectLibrary's Bleed default is still the rank-1 curve")
	_check(bleed5.dot_fractions == rank1_base, "rank<2: Bleed curve is untouched at level 1")
	_check(bleed5.max_stacks == 3, "rank<2: Bleed max_stacks is untouched at 3 (got %d)" % bleed5.max_stacks)
```

- [ ] **Step 8: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_warrior.gd`
Expected: FAIL on the new rank-2-curve assertions (still using the old flat `[0.50,0.80,1.15]` +
`rend_deeper_cut` multiply, and `max_stacks` still 3/4 instead of 4/5).

- [ ] **Step 9: Implement the rank-2 curve/stacks in `apply_rider_talent_adjustments`**

In `combat/combatant.gd`, replace the `&"bleed"` arm:

```gdscript
				&"bleed":
					if has_ability_talent(&"rend_deeper_cut"):
						for i: int in range(effect.dot_fractions.size()):
							effect.dot_fractions[i] *= 1.35
					if has_ability_talent(&"rend_lasting_wound"):
						effect.max_stacks = 4
						if effect.dot_fractions.size() < 4:
							effect.dot_fractions.append(1.55)
					if has_ability_talent(&"rend_salted_wound") and target.has_effect(&"sundered"):
						for i: int in range(effect.dot_fractions.size()):
							effect.dot_fractions[i] *= 1.25
```

with:

```gdscript
				&"bleed":
					# Rank-2 (2026-09-06 warrior-rank2-content spec §2): swap the base curve/cap
					# BEFORE the existing talent multiplies below run, so they still compose UNDER
					# the new rank-2 numbers rather than needing their own rank-aware branches.
					if ability_talent_row_rank(&"base_ability") >= 2:
						effect.dot_fractions = [0.60, 0.95, 1.35, 1.70, 2.25]
						effect.max_stacks = 5 if has_ability_talent(&"rend_lasting_wound") else 4
					elif has_ability_talent(&"rend_lasting_wound"):
						effect.max_stacks = 4
						if effect.dot_fractions.size() < 4:
							effect.dot_fractions.append(1.55)
					if has_ability_talent(&"rend_deeper_cut"):
						for i: int in range(effect.dot_fractions.size()):
							effect.dot_fractions[i] *= 1.35
					if has_ability_talent(&"rend_salted_wound") and target.has_effect(&"sundered"):
						for i: int in range(effect.dot_fractions.size()):
							effect.dot_fractions[i] *= 1.25
```

- [ ] **Step 10: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_warrior.gd`
Expected: `WARRIOR ABILITY TALENTS TEST PASSED` (this file also still contains pre-existing,
not-yet-updated Sundering Strike/Second Wind/Last Stand/Wild assertions that Tasks 2/4/5/6 will fix —
if any of THOSE fail right now, that's expected and out of scope for this task; only confirm the Rend
section's own assertions now pass by reading the printed `ok`/`FAIL` lines for `_test_rend_row`).

- [ ] **Step 11: Commit**

```bash
git add combat/combatant.gd tests/test_ability_talents_warrior.gd
git commit -m "feat(warrior): Rend rank-2 Bleed curve/stack-cap bump"
```

- [ ] **Step 12: Implement the meter-charge-on-max-stack-hit mechanic**

In `combat/combat.gd`, find the generic rider-attach block (starting `if attack.rider_effect_id != &"":`,
around line 3092). Immediately before the line `t.attach_effect(rider)`, add a stack snapshot; then
immediately after that same line, add the meter-charge check:

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
						# Warrior Rend rank-2 (2026-09-06 warrior-rank2-content spec §2.4): snapshot the
						# target's CURRENT Bleed stack count before this attach, so the check below can
						# tell "just reached the new max cap this hit" from "was already at cap".
						var bleed_stacks_before_this_hit: int = 0
						if rider.id == &"bleed":
							for e2: Effect in t.active_effects:
								if e2.id == &"bleed":
									bleed_stacks_before_this_hit = e2.stacks
						t.attach_effect(rider)
						if rider.id == &"bleed" and _attacker.class_id == &"warrior" and _attacker.ability_talent_row_rank(&"base_ability") >= 2 and _attacker.bonus_meter != null:
							for e2: Effect in t.active_effects:
								if e2.id == &"bleed" and e2.stacks == e2.max_stacks and bleed_stacks_before_this_hit < e2.max_stacks:
									var meter_bonus: int = 8 if e2.max_stacks == 5 else 5
									_attacker.bonus_meter.add_flat(meter_bonus)
									_log("  💢 %s's Bleed reaches max stacks — BM +%d (%d/%d)" % [_attacker.display_name, meter_bonus, _attacker.bonus_meter.value, _attacker.bonus_meter.cap])
									if _panels.has(_attacker):
										(_panels[_attacker] as CombatantPanel).refresh_resources()
									break
```

(Keep every following line in that block — the Crippling Shot Wounded chain, the `talent_extra_rider_stack`
check, the log line, the panel refreshes — exactly as they already are; only the two new blocks above
are inserted.)

- [ ] **Step 13: Run the full test suite's Rend-adjacent files to confirm no regression**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_rend_reel.gd`
Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_warrior.gd`
Expected: both still pass (this step is orchestrator-level and has no dedicated headless test per the
spec's own Testing section — it needs a live Combat scene to fire a real hit — so this step only
proves no regression, not the new mechanic itself; full behavior is a playtest item).

- [ ] **Step 14: Commit**

```bash
git add combat/combat.gd
git commit -m "feat(warrior): Rend rank-2 meter charge on hitting Bleed's new max stack cap"
```

---

## Task 2: Sundering Strike rank-2 (accuracy, Sundered magnitude)

**Files:**
- Modify: `combat/resources/action_reel.gd` (new `make_sundering_strike`)
- Modify: `combat/combatant.gd:1654-1662` (`try_sundering_strike`), `combat/combatant.gd:1005-1007`
  (`apply_rider_talent_adjustments`'s `&"sundered"` arm)
- Test: new `tests/test_sundering_strike_reel.gd`, `tests/test_ability_talents_warrior.gd`

**Interfaces:**
- Consumes: `Combatant.ability_talent_row_rank(&"ability_l2")`.
- Produces: `ActionReel.make_sundering_strike(type: DamageType, rank2: bool = false) -> ActionReel`.

- [ ] **Step 1: Write the failing test — Sundering Strike's own reel**

Create `tests/test_sundering_strike_reel.gd`:

```gdscript
extends SceneTree

# Headless test: ActionReel.make_sundering_strike — real-damage reel + sundered rider, with a
# rank-2 accuracy bump mirroring Rend's own (see tests/test_rend_reel.gd).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_sundering_strike_reel.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")

	# Rank<2 (default): 70% hit rate, real damage on SUCCESS/CRIT_SUCCESS, sundered rider.
	var reel1: ActionReel = ActionReel.make_sundering_strike(slashing)
	var hit_faces1: int = 0
	var crit_fail_faces1: int = 0
	for f: ReelFace in reel1.faces:
		if f.result_tier == ReelFace.ResultTier.CRIT_FAILURE:
			crit_fail_faces1 += 1
		if f.result_tier == ReelFace.ResultTier.SUCCESS or f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
			hit_faces1 += 1
			_check(f.multiplier > 0.0, "rank<2 hit face keeps real damage")
			_check(f.rider_effect_id == &"sundered", "rank<2 hit face carries sundered rider")
	_check(crit_fail_faces1 == 5, "rank<2 has 5 crit-fail faces (got %d)" % crit_fail_faces1)
	_check(hit_faces1 == 35, "rank<2 has 35 hit faces (70%% hit rate, got %d)" % hit_faces1)

	# Rank 2: crit-fail faces convert to success (real damage + sundered rider), 80% hit rate.
	var reel2: ActionReel = ActionReel.make_sundering_strike(slashing, true)
	var hit_faces2: int = 0
	var crit_fail_faces2: int = 0
	for f: ReelFace in reel2.faces:
		if f.result_tier == ReelFace.ResultTier.CRIT_FAILURE:
			crit_fail_faces2 += 1
		if f.result_tier == ReelFace.ResultTier.SUCCESS or f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
			hit_faces2 += 1
			_check(f.multiplier > 0.0, "rank 2 hit face keeps real damage")
			_check(f.rider_effect_id == &"sundered", "rank 2 hit face carries sundered rider")
	_check(crit_fail_faces2 == 0, "rank 2 has 0 crit-fail faces (converted to success)")
	_check(hit_faces2 == 40, "rank 2 has 40 hit faces (80%% hit rate, got %d)" % hit_faces2)

	print(("SUNDERING STRIKE REEL TEST PASSED" if _failures == 0 else "SUNDERING STRIKE REEL TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_sundering_strike_reel.gd`
Expected: FAIL/SCRIPT ERROR — `make_sundering_strike` doesn't exist yet.

- [ ] **Step 3: Implement `make_sundering_strike`**

In `combat/resources/action_reel.gd`, add a new static function right after `make_rend`:

```gdscript
## Builds the Warrior's "Sundering Strike" reel (2026-09-06 warrior-rank2-content spec §3.2):
## real-damage weapon-type reel whose hit faces carry the &"sundered" rider — unlike Rend, this
## deals real damage. At rank 2, converts CRIT_FAILURE faces into SUCCESS faces (same accuracy
## bump shape as make_rend's own rank2 param) — 70% -> 80% hit rate.
static func make_sundering_strike(type: DamageType, rank2: bool = false) -> ActionReel:
	var reel: ActionReel = make_ability_attack(type, &"sundered")
	if rank2:
		for face: ReelFace in reel.faces:
			if face.result_tier == ReelFace.ResultTier.CRIT_FAILURE:
				face.result_tier = ReelFace.ResultTier.SUCCESS
				face.multiplier = 1.0
				face.rider_effect_id = &"sundered"
	return reel
```

- [ ] **Step 4: Wire it into `try_sundering_strike`**

In `combat/combatant.gd`, replace:

```gdscript
func try_sundering_strike(type: DamageType, cost: int, cap: int) -> bool:
	if turn_reels.size() >= cap:
		return false
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	turn_reels.append(ActionReel.make_ability_attack(type, &"sundered"))
	return true
```

with:

```gdscript
func try_sundering_strike(type: DamageType, cost: int, cap: int) -> bool:
	if turn_reels.size() >= cap:
		return false
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	turn_reels.append(ActionReel.make_sundering_strike(type, ability_talent_row_rank(&"ability_l2") >= 2))
	return true
```

- [ ] **Step 5: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_sundering_strike_reel.gd`
Expected: `SUNDERING STRIKE REEL TEST PASSED`

Also run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_sundering_strike.gd`
Expected: still `PASSED` (no rank dependency in that file's own assertions — it uses `c.level = 2`,
below `ability_l2`'s rank-2 threshold of 6, so it stays a pure rank-1 regression unaffected by this change).

- [ ] **Step 6: Commit**

```bash
git add combat/resources/action_reel.gd combat/combatant.gd tests/test_sundering_strike_reel.gd
git commit -m "feat(warrior): Sundering Strike rank-2 own-reel accuracy bump (70%% -> 80%%)"
```

- [ ] **Step 7: Write the failing test — Sundered magnitude rank-2 bump**

In `tests/test_ability_talents_warrior.gd`'s `_test_sundering_strike_row()`, replace the opening block:

```gdscript
func _test_sundering_strike_row() -> void:
	var c2: Combatant = _mk_warrior()
	_check(c2.pick_ability_talent(&"ability_l2", &"sunder_deeper"), "picks sunder_deeper")
	var sundered: Effect = EffectLibrary.make(&"sundered")
	c2.apply_rider_talent_adjustments(&"sundered", sundered, c2)
	_check(is_equal_approx(sundered.magnitude, 1.35), "sunder_deeper: Sundered's incoming multiplier is 1.35 (got %.3f)" % sundered.magnitude)
	_check(sundered.duration == 2, "sunder_deeper alone leaves duration at 2")
```

with:

```gdscript
func _test_sundering_strike_row() -> void:
	var c2: Combatant = _mk_warrior()
	_check(c2.pick_ability_talent(&"ability_l2", &"sunder_deeper"), "picks sunder_deeper")
	var sundered: Effect = EffectLibrary.make(&"sundered")
	c2.apply_rider_talent_adjustments(&"sundered", sundered, c2)
	_check(is_equal_approx(sundered.magnitude, 1.45), "sunder_deeper (rank 2): Sundered's incoming multiplier is 1.45 (got %.3f)" % sundered.magnitude)
	_check(sundered.duration == 2, "sunder_deeper alone leaves duration at 2")
```

Then, at the end of `_test_sundering_strike_row()` (after the existing mutual-exclusion-independent
`sunder_twist_knife`/`sunder_vicious_return` checks, before the function's closing brace), add:

```gdscript
	# Rank<2 regression + rank-2-no-talent baseline.
	var c7: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	c7.level = 1
	var sundered2: Effect = EffectLibrary.make(&"sundered")
	c7.apply_rider_talent_adjustments(&"sundered", sundered2, c7)
	_check(is_equal_approx(sundered2.magnitude, 1.30), "rank<2: Sundered baseline magnitude untouched at 1.30 (got %.3f)" % sundered2.magnitude)

	var c8: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	c8.level = 6  # ability_l2's rank-2 threshold, no talent picked
	var sundered3: Effect = EffectLibrary.make(&"sundered")
	c8.apply_rider_talent_adjustments(&"sundered", sundered3, c8)
	_check(is_equal_approx(sundered3.magnitude, 1.40), "rank 2 baseline (no talent): Sundered magnitude is 1.40 (got %.3f)" % sundered3.magnitude)
```

- [ ] **Step 8: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_warrior.gd`
Expected: FAIL on the `sunder_deeper`/rank-2-baseline assertions (still returning 1.35/1.30 with no
rank-2 path).

- [ ] **Step 9: Implement the rank-2 magnitude bump**

In `combat/combatant.gd`, replace the `&"sundered"` arm:

```gdscript
				&"sundered":
					if has_ability_talent(&"sunder_deeper"):
						effect.magnitude = 1.35
```

with:

```gdscript
				&"sundered":
					var sunder_rank: int = ability_talent_row_rank(&"ability_l2")
					if has_ability_talent(&"sunder_deeper"):
						effect.magnitude = 1.45 if sunder_rank >= 2 else 1.35
					elif sunder_rank >= 2:
						effect.magnitude = 1.40
```

- [ ] **Step 10: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_warrior.gd`
Expected: the Sundering Strike section's assertions now pass (Rend section already fixed in Task 1;
Heroic Guard/Second Wind/Last Stand/Wild sections still pending Tasks 3-6).

- [ ] **Step 11: Commit**

```bash
git add combat/combatant.gd tests/test_ability_talents_warrior.gd
git commit -m "feat(warrior): Sundering Strike rank-2 Sundered magnitude bump (1.30 -> 1.40)"
```

---

## Task 3: Heroic Guard rank-2 (meter charge on absorbed hits)

**Files:**
- Modify: `combat/combat.gd` (`_apply_attack()`'s per-target loop)
- Test: `tests/test_heroic_guard.gd`

**Interfaces:**
- Consumes: `Combatant.ability_talent_row_rank(&"ability_l3")`, `Combatant.has_effect(&"guarded")`,
  `Combatant.bonus_meter.add_flat(amount: int)`.
- Produces: nothing new consumed by later tasks (this row is self-contained).

No baseline number changes — this row is a new orchestrator-level mechanic only, which (per the
spec's own Testing section) needs a live Combat scene to prove end-to-end and is deferred to
playtest. This task adds only a precondition test proving the rank gate itself is correct, matching
this codebase's established convention for orchestrator-only mechanics (see
`tests/test_ability_talents_warrior.gd`'s own header comment on Bleeding Wild for the precedent).

- [ ] **Step 1: Write the failing precondition test**

Append to `tests/test_heroic_guard.gd`, right before `quit()`:

```gdscript
	# Rank-2 meter-charge-on-absorbed-hit mechanic (2026-09-06 warrior-rank2-content spec §4): the
	# actual per-hit charge lives in combat.gd's _apply_attack() (orchestrator-level, needs a live
	# Combat scene) — headlessly, prove the rank gate itself reads correctly at the right levels.
	var rank_c: Combatant = cc.build_combatant(true)
	rank_c.level = 6
	_check(rank_c.ability_talent_row_rank(&"ability_l3") == 1, "rank<2 below level 7 (got %d)" % rank_c.ability_talent_row_rank(&"ability_l3"))
	rank_c.level = 7
	_check(rank_c.ability_talent_row_rank(&"ability_l3") == 2, "rank 2 at level 7 (got %d)" % rank_c.ability_talent_row_rank(&"ability_l3"))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_heroic_guard.gd`
Expected: PASS already (this step only exercises already-shipped `ability_talent_row_rank`
infrastructure — confirm it passes before touching `combat.gd`, so Step 4's own pass proves the new
`combat.gd` code didn't break this precondition, not that this precondition itself newly works).

- [ ] **Step 3: Implement the meter-charge mechanic**

In `combat/combat.gd`'s `_apply_attack()`, in the per-target loop, right after
`t.take_damage(attack.final_damage)` (before the `reel_surge_overflow_pending` block), add:

```gdscript
				# Warrior "Heroic Guard" rank-2 (2026-09-06 warrior-rank2-content spec §4): any hit
				# that connects on a Guarded Warrior at rank 2 grants a flat Bonus Meter charge — a
				# low-stakes trickle (any result tier, uncapped per turn), not a milestone burst like
				# Rend's stack-cap payoff. Gated on class_id: no other Warrior ability attaches
				# &"guarded", so this can't fire off a Guarded granted by another class's own kit
				# (those live on entirely different combatants).
				if t.class_id == &"warrior" and t.has_effect(&"guarded") and t.ability_talent_row_rank(&"ability_l3") >= 2 and t.bonus_meter != null:
					t.bonus_meter.add_flat(1)
					_log("  🛡 %s's Heroic Guard absorbs a hit — BM +1 (%d/%d)." % [t.display_name, t.bonus_meter.value, t.bonus_meter.cap])
					if _panels.has(t):
						(_panels[t] as CombatantPanel).refresh_resources()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_heroic_guard.gd`
Expected: PASS (unchanged from Step 2 — this confirms no regression from the `combat.gd` edit).

- [ ] **Step 5: Commit**

```bash
git add combat/combat.gd tests/test_heroic_guard.gd
git commit -m "feat(warrior): Heroic Guard rank-2 meter charge on absorbed hits"
```

---

## Task 4: Second Wind rank-2 (heal bump + Heal-over-Time)

**Files:**
- Modify: `combat/effect_library.gd` (new `&"second_wind_hot"` case)
- Modify: `combat/combatant.gd:1787-1801` (`apply_second_wind`)
- Test: `tests/test_second_wind.gd`, `tests/test_ability_talents_warrior.gd`

**Interfaces:**
- Consumes: `Combatant.ability_talent_row_rank(&"ability_l4")`, `Combatant.has_ability_talent()`.
- Produces: `EffectLibrary.make(&"second_wind_hot") -> Effect` — a standalone id (deliberately NOT
  reusing the shared `&"regen"` id, to avoid an unwanted merge if a Warrior ally is also carrying a
  Warden Regrowth/Wheat Hasty-Minion-granted `&"regen"` effect at the same time — `attach_effect()`
  merges by id).

- [ ] **Step 1: Write the failing test — heal % and HoT**

Append to `tests/test_second_wind.gd`, right before `quit()`:

```gdscript
	# Rank-2 (2026-09-06 warrior-rank2-content spec §5): heal 30%% -> 40%%, plus a new 2-turn HoT
	# at 5%% max HP per turn (10%% total). ability_l4 ranks to 2 at level 8.
	var rank2_c: Combatant = cc.build_combatant(true)
	rank2_c.level = 8
	rank2_c.resource_pool.stamina = rank2_c.resource_pool.max_stamina
	rank2_c.max_hp = 100; rank2_c.hp = 10
	_check(rank2_c.apply_second_wind(5), "apply_second_wind succeeds at rank 2")
	_check(rank2_c.hp == 50, "rank 2 baseline: heals 40%% max HP (10 + 40 = 50, got %d)" % rank2_c.hp)
	var hot: Effect = rank2_c._find_effect(&"second_wind_hot")
	_check(hot != null, "rank 2: a second_wind_hot HoT is attached")
	_check(hot != null and hot.duration == 2, "rank 2 baseline: HoT lasts 2 turns (got %d)" % (hot.duration if hot != null else -1))
	_check(hot != null and hot.beneficial, "the HoT is beneficial (heals, doesn't damage)")
	_check(hot != null and is_equal_approx(hot.dot_base_damage, 100.0), "the HoT's dot_base_damage is max_hp (got %.1f)" % (hot.dot_base_damage if hot != null else -1.0))
	_check(hot != null and hot.dot_fractions == [0.05], "the HoT ticks a flat 5%% every turn (got %s)" % str(hot.dot_fractions if hot != null else []))

	# Rank 2 + wind_deeper: heal 40%% + 10 = 50%%, HoT extends to 3 turns (same 5%%/turn rate, 15%% total).
	var rank2_deeper_c: Combatant = cc.build_combatant(true)
	rank2_deeper_c.level = 8
	rank2_deeper_c.resource_pool.stamina = rank2_deeper_c.resource_pool.max_stamina
	rank2_deeper_c.max_hp = 100; rank2_deeper_c.hp = 10
	_check(rank2_deeper_c.pick_ability_talent(&"ability_l4", &"wind_deeper"), "picks wind_deeper")
	_check(rank2_deeper_c.apply_second_wind(5), "apply_second_wind succeeds at rank 2 + wind_deeper")
	_check(rank2_deeper_c.hp == 60, "rank 2 + wind_deeper: heals 50%% max HP (10 + 50 = 60, got %d)" % rank2_deeper_c.hp)
	var hot_deeper: Effect = rank2_deeper_c._find_effect(&"second_wind_hot")
	_check(hot_deeper != null and hot_deeper.duration == 3, "rank 2 + wind_deeper: HoT lasts 3 turns (got %d)" % (hot_deeper.duration if hot_deeper != null else -1))

	# Rank<2 regression: no HoT, heal stays at the old 30%%.
	var rank1_c: Combatant = cc.build_combatant(true)
	rank1_c.level = 4
	rank1_c.resource_pool.stamina = rank1_c.resource_pool.max_stamina
	rank1_c.max_hp = 100; rank1_c.hp = 10
	_check(rank1_c.apply_second_wind(5), "apply_second_wind succeeds at rank<2")
	_check(rank1_c.hp == 40, "rank<2: still heals 30%% max HP (10 + 30 = 40, got %d)" % rank1_c.hp)
	_check(rank1_c._find_effect(&"second_wind_hot") == null, "rank<2: no HoT attached")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_second_wind.gd`
Expected: FAIL — `apply_second_wind` still heals 30%/45% only, no HoT exists yet.

- [ ] **Step 3: Add the new effect id**

In `combat/effect_library.gd`, insert a new case right before the final `_:` default arm (after the
`&"indestructible"` case):

```gdscript
		&"second_wind_hot":
			# Warrior "Second Wind" rank-2 (2026-09-06 warrior-rank2-content spec §5.2): a standalone
			# HoT id (deliberately NOT the shared &"regen" id — attach_effect() merges by id, and this
			# must never blend with a Warden Regrowth/Wheat Hasty-Minion-granted regen on the same
			# ally). Non-stacking (max_stacks 1): dot_damage() always reads dot_fractions[0], so a
			# single 0.05 entry ticks a flat 5% of dot_base_damage every turn for however many turns
			# duration lasts — the caller sets dot_base_damage (to max_hp) and duration (2 or 3).
			var e: Effect = Effect.new()
			e.id = &"second_wind_hot"; e.kind = Effect.Kind.DAMAGE_OVER_TIME
			e.dot_fractions = [0.05]; e.max_stacks = 1; e.beneficial = true
			return e
```

- [ ] **Step 4: Implement the rank-2 heal/HoT in `apply_second_wind`**

In `combat/combatant.gd`, replace:

```gdscript
func apply_second_wind(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	var heal_pct: float = 0.45 if has_ability_talent(&"wind_deeper") else 0.30
	heal(ceili(max_hp * heal_pct))
	cleanse()
	var guard: Effect = EffectLibrary.make(&"guarded")
	guard.duration = 3
	attach_effect(guard)
	if has_ability_talent(&"wind_empowering"):
		var empowered: Effect = EffectLibrary.make(&"empowered")
		empowered.magnitude = 1.15
		empowered.duration = 2
		attach_effect(empowered)
	return true
```

with:

```gdscript
func apply_second_wind(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	var rank: int = ability_talent_row_rank(&"ability_l4")
	var heal_pct: float
	if rank >= 2:
		heal_pct = 0.50 if has_ability_talent(&"wind_deeper") else 0.40
	else:
		heal_pct = 0.45 if has_ability_talent(&"wind_deeper") else 0.30
	heal(ceili(max_hp * heal_pct))
	cleanse()
	var guard: Effect = EffectLibrary.make(&"guarded")
	guard.duration = 3
	attach_effect(guard)
	if rank >= 2:
		var hot: Effect = EffectLibrary.make(&"second_wind_hot")
		hot.dot_base_damage = max_hp
		hot.duration = 3 if has_ability_talent(&"wind_deeper") else 2
		attach_effect(hot)
	if has_ability_talent(&"wind_empowering"):
		var empowered: Effect = EffectLibrary.make(&"empowered")
		empowered.magnitude = 1.15
		empowered.duration = 2
		attach_effect(empowered)
	return true
```

- [ ] **Step 5: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_second_wind.gd`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add combat/effect_library.gd combat/combatant.gd tests/test_second_wind.gd
git commit -m "feat(warrior): Second Wind rank-2 heal bump + Heal-over-Time"
```

- [ ] **Step 7: Fix the stale wind_deeper assertion in test_ability_talents_warrior.gd**

`_test_second_wind_row()` uses `_mk_warrior()` (level `Combatant.MAX_LEVEL` = 10, ABOVE `ability_l4`'s
rank-2 threshold of 8) for its `wind_deeper` check, which currently expects the OLD flat 45%. Replace:

```gdscript
	var c2: Combatant = _mk_warrior()
	c2.max_hp = 100; c2.hp = 10
	_check(c2.pick_ability_talent(&"ability_l4", &"wind_deeper"), "picks wind_deeper")
	_check(c2.apply_second_wind(2), "casts Second Wind (deeper)")
	_check(c2.hp == 55, "wind_deeper: Second Wind heals 45%% max HP (10 + 45 = 55, got %d)" % c2.hp)
```

with:

```gdscript
	var c2: Combatant = _mk_warrior()
	c2.max_hp = 100; c2.hp = 10
	_check(c2.pick_ability_talent(&"ability_l4", &"wind_deeper"), "picks wind_deeper")
	_check(c2.apply_second_wind(2), "casts Second Wind (deeper, rank 2)")
	_check(c2.hp == 60, "wind_deeper (rank 2): Second Wind heals 50%% max HP (10 + 50 = 60, got %d)" % c2.hp)
	var hot2: Effect = c2._find_effect(&"second_wind_hot")
	_check(hot2 != null and hot2.duration == 3, "wind_deeper (rank 2): HoT lasts 3 turns (got %d)" % (hot2.duration if hot2 != null else -1))
```

(`c3`'s `wind_empowering` check and `c4`/`c5`/`c5b`/`c6`'s `wind_desperate_recovery`/mutual-exclusion
checks are untouched by this pass — leave them exactly as they are.)

- [ ] **Step 8: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_warrior.gd`
Expected: the Second Wind section's assertions now pass.

- [ ] **Step 9: Commit**

```bash
git add tests/test_ability_talents_warrior.gd
git commit -m "fix(warrior): update stale Second Wind wind_deeper assertion for rank-2"
```

---

## Task 5: Last Stand rank-2 amplify

**Files:**
- Modify: `combat/combatant.gd:1231-1237` (`passive_outgoing_multiplier`'s `&"last_stand"` arm)
- Test: `tests/test_passive_last_stand.gd`, `tests/test_ability_talents_warrior.gd`

**Interfaces:**
- Consumes: `Combatant.ability_talent_row_rank(&"passive")`.
- Produces: nothing new consumed elsewhere.

- [ ] **Step 1: Write the failing test — amplified bonus**

In `tests/test_passive_last_stand.gd`, the existing `stand_vengeful` block sets `v.level = 9` (exactly
the `passive` row's amplification threshold) and expects the OLD +24%. Replace:

```gdscript
	var v: Combatant = Combatant.new()
	v.class_id = &"warrior"  # pick_ability_talent() validates against AbilityTalentLibrary.options_for(class_id, ...)
	v.passive_ability_id = &"last_stand"
	v.level = 9
	v.max_hp = 100; v.hp = 100  # full HP — the self-HP trigger would NOT fire
	_check(v.pick_ability_talent(&"passive", &"stand_vengeful"), "picks stand_vengeful")
	var enemy_plain: Combatant = Combatant.new()
	var enemy_doubly_debuffed: Combatant = Combatant.new()
	enemy_doubly_debuffed.attach_effect(EffectLibrary.make(&"bleed"))
	enemy_doubly_debuffed.attach_effect(EffectLibrary.make(&"sundered"))
	_check(v.passive_outgoing_multiplier(enemy_plain) == 1.0, "stand_vengeful: no bonus vs. an undebuffed target at full HP")
	_check(v.passive_outgoing_multiplier(enemy_doubly_debuffed) == 1.24, "stand_vengeful: +24% vs. a Bled+Sundered target even at full HP")
	var enemy_only_bled: Combatant = Combatant.new()
	enemy_only_bled.attach_effect(EffectLibrary.make(&"bleed"))
	_check(v.passive_outgoing_multiplier(enemy_only_bled) == 1.0, "stand_vengeful: no bonus vs. a target with only ONE of the two debuffs")
	quit()
```

with (same body, `v.level = 8` instead of `9` so this stays a pure rank-1 vengeful-trigger test, plus
a new amplified-rank block appended before `quit()`):

```gdscript
	var v: Combatant = Combatant.new()
	v.class_id = &"warrior"  # pick_ability_talent() validates against AbilityTalentLibrary.options_for(class_id, ...)
	v.passive_ability_id = &"last_stand"
	v.level = 8  # below the passive row's amplification threshold (9) — pure rank-1 vengeful test
	v.max_hp = 100; v.hp = 100  # full HP — the self-HP trigger would NOT fire
	_check(v.pick_ability_talent(&"passive", &"stand_vengeful"), "picks stand_vengeful")
	var enemy_plain: Combatant = Combatant.new()
	var enemy_doubly_debuffed: Combatant = Combatant.new()
	enemy_doubly_debuffed.attach_effect(EffectLibrary.make(&"bleed"))
	enemy_doubly_debuffed.attach_effect(EffectLibrary.make(&"sundered"))
	_check(v.passive_outgoing_multiplier(enemy_plain) == 1.0, "stand_vengeful: no bonus vs. an undebuffed target at full HP")
	_check(v.passive_outgoing_multiplier(enemy_doubly_debuffed) == 1.24, "stand_vengeful: +24% vs. a Bled+Sundered target even at full HP")
	var enemy_only_bled: Combatant = Combatant.new()
	enemy_only_bled.attach_effect(EffectLibrary.make(&"bleed"))
	_check(v.passive_outgoing_multiplier(enemy_only_bled) == 1.0, "stand_vengeful: no bonus vs. a target with only ONE of the two debuffs")

	# Rank-2 amplify (2026-09-06 warrior-rank2-content spec §6): +24% -> +34% at level 9+.
	var v2: Combatant = Combatant.new()
	v2.class_id = &"warrior"
	v2.passive_ability_id = &"last_stand"
	v2.level = 9
	v2.max_hp = 100; v2.hp = 30
	_check(v2.passive_outgoing_multiplier() == 1.34, "rank 2 (amplified): Last Stand is +34% at 30% HP (got %.3f)" % v2.passive_outgoing_multiplier())
	v2.hp = 31
	_check(v2.passive_outgoing_multiplier() == 1.0, "rank 2: neutral just above 30% HP")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_passive_last_stand.gd`
Expected: FAIL on the new `v2` amplified-rank assertions (still returning 1.24 at level 9).

- [ ] **Step 3: Implement the amplified bonus**

In `combat/combatant.gd`, replace:

```gdscript
			&"last_stand":
				var threshold: float = 0.40 if has_ability_talent(&"stand_wider") else 0.30
				var bonus: float = 1.24
				var self_triggered: bool = (float(hp) / float(maxi(max_hp, 1))) <= threshold
				var vengeful_triggered: bool = has_ability_talent(&"stand_vengeful") and defender != null and defender.has_effect(&"bleed") and defender.has_effect(&"sundered")
				return bonus if (self_triggered or vengeful_triggered) else 1.0
```

with:

```gdscript
			&"last_stand":
				var threshold: float = 0.40 if has_ability_talent(&"stand_wider") else 0.30
				# Amplified (level 9+, 2026-09-06 warrior-rank2-content spec §6): +24% -> +34%. The
				# thresholds/vengeful trigger above are unaffected — only the payoff size grows.
				var bonus: float = 1.34 if ability_talent_row_rank(&"passive") >= 2 else 1.24
				var self_triggered: bool = (float(hp) / float(maxi(max_hp, 1))) <= threshold
				var vengeful_triggered: bool = has_ability_talent(&"stand_vengeful") and defender != null and defender.has_effect(&"bleed") and defender.has_effect(&"sundered")
				return bonus if (self_triggered or vengeful_triggered) else 1.0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_passive_last_stand.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add combat/combatant.gd tests/test_passive_last_stand.gd
git commit -m "feat(warrior): Last Stand rank-2 amplify (+24%% -> +34%%)"
```

- [ ] **Step 6: Fix the stale assertions in test_ability_talents_warrior.gd**

`_test_last_stand_row()` uses `_mk_warrior()` (level `MAX_LEVEL` = 10, above the `passive` row's
amplify threshold of 9) throughout, so every `1.24` in it is now stale. Replace the entire function:

```gdscript
func _test_last_stand_row() -> void:
	var c: Combatant = _mk_warrior()
	c.passive_ability_id = &"last_stand"
	c.max_hp = 100; c.hp = 30
	_check(is_equal_approx(c.passive_outgoing_multiplier(), 1.24), "baseline Last Stand: +24% at 30% HP")

	var c3: Combatant = _mk_warrior()
	c3.passive_ability_id = &"last_stand"
	c3.max_hp = 100; c3.hp = 35
	_check(is_equal_approx(c3.passive_outgoing_multiplier(), 1.0), "sanity: 35% HP is above the baseline 30% threshold")
	_check(c3.pick_ability_talent(&"passive", &"stand_wider"), "picks stand_wider")
	_check(is_equal_approx(c3.passive_outgoing_multiplier(), 1.24), "stand_wider: Last Stand now active at 35% HP too (widened to 40%)")
	c3.hp = 41
	_check(is_equal_approx(c3.passive_outgoing_multiplier(), 1.0), "stand_wider: still inactive just above the widened 40% threshold")

	var c4: Combatant = _mk_warrior()
	c4.passive_ability_id = &"last_stand"
	c4.max_hp = 100; c4.hp = 30
	_check(is_equal_approx(c4.passive_incoming_multiplier(), 1.0), "baseline Last Stand grants no incoming reduction")
	_check(c4.pick_ability_talent(&"passive", &"stand_guarded"), "picks stand_guarded")
	_check(is_equal_approx(c4.passive_incoming_multiplier(), 0.9), "stand_guarded: -10%% incoming while Last Stand is active (got %.3f)" % c4.passive_incoming_multiplier())
	c4.hp = 31
	_check(is_equal_approx(c4.passive_incoming_multiplier(), 1.0), "stand_guarded: no reduction once Last Stand's own condition drops off")
```

with:

```gdscript
func _test_last_stand_row() -> void:
	var c: Combatant = _mk_warrior()
	c.passive_ability_id = &"last_stand"
	c.max_hp = 100; c.hp = 30
	_check(is_equal_approx(c.passive_outgoing_multiplier(), 1.34), "rank 2 (amplified): Last Stand is +34% at 30% HP")

	var c3: Combatant = _mk_warrior()
	c3.passive_ability_id = &"last_stand"
	c3.max_hp = 100; c3.hp = 35
	_check(is_equal_approx(c3.passive_outgoing_multiplier(), 1.0), "sanity: 35% HP is above the baseline 30% threshold")
	_check(c3.pick_ability_talent(&"passive", &"stand_wider"), "picks stand_wider")
	_check(is_equal_approx(c3.passive_outgoing_multiplier(), 1.34), "stand_wider (rank 2): Last Stand now active at 35% HP too (widened to 40%), +34%")
	c3.hp = 41
	_check(is_equal_approx(c3.passive_outgoing_multiplier(), 1.0), "stand_wider: still inactive just above the widened 40% threshold")

	var c4: Combatant = _mk_warrior()
	c4.passive_ability_id = &"last_stand"
	c4.max_hp = 100; c4.hp = 30
	_check(is_equal_approx(c4.passive_incoming_multiplier(), 1.0), "baseline Last Stand grants no incoming reduction")
	_check(c4.pick_ability_talent(&"passive", &"stand_guarded"), "picks stand_guarded")
	_check(is_equal_approx(c4.passive_incoming_multiplier(), 0.9), "stand_guarded: -10%% incoming while Last Stand is active (got %.3f)" % c4.passive_incoming_multiplier())
	c4.hp = 31
	_check(is_equal_approx(c4.passive_incoming_multiplier(), 1.0), "stand_guarded: no reduction once Last Stand's own condition drops off")

	# Rank<2 regression: below the passive row's amplification threshold (level 9).
	var c9: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	c9.level = 1
	c9.passive_ability_id = &"last_stand"
	c9.max_hp = 100; c9.hp = 30
	_check(is_equal_approx(c9.passive_outgoing_multiplier(), 1.24), "rank<2: Last Stand is still +24% at 30% HP (unamplified)")
```

- [ ] **Step 7: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_warrior.gd`
Expected: the Last Stand section's assertions now pass.

- [ ] **Step 8: Commit**

```bash
git add tests/test_ability_talents_warrior.gd
git commit -m "fix(warrior): update stale Last Stand assertions for rank-2 amplification"
```

---

## Task 6: Devastating Strikes — rename + rank-2 mechanics

**Files:**
- Modify: `combat/class_library.gd:44`
- Modify: `combat/main_phase_plan.gd:36-37, 566-569`
- Modify: `combat/combat.gd:1855, 2965`
- Modify: `combat/ui/ultimate_catalog.gd:13, 25`
- Modify: `combat/ability_talent_library.gd:84-97`
- Modify: `combat/combatant.gd:1203` (talent-id string rename only, `wild_executioner` in
  `outgoing_damage_multiplier`)
- Modify: `combat/combat.gd` (new crit-bonus check, `_apply_attack()`'s per-target loop)
- Test: `tests/test_ability_talents_warrior.gd`, `tests/test_class_library.gd`,
  `tests/test_ultimate_variants.gd`

**Interfaces:**
- Consumes: `Combatant.ability_talent_row_rank(&"ultimate")`, `Combatant.turn_reels`,
  `ActionReel.make_ability_attack(type)`, `Combatant.fire_sticky_wild(reel_count, spins)` (called,
  never modified).
- Produces: nothing new consumed by other tasks — this is the last content row.

- [ ] **Step 1: Write the failing test — id rename sanity checks**

In `tests/test_class_library.gd`, replace:

```gdscript
	_check(warrior.ultimate_id == &"wild", "warrior ultimate = wild (single-spin)")
```

with:

```gdscript
	_check(warrior.ultimate_id == &"devastating_strikes", "warrior ultimate = devastating_strikes (single-spin)")
```

In `tests/test_ultimate_variants.gd`, replace:

```gdscript
	# Warrior &"wild": single-spin.
	var w: Combatant = _pc(&"rend", &"wild", 3, slashing, 10)
	var pw: MainPhasePlan = MainPhasePlan.new(w, 2, 5, 2)
	pw.toggle_ultimate()
	pw.commit()
	_check(w.sticky_wild_spins_remaining == 1, "Warrior wild = 1 spin (got %d)" % w.sticky_wild_spins_remaining)
```

with:

```gdscript
	# Warrior &"devastating_strikes": single-spin (this combatant is built at the default level 1,
	# below the ultimate row's rank-2 threshold of 10, so no reel top-up applies here).
	var w: Combatant = _pc(&"rend", &"devastating_strikes", 3, slashing, 10)
	var pw: MainPhasePlan = MainPhasePlan.new(w, 2, 5, 2)
	pw.toggle_ultimate()
	pw.commit()
	_check(w.sticky_wild_spins_remaining == 1, "Warrior Devastating Strikes = 1 spin (got %d)" % w.sticky_wild_spins_remaining)
```

In `tests/test_ability_talents_warrior.gd`, replace the `all_ids` array entry:

```gdscript
		&"wild_executioner", &"wild_bleeding", &"wild_lasting",
```

with:

```gdscript
		&"devastating_executioner", &"devastating_bleeding", &"devastating_lasting",
```

Replace the entire `_test_wild_row()` function (name it `_test_devastating_strikes_row()`):

```gdscript
func _test_wild_row() -> void:
	var c: Combatant = _mk_warrior()
	c.bonus_meter.value = c.bonus_meter.cap
	_check(c.fire_sticky_wild(c.weapon.reels.size(), 1), "fires Wild (baseline)")
	_check(not c.has_effect(&"empowered"), "baseline Wild grants no Empowered")

	var c2: Combatant = _mk_warrior()
	c2.bonus_meter.value = c2.bonus_meter.cap
	_check(c2.pick_ability_talent(&"ultimate", &"wild_executioner"), "picks wild_executioner")
	_check(c2.fire_sticky_wild(c2.weapon.reels.size(), 1), "fires Wild (executioner)")
	var enemy_plain: Combatant = _mk_warrior()
	var enemy_doubly_debuffed: Combatant = _mk_warrior()
	enemy_doubly_debuffed.attach_effect(EffectLibrary.make(&"bleed"))
	enemy_doubly_debuffed.attach_effect(EffectLibrary.make(&"sundered"))
	_check(is_equal_approx(c2.outgoing_damage_multiplier(enemy_plain), 1.0), "wild_executioner: no bonus vs. an undebuffed target")
	_check(is_equal_approx(c2.outgoing_damage_multiplier(enemy_doubly_debuffed), 1.25), "wild_executioner: +25%% vs. a Bled+Sundered target while Wild is active (got %.3f)" % c2.outgoing_damage_multiplier(enemy_doubly_debuffed))
	c2.consume_wild_spin()
	_check(is_equal_approx(c2.outgoing_damage_multiplier(enemy_doubly_debuffed), 1.0), "wild_executioner: no bonus once Wild has been consumed")

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
```

with:

```gdscript
func _test_devastating_strikes_row() -> void:
	var c: Combatant = _mk_warrior()
	c.bonus_meter.value = c.bonus_meter.cap
	_check(c.fire_sticky_wild(c.weapon.reels.size(), 1), "fires Devastating Strikes (baseline, direct low-level call)")
	_check(not c.has_effect(&"empowered"), "baseline Devastating Strikes grants no Empowered")

	var c2: Combatant = _mk_warrior()
	c2.bonus_meter.value = c2.bonus_meter.cap
	_check(c2.pick_ability_talent(&"ultimate", &"devastating_executioner"), "picks devastating_executioner")
	_check(c2.fire_sticky_wild(c2.weapon.reels.size(), 1), "fires Devastating Strikes (executioner)")
	var enemy_plain: Combatant = _mk_warrior()
	var enemy_doubly_debuffed: Combatant = _mk_warrior()
	enemy_doubly_debuffed.attach_effect(EffectLibrary.make(&"bleed"))
	enemy_doubly_debuffed.attach_effect(EffectLibrary.make(&"sundered"))
	_check(is_equal_approx(c2.outgoing_damage_multiplier(enemy_plain), 1.0), "devastating_executioner: no bonus vs. an undebuffed target")
	_check(is_equal_approx(c2.outgoing_damage_multiplier(enemy_doubly_debuffed), 1.25), "devastating_executioner: +25%% vs. a Bled+Sundered target while active (got %.3f)" % c2.outgoing_damage_multiplier(enemy_doubly_debuffed))
	c2.consume_wild_spin()
	_check(is_equal_approx(c2.outgoing_damage_multiplier(enemy_doubly_debuffed), 1.0), "devastating_executioner: no bonus once consumed")

	# Bleeding's precondition state (the actual on-hit attach lives in combat.gd's _apply_attack(),
	# orchestrator-level — see the file header comment above).
	var c3: Combatant = _mk_warrior()
	c3.bonus_meter.value = c3.bonus_meter.cap
	_check(c3.pick_ability_talent(&"ultimate", &"devastating_bleeding"), "picks devastating_bleeding")
	_check(c3.fire_sticky_wild(c3.weapon.reels.size(), 1), "fires Devastating Strikes (bleeding)")
	_check(c3.sticky_wild_spins_remaining > 0, "Devastating Strikes is active for combat.gd's devastating_bleeding check to read")

	# c4/c5 are level MAX (rank 2 for the ultimate row) via _mk_warrior(), so committing through the
	# real MainPhasePlan dispatch now exercises the rank-2 reel top-up (§7.1) for real.
	var c4: Combatant = _mk_warrior()
	c4.bonus_meter.value = c4.bonus_meter.cap
	var plan: MainPhasePlan = MainPhasePlan.new(c4)
	_check(plan.ultimate_id == &"devastating_strikes", "sanity: Warrior's Ultimate id is &devastating_strikes")
	plan.toggle_ultimate()
	_check(plan.fire_ultimate_staged, "Devastating Strikes stages when the meter is armed")
	plan.commit()
	_check(c4.sticky_wild_spins_remaining == 1, "without Lasting Strikes, firing grants 1 spin (got %d)" % c4.sticky_wild_spins_remaining)
	_check(c4.turn_reels.size() == 5, "rank 2: reel top-up fills the loadout to 5 (got %d)" % c4.turn_reels.size())
	_check(c4.sticky_wild_count == 5, "rank 2: all 5 topped-up reels are marked wild (got %d)" % c4.sticky_wild_count)

	var c5: Combatant = _mk_warrior()
	c5.bonus_meter.value = c5.bonus_meter.cap
	_check(c5.pick_ability_talent(&"ultimate", &"devastating_lasting"), "picks devastating_lasting")
	var plan2: MainPhasePlan = MainPhasePlan.new(c5)
	plan2.toggle_ultimate()
	plan2.commit()
	_check(c5.sticky_wild_spins_remaining == 2, "devastating_lasting: firing grants 2 spins (got %d)" % c5.sticky_wild_spins_remaining)
	_check(c5.turn_reels.size() == 5, "rank 2 + devastating_lasting: reel top-up still fills to 5 (got %d)" % c5.turn_reels.size())

	# Rank<2 regression: a fresh level-1 Combatant (ultimate row's rank-2 threshold is level 10 —
	# MAX_LEVEL itself — so this can't be tested via _mk_warrior()).
	var c6: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	c6.bonus_meter.value = c6.bonus_meter.cap
	var plan3: MainPhasePlan = MainPhasePlan.new(c6)
	plan3.toggle_ultimate()
	plan3.commit()
	_check(c6.turn_reels.size() == 3, "rank<2: no reel top-up, stays at the weapon baseline of 3 (got %d)" % c6.turn_reels.size())
	_check(c6.sticky_wild_count == 3, "rank<2: only the 3 baseline reels are marked wild (got %d)" % c6.sticky_wild_count)
```

And in `_init()`, replace the call `_test_wild_row()` with `_test_devastating_strikes_row()`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_class_library.gd`
Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ultimate_variants.gd`
Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_warrior.gd`
Expected: FAIL — the production code still uses the old `&"wild"`/`wild_*` ids and has no reel top-up.

- [ ] **Step 3: Rename the Ultimate id and talent ids in production code**

In `combat/class_library.gd`, replace:

```gdscript
			c.ultimate_id = &"wild"  # single-spin crit-bias wild (distinct from the Skirmisher's 2-spin sticky wild)
```

with:

```gdscript
			c.ultimate_id = &"devastating_strikes"  # single-spin crit-bias wild (distinct from the Skirmisher's 2-spin sticky wild)
```

In `combat/ability_talent_library.gd`, replace the `&"ultimate"` row's block:

```gdscript
				&"ultimate":
					var u1: AbilityTalentOption = AbilityTalentOption.new()
					u1.id = &"wild_executioner"; u1.row_id = row_id
					u1.display_name = "Executioner's Wild"
					u1.description = "While Wild is active, hits against a target carrying BOTH Bleed and Sundered deal +25% bonus damage."
					var u2: AbilityTalentOption = AbilityTalentOption.new()
					u2.id = &"wild_bleeding"; u2.row_id = row_id
					u2.display_name = "Bleeding Wild"
					u2.description = "Any hit landed while Wild is active also applies a stack of Bleed."
					var u3: AbilityTalentOption = AbilityTalentOption.new()
					u3.id = &"wild_lasting"; u3.row_id = row_id
					u3.display_name = "Lasting Wild"
					u3.description = "Wild's crit bias lasts 2 spins instead of 1."
					return [u1, u2, u3]
```

with:

```gdscript
				&"ultimate":
					var u1: AbilityTalentOption = AbilityTalentOption.new()
					u1.id = &"devastating_executioner"; u1.row_id = row_id
					u1.display_name = "Executioner's Strikes"
					u1.description = "While Devastating Strikes is active, hits against a target carrying BOTH Bleed and Sundered deal +25% bonus damage."
					var u2: AbilityTalentOption = AbilityTalentOption.new()
					u2.id = &"devastating_bleeding"; u2.row_id = row_id
					u2.display_name = "Bleeding Strikes"
					u2.description = "Any hit landed while Devastating Strikes is active also applies a stack of Bleed."
					var u3: AbilityTalentOption = AbilityTalentOption.new()
					u3.id = &"devastating_lasting"; u3.row_id = row_id
					u3.display_name = "Lasting Strikes"
					u3.description = "Devastating Strikes' crit bias lasts 2 spins instead of 1."
					return [u1, u2, u3]
```

In `combat/combatant.gd`, replace the `wild_executioner` reference in `outgoing_damage_multiplier`:

```gdscript
	if class_id == &"warrior" and has_ability_talent(&"wild_executioner") and sticky_wild_spins_remaining > 0 and defender != null and defender.has_effect(&"bleed") and defender.has_effect(&"sundered"):
```

with:

```gdscript
	if class_id == &"warrior" and has_ability_talent(&"devastating_executioner") and sticky_wild_spins_remaining > 0 and defender != null and defender.has_effect(&"bleed") and defender.has_effect(&"sundered"):
```

In `combat/combat.gd`, replace the `wild_bleeding` reference:

```gdscript
			if _attacker.class_id == &"warrior" and _attacker.has_ability_talent(&"wild_bleeding") and _attacker.sticky_wild_spins_remaining > 0:
```

with:

```gdscript
			if _attacker.class_id == &"warrior" and _attacker.has_ability_talent(&"devastating_bleeding") and _attacker.sticky_wild_spins_remaining > 0:
```

Also in `combat/combat.gd`, replace the log-text match arm:

```gdscript
		&"wild": return "ULTIMATE: Wild (1 spin)"
```

with:

```gdscript
		&"devastating_strikes": return "ULTIMATE: Devastating Strikes (1 spin)"
```

In `combat/ui/ultimate_catalog.gd`, replace:

```gdscript
		&"wild": return "WILD (all reels crit-biased, 1 spin)"
```

with:

```gdscript
		&"devastating_strikes": return "DEVASTATING STRIKES (all reels crit-biased, 1 spin, +reels at rank 2)"
```

and replace:

```gdscript
		&"wild": return "Wild (full meter): all weapon reels crit-biased for 1 spin. Your base ability still works — fire both."
```

with:

```gdscript
		&"devastating_strikes": return "Devastating Strikes (full meter): all weapon reels crit-biased for 1 spin. At rank 2 (level 10), the loadout tops up to 5 reels and any crit landed deals +20% bonus damage. Your base ability still works — fire both."
```

- [ ] **Step 4: Rank-2 mechanic — reel top-up in main_phase_plan.gd**

In `combat/main_phase_plan.gd`, replace:

```gdscript
## Crit-bias WILD spin counts, separated per class (spec 2026-06-21 iteration 2):
## the Warrior's &"wild" is single-spin; the Skirmisher's &"sticky_wild" rides for two.
const WILD_SPINS: int = 1
const STICKY_WILD_SPINS: int = 2
```

with:

```gdscript
## Crit-bias WILD spin counts, separated per class (spec 2026-06-21 iteration 2):
## the Warrior's &"devastating_strikes" is single-spin; the Skirmisher's &"sticky_wild" rides for two.
const DEVASTATING_STRIKES_SPINS: int = 1
## Rank-2 (2026-09-06 warrior-rank2-content spec §7.1): Devastating Strikes tops the loadout to this
## many reels (the project's hard 5-reel-per-turn ceiling) instead of the plain weapon baseline.
const DEVASTATING_STRIKES_RANK2_REELS: int = 5
const STICKY_WILD_SPINS: int = 2
```

Then replace:

```gdscript
			&"wild":
				# Warrior "Lasting Wild" talent (Task 15): the crit bias lasts 2 spins instead of 1.
				var spins: int = (WILD_SPINS + 1) if combatant.has_ability_talent(&"wild_lasting") else WILD_SPINS
				combatant.fire_sticky_wild(_weapon_reel_count(), spins)        # single spin (Warrior), +1 with Lasting Wild
```

with:

```gdscript
			&"devastating_strikes":
				# Warrior "Lasting Strikes" talent: the crit bias lasts 2 spins instead of 1.
				var spins: int = (DEVASTATING_STRIKES_SPINS + 1) if combatant.has_ability_talent(&"devastating_lasting") else DEVASTATING_STRIKES_SPINS
				var reel_count: int = _weapon_reel_count()
				if combatant.ability_talent_row_rank(&"ultimate") >= 2:
					# Rank-2 (2026-09-06 warrior-rank2-content spec §7.1): tops the loadout up to the
					# project's 5-reel ceiling before marking every reel wild — the "one legendary
					# blow" alpha-strike variant chosen over a "2 spins/4 reels" alternative during
					# brainstorming. Performed here (the caller), NOT inside fire_sticky_wild() itself,
					# so that shared function (also used by the Skirmisher) stays untouched.
					reel_count = DEVASTATING_STRIKES_RANK2_REELS
					while combatant.turn_reels.size() < reel_count:
						combatant.turn_reels.append(ActionReel.make_ability_attack(combatant.weapon_type()))
				combatant.fire_sticky_wild(reel_count, spins)  # single spin baseline (Warrior), +1 with Lasting Strikes
```

Also update the nearby Rampage comment that references the old constant name — replace:

```gdscript
			&"rampage":
				# Vanguard "Lasting Rampage" talent (Task 16): the AoE window lasts 2 spins instead
				# of 1 — same pattern as &"wild"'s wild_lasting just above.
```

with:

```gdscript
			&"rampage":
				# Vanguard "Lasting Rampage" talent (Task 16): the AoE window lasts 2 spins instead
				# of 1 — same pattern as &"devastating_strikes"'s devastating_lasting just above.
```

- [ ] **Step 5: Rank-2 mechanic — crit-bonus damage in combat.gd**

In `combat/combat.gd`'s `_apply_attack()` per-target loop, right after the existing Vicious Return
block (after the `sunder_vicious_return` `if` block's closing, before the "Ranger Weakening Aim
talent" comment/block that follows it), add:

```gdscript
			# Warrior "Devastating Strikes" rank-2 (2026-09-06 warrior-rank2-content spec §7.3): any
			# CRIT landed while its guaranteed-feeling crit-bias window is active deals +20% bonus
			# damage. Gated on the actual result tier (NOT just "while active") since WILD_CRIT_CHANCE
			# is a 65% BIAS, not a guarantee — some wild-marked reels still land as ordinary hits and
			# must not get this bonus.
			if _attacker.class_id == &"warrior" and _attacker.ability_talent_row_rank(&"ultimate") >= 2 and _attacker.sticky_wild_spins_remaining > 0 and attack.face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS and attack.final_damage > 0:
				var devastating_bonus: int = ceili(attack.final_damage * 0.20)
				t.take_damage(devastating_bonus)
				_log("  ⚡ %s's Devastating Strikes adds %d bonus damage." % [_attacker.display_name, devastating_bonus])
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_class_library.gd`
Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ultimate_variants.gd`
Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_warrior.gd`
Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ultimate_sticky_wild.gd`
Expected: all PASS (`test_ultimate_sticky_wild.gd` is unaffected — it exercises the shared
`fire_sticky_wild()` plumbing directly and never references the Warrior-specific ids).

- [ ] **Step 7: Commit**

```bash
git add combat/class_library.gd combat/ability_talent_library.gd combat/combatant.gd combat/combat.gd combat/main_phase_plan.gd combat/ui/ultimate_catalog.gd tests/test_class_library.gd tests/test_ultimate_variants.gd tests/test_ability_talents_warrior.gd
git commit -m "feat(warrior): rename Wild -> Devastating Strikes + rank-2 reel top-up/crit bonus"
```

---

## Task 7: Full-suite regression + stale-reference sweep

**Files:** none modified unless a regression turns up.

- [ ] **Step 1: Grep for any remaining stale Warrior Wild references**

```bash
grep -rn "wild_executioner\|wild_bleeding\|wild_lasting" tests/ combat/ --include=*.gd
grep -rn "&\"wild\"" tests/ combat/ --include=*.gd
```

Expected: zero matches (every reference was either renamed in Task 6 or was already the Skirmisher's
separate `&"sticky_wild"`/generic `fire_sticky_wild()` plumbing, which is untouched by design).

- [ ] **Step 2: Run every Warrior-adjacent test file**

Run each of the following and confirm every one prints its own `PASSED` line (not just exit code 0 —
per CLAUDE.md's silent-script-error-exits-zero gotcha, grep the actual output for `SCRIPT ERROR`/`FAIL`
too, don't trust exit codes alone):

```
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_rend_reel.gd
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_sundering_strike_reel.gd
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_sundering_strike.gd
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_sundering_strike_talents.gd
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_heroic_guard.gd
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_second_wind.gd
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_passive_last_stand.gd
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_warrior.gd
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_class_library.gd
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ultimate_variants.gd
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ultimate_sticky_wild.gd
```

- [ ] **Step 3: If any file fails, fix inline and re-run** (not expected, given each task's own
  passing run above, but this is the integration checkpoint before final review).

- [ ] **Step 4: Invoke `superpowers:requesting-code-review`** for a whole-branch review against
  `docs/superpowers/specs/2026-09-06-warrior-rank2-content-design.md` before considering this plan
  complete — per this codebase's own established convention (see memory
  `final-review-catches-real-bugs-past-task-review`), the per-task reviews above don't replace a
  final whole-branch pass.

---

## Self-Review Notes (author's own pass, not a step to execute)

- **Spec coverage:** all 6 rows (Rend, Sundering Strike, Heroic Guard, Second Wind, Last Stand,
  Devastating Strikes) have a task each; the rename + rank-2 mechanics for the Ultimate are combined
  into Task 6 since they touch the exact same match arms/test functions.
- **Placeholder scan:** no TBD/TODO; every step has concrete code.
- **Type consistency:** `ability_talent_row_rank(row_id) -> int` used consistently; `bonus_meter.add_flat(amount: int)`
  used consistently; `make_rend`/`make_sundering_strike` both take `(type: DamageType, rank2: bool = false)`.
- **Known correction from the design spec:** the spec's Second Wind section describes the HoT as
  `dot_fractions = [0.05, 0.05]` (one entry per turn) — this plan uses `[0.05]` (a single entry)
  instead, since `Effect.dot_damage()` indexes by STACK count, not by turn/duration, and this HoT is
  non-stacking (`max_stacks = 1`, so `stacks` never leaves 1). A single 0.05 entry read every tick for
  `duration` turns produces the exact same 10%/15% totals the spec locked in — this is a pure
  implementation-mechanics fix, not a numbers or behavior change.
