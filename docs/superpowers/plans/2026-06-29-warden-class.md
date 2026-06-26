# Warden Class Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the 7th and final class — the Warden (Earth/Earthstave mana caster) — with the **Rallying Cry** base ability (party shield) and the new **Earthquake** Ultimate (+1 WILD reel, full-to-primary / half-to-others splash, and a STUNNED debuff that leaves Initiative untouched).

**Architecture:** Pure-logic additions to existing `Resource`/`RefCounted` combat classes (`ActionReel`, `Combatant`, `MainPhasePlan`, `ClassLibrary`), wired into the `combat.gd` orchestrator. Earthquake reuses the Ranger Collateral splash model (`is_aoe_active()` stays false; primary takes full, others take `ceil(total/2)`) plus the Sticky-Wild path (`sticky_wild_count`), and adds a one-shot `force_stun_next_turn` flag honored by the existing `evaluate_stun` / d100 gate. Rallying Cry reuses the existing SHIELDED system.

**Tech Stack:** Godot 4.6.3-stable, GDScript (no C#), static typing, `Resource`-based data. Headless `SceneTree` test scripts under `tests/`.

## Global Constraints

- **Engine:** Godot 4.6.3-stable. **Language:** GDScript only — no C#, no .NET. (CLAUDE.md §2)
- **Naming:** Classes `PascalCase`, files `snake_case`, signals past-tense `snake_case`, handlers `_on_<emitter>_<signal>`. (CLAUDE.md §2)
- **Static typing** everywhere (typed vars + signatures).
- **All damage/heal math rounds UP** (`ceil` / `ceili`). (CLAUDE.md §4, [[round-up-damage-healing]])
- **Balance numbers are `[ASSUMPTION]`** — build as editable data, do not hard-balance. (CLAUDE.md §4)
- **Prototype runs 1v1 + dummies**; every multi-combatant path is written N-vs-M-correct and verified by **synthetic headless tests**, not a new scene. (CLAUDE.md §7)
- **Run a headless test:**
  ```bash
  "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_<name>.gd
  ```
  Use the `_console.exe` build (captures stdout). Bound runs with `timeout 60`. No new `class_name` is introduced by this plan (all changes are methods/fields on existing classes + one new `static func`), so no class-cache refresh is needed.
- **The "fun" call is the human's** (CLAUDE.md §5): the final step is a cross-class playtest, not a machine judgement.

---

### Task 1: `ActionReel.make_rallying_cry` — the no-damage shield reel

**Files:**
- Modify: `combat/resources/action_reel.gd` (add a `static func` after `make_rend`, ~line 63)
- Test: `tests/test_rallying_cry_reel.gd` (create)

**Interfaces:**
- Produces: `ActionReel.make_rallying_cry(type: DamageType = null) -> ActionReel` — a reel of **2 CRIT_SUCCESS + 8 SUCCESS** faces, every face `multiplier = 0.0`, `is_weapon_attack = false`, no rider. (Out of paylines, never WILD, kept at the loadout tail.)

- [ ] **Step 1: Write the failing test**

Create `tests/test_rallying_cry_reel.gd`:

```gdscript
extends SceneTree

# Headless test: ActionReel.make_rallying_cry — the Warden's no-damage party-shield reel
# (spec 2026-06-29 §3). 2 crit + 8 success faces, zero damage, excluded from paylines.
# Run: "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_rallying_cry_reel.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _count(reel: ActionReel, tier: ReelFace.ResultTier) -> int:
	var n: int = 0
	for f: ReelFace in reel.faces:
		if f.result_tier == tier: n += 1
	return n

func _initialize() -> void:
	var earth: DamageType = load("res://combat/resources/types/earth.tres")
	var reel: ActionReel = ActionReel.make_rallying_cry(earth)
	_check(reel.faces.size() == 10, "10 faces (got %d)" % reel.faces.size())
	_check(_count(reel, ReelFace.ResultTier.CRIT_SUCCESS) == 2, "2 crit-success faces (got %d)" % _count(reel, ReelFace.ResultTier.CRIT_SUCCESS))
	_check(_count(reel, ReelFace.ResultTier.SUCCESS) == 8, "8 success faces (got %d)" % _count(reel, ReelFace.ResultTier.SUCCESS))
	_check(_count(reel, ReelFace.ResultTier.FAILURE) == 0, "no failure faces")
	_check(_count(reel, ReelFace.ResultTier.NEUTRAL) == 0, "no neutral faces")
	_check(_count(reel, ReelFace.ResultTier.CRIT_FAILURE) == 0, "no crit-failure faces")
	_check(not reel.is_weapon_attack, "is_weapon_attack = false (out of paylines)")
	_check(reel.damage_type == earth, "carries the requested type")
	var all_zero: bool = reel.faces.all(func(f: ReelFace) -> bool: return f.multiplier == 0.0)
	_check(all_zero, "every face deals zero direct damage")
	var no_rider: bool = reel.faces.all(func(f: ReelFace) -> bool: return f.rider_effect_id == &"")
	_check(no_rider, "no rider on any face (shield applied by orchestrator from tier)")

	print(("RALLYING CRY REEL TEST PASSED" if _failures == 0 else "RALLYING CRY REEL TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 60 "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_rallying_cry_reel.gd`
Expected: FAIL (or parse error) — `make_rallying_cry` is not defined.

- [ ] **Step 3: Add `make_rallying_cry` to `combat/resources/action_reel.gd`**

Insert after `make_rend` (after line 63, before `_make_face`):

```gdscript
## Builds the Warden's "Rallying Cry" reel (spec 2026-06-29 §3): a no-damage UTILITY reel of 2
## crit-success + 8 success faces (no fail/neutral/crit-fail). Every face deals zero direct damage
## (multiplier 0) and carries NO rider — the orchestrator reads the landed tier post-spin and shields
## the party (SUCCESS → half-weapon, CRIT_SUCCESS → full-weapon). is_weapon_attack = false → it stays
## OUT of paylines, is never WILD-biased, and sits at the loadout tail.
static func make_rallying_cry(type: DamageType = null) -> ActionReel:
	var reel: ActionReel = ActionReel.new()
	reel.damage_type = type
	reel.is_weapon_attack = false
	for i: int in range(2):
		reel.faces.append(_make_face(ReelFace.ResultTier.CRIT_SUCCESS, 0.0))
	for i: int in range(8):
		reel.faces.append(_make_face(ReelFace.ResultTier.SUCCESS, 0.0))
	reel.faces.shuffle()  # balance-neutral: only adjacency varies, tier counts fixed
	return reel
```

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 60 "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_rallying_cry_reel.gd`
Expected: PASS — `RALLYING CRY REEL TEST PASSED`.

- [ ] **Step 5: Commit**

```bash
git add combat/resources/action_reel.gd tests/test_rallying_cry_reel.gd
git commit -m "feat(warden): ActionReel.make_rallying_cry (no-damage party-shield reel)"
```

---

### Task 2: `force_stun_next_turn` — stun without touching Initiative

**Files:**
- Modify: `combat/combatant.gd` — add the field (near `stunned_this_turn`, ~line 137) and update `evaluate_stun` (~line 461)
- Test: `tests/test_force_stun.gd` (create)

**Interfaces:**
- Produces: `Combatant.force_stun_next_turn: bool` (one-shot flag) and an updated `evaluate_stun(threshold: int) -> bool` that returns true when the flag is set (consuming it), **bypassing the anti-lock**, and **never writes `current_initiative`**.

- [ ] **Step 1: Write the failing test**

Create `tests/test_force_stun.gd`:

```gdscript
extends SceneTree

# Headless test: force_stun_next_turn (Warden Earthquake stun, spec 2026-06-29 §4.3). A forced stun
# triggers STUNNED next turn WITHOUT altering current_initiative (queue position preserved), bypasses
# the anti-lock, is one-shot (consumed), and routes the existing d100 gate.
# Run: "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_force_stun.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _mk(init: int) -> Combatant:
	var c: Combatant = Combatant.new()
	c.base_initiative = init
	c.recompute_initiative()
	return c

func _initialize() -> void:
	# Forced stun on a combatant whose initiative is WELL ABOVE the threshold → still STUNNED.
	var a: Combatant = _mk(50)
	a.force_stun_next_turn = true
	var init_before: int = a.current_initiative
	_check(a.evaluate_stun(-20), "forced stun → STUNNED even at init 50 (above threshold)")
	_check(a.current_initiative == init_before, "initiative UNCHANGED by the forced stun (queue preserved)")
	_check(not a.force_stun_next_turn, "force flag is consumed (one-shot)")

	# Forced stun BYPASSES the anti-lock (stunned last turn would normally grant immunity).
	var b: Combatant = _mk(50)
	b.stunned_last_turn = true
	b.force_stun_next_turn = true
	_check(b.evaluate_stun(-20), "forced stun bypasses the anti-lock (lands despite stunned_last_turn)")

	# Without the flag, a high-initiative combatant is NOT stunned (regression: normal path intact).
	var c: Combatant = _mk(50)
	_check(not c.evaluate_stun(-20), "no forced stun + high init → not stunned")

	# Init-based stun still respects the anti-lock (unchanged behavior).
	var d: Combatant = _mk(-50)
	d.stunned_last_turn = true
	_check(not d.evaluate_stun(-20), "init-based stun still immune when stunned_last_turn")

	print(("FORCE STUN TEST PASSED" if _failures == 0 else "FORCE STUN TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 60 "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_force_stun.gd`
Expected: FAIL/parse error — `force_stun_next_turn` not defined.

- [ ] **Step 3: Add the field and update `evaluate_stun`**

In `combat/combatant.gd`, after the `stunned_last_turn` declaration (~line 138), add:

```gdscript
## Earthquake (Warden Ultimate, spec 2026-06-29 §4.3) force-stun: a one-shot flag set by the
## orchestrator on every enemy the Earthquake damaged. evaluate_stun honors it to STUN the bearer next
## turn REGARDLESS of initiative and WITHOUT changing current_initiative (queue position preserved),
## bypassing the anti-lock so the expensive Ultimate reliably lands. Consumed when evaluated.
var force_stun_next_turn: bool = false
```

Replace the body of `evaluate_stun` (~lines 461-463):

```gdscript
func evaluate_stun(threshold: int) -> bool:
	var forced: bool = force_stun_next_turn
	force_stun_next_turn = false  # one-shot: consume on evaluation
	# Forced (Earthquake) stun bypasses the anti-lock; init-based stun still respects it (the spiral case).
	var by_initiative: bool = current_initiative < threshold and not stunned_last_turn
	stunned_this_turn = forced or by_initiative
	return stunned_this_turn
```

- [ ] **Step 4: Run the new test AND the existing stun test (regression)**

```bash
timeout 60 "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_force_stun.gd
timeout 60 "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_stun.gd
```
Expected: both PASS (`FORCE STUN TEST PASSED`, `STUN TEST PASSED`).

- [ ] **Step 5: Commit**

```bash
git add combat/combatant.gd tests/test_force_stun.gd
git commit -m "feat(warden): force_stun_next_turn honored by evaluate_stun (Initiative untouched)"
```

---

### Task 3: `Combatant.apply_rallying_cry` + `rallying_cry_reel`

**Files:**
- Modify: `combat/combatant.gd` — add `rallying_cry_reel` field, reset in `begin_turn` (~line 308), add `apply_rallying_cry` (near the Seer ability methods, ~after line 352)
- Test: `tests/test_rallying_cry.gd` (create)

**Interfaces:**
- Consumes: `ActionReel.make_rallying_cry` (Task 1).
- Produces:
  - `Combatant.rallying_cry_reel: ActionReel` — the appended utility reel this turn (null otherwise); reset to null in `begin_turn`.
  - `Combatant.apply_rallying_cry(cost: int, cap: int) -> bool` — spend `cost` mana, append `make_rallying_cry(weapon_type())` (no-op + false if unaffordable or at the reel cap), record `rallying_cry_reel`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_rallying_cry.gd`:

```gdscript
extends SceneTree

# Headless test: Combatant.apply_rallying_cry (Warden base ability, spec 2026-06-29 §3) + the
# orchestrator's per-tier shield formula over a synthetic 3-ally party.
# Run: "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_rallying_cry.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _make_warden(type: DamageType) -> Combatant:
	var c: Combatant = Combatant.new()
	c.ability_resource = &"mana"
	var w: Weapon = Weapon.new(); w.base_damage = 9.0
	for i: int in range(3):
		w.reels.append(ActionReel.make_default(type))
	c.weapon = w
	c.resource_pool = ResourcePool.new(); c.resource_pool.mana = 12; c.resource_pool.max_mana = 12
	c.begin_turn()
	return c

func _initialize() -> void:
	var earth: DamageType = load("res://combat/resources/types/earth.tres")

	# apply_rallying_cry: spends 4 mana, appends the utility reel (3 → 4), records rallying_cry_reel.
	var w: Combatant = _make_warden(earth)
	_check(w.turn_reels.size() == 3, "starts with 3 reels")
	var ok: bool = w.apply_rallying_cry(4, 5)
	_check(ok, "apply_rallying_cry succeeds when affordable")
	_check(w.resource_pool.mana == 8, "spent 4 mana (12 → 8, got %d)" % w.resource_pool.mana)
	_check(w.turn_reels.size() == 4, "appended the utility reel (3 → 4, got %d)" % w.turn_reels.size())
	_check(w.rallying_cry_reel != null and w.rallying_cry_reel == w.turn_reels[3], "rallying_cry_reel records the appended reel")
	_check(not w.turn_reels[3].is_weapon_attack, "the rally reel is a non-weapon-attack reel")

	# begin_turn resets the recorded reel.
	w.begin_turn()
	_check(w.rallying_cry_reel == null, "begin_turn resets rallying_cry_reel")
	_check(w.turn_reels.size() == 3, "begin_turn resets to 3 weapon reels")

	# Unaffordable → no-op, false.
	var poor: Combatant = _make_warden(earth)
	poor.resource_pool.mana = 2
	_check(not poor.apply_rallying_cry(4, 5), "apply_rallying_cry fails when mana < cost")
	_check(poor.turn_reels.size() == 3 and poor.rallying_cry_reel == null, "no reel added when unaffordable")

	# At the reel cap → no-op, false (mana NOT spent).
	var capped: Combatant = _make_warden(earth)
	capped.turn_reels.append(ActionReel.make_default(earth))
	capped.turn_reels.append(ActionReel.make_default(earth))  # now 5 = cap
	_check(not capped.apply_rallying_cry(4, 5), "apply_rallying_cry fails at the reel cap")
	_check(capped.resource_pool.mana == 12, "no mana spent when at the cap (got %d)" % capped.resource_pool.mana)

	# --- per-tier shield formula (the orchestrator's logic) over a synthetic 3-ally party ---
	# weapon_base 9: SUCCESS → ceil(9*0.5)=5 shield; CRIT_SUCCESS → ceil(9)=9 shield; 2 turns.
	var base: float = 9.0
	_check(ceili(base * 0.5) == 5, "SUCCESS shield = ceil(9*0.5) = 5 (got %d)" % ceili(base * 0.5))
	_check(ceili(base) == 9, "CRIT shield = ceil(9) = 9 (got %d)" % ceili(base))
	var a: Combatant = Combatant.new()
	var b: Combatant = Combatant.new()
	for ally: Combatant in [a, b]:
		ally.apply_shield(ceili(base * 0.5), 2)
	_check(a.shield_hp == 5 and a.shield_turns == 2, "ally A gets a 5-shield for 2 turns")
	_check(b.shield_hp == 5, "ally B gets a 5-shield")
	# Higher-total-overrides: a crit later in the fight upgrades the shield to 9.
	a.apply_shield(ceili(base), 2)
	_check(a.shield_hp == 9, "crit shield upgrades 5 → 9 (higher overrides)")

	print(("RALLYING CRY TEST PASSED" if _failures == 0 else "RALLYING CRY TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 60 "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_rallying_cry.gd`
Expected: FAIL/parse error — `apply_rallying_cry` / `rallying_cry_reel` not defined.

- [ ] **Step 3: Add the field, reset, and method**

In `combat/combatant.gd`, after the `big_bang_spins_remaining` declaration (~line 133), add:

```gdscript
## Warden "Rallying Cry" base ability (spec 2026-06-29 §3): the no-damage utility reel appended THIS
## turn (null otherwise). The orchestrator reads its post-spin result tier to shield the party. Reset
## each turn by begin_turn.
var rallying_cry_reel: ActionReel = null
```

In `begin_turn` (~line 308), add the reset (after the if/else that sets `turn_reels`):

```gdscript
func begin_turn() -> void:
	if weapon != null:
		turn_reels = weapon.reels.duplicate()
	else:
		turn_reels.clear()
	rallying_cry_reel = null  # Warden: clear last turn's recorded Rallying Cry reel
```

After `convert_turn_reels_to` (~line 361), add:

```gdscript
## Warden "Rallying Cry" (spec 2026-06-29 §3): spends [param cost] Mana and appends one no-damage
## utility reel ([method ActionReel.make_rallying_cry], own weapon type) onto THIS turn, recording it
## on [member rallying_cry_reel] so the orchestrator can read its post-spin tier and shield the party.
## Respects the [param cap]-reel ceiling. Returns false (and changes nothing) if at the cap or the Mana
## is unaffordable.
func apply_rallying_cry(cost: int, cap: int) -> bool:
	if turn_reels.size() >= cap:
		return false
	if resource_pool == null or not resource_pool.spend({&"mana": cost}):
		return false
	var reel: ActionReel = ActionReel.make_rallying_cry(weapon_type())
	turn_reels.append(reel)
	rallying_cry_reel = reel
	return true
```

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 60 "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_rallying_cry.gd`
Expected: PASS — `RALLYING CRY TEST PASSED`.

- [ ] **Step 5: Commit**

```bash
git add combat/combatant.gd tests/test_rallying_cry.gd
git commit -m "feat(warden): Combatant.apply_rallying_cry + rallying_cry_reel tracking"
```

---

### Task 4: `Combatant.fire_earthquake` + contiguous reel insert

**Files:**
- Modify: `combat/combatant.gd` — add `earthquake_spins_remaining` field (~line 133 area), `_insert_weapon_attack_reel` helper, `fire_earthquake` / `is_earthquake_active` / `consume_earthquake_spin` (in the Ultimate section, after the Big Bang block ~line 581)
- Test: `tests/test_earthquake.gd` (create)

**Interfaces:**
- Consumes: `BonusMeter.is_armed()`/`consume()`, `ActionReel.make_default`, `sticky_wild_count`/`wild_reel_indices` (existing).
- Produces:
  - `Combatant.earthquake_spins_remaining: int`
  - `Combatant.fire_earthquake(extra_reel_type: DamageType, spins: int) -> bool` — armed → consume meter, insert 1 weapon-attack reel after the last weapon-attack reel (keeps the attack run contiguous), set `sticky_wild_count = <count of weapon-attack reels>` + `sticky_wild_spins_remaining = spins`, set `earthquake_spins_remaining = spins`. NOT AoE.
  - `Combatant.is_earthquake_active() -> bool`, `Combatant.consume_earthquake_spin() -> void`

- [ ] **Step 1: Write the failing test**

Create `tests/test_earthquake.gd`:

```gdscript
extends SceneTree

# Headless test: Combatant.fire_earthquake (Warden Ultimate, spec 2026-06-29 §4). +1 weapon-attack reel
# (3 → 4), all 4 WILD, NOT AoE (primary takes full; orchestrator splashes half to others), reel inserted
# contiguously before any trailing utility reel. Also covers the splash + force-stun rules.
# Run: "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_earthquake.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _make_armed_warden(type: DamageType) -> Combatant:
	var c: Combatant = Combatant.new()
	var w: Weapon = Weapon.new(); w.base_damage = 9.0
	for i: int in range(3):
		w.reels.append(ActionReel.make_default(type))
	c.weapon = w
	c.bonus_meter = BonusMeter.new(); c.bonus_meter.cap = 15; c.bonus_meter.value = 15  # armed
	c.begin_turn()
	return c

func _initialize() -> void:
	var earth: DamageType = load("res://combat/resources/types/earth.tres")

	# fire_earthquake alone: 3 → 4 weapon-attack reels, all 4 wild, NOT AoE, meter consumed.
	var w: Combatant = _make_armed_warden(earth)
	_check(w.turn_reels.size() == 3, "starts with 3 reels")
	var fired: bool = w.fire_earthquake(earth, 1)
	_check(fired, "fire_earthquake succeeds when armed")
	_check(w.bonus_meter.value == 0, "consumed the full meter (got %d)" % w.bonus_meter.value)
	_check(w.turn_reels.size() == 4, "added 1 reel (3 → 4, got %d)" % w.turn_reels.size())
	_check(w.wild_reel_indices() == [0, 1, 2, 3], "all 4 reels wild (got %s)" % str(w.wild_reel_indices()))
	_check(not w.is_aoe_active(), "Earthquake is NOT an AoE spin (primary takes full; splash is separate)")
	_check(w.is_earthquake_active(), "earthquake active for the spin")
	var all_attack: bool = w.turn_reels.all(func(r: ActionReel) -> bool: return r.is_weapon_attack)
	_check(all_attack, "all 4 reels are weapon-attack reels (feed the 4-wide payline grid)")

	# Consume → clears.
	w.consume_earthquake_spin()
	w.consume_wild_spin()
	_check(not w.is_earthquake_active(), "earthquake cleared after one spin")
	_check(w.wild_reel_indices().is_empty(), "wild cleared after one spin")

	# Not armed → no fire.
	var poor: Combatant = _make_armed_warden(earth)
	poor.bonus_meter.value = 5
	_check(not poor.fire_earthquake(earth, 1), "fire_earthquake fails when meter not armed")

	# CONTIGUITY: with a trailing utility (Rallying Cry) reel already present, Earthquake's attack reel
	# inserts BEFORE it so the 4 weapon-attack reels stay contiguous at the front (grid + WILD correct).
	var combo: Combatant = _make_armed_warden(earth)
	combo.resource_pool = ResourcePool.new(); combo.resource_pool.mana = 12; combo.resource_pool.max_mana = 12
	combo.apply_rallying_cry(4, 5)  # turn_reels = [w0, w1, w2, rally]
	_check(combo.turn_reels.size() == 4 and not combo.turn_reels[3].is_weapon_attack, "rally reel sits at index 3")
	combo.fire_earthquake(earth, 1)  # → [w0, w1, w2, eq, rally]
	_check(combo.turn_reels.size() == 5, "5 reels with both staged (got %d)" % combo.turn_reels.size())
	_check(combo.turn_reels[3].is_weapon_attack, "Earthquake reel inserted at index 3 (contiguous attack run)")
	_check(not combo.turn_reels[4].is_weapon_attack, "rally reel pushed to the tail (index 4)")
	_check(combo.wild_reel_indices() == [0, 1, 2, 3], "WILD covers exactly the 4 attack reels (got %s)" % str(combo.wild_reel_indices()))

	# SPLASH math (orchestrator formula): primary total 30 → others take ceil(30/2)=15.
	_check(ceili(30 / 2.0) == 15, "splash = ceil(30/2) = 15")
	_check(ceili(7 / 2.0) == 4, "odd total rounds up: ceil(7/2) = 4")

	# STUN rule: every DAMAGED enemy is force-stunned; next turn it is STUNNED with init untouched.
	var enemy: Combatant = Combatant.new(); enemy.base_initiative = 40; enemy.recompute_initiative()
	enemy.hp = 100; enemy.max_hp = 100
	enemy.take_damage(15)  # damaged by the splash
	_check(enemy.hp == 85, "enemy took 15 splash")
	enemy.force_stun_next_turn = true  # orchestrator sets this on every damaged enemy
	var init_before: int = enemy.current_initiative
	_check(enemy.evaluate_stun(-20), "damaged enemy is STUNNED next turn")
	_check(enemy.current_initiative == init_before, "stunned enemy keeps its initiative (queue position)")

	print(("EARTHQUAKE TEST PASSED" if _failures == 0 else "EARTHQUAKE TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 60 "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_earthquake.gd`
Expected: FAIL/parse error — `fire_earthquake` not defined.

- [ ] **Step 3: Add the field, helper, and methods**

In `combat/combatant.gd`, after the `rallying_cry_reel` field added in Task 3, add:

```gdscript
## Warden "Earthquake" Ultimate state (spec 2026-06-29 §4): while > 0, this combatant added a 4th
## weapon-attack reel, made all weapon-attack reels WILD, and its spin splashes half its primary total
## to every OTHER enemy + force-stuns every damaged enemy. Like Collateral (primary takes FULL; not an
## AoE spin), distinct from aoe_spins_remaining. Set by fire_earthquake, consumed by consume_earthquake_spin.
var earthquake_spins_remaining: int = 0
```

In the Combatant `# Per-turn reel loadout` region, after `try_rend_reel` (~line 334), add the insert helper:

```gdscript
## Inserts [param reel] (a weapon-attack reel) immediately AFTER the last weapon-attack reel in this
## turn's loadout, so the weapon-attack reels stay CONTIGUOUS at the front even when a trailing utility
## reel (e.g. Rallying Cry) is already present. Keeps the payline grid (leading weapon-attack run) and
## the WILD glow (indices 0..n-1) correct regardless of Main-1 commit order. Used by Earthquake.
func _insert_weapon_attack_reel(reel: ActionReel) -> void:
	var pos: int = 0
	for i: int in range(turn_reels.size()):
		if turn_reels[i].is_weapon_attack:
			pos = i + 1
	turn_reels.insert(pos, reel)
```

After the Big Bang Ultimate block (after `consume_big_bang_spin`, ~line 581), add:

```gdscript
# ---------------------------------------------------------------------------
# Warden "Earthquake" Ultimate (spec 2026-06-29 §4) — costs ONLY the Bonus Meter
# ---------------------------------------------------------------------------

## Fires the Earthquake Ultimate if the meter is armed: consumes the full meter, inserts one extra
## [param extra_reel_type] WEAPON-ATTACK reel (the Warden's 3 → 4) contiguous with the attack run, makes
## ALL weapon-attack reels crit-biased WILD for [param spins] spins (reuse the wild path), and flags the
## next [param spins] spins as Earthquake. NOT an AoE spin (is_aoe_active stays false): the primary takes
## FULL weapon damage; the orchestrator splashes half the primary total to every OTHER enemy and
## force-stuns every damaged enemy. Returns false if not armed.
func fire_earthquake(extra_reel_type: DamageType, spins: int) -> bool:
	if bonus_meter == null or not bonus_meter.is_armed():
		return false
	bonus_meter.consume()
	_insert_weapon_attack_reel(ActionReel.make_default(extra_reel_type))  # 3 → 4 weapon-attack reels
	var attack_count: int = 0
	for r: ActionReel in turn_reels:
		if r.is_weapon_attack:
			attack_count += 1
	sticky_wild_count = attack_count            # every weapon-attack reel crit-biased (reuse the wild path)
	sticky_wild_spins_remaining = spins
	earthquake_spins_remaining = spins
	return true

## True while an Earthquake spin is pending (drives the orchestrator's splash + force-stun).
func is_earthquake_active() -> bool:
	return earthquake_spins_remaining > 0

## Consumes one Earthquake spin. Call once per resolved spin (after the splash/stun has been applied).
func consume_earthquake_spin() -> void:
	if earthquake_spins_remaining > 0:
		earthquake_spins_remaining -= 1
```

- [ ] **Step 4: Run the new test AND the Big Bang test (regression on the shared wild path)**

```bash
timeout 60 "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_earthquake.gd
timeout 60 "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_big_bang.gd
```
Expected: both PASS.

- [ ] **Step 5: Commit**

```bash
git add combat/combatant.gd tests/test_earthquake.gd
git commit -m "feat(warden): Combatant.fire_earthquake (+1 WILD reel, contiguous insert, force-stun state)"
```

---

### Task 5: MainPhasePlan — stage / preview / commit Rallying Cry + Earthquake

**Files:**
- Modify: `combat/main_phase_plan.gd` — `EARTHQUAKE_SPINS` const, `_ability_adds_reel`, `preview_reels`, `effective_wild_indices`, `commit`
- Test: `tests/test_class_abilities_plan.gd` — append a Warden block

**Interfaces:**
- Consumes: `Combatant.apply_rallying_cry` (Task 3), `Combatant.fire_earthquake` (Task 4), `ActionReel.make_rallying_cry` (Task 1).
- Produces: MainPhasePlan recognises `&"rallying_cry"` (reel-adding ability) and `&"earthquake"` (reel-adding, all-WILD Ultimate) in preview/glow/commit. Earthquake does NOT subsume Rallying Cry (`_ultimate_subsumes_ability` unchanged → they stack).

- [ ] **Step 1: Write the failing test** — append before the final `print(...)` in `tests/test_class_abilities_plan.gd` (after the Big Bang block, ~line 163):

```gdscript
	# WARDEN — Rallying Cry (base, mana): previews +1 utility reel (out of paylines); commit appends it
	# + spends 4 mana.
	var rc: Combatant = _warden(3, earth)
	var prc: MainPhasePlan = MainPhasePlan.new(rc, 4, 5, 1)
	prc.toggle_ability()
	_check(prc.ability_staged, "rallying_cry stages via toggle")
	_check(prc.preview_reels().size() == 4, "rallying_cry preview: 3 → 4 reels (got %d)" % prc.preview_reels().size())
	_check(not prc.preview_reels()[3].is_weapon_attack, "rallying_cry preview reel is a non-weapon-attack (utility) reel")
	prc.commit()
	_check(rc.turn_reels.size() == 4 and rc.resource_pool.mana == 8, "rallying_cry commit: 4 reels, 4 mana spent (got %d mana)" % rc.resource_pool.mana)
	_check(rc.rallying_cry_reel != null, "rallying_cry commit records the reel for the orchestrator")

	# WARDEN — Earthquake (Ultimate): preview tops to 4 reels, all 4 glow WILD; commit consumes meter,
	# +1 reel, NOT AoE, earthquake active.
	var eq: Combatant = _warden(3, earth)
	eq.ultimate_id = &"earthquake"
	eq.bonus_meter = BonusMeter.new(); eq.bonus_meter.cap = 15; eq.bonus_meter.add_flat(15)
	var peq: MainPhasePlan = MainPhasePlan.new(eq, 4, 5, 1)
	peq.toggle_ultimate()
	_check(peq.fire_ultimate_staged, "earthquake stages")
	_check(peq.preview_reels().size() == 4, "earthquake preview: 3 → 4 reels (got %d)" % peq.preview_reels().size())
	_check(peq.effective_wild_indices() == [0, 1, 2, 3], "earthquake glows all 4 reels wild (got %s)" % str(peq.effective_wild_indices()))
	peq.commit()
	_check(eq.bonus_meter.value == 0, "earthquake commit consumed the meter")
	_check(eq.turn_reels.size() == 4 and eq.is_earthquake_active() and not eq.is_aoe_active(), "earthquake commit: 4 reels, active, not AoE")

	# WARDEN — Earthquake does NOT subsume Rallying Cry (independent: nuke vs party-shield) → they STACK.
	var both: Combatant = _warden(3, earth)
	both.ultimate_id = &"earthquake"
	both.bonus_meter = BonusMeter.new(); both.bonus_meter.cap = 15; both.bonus_meter.add_flat(15)
	var pboth: MainPhasePlan = MainPhasePlan.new(both, 4, 5, 1)
	pboth.toggle_ability()
	pboth.toggle_ultimate()
	_check(pboth.ability_staged and pboth.fire_ultimate_staged, "Rallying Cry stays staged alongside Earthquake")
	_check(not pboth.ability_locked_by_ultimate(), "Earthquake does not lock Rallying Cry")
	_check(pboth.preview_reels().size() == 5, "combo preview: 3 → 5 reels (4 attack + 1 utility, got %d)" % pboth.preview_reels().size())
	_check(pboth.preview_reels()[4].is_weapon_attack == false, "combo preview keeps the utility reel at the tail")
	_check(pboth.effective_wild_indices() == [0, 1, 2, 3], "combo glows only the 4 attack reels (got %s)" % str(pboth.effective_wild_indices()))
	pboth.commit()
	_check(both.turn_reels.size() == 5, "combo commit: 5 reels (got %d)" % both.turn_reels.size())
	_check(both.turn_reels[3].is_weapon_attack and not both.turn_reels[4].is_weapon_attack, "combo commit: attack reel at 3, utility reel at tail")
	_check(both.resource_pool.mana == 8 and both.bonus_meter.value == 0, "combo commit spent 4 mana AND the meter")
```

Also add a `_warden` helper (and the `earth` type) at the top of `_initialize` / bottom of the file. Add near the `crushing` load (~line 29):

```gdscript
	var earth: DamageType = load("res://combat/resources/types/earth.tres")
```

And append a `_warden` helper after `_seer` (~line 178):

```gdscript
## A mana-only Warden PC for the Rallying-Cry / Earthquake plan tests: Earth reels + a full mana pool.
func _warden(reel_count: int, type: DamageType) -> Combatant:
	var c: Combatant = Combatant.new()
	c.ability_id = &"rallying_cry"
	c.ability_resource = &"mana"
	var w: Weapon = Weapon.new(); w.base_damage = 9.0
	for i: int in range(reel_count): w.reels.append(ActionReel.make_default(type))
	c.weapon = w
	c.resource_pool = ResourcePool.new(); c.resource_pool.mana = 12; c.resource_pool.max_mana = 12
	c.begin_turn()
	return c
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 60 "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_class_abilities_plan.gd`
Expected: FAIL — Warden previews/commits don't yet add the reels / glow wild.

- [ ] **Step 3: Update `combat/main_phase_plan.gd`**

Add the constant after `BIG_BANG_SPINS` (~line 31):

```gdscript
## Earthquake (Warden) is a single-turn Ultimate (+1 WILD reel, splash + stun for the fired spin only).
const EARTHQUAKE_SPINS: int = 1
```

Extend `_ability_adds_reel` (~line 59-60):

```gdscript
func _ability_adds_reel() -> bool:
	return ability_id == &"flurry" or ability_id == &"rend" or ability_id == &"select_fate" or ability_id == &"rallying_cry"
```

In `preview_reels` (~line 164), add the `rallying_cry` case to the ability match, and an `earthquake` block. The ability `match` becomes:

```gdscript
	if ability_staged and _ability_adds_reel() and reels.size() < reel_cap:
		match ability_id:
			&"flurry":
				reels.append(ActionReel.make_default(combatant.weapon_type()))
			&"rend":
				reels.append(ActionReel.make_rend(combatant.weapon_type()))
			&"select_fate":
				reels.append(ActionReel.make_default(selected_fate_type))  # joins paylines (a weapon-attack reel)
			&"rallying_cry":
				reels.append(ActionReel.make_rallying_cry(combatant.weapon_type()))  # utility reel (out of paylines, tail)
```

Then update the reel-adding-Ultimate preview line to keep the attack reel ahead of the utility reel. Replace the existing Rampage/Collateral block (~line 176) with one that also handles Earthquake and **inserts the attack reel before any trailing non-weapon-attack reel**:

```gdscript
	# The reel-adding Ultimates preview their +1 attack reel too: Rampage (Heft/AoE aren't strips),
	# Collateral (the splash isn't a strip), and Earthquake (+1 WILD attack reel). All add one own-type
	# weapon-attack reel. Insert BEFORE any trailing utility reel (e.g. a staged Rallying Cry) so the
	# weapon-attack run stays contiguous (matching the commit-time insert).
	if fire_ultimate_staged and (ultimate_id == &"rampage" or ultimate_id == &"collateral" or ultimate_id == &"earthquake") and reels.size() < reel_cap:
		var pos: int = 0
		for i: int in range(reels.size()):
			if reels[i].is_weapon_attack:
				pos = i + 1
		reels.insert(pos, ActionReel.make_default(combatant.weapon_type()))
```

In `effective_wild_indices` (~line 201), add an `earthquake` branch alongside the Big Bang one. After the `elif fire_ultimate_staged and ultimate_id == &"big_bang":` block, add:

```gdscript
	# Earthquake makes every weapon-attack reel WILD — glow the leading attack run (the previewed
	# weapon-attack reels; the trailing utility reel is excluded).
	elif fire_ultimate_staged and ultimate_id == &"earthquake":
		var preview: Array[ActionReel] = preview_reels()
		for i: int in range(preview.size()):
			if preview[i].is_weapon_attack and not (i in out):
				out.append(i)
		out.sort()
```

In `commit` (~line 226), add the `rallying_cry` case to the ability match and the `earthquake` case to the ultimate match:

```gdscript
			&"select_fate":
				combatant.apply_select_fate(selected_fate_type, ability_cost)  # +1 reel, retype loadout (Seer)
			&"rallying_cry":
				combatant.apply_rallying_cry(ability_cost, reel_cap)           # +1 utility reel; orchestrator shields the party
```

```gdscript
			&"big_bang":
				combatant.fire_big_bang(combatant.weapon_type(), BIG_BANG_REELS, BIG_BANG_SPINS)  # 4 wild AoE reels (Seer)
			&"earthquake":
				combatant.fire_earthquake(combatant.weapon_type(), EARTHQUAKE_SPINS)  # +1 WILD reel; orchestrator splashes + stuns
```

> Note: commit order is ability-first, so Rallying Cry appends its utility reel, then `fire_earthquake`'s `_insert_weapon_attack_reel` places the attack reel ahead of it — the combo lands `[w0,w1,w2,eq,rally]`. `_ultimate_subsumes_ability()` is **unchanged** (returns false for `earthquake`), so the two stack.

- [ ] **Step 4: Run the new test AND the Seer plan test (regression)**

```bash
timeout 60 "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_class_abilities_plan.gd
```
Expected: PASS — `CLASS ABILITIES PLAN TEST PASSED` (Seer/Warrior/etc. blocks still green).

- [ ] **Step 5: Commit**

```bash
git add combat/main_phase_plan.gd tests/test_class_abilities_plan.gd
git commit -m "feat(warden): MainPhasePlan stages/previews/commits Rallying Cry + Earthquake"
```

---

### Task 6: ClassLibrary — register `&"warden"`

**Files:**
- Modify: `combat/class_library.gd` — extend `IDS`, add `&"warden"` case
- Test: `tests/test_warden_class.gd` (create); the existing Luck-cleanup regression auto-covers Warden once it's in `IDS`.

**Interfaces:**
- Consumes: `CharacterClass.build_combatant`, the `&"warden"`/`&"rallying_cry"`/`&"earthquake"` ids.
- Produces: `ClassLibrary.make(&"warden") -> CharacterClass` with the §2 profile; `&"warden"` in `ClassLibrary.IDS`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_warden_class.gd`:

```gdscript
extends SceneTree

# Headless test: the Warden class profile (spec 2026-06-29 §2). Earth Earthstave, 3 reels, mana-only
# 12/12, meter cap 15, Rallying Cry (mana) + Earthquake. Luck 0 (Chancer-exclusive).
# Run: "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_warden_class.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	_check(&"warden" in ClassLibrary.IDS, "warden is registered in ClassLibrary.IDS")

	var cc: CharacterClass = ClassLibrary.make(&"warden")
	_check(cc != null, "ClassLibrary.make(&\"warden\") returns a class")
	_check(cc.reel_count == 3, "3 reels (got %d)" % cc.reel_count)
	_check(cc.weapon_base_damage == 9.0, "Earthstave base 9 (got %s)" % str(cc.weapon_base_damage))
	_check(cc.ability_id == &"rallying_cry" and cc.ability_resource == &"mana" and cc.ability_cost == 4, "Rallying Cry: 4 mana")
	_check(cc.ultimate_id == &"earthquake", "Ultimate is Earthquake")
	_check(cc.meter_cap == 15, "meter cap 15 (match Seer, got %d)" % cc.meter_cap)
	_check(cc.base_max_stamina == 0, "mana-only (no stamina)")
	_check(cc.base_stats.luck == 0, "Luck 0 (Chancer-exclusive)")

	# Built combatant: mana-only pool derives to 12 (base 8 + Focus 4), starts full, no stamina rail.
	var w: Combatant = cc.build_combatant(true)
	_check(w.resource_pool.max_mana == 12, "max_mana = 8 + Focus 4 = 12 (got %d)" % w.resource_pool.max_mana)
	_check(w.resource_pool.mana == 12, "starts at full mana (got %d)" % w.resource_pool.mana)
	_check(w.resource_pool.max_stamina == 0, "no stamina rail (got %d)" % w.resource_pool.max_stamina)
	_check(w.bonus_meter.cap == 15, "combatant meter cap 15")
	_check(w.weapon.reels.size() == 3, "weapon has 3 reels")
	var earth: DamageType = load("res://combat/resources/types/earth.tres")
	_check(w.weapon_type() == earth, "weapon type is Earth")

	print(("WARDEN CLASS TEST PASSED" if _failures == 0 else "WARDEN CLASS TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 60 "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_warden_class.gd`
Expected: FAIL — `ClassLibrary.make(&"warden")` returns null / not in IDS.

- [ ] **Step 3: Register the Warden**

In `combat/class_library.gd`, extend `IDS` (line 8):

```gdscript
const IDS: Array[StringName] = [&"warrior", &"vanguard", &"skirmisher", &"chancer", &"ranger", &"seer", &"warden"]
```

Add the `earth` type load alongside the others in `make` (after line 20):

```gdscript
	var earth: DamageType = load("res://combat/resources/types/earth.tres")
```

Add the `&"warden"` case before the `_:` fallthrough (~line 106):

```gdscript
		&"warden":
			# Earth caster-guardian: 3-reel Earthstave, mana-only. Base Rallying Cry shields the party;
			# Ultimate Earthquake nukes one + half-splashes others + STUNS every enemy hit (spec 2026-06-29).
			var c: CharacterClass = CharacterClass.new()
			c.display_name = "Warden (Mole)"; c.species = "Mole"
			c.base_stats = _stats(1, 1, 3, 4, 2, 0)
			c.weapon_base_damage = 9.0; c.weapon_type = earth; c.reel_count = 3
			c.defense_type = earth
			# [ASSUMPTION] HP 300 for testing; meter_cap 15 — match the Seer per player directive (15/15).
			c.base_max_hp = 300; c.base_max_stamina = 0; c.base_meter_floor = 3; c.meter_cap = 15
			# Mana-only: max = base 8 + Focus 4 = 12, starts full, +1/turn. [ASSUMPTION] tune by playtest.
			c.base_max_mana = 8; c.start_mana = 12; c.mana_regen = 1
			c.ability_id = &"rallying_cry"; c.ability_cost = 4; c.ability_resource = &"mana"
			c.ultimate_id = &"earthquake"
			return c
```

- [ ] **Step 4: Run the new test AND the Luck-cleanup + class-library regressions**

```bash
timeout 60 "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_warden_class.gd
timeout 60 "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_luck_cleanup.gd
timeout 60 "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_class_library.gd
```
Expected: all PASS (the Luck regression now also iterates `&"warden"` and confirms Luck 0).

- [ ] **Step 5: Commit**

```bash
git add combat/class_library.gd tests/test_warden_class.gd
git commit -m "feat(warden): register Warden class (Earth, Rallying Cry + Earthquake, meter 15)"
```

---

### Task 7: Orchestrator wiring — splash refactor, Earthquake + Rallying Cry resolution, labels/picker

**Files:**
- Modify: `combat/combat.gd` — `_earthquake_total` member; `_do_spin` sum; `_splash_half_to_others` refactor; `_finish_spin` Earthquake + Rallying-Cry blocks; label/tooltip/picker strings
- Verify: scene loads headlessly + full suite green (the orchestrator is a `Node` scene — its wiring is verified by scene-load + the human playtest, mirroring how Big Bang/Collateral were shipped).

**Interfaces:**
- Consumes: `Combatant.is_earthquake_active`/`consume_earthquake_spin`/`earthquake_spins_remaining`/`rallying_cry_reel`/`force_stun_next_turn` (Tasks 2–4), `_enemies_of`/`_allies_of` (existing).
- Produces: orchestrator resolves the Earthquake splash + multi-target stun and the Rallying Cry party shield each spin; `&"warden"`/`&"rallying_cry"`/`&"earthquake"` UI strings.

- [ ] **Step 1: Add the `_earthquake_total` member**

In `combat/combat.gd`, after `_big_bang_total` (~line 66):

```gdscript
var _earthquake_total: int = 0          # this spin's primary-target total, for the Warden Earthquake splash (half to other enemies) + stun
```

- [ ] **Step 2: Sum the Earthquake total in `_do_spin`**

After the Big Bang total block (~line 1033), add:

```gdscript
	# Earthquake (Warden Ultimate): remember the primary total so _finish_spin can splash ceil(total/2)
	# to every OTHER enemy as Earth and force-stun every damaged enemy. Computed AFTER any reroll.
	_earthquake_total = 0
	if _attacker.is_earthquake_active():
		for a in attacks:
			_earthquake_total += a.final_damage
```

- [ ] **Step 3: Refactor the Collateral splash into a shared helper**

In `_finish_spin` (~line 1218), the Collateral block currently inlines the splash. Replace its splash loop with a call to a new helper. Change the Collateral block to:

```gdscript
	if _attacker.is_collateral_active():
		_splash_half_to_others(_attacker, _collateral_total, "Piercing")
		_attacker.consume_collateral_spin()
```

Then add the helper (place it next to `_enemies_of`, ~line 1145):

```gdscript
## Splashes ceil([param total] / 2) damage to every OTHER living enemy of [param attacker] (every enemy
## except the primary [member _defender]) and logs each with [param type_label]. Off the type chart (flat
## half) — the deferred N-vs-M per-target-type simplification. Returns the enemies actually damaged (for
## Earthquake's follow-up force-stun). Shared by Ranger Collateral and Warden Earthquake. 1v1 → no-op.
func _splash_half_to_others(attacker: Combatant, total: int, type_label: String) -> Array[Combatant]:
	var damaged: Array[Combatant] = []
	var splash: int = ceili(total / 2.0)
	if splash <= 0:
		return damaged
	for other: Combatant in _enemies_of(attacker):
		if other == _defender:
			continue
		other.take_damage(splash)
		damaged.append(other)
		_log("  💥 splash → %s takes %d %s (half of %d)." % [other.display_name, splash, type_label, total])
		if _panels.has(other):
			(_panels[other] as CombatantPanel).refresh_status()
	return damaged
```

- [ ] **Step 4: Add the Earthquake block to `_finish_spin`**

After the Big Bang block (after `_attacker.consume_big_bang_spin()`, ~line 1250), add:

```gdscript
	# Earthquake (Warden Ultimate, spec 2026-06-29 §4): the primary took full per-reel damage; now splash
	# half (ceil) to every OTHER enemy as Earth, then STUN every enemy this spin damaged — without touching
	# their Initiative (force_stun_next_turn; they keep their queue position and roll the d100 gate on their
	# turn). "Successful attack" = the spin dealt that enemy > 0 damage.
	if _attacker.is_earthquake_active():
		var quaked: Array[Combatant] = _splash_half_to_others(_attacker, _earthquake_total, "Earth")
		if _earthquake_total > 0 and _defender.is_alive():
			_defender.force_stun_next_turn = true
			_log("  ☷ EARTHQUAKE → %s is STUNNED next turn (initiative unchanged)." % _defender.display_name)
		for other: Combatant in quaked:
			if other.is_alive():
				other.force_stun_next_turn = true
				_log("  ☷ EARTHQUAKE → %s is STUNNED next turn (initiative unchanged)." % other.display_name)
		_attacker.consume_earthquake_spin()
```

- [ ] **Step 5: Add the Rallying Cry shield resolution to `_finish_spin`**

The orchestrator must read the rally reel's resolved tier. `CombatResolver.AttackResult` has **no `reel` field** (verified — fields are `face`, `damage_type`, `base_damage`, `final_damage`, `meter_gain`, `rider_effect_id`, `landed_index`), so we capture the tier in `_do_spin`, where the local `reels` (= `_attacker.turn_reels`) and the resolved `attacks` array are **index-aligned**. No `_apply_attack` change is needed.

Add a member after `_earthquake_total` (Step 1 area):

```gdscript
var _rallying_cry_tier: int = -1        # the Warden Rallying Cry reel's landed tier this spin (-1 = none)
```

In `_do_spin`, after the `_earthquake_total` block (Step 2) — i.e. after `attacks` is fully resolved and the post-spin reroll pass has run — capture the rally reel's tier by its index in the loadout:

```gdscript
	# Warden Rallying Cry: read the utility reel's resolved tier (reels and attacks are index-aligned)
	# so _finish_spin can shield the party. rallying_cry_reel is null unless Rallying Cry was committed.
	_rallying_cry_tier = -1
	if _attacker.rallying_cry_reel != null:
		var rc_idx: int = reels.find(_attacker.rallying_cry_reel)
		if rc_idx >= 0 and rc_idx < attacks.size():
			_rallying_cry_tier = attacks[rc_idx].face.result_tier
```

> `reels` is the local `var reels: Array[ActionReel] = _attacker.turn_reels` already declared in `_do_spin` (assigned after any Hunter's Mark swap, which deep-copies only weapon-attack reels — the non-weapon rally reel passes through by reference, so `find()` by identity holds).

Then in `_finish_spin`, before the `consume_*` calls (after the Earthquake block), add:

```gdscript
	# Warden Rallying Cry (spec 2026-06-29 §3): read the utility reel's tier and shield every ally.
	# SUCCESS → half-weapon shield, CRIT_SUCCESS → full-weapon shield, 2 turns, higher-total-overrides.
	if _attacker.rallying_cry_reel != null and _rallying_cry_tier != -1:
		var base: float = _attacker.weapon.base_damage
		var amount: int = 0
		if _rallying_cry_tier == ReelFace.ResultTier.CRIT_SUCCESS:
			amount = ceili(base)
		elif _rallying_cry_tier == ReelFace.ResultTier.SUCCESS:
			amount = ceili(base * 0.5)
		if amount > 0:
			_log("  ⛨ RALLYING CRY → %d shield to all allies (2 turns)." % amount)
			for ally: Combatant in _allies_of(_attacker):
				ally.apply_shield(amount, RALLYING_CRY_SHIELD_TURNS)
				if _panels.has(ally):
					(_panels[ally] as CombatantPanel).refresh_status()
					(_panels[ally] as CombatantPanel).refresh_shield()
```

Add the shield-duration constant near `BIG_BANG_SHIELD_TURNS` (grep for it; add beside it):

```gdscript
const RALLYING_CRY_SHIELD_TURNS: int = 2
```

- [ ] **Step 6: Add label / tooltip / picker strings**

Find the label/name/tooltip helpers (grep `&"big_bang": return`) and add Warden entries beside the Seer ones:

`_ultimate_tooltip` (~line 522):
```gdscript
		&"earthquake": return "Earthquake (full meter): +1 reel, all 4 reels crit-biased WILD and feeding the 4-line paylines. Primary enemy takes full damage, all others take half (Earth). Every enemy hit is STUNNED next turn — its initiative (turn order) is unchanged."
```
`_ultimate_label` (~line 663):
```gdscript
		&"earthquake": return "ULTIMATE: Earthquake"
```
`_ultimate_name` (~line 673):
```gdscript
		&"earthquake": return "EARTHQUAKE (+1 wild reel, splash, stun all hit)"
```

Find the ability-string helpers (grep `&"select_fate": return` in `_ability_tooltip`/`_ability_label`/`_ability_name`) and add:
```gdscript
		&"rallying_cry": return "Rallying Cry (4 mana): +1 no-damage reel. On a hit it shields every ally for 2 turns — half your weapon's damage on a success, full on a crit. Stacks with Earthquake."
```
```gdscript
		&"rallying_cry": return "Rallying Cry"
```
(Use the matching short forms the other classes use in `_ability_label`/`_ability_name`.)

Find `_class_tooltip` (grep `&"seer":` in it) and add:
```gdscript
		&"warden": return "Warden (Mole) — Earth Earthstave, 3 reels, mana 12. Rallying Cry shields the party; Earthquake nukes one enemy, half-splashes the rest, and STUNS everyone it hits."
```

- [ ] **Step 7: Verify the scene loads headlessly + run the full suite**

```bash
# Scene-load smoke check (no errors on load):
timeout 60 "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --quit-after 2 res://combat/combat.tscn
# Full suite — loop every test under timeout:
for t in tests/test_*.gd; do echo "== $t =="; timeout 60 "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script "res://$t"; done
```
Expected: scene loads with no script/parse errors; every suite prints `… TEST PASSED` and exits 0. Investigate any non-zero exit before proceeding.

- [ ] **Step 8: Commit**

```bash
git add combat/combat.gd
git commit -m "feat(warden): orchestrate Earthquake (splash+stun) & Rallying Cry party shield + UI strings"
```

---

### Task 8: Docs — update status snapshots

**Files:**
- Modify: `CLAUDE.md` (§8 status), `HANDOFF.md` (§6), `ARCHITECTURE.md` (if it tracks per-class systems)

**Interfaces:** none (documentation only).

- [ ] **Step 1: Update `HANDOFF.md` §6** — move the Warden from "NEXT" to a LIVE class line; record Earthquake's actual design (replaces the Pick'em placeholder); bump the suite count; note "ALL SEVEN classes live — final cross-class fairness playtest pending."

- [ ] **Step 2: Update `CLAUDE.md` §8** — append the Warden to the live-classes list with the Earthquake summary; cite the new spec `2026-06-29-warden-class-design.md`; remove the "NEXT SESSION — build Warden" block; bump the suite count.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md HANDOFF.md ARCHITECTURE.md
git commit -m "docs: Warden live — all 7 classes shipped (Earthquake Ultimate); update snapshots"
```

---

## Self-Review

**1. Spec coverage:**
- §2 Warden profile → Task 6. ✓
- §3 Rallying Cry (`make_rallying_cry`, `apply_rallying_cry`, per-tier party shield) → Tasks 1, 3, 7 (shield resolution). ✓
- §4.1 Earthquake reel mechanics (+1 contiguous WILD reel, not AoE, `_earthquake_total`) → Tasks 4, 7. ✓
- §4.2 shared half-splash helper → Task 7 Step 3. ✓
- §4.3 force-stun without Initiative change + d100 gate reuse → Task 2, applied in Task 7 Step 4. ✓
- §4.4 Earthquake + Rallying Cry stack (no subsume) → Task 5 (combo test) + commit-order note. ✓
- §5 MainPhasePlan changes → Task 5. ✓
- §6 orchestrator changes → Task 7. ✓
- §7 code surfaces + tests → all tasks; test files: `test_rallying_cry_reel`, `test_force_stun`, `test_rallying_cry`, `test_earthquake`, `test_warden_class`, `test_class_abilities_plan` additions. ✓

**2. Placeholder scan:** No TBD/TODO/"handle edge cases" — every code step shows complete code. The Rallying Cry tier capture uses the verified index-aligned `_do_spin` approach (no dependency on a non-existent `AttackResult.reel` field). ✓

**3. Type consistency:** `apply_rallying_cry(cost, cap)`, `fire_earthquake(extra_reel_type, spins)`, `is_earthquake_active()`, `consume_earthquake_spin()`, `force_stun_next_turn`, `rallying_cry_reel`, `_splash_half_to_others(attacker, total, type_label) -> Array[Combatant]`, `_earthquake_total`, `_rallying_cry_tier`, `RALLYING_CRY_SHIELD_TURNS`, `EARTHQUAKE_SPINS` — names match across tasks. ✓

**Verified during planning:** `CombatResolver.AttackResult` fields (`face`/`damage_type`/`base_damage`/`final_damage`/`meter_gain`/`rider_effect_id`/`landed_index`) — the Rallying Cry capture reads `attacks[idx].face.result_tier` by index, no source-reel field required.
