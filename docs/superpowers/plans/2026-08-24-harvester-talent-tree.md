# Harvester Talent Tree Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the Harvester (`class_id = &"summoner"`) a real 6-row, 18-option talent tree plus a
new always-on passive ("Harvest's Favor"), matching the depth the other 7 classes already have.

**Architecture:** A new `harvest_favor` passive hooks into the existing per-landed-reel loop in
`combat.gd::_apply_attack()` and the per-combatant Upkeep handler in `_on_phase_changed()`. The 18
talent options are registered as plain data in `AbilityTalentLibrary.options_for()` (mirrors every
other class). Each option's actual behavior is a `has_ability_talent(&"...")` branch inside the
existing minion-stage functions (`_run_ember_stage`, `_run_dew_stage`, `_run_misfortune_stage`,
`_run_hasty_stage`) and `_apply_grand_sacrifice()`, all in `combat/combat.gd`. One general
`Combatant.attach_effect()` bug fix is bundled in because Nightshade/Strawfellow's Due talent
content makes it reachable for the first time.

**Tech Stack:** Godot 4.6.3, GDScript, headless `SceneTree` tests run via
`Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_X.gd`
from `C:\bunnies\bunnies-main\` (one directory above this repo).

**Spec:** `docs/superpowers/specs/2026-08-24-harvester-talent-tree-design.md`

## Global Constraints

- Language: GDScript only, no C#. Static typing everywhere (typed vars, typed signatures).
- All new balance numbers (percentages, flat amounts, turn counts) are `[ASSUMPTION]` placeholders
  per CLAUDE.md §4 — implement as plain constants/fields, easy to retune, never hard-branch on them.
- No `ability_l3` (Nightshade) or `ability_l4` (Wheat) talent may extend that minion's own lifespan
  (spec §3) — do not add one even if it looks tempting during implementation.
- Round all combat damage/heal math up (`ceili`/`roundf`+ceiling per existing convention) — match
  whatever rounding the surrounding existing code in the same function already uses; don't introduce
  a new rounding convention.
- Every new test file follows the existing headless `SceneTree` harness pattern (see Task 1's test
  for the base shape); run each new/modified test file after writing it and before moving on.
- Commit after each task with a `feat(harvester):` or `fix(combatant):` prefix matching this repo's
  existing commit style (see `git log --oneline` for examples).

---

### Task 1: `Combatant.attach_effect()` merge-strength fix

**Files:**
- Modify: `combat/combatant.gd:1316-1344` (`attach_effect()`)
- Test: `tests/test_attach_effect_merge_strength.gd` (new)

**Interfaces:**
- Consumes: `Effect` (`combat/resources/effect.gd`) fields `id`, `kind`, `dot_base_damage`,
  `magnitude`, `duration`; `Effect.Kind` enum (`INITIATIVE_MOD, DAMAGE_OVER_TIME, MULTIPLIER_EDIT,
  REEL_FACE_EDIT`); `Combatant.active_effects: Array[Effect]`, `Combatant._find_effect(id) ->
  Effect`.
- Produces: `attach_effect()`'s new behavior — every later task's stage/Ultimate/passive code that
  calls `attach_effect()` on a shared-id effect (`&"cursed"`, `&"jinxed"`, etc.) can now rely on the
  STRONGER of the two `dot_base_damage`/`magnitude` values surviving a merge.

- [ ] **Step 1: Write the failing test**

Create `tests/test_attach_effect_merge_strength.gd`:

```gdscript
extends SceneTree

# Headless test for the attach_effect() merge-strength fix (2026-08-24 harvester-talent-tree spec
# §2). Proves that merging an effect sharing an id with an already-active one keeps whichever side
# is STRONGER (dot_base_damage for DAMAGE_OVER_TIME, magnitude for every other Kind), while still
# refreshing duration/stacks from the incoming effect, regardless of merge order.
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_attach_effect_merge_strength.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _init() -> void:
	_test_dot_weaker_then_stronger()
	_test_dot_stronger_then_weaker()
	_test_multiplier_edit_weaker_then_stronger()
	_test_duration_and_stacks_still_refresh()
	quit(_failures)

func _test_dot_weaker_then_stronger() -> void:
	var c: Combatant = Combatant.new()
	var weak := Effect.new()
	weak.id = &"cursed"; weak.kind = Effect.Kind.DAMAGE_OVER_TIME; weak.dot_base_damage = 12.0
	weak.duration = 3
	c.attach_effect(weak)
	var strong := Effect.new()
	strong.id = &"cursed"; strong.kind = Effect.Kind.DAMAGE_OVER_TIME; strong.dot_base_damage = 15.0
	strong.duration = 3
	c.attach_effect(strong)
	var merged: Effect = c._find_effect(&"cursed")
	_check(merged != null, "cursed effect present after merge")
	_check(is_equal_approx(merged.dot_base_damage, 15.0), "weaker-then-stronger: kept the STRONGER 15.0 dot_base_damage (got %.1f)" % merged.dot_base_damage)

func _test_dot_stronger_then_weaker() -> void:
	var c: Combatant = Combatant.new()
	var strong := Effect.new()
	strong.id = &"cursed"; strong.kind = Effect.Kind.DAMAGE_OVER_TIME; strong.dot_base_damage = 15.0
	strong.duration = 3
	c.attach_effect(strong)
	var weak := Effect.new()
	weak.id = &"cursed"; weak.kind = Effect.Kind.DAMAGE_OVER_TIME; weak.dot_base_damage = 12.0
	weak.duration = 3
	c.attach_effect(weak)
	var merged: Effect = c._find_effect(&"cursed")
	_check(is_equal_approx(merged.dot_base_damage, 15.0), "stronger-then-weaker: KEEPS the stronger 15.0, doesn't downgrade to 12.0 (got %.1f)" % merged.dot_base_damage)

func _test_multiplier_edit_weaker_then_stronger() -> void:
	var c: Combatant = Combatant.new()
	var weak := Effect.new()
	weak.id = &"sundered"; weak.kind = Effect.Kind.MULTIPLIER_EDIT; weak.magnitude = 1.25
	weak.duration = 2
	c.attach_effect(weak)
	var strong := Effect.new()
	strong.id = &"sundered"; strong.kind = Effect.Kind.MULTIPLIER_EDIT; strong.magnitude = 1.5
	strong.duration = 2
	c.attach_effect(strong)
	var merged: Effect = c._find_effect(&"sundered")
	_check(is_equal_approx(merged.magnitude, 1.5), "non-DoT kind: kept the STRONGER 1.5 magnitude (got %.2f)" % merged.magnitude)

func _test_duration_and_stacks_still_refresh() -> void:
	var c: Combatant = Combatant.new()
	var first := Effect.new()
	first.id = &"cursed"; first.kind = Effect.Kind.DAMAGE_OVER_TIME; first.dot_base_damage = 12.0
	first.duration = 1; first.max_stacks = 3
	c.attach_effect(first)
	var second := Effect.new()
	second.id = &"cursed"; second.kind = Effect.Kind.DAMAGE_OVER_TIME; second.dot_base_damage = 10.0
	second.duration = 5; second.max_stacks = 3
	c.attach_effect(second)
	var merged: Effect = c._find_effect(&"cursed")
	_check(merged.duration == 5, "duration still refreshes to the incoming value even when strength doesn't (got %d)" % merged.duration)
	_check(merged.stacks == 2, "stacks still increments on merge (got %d)" % merged.stacks)
	_check(is_equal_approx(merged.dot_base_damage, 12.0), "weaker second attach doesn't downgrade dot_base_damage (got %.1f)" % merged.dot_base_damage)
```

- [ ] **Step 2: Run test to verify it fails**

Run (from `C:\bunnies\bunnies-main\`):
`Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_attach_effect_merge_strength.gd`
Expected: FAIL on `_test_dot_stronger_then_weaker` and `_test_multiplier_edit_weaker_then_stronger`
(the current code silently keeps the OLD/first value regardless of strength, so the
weaker-then-stronger case looks correct by accident but stronger-then-weaker exposes the bug).

- [ ] **Step 3: Fix `attach_effect()`**

Replace `combat/combatant.gd:1333-1338`:

```gdscript
	var existing: Effect = _find_effect(effect.id)
	if existing != null:
		existing.add_stack()                 # no-op at cap / for max_stacks == 1
		existing.duration = effect.duration   # refresh to the incoming duration
		recompute_initiative()
		return
```

with:

```gdscript
	var existing: Effect = _find_effect(effect.id)
	if existing != null:
		existing.add_stack()                 # no-op at cap / for max_stacks == 1
		existing.duration = effect.duration   # refresh to the incoming duration
		# Merge-strength fix (2026-08-24 harvester-talent-tree spec §2): keep whichever side is
		# STRONGER, not whichever was attached first — a later, weaker reapplication must not
		# downgrade an already-stronger active effect, and a later, stronger one must win.
		if existing.kind == Effect.Kind.DAMAGE_OVER_TIME:
			existing.dot_base_damage = maxf(existing.dot_base_damage, effect.dot_base_damage)
		else:
			existing.magnitude = maxf(existing.magnitude, effect.magnitude)
		recompute_initiative()
		return
```

Also update the stale comment directly above (lines ~1326-1332) — replace the whole
"NOTE (final-review M1, currently unreachable but latent)" block with:

```gdscript
	# Merge by id: re-applying an effect already active never creates a second instance (this is
	# what prevents unbounded additive stacking). A stacking effect adds a stack (diminishing,
	# capped); a non-stacking one is a no-op on stacks. Duration always refreshes to the incoming
	# value; dot_base_damage/magnitude keep whichever side is STRONGER (2026-08-24 harvester-talent-
	# tree spec §2 fix) — other fields (immune_effect_ids, thorns_pct, grants_stun_immunity, etc.)
	# are still kept from the EXISTING instance, not the incoming one.
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2. Expected: all 4 checks in each of the 4 test functions pass (0 failures).

- [ ] **Step 5: Commit**

```bash
git add combat/combatant.gd tests/test_attach_effect_merge_strength.gd
git commit -m "fix(combatant): attach_effect() merge keeps the stronger dot/magnitude, not the older one"
```

---

### Task 2: Harvest's Favor — base passive (Touch-Me-Not/Lotus/Nightshade/Wheat branches, no talent upgrades yet)

**Files:**
- Modify: `combat/class_library.gd:197-226` (`&"summoner"` case — add `passive_ability_id`)
- Modify: `combat/combatant.gd` (new method `harvest_favor_on_hit`, new field
  `pending_delayed_bloom_damage` used later by Task 5, not this task)
- Modify: `combat/combat.gd:2636-2720`-ish (`_apply_attack()` — add the trigger call)
- Test: `tests/test_harvest_favor_passive.gd` (new)

**Interfaces:**
- Consumes: `Combatant.active_minion: Combatant` (null when no minion), `Combatant.minion_type:
  StringName` (on the minion itself — `&"ember"|"dew"|"misfortune"|"hasty"`),
  `Combatant.cleanse_oldest_debuff()` is NOT used here (Harvest's Favor extends, not cleanses),
  `Combatant.has_effect(id) -> bool`, `Combatant._find_effect(id) -> Effect`,
  `Combatant.attach_effect(effect)`, `EffectLibrary.make(id) -> Effect`, `_enemies_of(c)`/
  `_allies_of(c)` (combat.gd), `ReelFace.ResultTier` enum (`SUCCESS`, `CRIT_SUCCESS`).
- Produces: `Combatant.harvest_favor_on_hit(target: Combatant, allies: Array[Combatant]) -> void` —
  called once per landed SUCCESS/CRIT_SUCCESS reel by `_apply_attack()`. Later tasks (5, 8, 9) add
  more branches inside this same method.

- [ ] **Step 1: Write the failing test**

Create `tests/test_harvest_favor_passive.gd`:

```gdscript
extends SceneTree

# Headless test for the Harvest's Favor passive base behavior (2026-08-24 harvester-talent-tree
# spec §1) — no minion active = no-op; each minion type's on-hit bonus fires from a direct
# harvest_favor_on_hit() call (mirrors this codebase's precedent of unit-testing a Combatant-level
# hook directly rather than driving a full spin — see tests/test_ability_talents_warrior.gd's header
# comment on Bleeding Wild for the same rationale).
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_harvest_favor_passive.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _mk_harvester() -> Combatant:
	var c: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	c.level = Combatant.MAX_LEVEL
	return c

func _init() -> void:
	_test_passive_id_set()
	_test_no_minion_no_effect()
	_test_ember_active_deals_bonus_damage()
	_test_dew_active_heals_lowest_hp_ally()
	_test_misfortune_active_extends_debuff()
	_test_hasty_active_extends_own_buff()
	quit(_failures)

func _test_passive_id_set() -> void:
	var c: Combatant = _mk_harvester()
	_check(c.passive_ability_id == &"harvest_favor", "Harvester's passive_ability_id is harvest_favor")

func _test_no_minion_no_effect() -> void:
	var c: Combatant = _mk_harvester()
	var target: Combatant = Combatant.new()
	target.base_max_hp = 50; target.apply_stats(); target.start_combat()
	var hp_before: int = target.hp
	c.harvest_favor_on_hit(target, [c])
	_check(target.hp == hp_before, "no active minion: harvest_favor_on_hit is a no-op")

func _test_ember_active_deals_bonus_damage() -> void:
	var c: Combatant = _mk_harvester()
	c.active_minion = MinionLibrary.make(false, &"ember")
	var target: Combatant = Combatant.new()
	target.base_max_hp = 50; target.apply_stats(); target.start_combat()
	var hp_before: int = target.hp
	c.harvest_favor_on_hit(target, [c])
	_check(target.hp < hp_before, "Touch-Me-Not active: harvest_favor_on_hit dealt bonus damage to the target")

func _test_dew_active_heals_lowest_hp_ally() -> void:
	var c: Combatant = _mk_harvester()
	c.active_minion = MinionLibrary.make(false, &"dew")
	var low_ally: Combatant = Combatant.new()
	low_ally.base_max_hp = 50; low_ally.apply_stats(); low_ally.start_combat(); low_ally.hp = 10
	var high_ally: Combatant = Combatant.new()
	high_ally.base_max_hp = 50; high_ally.apply_stats(); high_ally.start_combat(); high_ally.hp = 45
	var enemy: Combatant = Combatant.new()
	enemy.base_max_hp = 50; enemy.apply_stats(); enemy.start_combat()
	c.harvest_favor_on_hit(enemy, [c, low_ally, high_ally])
	_check(low_ally.hp > 10, "Lotus active: harvest_favor_on_hit healed the lowest-HP ally (got %d)" % low_ally.hp)
	_check(high_ally.hp == 45, "Lotus active: harvest_favor_on_hit left the higher-HP ally untouched")

func _test_misfortune_active_extends_debuff() -> void:
	var c: Combatant = _mk_harvester()
	c.active_minion = MinionLibrary.make(false, &"misfortune")
	var target: Combatant = Combatant.new()
	target.base_max_hp = 50; target.apply_stats(); target.start_combat()
	var weakened: Effect = EffectLibrary.make(&"weakened")
	weakened.duration = 1
	target.attach_effect(weakened)
	c.harvest_favor_on_hit(target, [c])
	var found: Effect = target._find_effect(&"weakened")
	_check(found != null and found.duration == 2, "Nightshade active: extended the target's Weakened duration by 1 (got %d)" % (found.duration if found != null else -1))

func _test_hasty_active_extends_own_buff() -> void:
	var c: Combatant = _mk_harvester()
	c.active_minion = MinionLibrary.make(false, &"hasty")
	var haste: Effect = EffectLibrary.make(&"empowered")
	haste.duration = 1
	c.attach_effect(haste)
	var target: Combatant = Combatant.new()
	target.base_max_hp = 50; target.apply_stats(); target.start_combat()
	c.harvest_favor_on_hit(target, [c])
	var found: Effect = c._find_effect(&"empowered")
	_check(found != null and found.duration == 2, "Wheat active: extended the HARVESTER'S OWN buff duration by 1 (got %d)" % (found.duration if found != null else -1))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_harvest_favor_passive.gd`
Expected: FAIL — `passive_ability_id` isn't set, and `harvest_favor_on_hit` doesn't exist yet (a
script error attempting to call an undefined method; count this as the expected failing state).

- [ ] **Step 3: Register the passive on the class**

In `combat/class_library.gd`, inside the `&"summoner"` case (around line 218, right after
`c.ability_id = &"ember_minion"; c.ability_cost = 4; c.ability_resource = &"mana"`), add:

```gdscript
			c.passive_ability_id = &"harvest_favor"
```

- [ ] **Step 4: Add `harvest_favor_on_hit()` to `Combatant`**

In `combat/combatant.gd`, add this new method near the other passive hooks (e.g. right after
`passive_on_payline_scored`, ~line 1254):

```gdscript
## Harvest's Favor (Harvester passive, 2026-08-24 harvester-talent-tree spec §1) — fires once per
## landed SUCCESS/CRIT_SUCCESS weapon-reel hit while a minion is active. No-op with no active
## minion. [param target] is the hit's target; [param allies] is every ally to consider for the
## Lotus branch (pass the party including this combatant). Row-5 talent upgrades (Amplified Bond,
## Favor Unleashed, Spirit Surge) extend this method in Task 9.
func harvest_favor_on_hit(target: Combatant, allies: Array[Combatant]) -> void:
	if passive_ability_id != &"harvest_favor" or active_minion == null or not active_minion.is_alive():
		return
	match active_minion.minion_type:
		&"ember":
			if target != null and target.is_alive():
				target.take_damage(HARVEST_FAVOR_EMBER_BONUS_DAMAGE)
		&"dew":
			var lowest: Combatant = null
			for a: Combatant in allies:
				if a == null or not a.is_alive() or a.is_minion:
					continue
				if lowest == null or a.hp < lowest.hp:
					lowest = a
			if lowest != null:
				lowest.heal(HARVEST_FAVOR_DEW_HEAL)
		&"misfortune":
			if target == null or not target.is_alive():
				return
			for debuff_id: StringName in [&"weakened", &"sundered", &"cursed"]:
				var e: Effect = target._find_effect(debuff_id)
				if e != null:
					e.duration += 1
		&"hasty":
			for e: Effect in active_effects:
				if e != null and e.beneficial:
					e.duration += 1
```

Add the two new constants near the top of `combat/combatant.gd` alongside other `[ASSUMPTION]`
tunables (search for an existing `const ... : int = ` block, e.g. near
`GRAND_SACRIFICE_EMBER_BURST` if it's declared here, otherwise add a small new block):

```gdscript
## [ASSUMPTION] Harvest's Favor per-hit bonuses — tune by playtest (2026-08-24 spec §10).
const HARVEST_FAVOR_EMBER_BONUS_DAMAGE: int = 4
const HARVEST_FAVOR_DEW_HEAL: int = 3
```

Note: the `&"hasty"` branch above extends EVERY beneficial effect on the caster by 1 turn (matches
the spec's "the Harvester's own copy of a Wheat-applied buff" — since Wheat only ever attaches
`hasty_initiative`/`hasty_regen`/`empowered`/`reel_surge`, all beneficial, to whoever's active, this
is equivalent in practice and avoids hardcoding those 4 ids by name).

- [ ] **Step 5: Wire the trigger into `_apply_attack()`**

In `combat/combat.gd`, inside `_apply_attack()`'s `if attack.final_damage > 0: for t: Combatant in
targets:` loop (the block starting at line 2647), add the Harvest's Favor call right after the
existing `take_damage`/reel-surge-overflow block (after line 2660, before the loop's closing brace).
Insert:

```gdscript
			# Harvest's Favor (2026-08-24 harvester-talent-tree spec §1): fires once per landed
			# SUCCESS/CRIT_SUCCESS hit on EVERY reel this turn, including ability/buff-granted extra
			# reels (reel_surge, etc.) since this loop runs once per _apply_attack() call and
			# _apply_attack() is bound per-reel for the whole turn_reels array, not just the base
			# weapon loadout.
			if _attacker.passive_ability_id == &"harvest_favor" and (attack.face.result_tier == ReelFace.ResultTier.SUCCESS or attack.face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS):
				_attacker.harvest_favor_on_hit(t, _allies_of(_attacker))
```

- [ ] **Step 6: Run test to verify it passes**

Run the same command as Step 2. Expected: all 6 checks pass.

- [ ] **Step 7: Commit**

```bash
git add combat/class_library.gd combat/combatant.gd combat/combat.gd tests/test_harvest_favor_passive.gd
git commit -m "feat(harvester): add Harvest's Favor passive base behavior"
```

---

### Task 3: Register all 18 `AbilityTalentOption`s for `&"summoner"`

**Files:**
- Modify: `combat/ability_talent_library.gd` (add a `&"summoner":` case to `options_for()`)
- Test: `tests/test_ability_talents_summoner.gd` (new — shape test only; mechanical behavior tests
  come in Tasks 4-8)

**Interfaces:**
- Consumes: `AbilityTalentOption` (`id`, `row_id`, `display_name`, `description` — all `String`/
  `StringName`), `AbilityTalentLibrary.ROW_IDS`.
- Produces: 18 option ids used by Tasks 4-8's `has_ability_talent()` checks:
  `ember_delayed_bloom`, `ember_overripe`, `ember_overgrown_roots`, `dew_evergreen_bloom`,
  `dew_twin_petal`, `dew_guardian_bloom`, `misfortune_withering_touch`,
  `misfortune_creeping_blight`, `misfortune_ill_fortune`, `hasty_bountiful_harvest`,
  `hasty_charged_growth`, `hasty_unshakeable_roots`, `harvest_favor_amplified_bond`,
  `harvest_favor_unleashed`, `harvest_favor_spirit_surge`, `strawfellow_petrifying_burst`,
  `strawfellow_undying_bloom`, `strawfellow_withering_doom`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_ability_talents_summoner.gd`:

```gdscript
extends SceneTree

# Headless test: the Harvester's 18 Ability Talent options (2026-08-24 harvester-talent-tree spec).
# Mirrors tests/test_ability_talents_warrior.gd's shape-check pattern — asserts each row has exactly
# 3 options, correct row_id, non-empty display_name/description, and the exact expected id set.
# Mechanical behavior (what each option actually changes) is tested per-row in later test files
# (test_harvest_favor_passive.gd, and new files added in Tasks 4-8).
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_summoner.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

const EXPECTED_IDS: Dictionary = {
	&"base_ability": [&"ember_delayed_bloom", &"ember_overripe", &"ember_overgrown_roots"],
	&"ability_l2": [&"dew_evergreen_bloom", &"dew_twin_petal", &"dew_guardian_bloom"],
	&"ability_l3": [&"misfortune_withering_touch", &"misfortune_creeping_blight", &"misfortune_ill_fortune"],
	&"ability_l4": [&"hasty_bountiful_harvest", &"hasty_charged_growth", &"hasty_unshakeable_roots"],
	&"passive": [&"harvest_favor_amplified_bond", &"harvest_favor_unleashed", &"harvest_favor_spirit_surge"],
	&"ultimate": [&"strawfellow_petrifying_burst", &"strawfellow_undying_bloom", &"strawfellow_withering_doom"],
}

func _test_options_for_shape() -> void:
	for row: StringName in AbilityTalentLibrary.ROW_IDS:
		var opts: Array[AbilityTalentOption] = AbilityTalentLibrary.options_for(&"summoner", row)
		_check(opts.size() == 3, "%s row has exactly 3 options (got %d)" % [row, opts.size()])
		var seen: Array[StringName] = []
		for o: AbilityTalentOption in opts:
			_check(o.row_id == row, "%s option %s carries the correct row_id" % [row, o.id])
			_check(o.display_name != "", "%s option %s has a non-empty display_name" % [row, o.id])
			_check(o.description != "", "%s option %s has a non-empty description" % [row, o.id])
			seen.append(o.id)
		for expected_id: StringName in EXPECTED_IDS[row]:
			_check(expected_id in seen, "%s row includes expected id %s" % [row, expected_id])

func _init() -> void:
	_test_options_for_shape()
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_ability_talents_summoner.gd`
Expected: FAIL — every row currently returns an empty array for `&"summoner"` (no case exists yet).

- [ ] **Step 3: Add the `&"summoner"` case**

In `combat/ability_talent_library.gd`, add a new `&"summoner":` branch to the top-level `match
class_id:` inside `options_for()` (add it after whichever class's case currently comes last —
order among classes doesn't matter, `match` doesn't require it):

```gdscript
		&"summoner":
			match row_id:
				&"base_ability":
					var e1: AbilityTalentOption = AbilityTalentOption.new()
					e1.id = &"ember_delayed_bloom"; e1.row_id = row_id
					e1.display_name = "Delayed Bloom"
					e1.description = "Touch-Me-Not's burst echoes for 50% of its value at the start of your next turn."
					var e2: AbilityTalentOption = AbilityTalentOption.new()
					e2.id = &"ember_overripe"; e2.row_id = row_id
					e2.display_name = "Overripe"
					e2.description = "If Touch-Me-Not's burst kills an enemy, the overkill damage splashes onto another random living enemy."
					var e3: AbilityTalentOption = AbilityTalentOption.new()
					e3.id = &"ember_overgrown_roots"; e3.row_id = row_id
					e3.display_name = "Overgrown Roots"
					e3.description = "Touch-Me-Not's stage-3 burst also applies Rooted to every enemy hit."
					return [e1, e2, e3]
				&"ability_l2":
					var d1: AbilityTalentOption = AbilityTalentOption.new()
					d1.id = &"dew_evergreen_bloom"; d1.row_id = row_id
					d1.display_name = "Evergreen Bloom"
					d1.description = "Lotus doesn't expire after stage 3 — it loops a reduced heal every round until killed or replaced."
					var d2: AbilityTalentOption = AbilityTalentOption.new()
					d2.id = &"dew_twin_petal"; d2.row_id = row_id
					d2.display_name = "Twin Petal Cleanse"
					d2.description = "From stage 2 onward, Lotus cleanses the two oldest debuffs per ally instead of one."
					var d3: AbilityTalentOption = AbilityTalentOption.new()
					d3.id = &"dew_guardian_bloom"; d3.row_id = row_id
					d3.display_name = "Guardian Bloom"
					d3.description = "Lotus's stage-3 Thorns buff also grants a small flat damage shield."
					return [d1, d2, d3]
				&"ability_l3":
					var m1: AbilityTalentOption = AbilityTalentOption.new()
					m1.id = &"misfortune_withering_touch"; m1.row_id = row_id
					m1.display_name = "Withering Touch"
					m1.description = "Nightshade's stage-3 Cursed also reduces the target's healing received."
					var m2: AbilityTalentOption = AbilityTalentOption.new()
					m2.id = &"misfortune_creeping_blight"; m2.row_id = row_id
					m2.display_name = "Creeping Blight"
					m2.description = "Nightshade's stage 3 also reapplies Weakened and Sundered alongside Cursed."
					var m3: AbilityTalentOption = AbilityTalentOption.new()
					m3.id = &"misfortune_ill_fortune"; m3.row_id = row_id
					m3.display_name = "Ill Fortune"
					m3.description = "Nightshade's stage 2 also applies Jinxed to every enemy hit."
					return [m1, m2, m3]
				&"ability_l4":
					var h1: AbilityTalentOption = AbilityTalentOption.new()
					h1.id = &"hasty_bountiful_harvest"; h1.row_id = row_id
					h1.display_name = "Bountiful Harvest"
					h1.description = "Wheat's stage-2 regen buff also refunds part of the cost of each affected ally's next ability."
					var h2: AbilityTalentOption = AbilityTalentOption.new()
					h2.id = &"hasty_charged_growth"; h2.row_id = row_id
					h2.display_name = "Charged Growth"
					h2.description = "Wheat's stage-3 extra reel is crit-biased for its duration."
					var h3: AbilityTalentOption = AbilityTalentOption.new()
					h3.id = &"hasty_unshakeable_roots"; h3.row_id = row_id
					h3.display_name = "Unshakeable Roots"
					h3.description = "Wheat's stage-1 Initiative buff also grants immunity to Slow and Rooted."
					return [h1, h2, h3]
				&"passive":
					var p1: AbilityTalentOption = AbilityTalentOption.new()
					p1.id = &"harvest_favor_amplified_bond"; p1.row_id = row_id
					p1.display_name = "Amplified Bond"
					p1.description = "Harvest's Favor's bonus scales up with your active minion's current stage."
					var p2: AbilityTalentOption = AbilityTalentOption.new()
					p2.id = &"harvest_favor_unleashed"; p2.row_id = row_id
					p2.display_name = "Favor Unleashed"
					p2.description = "Harvest's Favor also triggers, at reduced value, on a NEUTRAL-tier hit."
					var p3: AbilityTalentOption = AbilityTalentOption.new()
					p3.id = &"harvest_favor_spirit_surge"; p3.row_id = row_id
					p3.display_name = "Spirit Surge"
					p3.description = "Harvest's Favor guarantees one free proc at your own Upkeep each turn."
					return [p1, p2, p3]
				&"ultimate":
					var u1: AbilityTalentOption = AbilityTalentOption.new()
					u1.id = &"strawfellow_petrifying_burst"; u1.row_id = row_id
					u1.display_name = "Petrifying Burst"
					u1.description = "Strawfellow's Due (Touch-Me-Not) also guarantees a 1-turn Stun on the primary target."
					var u2: AbilityTalentOption = AbilityTalentOption.new()
					u2.id = &"strawfellow_undying_bloom"; u2.row_id = row_id
					u2.display_name = "Undying Bloom"
					u2.description = "Strawfellow's Due (Lotus) also cleanses all active debuffs from the whole party immediately."
					var u3: AbilityTalentOption = AbilityTalentOption.new()
					u3.id = &"strawfellow_withering_doom"; u3.row_id = row_id
					u3.display_name = "Withering Doom"
					u3.description = "Strawfellow's Due (Nightshade)'s improved Curse deals double damage if the target already carries Weakened or Sundered."
					return [u1, u2, u3]
	return []
```

(If `options_for()` already ends with a bare `return []` after its `match` block, place this new
case before that trailing `return []` so it's reached — confirm the exact trailing structure by
reading the end of the function before inserting.)

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2. Expected: all checks pass.

- [ ] **Step 5: Commit**

```bash
git add combat/ability_talent_library.gd tests/test_ability_talents_summoner.gd
git commit -m "feat(harvester): register the 18 Harvester ability talent options"
```

---

### Task 4: Row 1 — Touch-Me-Not talents (Delayed Bloom, Overripe, Overgrown Roots)

**Files:**
- Modify: `combat/combat.gd:866-898` (`_run_minion_stage` dispatcher + `_run_ember_stage`)
- Modify: `combat/combat.gd` (`_on_phase_changed`'s UPKEEP branch — Delayed Bloom's echo)
- Modify: `combat/combatant.gd` (new field `pending_delayed_bloom_damage`)
- Test: `tests/test_touch_me_not_talents.gd` (new)

**Interfaces:**
- Consumes: `EffectLibrary.make(&"rooted") -> Effect`, `_enemies_of(minion) -> Array[Combatant]`,
  `Combatant.has_ability_talent(id) -> bool`, `Combatant.take_damage(amount)`.
- Produces: `Combatant.pending_delayed_bloom_damage: int` — read and cleared by the UPKEEP handler
  added in this task; no later task depends on it.

- [ ] **Step 1: Write the failing test**

Create `tests/test_touch_me_not_talents.gd`:

```gdscript
extends SceneTree

# Headless test for Touch-Me-Not's 3 talent options (2026-08-24 harvester-talent-tree spec §4).
# Calls Combat's private stage functions directly via the same reflection-free approach every other
# minion test uses (they're regular script methods, callable on any Combat instance) — mirrors
# tests/test_hasty_minion.gd's harness for building a real Combat scene, but drives _run_minion_stage
# directly instead of a full spin, since these talents don't touch reel resolution.
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_touch_me_not_talents.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _new_combat_with_harvester() -> Array:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()
	var pc: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	pc.level = Combatant.MAX_LEVEL
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	CombatHandoff.begin_encounter(pc, [], inv, vault, [&"rat"], &"tmn_talents", "res://world/overworld_demo.tscn", Vector2.ZERO)
	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame
	await process_frame
	inst.roll_initiative_for_test()
	return [inst, pc]

func _test_overgrown_roots() -> void:
	var setup: Array = await _new_combat_with_harvester()
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	_check(pc.pick_ability_talent(&"base_ability", &"ember_overgrown_roots"), "picks ember_overgrown_roots")
	var minion: Combatant = MinionLibrary.make(false, &"ember")
	minion.minion_caster = pc
	var enemy: Combatant = inst._enemies[0]
	inst._run_minion_stage(minion, 3, pc)
	var rooted: Effect = enemy._find_effect(&"rooted")
	_check(rooted != null, "ember_overgrown_roots: stage-3 burst applied Rooted to the enemy")
	inst.queue_free()

func _test_no_talent_no_rooted() -> void:
	var setup: Array = await _new_combat_with_harvester()
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	var minion: Combatant = MinionLibrary.make(false, &"ember")
	minion.minion_caster = pc
	var enemy: Combatant = inst._enemies[0]
	inst._run_minion_stage(minion, 3, pc)
	_check(enemy._find_effect(&"rooted") == null, "no talent: stage-3 burst does NOT apply Rooted")
	inst.queue_free()

func _test_delayed_bloom_echo() -> void:
	var setup: Array = await _new_combat_with_harvester()
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	_check(pc.pick_ability_talent(&"base_ability", &"ember_delayed_bloom"), "picks ember_delayed_bloom")
	var minion: Combatant = MinionLibrary.make(false, &"ember")
	minion.minion_caster = pc
	inst._run_minion_stage(minion, 1, pc)  # stage 1 = 8 base damage, echo = 4
	_check(pc.pending_delayed_bloom_damage == 4, "ember_delayed_bloom: queued a 4-damage echo (50%% of 8) (got %d)" % pc.pending_delayed_bloom_damage)
	inst.queue_free()

func _test_overripe_splashes_overkill() -> void:
	var setup: Array = await _new_combat_with_harvester()
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	_check(pc.pick_ability_talent(&"base_ability", &"ember_overripe"), "picks ember_overripe")
	var minion: Combatant = MinionLibrary.make(false, &"ember")
	minion.minion_caster = pc
	var victim: Combatant = Combatant.new()
	victim.base_max_hp = 5; victim.apply_stats(); victim.start_combat()
	var bystander: Combatant = Combatant.new()
	bystander.base_max_hp = 50; bystander.apply_stats(); bystander.start_combat()
	inst._enemies = [victim, bystander]
	inst._run_minion_stage(minion, 3, pc)  # stage 3 = 24 damage; victim has 5 HP -> 19 overkill
	_check(not victim.is_alive(), "ember_overripe setup: the low-HP victim died to the stage-3 burst")
	_check(bystander.hp == bystander.max_hp - 19, "ember_overripe: overkill splashed onto the bystander (got %d/%d)" % [bystander.hp, bystander.max_hp])
	inst.queue_free()

func _init() -> void:
	await _test_overgrown_roots()
	await _test_no_talent_no_rooted()
	await _test_delayed_bloom_echo()
	await _test_overripe_splashes_overkill()
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_touch_me_not_talents.gd`
Expected: FAIL — none of the 3 talents are implemented yet (`pending_delayed_bloom_damage` doesn't
exist, `_run_ember_stage` doesn't branch on any of the 3 new ids).

- [ ] **Step 3: Add `pending_delayed_bloom_damage` to `Combatant`**

In `combat/combatant.gd`, near `reel_surge_overflow_pending` (~line 421), add:

```gdscript
## Delayed Bloom (2026-08-24 harvester-talent-tree spec §4): flat damage queued by a Touch-Me-Not
## burst, applied as an AoE echo at this combatant's own next Upkeep, then cleared to 0. Accumulates
## if multiple stages fire before the next Upkeep (e.g. re-summoning mid-round).
var pending_delayed_bloom_damage: int = 0
```

Do NOT add any reset of this field to `begin_turn()` — it must survive from the turn it was queued
until the Upkeep handler reads it (Upkeep runs before `begin_turn()`'s own-turn reset logic for the
same combatant, so a `begin_turn()` reset would always wipe it first). Only the Upkeep handler added
in Step 5 below ever clears it, immediately after applying the echo.

- [ ] **Step 4: Update `_run_minion_stage`/`_run_ember_stage` in `combat.gd`**

Replace `combat/combat.gd:866-875` (the dispatcher) with:

```gdscript
func _run_minion_stage(minion: Combatant, stage: int, caster: Combatant = null) -> void:
	match minion.minion_type:
		&"dew":
			_run_dew_stage(minion, stage, caster)
		&"misfortune":
			_run_misfortune_stage(minion, stage, caster)
		&"hasty":
			_run_hasty_stage(minion, stage, caster)
		_:
			_run_ember_stage(minion, stage, caster)
	if stage >= 3 and minion.is_alive() and not _dew_evergreen_active(minion):
		_log("  %s completes its final stage and fades away." % minion.display_name)
		minion.force_expire()
		_turn_manager.remove_dead_combatant(minion)
		if minion.minion_caster != null and minion.minion_caster.is_alive() and minion.minion_caster.bonus_meter != null:
			var before: int = minion.minion_caster.bonus_meter.value
			minion.minion_caster.bonus_meter.add_flat(MINION_NATURAL_EXPIRY_BM_BONUS)
			var added: int = minion.minion_caster.bonus_meter.value - before
			if added > 0 and minion.minion_caster.bonus_meter.is_visible:
				_log("    BM +%d  (%d/%d)  — %s's minion completed its lifecycle" % [added, minion.minion_caster.bonus_meter.value, minion.minion_caster.bonus_meter.cap, minion.minion_caster.display_name])
```

The dispatcher above calls all four stage functions with `(minion, stage, caster)`, but
`_run_dew_stage` and `_run_misfortune_stage` don't accept a third argument in the current code —
without a matching signature change THIS task would break compilation (and
`tests/test_dew_minion.gd`/`tests/test_misfortune_minion.gd`) before Tasks 5/6 ever run. Fix this
now by adding the same optional `caster` parameter to both signatures, bodies UNCHANGED (Tasks 5
and 6 replace these same functions again, at which point the bodies start actually using `caster`):

In `combat/combat.gd`, change the `_run_dew_stage` signature line only:
```gdscript
func _run_dew_stage(minion: Combatant, stage: int, caster: Combatant = null) -> void:
```
(everything else in that function's body is untouched by this task).

In `combat/combat.gd`, change the `_run_misfortune_stage` signature line only:
```gdscript
func _run_misfortune_stage(minion: Combatant, stage: int, caster: Combatant = null) -> void:
```
(everything else in that function's body is untouched by this task — Task 6 gives it real use).

`_dew_evergreen_active()` is also added in this task (Task 5 doesn't need to change this function
again):

```gdscript
## Evergreen Bloom (2026-08-24 harvester-talent-tree spec §5): true when [param minion] is Lotus,
## already past its natural stage-3 expiry, and its caster picked dew_evergreen_bloom — prevents
## the dispatcher above from expiring it. False for every other minion type/pick.
func _dew_evergreen_active(minion: Combatant) -> bool:
	return minion.minion_type == &"dew" and minion.minion_caster != null and minion.minion_caster.has_ability_talent(&"dew_evergreen_bloom")
```

Replace `_run_ember_stage` (`combat/combat.gd:892-898`) with:

```gdscript
func _run_ember_stage(minion: Combatant, stage: int, caster: Combatant = null) -> void:
	var amount: int = MINION_BASE_STAGE_DAMAGE * stage
	var overripe: bool = caster != null and caster.has_ability_talent(&"ember_overripe")
	var overgrown_roots: bool = stage == 3 and caster != null and caster.has_ability_talent(&"ember_overgrown_roots")
	var delayed_bloom: bool = caster != null and caster.has_ability_talent(&"ember_delayed_bloom")
	var enemies: Array[Combatant] = _enemies_of(minion)
	for enemy: Combatant in enemies:
		if not enemy.is_alive():
			continue
		var hp_before: int = enemy.hp
		enemy.take_damage(amount)
		if _panels.has(enemy):
			(_panels[enemy] as CombatantPanel).refresh_status()
		if overgrown_roots:
			enemy.attach_effect(EffectLibrary.make(&"rooted"))
		if overripe and hp_before > 0 and not enemy.is_alive() and hp_before < amount:
			var overkill: int = amount - hp_before
			var others: Array[Combatant] = enemies.filter(func(e: Combatant) -> bool: return e != enemy and e.is_alive())
			if others.size() > 0:
				var splash_target: Combatant = others[randi() % others.size()]
				splash_target.take_damage(overkill)
				if _panels.has(splash_target):
					(_panels[splash_target] as CombatantPanel).refresh_status()
				_log("  🍂 Overripe splashes %d overkill damage onto %s." % [overkill, splash_target.display_name])
	if delayed_bloom and caster != null:
		caster.pending_delayed_bloom_damage += int(roundf(amount * 0.5))
	_log("  💥 %s (stage %d) pulses %d damage to every enemy." % [minion.display_name, stage, amount])
```

- [ ] **Step 5: Add the Delayed Bloom echo to the UPKEEP handler**

In `combat/combat.gd`'s `_on_phase_changed()`, inside the `if phase == PhaseManager.Phase.UPKEEP:`
branch (~lines 1886-1893), add right after the existing `passive_heal` block:

```gdscript
		if _attacker.pending_delayed_bloom_damage > 0 and _attacker.is_alive():
			var echo: int = _attacker.pending_delayed_bloom_damage
			_attacker.pending_delayed_bloom_damage = 0
			for enemy: Combatant in _enemies_of(_attacker):
				if enemy.is_alive():
					enemy.take_damage(echo)
					if _panels.has(enemy):
						(_panels[enemy] as CombatantPanel).refresh_status()
			_log("  🌱 Delayed Bloom echoes %d damage to every enemy." % echo)
```

- [ ] **Step 6: Run test to verify it passes**

Run the same command as Step 2. Expected: all checks pass.

- [ ] **Step 7: Run the pre-existing minion tests to confirm no regression**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_minion_lifecycle.gd`
and
`Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_minion_library.gd`
Expected: both still PASS (the `_run_ember_stage`/`_run_misfortune_stage` signature changes added an
optional trailing `caster` param with a `null` default, so existing untalented call sites are
unaffected).

- [ ] **Step 8: Commit**

```bash
git add combat/combat.gd combat/combatant.gd tests/test_touch_me_not_talents.gd
git commit -m "feat(harvester): implement Touch-Me-Not row talents (Delayed Bloom, Overripe, Overgrown Roots)"
```

---

### Task 5: Row 2 — Lotus talents (Evergreen Bloom, Twin Petal Cleanse, Guardian Bloom)

**Files:**
- Modify: `combat/combat.gd:900-930` (`_run_dew_stage`)
- Test: `tests/test_lotus_talents.gd` (new)

**Interfaces:**
- Consumes: `Combatant.cleanse_oldest_debuff() -> Effect`, `Combatant.apply_shield(amount: int,
  turns: int)`, `_allies_of(minion) -> Array[Combatant]`, `_dew_evergreen_active(minion)` (Task 4).
- Produces: nothing new consumed by later tasks.

- [ ] **Step 1: Write the failing test**

Create `tests/test_lotus_talents.gd`:

```gdscript
extends SceneTree

# Headless test for Lotus's 3 talent options (2026-08-24 harvester-talent-tree spec §5). Drives
# _run_minion_stage/_run_dew_stage directly, same approach as test_touch_me_not_talents.gd.
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_lotus_talents.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _new_combat_with_harvester() -> Array:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()
	var pc: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	pc.level = Combatant.MAX_LEVEL
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	CombatHandoff.begin_encounter(pc, [], inv, vault, [&"rat"], &"lotus_talents", "res://world/overworld_demo.tscn", Vector2.ZERO)
	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame
	await process_frame
	inst.roll_initiative_for_test()
	return [inst, pc]

func _test_evergreen_bloom_prevents_expiry_and_loops() -> void:
	var setup: Array = await _new_combat_with_harvester()
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	_check(pc.pick_ability_talent(&"ability_l2", &"dew_evergreen_bloom"), "picks dew_evergreen_bloom")
	var minion: Combatant = MinionLibrary.make(false, &"dew")
	minion.minion_caster = pc
	pc.active_minion = minion
	inst._run_minion_stage(minion, 3, pc)
	_check(minion.is_alive(), "dew_evergreen_bloom: minion survives past stage 3")
	pc.hp = 10
	inst._run_minion_stage(minion, 4, pc)
	_check(pc.hp > 10, "dew_evergreen_bloom: stage 4+ still heals (the looping reduced heal)")
	inst.queue_free()

func _test_twin_petal_cleanses_two() -> void:
	var setup: Array = await _new_combat_with_harvester()
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	_check(pc.pick_ability_talent(&"ability_l2", &"dew_twin_petal"), "picks dew_twin_petal")
	var minion: Combatant = MinionLibrary.make(false, &"dew")
	minion.minion_caster = pc
	var w1: Effect = EffectLibrary.make(&"weakened"); w1.id = &"weakened"
	pc.attach_effect(w1)
	var s1: Effect = EffectLibrary.make(&"sundered"); s1.id = &"sundered"
	pc.attach_effect(s1)
	inst._run_minion_stage(minion, 2, pc)
	_check(pc._find_effect(&"weakened") == null and pc._find_effect(&"sundered") == null, "dew_twin_petal: both debuffs cleansed by one stage-2 tick")
	inst.queue_free()

func _test_guardian_bloom_adds_shield() -> void:
	var setup: Array = await _new_combat_with_harvester()
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	_check(pc.pick_ability_talent(&"ability_l2", &"dew_guardian_bloom"), "picks dew_guardian_bloom")
	var minion: Combatant = MinionLibrary.make(false, &"dew")
	minion.minion_caster = pc
	inst._run_minion_stage(minion, 3, pc)
	_check(pc.shield_hp > 0, "dew_guardian_bloom: stage 3 grants a flat shield (got %d)" % pc.shield_hp)
	inst.queue_free()

func _init() -> void:
	await _test_evergreen_bloom_prevents_expiry_and_loops()
	await _test_twin_petal_cleanses_two()
	await _test_guardian_bloom_adds_shield()
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_lotus_talents.gd`
Expected: FAIL — none of the 3 talents branch yet.

- [ ] **Step 3: Update `_run_dew_stage`**

Replace `combat/combat.gd:909-930` with:

```gdscript
## [ASSUMPTION] Evergreen Bloom's looping post-stage-3 heal (2026-08-24 spec §5) — tune by playtest.
const DEW_EVERGREEN_LOOP_HEAL: int = 6
## [ASSUMPTION] Guardian Bloom's flat shield alongside stage-3 Thorns — tune by playtest.
const DEW_GUARDIAN_SHIELD: int = 10
const DEW_GUARDIAN_SHIELD_TURNS: int = 2

func _run_dew_stage(minion: Combatant, stage: int, caster: Combatant = null) -> void:
	var twin_petal: bool = caster != null and caster.has_ability_talent(&"dew_twin_petal")
	var guardian_bloom: bool = caster != null and caster.has_ability_talent(&"dew_guardian_bloom")
	if stage >= 4:
		# Evergreen Bloom loop (2026-08-24 spec §5): a reduced heal only, no cleanse/Thorns re-trigger.
		for ally: Combatant in _allies_of(minion):
			if not ally.is_alive():
				continue
			ally.heal(DEW_EVERGREEN_LOOP_HEAL)
			if _panels.has(ally):
				(_panels[ally] as CombatantPanel).refresh_status()
		_log("  💧 Lotus's Evergreen Bloom loops a %d heal to the party." % DEW_EVERGREEN_LOOP_HEAL)
		return
	var heal_amount: int = DEW_STAGE3_HEAL if stage == 3 else (DEW_STAGE2_HEAL if stage == 2 else DEW_STAGE1_HEAL)
	for ally: Combatant in _allies_of(minion):
		if not ally.is_alive():
			continue
		ally.heal(heal_amount)
		if stage >= 2:
			var cleanse_count: int = 2 if twin_petal else 1
			for i: int in range(cleanse_count):
				var cleansed: Effect = ally.cleanse_oldest_debuff()
				if cleansed != null:
					_log("  💧 Lotus cleanses %s's %s." % [ally.display_name, String(cleansed.id).to_upper()])
		if stage >= 3:
			var thorns := Effect.new()
			thorns.id = &"dew_thorns"
			thorns.kind = Effect.Kind.REEL_FACE_EDIT  # inert marker kind — thorns_pct is read directly regardless of kind
			thorns.thorns_pct = DEW_THORNS_PCT
			thorns.duration = DEW_THORNS_TURNS
			thorns.beneficial = true
			ally.attach_effect(thorns)
			_log("  🛡 Lotus wraps %s in Thorns (%d%% reflected, %d turns)." % [ally.display_name, roundi(DEW_THORNS_PCT * 100), DEW_THORNS_TURNS])
			if guardian_bloom:
				ally.apply_shield(DEW_GUARDIAN_SHIELD, DEW_GUARDIAN_SHIELD_TURNS)
				_log("  🛡 Guardian Bloom shields %s for %d." % [ally.display_name, DEW_GUARDIAN_SHIELD])
		if _panels.has(ally):
			(_panels[ally] as CombatantPanel).refresh_status()
	_log("  💧 Lotus (stage %d) heals the party for %d." % [stage, heal_amount])
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2. Expected: all checks pass.

- [ ] **Step 5: Run `tests/test_dew_minion.gd` to confirm no regression**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_dew_minion.gd`
Expected: still PASS.

- [ ] **Step 6: Commit**

```bash
git add combat/combat.gd tests/test_lotus_talents.gd
git commit -m "feat(harvester): implement Lotus row talents (Evergreen Bloom, Twin Petal Cleanse, Guardian Bloom)"
```

---

### Task 6: Row 3 — Nightshade talents (Withering Touch, Creeping Blight, Ill Fortune) + Harvest's Favor Ill Fortune synergy + `Effect.heal_multiplier`

**Files:**
- Modify: `combat/resources/effect.gd` (new field `heal_multiplier`)
- Modify: `combat/combatant.gd` (`heal()` respects `heal_multiplier`; `harvest_favor_on_hit()`'s
  `&"misfortune"` branch gains the Ill Fortune synergy)
- Modify: `combat/combat.gd:938-952` (`_run_misfortune_stage`)
- Test: `tests/test_nightshade_talents.gd` (new)

**Interfaces:**
- Consumes: `EffectLibrary.make(&"jinxed") -> Effect`, `EffectLibrary.make(&"weakened"/"sundered"/
  "cursed") -> Effect`, `Combatant.harvest_favor_on_hit()` (Task 2, extended here).
- Produces: `Effect.heal_multiplier: float` (default `1.0`) — usable by any future ability that
  wants to reduce/boost healing received; only Withering Touch sets it below 1.0 for now.

- [ ] **Step 1: Write the failing test**

Create `tests/test_nightshade_talents.gd`:

```gdscript
extends SceneTree

# Headless test for Nightshade's 3 talent options + the Harvest's Favor Ill Fortune synergy
# (2026-08-24 harvester-talent-tree spec §6, §1).
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_nightshade_talents.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _new_combat_with_harvester() -> Array:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()
	var pc: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	pc.level = Combatant.MAX_LEVEL
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	CombatHandoff.begin_encounter(pc, [], inv, vault, [&"rat"], &"nightshade_talents", "res://world/overworld_demo.tscn", Vector2.ZERO)
	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame
	await process_frame
	inst.roll_initiative_for_test()
	return [inst, pc]

func _test_withering_touch_reduces_healing() -> void:
	var setup: Array = await _new_combat_with_harvester()
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	_check(pc.pick_ability_talent(&"ability_l3", &"misfortune_withering_touch"), "picks misfortune_withering_touch")
	var minion: Combatant = MinionLibrary.make(false, &"misfortune")
	minion.minion_caster = pc
	var enemy: Combatant = inst._enemies[0]
	enemy.hp = 1
	inst._run_minion_stage(minion, 3, pc)
	var curse: Effect = enemy._find_effect(&"cursed")
	_check(curse != null and curse.heal_multiplier < 1.0, "misfortune_withering_touch: Cursed carries a heal_multiplier below 1.0 (got %.2f)" % (curse.heal_multiplier if curse != null else -1.0))
	var before: int = enemy.hp
	enemy.heal(20)
	_check(enemy.hp < before + 20, "misfortune_withering_touch: heal() actually respects heal_multiplier (healed to %d, expected less than %d)" % [enemy.hp, before + 20])
	inst.queue_free()

func _test_creeping_blight_reapplies_debuffs() -> void:
	var setup: Array = await _new_combat_with_harvester()
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	_check(pc.pick_ability_talent(&"ability_l3", &"misfortune_creeping_blight"), "picks misfortune_creeping_blight")
	var minion: Combatant = MinionLibrary.make(false, &"misfortune")
	minion.minion_caster = pc
	var enemy: Combatant = inst._enemies[0]
	inst._run_minion_stage(minion, 3, pc)
	_check(enemy._find_effect(&"weakened") != null, "misfortune_creeping_blight: stage 3 also applies Weakened")
	_check(enemy._find_effect(&"sundered") != null, "misfortune_creeping_blight: stage 3 also applies Sundered")
	_check(enemy._find_effect(&"cursed") != null, "misfortune_creeping_blight: stage 3 still applies Cursed")
	inst.queue_free()

func _test_ill_fortune_applies_jinxed_at_stage2() -> void:
	var setup: Array = await _new_combat_with_harvester()
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	_check(pc.pick_ability_talent(&"ability_l3", &"misfortune_ill_fortune"), "picks misfortune_ill_fortune")
	var minion: Combatant = MinionLibrary.make(false, &"misfortune")
	minion.minion_caster = pc
	var enemy: Combatant = inst._enemies[0]
	inst._run_minion_stage(minion, 2, pc)
	_check(enemy._find_effect(&"jinxed") != null, "misfortune_ill_fortune: stage 2 also applies Jinxed")
	inst.queue_free()

func _test_harvest_favor_ill_fortune_synergy() -> void:
	var setup: Array = await _new_combat_with_harvester()
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	_check(pc.pick_ability_talent(&"ability_l3", &"misfortune_ill_fortune"), "picks misfortune_ill_fortune")
	pc.active_minion = MinionLibrary.make(false, &"misfortune")
	var target: Combatant = inst._enemies[0]
	var weakened: Effect = EffectLibrary.make(&"weakened")
	target.attach_effect(weakened)
	pc.harvest_favor_on_hit(target, [pc])
	_check(target._find_effect(&"jinxed") != null, "harvest_favor + Ill Fortune: Nightshade branch also applies Jinxed on top of the duration extension")
	inst.queue_free()

func _init() -> void:
	await _test_withering_touch_reduces_healing()
	await _test_creeping_blight_reapplies_debuffs()
	await _test_ill_fortune_applies_jinxed_at_stage2()
	await _test_harvest_favor_ill_fortune_synergy()
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_nightshade_talents.gd`
Expected: FAIL — `heal_multiplier` doesn't exist, `_run_misfortune_stage` doesn't branch on any of
the 3 ids, `harvest_favor_on_hit` doesn't apply Jinxed.

- [ ] **Step 3: Add `heal_multiplier` to `Effect` and apply it in `Combatant.heal()`**

In `combat/resources/effect.gd`, add near `regen_bonus` (~line 58):

```gdscript
## Multiplies healing RECEIVED by the bearer while active (2026-08-24 harvester-talent-tree spec
## §6 — Withering Touch). 1.0 = no change. Read directly by Combatant.heal(), regardless of kind.
@export var heal_multiplier: float = 1.0
```

In `combat/combatant.gd`, update `heal()` (currently `combat/combatant.gd:499-508`):

```gdscript
## Restores [param amount] HP, clamped to max_hp. The lowest active heal_multiplier across
## active_effects is applied first (2026-08-24 harvester-talent-tree spec §6 — Withering Touch).
## Returns the OVERFLOW (amount that exceeded max) so a caller (e.g. Big Bang) can convert it to a
## shield. No-op (returns 0) if dead or amount ≤ 0.
func heal(amount: int) -> int:
	if amount <= 0 or hp <= 0:
		return 0
	var mult: float = 1.0
	for e: Effect in active_effects:
		if e != null and e.heal_multiplier < mult:
			mult = e.heal_multiplier
	var effective: int = int(roundf(amount * mult))
	var before: int = hp
	hp = mini(hp + effective, max_hp)
	if hp != before:
		hp_changed.emit(hp, max_hp)
	return effective - (hp - before)
```

- [ ] **Step 4: Update `_run_misfortune_stage`**

Replace `combat/combat.gd:938-952` with:

```gdscript
## [ASSUMPTION] Withering Touch's heal-reduction on the target while Cursed — tune by playtest.
const MISFORTUNE_WITHERING_TOUCH_HEAL_MULT: float = 0.5

func _run_misfortune_stage(minion: Combatant, stage: int, caster: Combatant = null) -> void:
	var withering_touch: bool = caster != null and caster.has_ability_talent(&"misfortune_withering_touch")
	var creeping_blight: bool = caster != null and caster.has_ability_talent(&"misfortune_creeping_blight")
	var ill_fortune: bool = caster != null and caster.has_ability_talent(&"misfortune_ill_fortune")
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
			if creeping_blight:
				enemy.attach_effect(EffectLibrary.make(&"weakened"))
				enemy.attach_effect(EffectLibrary.make(&"sundered"))
			var curse: Effect = EffectLibrary.make(&"cursed")
			curse.dot_base_damage = 12.0  # flat, not weapon-scaled — 6 dmg/turn at stacks=1 (2026-08-17 playtest: was 1 dmg/turn)
			if withering_touch:
				curse.heal_multiplier = MISFORTUNE_WITHERING_TOUCH_HEAL_MULT
			enemy.attach_effect(curse)
		if _panels.has(enemy):
			(_panels[enemy] as CombatantPanel).refresh_status()
	_log("  🌑 Nightshade (stage %d) afflicts every enemy." % stage)
```

- [ ] **Step 5: Add the Ill Fortune synergy to `harvest_favor_on_hit()`**

In `combat/combatant.gd`, update the `&"misfortune"` branch inside `harvest_favor_on_hit()` (added
in Task 2):

```gdscript
		&"misfortune":
			if target == null or not target.is_alive():
				return
			for debuff_id: StringName in [&"weakened", &"sundered", &"cursed"]:
				var e: Effect = target._find_effect(debuff_id)
				if e != null:
					e.duration += 1
			if has_ability_talent(&"misfortune_ill_fortune"):
				target.attach_effect(EffectLibrary.make(&"jinxed"))
```

- [ ] **Step 6: Run test to verify it passes**

Run the same command as Step 2. Expected: all checks pass.

- [ ] **Step 7: Run `tests/test_misfortune_minion.gd` to confirm no regression**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_misfortune_minion.gd`
Expected: still PASS.

- [ ] **Step 8: Commit**

```bash
git add combat/resources/effect.gd combat/combatant.gd combat/combat.gd tests/test_nightshade_talents.gd
git commit -m "feat(harvester): implement Nightshade row talents + Ill Fortune/Harvest's Favor synergy"
```

---

### Task 7: Row 4 — Wheat talents (Bountiful Harvest, Charged Growth, Unshakeable Roots)

**Files:**
- Modify: `combat/resource_pool.gd` (new field `pending_ability_refund`, `spend()` applies it)
- Modify: `combat/combatant.gd` (new field `charged_growth_reel_index`)
- Modify: `combat/combat.gd:958-1002` (`_run_hasty_stage`)
- Modify: `combat/combat.gd:2416-2427` (`_commit_main1`'s reel_surge cap check — record the surge
  reel's index for Charged Growth)
- Modify: `combat/combat.gd:2480` (`_do_spin`'s `resolve_combat_phase` call — merge Charged Growth's
  index into the forced-crit list)
- Test: `tests/test_wheat_talents.gd` (new)

**Interfaces:**
- Consumes: `EffectLibrary.make(&"empowered") -> Effect`, `ResourcePool.spend(cost: Dictionary) ->
  bool`, `ResourcePool.refund(cost: Dictionary) -> void`, `Combatant.wild_reel_indices() ->
  Array[int]`.
- Produces: `ResourcePool.pending_ability_refund: int` (settable by any future talent, not just
  this one). `Combatant.charged_growth_reel_index: int` (-1 = none), read once per spin by
  `_do_spin()`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_wheat_talents.gd`:

```gdscript
extends SceneTree

# Headless test for Wheat's 3 talent options (2026-08-24 harvester-talent-tree spec §7).
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_wheat_talents.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _new_combat_with_harvester() -> Array:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()
	var pc: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	pc.level = Combatant.MAX_LEVEL
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	CombatHandoff.begin_encounter(pc, [], inv, vault, [&"rat"], &"wheat_talents", "res://world/overworld_demo.tscn", Vector2.ZERO)
	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame
	await process_frame
	inst.roll_initiative_for_test()
	return [inst, pc]

func _test_bountiful_harvest_refunds_next_cast() -> void:
	var setup: Array = await _new_combat_with_harvester()
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	_check(pc.pick_ability_talent(&"ability_l4", &"hasty_bountiful_harvest"), "picks hasty_bountiful_harvest")
	var minion: Combatant = MinionLibrary.make(false, &"hasty")
	minion.minion_caster = pc
	inst._run_minion_stage(minion, 2, pc)
	_check(pc.resource_pool.pending_ability_refund > 0, "hasty_bountiful_harvest: stage 2 queued a refund (got %d)" % pc.resource_pool.pending_ability_refund)
	var before: int = pc.resource_pool.mana
	pc.resource_pool.spend({&"mana": 4})
	_check(pc.resource_pool.mana > before - 4, "hasty_bountiful_harvest: next ability's spend was partially refunded (mana %d, spent from %d)" % [pc.resource_pool.mana, before])
	_check(pc.resource_pool.pending_ability_refund == 0, "hasty_bountiful_harvest: refund is consumed after one ability")
	inst.queue_free()

func _test_unshakeable_roots_grants_immunity() -> void:
	var setup: Array = await _new_combat_with_harvester()
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	_check(pc.pick_ability_talent(&"ability_l4", &"hasty_unshakeable_roots"), "picks hasty_unshakeable_roots")
	var minion: Combatant = MinionLibrary.make(false, &"hasty")
	minion.minion_caster = pc
	inst._run_minion_stage(minion, 1, pc)
	var haste: Effect = pc._find_effect(&"hasty_initiative")
	_check(haste != null and &"rooted" in haste.immune_effect_ids, "hasty_unshakeable_roots: stage-1 Initiative buff grants Rooted immunity")
	inst.queue_free()

func _test_charged_growth_marks_surge_reel() -> void:
	var setup: Array = await _new_combat_with_harvester()
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	_check(pc.pick_ability_talent(&"ability_l4", &"hasty_charged_growth"), "picks hasty_charged_growth")
	var minion: Combatant = MinionLibrary.make(false, &"hasty")
	minion.minion_caster = pc
	inst._run_minion_stage(minion, 3, pc)  # attaches reel_surge
	pc.turn_reels = [ActionReel.make_default(pc.weapon_type()), ActionReel.make_default(pc.weapon_type())]
	inst._commit_main1()
	_check(pc.charged_growth_reel_index == pc.turn_reels.size() - 1, "hasty_charged_growth: the surge-appended reel's index was recorded (got %d, expected %d)" % [pc.charged_growth_reel_index, pc.turn_reels.size() - 1])
	inst.queue_free()

func _init() -> void:
	await _test_bountiful_harvest_refunds_next_cast()
	await _test_unshakeable_roots_grants_immunity()
	await _test_charged_growth_marks_surge_reel()
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_wheat_talents.gd`
Expected: FAIL — none of the 3 fields/branches exist yet.

- [ ] **Step 3: Add `pending_ability_refund` to `ResourcePool`**

In `combat/resource_pool.gd`, add near the top (after the `mana_regen_per_turn` field):

```gdscript
## Bountiful Harvest (2026-08-24 harvester-talent-tree spec §7): a one-time flat refund applied to
## the NEXT successful spend() call, then cleared. [ASSUMPTION] amount — tune by playtest.
var pending_ability_refund: int = 0
```

Update `spend()`:

```gdscript
## Spends [param cost] atomically across both rails. Returns false and changes nothing if unaffordable.
func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	var sta: int = int(cost.get(&"stamina", 0))
	if sta != 0:
		stamina -= sta
		pool_changed.emit(&"stamina", stamina, max_stamina)
	var man: int = int(cost.get(&"mana", 0))
	if man != 0:
		mana -= man
		pool_changed.emit(&"mana", mana, max_mana)
	if pending_ability_refund > 0:
		var refund_cost: Dictionary = {}
		if sta > 0:
			refund_cost[&"stamina"] = mini(pending_ability_refund, sta)
		if man > 0:
			refund_cost[&"mana"] = mini(pending_ability_refund, man)
		pending_ability_refund = 0
		if not refund_cost.is_empty():
			refund(refund_cost)
	return true
```

- [ ] **Step 4: Add `charged_growth_reel_index` to `Combatant`**

In `combat/combatant.gd`, near `reel_surge_overflow_pending` (~line 421):

```gdscript
## Charged Growth (2026-08-24 harvester-talent-tree spec §7): index into turn_reels of the reel
## reel_surge appended this turn, or -1 if none/not picked. Read once by combat.gd's _do_spin() to
## fold into the forced-crit reel list alongside wild_reel_indices(). Reset at begin_turn().
var charged_growth_reel_index: int = -1
```

Reset it in `begin_turn()` alongside `reel_surge_overflow_pending = false`:

```gdscript
	charged_growth_reel_index = -1
```

- [ ] **Step 5: Update `_run_hasty_stage`**

Replace `combat/combat.gd:964-1002` with:

```gdscript
## [ASSUMPTION] Bountiful Harvest's next-ability refund — tune by playtest.
const HASTY_BOUNTIFUL_HARVEST_REFUND: int = 2

func _run_hasty_stage(minion: Combatant, stage: int, caster: Combatant = null) -> void:
	var bountiful_harvest: bool = caster != null and caster.has_ability_talent(&"hasty_bountiful_harvest")
	var unshakeable_roots: bool = caster != null and caster.has_ability_talent(&"hasty_unshakeable_roots")
	for ally: Combatant in _allies_of(minion):
		if not ally.is_alive():
			continue
		if stage == 1:
			var haste := Effect.new()
			haste.id = &"hasty_initiative"
			haste.kind = Effect.Kind.INITIATIVE_MOD
			haste.magnitude = HASTY_INITIATIVE_BONUS
			haste.duration = HASTY_INITIATIVE_TURNS + (1 if ally == caster else 0)
			haste.beneficial = true
			if unshakeable_roots:
				haste.immune_effect_ids = [&"slow", &"rooted"]
			ally.attach_effect(haste)
		if stage == 2:
			var regen := Effect.new()
			regen.id = &"hasty_regen"
			regen.kind = Effect.Kind.REEL_FACE_EDIT  # inert marker kind — regen_bonus is read directly
			regen.regen_bonus = HASTY_REGEN_BONUS
			regen.duration = HASTY_REGEN_TURNS
			regen.beneficial = true
			ally.attach_effect(regen)
			_log("  💨 Wheat grants %s +%d resource regen (%d turns)." % [ally.display_name, HASTY_REGEN_BONUS, HASTY_REGEN_TURNS])
			if bountiful_harvest and ally.resource_pool != null:
				ally.resource_pool.pending_ability_refund = HASTY_BOUNTIFUL_HARVEST_REFUND
		if stage == 3:
			var empowered: Effect = EffectLibrary.make(&"empowered")
			empowered.duration = 1  # spec §5 locks this specific stage's Empowered to 1 turn
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

- [ ] **Step 6: Record the Charged Growth reel index in `_commit_main1()`**

In `combat/combat.gd`, update the reel_surge cap-check block (lines 2416-2427):

```gdscript
	const REEL_SURGE_CAP: int = 5   # matches the 5-cap used everywhere MainPhasePlan is constructed
	if _attacker.has_effect(&"reel_surge"):
		if _attacker.turn_reels.size() < REEL_SURGE_CAP:
			_attacker.turn_reels.append(ActionReel.make_ability_attack(_attacker.weapon_type()))
			if _attacker.class_id == &"summoner" and _attacker.has_ability_talent(&"hasty_charged_growth"):
				_attacker.charged_growth_reel_index = _attacker.turn_reels.size() - 1
		else:
			_attacker.reel_surge_overflow_pending = true
```

- [ ] **Step 7: Fold Charged Growth into the forced-crit list in `_do_spin()`**

In `combat/combat.gd:2480`, change:

```gdscript
	var attacks: Array[CombatResolver.AttackResult] = _resolver.resolve_combat_phase(reels, _attacker.weapon_effective_base_damage(), _defender.defense_type, _attacker.wild_reel_indices(), weapon_count, _attacker.might_damage_bonus_per_reel(reels.size()), extra_lines, true, dmg_mult)
```

to:

```gdscript
	var forced_crit_indices: Array[int] = _attacker.wild_reel_indices()
	if _attacker.charged_growth_reel_index >= 0:
		forced_crit_indices.append(_attacker.charged_growth_reel_index)
	var attacks: Array[CombatResolver.AttackResult] = _resolver.resolve_combat_phase(reels, _attacker.weapon_effective_base_damage(), _defender.defense_type, forced_crit_indices, weapon_count, _attacker.might_damage_bonus_per_reel(reels.size()), extra_lines, true, dmg_mult)
```

- [ ] **Step 8: Run test to verify it passes**

Run the same command as Step 2. Expected: all checks pass.

- [ ] **Step 9: Run `tests/test_hasty_minion.gd` to confirm no regression**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_hasty_minion.gd`
Expected: still PASS.

- [ ] **Step 10: Commit**

```bash
git add combat/resource_pool.gd combat/combatant.gd combat/combat.gd tests/test_wheat_talents.gd
git commit -m "feat(harvester): implement Wheat row talents (Bountiful Harvest, Charged Growth, Unshakeable Roots)"
```

---

### Task 8: Row 5 — Harvest's Favor upgrades (Amplified Bond, Favor Unleashed, Spirit Surge)

**Files:**
- Modify: `combat/combatant.gd` (`harvest_favor_on_hit()` gains Amplified Bond scaling; new method
  `harvest_favor_spirit_surge_proc()` for the Upkeep hook)
- Modify: `combat/combat.gd` (`_apply_attack()`'s NEUTRAL-tier handling — Favor Unleashed; UPKEEP
  handler — Spirit Surge)
- Test: `tests/test_harvest_favor_talents.gd` (new)

**Interfaces:**
- Consumes: `Combatant.active_minion.minion_stage: int`, `ReelFace.ResultTier.NEUTRAL`.
- Produces: `Combatant.harvest_favor_spirit_surge_proc(allies: Array[Combatant]) -> void`, called
  from the UPKEEP branch of `_on_phase_changed()`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_harvest_favor_talents.gd`:

```gdscript
extends SceneTree

# Headless test for the 3 Harvest's Favor row-5 talent upgrades (2026-08-24 harvester-talent-tree
# spec §8). Amplified Bond and Favor Unleashed are checked via direct harvest_favor_on_hit()/a new
# NEUTRAL-tier variant call; Spirit Surge via the new harvest_favor_spirit_surge_proc() method.
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_harvest_favor_talents.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _mk_harvester() -> Combatant:
	var c: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	c.level = Combatant.MAX_LEVEL
	return c

func _test_amplified_bond_scales_with_stage() -> void:
	var c: Combatant = _mk_harvester()
	_check(c.pick_ability_talent(&"passive", &"harvest_favor_amplified_bond"), "picks harvest_favor_amplified_bond")
	var target1: Combatant = Combatant.new()
	target1.base_max_hp = 100; target1.apply_stats(); target1.start_combat()
	c.active_minion = MinionLibrary.make(false, &"ember")
	c.active_minion.minion_stage = 1
	c.harvest_favor_on_hit(target1, [c])
	var dmg_at_stage1: int = target1.max_hp - target1.hp

	var c2: Combatant = _mk_harvester()
	_check(c2.pick_ability_talent(&"passive", &"harvest_favor_amplified_bond"), "picks harvest_favor_amplified_bond (c2)")
	var target3: Combatant = Combatant.new()
	target3.base_max_hp = 100; target3.apply_stats(); target3.start_combat()
	c2.active_minion = MinionLibrary.make(false, &"ember")
	c2.active_minion.minion_stage = 3
	c2.harvest_favor_on_hit(target3, [c2])
	var dmg_at_stage3: int = target3.max_hp - target3.hp

	_check(dmg_at_stage3 > dmg_at_stage1, "harvest_favor_amplified_bond: stage-3 bonus (%d) exceeds stage-1 bonus (%d)" % [dmg_at_stage3, dmg_at_stage1])

func _test_favor_unleashed_triggers_on_neutral() -> void:
	var c: Combatant = _mk_harvester()
	_check(c.pick_ability_talent(&"passive", &"harvest_favor_unleashed"), "picks harvest_favor_unleashed")
	c.active_minion = MinionLibrary.make(false, &"ember")
	var target: Combatant = Combatant.new()
	target.base_max_hp = 100; target.apply_stats(); target.start_combat()
	c.harvest_favor_on_hit(target, [c], true)  # is_neutral = true
	_check(target.hp < target.max_hp, "harvest_favor_unleashed: a NEUTRAL-tier hit still triggers a (reduced) bonus")

func _test_favor_unleashed_required_for_neutral_trigger() -> void:
	var c: Combatant = _mk_harvester()
	c.active_minion = MinionLibrary.make(false, &"ember")
	var target: Combatant = Combatant.new()
	target.base_max_hp = 100; target.apply_stats(); target.start_combat()
	c.harvest_favor_on_hit(target, [c], true)
	_check(target.hp == target.max_hp, "without harvest_favor_unleashed: a NEUTRAL-tier hit does NOT trigger")

func _test_spirit_surge_guarantees_proc() -> void:
	var c: Combatant = _mk_harvester()
	_check(c.pick_ability_talent(&"passive", &"harvest_favor_spirit_surge"), "picks harvest_favor_spirit_surge")
	c.active_minion = MinionLibrary.make(false, &"dew")
	var low_ally: Combatant = Combatant.new()
	low_ally.base_max_hp = 50; low_ally.apply_stats(); low_ally.start_combat(); low_ally.hp = 10
	c.harvest_favor_spirit_surge_proc([c, low_ally])
	_check(low_ally.hp > 10, "harvest_favor_spirit_surge: Upkeep proc healed the lowest-HP ally with no hit landed")

func _init() -> void:
	_test_amplified_bond_scales_with_stage()
	_test_favor_unleashed_triggers_on_neutral()
	_test_favor_unleashed_required_for_neutral_trigger()
	_test_spirit_surge_guarantees_proc()
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_harvest_favor_talents.gd`
Expected: FAIL — `harvest_favor_on_hit()` doesn't take a 3rd `is_neutral` param yet, no stage
scaling, `harvest_favor_spirit_surge_proc()` doesn't exist.

- [ ] **Step 3: Update `harvest_favor_on_hit()`**

Replace the method added in Task 2 (and extended in Task 6) in `combat/combatant.gd`:

```gdscript
## [ASSUMPTION] Favor Unleashed's reduced NEUTRAL-tier trigger fraction — tune by playtest.
const HARVEST_FAVOR_UNLEASHED_FRACTION: float = 0.5

## Harvest's Favor (Harvester passive, 2026-08-24 harvester-talent-tree spec §1, upgraded §8) —
## fires once per landed SUCCESS/CRIT_SUCCESS weapon-reel hit while a minion is active (or on a
## NEUTRAL-tier hit too, at reduced value, if [param is_neutral] is true AND
## harvest_favor_unleashed is picked). No-op with no active minion. [param target] is the hit's
## target; [param allies] is every ally to consider for the Lotus branch (pass the party including
## this combatant).
func harvest_favor_on_hit(target: Combatant, allies: Array[Combatant], is_neutral: bool = false) -> void:
	if passive_ability_id != &"harvest_favor" or active_minion == null or not active_minion.is_alive():
		return
	if is_neutral and not has_ability_talent(&"harvest_favor_unleashed"):
		return
	var scale: float = HARVEST_FAVOR_UNLEASHED_FRACTION if is_neutral else 1.0
	if has_ability_talent(&"harvest_favor_amplified_bond"):
		scale *= float(active_minion.minion_stage)
	match active_minion.minion_type:
		&"ember":
			if target != null and target.is_alive():
				target.take_damage(int(roundf(HARVEST_FAVOR_EMBER_BONUS_DAMAGE * scale)))
		&"dew":
			var lowest: Combatant = null
			for a: Combatant in allies:
				if a == null or not a.is_alive() or a.is_minion:
					continue
				if lowest == null or a.hp < lowest.hp:
					lowest = a
			if lowest != null:
				lowest.heal(int(roundf(HARVEST_FAVOR_DEW_HEAL * scale)))
		&"misfortune":
			if target == null or not target.is_alive():
				return
			for debuff_id: StringName in [&"weakened", &"sundered", &"cursed"]:
				var e: Effect = target._find_effect(debuff_id)
				if e != null:
					e.duration += 1
			if has_ability_talent(&"misfortune_ill_fortune"):
				target.attach_effect(EffectLibrary.make(&"jinxed"))
		&"hasty":
			for e: Effect in active_effects:
				if e != null and e.beneficial:
					e.duration += 1

## Spirit Surge (2026-08-24 harvester-talent-tree spec §8): guarantees one free harvest_favor_on_hit
## proc at this combatant's own Upkeep, regardless of whether any hit landed that turn. No-op if
## the talent isn't picked (called unconditionally from combat.gd's UPKEEP handler; cheap no-op).
func harvest_favor_spirit_surge_proc(allies: Array[Combatant]) -> void:
	if not has_ability_talent(&"harvest_favor_spirit_surge"):
		return
	if active_minion == null or not active_minion.is_alive():
		return
	var primary_target: Combatant = null
	for a: Combatant in allies:
		if a != null and a.is_alive() and a != self and not a.is_minion:
			primary_target = a
			break
	harvest_favor_on_hit(primary_target, allies)
```

Note: for a solo-encounter test with no enemy passed into `allies` (Spirit Surge only needs a
target for the Ember/Nightshade branches — the test above uses `&"dew"`, which doesn't need
`primary_target` at all, so `primary_target == null` is fine there).

- [ ] **Step 4: Wire Favor Unleashed into `_apply_attack()`'s NEUTRAL handling**

In `combat/combat.gd`, find the existing NEUTRAL-tier handling inside `_apply_attack()` (the
"SUCCESS LINE" logging block around line 2971-2975, which is the `SUCCESS` case — the `NEUTRAL`
case is the sibling branch just above/below it in the same tier dispatch; locate it by searching
for `ReelFace.ResultTier.NEUTRAL` in this function). Add, in that NEUTRAL branch:

```gdscript
			if _attacker.passive_ability_id == &"harvest_favor":
				_attacker.harvest_favor_on_hit(t, _allies_of(_attacker), true)
```

(`t` must be whichever target variable that branch already has in scope — reuse the existing local,
matching the SUCCESS/CRIT_SUCCESS call added in Task 2 Step 5.)

- [ ] **Step 5: Wire Spirit Surge into the UPKEEP handler**

In `combat/combat.gd`'s `_on_phase_changed()`, inside the `UPKEEP` branch, add right after the
Delayed Bloom block added in Task 4 Step 5:

```gdscript
		if _attacker.passive_ability_id == &"harvest_favor" and _attacker.is_alive():
			_attacker.harvest_favor_spirit_surge_proc(_allies_of(_attacker))
```

- [ ] **Step 6: Run test to verify it passes**

Run the same command as Step 2. Expected: all checks pass.

- [ ] **Step 7: Re-run Task 2's and Task 6's test files to confirm no regression**

Run `tests/test_harvest_favor_passive.gd` and `tests/test_nightshade_talents.gd` again (same
command shape as before). Expected: both still fully PASS — `harvest_favor_on_hit`'s new
`is_neutral` param defaults to `false`, so the existing SUCCESS/CRIT_SUCCESS call sites are
unaffected.

- [ ] **Step 8: Commit**

```bash
git add combat/combatant.gd combat/combat.gd tests/test_harvest_favor_talents.gd
git commit -m "feat(harvester): implement Harvest's Favor row-5 talent upgrades"
```

---

### Task 9: Row 6 — Strawfellow's Due talents (Petrifying Burst, Undying Bloom, Withering Doom)

**Files:**
- Modify: `combat/combat.gd:1017-1115` (`_apply_grand_sacrifice`)
- Test: `tests/test_strawfellow_due_talents.gd` (new)

**Interfaces:**
- Consumes: `Combatant.force_stun_next_turn: bool`, `Combatant.cleanse() -> int`,
  `Combatant.has_effect(id) -> bool`, `_allies_of`/`_enemies_of`, `EffectLibrary.make`.
- Produces: nothing new consumed elsewhere.

- [ ] **Step 1: Write the failing test**

Create `tests/test_strawfellow_due_talents.gd`:

```gdscript
extends SceneTree

# Headless test for Strawfellow's Due's 3 Ultimate-row talent options (2026-08-24
# harvester-talent-tree spec §9). Calls _apply_grand_sacrifice() directly with a pre-summoned
# minion of the relevant variant, mirroring tests/test_grand_sacrifice.gd's own direct-call harness.
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_strawfellow_due_talents.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _new_combat_with_harvester() -> Array:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()
	var pc: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	pc.level = Combatant.MAX_LEVEL
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	CombatHandoff.begin_encounter(pc, [], inv, vault, [&"rat"], &"strawfellow_talents", "res://world/overworld_demo.tscn", Vector2.ZERO)
	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame
	await process_frame
	inst.roll_initiative_for_test()
	return [inst, pc]

func _test_petrifying_burst_forces_stun() -> void:
	var setup: Array = await _new_combat_with_harvester()
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	_check(pc.pick_ability_talent(&"ultimate", &"strawfellow_petrifying_burst"), "picks strawfellow_petrifying_burst")
	inst._defender = inst._enemies[0]
	inst._apply_grand_sacrifice(pc, &"ember")
	_check(inst._enemies[0].force_stun_next_turn, "strawfellow_petrifying_burst: primary target's force_stun_next_turn is set")
	inst.queue_free()

func _test_undying_bloom_cleanses_whole_party() -> void:
	var setup: Array = await _new_combat_with_harvester()
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	_check(pc.pick_ability_talent(&"ultimate", &"strawfellow_undying_bloom"), "picks strawfellow_undying_bloom")
	var weakened: Effect = EffectLibrary.make(&"weakened")
	pc.attach_effect(weakened)
	inst._apply_grand_sacrifice(pc, &"dew")
	_check(pc._find_effect(&"weakened") == null, "strawfellow_undying_bloom: immediately cleansed the caster's debuff")
	inst.queue_free()

func _test_withering_doom_doubles_damage_vs_debuffed() -> void:
	var setup: Array = await _new_combat_with_harvester()
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	_check(pc.pick_ability_talent(&"ultimate", &"strawfellow_withering_doom"), "picks strawfellow_withering_doom")
	var enemy: Combatant = inst._enemies[0]
	enemy.attach_effect(EffectLibrary.make(&"weakened"))
	inst._apply_grand_sacrifice(pc, &"misfortune")
	var curse: Effect = enemy._find_effect(&"cursed")
	_check(curse != null and is_equal_approx(curse.dot_base_damage, 30.0), "strawfellow_withering_doom: doubled Curse's dot_base_damage vs. a Weakened target (got %.1f)" % (curse.dot_base_damage if curse != null else -1.0))
	inst.queue_free()

func _test_withering_doom_no_bonus_without_debuff() -> void:
	var setup: Array = await _new_combat_with_harvester()
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	_check(pc.pick_ability_talent(&"ultimate", &"strawfellow_withering_doom"), "picks strawfellow_withering_doom")
	var enemy: Combatant = inst._enemies[0]
	inst._apply_grand_sacrifice(pc, &"misfortune")
	var curse: Effect = enemy._find_effect(&"cursed")
	_check(curse != null and is_equal_approx(curse.dot_base_damage, 15.0), "strawfellow_withering_doom: NO bonus vs. an undebuffed target (got %.1f)" % (curse.dot_base_damage if curse != null else -1.0))
	inst.queue_free()

func _init() -> void:
	await _test_petrifying_burst_forces_stun()
	await _test_undying_bloom_cleanses_whole_party()
	await _test_withering_doom_doubles_damage_vs_debuffed()
	await _test_withering_doom_no_bonus_without_debuff()
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_strawfellow_due_talents.gd`
Expected: FAIL — none of the 3 talents branch yet.

- [ ] **Step 3: Update `_apply_grand_sacrifice`**

In `combat/combat.gd`, update the `&"ember"` branch (lines 1019-1036) — after the existing
`_defender.take_damage(GRAND_SACRIFICE_EMBER_BURST)` call, add:

```gdscript
			if caster.has_ability_talent(&"strawfellow_petrifying_burst"):
				_defender.force_stun_next_turn = true
```

Update the `&"dew"` branch (lines 1037-1068) — after the existing per-ally loop body, but still
inside the `for ally: Combatant in _allies_of(caster):` loop, add (right after `ally.attach_effect(cleanse)`):

```gdscript
				if caster.has_ability_talent(&"strawfellow_undying_bloom"):
					ally.cleanse()
```

Update the `&"misfortune"` branch (lines 1069-1088) — change the `curse.dot_base_damage = 15.0`
line to:

```gdscript
				var curse: Effect = EffectLibrary.make(&"cursed")
				curse.dot_base_damage = 15.0  # 18 dmg/turn at stacks=3 (2026-08-17 playtest: was 3 dmg/turn)
				if caster.has_ability_talent(&"strawfellow_withering_doom") and (enemy.has_effect(&"weakened") or enemy.has_effect(&"sundered")):
					curse.dot_base_damage *= 2.0
				curse.duration = GRAND_SACRIFICE_CURSE_TURNS
```

(This replaces the original 2-line `curse.dot_base_damage = 15.0` / `curse.duration =
GRAND_SACRIFICE_CURSE_TURNS` pair with the 5-line version above — the surrounding
`jinx`/`add_stack()`/`attach_effect(curse)` lines are unchanged.)

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2. Expected: all checks pass.

- [ ] **Step 5: Run `tests/test_grand_sacrifice.gd` to confirm no regression**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_grand_sacrifice.gd`
Expected: still PASS.

- [ ] **Step 6: Commit**

```bash
git add combat/combat.gd tests/test_strawfellow_due_talents.gd
git commit -m "feat(harvester): implement Strawfellow's Due ultimate-row talents"
```

---

### Task 10: `TalentMenuPanel` smoke check + full-suite regression pass

**Files:**
- No source modification expected (this task is verification-only, plus documentation touch-up).
- Modify: `CLAUDE.md` §8 (status update — Harvester talent tree now shipped)

**Interfaces:** none new.

- [ ] **Step 1: Confirm the Harvester shows up correctly in `TalentMenuPanel`**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_talent_menu_panel.gd`
(or whatever the existing generic talent-menu UI test file is named — locate it via
`Glob("tests/test_talent_menu*")` if the exact name isn't `test_talent_menu_panel.gd`). Expected:
PASS with no Harvester-specific failures. This file iterates real classes generically in most of
this codebase's UI test files — if it hardcodes a class list that doesn't include `&"summoner"`,
that's a pre-existing gap, not something this plan needs to fix; note it in the commit message if
found but don't expand scope.

- [ ] **Step 2: Run every test file touched or added by this plan, back to back**

Run each of the following (from `C:\bunnies\bunnies-main\`), confirming 0 failures each:

```
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_attach_effect_merge_strength.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_harvest_favor_passive.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_ability_talents_summoner.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_touch_me_not_talents.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_lotus_talents.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_nightshade_talents.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_wheat_talents.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_harvest_favor_talents.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_strawfellow_due_talents.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_minion_lifecycle.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_minion_library.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_dew_minion.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_misfortune_minion.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_hasty_minion.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_grand_sacrifice.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_summoner_meter_economy.gd
```

Per CLAUDE.md's documented "Silent script-error-exits-zero" gotcha, don't trust exit codes alone —
grep each run's console output for `SCRIPT ERROR` or `FAIL` before treating it as green.

- [ ] **Step 3: Update CLAUDE.md §8**

Add a line to the "Combat prototype" bullet list in `CLAUDE.md` §8 noting the Harvester talent tree
(6 rows, 18 options, Harvest's Favor passive) is now code-complete and test-green, alongside the
existing per-class talent-tree mention.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: mark the Harvester talent tree as shipped"
```
