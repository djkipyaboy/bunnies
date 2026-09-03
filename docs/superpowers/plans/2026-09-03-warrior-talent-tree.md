# Warrior Talent Tree Depth Rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rework the Warrior's 6-row talent tree (`combat/ability_talent_library.gd`'s `&"warrior"`
case) into a Bleed/Sundered synergy backbone plus a baseline power bump, replacing 7 of its 18 flat
"+X%" options and bumping several unconditional baseline numbers, without touching rank-2/stat-
scaling (a separate deferred pass).

**Architecture:** No new systems or effect ids. Every new mechanic reuses an existing engine idiom
already shipped for another class: the defender-conditional passive check (`passive_outgoing_
multiplier(defender)`, already used by Ranger's Opportunist/Seer's Steady Aim), the generic
`outgoing_damage_multiplier(defender)` composition point, the `apply_rider_talent_adjustments()`
per-rider hook (already used for Bleed/Sundered's existing talents), and the "+1 reel" splice
pattern already used by Rampage/Collateral/Big Bang/Earthquake.

**Tech Stack:** Godot 4.6 / GDScript, headless test runner (`Godot_v4.6.3-stable_win64_console.exe
--headless --path . --script res://tests/<file>.gd`, run from the repo root one directory below
the executable).

**Spec:** `docs/superpowers/specs/2026-09-03-warrior-talent-tree-design.md`

## Global Constraints

- Every specific percentage/turn-count is an `[ASSUMPTION]` placeholder (CLAUDE.md §4) — implement
  as plain data (local `var`/constants), not something requiring a design review to change later.
- No rank-2/stat-scaling wiring in this plan — that's a separate, later spec (design doc's Open
  Questions).
- No new effect ids — every synergy check reads existing `&"bleed"`/`&"sundered"` state via
  `has_effect()`.
- Round up (ceil) for any new damage/heal math, per project convention.
- Before considering this plan done, grep the whole repo for all 8 retired option ids
  (`rend_efficient`, `sunder_efficient`, `sunder_lingering`, `guard_cleansing`, `guard_lasting`,
  `wind_swift`, `stand_deeper`, `wild_truer`) — Task 8 does this explicitly, but if any earlier
  task's own grep turns up an unexpected hit, fix it in that task rather than deferring it.

---

### Task 1: Sundered baseline magnitude bump

**Files:**
- Modify: `combat/effect_library.gd:58-62` (the `&"sundered"` case)
- Test: `tests/test_new_effects.gd`

**Interfaces:**
- Produces: `EffectLibrary.make(&"sundered")` now returns `magnitude = 1.30` (was 1.25). Every
  caller (Sundering Strike, and anything else that builds a fresh Sundered) picks this up
  automatically — no other file references the literal `1.25` for Sundered's baseline.

- [ ] **Step 1: Write the failing test**

Add this block right after the existing `sundered`/`guarded` checks (after line 16) in
`tests/test_new_effects.gd`:

```gdscript
	_check(is_equal_approx(sundered.magnitude, 1.30), "sundered: baseline incoming multiplier is 1.30 (got %.3f)" % sundered.magnitude)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_new_effects.gd`
Expected: `FAIL sundered: baseline incoming multiplier is 1.30 (got 1.250)`

- [ ] **Step 3: Write minimal implementation**

In `combat/effect_library.gd`, change the `&"sundered"` case's magnitude:

```gdscript
	&"sundered":
		var e: Effect = Effect.new()
		e.id = &"sundered"; e.kind = Effect.Kind.MULTIPLIER_EDIT; e.magnitude = 1.30
		e.affects_incoming = true; e.duration = 2; e.beneficial = false
		return e
```

- [ ] **Step 4: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_new_effects.gd`
Expected: all `ok` lines, no `FAIL`.

- [ ] **Step 5: Commit**

```bash
git add combat/effect_library.gd tests/test_new_effects.gd
git commit -m "feat(warrior): bump Sundered's baseline incoming-damage magnitude to 1.30"
```

---

### Task 2: Rend row — Deeper Cut bump + Salted Wound

**Files:**
- Modify: `combat/combatant.gd:975-991` (`apply_rider_talent_adjustments()`, `&"warrior"` /
  `&"bleed"` case)
- Modify: `combat/ability_talent_library.gd` (warrior `&"base_ability"` row, ~lines 14-27)
- Test: `tests/test_ability_talents_warrior.gd` (`_test_rend_row()`, lines 52-81)

**Interfaces:**
- Consumes: `Combatant.apply_rider_talent_adjustments(rider_id: StringName, effect: Effect, target:
  Combatant) -> void` (existing signature, already takes `target`).
- Produces: new option id `&"rend_salted_wound"` (row `base_ability`), replacing `&"rend_efficient"`.

- [ ] **Step 1: Write the failing test**

Replace `_test_rend_row()` in `tests/test_ability_talents_warrior.gd` with:

```gdscript
func _test_rend_row() -> void:
	var c2: Combatant = _mk_warrior()
	_check(c2.pick_ability_talent(&"base_ability", &"rend_deeper_cut"), "picks rend_deeper_cut")
	var bleed: Effect = EffectLibrary.make(&"bleed")
	var base_fractions: Array = bleed.dot_fractions.duplicate()
	c2.apply_rider_talent_adjustments(&"bleed", bleed, c2)
	for i: int in range(base_fractions.size()):
		_check(is_equal_approx(bleed.dot_fractions[i], base_fractions[i] * 1.35),
			"rend_deeper_cut: Bleed fraction %d is +35%% (got %.4f, want %.4f)" % [i, bleed.dot_fractions[i], base_fractions[i] * 1.35])
	_check(bleed.max_stacks == 3, "rend_deeper_cut alone leaves max_stacks at 3")

	var c3: Combatant = _mk_warrior()
	_check(c3.pick_ability_talent(&"base_ability", &"rend_lasting_wound"), "picks rend_lasting_wound")
	var bleed2: Effect = EffectLibrary.make(&"bleed")
	c3.apply_rider_talent_adjustments(&"bleed", bleed2, c3)
	_check(bleed2.max_stacks == 4, "rend_lasting_wound: Bleed max_stacks is 4 (got %d)" % bleed2.max_stacks)
	_check(bleed2.dot_fractions.size() == 4, "rend_lasting_wound: Bleed gained a 4th stack fraction (got %d entries)" % bleed2.dot_fractions.size())
	_check(is_equal_approx(bleed2.dot_fractions[3], 1.55), "rend_lasting_wound: 4th stack fraction is 1.55 (got %.4f)" % bleed2.dot_fractions[3])

	# Salted Wound: bonus only fires if the TARGET already carries Sundered.
	var c4: Combatant = _mk_warrior()
	_check(c4.pick_ability_talent(&"base_ability", &"rend_salted_wound"), "picks rend_salted_wound")
	var target_plain: Combatant = _mk_warrior()
	var bleed3: Effect = EffectLibrary.make(&"bleed")
	var base_fractions3: Array = bleed3.dot_fractions.duplicate()
	c4.apply_rider_talent_adjustments(&"bleed", bleed3, target_plain)
	for i: int in range(base_fractions3.size()):
		_check(is_equal_approx(bleed3.dot_fractions[i], base_fractions3[i]),
			"rend_salted_wound: no bonus vs. a target with no Sundered (fraction %d unchanged)" % i)

	var c5: Combatant = _mk_warrior()
	_check(c5.pick_ability_talent(&"base_ability", &"rend_salted_wound"), "picks rend_salted_wound")
	var target_sundered: Combatant = _mk_warrior()
	target_sundered.attach_effect(EffectLibrary.make(&"sundered"))
	var bleed4: Effect = EffectLibrary.make(&"bleed")
	var base_fractions4: Array = bleed4.dot_fractions.duplicate()
	c5.apply_rider_talent_adjustments(&"bleed", bleed4, target_sundered)
	for i: int in range(base_fractions4.size()):
		_check(is_equal_approx(bleed4.dot_fractions[i], base_fractions4[i] * 1.25),
			"rend_salted_wound: +25%% vs. a Sundered target (fraction %d got %.4f, want %.4f)" % [i, bleed4.dot_fractions[i], base_fractions4[i] * 1.25])

	# Mutual exclusion: only 1 pick per row.
	var c6: Combatant = _mk_warrior()
	_check(c6.pick_ability_talent(&"base_ability", &"rend_deeper_cut"), "first pick on the Rend row succeeds")
	_check(not c6.pick_ability_talent(&"base_ability", &"rend_lasting_wound"), "a second pick on an already-filled row is rejected (cap of 1/row)")
	_check(c6.has_ability_talent(&"rend_deeper_cut"), "the row's original pick is still active")
```

Also update `_test_options_for_shape()`'s `all_ids` array (line 34): replace
`&"rend_deeper_cut", &"rend_lasting_wound", &"rend_efficient",` with
`&"rend_deeper_cut", &"rend_lasting_wound", &"rend_salted_wound",`.

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_warrior.gd`
Expected: FAIL on the 1.35 fraction check (still 1.25 in code) and on `rend_salted_wound` not being
a recognized option id.

- [ ] **Step 3: Write minimal implementation**

In `combat/combatant.gd`'s `apply_rider_talent_adjustments()`, `&"warrior"` / `&"bleed"` case:

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

In `combat/ability_talent_library.gd`'s warrior `&"base_ability"` row, replace the `o3`
(`rend_efficient`) option:

```gdscript
				&"base_ability":
					var o1: AbilityTalentOption = AbilityTalentOption.new()
					o1.id = &"rend_deeper_cut"; o1.row_id = row_id
					o1.display_name = "Deeper Cut"
					o1.description = "Rend's Bleed deals +35% DoT damage."
					var o2: AbilityTalentOption = AbilityTalentOption.new()
					o2.id = &"rend_lasting_wound"; o2.row_id = row_id
					o2.display_name = "Lasting Wound"
					o2.description = "Rend's Bleed can stack up to 4 times (was 3)."
					var o3: AbilityTalentOption = AbilityTalentOption.new()
					o3.id = &"rend_salted_wound"; o3.row_id = row_id
					o3.display_name = "Salted Wound"
					o3.description = "Rend's Bleed deals +25% DoT damage if the target already carries Sundered."
					return [o1, o2, o3]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_warrior.gd`
Expected: all `ok` lines, no `FAIL`.

- [ ] **Step 5: Grep for the retired `rend_efficient` id project-wide**

Run: `grep -rn "rend_efficient" --include=*.gd .` (or the Grep tool) — fix any other hit found (there
should be none besides the two files already touched; if `tests/test_ability_menu_state.gd` or
any other file references it, update that call site to use `rend_salted_wound` or drop the
assertion, whichever preserves the original test's intent).

- [ ] **Step 6: Commit**

```bash
git add combat/combatant.gd combat/ability_talent_library.gd tests/test_ability_talents_warrior.gd
git commit -m "feat(warrior): Rend row — bump Deeper Cut to +35%, add Salted Wound (Sundered synergy)"
```

---

### Task 3: Sundering Strike row — Vicious Return + Twist the Knife

**Files:**
- Modify: `combat/combatant.gd:835-844` (`ability_talent_cost_delta()`, remove the `sundering_strike`
  arm)
- Modify: `combat/combatant.gd:975-991` (`apply_rider_talent_adjustments()`, `&"sundered"` case —
  remove the `sunder_lingering` branch)
- Modify: `combat/combat.gd:2830-2998` (`_apply_attack()` — add the pre-hit snapshot + two new
  conditional bonuses)
- Modify: `combat/ability_talent_library.gd` (warrior `&"ability_l2"` row)
- Test: `tests/test_ability_talents_warrior.gd` (`_test_sundering_strike_row()`, lines 83-101)

**Interfaces:**
- Produces: in `combat.gd::_apply_attack()`, a per-target snapshot pair
  (`target_had_bleed_before_hit`, `target_had_sundered_before_hit`) taken BEFORE any effect gets
  attached to that target this hit — later tasks do not need these (Vengeful Guard/Vengeful
  Stand/Executioner's Wild all read defender state at the pre-spin `outgoing_damage_multiplier()`
  call site instead, which already runs before any of this turn's hits land), but if a future task
  ever needs a "did the target already have X before THIS hit" check inside `_apply_attack()`,
  reuse this pair rather than adding a second snapshot.

**Why the snapshot matters (read before writing the code):** `_apply_attack()` already contains a
Warrior-specific block (the existing `wild_bleeding` check) that can itself attach a fresh Bleed
stack to the SAME target earlier in the same function, before the new code below runs. A live
`t.has_effect(&"bleed")` call after that point would see the bleed Wild just applied THIS hit, not
a genuinely pre-existing one — so Twist the Knife and Vicious Return must read a snapshot taken at
the very top of the per-target loop, before any same-hit effect attachment happens.

- [ ] **Step 1: Write the failing test**

Replace `_test_sundering_strike_row()` in `tests/test_ability_talents_warrior.gd` with:

```gdscript
func _test_sundering_strike_row() -> void:
	var c2: Combatant = _mk_warrior()
	_check(c2.pick_ability_talent(&"ability_l2", &"sunder_deeper"), "picks sunder_deeper")
	var sundered: Effect = EffectLibrary.make(&"sundered")
	c2.apply_rider_talent_adjustments(&"sundered", sundered, c2)
	_check(is_equal_approx(sundered.magnitude, 1.35), "sunder_deeper: Sundered's incoming multiplier is 1.35 (got %.3f)" % sundered.magnitude)
	_check(sundered.duration == 2, "sunder_deeper alone leaves duration at 2")

	# Vicious Return / Twist the Knife: the actual on-hit refund/bonus-damage lives in combat.gd's
	# _apply_attack() (orchestrator-level), same documented precedent as Bleeding Wild (see this
	# file's header comment) — headlessly we only prove the talent is a real, pickable, mutually-
	# exclusive option on this row.
	var c3: Combatant = _mk_warrior()
	_check(c3.pick_ability_talent(&"ability_l2", &"sunder_vicious_return"), "picks sunder_vicious_return")
	_check(c3.has_ability_talent(&"sunder_vicious_return"), "has_ability_talent sees sunder_vicious_return")
	_check(not c3.pick_ability_talent(&"ability_l2", &"sunder_deeper"), "a second pick on an already-filled row is rejected (cap of 1/row)")

	var c4: Combatant = _mk_warrior()
	_check(c4.pick_ability_talent(&"ability_l2", &"sunder_twist_knife"), "picks sunder_twist_knife")
	_check(c4.has_ability_talent(&"sunder_twist_knife"), "has_ability_talent sees sunder_twist_knife")
```

Also update `_test_options_for_shape()`'s `all_ids` array (line 35): replace
`&"sunder_deeper", &"sunder_lingering", &"sunder_efficient",` with
`&"sunder_deeper", &"sunder_vicious_return", &"sunder_twist_knife",`.

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_warrior.gd`
Expected: FAIL — `sunder_vicious_return`/`sunder_twist_knife` aren't recognized options yet.

- [ ] **Step 3: Write minimal implementation**

In `combat/combatant.gd`, `ability_talent_cost_delta()`: delete the `&"sundering_strike":` arm
entirely (it now falls through to the warrior match's `_: return 0`):

```gdscript
	match class_id:
		&"warrior":
			match ability_id:
				&"rend":
					return -1 if has_ability_talent(&"rend_efficient") else 0
				_:
					return 0
```

In `apply_rider_talent_adjustments()`, `&"sundered"` case: drop the `sunder_lingering` branch (no
replacement — the design retires duration-extension for this row without a baseline absorption):

```gdscript
			&"sundered":
				if has_ability_talent(&"sunder_deeper"):
					effect.magnitude = 1.35
```

In `combat/combat.gd`'s `_apply_attack()`, at the top of the `if attack.final_damage > 0:` block's
`for t: Combatant in targets:` loop (right after `for t: Combatant in targets:`, before
`t.take_damage(attack.final_damage)`), add the snapshot:

```gdscript
			for t: Combatant in targets:
				var target_had_bleed_before_hit: bool = t.has_effect(&"bleed")
				var target_had_sundered_before_hit: bool = t.has_effect(&"sundered")
				t.take_damage(attack.final_damage)
```

Then, immediately after the existing `rider_talent_bonus_damage_pct` block (right after the `if
attack.rider_effect_id != &"":` / `talent_bonus_pct` block that ends around line 2893), add:

```gdscript
				# Warrior "Twist the Knife" talent: Sundering Strike's own hit deals bonus damage
				# if the target already carried Bleed BEFORE this hit (snapshot above — Bleeding
				# Wild's block above this one can attach a fresh Bleed same-hit, which must not
				# count).
				if _attacker.class_id == &"warrior" and _attacker.has_ability_talent(&"sunder_twist_knife") and attack.rider_effect_id == &"sundered" and target_had_bleed_before_hit and attack.final_damage > 0:
					var twist_bonus: int = ceili(attack.final_damage * 0.20)
					t.take_damage(twist_bonus)
					_log("  🗡 %s's Twist the Knife adds %d bonus damage." % [_attacker.display_name, twist_bonus])
				# Warrior "Vicious Return" talent: Sundering Strike refunds its full Stamina cost
				# if it lands on a target that already carried Sundered BEFORE this hit (a refresh,
				# not a fresh application).
				if _attacker.class_id == &"warrior" and _attacker.has_ability_talent(&"sunder_vicious_return") and attack.rider_effect_id == &"sundered" and target_had_sundered_before_hit and attack.final_damage > 0:
					var sunder_def: AbilityDef = _attacker.find_extra_ability(&"sundering_strike")
					if sunder_def != null:
						_attacker.resource_pool.refund({&"stamina": sunder_def.cost})
						_log("  ♻ %s's Vicious Return refunds %d Stamina." % [_attacker.display_name, sunder_def.cost])
```

In `combat/ability_talent_library.gd`'s warrior `&"ability_l2"` row:

```gdscript
				&"ability_l2":
					var s1: AbilityTalentOption = AbilityTalentOption.new()
					s1.id = &"sunder_deeper"; s1.row_id = row_id
					s1.display_name = "Deeper Sunder"
					s1.description = "Sundering Strike's Sundered debuff raises incoming damage taken to +35% (was +30%)."
					var s2: AbilityTalentOption = AbilityTalentOption.new()
					s2.id = &"sunder_vicious_return"; s2.row_id = row_id
					s2.display_name = "Vicious Return"
					s2.description = "Sundering Strike refunds its full Stamina cost if it hits a target that's already Sundered."
					var s3: AbilityTalentOption = AbilityTalentOption.new()
					s3.id = &"sunder_twist_knife"; s3.row_id = row_id
					s3.display_name = "Twist the Knife"
					s3.description = "Sundering Strike deals +20% bonus damage if the target already carries Bleed."
					return [s1, s2, s3]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_warrior.gd`
Expected: all `ok` lines, no `FAIL`.

- [ ] **Step 5: Grep for the two retired ids project-wide**

Run: `grep -rn "sunder_efficient\|sunder_lingering" --include=*.gd .` — fix any hit besides the two
files already touched in this task.

- [ ] **Step 6: Commit**

```bash
git add combat/combatant.gd combat/combat.gd combat/ability_talent_library.gd tests/test_ability_talents_warrior.gd
git commit -m "feat(warrior): Sundering Strike row — Vicious Return (stamina refund) + Twist the Knife (Bleed synergy)"
```

---

### Task 4: Heroic Guard row — baseline bump + Reckless Guard + Vengeful Guard

**Files:**
- Modify: `combat/combatant.gd:1726-1751` (`apply_heroic_guard()`)
- Modify: `combat/combatant.gd:1193-1200` (`outgoing_damage_multiplier()`)
- Modify: `combat/ability_talent_library.gd` (warrior `&"ability_l3"` row)
- Modify: `combat/main_phase_plan.gd:531-532` (the `&"heroic_guard":` dispatch call — pass `reel_cap`)
- Test: `tests/test_ability_talents_warrior.gd` (`_test_heroic_guard_row()`, lines 103-132)

**Interfaces:**
- Consumes: `Combatant.outgoing_damage_multiplier(defender: Combatant = null) -> float` (existing
  signature).
- Produces: `apply_heroic_guard(cost: int, cap: int = 999) -> bool` — signature gains a second
  parameter with a default so every existing headless-test call site (`c.apply_heroic_guard(2)`)
  keeps compiling unchanged; only `main_phase_plan.gd`'s real dispatch needs to pass the actual
  `reel_cap`.

**Why `EffectLibrary.make(&"guarded")`'s shared default must NOT change:** Guarded's 0.75 default
magnitude is also used by Skirmisher's Feint & Riposte (which never overrides it) and is the
un-overridden starting point Vanguard's Mountain Stance/Warden's Bastion both explicitly replace.
Bumping the shared default would silently change Feint & Riposte's magnitude too — a class this
spec never touches. Heroic Guard's new 70%/60% numbers must be set as an explicit
`guard.magnitude = ...` assignment inside `apply_heroic_guard()` itself, exactly as `guard_reinforced`
already does today.

- [ ] **Step 1: Write the failing test**

Replace `_test_heroic_guard_row()` in `tests/test_ability_talents_warrior.gd` with:

```gdscript
func _test_heroic_guard_row() -> void:
	var c: Combatant = _mk_warrior()
	c.attach_effect(EffectLibrary.make(&"slow"))
	_check(c.apply_heroic_guard(2), "casts Heroic Guard (baseline)")
	var g: Effect = c._find_effect(&"guarded")
	var t: Effect = c._find_effect(&"taunt")
	_check(g != null, "sanity: Guarded attached")
	_check(is_equal_approx(g.magnitude, 0.70), "baseline Heroic Guard: Guarded magnitude 0.70 (got %.3f)" % g.magnitude)
	_check(g.duration == 4, "baseline Heroic Guard: 4-turn duration")
	_check(t != null and t.duration == 4, "baseline Heroic Guard: Taunt attached, 4-turn duration")
	_check(not c.has_effect(&"slow"), "baseline Heroic Guard now cleanses on cast unconditionally")

	var c2: Combatant = _mk_warrior()
	_check(c2.pick_ability_talent(&"ability_l3", &"guard_reinforced"), "picks guard_reinforced")
	_check(c2.apply_heroic_guard(2), "casts Heroic Guard (reinforced)")
	var g2: Effect = c2._find_effect(&"guarded")
	_check(is_equal_approx(g2.magnitude, 0.60), "guard_reinforced: Guarded magnitude 0.60 (got %.3f)" % g2.magnitude)

	var c3: Combatant = _mk_warrior()
	_check(c3.pick_ability_talent(&"ability_l3", &"guard_reckless"), "picks guard_reckless")
	var reels_before: int = c3.turn_reels.size()
	_check(c3.apply_heroic_guard(2, 5), "casts Heroic Guard (reckless)")
	_check(c3._find_effect(&"taunt") == null, "guard_reckless: no Taunt is applied")
	_check(c3._find_effect(&"guarded") != null, "guard_reckless: Guarded is still applied")
	_check(c3.turn_reels.size() == reels_before + 1, "guard_reckless: +1 action reel spliced onto this turn")

	var c4: Combatant = _mk_warrior()
	_check(c4.pick_ability_talent(&"ability_l3", &"guard_vengeful"), "picks guard_vengeful")
	_check(c4.apply_heroic_guard(2), "casts Heroic Guard (vengeful)")
	var enemy_plain: Combatant = _mk_warrior()
	var enemy_bled: Combatant = _mk_warrior()
	enemy_bled.attach_effect(EffectLibrary.make(&"bleed"))
	_check(is_equal_approx(c4.outgoing_damage_multiplier(enemy_plain), 1.0), "guard_vengeful: no bonus vs. an undebuffed target")
	_check(is_equal_approx(c4.outgoing_damage_multiplier(enemy_bled), 1.20), "guard_vengeful: +20%% vs. a Bled target while Guarded (got %.3f)" % c4.outgoing_damage_multiplier(enemy_bled))

	var c5: Combatant = _mk_warrior()
	_check(c5.pick_ability_talent(&"ability_l3", &"guard_vengeful"), "picks guard_vengeful")
	var enemy_bled2: Combatant = _mk_warrior()
	enemy_bled2.attach_effect(EffectLibrary.make(&"bleed"))
	_check(is_equal_approx(c5.outgoing_damage_multiplier(enemy_bled2), 1.0), "guard_vengeful: no bonus vs. a Bled target when NOT currently Guarded")

	# Mutual exclusion: only 1 pick per row.
	var c6: Combatant = _mk_warrior()
	_check(c6.pick_ability_talent(&"ability_l3", &"guard_reinforced"), "first pick on the Heroic Guard row succeeds")
	_check(not c6.pick_ability_talent(&"ability_l3", &"guard_reckless"), "a second pick on an already-filled row is rejected (cap of 1/row)")
```

Also update `_test_options_for_shape()`'s `all_ids` array (line 36): replace
`&"guard_reinforced", &"guard_cleansing", &"guard_lasting",` with
`&"guard_reinforced", &"guard_vengeful", &"guard_reckless",`.

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_warrior.gd`
Expected: FAIL — baseline magnitude/duration/cleanse assertions fail against the old 0.75/3-turn/
gated-cleanse behavior; `guard_vengeful`/`guard_reckless` aren't recognized options yet.

- [ ] **Step 3: Write minimal implementation**

In `combat/combatant.gd`, replace `apply_heroic_guard()`:

```gdscript
func apply_heroic_guard(cost: int, cap: int = 999) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	var dur: int = 4
	var guard: Effect = EffectLibrary.make(&"guarded")
	guard.magnitude = 0.60 if has_ability_talent(&"guard_reinforced") else 0.70
	guard.duration = dur
	attach_effect(guard)
	if has_ability_talent(&"guard_reckless"):
		if turn_reels.size() < cap:
			turn_reels.append(ActionReel.make_ability_attack(weapon_type()))
	else:
		var taunt: Effect = EffectLibrary.make(&"taunt")
		taunt.duration = dur
		attach_effect(taunt)
	cleanse()
	return true
```

In `outgoing_damage_multiplier()`, add the Vengeful Guard check before the `return total` line:

```gdscript
func outgoing_damage_multiplier(defender: Combatant = null) -> float:
	var total: float = 1.0
	for e: Effect in active_effects:
		if e != null and e.kind == Effect.Kind.MULTIPLIER_EDIT and not e.affects_incoming:
			total *= e.effective_magnitude()
	total *= passive_outgoing_multiplier(defender)
	total *= power_stat_weapon_multiplier()
	if class_id == &"warrior" and has_ability_talent(&"guard_vengeful") and has_effect(&"guarded") and defender != null and (defender.has_effect(&"bleed") or defender.has_effect(&"sundered")):
		total *= 1.20
	return total
```

In `combat/ability_talent_library.gd`'s warrior `&"ability_l3"` row:

```gdscript
				&"ability_l3":
					var g1: AbilityTalentOption = AbilityTalentOption.new()
					g1.id = &"guard_reinforced"; g1.row_id = row_id
					g1.display_name = "Reinforced Guard"
					g1.description = "Heroic Guard reduces incoming damage to 60% (was 70%)."
					var g2: AbilityTalentOption = AbilityTalentOption.new()
					g2.id = &"guard_vengeful"; g2.row_id = row_id
					g2.display_name = "Vengeful Guard"
					g2.description = "While Guarded (from Heroic Guard), your hits against a Bled or Sundered target deal +20% bonus damage."
					var g3: AbilityTalentOption = AbilityTalentOption.new()
					g3.id = &"guard_reckless"; g3.row_id = row_id
					g3.display_name = "Reckless Guard"
					g3.description = "Heroic Guard no longer applies Taunt, but grants +1 action reel for its duration."
					return [g1, g2, g3]
```

In `combat/main_phase_plan.gd`, the `&"heroic_guard":` dispatch line (~532):

```gdscript
			&"heroic_guard":
				combatant.apply_heroic_guard(extra_talent_cost, reel_cap)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_warrior.gd`
Expected: all `ok` lines, no `FAIL`.

- [ ] **Step 5: Grep for the two retired ids project-wide**

Run: `grep -rn "guard_cleansing\|guard_lasting" --include=*.gd .` — fix any hit besides the files
already touched in this task.

- [ ] **Step 6: Commit**

```bash
git add combat/combatant.gd combat/ability_talent_library.gd combat/main_phase_plan.gd tests/test_ability_talents_warrior.gd
git commit -m "feat(warrior): Heroic Guard row — baseline cleanse/4-turn/70% bump, Reckless Guard, Vengeful Guard"
```

---

### Task 5: Second Wind row — heal/duration bump + Desperate Recovery

**Files:**
- Modify: `combat/combatant.gd:1757-1771` (`apply_second_wind()`)
- Modify: `combat/combatant.gd:918-925` (`ability_talent_cooldown_delta()`, `&"warrior"` /
  `&"second_wind"` arm)
- Modify: `combat/ability_talent_library.gd` (warrior `&"ability_l4"` row)
- Modify: `combat/main_phase_plan.gd:507-561` (compute `talent_cd` BEFORE the ability dispatch match,
  not after)
- Test: `tests/test_ability_talents_warrior.gd` (`_test_second_wind_row()`, lines 134-...)
- Test: `tests/test_ability_menu_state.gd:89-91` (the retired `wind_swift` preview check)

**Interfaces:**
- Consumes: `Combatant.ability_talent_cooldown_delta(ability_id: StringName) -> int` (existing
  signature, existing call site in `main_phase_plan.gd`).

**Why the `main_phase_plan.gd` reorder is required:** Desperate Recovery's condition is "the
Warrior's HP was at/below Last Stand's threshold WHEN Second Wind was cast." `apply_second_wind()`
calls `heal()` — if `ability_talent_cooldown_delta()` (which will read current `hp`) is evaluated
AFTER `apply_second_wind()` already ran (the current code order), the heal has already raised `hp`
and the check would almost always read as "not desperate," defeating the whole mechanic. Moving
the `talent_cd` calculation to before the per-ability dispatch match (mirroring how
`extra_talent_cost` is already computed before that same match, one line above) fixes this with no
new state — `ability_talent_cooldown_delta()` just reads `hp` at the right moment. No other
ability's cooldown delta depends on cast-time side effects, so this reorder changes nothing for
any of them.

- [ ] **Step 1: Write the failing test**

Replace `_test_second_wind_row()` in `tests/test_ability_talents_warrior.gd` with:

```gdscript
func _test_second_wind_row() -> void:
	var c2: Combatant = _mk_warrior()
	c2.max_hp = 100; c2.hp = 10
	_check(c2.pick_ability_talent(&"ability_l4", &"wind_deeper"), "picks wind_deeper")
	_check(c2.apply_second_wind(2), "casts Second Wind (deeper)")
	_check(c2.hp == 55, "wind_deeper: Second Wind heals 45%% max HP (10 + 45 = 55, got %d)" % c2.hp)

	var c3: Combatant = _mk_warrior()
	c3.max_hp = 100; c3.hp = 10
	_check(c3.pick_ability_talent(&"ability_l4", &"wind_empowering"), "picks wind_empowering")
	_check(c3.apply_second_wind(2), "casts Second Wind (empowering)")
	var emp: Effect = c3._find_effect(&"empowered")
	_check(emp != null and emp.duration == 2, "wind_empowering: Empowered lasts 2 turns (got %d)" % (emp.duration if emp != null else -1))

	# Desperate Recovery: the cooldown discount only applies while at/below Last Stand's threshold
	# AT THE MOMENT OF CASTING (checked before this cast's own heal changes hp).
	var c4: Combatant = _mk_warrior()
	c4.max_hp = 100; c4.hp = 25
	_check(c4.pick_ability_talent(&"ability_l4", &"wind_desperate_recovery"), "picks wind_desperate_recovery")
	_check(c4.ability_talent_cooldown_delta(&"second_wind") == -2, "wind_desperate_recovery: -2 cooldown while at/below 30% HP (got %d)" % c4.ability_talent_cooldown_delta(&"second_wind"))

	var c5: Combatant = _mk_warrior()
	c5.max_hp = 100; c5.hp = 50
	_check(c5.pick_ability_talent(&"ability_l4", &"wind_desperate_recovery"), "picks wind_desperate_recovery")
	_check(c5.ability_talent_cooldown_delta(&"second_wind") == 0, "wind_desperate_recovery: no discount above the threshold (got %d)" % c5.ability_talent_cooldown_delta(&"second_wind"))

	# Mutual exclusion: only 1 pick per row.
	var c6: Combatant = _mk_warrior()
	_check(c6.pick_ability_talent(&"ability_l4", &"wind_deeper"), "first pick on the Second Wind row succeeds")
	_check(not c6.pick_ability_talent(&"ability_l4", &"wind_empowering"), "a second pick on an already-filled row is rejected (cap of 1/row)")
```

Also update `_test_options_for_shape()`'s `all_ids` array (line 37): replace
`&"wind_deeper", &"wind_empowering", &"wind_swift",` with
`&"wind_deeper", &"wind_empowering", &"wind_desperate_recovery",`.

In `tests/test_ability_menu_state.gd`, replace lines 89-91 (the `wind_swift` preview check) with a
Vanguard `stance_swift` check instead — the mechanic this test actually exercises (a picked
Ability Talent cooldown discount showing up live in the menu preview) is generic, not
Warrior-specific, and Vanguard's Mountain Stance still has a static swift-cooldown talent:

```gdscript
	var vanguard2: Combatant = ClassLibrary.make(&"vanguard").build_combatant(true)
	vanguard2.level = Combatant.MAX_LEVEL
	_check(AbilityMenuPanel.cooldown_text(vanguard2, &"mountain_stance") == "Ready — 4-turn cooldown after use", "baseline Mountain Stance cooldown preview (no talent picked)")
	_check(vanguard2.pick_ability_talent(&"ability_l4", &"stance_swift"), "picks stance_swift")
	_check(AbilityMenuPanel.cooldown_text(vanguard2, &"mountain_stance") == "Ready — 3-turn cooldown after use", "stance_swift: Mountain Stance's live cooldown preview shows the discounted 3 turns, not the stale 4")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_warrior.gd`
and `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_menu_state.gd`
Expected: FAIL — heal is still 40%/50 not 45%/55, Empowered duration still 1, `wind_desperate_recovery`
not a recognized option.

- [ ] **Step 3: Write minimal implementation**

In `combat/combatant.gd`, replace `apply_second_wind()`:

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

In `ability_talent_cooldown_delta()`, replace the `&"second_wind":` arm:

```gdscript
			&"second_wind":
				if not has_ability_talent(&"wind_desperate_recovery"):
					return 0
				var stand_threshold: float = 0.40 if has_ability_talent(&"stand_wider") else 0.30
				return -2 if (float(hp) / float(maxi(max_hp, 1))) <= stand_threshold else 0
```

In `combat/ability_talent_library.gd`'s warrior `&"ability_l4"` row:

```gdscript
				&"ability_l4":
					var w1: AbilityTalentOption = AbilityTalentOption.new()
					w1.id = &"wind_deeper"; w1.row_id = row_id
					w1.display_name = "Deeper Wind"
					w1.description = "Second Wind heals 45% max HP (was 40%)."
					var w2: AbilityTalentOption = AbilityTalentOption.new()
					w2.id = &"wind_empowering"; w2.row_id = row_id
					w2.display_name = "Empowering Wind"
					w2.description = "Second Wind also grants Empowered (x1.15 outgoing damage) for 2 turns (was 1)."
					var w3: AbilityTalentOption = AbilityTalentOption.new()
					w3.id = &"wind_desperate_recovery"; w3.row_id = row_id
					w3.display_name = "Desperate Recovery"
					w3.description = "Casting Second Wind at or below Last Stand's HP threshold instantly cuts its cooldown by 2 turns."
					return [w1, w2, w3]
```

In `combat/main_phase_plan.gd`, restructure the `if staged_extra_ability_id != &"":` block (~lines
507-561) so `talent_cd` is computed before the dispatch match, not after:

```gdscript
	if staged_extra_ability_id != &"":
		var def: AbilityDef = combatant.find_extra_ability(staged_extra_ability_id)
		var extra_talent_cost: int = def.cost + combatant.ability_talent_cost_delta(staged_extra_ability_id)
		var talent_cd: int = -1
		if def != null and def.cooldown_turns > 0:
			talent_cd = maxi(1, def.cooldown_turns + combatant.ability_talent_cooldown_delta(staged_extra_ability_id))
		match staged_extra_ability_id:
			# ... every existing arm in this match is UNCHANGED, keep them verbatim ...
		if talent_cd >= 0:
			combatant.start_cooldown(staged_extra_ability_id, talent_cd)
```

(Keep every existing `match` arm's body byte-for-byte identical — only the surrounding
`var def`/`var talent_cd`/`if talent_cd >= 0: start_cooldown(...)` scaffolding moves. Do not
re-derive `def`, `extra_talent_cost`, or `talent_cd` a second time anywhere in this block.)

- [ ] **Step 4: Run test to verify it passes**

Run both test files again as in Step 2.
Expected: all `ok` lines, no `FAIL`, in both files.

- [ ] **Step 5: Grep for the retired `wind_swift` id project-wide**

Run: `grep -rn "wind_swift" --include=*.gd .` — should now show zero hits.

- [ ] **Step 6: Run the FULL test suite once, not just these two files**

The `main_phase_plan.gd` reorder touches the shared commit path every extra ability goes through.
Run every existing headless test file under `tests/` that exercises `MainPhasePlan.commit()` for
a non-Warrior extra ability with a cooldown (at minimum: `tests/test_mountain_stance.gd`,
`tests/test_bastion.gd`, `tests/test_riposte_storm.gd`, `tests/test_quake_slam.gd` if it has a
cooldown, `tests/test_crippling_shot.gd`) to confirm the reorder is a pure no-op for them.

- [ ] **Step 7: Commit**

```bash
git add combat/combatant.gd combat/ability_talent_library.gd combat/main_phase_plan.gd tests/test_ability_talents_warrior.gd tests/test_ability_menu_state.gd
git commit -m "feat(warrior): Second Wind row — 45% heal, 2-turn Empowered, Desperate Recovery"
```

---

### Task 6: Last Stand row — baseline bump + Vengeful Stand

**Files:**
- Modify: `combat/combatant.gd:1223-1250` (`passive_outgoing_multiplier()`, `&"last_stand"` arm)
- Modify: `combat/ability_talent_library.gd` (warrior `&"passive"` row)
- Test: `tests/test_ability_talents_warrior.gd` (`_test_last_stand_row()`)
- Test: `tests/test_passive_last_stand.gd`

**Interfaces:**
- Consumes: `Combatant.passive_outgoing_multiplier(defender: Combatant = null) -> float` (existing
  signature, already takes `defender`).

- [ ] **Step 1: Write the failing test**

In `tests/test_passive_last_stand.gd`, change line 12's expected value and add a Vengeful Stand
case:

```gdscript
func _init() -> void:
	var c: Combatant = Combatant.new()
	c.passive_ability_id = &"last_stand"
	c.level = 5
	c.max_hp = 100
	c.hp = 30  # exactly 30% — the threshold is inclusive
	_check(c.passive_outgoing_multiplier() == 1.24, "Last Stand: +24% at exactly 30% HP")
	c.hp = 31
	_check(c.passive_outgoing_multiplier() == 1.0, "Last Stand: neutral just above 30% HP")
	c.level = 4
	c.hp = 10
	_check(c.passive_outgoing_multiplier() == 1.0, "Last Stand: inactive below L5 even at low HP")

	var wc: CharacterClass = ClassLibrary.make(&"warrior")
	_check(wc.passive_ability_id == &"last_stand", "Warrior's CharacterClass carries the passive id")
	var pc: Combatant = wc.build_combatant(true)
	_check(pc.passive_ability_id == &"last_stand", "build_combatant() copies passive_ability_id")

	# Vengeful Stand: triggers off the DEFENDER's Bleed+Sundered state, independent of self HP.
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

In `tests/test_ability_talents_warrior.gd`'s `_test_last_stand_row()`, remove the `stand_deeper`
sub-test (its case around lines 165-169) since `stand_deeper` is retired, and update
`_test_options_for_shape()`'s `all_ids` array (line 38): replace
`&"stand_deeper", &"stand_wider", &"stand_guarded",` with
`&"stand_vengeful", &"stand_wider", &"stand_guarded",`.

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_passive_last_stand.gd`
and `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_warrior.gd`
Expected: FAIL — baseline is still 1.2 not 1.24; `stand_vengeful` not a recognized option.

- [ ] **Step 3: Write minimal implementation**

In `combat/combatant.gd`'s `passive_outgoing_multiplier()`, replace the `&"last_stand":` arm:

```gdscript
		&"last_stand":
			var threshold: float = 0.40 if has_ability_talent(&"stand_wider") else 0.30
			var bonus: float = 1.24
			var self_triggered: bool = (float(hp) / float(maxi(max_hp, 1))) <= threshold
			var vengeful_triggered: bool = has_ability_talent(&"stand_vengeful") and defender != null and defender.has_effect(&"bleed") and defender.has_effect(&"sundered")
			return bonus if (self_triggered or vengeful_triggered) else 1.0
```

In `combat/ability_talent_library.gd`'s warrior `&"passive"` row:

```gdscript
				&"passive":
					var p1: AbilityTalentOption = AbilityTalentOption.new()
					p1.id = &"stand_wider"; p1.row_id = row_id
					p1.display_name = "Wider Window"
					p1.description = "Last Stand activates at or below 40% HP (was 30%)."
					var p2: AbilityTalentOption = AbilityTalentOption.new()
					p2.id = &"stand_guarded"; p2.row_id = row_id
					p2.display_name = "Guarded Stand"
					p2.description = "While Last Stand is active, also reduce incoming damage by 10%."
					var p3: AbilityTalentOption = AbilityTalentOption.new()
					p3.id = &"stand_vengeful"; p3.row_id = row_id
					p3.display_name = "Vengeful Stand"
					p3.description = "Last Stand's damage bonus also activates against any target that carries BOTH Bleed and Sundered, regardless of your own HP."
					return [p1, p2, p3]
```

- [ ] **Step 4: Run test to verify it passes**

Run both test files again as in Step 2.
Expected: all `ok` lines, no `FAIL`, in both files.

- [ ] **Step 5: Grep for the retired `stand_deeper` id project-wide**

Run: `grep -rn "stand_deeper" --include=*.gd .` — should now show zero hits.

- [ ] **Step 6: Commit**

```bash
git add combat/combatant.gd combat/ability_talent_library.gd tests/test_ability_talents_warrior.gd tests/test_passive_last_stand.gd
git commit -m "feat(warrior): Last Stand row — baseline +24%, Vengeful Stand (Bleed+Sundered synergy)"
```

---

### Task 7: Wild row — Executioner's Wild

**Files:**
- Modify: `combat/combatant.gd:1193-1200` (`outgoing_damage_multiplier()` — add the Executioner's
  Wild check alongside Vengeful Guard's, from Task 4)
- Modify: `combat/ability_talent_library.gd` (warrior `&"ultimate"` row)
- Test: `tests/test_ability_talents_warrior.gd` (`_test_wild_row()`)

**Interfaces:**
- Consumes: `Combatant.sticky_wild_spins_remaining: int` (existing field, already read by
  combat.gd's Bleeding Wild block and by `wild_reel_indices()`).

- [ ] **Step 1: Write the failing test**

In `tests/test_ability_talents_warrior.gd`'s `_test_wild_row()`, replace the `wild_truer` sub-test
(the block around lines 195-201) with:

```gdscript
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
```

Also update `_test_options_for_shape()`'s `all_ids` array (line 39): replace
`&"wild_truer", &"wild_bleeding", &"wild_lasting",` with
`&"wild_executioner", &"wild_bleeding", &"wild_lasting",`.

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_warrior.gd`
Expected: FAIL — `wild_executioner` not a recognized option, no bonus wired up yet.

- [ ] **Step 3: Write minimal implementation**

In `combat/combatant.gd`'s `outgoing_damage_multiplier()`, extend the `class_id == &"warrior"`
block added in Task 4:

```gdscript
	if class_id == &"warrior":
		if has_ability_talent(&"guard_vengeful") and has_effect(&"guarded") and defender != null and (defender.has_effect(&"bleed") or defender.has_effect(&"sundered")):
			total *= 1.20
		if has_ability_talent(&"wild_executioner") and sticky_wild_spins_remaining > 0 and defender != null and defender.has_effect(&"bleed") and defender.has_effect(&"sundered"):
			total *= 1.25
```

In `combat/ability_talent_library.gd`'s warrior `&"ultimate"` row:

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

- [ ] **Step 4: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_warrior.gd`
Expected: all `ok` lines, no `FAIL`.

- [ ] **Step 5: Grep for the retired `wild_truer` id project-wide**

Run: `grep -rn "wild_truer" --include=*.gd .` — should now show zero hits.

- [ ] **Step 6: Commit**

```bash
git add combat/combatant.gd combat/ability_talent_library.gd tests/test_ability_talents_warrior.gd
git commit -m "feat(warrior): Wild row — Executioner's Wild (Bleed+Sundered synergy)"
```

---

### Task 8: Final regression sweep

**Files:**
- No production changes expected — this task is verification-only, with fixes applied inline if
  the sweep finds anything.

- [ ] **Step 1: Grep for all 8 retired ids across the ENTIRE repo (not just `.gd` files — plan docs
  and design bible files may also reference them for historical reasons, which is fine, but
  distinguish those from anything still LIVE in `combat/` or `tests/`)**

Run: `grep -rn "rend_efficient\|sunder_efficient\|sunder_lingering\|guard_cleansing\|guard_lasting\|wind_swift\|stand_deeper\|wild_truer" combat/ tests/`
Expected: zero hits. If anything turns up, fix it now (this exact failure mode — a stray reference
surviving in an untouched test file — bit the Harvester rank-2 pass multiple times per
`docs/superpowers/specs/2026-09-02-harvester-rank2-content-design.md`'s own retrospective).

- [ ] **Step 2: Run every test file this plan touched, in one pass**

Run each of these and confirm zero `FAIL`/`SCRIPT ERROR` in the output (grep the actual output text,
per this project's own documented "silent script-error-exits-zero" gotcha — don't trust exit codes
alone):

```
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_new_effects.gd
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_warrior.gd
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_menu_state.gd
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_passive_last_stand.gd
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_mountain_stance.gd
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_bastion.gd
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_sundering_strike.gd
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_heroic_guard.gd
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_second_wind.gd
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ultimate_variants.gd
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_extra_ability_ultimate_conflict.gd
..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_payline_and_splash_damage_multiplier.gd
```

If any of these fail unexpectedly (particularly `test_heroic_guard.gd`/`test_second_wind.gd`/
`test_sundering_strike.gd`/`test_ultimate_variants.gd`/`test_extra_ability_ultimate_conflict.gd`,
which weren't touched by name in Tasks 2-7 but exercise the same production functions), read the
failure, fix the root cause in the relevant production file, and re-run — do not edit the test's
expectation unless the OLD expectation was actually asserting the retired/changed behavior on
purpose.

- [ ] **Step 3: Confirm no test relies on `EffectLibrary.make(&"guarded")`'s shared default having
  changed**

Run: `grep -rn "EffectLibrary.make(&\"guarded\")" tests/` and spot-check that
`tests/test_payline_and_splash_damage_multiplier.gd`'s splash-damage assertions
(`ceili(ceili(40 * 0.5) * 0.75)`) are UNCHANGED and still passing — this test builds Guarded
directly via `EffectLibrary.make()`, not via `apply_heroic_guard()`, so it must still see 0.75.

- [ ] **Step 4: Commit (only if Step 2 required fixes)**

```bash
git add -A
git commit -m "test(warrior): fix regressions surfaced by the talent-tree depth rework's final sweep"
```

(Skip this commit entirely if Step 2 found nothing to fix — an empty final-sweep task doesn't need
a commit.)
