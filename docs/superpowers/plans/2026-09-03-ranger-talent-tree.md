# Ranger Talent Tree Depth Rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rework the Ranger's 6-row talent tree (`combat/ability_talent_library.gd`'s `&"ranger"`
case) into three per-row playstyle columns (Control/Hunter/Marksman), replacing 15 of its 18 flat
options, adding one genuinely new orchestrator mechanic (Marksman's Call, a Ranger bonus reel that
fires off an ally's hit), and bumping 3 unconditional baseline behaviors — without touching
rank-2/stat-scaling (a separate, later, deferred pass).

**Architecture:** No new effect ids. Every new mechanic reuses an existing engine idiom already
shipped elsewhere: the defender-conditional passive check (`passive_outgoing_multiplier(defender)`),
the per-target bonus-hit idiom already used by `bonus_vs_cc`/Twist the Knife/Vicious Return, the
splash helper `_splash_half_to_others()` (already shared by Collateral/Earthquake), and the
commit-time defender-aware finalize block `_commit_main1()` already used by Hunter's Mark/Aimed
Shot. The one wholly new piece is `CombatResolver.resolve_single_reel()` — a public sibling of the
existing `reresolve_reel()` that actually applies a `damage_multiplier` (which `reresolve_reel()`
deliberately hardcodes to 1.0 for its own Chancer reroll/gamble callers) — needed so Marksman's
Call's bonus reel reads the Ranger's own full outgoing/incoming multiplier product.

**Tech Stack:** Godot 4.6 / GDScript, headless test runner (`Godot_v4.6.3-stable_win64_console.exe
--headless --path . --script res://tests/<file>.gd`, run from the repo root one directory below
the executable).

**Spec:** `docs/superpowers/specs/2026-09-03-ranger-talent-tree-design.md`

## Global Constraints

- Every specific percentage/turn-count is an `[ASSUMPTION]` placeholder (CLAUDE.md §4) — implement
  as plain data (local `var`/literals), not something requiring a design review to change later.
- No rank-2/stat-scaling wiring in this plan — that's a separate, later spec (design doc's Open
  Questions).
- No new effect ids — every new check reads existing `&"hunters_mark"`/`&"rooted"`/`&"weakened"`/
  `&"slow"` state via `has_effect()`.
- Round up (ceil) for any new damage math, per project convention (`ceili()`).
- Marksman's Call has NO per-round cap in this plan — build it uncapped, per the spec's explicit
  playtest-tunable note. Do not add a limiter that wasn't asked for.
- Before considering this plan done, grep the whole repo for every retired option id (Task 8 does
  this explicitly) — per the Harvester rank-2 pass's and the Warrior talent pass's own hard-won
  lesson, a stray reference reliably survives in an untouched test file.

---

### Task 1: Hunter's Mark row — widened baseline conversion, Rooting Mark, Marksman's Mark

**Files:**
- Modify: `combat/combatant.gd:2133-2145` (`hunters_mark_reels()`)
- Modify: `combat/combatant.gd:873-882` (`ability_talent_cost_delta()`, ranger `&"hunters_mark"` arm — remove)
- Modify: `combat/combatant.gd:1005-1015` (`apply_rider_talent_adjustments()`, ranger `&"hunters_mark"` case)
- Modify: `combat/combat.gd:2862-2878` (`_apply_attack()` — add Marksman's Mark block after the existing `bonus_vs_cc` block)
- Modify: `combat/ability_talent_library.gd:366-379` (ranger `&"base_ability"` row)
- Test: `tests/test_hunters_mark.gd` (widened-conversion assertions)
- Test: `tests/test_ability_talents_ranger.gd` (`_test_hunters_mark_row()`, `_test_options_for_shape()`'s `all_ids`)

**Interfaces:**
- Produces: `Combatant.hunters_mark_reels(reels: Array) -> Array[ActionReel]` (unchanged signature)
  now also converts up to half (floor) of a weapon-attack reel's FAILURE-tier faces to SUCCESS, on
  top of its existing full CRIT_FAILURE conversion.

- [ ] **Step 1: Write the failing test**

In `tests/test_hunters_mark.gd`, replace lines 50-67 (the "pure reel swap" section) with:

```gdscript
	# --- the pure reel swap: weapon-attack reels lose crit-fails AND half their failures (→ hits);
	#     utility reels untouched ---
	var weapon_a: ActionReel = ActionReel.make_default(piercing)
	var weapon_b: ActionReel = ActionReel.make_default(piercing)
	var rend: ActionReel = ActionReel.make_rend(piercing)  # is_weapon_attack == false
	var before_a_cf: int = _count(weapon_a, ReelFace.ResultTier.CRIT_FAILURE)
	var before_a_fail: int = _count(weapon_a, ReelFace.ResultTier.FAILURE)
	var before_a_succ: int = _count(weapon_a, ReelFace.ResultTier.SUCCESS)
	_check(before_a_cf == 5, "default reel has 5 crit-fail faces before swap (DEFAULT_COMPOSITION, 5x scale, got %d)" % before_a_cf)
	_check(before_a_fail == 10, "default reel has 10 failure faces before swap (DEFAULT_COMPOSITION, 5x scale, got %d)" % before_a_fail)

	var swapped: Array = Combatant.hunters_mark_reels([weapon_a, weapon_b, rend])
	_check(swapped.size() == 3, "swap returns same count")
	_check(_count(swapped[0], ReelFace.ResultTier.CRIT_FAILURE) == 0, "weapon reel 0: no crit-fails after swap")
	_check(_count(swapped[1], ReelFace.ResultTier.CRIT_FAILURE) == 0, "weapon reel 1: no crit-fails after swap")
	_check(_count(swapped[0], ReelFace.ResultTier.FAILURE) == before_a_fail - 5, "weapon reel 0: half of failure faces (5 of 10) also converted (got %d remaining)" % _count(swapped[0], ReelFace.ResultTier.FAILURE))
	_check(_count(swapped[0], ReelFace.ResultTier.SUCCESS) == before_a_succ + before_a_cf + 5, "crit-fail (+5) and half of failure (+5) both became successes (got %d)" % _count(swapped[0], ReelFace.ResultTier.SUCCESS))
	# The utility (Rend) reel passes through untouched — still carries its crit-fail face.
	_check(_count(swapped[2], ReelFace.ResultTier.CRIT_FAILURE) == _count(rend, ReelFace.ResultTier.CRIT_FAILURE), "rend reel untouched")

	# Originals are NOT mutated (deep copy) — weapon_a still has its crit-fail AND failure faces.
	_check(_count(weapon_a, ReelFace.ResultTier.CRIT_FAILURE) == before_a_cf, "original weapon reel unmutated (crit-fail, got %d)" % _count(weapon_a, ReelFace.ResultTier.CRIT_FAILURE))
	_check(_count(weapon_a, ReelFace.ResultTier.FAILURE) == before_a_fail, "original weapon reel unmutated (failure, got %d)" % _count(weapon_a, ReelFace.ResultTier.FAILURE))
```

In `tests/test_ability_talents_ranger.gd`, replace `_test_hunters_mark_row()` (lines 62-89) with:

```gdscript
func _test_hunters_mark_row() -> void:
	var c: Combatant = _mk_ranger()
	_check(c.ability_talent_cost_delta(&"hunters_mark") == 0, "no Hunter's Mark cost delta (mark_efficient retired)")

	var c2: Combatant = _mk_ranger()
	var target: Combatant = _mk_ranger()
	_check(c2.pick_ability_talent(&"base_ability", &"mark_rooting"), "picks mark_rooting")
	var mark: Effect = EffectLibrary.make(&"hunters_mark")
	_check(not target.has_effect(&"rooted"), "sanity: target starts unrooted")
	c2.apply_rider_talent_adjustments(&"hunters_mark", mark, target)
	_check(target.has_effect(&"rooted"), "mark_rooting: the target also gets a stack of Rooted")
	_check(mark.duration == 3, "mark_rooting alone leaves Hunter's Mark's own duration at 3")

	# Marksman's Call/Marksman's Mark: the actual bonus-reel firing and the +20% bonus-vs-Marked
	# damage both live in combat.gd (orchestrator-level — Marksman's Call needs a running Combat
	# scene's _finish_spin/_resolver, Marksman's Mark reads _apply_attack()'s live per-hit state),
	# consistent with this file's own header-comment precedent. This proves the precondition state
	# combat.gd's wiring reads. Marksman's Call's own resolver math is covered in
	# tests/test_marksmans_call.gd (Task 2).
	var c3: Combatant = _mk_ranger()
	_check(c3.pick_ability_talent(&"base_ability", &"mark_marksmans_call"), "picks mark_marksmans_call")
	_check(c3.has_ability_talent(&"mark_marksmans_call"), "has_ability_talent sees mark_marksmans_call")

	var c4: Combatant = _mk_ranger()
	_check(c4.pick_ability_talent(&"base_ability", &"mark_marksman"), "picks mark_marksman")
	_check(c4.has_ability_talent(&"mark_marksman"), "has_ability_talent sees mark_marksman")

	# Mutual exclusion: only 1 pick per row.
	var c5: Combatant = _mk_ranger()
	_check(c5.pick_ability_talent(&"base_ability", &"mark_rooting"), "first pick on the Hunter's Mark row succeeds")
	_check(not c5.pick_ability_talent(&"base_ability", &"mark_marksman"), "a second pick on an already-filled row is rejected (cap of 1/row)")
	_check(c5.has_ability_talent(&"mark_rooting"), "the row's original pick is still active")
```

In `_test_options_for_shape()`'s `all_ids` array (line 44), replace
`&"mark_deeper", &"mark_weakening", &"mark_efficient",` with
`&"mark_rooting", &"mark_marksmans_call", &"mark_marksman",`.

- [ ] **Step 2: Run tests to verify they fail**

Run:
```
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_hunters_mark.gd
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_ranger.gd
```
Expected: FAIL — the failure-face count is still 10 (not 5) after swap; `mark_rooting`/
`mark_marksmans_call`/`mark_marksman` aren't recognized options yet.

- [ ] **Step 3: Write minimal implementation**

In `combat/combatant.gd`, replace `hunters_mark_reels()`:

```gdscript
static func hunters_mark_reels(reels: Array) -> Array[ActionReel]:
	var out: Array[ActionReel] = []
	for r: ActionReel in reels:
		if r != null and r.is_weapon_attack:
			var copy: ActionReel = r.duplicate(true)  # deep: its own faces
			var failure_count: int = 0
			for f: ReelFace in copy.faces:
				if f.result_tier == ReelFace.ResultTier.FAILURE:
					failure_count += 1
			var failures_to_convert: int = failure_count / 2  # floor, per the widened-accuracy baseline
			var failures_converted: int = 0
			for f: ReelFace in copy.faces:
				if f.result_tier == ReelFace.ResultTier.CRIT_FAILURE:
					f.result_tier = ReelFace.ResultTier.SUCCESS
					f.multiplier = 1.0
				elif f.result_tier == ReelFace.ResultTier.FAILURE and failures_converted < failures_to_convert:
					f.result_tier = ReelFace.ResultTier.SUCCESS
					f.multiplier = 1.0
					failures_converted += 1
			out.append(copy)
		else:
			out.append(r)
	return out
```

In `ability_talent_cost_delta()`'s `&"ranger":` match, delete the `&"hunters_mark":` arm entirely
(falls through to the ranger match's `_: return 0`):

```gdscript
		&"ranger":
			match ability_id:
				&"aimed_shot":
					return -1 if has_ability_talent(&"aim_efficient") else 0
				&"snare_trap":
					return -1 if has_ability_talent(&"snare_efficient") else 0
				_:
					return 0
```

(Leave `aimed_shot`/`snare_trap`'s arms untouched here — those are retired in Tasks 3/4 respectively.)

In `apply_rider_talent_adjustments()`'s `&"ranger":` match, replace the `&"hunters_mark":` case:

```gdscript
				&"hunters_mark":
					if has_ability_talent(&"mark_rooting"):
						target.attach_effect(EffectLibrary.make(&"rooted"))
```

In `combat/combat.gd`'s `_apply_attack()`, immediately after the existing `bonus_vs_cc` block (right
after its closing `_log(...)` line, still inside the `for t: Combatant in targets:` loop), add:

```gdscript
			# Ranger "Marksman's Mark" talent (2026-09-03 ranger-talent-tree spec §3.3): the
			# Ranger's OWN hits against a Marked target deal additional bonus damage. This is
			# _attacker's own turn here — Marksman's Call's separately-resolved bonus reel never
			# re-enters this function, so no double-count risk.
			if _attacker.class_id == &"ranger" and _attacker.has_ability_talent(&"mark_marksman") and t.has_effect(&"hunters_mark") and attack.final_damage > 0:
				var marksman_bonus: int = ceili(attack.final_damage * 0.20)
				t.take_damage(marksman_bonus)
				_log("  🎯 %s's Marksman's Mark adds %d bonus damage." % [_attacker.display_name, marksman_bonus])
```

In `combat/ability_talent_library.gd`'s ranger `&"base_ability"` row, replace the whole case:

```gdscript
				&"base_ability":
					var m1: AbilityTalentOption = AbilityTalentOption.new()
					m1.id = &"mark_rooting"; m1.row_id = row_id
					m1.display_name = "Rooting Mark"
					m1.description = "Hunter's Mark also applies a stack of Rooted to the target."
					var m2: AbilityTalentOption = AbilityTalentOption.new()
					m2.id = &"mark_marksmans_call"; m2.row_id = row_id
					m2.display_name = "Marksman's Call"
					m2.description = "Once per ally per round, when an ally attacks your Marked target, you fire an independent bonus shot at it."
					var m3: AbilityTalentOption = AbilityTalentOption.new()
					m3.id = &"mark_marksman"; m3.row_id = row_id
					m3.display_name = "Marksman's Mark"
					m3.description = "Your own hits against a Marked target deal +20% bonus damage."
					return [m1, m2, m3]
```

- [ ] **Step 4: Run tests to verify they pass**

Run both files again as in Step 2. Expected: all `ok` lines, no `FAIL`.

- [ ] **Step 5: Grep for the three retired ids project-wide**

Run: `grep -rn "mark_deeper\|mark_weakening\|mark_efficient" --include=*.gd .` — fix any hit besides
the two files already touched in this task.

- [ ] **Step 6: Commit**

```bash
git add combat/combatant.gd combat/combat.gd combat/ability_talent_library.gd tests/test_hunters_mark.gd tests/test_ability_talents_ranger.gd
git commit -m "feat(ranger): Hunter's Mark row — widen accuracy conversion, Rooting Mark, Marksman's Mark"
```

---

### Task 2: Marksman's Call — new resolver method + orchestrator wiring

**Files:**
- Modify: `combat/combat_resolver.gd:142-143` (add `resolve_single_reel()` right after `reresolve_reel()`)
- Modify: `combat/combat.gd` (new `_fire_marksmans_call()` helper + a hook in `_finish_spin()`)
- Test: `tests/test_marksmans_call.gd` (new file)

**Interfaces:**
- Produces: `CombatResolver.resolve_single_reel(reel: ActionReel, base_damage: float, target_type:
  DamageType, flat_damage_bonus: int = 0, damage_multiplier: float = 1.0) -> AttackResult` — a
  public sibling of `reresolve_reel()` that actually applies `damage_multiplier` instead of
  hardcoding it to 1.0.
- Consumes: `Combatant.outgoing_damage_multiplier(defender)`, `Combatant.
  incoming_damage_multiplier()`, `Combatant.weapon_type()`, `Combatant.weapon_effective_base_damage()`,
  `Combatant.might_damage_bonus_per_reel(count)` (all existing, unchanged signatures).

- [ ] **Step 1: Write the failing test**

Create `tests/test_marksmans_call.gd`:

```gdscript
extends SceneTree

# Headless test: CombatResolver.resolve_single_reel() (2026-09-03 ranger-talent-tree spec §3.2,
# "Marksman's Call") — the one new resolver method this feature needs: a single-reel resolve that,
# unlike reresolve_reel() (which hardcodes damage_multiplier = 1.0 for the Chancer reroll/gamble
# paths, which apply their own separate multiplier afterward), actually applies the given
# damage_multiplier — Marksman's Call needs the Ranger's own full outgoing/incoming multiplier
# product baked in, exactly like a normal weapon-attack reel. The full orchestrator wiring (firing
# once per ally-turn via _finish_spin's hook, _fire_marksmans_call's own damage/log/meter-charge
# application) is orchestrator-level (combat.gd) and requires a running Combat scene — NOT
# headlessly tested here, consistent with this codebase's own documented precedent
# (tests/test_ability_talents_ranger.gd's header comment).
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_marksmans_call.gd

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _make_single_face_reel(type: DamageType, tier: ReelFace.ResultTier, multiplier: float) -> ActionReel:
	var reel: ActionReel = ActionReel.new()
	reel.damage_type = type
	var face: ReelFace = ReelFace.new()
	face.result_tier = tier
	face.multiplier = multiplier
	reel.faces = [face]
	return reel

func _init() -> void:
	var piercing: DamageType = load("res://combat/resources/types/piercing.tres")
	var resolver: CombatResolver = CombatResolver.new()

	# A single guaranteed-SUCCESS-face reel makes the "spin" fully deterministic, isolating the
	# math this test actually cares about (damage_multiplier's application).
	var reel: ActionReel = _make_single_face_reel(piercing, ReelFace.ResultTier.SUCCESS, 1.0)
	var attack: CombatResolver.AttackResult = resolver.resolve_single_reel(reel, 10.0, piercing, 2, 1.5)
	# base 10.0 * multiplier 1.0 * type_mult 1.0 (piercing vs piercing = neutral default) = 10.0,
	# then * damage_multiplier 1.5 = 15.0, ceil'd, + flat_damage_bonus 2 = 17.
	_check(attack.final_damage == 17, "resolve_single_reel applies damage_multiplier (got %d, want 17)" % attack.final_damage)
	_check(attack.face.result_tier == ReelFace.ResultTier.SUCCESS, "sanity: the single face always lands")

	# damage_multiplier == 1.0 (the neutral default) matches reresolve_reel()'s own existing shape.
	var reel2: ActionReel = _make_single_face_reel(piercing, ReelFace.ResultTier.SUCCESS, 1.0)
	var attack2: CombatResolver.AttackResult = resolver.resolve_single_reel(reel2, 10.0, piercing, 0, 1.0)
	var attack3: CombatResolver.AttackResult = resolver.reresolve_reel(reel2, 10.0, piercing, 0)
	_check(attack2.final_damage == attack3.final_damage, "resolve_single_reel(damage_multiplier=1.0) matches reresolve_reel's own math (got %d vs %d)" % [attack2.final_damage, attack3.final_damage])

	# A miss face (FAILURE) deals no damage regardless of damage_multiplier/flat_damage_bonus.
	var reel4: ActionReel = _make_single_face_reel(piercing, ReelFace.ResultTier.FAILURE, 0.0)
	var attack4: CombatResolver.AttackResult = resolver.resolve_single_reel(reel4, 10.0, piercing, 5, 2.0)
	_check(attack4.final_damage == 0, "a FAILURE face deals no damage even with flat_damage_bonus/damage_multiplier set")

	# Ranger precondition: mark_marksmans_call is a real, pickable talent on the Hunter's Mark row.
	var ranger: Combatant = ClassLibrary.make(&"ranger").build_combatant(true)
	ranger.level = Combatant.MAX_LEVEL
	_check(ranger.pick_ability_talent(&"base_ability", &"mark_marksmans_call"), "picks mark_marksmans_call")
	_check(ranger.has_ability_talent(&"mark_marksmans_call"), "has_ability_talent sees mark_marksmans_call")

	print(("MARKSMAN'S CALL TEST PASSED" if _failures == 0 else "MARKSMAN'S CALL TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_marksmans_call.gd`
Expected: FAIL — `resolve_single_reel` is not a recognized method on `CombatResolver` yet.

- [ ] **Step 3: Write minimal implementation**

In `combat/combat_resolver.gd`, right after `reresolve_reel()` (line 143), add:

```gdscript
	## Resolves ONE reel into a fresh AttackResult with a normal (non-wild) weighted spin AND the
	## given [param damage_multiplier] applied (unlike [method reresolve_reel], which hardcodes 1.0
	## for the Chancer reroll/gamble paths, which apply their own separate multiplier afterward).
	## Used by Ranger "Marksman's Call" (2026-09-03 ranger-talent-tree spec §3.2), which needs the
	## Ranger's own full outgoing/incoming multiplier product baked in, exactly like a normal
	## weapon-attack reel.
	func resolve_single_reel(reel: ActionReel, base_damage: float, target_type: DamageType, flat_damage_bonus: int = 0, damage_multiplier: float = 1.0) -> AttackResult:
		return _resolve_single(reel, base_damage, target_type, false, flat_damage_bonus, damage_multiplier)
```

In `combat/combat.gd`, add a new helper (place it near `_splash_half_to_others()`, since both are
per-turn orchestrator helpers called from `_finish_spin()`):

```gdscript
## Ranger "Marksman's Call" talent (2026-09-03 ranger-talent-tree spec §3.2): resolves one
## independent bonus weapon-attack reel with [param ranger] as the effective attacker (their own
## outgoing multipliers/passive/talents apply, exactly like one of the Ranger's own action reels),
## damaging [param target]. NOT spliced into anyone's turn_reels — a same-moment follow-up shot,
## resolved and applied immediately, with no strip animation (no running spin to attach one to).
func _fire_marksmans_call(ranger: Combatant, target: Combatant) -> void:
	var reel: ActionReel = ActionReel.make_ability_attack(ranger.weapon_type())
	var dmg_mult: float = ranger.outgoing_damage_multiplier(target) * target.incoming_damage_multiplier()
	var attack: CombatResolver.AttackResult = _resolver.resolve_single_reel(reel, ranger.weapon_effective_base_damage(), target.defense_type, ranger.might_damage_bonus_per_reel(1), dmg_mult)
	if attack.final_damage > 0:
		target.take_damage(attack.final_damage)
		var mult: float = reel.damage_type.multiplier_against(target.defense_type) if reel.damage_type != null else 1.0
		_log("  🏹 %s's MARKSMAN'S CALL adds a bow shot on %s for %d damage.  %s" % [ranger.display_name, target.display_name, attack.final_damage, TypeVisuals.effectiveness_tag(mult)])
	if ranger.bonus_meter != null and attack.charges_meter:
		ranger.bonus_meter.charge(attack.face.result_tier)
	if _panels.has(target):
		(_panels[target] as CombatantPanel).refresh_status()
```

In `combat/combat.gd`'s `_finish_spin()`, at the very top of the function (before the Collateral
Damage check), add:

```gdscript
func _finish_spin() -> void:
	# Ranger "Marksman's Call" talent (2026-09-03 ranger-talent-tree spec §3.2): this runs once per
	# spin/turn (not per reel), which naturally satisfies "once per ally-turn" with no extra
	# bookkeeping. If this turn's attacker is an ALLY of a Marksman's-Call Ranger (not the Ranger's
	# own turn) and the defender is still alive and Hunter's-Marked, the Ranger fires one
	# independent bonus reel at the same target.
	if _defender != null and _defender.is_alive() and _defender.has_effect(&"hunters_mark"):
		for ally: Combatant in _allies_of(_attacker):
			if ally != _attacker and ally.class_id == &"ranger" and ally.is_alive() and ally.has_ability_talent(&"mark_marksmans_call"):
				_fire_marksmans_call(ally, _defender)
	# Collateral Damage (Ranger Ultimate): ...
```

(Keep every existing line of `_finish_spin()` after this point unchanged — only the new block above
is inserted, before the pre-existing Collateral Damage comment/check.)

- [ ] **Step 4: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_marksmans_call.gd`
Expected: all `ok` lines, no `FAIL`.

- [ ] **Step 5: Commit**

```bash
git add combat/combat_resolver.gd combat/combat.gd tests/test_marksmans_call.gd
git commit -m "feat(ranger): Marksman's Call — independent bonus reel on an ally's hit vs a Marked target"
```

---

### Task 3: Aimed Shot row — Rooting Aim, Weakening Aim (renamed), Practiced Aim

**Files:**
- Modify: `combat/combatant.gd:323-332` (add `aimed_shot_root_pending` field, alongside `aimed_shot_hit_pending`)
- Modify: `combat/combatant.gd:873-882` (`ability_talent_cost_delta()`, ranger `&"aimed_shot"` arm — remove)
- Modify: `combat/combat.gd:2521-2538` (Aimed Shot's commit-time resolution in `_commit_main1()`)
- Modify: `combat/combat.gd:2912-2922` (`_apply_attack()`'s `aimed_shot_hit_pending`/Weakening Aim block — add a matching Rooting Aim block right after it)
- Modify: `combat/ability_talent_library.gd:380-393` (ranger `&"ability_l2"` row)
- Test: `tests/test_ability_talents_ranger.gd` (`_test_aimed_shot_row()`, `_test_options_for_shape()`'s `all_ids`)

**Interfaces:**
- Produces: `Combatant.aimed_shot_root_pending: bool` (new field, mirrors `aimed_shot_hit_pending`'s
  exact shape — set at commit time, consumed the first time a reel connects this same spin).

- [ ] **Step 1: Write the failing test**

Replace `_test_aimed_shot_row()` in `tests/test_ability_talents_ranger.gd` (lines 91-118) with:

```gdscript
func _test_aimed_shot_row() -> void:
	var c: Combatant = _mk_ranger()
	_check(c.ability_talent_cost_delta(&"aimed_shot") == 0, "no Aimed Shot cost delta (aim_efficient retired)")
	_check(c.pick_ability_talent(&"ability_l2", &"aim_rooting"), "picks aim_rooting")
	_check(not c.aimed_shot_root_pending, "sanity: aimed_shot_root_pending starts false")
	_check(c.stage_aimed_shot(3), "stages Aimed Shot (rooting)")
	_check(c.aimed_shot_pending, "Aimed Shot is pending for combat.gd's commit-time wiring (which sets aimed_shot_root_pending) to read")

	var c2: Combatant = _mk_ranger()
	_check(c2.pick_ability_talent(&"ability_l2", &"aim_weakening"), "picks aim_weakening")
	_check(not c2.aimed_shot_hit_pending, "sanity: aimed_shot_hit_pending starts false")
	_check(c2.stage_aimed_shot(3), "stages Aimed Shot (weakening)")
	_check(c2.aimed_shot_pending, "Aimed Shot is pending for combat.gd's commit-time wiring (which sets aimed_shot_hit_pending) to read")

	# Practiced Aim's actual Empowered-duration extension (2 turns instead of 1, when the target is
	# already Marked) lives in combat.gd's own commit-time resolution — orchestrator-level (Aimed
	# Shot's whole magnitude/duration computation already lived there before this task, sized by the
	# defender's Mark status) — NOT headlessly tested here (see this file's header comment).
	var c3: Combatant = _mk_ranger()
	_check(c3.pick_ability_talent(&"ability_l2", &"aim_practiced"), "picks aim_practiced")
	_check(c3.has_ability_talent(&"aim_practiced"), "has_ability_talent sees aim_practiced")
	_check(c3.stage_aimed_shot(3), "stages Aimed Shot (practiced)")
	_check(c3.aimed_shot_pending, "Aimed Shot is pending for combat.gd's commit-time wiring to read")

	# Mutual exclusion: only 1 pick per row.
	var c4: Combatant = _mk_ranger()
	_check(c4.pick_ability_talent(&"ability_l2", &"aim_rooting"), "first pick on the Aimed Shot row succeeds")
	_check(not c4.pick_ability_talent(&"ability_l2", &"aim_weakening"), "a second pick on an already-filled row is rejected (cap of 1/row)")
```

In `_test_options_for_shape()`'s `all_ids` array (line 45), replace
`&"aim_deeper", &"aim_piercing", &"aim_efficient",` with
`&"aim_rooting", &"aim_weakening", &"aim_practiced",`.

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_ranger.gd`
Expected: FAIL — `aim_rooting`/`aim_weakening`/`aim_practiced` aren't recognized options yet;
`aimed_shot_root_pending` doesn't exist yet.

- [ ] **Step 3: Write minimal implementation**

In `combat/combatant.gd`, right after `aimed_shot_hit_pending`'s declaration (line 332), add:

```gdscript
## Ranger "Rooting Aim" talent (2026-09-03 ranger-talent-tree spec §4.1) pending flag: mirrors
## aimed_shot_hit_pending's exact shape (set alongside aimed_shot_pending's own commit-time attach,
## consumed the first time a reel actually connects this same spin in combat.gd's _apply_attack()).
## Kept as a SEPARATE flag (rather than reusing aimed_shot_hit_pending for a different rider) so
## Rooting Aim's and Weakening Aim's own consume-on-hit logic can never cross-fire — only one of
## the two can ever be picked on this row, but keeping them as two distinct fields makes that true
## by construction, not by convention.
var aimed_shot_root_pending: bool = false
```

In `ability_talent_cost_delta()`'s `&"ranger":` match, delete the `&"aimed_shot":` arm (leaves only
the `&"snare_trap":` arm from Task 1, falling through to `_: return 0` for everything else):

```gdscript
		&"ranger":
			match ability_id:
				&"snare_trap":
					return -1 if has_ability_talent(&"snare_efficient") else 0
				_:
					return 0
```

In `combat/combat.gd`'s `_commit_main1()`, replace the `if _attacker.aimed_shot_pending:` block:

```gdscript
	if _attacker.aimed_shot_pending:
		var target_marked: bool = _defender.has_effect(&"hunters_mark")
		var e: Effect = EffectLibrary.make(&"empowered")
		e.magnitude = 1.6 if target_marked else 1.3
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

In `combat/combat.gd`'s `_apply_attack()`, right after the existing `aimed_shot_hit_pending` block
(the "Piercing Aim"/Weakening Aim block ending at its `refresh_status()` call, ~line 2922), add:

```gdscript
			# Ranger "Rooting Aim" talent (2026-09-03 ranger-talent-tree spec §4.1): mirrors the
			# Weakening Aim block immediately above exactly, but attaches Rooted instead.
			if _attacker.aimed_shot_root_pending and attack.final_damage > 0:
				var piercing_root: Effect = EffectLibrary.make(&"rooted")
				t.attach_effect(piercing_root)
				_attacker.aimed_shot_root_pending = false
				_log("  🏹 Rooting Aim: %s is ROOTED." % t.display_name)
				if _panels.has(t):
					(_panels[t] as CombatantPanel).refresh_status()
```

In `combat/ability_talent_library.gd`'s ranger `&"ability_l2"` row, replace the whole case:

```gdscript
				&"ability_l2":
					var a1: AbilityTalentOption = AbilityTalentOption.new()
					a1.id = &"aim_rooting"; a1.row_id = row_id
					a1.display_name = "Rooting Aim"
					a1.description = "Aimed Shot's own hit also applies a stack of Rooted."
					var a2: AbilityTalentOption = AbilityTalentOption.new()
					a2.id = &"aim_weakening"; a2.row_id = row_id
					a2.display_name = "Weakening Aim"
					a2.description = "Aimed Shot's own hit also applies a stack of Weakened."
					var a3: AbilityTalentOption = AbilityTalentOption.new()
					a3.id = &"aim_practiced"; a3.row_id = row_id
					a3.display_name = "Practiced Aim"
					a3.description = "If the target is already Marked, Aimed Shot's Empowered buff lasts 2 turns instead of 1."
					return [a1, a2, a3]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_ranger.gd`
Expected: all `ok` lines, no `FAIL`.

- [ ] **Step 5: Grep for the two retired ids project-wide**

Run: `grep -rn "aim_deeper\|aim_piercing\|aim_efficient" --include=*.gd .` — fix any hit besides the
files already touched in this task (`aim_piercing` is a renamed-not-deleted id, so this grep should
still show zero LIVE hits once the rename above lands).

- [ ] **Step 6: Commit**

```bash
git add combat/combatant.gd combat/combat.gd combat/ability_talent_library.gd tests/test_ability_talents_ranger.gd
git commit -m "feat(ranger): Aimed Shot row — Rooting Aim, rename Piercing Aim to Weakening Aim, Practiced Aim"
```

---

### Task 4: Snare Trap row — baseline AoE splash+Rooted, Wider Snare, Marking Snare, Focused Trap

**Files:**
- Modify: `combat/combatant.gd:1005-1021` (`apply_rider_talent_adjustments()`, ranger `&"rooted"` case — remove)
- Modify: `combat/combatant.gd:1057-1078` (`rider_talent_bonus_damage_pct()`, ranger `&"ranger"` case — remove)
- Modify: `combat/combat.gd:3001-3021` (`_apply_attack()` — add the Snare Trap splash+Marking Snare block right after the generic rider-attach loop)
- Modify: `combat/combat.gd:2473-2499` (`_commit_main1()` — add the Focused Trap face-upgrade block)
- Modify: `combat/ability_talent_library.gd:394-407` (ranger `&"ability_l3"` row)
- Test: `tests/test_ability_talents_ranger.gd` (`_test_snare_trap_row()`, `_test_options_for_shape()`'s `all_ids`)

**Interfaces:**
- Consumes: `Combatant._find_effect(id: StringName) -> Effect` (existing, already used by other
  talent tests, e.g. `tests/test_ability_talents_warrior.gd`).
- Consumes: `Combat._splash_half_to_others(attacker, total, type_label, fraction: float = 0.5) ->
  Array[Combatant]` (existing signature, unchanged).

- [ ] **Step 1: Write the failing test**

Replace `_test_snare_trap_row()` in `tests/test_ability_talents_ranger.gd` (lines 120-139) with:

```gdscript
func _test_snare_trap_row() -> void:
	var c: Combatant = _mk_ranger()
	_check(c.pick_ability_talent(&"ability_l3", &"snare_wider"), "picks snare_wider")
	_check(c.has_ability_talent(&"snare_wider"), "has_ability_talent sees snare_wider")

	var c2: Combatant = _mk_ranger()
	_check(c2.pick_ability_talent(&"ability_l3", &"snare_marking"), "picks snare_marking")
	_check(c2.has_ability_talent(&"snare_marking"), "has_ability_talent sees snare_marking")

	var c3: Combatant = _mk_ranger()
	_check(c3.pick_ability_talent(&"ability_l3", &"snare_focused"), "picks snare_focused")
	_check(c3.has_ability_talent(&"snare_focused"), "has_ability_talent sees snare_focused")

	# Baseline AoE splash math (proof of the formula, mirroring tests/test_collateral.gd's own
	# convention of replicating the orchestrator's formula directly — _splash_half_to_others() is a
	# private Combat-scene method with no live scene here). Snare Trap's own primary hit + the
	# actual splash/Rooted-attach/Marking-Snare loop are all orchestrator-level (combat.gd's
	# _apply_attack()), NOT headlessly tested here (see this file's header comment).
	_check(ceili(20 * 0.5) == 10, "sanity: baseline (1/2) splash of 20 is 10")
	var other_a: Combatant = _mk_ranger()
	var other_b: Combatant = _mk_ranger()
	var splashed: Array[Combatant] = [other_a, other_b]
	_check(not other_a.has_effect(&"rooted") and not other_b.has_effect(&"rooted"), "sanity: neither splashed enemy starts Rooted")
	var wide_duration: int = 2 if c.has_ability_talent(&"snare_wider") else 1
	for other: Combatant in splashed:
		var splash_rooted: Effect = EffectLibrary.make(&"rooted")
		splash_rooted.duration = wide_duration
		other.attach_effect(splash_rooted)
	_check(other_a.has_effect(&"rooted") and other_b.has_effect(&"rooted"), "every splashed enemy is also Rooted")
	_check(other_a._find_effect(&"rooted").duration == 2, "snare_wider: splash Rooted matches the primary's full 2-turn duration (got %d)" % other_a._find_effect(&"rooted").duration)

	var c4: Combatant = _mk_ranger()
	_check(c4.try_snare_trap(c4.weapon_type(), 4, 6), "casts Snare Trap (sanity: unaffected structurally by talents)")

	# Mutual exclusion: only 1 pick per row.
	var c5: Combatant = _mk_ranger()
	_check(c5.pick_ability_talent(&"ability_l3", &"snare_wider"), "first pick on the Snare Trap row succeeds")
	_check(not c5.pick_ability_talent(&"ability_l3", &"snare_marking"), "a second pick on an already-filled row is rejected (cap of 1/row)")
```

In `_test_options_for_shape()`'s `all_ids` array (line 46), replace
`&"snare_deeper", &"snare_lasting", &"snare_efficient",` with
`&"snare_wider", &"snare_marking", &"snare_focused",`.

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_ranger.gd`
Expected: FAIL — `snare_wider`/`snare_marking`/`snare_focused` aren't recognized options yet.

- [ ] **Step 3: Write minimal implementation**

In `combat/combatant.gd`'s `apply_rider_talent_adjustments()`, ranger `&"rooted":` case: delete it
entirely (no ranger talent adjusts the generic rooted-rider-attach anymore — Wider Snare's own
duration bump is bespoke to the SPLASH targets, handled directly in combat.gd, not through this
generic per-rider hook). The ranger match becomes:

```gdscript
			&"ranger":
				match rider_id:
					&"hunters_mark":
						if has_ability_talent(&"mark_rooting"):
							target.attach_effect(EffectLibrary.make(&"rooted"))
					&"weakened":
						if has_ability_talent(&"crippling_lasting"):
							effect.duration = 3
```

In `rider_talent_bonus_damage_pct()`, delete the ranger `&"ranger":` case entirely (no ranger talent
uses this hook anymore — Focused Trap upgrades faces at cast time instead of adding a bonus hit).
The function's `match class_id:` loses that whole case, falling through to `_: return 0.0` for
Ranger.

In `combat/combat.gd`'s `_apply_attack()`, right after the generic rider-attach loop (immediately
after its closing `_turn_order_bar.set_order(...)` line, before the Chancer "Double or Nothing"
block), add:

```gdscript
	# Ranger "Snare Trap" additions (2026-09-03 ranger-talent-tree spec §2.2/§5): identified by
	# class_id + the rooted rider — Crippling Shot's own reel carries &"weakened", never &"rooted",
	# so no cross-ability collision within Ranger's kit; Warden's Entangle also carries &"rooted"
	# but is a different class_id.
	if _attacker.class_id == &"ranger" and attack.rider_effect_id == &"rooted" and attack.final_damage > 0:
		for t: Combatant in targets:
			# Hunter "Marking Snare" talent (§5.2): auto-applies Hunter's Mark to the PRIMARY
			# target only (does not apply to splash targets below).
			if _attacker.has_ability_talent(&"snare_marking"):
				t.attach_effect(EffectLibrary.make(&"hunters_mark"))
				_log("  ⊕ Marking Snare: %s is also MARKED." % t.display_name)
				if _panels.has(t):
					(_panels[t] as CombatantPanel).refresh_status()
		# Baseline AoE splash (§2.2): half damage + a shorter Rooted to every OTHER enemy.
		var splashed: Array[Combatant] = _splash_half_to_others(_attacker, attack.final_damage, _type_name(attack.damage_type), 0.5)
		# Control "Wider Snare" talent (§5.1): splash Rooted matches the primary's full 2-turn
		# duration instead of the shorter 1-turn splash duration.
		var splash_rooted_duration: int = 2 if _attacker.has_ability_talent(&"snare_wider") else 1
		for other: Combatant in splashed:
			if other.is_alive():
				var splash_rooted: Effect = EffectLibrary.make(&"rooted")
				splash_rooted.duration = splash_rooted_duration
				other.attach_effect(splash_rooted)
				_log("  🪤 Snare Trap's splash ROOTS %s (%d turns)." % [other.display_name, splash_rooted.duration])
				if _panels.has(other):
					(_panels[other] as CombatantPanel).refresh_status()
```

In `combat/combat.gd`'s `_commit_main1()`, right after the `if did_extra != &"":` log line (before
the `if did_ultimate:` block), add:

```gdscript
	# Ranger "Focused Trap" talent (2026-09-03 ranger-talent-tree spec §5.3): if Snare Trap was just
	# staged this commit and the target is already Marked, its reel's SUCCESS faces are upgraded to
	# guaranteed CRIT_SUCCESS (a miss can still happen; a HIT is now always a crit).
	if did_extra == &"snare_trap" and _attacker.has_ability_talent(&"snare_focused") and _defender.has_effect(&"hunters_mark"):
		var snare_reel: ActionReel = _attacker.turn_reels[_attacker.turn_reels.size() - 1]
		for f: ReelFace in snare_reel.faces:
			if f.result_tier == ReelFace.ResultTier.SUCCESS:
				f.result_tier = ReelFace.ResultTier.CRIT_SUCCESS
				f.multiplier = 2.0
```

In `combat/ability_talent_library.gd`'s ranger `&"ability_l3"` row, replace the whole case:

```gdscript
				&"ability_l3":
					var s1: AbilityTalentOption = AbilityTalentOption.new()
					s1.id = &"snare_wider"; s1.row_id = row_id
					s1.display_name = "Wider Snare"
					s1.description = "Snare Trap's splash Rooted lasts as long as the primary target's (2 turns, was 1)."
					var s2: AbilityTalentOption = AbilityTalentOption.new()
					s2.id = &"snare_marking"; s2.row_id = row_id
					s2.display_name = "Marking Snare"
					s2.description = "Snare Trap automatically applies Hunter's Mark to its target on a hit."
					var s3: AbilityTalentOption = AbilityTalentOption.new()
					s3.id = &"snare_focused"; s3.row_id = row_id
					s3.display_name = "Focused Trap"
					s3.description = "If the target is already Marked, Snare Trap's hits are guaranteed critical."
					return [s1, s2, s3]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_ranger.gd`
Expected: all `ok` lines, no `FAIL`.

- [ ] **Step 5: Grep for the three retired ids project-wide**

Run: `grep -rn "snare_deeper\|snare_lasting\|snare_efficient" --include=*.gd .` — fix any hit besides
the files already touched in this task.

- [ ] **Step 6: Commit**

```bash
git add combat/combatant.gd combat/combat.gd combat/ability_talent_library.gd tests/test_ability_talents_ranger.gd
git commit -m "feat(ranger): Snare Trap row — baseline AoE splash+Rooted, Wider Snare, Marking Snare, Focused Trap"
```

---

### Task 5: Crippling Shot row — Marked for the Kill

**Files:**
- Modify: `combat/combat.gd:2862-2878` (`_apply_attack()`'s `bonus_vs_cc` block)
- Modify: `combat/ability_talent_library.gd:408-421` (ranger `&"ability_l4"` row — only the
  `crippling_deeper` slot changes; `crippling_swift`/`crippling_lasting` keep byte-identical content)
- Test: `tests/test_ability_talents_ranger.gd` (`_test_crippling_shot_row()`, `_test_options_for_shape()`'s `all_ids`)

**Interfaces:** none new — reuses `attack.source_reel.bonus_vs_cc`/`t.has_effect()` exactly as today.

- [ ] **Step 1: Write the failing test**

In `tests/test_ability_talents_ranger.gd`'s `_test_crippling_shot_row()` (lines 141-161), replace
the `crippling_deeper` sub-test (lines 154-161) with:

```gdscript
	# Marked for the Kill's actual ADDITIONAL +25%-if-also-Marked bonus lives in combat.gd's
	# _apply_attack() — it stacks on top of the EXISTING bonus_vs_cc inline calculation, not a new
	# separate hit, so it's checked directly there rather than through a generic hook (see this
	# task's Implementation notes). Orchestrator-level, NOT headlessly tested here.
	var c3: Combatant = _mk_ranger()
	_check(c3.pick_ability_talent(&"ability_l4", &"crippling_marked"), "picks crippling_marked")
	_check(c3.has_ability_talent(&"crippling_marked"), "has_ability_talent sees crippling_marked")
	_check(c3.try_crippling_shot(c3.weapon_type(), 5, 6), "casts Crippling Shot (sanity: unaffected structurally by talents)")
```

In `_test_options_for_shape()`'s `all_ids` array (line 47), replace
`&"crippling_deeper", &"crippling_lasting", &"crippling_swift",` with
`&"crippling_swift", &"crippling_lasting", &"crippling_marked",`.

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_ranger.gd`
Expected: FAIL — `crippling_marked` is not a recognized option yet.

- [ ] **Step 3: Write minimal implementation**

In `combat/combat.gd`'s `_apply_attack()`, replace the `bonus_vs_cc` block:

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
					# Ranger "Marked for the Kill" talent (2026-09-03 ranger-talent-tree spec §6.3):
					# an ADDITIONAL bonus if the target is ALSO Marked at the same moment — stacks
					# with, does not replace, the CC-exploit bonus above.
					if _attacker.has_ability_talent(&"crippling_marked") and t.has_effect(&"hunters_mark"):
						var marked_bonus: int = ceili(attack.final_damage * 0.25)
						t.take_damage(marked_bonus)
						_log("  🎯 Marked for the Kill adds %d more bonus damage." % marked_bonus)
```

In `combat/ability_talent_library.gd`'s ranger `&"ability_l4"` row, replace the `c1`
(`crippling_deeper`) option only — `c2`/`c3` stay byte-identical:

```gdscript
				&"ability_l4":
					var c1: AbilityTalentOption = AbilityTalentOption.new()
					c1.id = &"crippling_marked"; c1.row_id = row_id
					c1.display_name = "Marked for the Kill"
					c1.description = "Crippling Shot's CC-exploit bonus gets an additional +25% if the target is also Marked."
					var c2: AbilityTalentOption = AbilityTalentOption.new()
					c2.id = &"crippling_lasting"; c2.row_id = row_id
					c2.display_name = "Lasting Crippling"
					c2.description = "Weakened (from this ability) lasts 3 turns (was 2)."
					var c3: AbilityTalentOption = AbilityTalentOption.new()
					c3.id = &"crippling_swift"; c3.row_id = row_id
					c3.display_name = "Swift Crippling"
					c3.description = "Crippling Shot's cooldown is reduced to 2 turns (was 3)."
					return [c1, c2, c3]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_ranger.gd`
Expected: all `ok` lines, no `FAIL`.

- [ ] **Step 5: Grep for the retired `crippling_deeper` id project-wide**

Run: `grep -rn "crippling_deeper" --include=*.gd .` — should now show zero hits.

- [ ] **Step 6: Commit**

```bash
git add combat/combat.gd combat/ability_talent_library.gd tests/test_ability_talents_ranger.gd
git commit -m "feat(ranger): Crippling Shot row — Marked for the Kill (CC+Mark combo bonus)"
```

---

### Task 6: Steady Aim row — baseline meter-charge absorption, Controlled Aim, Deadeye

**Files:**
- Modify: `combat/combatant.gd:1254-1262` (`passive_outgoing_multiplier()`, `&"steady_aim"` arm)
- Modify: `combat/combat.gd:2973-2975` (the Steady Aim meter-charge check)
- Modify: `combat/combat.gd:2862-2878` area (`_apply_attack()` — add the Deadeye crit-bonus block; place it right after the Marked for the Kill block from Task 5)
- Modify: `combat/ability_talent_library.gd:422-435` (ranger `&"passive"` row — `steady_wider` keeps byte-identical content)
- Test: `tests/test_ability_talents_ranger.gd` (`_test_steady_aim_row()`, `_test_options_for_shape()`'s `all_ids`)
- Test: `tests/test_passive_steady_aim.gd` (unaffected — baseline `+10%` stays unchanged; verify it still passes, no edit needed)

**Interfaces:** none new — `passive_outgoing_multiplier(defender)`'s signature is unchanged.

- [ ] **Step 1: Write the failing test**

Replace `_test_steady_aim_row()` in `tests/test_ability_talents_ranger.gd` (lines 163-193) with:

```gdscript
func _test_steady_aim_row() -> void:
	var c: Combatant = _mk_ranger()
	c.passive_ability_id = &"steady_aim"
	var marked: Combatant = _mk_ranger()
	marked.attach_effect(EffectLibrary.make(&"hunters_mark"))
	_check(is_equal_approx(c.passive_outgoing_multiplier(marked), 1.10), "baseline Steady Aim: +10% vs a Marked defender")

	var c2: Combatant = _mk_ranger()
	c2.passive_ability_id = &"steady_aim"
	var cc_defender: Combatant = _mk_ranger()
	cc_defender.attach_effect(EffectLibrary.make(&"rooted"))
	_check(is_equal_approx(c2.passive_outgoing_multiplier(cc_defender), 1.0), "sanity: baseline Steady Aim does NOT trigger vs a merely-Rooted defender")
	_check(c2.pick_ability_talent(&"passive", &"steady_controlled"), "picks steady_controlled")
	_check(is_equal_approx(c2.passive_outgoing_multiplier(cc_defender), 1.10), "steady_controlled: now also triggers vs a Rooted defender (got %.3f)" % c2.passive_outgoing_multiplier(cc_defender))

	var c3: Combatant = _mk_ranger()
	c3.passive_ability_id = &"steady_aim"
	var weakened_defender: Combatant = _mk_ranger()
	weakened_defender.attach_effect(EffectLibrary.make(&"weakened"))
	_check(is_equal_approx(c3.passive_outgoing_multiplier(weakened_defender), 1.0), "sanity: baseline Steady Aim does NOT trigger vs a merely-Weakened defender")
	_check(c3.pick_ability_talent(&"passive", &"steady_wider"), "picks steady_wider")
	_check(is_equal_approx(c3.passive_outgoing_multiplier(weakened_defender), 1.10), "steady_wider: now also triggers vs a Weakened defender (got %.3f)" % c3.passive_outgoing_multiplier(weakened_defender))

	# Deadeye's actual +15%-on-CRIT_SUCCESS-vs-Marked bonus lives in combat.gd's _apply_attack() —
	# a crit-specific layer ON TOP OF the unchanged +10% baseline above, not a bigger baseline
	# multiplier — orchestrator-level, NOT headlessly tested here (see this file's header comment).
	var c4: Combatant = _mk_ranger()
	c4.passive_ability_id = &"steady_aim"
	_check(c4.pick_ability_talent(&"passive", &"steady_deadeye"), "picks steady_deadeye")
	_check(c4.has_ability_talent(&"steady_deadeye"), "has_ability_talent sees steady_deadeye")
	_check(is_equal_approx(c4.passive_outgoing_multiplier(marked), 1.10), "steady_deadeye alone leaves the baseline +10%-vs-Marked bonus unchanged")

	# Mutual exclusion (passive row): only 1 pick per row.
	_check(not c4.pick_ability_talent(&"passive", &"steady_controlled"), "a second pick on an already-filled row is rejected (cap of 1/row)")
```

In `_test_options_for_shape()`'s `all_ids` array (line 48), replace
`&"steady_deeper", &"steady_wider", &"steady_charging",` with
`&"steady_controlled", &"steady_wider", &"steady_deadeye",`.

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_ranger.gd`
Expected: FAIL — `steady_controlled`/`steady_deadeye` aren't recognized options yet.

- [ ] **Step 3: Write minimal implementation**

In `combat/combatant.gd`'s `passive_outgoing_multiplier()`, replace the `&"steady_aim":` arm:

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

In `combat/combat.gd`, simplify the Steady Aim meter-charge check (remove the retired
`steady_charging` gate — this behavior is now unconditional per the spec's §2.3 baseline
absorption):

```gdscript
		# Ranger Steady Aim (2026-09-03 ranger-talent-tree spec §2.3, baseline): an extra flat +1
		# charge whenever this hit actually benefited from the Steady Aim passive bonus — mirrors
		# Skirmisher's Charging Opportunist precedent exactly, reading passive_outgoing_multiplier
		# (_defender) against the same primary defender the actual damage math used this spin.
		if attack.final_damage > 0 and _attacker.class_id == &"ranger" and _attacker.passive_outgoing_multiplier(_defender) > 1.0:
			_attacker.bonus_meter.add_flat(1)
			_log("    🏹 Steady Aim strikes true — BM +1  (%d/%d)" % [_attacker.bonus_meter.value, _attacker.bonus_meter.cap])
```

In `combat/combat.gd`'s `_apply_attack()`, right after Task 5's Marked for the Kill block (still
inside the `if attack.source_reel != null and attack.source_reel.bonus_vs_cc:` block's parent
scope — this new check is INDEPENDENT of bonus_vs_cc, so place it as its own top-level `if` right
after that whole block closes), add:

```gdscript
			# Ranger "Deadeye" talent (2026-09-03 ranger-talent-tree spec §7.3): any CRIT_SUCCESS
			# face landed against a Marked defender deals a further bonus, ON TOP of Steady Aim's
			# own unchanged +10%-vs-Marked baseline multiplier (already folded into attack.final_damage
			# via outgoing_damage_multiplier before this function ever runs).
			if _attacker.class_id == &"ranger" and _attacker.has_ability_talent(&"steady_deadeye") and attack.face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS and t.has_effect(&"hunters_mark") and attack.final_damage > 0:
				var deadeye_bonus: int = ceili(attack.final_damage * 0.15)
				t.take_damage(deadeye_bonus)
				_log("  🎯 %s's Deadeye adds %d bonus damage." % [_attacker.display_name, deadeye_bonus])
```

In `combat/ability_talent_library.gd`'s ranger `&"passive"` row, replace the whole case (`p2`/
`steady_wider` keeps identical content, `p1`/`p3` change):

```gdscript
				&"passive":
					var p1: AbilityTalentOption = AbilityTalentOption.new()
					p1.id = &"steady_controlled"; p1.row_id = row_id
					p1.display_name = "Controlled Aim"
					p1.description = "Steady Aim's bonus also triggers vs a Rooted/Slowed/Stunned defender."
					var p2: AbilityTalentOption = AbilityTalentOption.new()
					p2.id = &"steady_wider"; p2.row_id = row_id
					p2.display_name = "Wider Aim"
					p2.description = "Steady Aim's bonus also applies vs a Weakened defender."
					var p3: AbilityTalentOption = AbilityTalentOption.new()
					p3.id = &"steady_deadeye"; p3.row_id = row_id
					p3.display_name = "Deadeye"
					p3.description = "Any CRIT_SUCCESS hit against a Marked defender deals a further +15% bonus damage."
					return [p1, p2, p3]
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_ranger.gd
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_passive_steady_aim.gd
```
Expected: all `ok` lines, no `FAIL`, in both files.

- [ ] **Step 5: Grep for the two retired ids project-wide**

Run: `grep -rn "steady_deeper\|steady_charging" --include=*.gd .` — should now show zero hits.

- [ ] **Step 6: Commit**

```bash
git add combat/combatant.gd combat/combat.gd combat/ability_talent_library.gd tests/test_ability_talents_ranger.gd
git commit -m "feat(ranger): Steady Aim row — baseline meter charge, Controlled Aim, Deadeye (crit-vs-Marked)"
```

---

### Task 7: Collateral Damage row — Point Blank

**Files:**
- Modify: `combat/combat.gd:3258` (`_finish_spin()`'s splash-fraction ternary — simplify to a flat 0.5)
- Modify: `combat/combat.gd:2490-2497` (`_commit_main1()`'s `if did_ultimate:` block — add the Point Blank face-upgrade)
- Modify: `combat/ability_talent_library.gd:436-449` (ranger `&"ultimate"` row — only the
  `collateral_deeper` slot changes; `collateral_marking`/`collateral_lasting` keep byte-identical content)
- Test: `tests/test_ability_talents_ranger.gd` (`_test_collateral_row()`, `_test_options_for_shape()`'s `all_ids`)

**Interfaces:** none new.

- [ ] **Step 1: Write the failing test**

In `tests/test_ability_talents_ranger.gd`'s `_test_collateral_row()` (lines 195-239), replace the
`collateral_deeper` sub-test (lines 196-203) with:

```gdscript
	# Point Blank's actual guaranteed-crit face upgrade (only when the primary target is already
	# Marked) lives in combat.gd's _commit_main1(), right after fire_collateral() appends its reel —
	# orchestrator-level (needs _defender), NOT headlessly tested here (see this file's header
	# comment).
	var c: Combatant = _mk_ranger()
	_check(c.pick_ability_talent(&"ultimate", &"collateral_point_blank"), "picks collateral_point_blank")
	_check(c.has_ability_talent(&"collateral_point_blank"), "has_ability_talent sees collateral_point_blank")
```

Also replace the final mutual-exclusion sub-test's first pick (was `collateral_deeper`):

```gdscript
	# Mutual exclusion (ultimate row): only 1 pick per row.
	var c5: Combatant = _mk_ranger()
	_check(c5.pick_ability_talent(&"ultimate", &"collateral_point_blank"), "first pick on the Collateral Damage row succeeds")
	_check(not c5.pick_ability_talent(&"ultimate", &"collateral_marking"), "a second pick on an already-filled row is rejected (cap of 1/row)")
```

In `_test_options_for_shape()`'s `all_ids` array (line 49), replace
`&"collateral_deeper", &"collateral_marking", &"collateral_lasting",` with
`&"collateral_lasting", &"collateral_marking", &"collateral_point_blank",`.

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_ranger.gd`
Expected: FAIL — `collateral_point_blank` is not a recognized option yet.

- [ ] **Step 3: Write minimal implementation**

In `combat/combat.gd`'s `_finish_spin()`, simplify the splash-fraction line (the `collateral_deeper`
ternary is retired, so the fraction is now always the baseline 0.5):

```gdscript
	if _attacker.is_collateral_active():
		var splashed: Array[Combatant] = _splash_half_to_others(_attacker, _collateral_total, "Piercing", 0.5)
```

In `combat/combat.gd`'s `_commit_main1()`, inside the `if did_ultimate:` block, right after the
existing `dark_reinforcements` special-case (still inside the same `if did_ultimate:` block), add:

```gdscript
		# Ranger "Point Blank" talent (2026-09-03 ranger-talent-tree spec §8.3): if the primary
		# target is already Marked when Collateral Damage resolves, its primary-target reel (the
		# last reel fire_collateral() appended) is upgraded to a GUARANTEED crit — every face
		# becomes CRIT_SUCCESS. Splash damage/logic to other enemies is untouched; it's simply
		# computed from this reel's own (now bigger) final_damage later in _finish_spin.
		if _attacker.ultimate_id == &"collateral" and _attacker.has_ability_talent(&"collateral_point_blank") and _defender.has_effect(&"hunters_mark"):
			var collateral_reel: ActionReel = _attacker.turn_reels[_attacker.turn_reels.size() - 1]
			for f: ReelFace in collateral_reel.faces:
				f.result_tier = ReelFace.ResultTier.CRIT_SUCCESS
				f.multiplier = 2.0
```

In `combat/ability_talent_library.gd`'s ranger `&"ultimate"` row, replace the `u1`
(`collateral_deeper`) option only — `u2`/`u3` stay byte-identical:

```gdscript
				&"ultimate":
					var u1: AbilityTalentOption = AbilityTalentOption.new()
					u1.id = &"collateral_point_blank"; u1.row_id = row_id
					u1.display_name = "Point Blank"
					u1.description = "If the primary target is already Marked, Collateral Damage's primary hit is a guaranteed critical."
					var u2: AbilityTalentOption = AbilityTalentOption.new()
					u2.id = &"collateral_marking"; u2.row_id = row_id
					u2.display_name = "Marking Collateral"
					u2.description = "Every enemy splashed by Collateral Damage also gets Hunter's Mark applied."
					var u3: AbilityTalentOption = AbilityTalentOption.new()
					u3.id = &"collateral_lasting"; u3.row_id = row_id
					u3.display_name = "Lasting Collateral"
					u3.description = "Collateral Damage's added reel stays for 2 spins instead of 1."
					return [u1, u2, u3]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_ranger.gd`
Expected: all `ok` lines, no `FAIL`.

- [ ] **Step 5: Grep for the retired `collateral_deeper` id project-wide**

Run: `grep -rn "collateral_deeper" --include=*.gd .` — expect it to remain ONLY inside
`tests/test_ability_talents_warden.gd`'s comment (line ~204, "mirrors Ranger's collateral_deeper
math-only convention") — a harmless historical reference, not a live dependency; leave it as-is
(matches this plan's own Global Constraints note: don't touch unrelated files beyond what's broken).

- [ ] **Step 6: Commit**

```bash
git add combat/combat.gd combat/ability_talent_library.gd tests/test_ability_talents_ranger.gd
git commit -m "feat(ranger): Collateral Damage row — Point Blank (guaranteed crit vs a Marked primary target)"
```

---

### Task 8: Final regression sweep

**Files:**
- No production changes expected — this task is verification-only, with fixes applied inline if
  the sweep finds anything.

- [ ] **Step 1: Grep for all retired ids across the ENTIRE repo (not just `.gd` files — plan/spec
  docs may also reference them for historical reasons, which is fine, but distinguish those from
  anything still LIVE in `combat/` or `tests/`)**

Run: `grep -rn "mark_deeper\|mark_weakening\|mark_efficient\|aim_deeper\|aim_piercing\|aim_efficient\|snare_deeper\|snare_lasting\|snare_efficient\|crippling_deeper\|steady_deeper\|steady_charging\|collateral_deeper" combat/ tests/`
Expected: zero hits, EXCEPT the one known harmless comment in
`tests/test_ability_talents_warden.gd` (see Task 7 Step 5) — confirm that's the only survivor.

- [ ] **Step 2: Run every test file this plan touched, in one pass**

Run each of these and confirm zero `FAIL`/`SCRIPT ERROR` in the output (grep the actual output text,
per this project's own documented "silent script-error-exits-zero" gotcha — don't trust exit codes
alone):

```
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_hunters_mark.gd
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_marksmans_call.gd
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_aimed_shot.gd
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_snare_trap.gd
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_crippling_shot.gd
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_passive_steady_aim.gd
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_collateral.gd
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_ranger.gd
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_warden.gd
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_menu_state.gd
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_payline_and_splash_damage_multiplier.gd
```

`test_ability_talents_warden.gd` is included because Task 4 removed the `&"rooted":` case ranger
shared no code with, and because `_splash_half_to_others()` (touched conceptually by Tasks 4/7) is
also used by Warden's Earthquake — confirm Earthquake's own splash math is untouched.
`test_ability_menu_state.gd` is included because it may render Ranger ability-cooldown/talent
previews live; confirm nothing there references a retired id.

If any of these fail unexpectedly, read the failure, fix the root cause in the relevant production
file, and re-run — do not edit a test's expectation unless the OLD expectation was actually
asserting the retired/changed behavior on purpose.

- [ ] **Step 3: Confirm Warden's Earthquake splash/Rooted logic is untouched**

Read `combat/combat.gd`'s Earthquake block (the `_attacker.is_earthquake_active()` section in
`_apply_attack()`) and confirm Task 4's new Snare Trap splash block (also in `_apply_attack()`,
gated on `_attacker.class_id == &"ranger"`) cannot fire for a Warden — the class_id guard makes
this true by construction, but re-read it once to be sure no shared mutable state (e.g. `targets`)
leaked between the two blocks.

- [ ] **Step 4: Commit (only if Step 2 required fixes)**

```bash
git add -A
git commit -m "test(ranger): fix regressions surfaced by the talent-tree depth rework's final sweep"
```

(Skip this commit entirely if Step 2 found nothing to fix — an empty final-sweep task doesn't need
a commit.)
