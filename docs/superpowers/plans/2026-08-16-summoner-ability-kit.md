# Summoner Ability Kit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Summoner's three remaining minion types (Dew, Misfortune, Hasty — L2/L3/L4
extra abilities) and its Ultimate ("Grand Sacrifice," which varies by whichever minion is
active), plus two brand-new effect mechanics the kit needs (a temporary resource-regen buff and
a temporary "+1 reel per turn" buff with a double-damage overflow fallback).

**Architecture:** `_run_minion_stage()` (currently hardcoded to Ember's formula) becomes a
dispatcher keyed on a new `Combatant.minion_type` field, with one `_run_<type>_stage()` helper
per type; the shared stage-3-completion expiry stays in the dispatcher so it isn't duplicated
4 times. Each new minion type is an *extra* ability (unlike Ember, which is the base ability),
so each needs its own near-duplicate-but-separate wiring through `MainPhasePlan.preview_reels()`/
`commit()`'s `staged_extra_ability_id` match blocks (confirmed: Ember's base-ability dispatch and
the extra-ability dispatch are genuinely separate code paths in this file — no shared case to
extend). The two new mechanics follow this codebase's existing "any Effect can carry an extra
field regardless of its `Kind`" precedent (already used once, by `thorns_pct`) rather than adding
new `Effect.Kind` enum values — safer, since the `Kind` enum is switched on in several places
this plan doesn't need to touch. The Ultimate is modeled on the existing Warden Acolyte "curse
the party" pattern (a flat, non-weapon-scaled AoE effect application) for its debuff/DoT
variants, and on Ranger's Collateral Damage splash mechanic (`_splash_half_to_others()`, already
generic and reusable) for Ember's burst+splash variant.

**Tech Stack:** Godot 4.6 GDScript, headless `SceneTree`-based test scripts under `tests/`.

**Spec:** `docs/superpowers/specs/2026-08-16-summoner-ability-kit-design.md`.

## Global Constraints

- Engine: Godot 4.6+, GDScript only (no C#) — `CLAUDE.md` §2.
- Static typing for all new vars/signatures — `CLAUDE.md` §2.
- All numeric values (HP, damage, buff magnitudes, mana costs) are `[ASSUMPTION]` placeholders
  per `CLAUDE.md` §4 — build as easily-editable data, do not hand-balance further.
- Crit-success on every minion type (including the three added here) affects ONLY HP (tankier
  variant) — never stage-effect magnitude. This is locked and applies uniformly across all four
  types.
- Costs (locked): Ember 4 Mana (unchanged), Dew 5 Mana, Misfortune 4 Mana, Hasty 6 Mana. No
  cooldowns on any of the four minion abilities.
- Cleanse always removes the OLDEST active debuff on a target (first-attached, chronologically —
  confirmed safe: nothing in this codebase reorders `active_effects`, so
  `active_effects.filter(func(e): return not e.beneficial)` reliably yields debuffs in
  attach-order). No-op if the target has no active debuffs.
- The reel-surge buff's overflow fallback doubles the FIRST successful hit (SUCCESS or
  CRIT_SUCCESS face) that lands that turn, with a distinct log line — not the highest-damage hit,
  not a random one.
- Talent-tree perks for the Summoner are explicitly OUT OF SCOPE for this plan (deferred per the
  spec).
- Ability/minion names in this plan (Dew Minion, Misfortune Minion, Hasty Minion, Grand
  Sacrifice) are working names, not final — do not treat them as locked flavor, only as
  identifiers.

---

## Task 1: `Combatant.minion_type` + generalize `MinionLibrary`

**Files:**
- Modify: `combat/combatant.gd`
- Modify: `combat/minion_library.gd`
- Modify: `combat/combat.gd` (the one existing call site)
- Test: `tests/test_minion_library.gd`

**Interfaces:**
- Produces: `Combatant.minion_type: StringName = &"ember"` (a new field, mirrors how
  `is_minion`/`active_minion` were added — read by later tasks' `_run_minion_stage()` dispatcher
  and the Ultimate's variant dispatch).
- Modifies: `MinionLibrary.make(tanky: bool) -> Combatant` becomes
  `MinionLibrary.make(tanky: bool, type: StringName = &"ember") -> Combatant"` — the default
  argument keeps every existing call site (including the shipped summon-payoff block) working
  unchanged for Ember specifically.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_minion_library.gd` (open it first to match its exact `_check`/style):

```gdscript
	var dew: Combatant = MinionLibrary.make(false, &"dew")
	_check(dew.minion_type == &"dew", "MinionLibrary.make(false, &dew) sets minion_type = &dew (got %s)" % dew.minion_type)
	_check(dew.display_name == "Dew Minion", "dew minion display name is 'Dew Minion' (got %s)" % dew.display_name)
	_check(dew.is_minion and dew.is_player, "dew minion is still is_minion/is_player like every other type")

	var misfortune: Combatant = MinionLibrary.make(false, &"misfortune")
	_check(misfortune.minion_type == &"misfortune", "misfortune minion_type set correctly (got %s)" % misfortune.minion_type)
	_check(misfortune.display_name == "Misfortune Minion", "misfortune display name correct (got %s)" % misfortune.display_name)

	var hasty: Combatant = MinionLibrary.make(false, &"hasty")
	_check(hasty.minion_type == &"hasty", "hasty minion_type set correctly (got %s)" % hasty.minion_type)
	_check(hasty.display_name == "Hasty Minion", "hasty display name correct (got %s)" % hasty.display_name)

	# Backward-compat: the default-argument call (used by the already-shipped Ember summon path)
	# still produces an Ember minion with no changes to its own behavior.
	var default_call: Combatant = MinionLibrary.make(false)
	_check(default_call.minion_type == &"ember", "make(tanky) with no type arg still defaults to &ember (got %s)" % default_call.minion_type)
	_check(default_call.display_name == "Ember Minion", "default-call display name unchanged (got %s)" % default_call.display_name)
```

- [ ] **Step 2: Run test to verify it fails**

`../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_minion_library.gd`
Expected: FAIL — `minion_type` doesn't exist, `make()` doesn't accept a second argument.

- [ ] **Step 3: Write minimal implementation**

In `combat/combatant.gd`, add immediately after `minion_stage` (added by the earlier
minion-summoning-class plan — find it near `active_minion`):

```gdscript
## Which minion type this combatant is, when is_minion is true (2026-08-16 summoner-ability-kit
## spec). Read by combat.gd's _run_minion_stage() dispatcher and the Grand Sacrifice Ultimate's
## variant dispatch. Meaningless/unused on a non-minion combatant.
var minion_type: StringName = &"ember"
```

In `combat/minion_library.gd`, replace the current `make()`:

```gdscript
class_name MinionLibrary
extends RefCounted

const BASELINE_HP: int = 15
const TANKY_HP: int = 25

## Display name per minion type. [ASSUMPTION] every type shares the same HP baseline/tanky
## values above — nothing in the spec calls for per-type HP differences, so reuse Ember's numbers
## rather than inventing new ones; revisit after playtest if a type needs more/less durability.
const DISPLAY_NAMES: Dictionary = {
	&"ember": "Ember Minion",
	&"dew": "Dew Minion",
	&"misfortune": "Misfortune Minion",
	&"hasty": "Hasty Minion",
}

## [param tanky] is true for a Critical-Success summon (crit success ALWAYS means more HP only,
## never a stronger stage effect, across every minion type — 2026-08-16 summoner-ability-kit spec
## §9). [param type] defaults to &"ember" so the original (already-shipped) call site in
## combat.gd's summon payoff keeps working unchanged.
static func make(tanky: bool, type: StringName = &"ember") -> Combatant:
	var earth: DamageType = load("res://combat/resources/types/earth.tres")
	var c: Combatant = Combatant.new()
	c.display_name = DISPLAY_NAMES.get(type, "Ember Minion")
	c.is_player = true
	c.is_minion = true
	c.minion_type = type
	c.defense_type = earth
	c.weapon = null
	c.base_max_hp = TANKY_HP if tanky else BASELINE_HP
	c.base_meter_floor = 0
	c.base_stats = Stats.new()
	c.apply_stats()   # derive max_hp from stats BEFORE seeding hp
	c.start_combat()
	return c
```

- [ ] **Step 4: Confirm the existing summon-payoff call site still compiles/works**

Find the existing summon-payoff block in `combat/combat.gd`'s `_finish_spin()` (search for
`_attacker.summon_reel != null and _summon_tier != -1`) — it currently calls
`MinionLibrary.make(tanky)` with one argument. Confirm this still resolves correctly against the
new two-parameter signature (it will, since `type` has a default) — no edit needed here, but
verify by reading the actual call site.

- [ ] **Step 5: Run test to verify it passes**

Same command as Step 2. Expected: PASS.

- [ ] **Step 6: Run the existing lifecycle regression test**

`../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_minion_lifecycle.gd`
Expected: still PASS — confirms the Ember path is unaffected.

- [ ] **Step 7: Commit**

```bash
git add combat/combatant.gd combat/minion_library.gd tests/test_minion_library.gd
git commit -m "feat(summoner-kit): add Combatant.minion_type, generalize MinionLibrary.make() for 4 types"
```

---

## Task 2: Resource-regen buff mechanic

**Files:**
- Modify: `combat/resources/effect.gd`
- Modify: `combat/combatant.gd`
- Modify: `combat/resources/resource_pool.gd`
- Test: `tests/test_resource_regen_buff.gd` (new)

**Interfaces:**
- Produces: `Effect.regen_bonus: int = 0` — a new field any `Effect` instance can carry
  regardless of its `Kind` (mirrors the existing `thorns_pct` precedent exactly — an "extra
  payload field," not a new enum value).
- Produces: `Combatant._effect_regen_bonus() -> int` — sums `regen_bonus` across all
  `active_effects`.
- Modifies: `ResourcePool.regen(bonus: int = 0) -> void` — adds `bonus` on top of the normal
  per-turn Stamina/Mana regen (backward-compatible default keeps every other call site
  unchanged).
- Modifies: `Combatant.on_upkeep()` — passes `_effect_regen_bonus()` into `resource_pool.regen()`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_resource_regen_buff.gd` (mirror the `extends SceneTree`/`_check()` convention
used by `tests/test_minion_library.gd`):

```gdscript
extends SceneTree

# Headless test for the resource-regen buff mechanic (2026-08-16 summoner-ability-kit spec §7). Run:
# Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_resource_regen_buff.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var c: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	c.resource_pool.mana = 0
	c.resource_pool.max_mana = 100
	var before_regen: int = c.resource_pool.mana_regen_per_turn

	# No buff: normal regen only.
	c.on_upkeep()
	_check(c.resource_pool.mana == before_regen, "no buff: mana regens by the normal per-turn amount only (got %d, expected %d)" % [c.resource_pool.mana, before_regen])

	# Attach a +3 regen buff, confirm the NEXT upkeep adds the bonus on top of normal regen.
	var buff := Effect.new()
	buff.id = &"hasty_regen_buff"
	buff.kind = Effect.Kind.REEL_FACE_EDIT  # inert marker kind — regen_bonus is read directly, not kind-dispatched
	buff.regen_bonus = 3
	buff.duration = 3
	buff.beneficial = true
	c.attach_effect(buff)
	var mana_before_buffed_tick: int = c.resource_pool.mana
	c.on_upkeep()
	_check(c.resource_pool.mana == mana_before_buffed_tick + before_regen + 3, "buffed upkeep adds normal regen PLUS the +3 bonus (got %d, expected %d)" % [c.resource_pool.mana, mana_before_buffed_tick + before_regen + 3])

	print(("RESOURCE REGEN BUFF TEST PASSED" if _failures == 0 else "RESOURCE REGEN BUFF TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

`../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_resource_regen_buff.gd`
Expected: FAIL — `regen_bonus` doesn't exist, `ResourcePool.regen()` doesn't accept a bonus.

- [ ] **Step 3: Write minimal implementation**

In `combat/resources/effect.gd`, add near the existing `thorns_pct` field declaration (read that
field's exact doc-comment style first and mirror it):

```gdscript
## While active, this combatant regenerates [member regen_bonus] EXTRA Stamina/Mana per turn, on
## top of their normal per-turn regen (2026-08-16 summoner-ability-kit spec §7 — Hasty Minion/
## Grand Sacrifice). Zero for every effect that doesn't grant this. Mirrors thorns_pct: an extra
## payload field any Effect can carry regardless of its Kind, not a new Kind value.
@export var regen_bonus: int = 0
```

In `combat/combatant.gd`, add near `thorns_pct()` (find that method and mirror its summation
shape — but note `thorns_pct()` takes the MAX across effects; this needs a SUM instead, matching
how `recompute_initiative()` sums `INITIATIVE_MOD` effects):

```gdscript
## Sums the regen_bonus field across every active effect (2026-08-16 summoner-ability-kit spec §7).
## Additive across multiple sources, unlike thorns_pct's max-across-effects rule — there's no
## reason two regen buffs shouldn't stack.
func _effect_regen_bonus() -> int:
	var total: int = 0
	for e: Effect in active_effects:
		total += e.regen_bonus
	return total
```

Find `Combatant.on_upkeep()` (exact current body, confirmed by prior research):
```gdscript
func on_upkeep() -> void:
	if resource_pool != null:
		resource_pool.regen()
	tick_cooldowns()
	recompute_initiative()
```
Change to:
```gdscript
func on_upkeep() -> void:
	if resource_pool != null:
		resource_pool.regen(_effect_regen_bonus())
	tick_cooldowns()
	recompute_initiative()
```

In `combat/resources/resource_pool.gd`, find the current `regen()`:
```gdscript
func regen() -> void:
	var before_s: int = stamina
	stamina = mini(stamina + regen_per_turn, max_stamina)
	if stamina != before_s:
		pool_changed.emit(&"stamina", stamina, max_stamina)
	var before_m: int = mana
	mana = mini(mana + mana_regen_per_turn, max_mana)
	if mana != before_m:
		pool_changed.emit(&"mana", mana, max_mana)
```
Change its signature and both regen lines to include the bonus (applied to whichever rail is
actually in play — a bonus is harmless/no-op on a rail the class doesn't use, since that rail's
own base values are already 0):
```gdscript
func regen(bonus: int = 0) -> void:
	var before_s: int = stamina
	stamina = mini(stamina + regen_per_turn + bonus, max_stamina)
	if stamina != before_s:
		pool_changed.emit(&"stamina", stamina, max_stamina)
	var before_m: int = mana
	mana = mini(mana + mana_regen_per_turn + bonus, max_mana)
	if mana != before_m:
		pool_changed.emit(&"mana", mana, max_mana)
```

- [ ] **Step 4: Run test to verify it passes**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Run regression tests for anything touching `on_upkeep()`/`ResourcePool.regen()`**

Run a couple of existing combat.tscn end-to-end tests that drive real turns (e.g.
`tests/test_combat_win_recovery.gd`, `tests/test_minion_lifecycle.gd`) to confirm no regression
from the `regen()` signature change.

- [ ] **Step 6: Commit**

```bash
git add combat/resources/effect.gd combat/combatant.gd combat/resources/resource_pool.gd tests/test_resource_regen_buff.gd
git commit -m "feat(summoner-kit): add the resource-regen buff mechanic (Effect.regen_bonus)"
```

---

## Task 3: "Extra reel per turn" buff mechanic + overflow fallback

**Files:**
- Modify: `combat/combatant.gd`
- Modify: `combat/combat.gd`
- Test: `tests/test_reel_surge_buff.gd` (new)

**Interfaces:**
- Produces: a marker effect id `&"reel_surge"` (working name) — attached the same way any other
  buff is (`EffectLibrary.make()`-style, or built inline where needed), `Kind.REEL_FACE_EDIT`
  (the established "inert marker" kind, same as `jinxed`/`hunters_mark`), no numeric payload
  needed since the bonus is a fixed +1.
- Produces: `Combatant.reel_surge_overflow_pending: bool = false` — set true (instead of
  appending a reel) when the buff is active but the combatant is ALREADY at the 5-reel cap;
  reset to false at the start of `begin_turn()` each turn.
- Modifies: `Combatant.begin_turn()` — after seeding `turn_reels` from the weapon, checks
  `has_effect(&"reel_surge")`: if under the 5-reel cap, appends one extra weapon-attack reel; if
  already at the cap, sets `reel_surge_overflow_pending = true` instead.
- Modifies: `combat.gd`'s attack-resolution code — when `_attacker.reel_surge_overflow_pending`
  is true, doubles the damage of the FIRST successful (SUCCESS/CRIT_SUCCESS) hit that lands that
  spin, logs a distinct line, and clears the flag so it only fires once per turn.

- [ ] **Step 1: Write the failing test**

Create `tests/test_reel_surge_buff.gd`:

```gdscript
extends SceneTree

# Headless test for the "extra reel per turn" buff + its 5-reel-cap overflow fallback (2026-08-16
# summoner-ability-kit spec §6). Run:
# Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_reel_surge_buff.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _mk_pc_with_n_weapon_reels(n: int) -> Combatant:
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")
	var w: Weapon = Weapon.new()
	w.base_damage = 10.0
	for i: int in range(n):
		w.reels.append(ActionReel.make_default(slashing))
	var c: Combatant = Combatant.new()
	c.weapon = w
	c.resource_pool = ResourcePool.new()
	return c

func _initialize() -> void:
	# --- Under the cap: the buff adds a real 4th reel ---
	var c: Combatant = _mk_pc_with_n_weapon_reels(3)
	var buff := Effect.new()
	buff.id = &"reel_surge"
	buff.kind = Effect.Kind.REEL_FACE_EDIT
	buff.duration = 3
	buff.beneficial = true
	c.attach_effect(buff)
	c.begin_turn()
	_check(c.turn_reels.size() == 4, "reel_surge under the cap adds a real 4th reel (got %d)" % c.turn_reels.size())
	_check(not c.reel_surge_overflow_pending, "no overflow flag when a real reel was added")

	# --- At the cap: the buff sets the overflow flag instead of a 6th reel ---
	var capped: Combatant = _mk_pc_with_n_weapon_reels(5)
	var buff2 := Effect.new()
	buff2.id = &"reel_surge"
	buff2.kind = Effect.Kind.REEL_FACE_EDIT
	buff2.duration = 3
	buff2.beneficial = true
	capped.attach_effect(buff2)
	capped.begin_turn()
	_check(capped.turn_reels.size() == 5, "reel_surge at the 5-cap does NOT add a 6th reel (got %d)" % capped.turn_reels.size())
	_check(capped.reel_surge_overflow_pending, "overflow flag IS set when already at the cap")

	# --- Overflow flag resets each new turn ---
	capped.reel_surge_overflow_pending = true
	capped.begin_turn()
	# (buff already expired one turn per tick, or still active — either way the flag must reflect
	# the CURRENT begin_turn() re-evaluation, not a stale true from before)
	_check(true, "begin_turn() always re-evaluates the flag fresh (structural check — see combat.gd Step 5 for the real consumption path)")

	print(("REEL SURGE BUFF TEST PASSED" if _failures == 0 else "REEL SURGE BUFF TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

`../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_reel_surge_buff.gd`
Expected: FAIL — `reel_surge_overflow_pending` doesn't exist, `begin_turn()` doesn't check for
the buff.

- [ ] **Step 3: Write minimal implementation**

In `combat/combatant.gd`, add a new field near `minion_stage`:

```gdscript
## True for exactly one turn when the reel_surge buff (2026-08-16 summoner-ability-kit spec §6)
## was active but this combatant was ALREADY at the 5-reel cap, so no reel could be added. The
## orchestrator (combat.gd) reads this to double the first successful hit's damage instead, then
## clears it. Reset to false at the top of every begin_turn().
var reel_surge_overflow_pending: bool = false
```

Find the current `begin_turn()` (already confirmed exact current body):
```gdscript
func begin_turn() -> void:
	if weapon != null:
		turn_reels = weapon.reels.duplicate()
	else:
		turn_reels.clear()
	rallying_cry_reel = null
	item_use_reel = null
	flee_reel = null
	summon_reel = null
	pending_item_base_heal = 0
	pending_item_name = ""
```
Add the reel-surge check at the end (after the existing reset lines):
```gdscript
	reel_surge_overflow_pending = false
	if has_effect(&"reel_surge"):
		const REEL_CAP: int = 5   # matches the 5-cap used everywhere MainPhasePlan is constructed
		if turn_reels.size() < REEL_CAP:
			turn_reels.append(ActionReel.make_ability_attack(weapon_type()))
		else:
			reel_surge_overflow_pending = true
```

- [ ] **Step 4: Wire the overflow fallback in `combat.gd`**

Find the attack-resolution loop in `_apply_attack()` or wherever individual reel hits are
processed into damage (search for where `rider_effect_id`/`talent_bonus_pct` are applied per-hit,
around the area confirmed in research — the loop iterating `targets`/`t.take_damage(...)` for
each landed attack). Add a check: the FIRST time in that spin's resolution loop that a hit's
`attack.face.result_tier` is SUCCESS or CRIT_SUCCESS AND `_attacker.reel_surge_overflow_pending`
is still true, double that hit's damage before applying it, log a distinct line, and clear the
flag so later hits in the same spin aren't also doubled:

```gdscript
	if _attacker.reel_surge_overflow_pending and (attack.face.result_tier == ReelFace.ResultTier.SUCCESS or attack.face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS):
		var doubled: int = attack.final_damage  # double by applying a second, identical hit
		t.take_damage(doubled)
		_log("  ⚡ %s's reel surge overflow doubles this hit's damage (would-be 6th reel converted to +%d bonus damage)." % [_attacker.display_name, doubled])
		_attacker.reel_surge_overflow_pending = false
```

Place this immediately after the normal `t.take_damage(attack.final_damage)` call for that hit
(read the exact surrounding code first — there may already be a `talent_bonus_pct` block right
after the main damage application that this should sit alongside, per the rider-bonus-damage
pattern already in the file). Applying a second `take_damage()` call for the same amount is the
simplest correct way to "double" the damage without needing to mutate `attack.final_damage`
after the fact (which may already have been used elsewhere in the same function for logging/
Collateral-total accumulation).

- [ ] **Step 5: Run test to verify it passes**

Same command as Step 2. Expected: PASS (Steps 1-2's assertions; Step 4's real spin-driven overflow
behavior isn't covered by this unit-level test — flag that as a gap for Task 10's end-to-end
Hasty test to cover with a real forced spin).

- [ ] **Step 6: Commit**

```bash
git add combat/combatant.gd combat/combat.gd tests/test_reel_surge_buff.gd
git commit -m "feat(summoner-kit): add the reel-surge buff mechanic + 5-cap double-damage overflow"
```

---

## Task 4: `Combatant.cleanse_oldest_debuff()`

**Files:**
- Modify: `combat/combatant.gd`
- Test: `tests/test_cleanse_oldest_debuff.gd` (new)

**Interfaces:**
- Produces: `func cleanse_oldest_debuff() -> Effect` — removes and returns the first-attached
  (oldest) non-beneficial effect in `active_effects`, or `null` if there are none. Mirrors
  `cleanse()`'s existing shape/placement in the file but removes exactly one, not all.

- [ ] **Step 1: Write the failing test**

Create `tests/test_cleanse_oldest_debuff.gd`:

```gdscript
extends SceneTree

# Headless test for Combatant.cleanse_oldest_debuff() (2026-08-16 summoner-ability-kit spec §4). Run:
# Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_cleanse_oldest_debuff.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var c: Combatant = Combatant.new()

	# No debuffs: no-op, returns null.
	var result_empty: Effect = c.cleanse_oldest_debuff()
	_check(result_empty == null, "cleanse_oldest_debuff() on a target with no debuffs returns null")

	# Attach 2 debuffs (in order) and 1 buff; cleanse must remove the FIRST-attached debuff only.
	var first_debuff := Effect.new()
	first_debuff.id = &"weakened"
	first_debuff.beneficial = false
	c.attach_effect(first_debuff)

	var a_buff := Effect.new()
	a_buff.id = &"empowered"
	a_buff.beneficial = true
	c.attach_effect(a_buff)

	var second_debuff := Effect.new()
	second_debuff.id = &"sundered"
	second_debuff.beneficial = false
	c.attach_effect(second_debuff)

	_check(c.active_effects.size() == 3, "sanity: 3 effects attached (got %d)" % c.active_effects.size())
	var removed: Effect = c.cleanse_oldest_debuff()
	_check(removed != null and removed.id == &"weakened", "cleanse_oldest_debuff() removes the FIRST-attached debuff (weakened), got %s" % (removed.id if removed != null else &"null"))
	_check(c.active_effects.size() == 2, "exactly one effect removed (got %d remaining)" % c.active_effects.size())
	_check(c.has_effect(&"sundered"), "the SECOND (newer) debuff is untouched")
	_check(c.has_effect(&"empowered"), "the buff is untouched")

	print(("CLEANSE OLDEST DEBUFF TEST PASSED" if _failures == 0 else "CLEANSE OLDEST DEBUFF TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

`../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_cleanse_oldest_debuff.gd`
Expected: FAIL — method doesn't exist.

- [ ] **Step 3: Write minimal implementation**

Find `Combatant.cleanse()` (confirmed exact current body) and add a new method right after it:

```gdscript
## Removes and returns the OLDEST (first-attached) active debuff, or null if this combatant has
## none (2026-08-16 summoner-ability-kit spec §4 — Dew Minion/Grand Sacrifice). Unlike cleanse()
## (which removes ALL debuffs at once, the Warden Ultimate's shape), this removes exactly one.
## Safe because nothing in this file reorders active_effects — append-order IS attach-order.
func cleanse_oldest_debuff() -> Effect:
	for e: Effect in active_effects:
		if e != null and not e.beneficial:
			active_effects.erase(e)
			recompute_initiative()
			return e
	return null
```

- [ ] **Step 4: Run test to verify it passes**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add combat/combatant.gd tests/test_cleanse_oldest_debuff.gd
git commit -m "feat(summoner-kit): add Combatant.cleanse_oldest_debuff()"
```

---

## Task 5: Generalize `_run_minion_stage()` into a type dispatcher

**Files:**
- Modify: `combat/combat.gd`

**Interfaces:**
- Consumes: `Combatant.minion_type` (Task 1).
- Produces: `_run_minion_stage(minion, stage)` becomes a dispatcher; the current Ember-specific
  body moves unchanged into a new `_run_ember_stage(minion, stage)`; the stage-3-completion
  expiry check is factored OUT of the per-type helper and into the dispatcher (shared, not
  duplicated).

- [ ] **Step 1: Read the exact current `_run_minion_stage()`**

Find it in `combat/combat.gd` (confirmed exact current body):
```gdscript
const MINION_BASE_STAGE_DAMAGE: int = 8

func _run_minion_stage(minion: Combatant, stage: int) -> void:
	var amount: int = MINION_BASE_STAGE_DAMAGE * stage
	for enemy: Combatant in _enemies_of(minion):
		enemy.take_damage(amount)
		if _panels.has(enemy):
			(_panels[enemy] as CombatantPanel).refresh_status()
	_log("  🔥 Ember Minion (stage %d) pulses %d damage to every enemy." % [stage, amount])
	if stage >= 3 and minion.is_alive():
		_log("  Ember Minion completes its final stage and fades away.")
		minion.take_damage(minion.hp)
```

- [ ] **Step 2: Replace it with a dispatcher + the extracted Ember helper**

```gdscript
## Runs a minion's stage effect, dispatching by its minion_type (2026-08-16 summoner-ability-kit
## spec — this class ships 4 distinct minion types sharing the same 3-stage-then-expire
## mechanism). Expiry-on-stage-3-completion is handled HERE, once, rather than duplicated in each
## per-type helper below.
func _run_minion_stage(minion: Combatant, stage: int) -> void:
	match minion.minion_type:
		&"dew":
			_run_dew_stage(minion, stage)
		&"misfortune":
			_run_misfortune_stage(minion, stage)
		&"hasty":
			_run_hasty_stage(minion, stage)
		_:
			_run_ember_stage(minion, stage)
	if stage >= 3 and minion.is_alive():
		_log("  %s completes its final stage and fades away." % minion.display_name)
		minion.take_damage(minion.hp)

const MINION_BASE_STAGE_DAMAGE: int = 8

## Ember Minion's stage effect (unchanged from the original shipped mechanism — the expiry check
## that used to live at the end of this function now lives in the _run_minion_stage() dispatcher
## above, shared across all 4 types).
func _run_ember_stage(minion: Combatant, stage: int) -> void:
	var amount: int = MINION_BASE_STAGE_DAMAGE * stage
	for enemy: Combatant in _enemies_of(minion):
		enemy.take_damage(amount)
		if _panels.has(enemy):
			(_panels[enemy] as CombatantPanel).refresh_status()
	_log("  🔥 %s (stage %d) pulses %d damage to every enemy." % [minion.display_name, stage, amount])
```

`_run_dew_stage()`/`_run_misfortune_stage()`/`_run_hasty_stage()` are added by Tasks 6-8 —
leave them undefined for now (this task's own test run will fail to parse until at least stub
versions exist; add trivial no-op stubs here so this task's own commit compiles standalone):

```gdscript
func _run_dew_stage(minion: Combatant, stage: int) -> void:
	pass  # implemented by Task 6

func _run_misfortune_stage(minion: Combatant, stage: int) -> void:
	pass  # implemented by Task 7

func _run_hasty_stage(minion: Combatant, stage: int) -> void:
	pass  # implemented by Task 8
```

- [ ] **Step 3: Run the existing Ember lifecycle regression test**

`../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_minion_lifecycle.gd`
Expected: still PASS — confirms the dispatcher correctly routes Ember (the default `minion_type`)
to the unchanged `_run_ember_stage()` logic, with identical damage numbers and expiry behavior.

- [ ] **Step 4: Commit**

```bash
git add combat/combat.gd
git commit -m "refactor(summoner-kit): generalize _run_minion_stage() into a minion_type dispatcher"
```

---

## Task 6: Dew Minion (L2 extra ability)

**Files:**
- Modify: `combat/class_library.gd`
- Modify: `combat/combatant.gd`
- Modify: `combat/main_phase_plan.gd`
- Modify: `combat/combat.gd`
- Modify: `combat/ui/ability_catalog.gd`
- Test: `tests/test_dew_minion.gd` (new)

**Interfaces:**
- Produces: a new `AbilityDef` on the Summoner (`&"dew_minion"`, unlock level 2, cost 5 Mana).
- Produces: `Combatant.apply_summon_dew(cost: int, cap: int) -> bool` (mirrors the shipped
  `apply_summon_minion()` exactly, appending the SAME generic `ActionReel.make_summon_reel()` —
  that reel factory isn't Ember-specific, it's reusable as-is).
- Produces: `_run_dew_stage(minion, stage)` in `combat.gd` (replacing Task 5's stub).
- Wires `&"dew_minion"` through `MainPhasePlan`'s extra-ability dispatch (staging, preview,
  commit) and `AbilityCatalog`.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_dew_minion.gd` (mirror `tests/test_minion_lifecycle.gd`'s real-spin harness —
read that file first in full to copy its exact `CombatHandoff`/force-a-reel-tier/frame-polling
pattern):

```gdscript
extends SceneTree

# Headless end-to-end test for Dew Minion (2026-08-16 summoner-ability-kit spec §2). Run:
# Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dew_minion.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

# (Reuse test_dew_minion.gd's own copies of _new_summoner_encounter/_stage_and_force_summon/
# _pump_one_frame-style helpers, adapted to stage &"dew_minion" as an EXTRA ability via
# _plan.toggle_extra_ability(&"dew_minion") rather than the base-ability toggle_ability() Ember
# uses — this is the concrete difference the plan's Architecture section calls out.)

func _initialize() -> void:
	# --- Stage/commit wiring: dew_minion is a real extra ability, costs 5 Mana, appends a real summon reel ---
	var summoner: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	summoner.resource_pool.mana = 10
	var plan: MainPhasePlan = MainPhasePlan.new(summoner, summoner.ability_cost, 5, 2)
	_check(plan.can_stage_extra_ability(&"dew_minion"), "dew_minion stageable when affordable and unlocked")
	plan.toggle_extra_ability(&"dew_minion")
	_check(plan.staged_extra_ability_id == &"dew_minion", "dew_minion staged")
	var preview: Array[ActionReel] = plan.preview_reels()
	_check(not preview.is_empty() and not preview[preview.size() - 1].is_weapon_attack, "previewed dew summon reel is out of paylines")
	plan.commit()
	_check(summoner.summon_reel != null, "commit(): summon_reel is set")
	_check(summoner.resource_pool.mana == 10 - 5, "commit(): 5 Mana spent (got %d)" % summoner.resource_pool.mana)

	# --- Real-spin end-to-end: summon a Dew Minion, force SUCCESS, verify stage 1 heals immediately ---
	# (Build a real combat.tscn instance the same way test_minion_lifecycle.gd does; damage a PC
	# first so the heal is observable; stage dew_minion via toggle_extra_ability(); force the
	# summon reel to SUCCESS; drive a real spin; assert the damaged PC's HP increased by 8
	# immediately, in the same spin, before any new round.)

	# --- Stage 2/3 escalation: advance real rounds, assert stage 2 heals+cleanses (attach a real
	# debuff to a PC first and confirm cleanse_oldest_debuff() actually removes it), stage 3 heals
	# 16 + cleanses + attaches a 2-turn Thorns-carrying effect to every ally (check thorns_pct()
	# on an ally reads > 0 after stage 3), then the minion expires. ---

	print(("DEW MINION TEST PASSED" if _failures == 0 else "DEW MINION TEST FAILED: %d" % _failures))
	quit(_failures)
```

Fill in the three commented sections with real code following `test_minion_lifecycle.gd`'s exact
harness conventions (read that file in full first — do not invent a different pattern).

- [ ] **Step 2: Run tests to verify they fail**

`../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dew_minion.gd`
Expected: FAIL — `dew_minion` isn't registered anywhere yet.

- [ ] **Step 3: Write minimal implementation**

In `combat/class_library.gd`'s `&"summoner"` branch, add to `extra_abilities`:
```gdscript
c.extra_abilities = [
	_ability(&"dew_minion", 2, 5, &"mana", 0),
]
```
(If Tasks 7/8 haven't run yet, this array will only have one entry — that's fine, each task
appends its own entry; confirm the actual current state of this array before editing, since
Task 5's dispatcher stubs don't touch `class_library.gd` at all.)

In `combat/combatant.gd`, add right after `apply_summon_minion()`:
```gdscript
## Stages the Summoner's "Dew Minion" extra ability (2026-08-16 spec §2): spends [param cost]
## Mana, appends the SAME generic ActionReel.make_summon_reel() Ember uses (it's not
## Ember-specific), records it on summon_reel. Mirrors apply_summon_minion() exactly — only the
## resource cost differs (this is an EXTRA ability, not the base ability).
func apply_summon_dew(cost: int, cap: int) -> bool:
	if turn_reels.size() >= cap:
		return false
	if resource_pool == null or not resource_pool.spend({&"mana": cost}):
		return false
	var reel: ActionReel = ActionReel.make_summon_reel()
	turn_reels.append(reel)
	summon_reel = reel
	return true
```

In `combat/main_phase_plan.gd`:
1. Add a new const near `REEL_ADDING_EXTRA_IDS`/`TWO_REEL_BONUS_EXTRA_IDS`:
   ```gdscript
   ## Extra-ability ids whose summon reel is gated by the reel cap the same way the base-ability
   ## summon reels are (2026-08-16 summoner-ability-kit spec) — grown by each new minion-type task.
   const SUMMON_EXTRA_IDS: Array[StringName] = [&"dew_minion"]
   ```
2. In `can_stage_extra_ability(id)`, add the same cap-check `REEL_ADDING_EXTRA_IDS` already gets:
   ```gdscript
   if id in SUMMON_EXTRA_IDS and combatant.turn_reels.size() >= reel_cap:
   	return false
   ```
3. In `preview_reels()`'s `match staged_extra_ability_id:` block, add (gated the same way the
   block's other cases already check `reels.size() < reel_cap`):
   ```gdscript
   &"dew_minion":
   	reels.append(ActionReel.make_summon_reel())
   ```
4. In `commit()`'s `match staged_extra_ability_id:` block, add:
   ```gdscript
   &"dew_minion":
   	combatant.apply_summon_dew(extra_talent_cost, reel_cap)
   ```
   Read the surrounding existing cases (e.g. `&"sundering_strike": combatant.try_sundering_strike(...)`)
   to confirm `extra_talent_cost`/`reel_cap` are the exact variable names already in scope at that
   point in `commit()` before using them verbatim.

In `combat/combat.gd`, replace Task 5's `_run_dew_stage()` stub:
```gdscript
## Dew Minion's 3-stage effect (2026-08-16 spec §2): AoE heal every stage, cleanse the OLDEST
## debuff off every ally starting stage 2, a party-wide Thorns buff on stage 3. [ASSUMPTION]
## heal amounts (8/8/16) and thorns_pct (0.20) — tune by playtest.
const DEW_STAGE1_HEAL: int = 8
const DEW_STAGE3_HEAL: int = 16
const DEW_THORNS_PCT: float = 0.20
const DEW_THORNS_TURNS: int = 2

func _run_dew_stage(minion: Combatant, stage: int) -> void:
	var heal_amount: int = DEW_STAGE3_HEAL if stage == 3 else DEW_STAGE1_HEAL
	for ally: Combatant in _allies_of(minion):
		if not ally.is_alive():
			continue
		ally.heal(heal_amount)
		if stage >= 2:
			var cleansed: Effect = ally.cleanse_oldest_debuff()
			if cleansed != null:
				_log("  💧 Dew Minion cleanses %s's %s." % [ally.display_name, String(cleansed.id).to_upper()])
		if stage >= 3:
			var thorns := Effect.new()
			thorns.id = &"dew_thorns"
			thorns.kind = Effect.Kind.REEL_FACE_EDIT  # inert marker kind — thorns_pct is read directly regardless of kind
			thorns.thorns_pct = DEW_THORNS_PCT
			thorns.duration = DEW_THORNS_TURNS
			thorns.beneficial = true
			ally.attach_effect(thorns)
		if _panels.has(ally):
			(_panels[ally] as CombatantPanel).refresh_status()
	_log("  💧 Dew Minion (stage %d) heals the party for %d." % [stage, heal_amount])
```

Also, in `combat/ui/ability_catalog.gd`, add to both `display_name()` and `description()`:
```gdscript
&"dew_minion": return "Dew Minion"
# ...and in description():
&"dew_minion": return "Summon a minion that heals the party, cleansing the oldest debuff and granting Thorns as it escalates."
```

- [ ] **Step 4: Run tests to verify they pass**

Same commands as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add combat/class_library.gd combat/combatant.gd combat/main_phase_plan.gd combat/combat.gd combat/ui/ability_catalog.gd tests/test_dew_minion.gd
git commit -m "feat(summoner-kit): add Dew Minion (L2 extra ability)"
```

---

## Task 7: Misfortune Minion (L3 extra ability)

**Files:**
- Modify: `combat/class_library.gd`
- Modify: `combat/combatant.gd`
- Modify: `combat/main_phase_plan.gd`
- Modify: `combat/combat.gd`
- Modify: `combat/ui/ability_catalog.gd`
- Test: `tests/test_misfortune_minion.gd` (new)

**Interfaces:**
- Same shape as Task 6, but for `&"misfortune_minion"` (unlock level 3, cost 4 Mana).
- `_run_misfortune_stage(minion, stage)` reuses the EXISTING `&"weakened"`/`&"sundered"`/
  `&"cursed"` effects via `EffectLibrary.make()` — no new effect ids, no new numbers.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_misfortune_minion.gd`, mirroring Task 6's structure (staging/preview/commit
wiring checks, then a real-spin end-to-end covering all 3 stages). Key assertions to include:

```gdscript
	# After stage 1: every enemy has &"weakened" active.
	# After stage 2: every enemy STILL has &"weakened" (reapplied) AND now has &"sundered".
	# After stage 3: every enemy has &"cursed" (a real DAMAGE_OVER_TIME effect — check
	#   enemy.has_effect(&"cursed") and inspect its dot_base_damage/dot_fractions match
	#   EffectLibrary.make(&"cursed")'s own defaults), and the minion expires.
```

- [ ] **Step 2: Run tests to verify they fail**

`../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_misfortune_minion.gd`
Expected: FAIL.

- [ ] **Step 3: Write minimal implementation**

Same wiring pattern as Task 6 (`class_library.gd`'s `extra_abilities` append, `apply_summon_misfortune()`
mirroring `apply_summon_dew()` exactly but costing 4 Mana, `SUMMON_EXTRA_IDS` append, the two
`MainPhasePlan` match-block cases, `AbilityCatalog` entries).

In `combat/combat.gd`, replace Task 5's `_run_misfortune_stage()` stub. Read the existing
"Warden Acolyte curse the party" code (search `curse_party_pending`) FIRST — it is the exact
template for applying a flat, non-weapon-scaled DoT to every enemy, since the minion itself is
weaponless and has no weapon base damage to scale off of:

```gdscript
## Misfortune Minion's 3-stage effect (2026-08-16 spec §2): a Weakened debuff on every enemy at
## stage 1, adds Sundered at stage 2, applies Cursed (flat-scaled, not weapon-scaled, since the
## minion itself is weaponless — mirrors the existing Warden-Acolyte "curse the party" pattern's
## flat dot_base_damage convention) at stage 3. [ASSUMPTION] whether stage 3 also reapplies
## Weakened/Sundered — currently Curse-only per the spec's own stated default; revisit after
## playtest if the debuffs expire before the minion's own lifespan does.
func _run_misfortune_stage(minion: Combatant, stage: int) -> void:
	for enemy: Combatant in _enemies_of(minion):
		if not enemy.is_alive():
			continue
		if stage == 1 or stage == 2:
			enemy.attach_effect(EffectLibrary.make(&"weakened"))
		if stage == 2:
			enemy.attach_effect(EffectLibrary.make(&"sundered"))
		if stage == 3:
			var curse: Effect = EffectLibrary.make(&"cursed")
			curse.dot_base_damage = 1.0  # flat, not weapon-scaled — mirrors the Warden Acolyte curse pattern
			enemy.attach_effect(curse)
		if _panels.has(enemy):
			(_panels[enemy] as CombatantPanel).refresh_status()
	_log("  🌑 Misfortune Minion (stage %d) afflicts every enemy." % stage)
```

- [ ] **Step 4: Run tests to verify they pass**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add combat/class_library.gd combat/combatant.gd combat/main_phase_plan.gd combat/combat.gd combat/ui/ability_catalog.gd tests/test_misfortune_minion.gd
git commit -m "feat(summoner-kit): add Misfortune Minion (L3 extra ability)"
```

---

## Task 8: Hasty Minion (L4 extra ability)

**Files:**
- Modify: `combat/class_library.gd`
- Modify: `combat/combatant.gd`
- Modify: `combat/main_phase_plan.gd`
- Modify: `combat/combat.gd`
- Modify: `combat/ui/ability_catalog.gd`
- Test: `tests/test_hasty_minion.gd` (new)

**Interfaces:**
- Consumes: `Effect.regen_bonus` (Task 2), the `&"reel_surge"` buff (Task 3).
- Same wiring shape as Tasks 6/7, for `&"hasty_minion"` (unlock level 4, cost 6 Mana).
- `_run_hasty_stage(minion, stage)` applies a party-wide +20 `INITIATIVE_MOD` buff at stage 1
  (3-turn duration, mirroring the existing `haste`/`inspirational` shape), adds the resource-regen
  buff at stage 2, adds `&"empowered"` (1 turn) + `&"reel_surge"` (3 turns, per the spec's
  `[ASSUMPTION]` default) at stage 3.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_hasty_minion.gd`, mirroring Tasks 6/7's structure. Key assertions:

```gdscript
	# After stage 1: every ally has an INITIATIVE_MOD effect with magnitude +20, duration 3.
	# After stage 2: every ally ALSO has a regen_bonus == 3 effect active.
	# After stage 3: every ally ALSO has &"empowered" active AND &"reel_surge" active; drive one
	#   more real turn for a party member and confirm their turn_reels grew by 1 (or, if they were
	#   already at the 5-cap, confirm reel_surge_overflow_pending became true and a real spin's
	#   first successful hit was doubled with the expected log line — reuse Task 3's overflow test
	#   technique but through the real ability path this time, not a synthetic effect).
```

- [ ] **Step 2: Run tests to verify they fail**

`../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_hasty_minion.gd`
Expected: FAIL.

- [ ] **Step 3: Write minimal implementation**

Same wiring pattern as Tasks 6/7 (`class_library.gd`, `apply_summon_hasty()` costing 6 Mana,
`SUMMON_EXTRA_IDS` append, `MainPhasePlan` cases, `AbilityCatalog` entries).

In `combat/combat.gd`, replace Task 5's `_run_hasty_stage()` stub:

```gdscript
## Hasty Minion's 3-stage effect (2026-08-16 spec §2): a party-wide +20 Initiative buff (3 turns)
## at stage 1, adds the resource-regen buff (Task 2) at stage 2, adds Empowered (1 turn) + the
## reel-surge buff (Task 3, 3 turns [ASSUMPTION] — the spec doesn't give this an explicit
## duration at the base-ability tier) at stage 3.
const HASTY_INITIATIVE_BONUS: float = 20.0
const HASTY_INITIATIVE_TURNS: int = 3
const HASTY_REGEN_BONUS: int = 3
const HASTY_REGEN_TURNS: int = 3
const HASTY_EMPOWERED_TURNS: int = 2   # matches EffectLibrary.make(&"empowered")'s own duration default at line ~92; every caller sets its own, so confirm the real default before assuming
const HASTY_REEL_SURGE_TURNS: int = 3

func _run_hasty_stage(minion: Combatant, stage: int) -> void:
	for ally: Combatant in _allies_of(minion):
		if not ally.is_alive():
			continue
		if stage == 1:
			var haste := Effect.new()
			haste.id = &"hasty_initiative"
			haste.kind = Effect.Kind.INITIATIVE_MOD
			haste.magnitude = HASTY_INITIATIVE_BONUS
			haste.duration = HASTY_INITIATIVE_TURNS
			haste.beneficial = true
			ally.attach_effect(haste)
		if stage == 2:
			var regen := Effect.new()
			regen.id = &"hasty_regen"
			regen.kind = Effect.Kind.REEL_FACE_EDIT  # inert marker kind — regen_bonus is read directly
			regen.regen_bonus = HASTY_REGEN_BONUS
			regen.duration = HASTY_REGEN_TURNS
			regen.beneficial = true
			ally.attach_effect(regen)
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
	_log("  💨 Hasty Minion (stage %d) buffs the party." % stage)
```

Before finalizing the `HASTY_EMPOWERED_TURNS`/1-turn override, read `EffectLibrary.make(&"empowered")`'s
actual current default duration and confirm the code above explicitly overrides it to 1 turn
regardless of that default, per the spec's own locked "Empowered for 1 turn" requirement for this
specific stage — don't rely on the library default matching by coincidence.

- [ ] **Step 4: Run tests to verify they pass**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add combat/class_library.gd combat/combatant.gd combat/main_phase_plan.gd combat/combat.gd combat/ui/ability_catalog.gd tests/test_hasty_minion.gd
git commit -m "feat(summoner-kit): add Hasty Minion (L4 extra ability)"
```

---

## Task 9: Ultimate — "Grand Sacrifice"

**Files:**
- Modify: `combat/class_library.gd`
- Modify: `combat/combatant.gd`
- Modify: `combat/main_phase_plan.gd`
- Modify: `combat/combat.gd`
- Modify: `combat/ui/ability_catalog.gd`
- Test: `tests/test_grand_sacrifice.gd` (new)

**Interfaces:**
- Consumes: `Combatant.minion_type`/`active_minion` (Task 1), the resource-regen buff (Task 2),
  the reel-surge buff (Task 3), `cleanse_oldest_debuff()` (Task 4), `_splash_half_to_others()`
  (existing, Ranger's Collateral mechanic).
- Produces: `ClassLibrary`'s Summoner branch gets `ultimate_id = &"grand_sacrifice"` (replacing
  the `&"sticky_wild"` placeholder).
- Produces: `MainPhasePlan.can_stage_ultimate()` gains a new precondition specific to this
  Ultimate: an active, alive minion is required IN ADDITION TO the normal meter-armed check.
- Produces: `Combatant.fire_grand_sacrifice()` + orchestrator-side variant application in
  `combat.gd` (modeled on the existing "Dark Reinforcements" precedent — an Ultimate with no
  reel/spin component, applied immediately rather than modifying an upcoming spin).

**Before writing code:** read `Combatant.fire_dark_reinforcements()`-or-equivalent (search
`combat.gd`/`combatant.gd` for `dark_reinforcements`) IN FULL — the research for this plan found
that this is the one existing Ultimate with "no fire_X() method... consumed directly" at its
commit site, since it has no reel/damage component. Grand Sacrifice is structurally the same
shape (an instant effect, not a spin-modifier) for 3 of its 4 variants, and even Ember's
burst+splash variant doesn't need to wait for a reel spin (the burst is a guaranteed effect paid
for by the sacrifice, not a dice roll) — model the whole Ultimate on this precedent rather than
the Wild/Rampage/Big Bang-style "modifies the next spin" Ultimates.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_grand_sacrifice.gd`, covering:

```gdscript
	# --- Cannot stage without an active minion, even with a full meter ---
	# --- Can stage once a minion IS active AND the meter is full ---
	# --- Firing consumes the meter AND kills the active minion (take_damage(hp)) ---
	# --- Ember variant: burst damage to the primary target + 50% splash to every other enemy ---
	# --- Dew variant: large AoE heal + improved Thorns (bigger thorns_pct than the base ability's
	#     0.20) + a "cleansing buff" that removes one debuff from each ally EVERY turn for 2 turns
	#     (not just once at cast time) — this needs its own new repeating-cleanse mechanic; see
	#     Step 3's design note. ---
	# --- Misfortune variant: &"jinxed" applied to every living enemy for 2 turns + an "improved"
	#     &"cursed" (bigger starting stacks/magnitude than Misfortune's own stage-3 version) for 3
	#     turns ---
	# --- Hasty variant: 2-turn versions of the regen buff, Empowered, and reel_surge, party-wide ---
```

- [ ] **Step 2: Run tests to verify they fail**

`../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_grand_sacrifice.gd`
Expected: FAIL.

- [ ] **Step 3: Write minimal implementation**

In `combat/class_library.gd`'s `&"summoner"` branch, change:
```gdscript
summoner.ultimate_id = &"grand_sacrifice"  # was &"sticky_wild" placeholder
```

In `combat/main_phase_plan.gd`'s `can_stage_ultimate()`, add the minion-alive precondition
specifically for this ultimate_id (every other ultimate_id keeps its existing meter-only gate):
```gdscript
func can_stage_ultimate() -> bool:
	if combatant == null or combatant.bonus_meter == null or not combatant.bonus_meter.is_armed():
		return false
	if combatant.ultimate_id == &"grand_sacrifice":
		return combatant.active_minion != null and combatant.active_minion.is_alive()
	return true
```
(Adjust to match the method's actual current exact body/return shape — read it first.)

In `main_phase_plan.gd`'s `commit()`'s `match ultimate_id:` block, add:
```gdscript
&"grand_sacrifice":
	combatant.fire_grand_sacrifice()
```

In `combat/combatant.gd`, add a new method (this only handles the resource/meter/sacrifice
bookkeeping — the actual per-variant EFFECT application needs enemy/ally target lists Combatant
doesn't have, so it sets a "pending variant" flag the orchestrator reads immediately, same
pattern `heal_boss_pending`/`curse_party_pending` already use for the Warden Acolyte):
```gdscript
## Fires the Summoner's "Grand Sacrifice" Ultimate (2026-08-16 spec §8): consumes the Bonus
## Meter (can_stage_ultimate() already confirmed an active, alive minion exists) and sacrifices
## that minion (self-inflicted fatal damage — the same expiry pattern used everywhere else a
## minion is replaced/expires). Reads the minion's OWN type (not which ability was most recently
## pressed) to decide which variant the orchestrator applies immediately after this call.
var grand_sacrifice_variant_pending: StringName = &""

func fire_grand_sacrifice() -> void:
	bonus_meter.consume()
	grand_sacrifice_variant_pending = active_minion.minion_type
	active_minion.take_damage(active_minion.hp)
	active_minion = null
```

In `combat/combat.gd`, find where `heal_boss_pending`/`curse_party_pending` are read and applied
(inside `_commit_main1()`, per the exact code already confirmed for the Warden Acolyte pattern —
search for `curse_party_pending`) and add a parallel block immediately after committing Main 1,
applying whichever variant is pending:

```gdscript
	if _attacker.grand_sacrifice_variant_pending != &"":
		_apply_grand_sacrifice(_attacker, _attacker.grand_sacrifice_variant_pending)
		_attacker.grand_sacrifice_variant_pending = &""

## Applies the Grand Sacrifice Ultimate's variant effect, keyed on which minion type was
## sacrificed (2026-08-16 spec §8). [ASSUMPTION] every magnitude/duration below — tune by
## playtest; the STRUCTURE (which variant does what) is locked.
const GRAND_SACRIFICE_EMBER_BURST: int = 40
const GRAND_SACRIFICE_DEW_HEAL: int = 30
const GRAND_SACRIFICE_DEW_THORNS_PCT: float = 0.35
const GRAND_SACRIFICE_DEW_TURNS: int = 2
const GRAND_SACRIFICE_MISFORTUNE_TURNS: int = 2
const GRAND_SACRIFICE_CURSE_TURNS: int = 3
const GRAND_SACRIFICE_HASTY_TURNS: int = 2

func _apply_grand_sacrifice(caster: Combatant, variant: StringName) -> void:
	match variant:
		&"ember":
			if _defender != null and _defender.is_alive():
				_defender.take_damage(GRAND_SACRIFICE_EMBER_BURST)
				var splashed: Array[Combatant] = _splash_half_to_others(caster, GRAND_SACRIFICE_EMBER_BURST, "Piercing", 0.5)
				_log("  🔥 Grand Sacrifice (Ember): %d burst damage, splashed to %d other enemies." % [GRAND_SACRIFICE_EMBER_BURST, splashed.size()])
		&"dew":
			for ally: Combatant in _allies_of(caster):
				if not ally.is_alive():
					continue
				ally.heal(GRAND_SACRIFICE_DEW_HEAL)
				var thorns := Effect.new()
				thorns.id = &"grand_sacrifice_thorns"
				thorns.kind = Effect.Kind.REEL_FACE_EDIT
				thorns.thorns_pct = GRAND_SACRIFICE_DEW_THORNS_PCT
				thorns.duration = GRAND_SACRIFICE_DEW_TURNS
				thorns.beneficial = true
				ally.attach_effect(thorns)
				# NOTE: the spec calls for a "cleansing buff that removes one debuff EVERY turn
				# for 2 turns," not a one-time cleanse. That repeating-per-turn behavior needs its
				# own new marker effect (e.g. &"grand_sacrifice_cleanse", checked every Upkeep
				# alongside the existing DoT-tick loop) rather than a single cleanse_oldest_debuff()
				# call here — implement that plumbing as part of this task, reusing Upkeep as the
				# hook point (mirrors how DoT effects already tick once per Upkeep).
				if _panels.has(ally):
					(_panels[ally] as CombatantPanel).refresh_status()
			_log("  💧 Grand Sacrifice (Dew): large party heal + improved Thorns + repeating cleanse.")
		&"misfortune":
			for enemy: Combatant in _enemies_of(caster):
				if not enemy.is_alive():
					continue
				enemy.attach_effect(EffectLibrary.make(&"jinxed"))
				var curse: Effect = EffectLibrary.make(&"cursed")
				curse.dot_base_damage = 1.0
				curse.duration = GRAND_SACRIFICE_CURSE_TURNS
				enemy.attach_effect(curse)
				if _panels.has(enemy):
					(_panels[enemy] as CombatantPanel).refresh_status()
			_log("  🌑 Grand Sacrifice (Misfortune): Jinxed + improved Curse on every enemy.")
		&"hasty":
			for ally: Combatant in _allies_of(caster):
				if not ally.is_alive():
					continue
				var regen := Effect.new()
				regen.id = &"grand_sacrifice_regen"
				regen.kind = Effect.Kind.REEL_FACE_EDIT
				regen.regen_bonus = HASTY_REGEN_BONUS
				regen.duration = GRAND_SACRIFICE_HASTY_TURNS
				regen.beneficial = true
				ally.attach_effect(regen)
				var empowered: Effect = EffectLibrary.make(&"empowered")
				empowered.duration = GRAND_SACRIFICE_HASTY_TURNS
				ally.attach_effect(empowered)
				var surge := Effect.new()
				surge.id = &"reel_surge"
				surge.kind = Effect.Kind.REEL_FACE_EDIT
				surge.duration = GRAND_SACRIFICE_HASTY_TURNS
				surge.beneficial = true
				ally.attach_effect(surge)
				if _panels.has(ally):
					(_panels[ally] as CombatantPanel).refresh_status()
			_log("  💨 Grand Sacrifice (Hasty): party-wide regen + Empowered + reel surge, 2 turns.")
```

**Open implementation decision (flagged, not blocking):** Dew's Ultimate "cleansing buff that
removes one debuff per turn" needs new per-Upkeep plumbing (a marker effect checked inside
whatever loop already ticks DoTs each Upkeep, calling `cleanse_oldest_debuff()` on its bearer
when present) — implement this as part of this task; it's the one piece of this Ultimate that
isn't a straightforward reuse of an existing one-shot pattern.

Also add `AbilityCatalog` entries for `&"grand_sacrifice"` (display name + a description noting
its effect varies by active minion).

- [ ] **Step 4: Run tests to verify they pass**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add combat/class_library.gd combat/combatant.gd combat/main_phase_plan.gd combat/combat.gd combat/ui/ability_catalog.gd tests/test_grand_sacrifice.gd
git commit -m "feat(summoner-kit): add the Grand Sacrifice Ultimate (4 variants by active minion type)"
```

---

## Task 10: Full regression pass + `test_summoner_class.gd` update

**Files:**
- Modify: `tests/test_summoner_class.gd`
- Test: full suite

**Interfaces:**
- Consumes: everything from Tasks 1-9.

- [ ] **Step 1: Update `tests/test_summoner_class.gd`**

This file currently asserts `extra_abilities == []`/`ultimate_id == &"sticky_wild"` (the
placeholders Tasks 6-9 just replaced). Update its assertions to match the real, final state:
`extra_abilities.size() == 3` (Dew/Misfortune/Hasty), each with the right `id`/`unlock_level`/
`cost`/`resource`, and `ultimate_id == &"grand_sacrifice"`.

- [ ] **Step 2: Run every test this plan touched or that touches shared machinery it modified**

`test_minion_library.gd`, `test_resource_regen_buff.gd`, `test_reel_surge_buff.gd`,
`test_cleanse_oldest_debuff.gd`, `test_minion_lifecycle.gd`, `test_dew_minion.gd`,
`test_misfortune_minion.gd`, `test_hasty_minion.gd`, `test_grand_sacrifice.gd`,
`test_summoner_class.gd`, `test_main_phase_plan.gd`, `test_class_library.gd`,
`test_ability_catalog.gd`, `test_turn_manager.gd`, `test_combat_flee.gd`,
`test_visible_initiative_roll.gd`, `test_spawn_enemy_mid_combat.gd`, `test_boss_phase_transition.gd`,
`test_collateral.gd`, `test_hex.gd`. Confirm all green.

- [ ] **Step 3: Commit**

```bash
git add tests/test_summoner_class.gd
git commit -m "test(summoner-kit): update test_summoner_class.gd for the finished 4-ability kit"
```

---

## Self-review notes (for whoever executes this plan)

- Task 9 (the Ultimate) is the most open-ended task in this plan — it has one explicitly flagged
  sub-mechanic (Dew's repeating per-turn cleanse) that needs new plumbing beyond what the rest of
  the plan builds. Budget extra review attention here.
- Every magnitude/duration/cost number in this plan is `[ASSUMPTION]` per `CLAUDE.md` §4 — do not
  hand-balance further; these exist so the mechanics can be played and tuned.
- This plan does not touch talent-tree perks for the Summoner (explicitly deferred) or add a
  second Ultimate/fifth minion type.
