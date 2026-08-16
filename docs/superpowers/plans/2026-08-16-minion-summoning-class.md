# Minion-Summoning Class Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a new class whose base ability summons a lightweight, short-lived "minion"
combatant: a 10-face success/crit-success-only reel decides success/crit on cast; the minion's
stage-1 AoE effect fires immediately; it then rolls its own initiative and joins the turn order
starting the following round, auto-casting an escalating stage-2/stage-3 AoE effect on its own
turns with no player input, until it completes stage 3 or is killed.

**Architecture:** This plan builds ONE concrete minion type end-to-end ("Ember Minion" — a
placeholder name, not blocking) rather than a generic data-driven "minion effect" system: every
other ability in this codebase is bespoke code dispatched by id in a `match` statement (Rend,
Rallying Cry, Sundering Strike, ...), not data-driven, and the spec itself defers "actual minion
kit content" (more minion types, real balance numbers, Ultimate variants) to a future
ability-design session — building a generic effect engine now would be exactly the kind of
speculative generalization `CLAUDE.md` §7 warns against. A second minion type, when it's designed,
is a new `match` case following this same pattern, not a rewrite.

The summon ability mirrors the existing **Rallying Cry** pattern almost exactly (same shape: a
base ability that appends a no-damage utility reel, whose landed tier the orchestrator reads
post-spin to decide a payoff) — `Combatant.apply_rallying_cry()`/`rallying_cry_reel`/
`_rallying_cry_tier` is the template for `apply_summon_minion()`/`summon_reel`/`_summon_tier`.
The minion combatant itself follows the existing "lightweight combatant excluded from the
win/loss check" precedent already set by `Combatant.is_target_dummy` (excluded from
`TurnManager._living()`), and its "no player input, auto-resolves" turn follows the existing
`_take_dummy_turn()`/`is_target_dummy` branch in `_on_turn_started()` exactly — a new
`is_minion` field gets the identical treatment. Turn-order insertion deliberately does NOT reuse
`TurnManager.insert_acting_this_round()` (which the Hollow Warden's mid-fight enemy spawns use) —
that method makes a spawned combatant act in the CURRENT round too, but the locked spec decision
is the opposite for minions (stage 1 fires immediately via direct code, THEN it joins the
following round's turn order) — so this plan adds a new `TurnManager.roll_initiative_for(c)`
(a refactor-out of the existing `roll_initiative()` loop body, extracting no behavior change) and
appends the minion directly to `combatants` without touching the current round's already-fixed
`_order`.

**Tech Stack:** Godot 4.6 GDScript, headless `SceneTree`-based test scripts under `tests/`.

**Spec:** `docs/superpowers/specs/2026-08-16-combat-encounter-revamp-design.md` §3
(Minion-summoning class).

## Global Constraints

- Engine: Godot 4.6+, GDScript only (no C#) — `CLAUDE.md` §2.
- Static typing for all new vars/signatures — `CLAUDE.md` §2.
- All numeric balance values in this plan (HP, damage, resource cost) are `[ASSUMPTION]`
  placeholders per `CLAUDE.md` §4 — build them as easily-editable data, do not hand-tune them
  now; they get tuned by playtest.
- Class name (`&"summoner"`) and minion display name ("Ember Minion") are placeholders — naming
  is explicitly still open per the spec, not blocking.
- Minions are a separate combatant category, NOT counted against the 3-PC party-selection cap —
  confirmed by research: the cap is enforced only in the pre-fight roster-selection screen, which
  a mid-fight-summoned minion never passes through, so no guard code is needed for this.
  "Focus" is a stat, not a spendable resource rail — this class's `ability_resource` must be
  `&"stamina"` or `&"mana"` (the only two real rails), matching the spec's "Stamina/Focus/Mana"
  phrasing loosely (Focus feeds max Mana via `Stats`, it isn't itself spendable).
- Only ONE minion active at a time — summoning replaces any existing one (expire-then-replace,
  reusing the existing `take_damage(hp)` self-defeat pattern, not new removal logic).
- This plan does NOT implement Ultimate variants (explicitly future ability-design work per
  spec) — the class's `ultimate_id` is a placeholder pointing at an existing shared Ultimate
  archetype so dispatch code doesn't need a null-check special case.
- This plan does NOT implement a second minion type or a picker UI — the "fixed ability slot per
  minion type" decision is honored structurally (a second type would be a new base-or-extra
  ability id and a new `match` case), but only one type ships in this plan.

---

## Task 1: `Combatant`/`TurnManager` plumbing for lightweight, auto-resolving combatants

**Files:**
- Modify: `combat/combatant.gd`
- Modify: `combat/turn_manager.gd`
- Test: `tests/test_turn_manager.gd`

**Interfaces:**
- Produces on `Combatant`:
  - `var is_minion: bool = false` — placed immediately after `is_target_dummy` (mirrors its doc
    comment style: "excluded from the combat-end check").
  - `var active_minion: Combatant = null` — the summoner's currently-active minion, or null. Set
    by `apply_summon_minion()` (Task 4), read/expired by the payoff code in Task 5.
  - `var minion_stage: int = 0` — how many stages THIS minion (when `is_minion` is true) has
    completed. 0 = not yet run its first post-summon stage (stage 1 already ran synchronously at
    summon time, see Task 5 — this counter tracks stage 2/3 on the minion's own subsequent
    turns).
- Produces on `TurnManager`:
  - `func roll_initiative_for(c: Combatant) -> int` — rolls initiative for exactly one
    combatant (the body currently inlined in `roll_initiative()`'s loop), returns the raw
    percentile value. `roll_initiative()` is refactored to call this once per combatant in its
    existing loop — **no observable behavior change**, purely an extraction.
- Modifies: `TurnManager._living(is_player)` — excludes `is_minion` combatants the same way it
  already excludes `is_target_dummy`.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_turn_manager.gd` (open the file first to match its exact `_check()`/`_mk()`
helper style):

```gdscript
	# --- is_minion combatants are excluded from _living()'s win/loss gate, same as is_target_dummy ---
	var minion_tm: TurnManager = TurnManager.new()
	var pc_side: Combatant = _mk("PC", true, 10)
	var enemy_side: Combatant = _mk("Enemy", false, 10)
	var lone_minion: Combatant = _mk("Minion", true, 10)
	lone_minion.is_minion = true
	minion_tm.combatants = [pc_side, enemy_side, lone_minion]
	pc_side.take_damage(999)  # kill the only real PC
	_check(minion_tm.is_combat_over(), "combat is over when the only real PC dies, even if an is_minion combatant on the same side survives")
	_check(not minion_tm.winner_is_player(), "the surviving minion does NOT count as a player win")

	# --- roll_initiative_for() rolls exactly one combatant, independent of the others ---
	var extract_tm: TurnManager = TurnManager.new()
	var solo: Combatant = _mk("Solo", true, 10)
	extract_tm.combatants = [solo]
	var solo_value: int = extract_tm.roll_initiative_for(solo)
	_check(solo_value >= 1 and solo_value <= 100, "roll_initiative_for returns a value in 1..100 (got %d)" % solo_value)
	_check(solo.current_initiative != 0, "roll_initiative_for actually sets the combatant's current_initiative")

	# --- roll_initiative() still behaves identically after the refactor (no regression) ---
	var regress_tm: TurnManager = TurnManager.new()
	var r1: Combatant = _mk("R1", true, 10)
	var r2: Combatant = _mk("R2", false, 10)
	regress_tm.combatants = [r1, r2]
	regress_tm.roll_initiative()
	_check(r1.current_initiative != 0 and r2.current_initiative != 0, "roll_initiative() still rolls every combatant after the refactor")
```

(Use whatever helper this file already provides for building a `Combatant` with a given
`is_player`/HP — the sketch above assumes a `_mk(name, is_player, hp)`-shaped helper; adapt to
the file's actual helper signature.)

- [ ] **Step 2: Run test to verify it fails**

Run (Godot executable lives one directory above the repo root):
`../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_turn_manager.gd`
Expected: FAIL — `is_minion`/`roll_initiative_for` don't exist yet.

- [ ] **Step 3: Write minimal implementation**

In `combat/combatant.gd`, add immediately after the existing `is_target_dummy` field
(`combat/combatant.gd:91`):

```gdscript
## True for a lightweight, auto-resolving combatant summoned by an ability mid-fight (2026-08-16
## minion-summoning-class spec §3) — EXCLUDED from the combat-end check (TurnManager._living), same
## treatment as is_target_dummy, so a surviving minion can never itself constitute a "win" for
## either side. Also drives combat.gd's _on_turn_started() branch that skips the normal player/
## enemy Main-1 flow entirely (mirrors is_target_dummy's own dedicated _take_dummy_turn() branch).
var is_minion: bool = false
```

Add near other per-combatant ability-adjacent state (e.g. alongside `rallying_cry_reel`):

```gdscript
## This combatant's currently-active summoned minion, or null (2026-08-16 minion-summoning-class
## spec §3). Only one minion may be active at a time — summoning a new one expires this one first
## (via take_damage(hp), the existing self-defeat pattern — see apply_summon_minion()).
var active_minion: Combatant = null

## How many post-summon stages THIS combatant (when is_minion is true) has completed on its OWN
## turns. Stage 1 always fires synchronously at summon time (2026-08-16 spec §3) and is NOT
## counted here; this tracks stage 2/3 on the minion's subsequent turns. Expires after stage 3.
var minion_stage: int = 0
```

In `combat/turn_manager.gd`, refactor `roll_initiative()` (lines 44-50):

```gdscript
## Rolls Initiative once for every combatant (2-reel d100, 00=100) and stores it as the live
## sort key. Emits [signal initiative_rolled] per combatant (DESIGN.md §4.1-§4.2).
func roll_initiative() -> void:
	for c: Combatant in combatants:
		roll_initiative_for(c)

## Rolls Initiative for exactly ONE combatant (extracted from roll_initiative()'s loop body,
## 2026-08-16 minion-summoning-class spec §3 — a minion needs to roll its own initiative the
## moment it's summoned, independent of every other combatant's already-fixed rolls). Returns the
## raw percentile value (pre-Finesse), same value roll_initiative() used to emit per combatant.
func roll_initiative_for(c: Combatant) -> int:
	var value: int = InitiativeReel.roll_percentile(_initiative_tens, _initiative_ones)
	c.base_initiative = value + c.effective_stats().finesse
	c.tiebreak_roll = _initiative_tens.spin().digit
	c.recompute_initiative()
	initiative_rolled.emit(c, value)
	return value
```

In `_living(is_player)` (line 96-103), change the filter condition:

```gdscript
func _living(is_player: bool) -> Array[Combatant]:
	var out: Array[Combatant] = []
	for c: Combatant in combatants:
		if c.is_player == is_player and c.is_alive() and not c.is_target_dummy and not c.is_minion:
			out.append(c)
	return out
```

- [ ] **Step 4: Run test to verify it passes**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Run the existing test_initiative_tiebreak.gd for regressions**

`../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_initiative_tiebreak.gd`
Expected: still PASS — the refactor must not change `roll_initiative()`'s observable behavior.

- [ ] **Step 6: Commit**

```bash
git add combat/combatant.gd combat/turn_manager.gd tests/test_turn_manager.gd
git commit -m "feat(minion): add is_minion/active_minion/minion_stage fields, extract roll_initiative_for()"
```

---

## Task 2: `ActionReel.make_summon_reel()`

**Files:**
- Modify: `combat/resources/action_reel.gd`
- Test: `tests/test_action_reel.gd`

**Interfaces:**
- Produces: `static func make_summon_reel() -> ActionReel` — identical shape to
  `make_item_use()` (45 SUCCESS + 5 CRIT_SUCCESS out of 50, no fail tiers, multiplier 0 on every
  face, `is_weapon_attack = false`, `charges_meter = false`), per the spec's explicit "10-face
  reel matching a consumable healing potion's reel, no chance of failure" decision.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_action_reel.gd`, following the same tier-counting style used for
`make_flee()`'s test (added by the Flee plan — open that section of the file to match its exact
pattern):

```gdscript
	# --- make_summon_reel(): no-damage utility reel, item-use-shaped tier counts, out of paylines ---
	var summon_reel: ActionReel = ActionReel.make_summon_reel()
	_check(summon_reel.faces.size() == 50, "make_summon_reel: 50 faces (got %d)" % summon_reel.faces.size())
	_check(not summon_reel.is_weapon_attack, "make_summon_reel: is_weapon_attack = false (out of paylines)")
	_check(not summon_reel.charges_meter, "make_summon_reel: charges_meter = false")
	var summon_success: int = 0
	var summon_crit: int = 0
	for f: ReelFace in summon_reel.faces:
		_check(f.multiplier == 0.0, "make_summon_reel: every face has multiplier 0.0")
		_check(f.result_tier == ReelFace.ResultTier.SUCCESS or f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS, "make_summon_reel: no FAILURE/CRIT_FAILURE/NEUTRAL faces")
		if f.result_tier == ReelFace.ResultTier.SUCCESS: summon_success += 1
		else: summon_crit += 1
	_check(summon_success == 45, "make_summon_reel: 45 success faces (got %d)" % summon_success)
	_check(summon_crit == 5, "make_summon_reel: 5 crit-success faces (got %d)" % summon_crit)
```

- [ ] **Step 2: Run test to verify it fails**

`../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_action_reel.gd`
Expected: FAIL — `make_summon_reel` not defined.

- [ ] **Step 3: Write minimal implementation**

Add to `combat/resources/action_reel.gd`, after `make_item_use()`:

```gdscript
## Builds the minion-summon reel (2026-08-16 minion-summoning-class spec §3): a no-damage utility
## reel with NO failure tiers — identical shape to make_item_use() (45 SUCCESS + 5 CRIT_SUCCESS,
## 90%/10%), since a summon should never simply fail, only land baseline vs. a stronger/tankier
## variant. Every face has multiplier 0; the orchestrator reads the landed tier post-spin and
## builds the minion itself (SUCCESS = baseline, CRIT_SUCCESS = the tankier variant).
## is_weapon_attack = false (out of paylines); charges_meter = false (same reasoning as
## make_rallying_cry()/make_item_use() — the summon IS the payoff).
static func make_summon_reel() -> ActionReel:
	var reel: ActionReel = ActionReel.new()
	reel.is_weapon_attack = false
	reel.charges_meter = false
	for i: int in range(5):
		reel.faces.append(_make_face(ReelFace.ResultTier.CRIT_SUCCESS, 0.0))
	for i: int in range(45):
		reel.faces.append(_make_face(ReelFace.ResultTier.SUCCESS, 0.0))
	reel.faces.shuffle()
	return reel
```

- [ ] **Step 4: Run test to verify it passes**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add combat/resources/action_reel.gd tests/test_action_reel.gd
git commit -m "feat(minion): add ActionReel.make_summon_reel() utility reel"
```

---

## Task 3: `MinionLibrary` — the Ember Minion combatant

**Files:**
- Create: `combat/minion_library.gd`
- Test: `tests/test_minion_library.gd` (new)

**Interfaces:**
- Consumes: `Combatant.is_minion`/`acts_last` (Task 1).
- Produces: `class_name MinionLibrary extends RefCounted`,
  `static func make(tanky: bool) -> Combatant` — builds a fresh "Ember Minion" `Combatant`:
  `is_player = true`, `is_minion = true`, `acts_last = true` (mirrors the Hollow Warden's own
  minions — "always acts last"), `weapon = null` (a weaponless combatant, same as a target
  dummy — it never spins a weapon reel, its damage is bespoke AoE code in Task 6), no
  `resource_pool`/Ultimate (it never takes a Main-1 turn). Baseline HP 15, tanky (crit-summoned)
  HP 25 — `[ASSUMPTION]` placeholders.

- [ ] **Step 1: Write the failing test**

Create `tests/test_minion_library.gd` (mirror `tests/test_turn_manager.gd`'s `extends
SceneTree`/`_check()`/`_initialize()` convention):

```gdscript
extends SceneTree

# Headless test for MinionLibrary.make() (2026-08-16 minion-summoning-class spec §3). Run:
# Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_minion_library.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var baseline: Combatant = MinionLibrary.make(false)
	_check(baseline.is_player, "baseline minion is_player = true (ally side)")
	_check(baseline.is_minion, "baseline minion is_minion = true")
	_check(baseline.acts_last, "baseline minion acts_last = true")
	_check(baseline.weapon == null, "baseline minion has no weapon (weaponless, like a target dummy)")
	_check(baseline.is_alive(), "baseline minion starts alive")
	_check(baseline.max_hp == 15, "baseline minion max_hp = 15 (got %d)" % baseline.max_hp)

	var tanky: Combatant = MinionLibrary.make(true)
	_check(tanky.max_hp == 25, "tanky (crit-summoned) minion max_hp = 25 (got %d)" % tanky.max_hp)
	_check(tanky.max_hp > baseline.max_hp, "tanky minion has more HP than baseline")

	print(("MINION LIBRARY TEST PASSED" if _failures == 0 else "MINION LIBRARY TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

`../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_minion_library.gd`
Expected: FAIL — `MinionLibrary` class doesn't exist.

- [ ] **Step 3: Write minimal implementation**

Create `combat/minion_library.gd` (modeled directly on `combat/combat.gd`'s own
`_make_combatant()` helper — a weaponless, Ultimate-less, resource-pool-less minimal combatant):

```gdscript
class_name MinionLibrary
extends RefCounted

## Builds the "Ember Minion" summoned combatant (2026-08-16 minion-summoning-class spec §3). A
## real Combatant with real HP, targetable and killable — deliberately NOT a special-cased fake:
## it participates in _enemies_of()/_allies_of() (both keyed purely on is_player) and the normal
## take_damage()/defeated pipeline for free, since it's a genuine is_player=true Combatant. It is
## weaponless (weapon = null, same as a target dummy) because it never takes a normal Main-1 turn
## — its stage effects are bespoke code in combat.gd, not a weapon-reel spin. [ASSUMPTION] HP
## values — tune by playtest, per CLAUDE.md §4.
const BASELINE_HP: int = 15
const TANKY_HP: int = 25

## [param tanky] is true for a Critical-Success summon (2026-08-16 spec §3: "Crit Success = a
## stronger/tankier version of the same minion").
static func make(tanky: bool) -> Combatant:
	var earth: DamageType = load("res://combat/resources/types/earth.tres")
	var c: Combatant = Combatant.new()
	c.display_name = "Ember Minion"
	c.is_player = true
	c.is_minion = true
	c.acts_last = true
	c.defense_type = earth
	c.weapon = null
	c.base_max_hp = TANKY_HP if tanky else BASELINE_HP
	c.base_meter_floor = 0
	c.base_stats = Stats.new()
	c.apply_stats()   # derive max_hp from stats BEFORE seeding hp
	c.start_combat()
	return c
```

(Confirm `Combatant.start_combat()`/`apply_stats()` don't require a non-null `weapon` or
`resource_pool` before calling them — `_make_dummy()`'s existing weaponless-combatant path in
`combat.gd:331-336` already proves this works, since it goes through the same
`_make_combatant()` helper with `weapon = null`.)

- [ ] **Step 4: Run test to verify it passes**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add combat/minion_library.gd tests/test_minion_library.gd
git commit -m "feat(minion): add MinionLibrary.make() — the Ember Minion combatant"
```

---

## Task 4: The Summoner class + `apply_summon_minion()` + `MainPhasePlan` dispatch

**Files:**
- Modify: `combat/class_library.gd`
- Modify: `combat/combatant.gd`
- Modify: `combat/main_phase_plan.gd`
- Test: `tests/test_summoner_class.gd` (new), `tests/test_main_phase_plan.gd`

**Interfaces:**
- Consumes: `ActionReel.make_summon_reel()` (Task 2).
- Produces:
  - `ClassLibrary.IDS` gains `&"summoner"`; `ClassLibrary.make(&"summoner")` returns a
    `CharacterClass` with `ability_id = &"ember_minion"`, `ability_cost` = 4,
    `ability_resource = &"mana"`.
  - `Combatant.summon_reel: ActionReel = null` (mirrors `rallying_cry_reel`), cleared in
    `begin_turn()`.
  - `func apply_summon_minion(cost: int, cap: int) -> bool` on `Combatant` (mirrors
    `apply_rallying_cry()` exactly).
  - `MainPhasePlan.preview_reels()`/`commit()` gain an `&"ember_minion"` case, following the
    existing `&"rallying_cry"` case's shape.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_summoner_class.gd` (mirror an existing class-kit test file, e.g.
`tests/test_warden_class.gd` — open it first to match its exact assertions/style):

```gdscript
extends SceneTree

# Headless test for the Summoner class shell (2026-08-16 minion-summoning-class spec §3). Run:
# Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_summoner_class.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	_check(&"summoner" in ClassLibrary.IDS, "summoner is registered in ClassLibrary.IDS")
	var cls: CharacterClass = ClassLibrary.make(&"summoner")
	_check(cls != null, "ClassLibrary.make(&summoner) returns a real CharacterClass")
	_check(cls.ability_id == &"ember_minion", "summoner base ability is ember_minion (got %s)" % cls.ability_id)
	_check(cls.ability_resource == &"mana", "summoner's ability resource is mana (got %s)" % cls.ability_resource)

	var c: Combatant = cls.build_combatant(true)
	_check(c.ability_id == &"ember_minion", "built Combatant carries the ember_minion ability_id")
	_check(c.resource_pool != null, "built Combatant has a resource pool to pay the summon cost")

	print(("SUMMONER CLASS TEST PASSED" if _failures == 0 else "SUMMONER CLASS TEST FAILED: %d" % _failures))
	quit(_failures)
```

Add to `tests/test_main_phase_plan.gd` (following the exact `_mk_pc()`-based style already used
for the `&"rallying_cry"`/Flee cases in this file):

```gdscript
	# --- Summon Minion base ability: appends the summon reel, previewed but not committed ---
	var summoner: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	summoner.resource_pool.mana = 10
	var plan_summon: MainPhasePlan = MainPhasePlan.new(summoner, summoner.ability_cost, 5, 2)
	_check(plan_summon.can_stage_ability(), "ember_minion ability stageable when affordable")
	plan_summon.toggle_ability()
	_check(plan_summon.ability_staged, "ember_minion staged after toggle")
	var preview: Array[ActionReel] = plan_summon.preview_reels()
	_check(not preview.is_empty() and not preview[preview.size() - 1].is_weapon_attack, "previewed summon reel is out of paylines (trailing utility reel)")
	plan_summon.commit()
	_check(summoner.summon_reel != null, "commit(): summon_reel is set on the combatant")
	_check(summoner.resource_pool.mana == 10 - summoner.ability_cost, "commit(): mana was spent (got %d)" % summoner.resource_pool.mana)
```

- [ ] **Step 2: Run tests to verify they fail**

```
../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_summoner_class.gd
../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_main_phase_plan.gd
```
Expected: FAIL — the class/ability don't exist yet.

- [ ] **Step 3: Write minimal implementation**

In `combat/class_library.gd`, add `&"summoner"` to `IDS` and a `match` branch (read the file's
actual current class-building style for an existing simple class like Warrior/Warden before
writing this, to match field-by-field conventions exactly — weapon type/base damage/reel count,
`base_stats`, HP/Mana seed values, `combat_role`, `defense_type`, `payline_profile_id` are all
required fields per the class shape documented in this plan's research):

```gdscript
&"summoner":
	var summoner := CharacterClass.new()
	summoner.class_id = &"summoner"
	summoner.display_name = "Summoner"   # placeholder — naming still open
	summoner.combat_role = &"support"
	summoner.weapon_type = load("res://combat/resources/types/earth.tres")
	summoner.weapon_base_damage = 6.0
	summoner.reel_count = 2
	summoner.weapon_display_name = "Warden's Staff"
	summoner.defense_type = load("res://combat/resources/types/earth.tres")
	summoner.base_stats = Stats.new()
	summoner.ability_id = &"ember_minion"
	summoner.ability_cost = 4
	summoner.ability_resource = &"mana"
	summoner.ultimate_id = &"sticky_wild"   # placeholder — real Ultimate variants are future work
	summoner.extra_abilities = []           # no extra abilities in this plan's scope
	summoner.payline_profile_id = &"default"
	return summoner
```

(Adjust exact field names/required fields to match `CharacterClass`'s real current shape and
whatever a minimal existing class branch — e.g. Warrior's — actually sets; the sketch above may
be missing a field or two the real resource requires, such as HP/Mana seed values. Fill in
whatever else `build_combatant()` reads that isn't listed here, using another simple class as
the reference.)

In `combat/combatant.gd`, add `summon_reel` near `rallying_cry_reel`:

```gdscript
## The minion-summon reel staged this turn, or null (2026-08-16 minion-summoning-class spec §3).
## Mirrors rallying_cry_reel/item_use_reel/flee_reel exactly: set once on commit, its landed tier
## read by the orchestrator post-spin to decide whether the summoned minion is baseline or the
## tankier crit-success variant.
var summon_reel: ActionReel = null
```

Add `summon_reel = null` to `begin_turn()`'s existing per-turn reset block, alongside
`flee_reel = null`.

Add `apply_summon_minion()` right after `apply_rallying_cry()` (mirrors it exactly, swapping the
reel factory and the resource rail):

```gdscript
## Stages the Summoner's "Ember Minion" base ability (2026-08-16 spec §3): spends [param cost]
## Mana, appends ActionReel.make_summon_reel() to this turn's loadout, and records the reel on
## [member summon_reel] so the orchestrator can read its post-spin tier and build the minion.
## Respects the [param cap]-reel ceiling, mirroring apply_rallying_cry() exactly. Returns false
## (no change) if at the cap or Mana is unaffordable.
func apply_summon_minion(cost: int, cap: int) -> bool:
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
1. `_ability_adds_reel()` (line 91-92): add `or ability_id == &"ember_minion"` to the existing
   `or`-chain (it appends a reel, same family as Rallying Cry/Select Fate).
2. `preview_reels()` (the `match ability_id:` block, alongside the existing `&"rallying_cry":`
   case): add
   ```gdscript
   &"ember_minion":
   	reels.append(ActionReel.make_summon_reel())  # utility reel (out of paylines, tail)
   ```
3. `commit()` (the `match ability_id:` block, alongside `&"rallying_cry":`): add
   ```gdscript
   &"ember_minion":
   	combatant.apply_summon_minion(talent_cost, reel_cap)
   ```

- [ ] **Step 4: Run tests to verify they pass**

Same two commands as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add combat/class_library.gd combat/combatant.gd combat/main_phase_plan.gd tests/test_summoner_class.gd tests/test_main_phase_plan.gd
git commit -m "feat(minion): add the Summoner class and its Ember Minion base ability"
```

---

## Task 5: combat.gd — summon payoff (build the minion, fire stage 1, join next round)

**Files:**
- Modify: `combat/combat.gd`

**Interfaces:**
- Consumes: `Combatant.summon_reel`/`active_minion`/`minion_stage` (Task 1/4),
  `MinionLibrary.make()` (Task 3), `TurnManager.roll_initiative_for()` (Task 1).
- Produces: `var _summon_tier: int = -1` (mirrors `_rallying_cry_tier`), a payoff block in
  `_finish_spin()`, and `func _run_minion_stage(minion: Combatant, stage: int) -> void` (the
  concrete Ember Minion effect — used here for stage 1, and again by Task 6 for stages 2/3).

- [ ] **Step 1: Track the summon reel's landed tier in `_do_spin()`**

Add the member declaration alongside `_rallying_cry_tier`/`_item_use_tier`/`_flee_tier`
(`combat/combat.gd:153-155`):

```gdscript
var _summon_tier: int = -1       # this spin's summon reel landed tier (-1 = none staged)
```

In `_do_spin()`, immediately after the existing Flee-tier block (`combat.gd:2078-2082`), add a
4th parallel block, following the identical pattern:

```gdscript
	# Minion-summon reel (2026-08-16 spec §3): read the utility reel's resolved tier the same way,
	# so _finish_spin can build the minion. summon_reel is null unless Ember Minion was staged.
	_summon_tier = -1
	if _attacker.summon_reel != null:
		var summon_idx: int = reels.find(_attacker.summon_reel)
		if summon_idx >= 0 and summon_idx < attacks.size():
			_summon_tier = attacks[summon_idx].face.result_tier
```

- [ ] **Step 2: Add the payoff block in `_finish_spin()`**

Add after the existing Flee branch's block (right where the Flee plan's own payoff sits in
`_finish_spin()`, around `combat.gd:2684` — find the exact spot by searching for
`_attacker.flee_reel != null and _flee_tier != -1`):

```gdscript
	# Ember Minion summon (2026-08-16 spec §3): SUCCESS = baseline minion, CRIT_SUCCESS = the
	# tankier variant. Only one minion may be active at a time — expire any existing one first
	# (self-inflicted fatal damage, the same pattern _sacrifice_reinforcements() already uses for
	# the Hollow Warden's own leftover adds — no bespoke removal logic needed). Stage 1 fires
	# IMMEDIATELY (not on the minion's own turn); it then rolls its own initiative and is appended
	# directly to combatants WITHOUT insert_acting_this_round() — that method would also make it
	# act THIS round, which the locked spec decision explicitly does not want (it joins the
	# turn order starting the FOLLOWING round only).
	if _attacker.summon_reel != null and _summon_tier != -1:
		if _attacker.active_minion != null and _attacker.active_minion.is_alive():
			_attacker.active_minion.take_damage(_attacker.active_minion.hp)
		var tanky: bool = _summon_tier == ReelFace.ResultTier.CRIT_SUCCESS
		var minion: Combatant = MinionLibrary.make(tanky)
		_attacker.active_minion = minion
		minion.minion_stage = 0
		_turn_manager.roll_initiative_for(minion)
		_turn_manager.combatants.append(minion)  # NOT insert_acting_this_round() — see comment above
		_build_minion_panel(minion)
		var tier_text: String = "CRITICAL SUCCESS — a stronger" if tanky else "SUCCESS — a"
		_log("  🔥 %s summons Ember Minion — %s minion appears! (%d HP)" % [_attacker.display_name, tier_text, minion.max_hp])
		_run_minion_stage(minion, 1)
```

- [ ] **Step 3: Add `_build_minion_panel()` and `_run_minion_stage()`**

`_build_minion_panel()` mirrors `_spawn_enemy_mid_combat()`'s panel-building portion (find that
method, `combat/combat.gd:615` per this plan's research, and copy its `CombatantPanel`
+ click-catcher `Button` construction, adapting the position to a new spot near the PC column —
e.g. below the party column, or a dedicated slot; exact placement is a visual detail to verify in
Step 5's manual check, not a hard requirement):

```gdscript
## Builds a CombatantPanel for a freshly-summoned minion, positioned directly below the PC column
## (2026-08-16 spec §3) — same x=24.0 as _place_party_column()'s PC column, same y-step math
## (312.0 panel height + 14.0 gap) that column already uses, placed one slot past the last PC.
## Mirrors _spawn_enemy_mid_combat()'s panel-building portion; a minion never needs a click-catcher
## target button since it's never player-targetable via the ally-target UI (only real PCs can be
## item/ability targets) — build the panel only, no click-catcher.
func _build_minion_panel(minion: Combatant) -> void:
	var panel := CombatantPanel.new()
	panel.position = Vector2(24.0, 80.0 + float(_pcs.size()) * (312.0 + 14.0))
	add_child(panel)
	panel.bind(minion)
	_panels[minion] = panel
	minion.defeated.connect(_on_minion_panel_death.bind(minion))

## A minion's panel-hide-on-death handler (2026-08-16 spec §3) — mirrors _on_enemy_panel_death()
## exactly (hide, don't remove from _panels; other code dereferences that dict without existence
## checks).
func _on_minion_panel_death(minion: Combatant) -> void:
	if _panels.has(minion):
		(_panels[minion] as CombatantPanel).visible = false

## Runs the Ember Minion's fixed 3-stage AoE effect (2026-08-16 spec §3): a scaling AoE damage
## pulse, stage N deals N x BASE_STAGE_DAMAGE to every living enemy of the minion's side (Earth
## typed, matching its defense_type). [ASSUMPTION] damage numbers — tune by playtest. Expires the
## minion (self-inflicted fatal damage, same pattern as _sacrifice_reinforcements()) once stage 3
## completes.
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

- [ ] **Step 4: Manual verification (no automated test for panel placement — Task 7 covers the
      logical lifecycle end-to-end)**

Flag for the human playtest, same accepted-gap pattern as the Flee/Initiative plans' own
UI-placement steps: confirm the minion's panel appears in a sensible spot and doesn't overlap the
PC column or get clipped, and that summoning a second minion while one is already active visibly
replaces it (the old one's panel hides, the new one's appears).

- [ ] **Step 5: Commit**

```bash
git add combat/combat.gd
git commit -m "feat(minion): summon payoff — build the minion, fire stage 1 immediately, queue for next round"
```

---

## Task 6: combat.gd — minion turn auto-resolution (stages 2/3, expiry)

**Files:**
- Modify: `combat/combat.gd`

**Interfaces:**
- Consumes: `_run_minion_stage()` (Task 5), `Combatant.is_minion`/`minion_stage` (Task 1).
- Produces: `func _take_minion_turn(c: Combatant) -> void` (mirrors `_take_dummy_turn()`), wired
  into `_on_turn_started()`.

- [ ] **Step 1: Wire the branch into `_on_turn_started()`**

In `_on_turn_started()`, immediately after the existing `is_target_dummy` check
(`combat.gd:1357-1360`, `if c.is_target_dummy: _take_dummy_turn(c); return`), add the identical
shape for minions, BEFORE the stun-check/spin flow that follows:

```gdscript
	# Minions never take a normal Main-1 turn — no reels, no player input (2026-08-16 spec §3).
	# Checked in the same spot/style as is_target_dummy, immediately before the stun/spin flow.
	if c.is_minion:
		_take_minion_turn(c)
		return
```

- [ ] **Step 2: Write `_take_minion_turn()`**

Add right after `_take_dummy_turn()` (`combat.gd:1391-1409`), mirroring its structure exactly
(disable every Main-1 button, no reel strips, brief beat, then skip straight to End/advance):

```gdscript
## A minion's whole turn: auto-resolve its next stage immediately, no reels, no player input
## (2026-08-16 spec §3). Mirrors _take_dummy_turn()'s structure exactly. Expiry-on-stage-3 is
## handled inside _run_minion_stage() itself; if it fires here, the combatant is already dead by
## the time TurnManager gets back around to it, and _announce_current() already skips dead
## combatants (no extra bookkeeping needed here).
func _take_minion_turn(c: Combatant) -> void:
	_spin_button.disabled = true
	_abilities_button.disabled = true
	_ultimate_button.disabled = true
	_items_button.disabled = true
	_team_up_button.disabled = true
	_flee_button.disabled = true
	var none: Array[ActionReel] = []
	_prepare_strips(none)  # no reels — the minion doesn't spin
	c.minion_stage += 1
	_run_minion_stage(c, c.minion_stage)
	get_tree().create_timer(ENEMY_THINK_DELAY).timeout.connect(_phase_manager.resume_after_combat, CONNECT_ONE_SHOT)
```

- [ ] **Step 3: Commit**

```bash
git add combat/combat.gd
git commit -m "feat(minion): auto-resolve the minion's stage 2/3 turns, no player input"
```

---

## Task 7: End-to-end lifecycle tests

**Files:**
- Test: `tests/test_minion_lifecycle.gd` (new)

**Interfaces:**
- Consumes: everything from Tasks 1-6, plus the same `CombatHandoff.begin_encounter()` /
  `combat.tscn` harness pattern used by `tests/test_combat_win_recovery.gd` and the Flee/
  Initiative plans' own end-to-end tests — read at least one of those fully before writing this
  file, per this project's established convention of reusing the exact harness rather than
  inventing a new one.

- [ ] **Step 1: Write the failing test**

Create `tests/test_minion_lifecycle.gd`. Build a real `combat.tscn` instance with a Summoner PC
(via `ClassLibrary.make(&"summoner").build_combatant(true)`) and at least one enemy, using the
same `CombatHandoff.begin_encounter()` + `roll_initiative_for_test()` (from the Visible
Initiative-Reels plan — already merged) setup every other combat.tscn test in this codebase now
uses to get a live round started. Then:

1. **Force a SUCCESS summon and verify stage 1 fires immediately.** Stage the ability
   (`_plan.toggle_ability()`/`commit()` on the Summoner's own turn), force the summon reel's
   landed face to SUCCESS (mirror the Flee plan's own "force a specific reel outcome" technique —
   swap `combatant.summon_reel.faces` to a single known-tier face before spinning), drive a real
   spin (`_do_spin()`), and assert: the enemy took `MINION_BASE_STAGE_DAMAGE * 1` damage
   immediately (same spin, before any new round has started), `_attacker.active_minion` is set
   and alive, and it is NOT in the current round's remaining turn order (its first appearance in
   `get_turn_order()` should be next round — assert `inst._turn_manager.combatants.has(minion)`
   is true but the minion doesn't act again until `round_started` fires again).
2. **Advance to the minion's turn next round and verify stage 2.** Continue driving turns
   (end the Summoner's turn, let the enemy act, advance to the next round) until the minion's
   `turn_started` fires; assert `minion_stage` becomes 2 and the enemy takes
   `MINION_BASE_STAGE_DAMAGE * 2` more damage, automatically, with no button press required.
3. **Advance again and verify stage 3 + expiry.** Same pattern for stage 3; assert the minion is
   no longer alive afterward (`not minion.is_alive()`) and `_turn_manager.is_combat_over()`
   correctly still reflects only the REAL PCs/enemies (the minion's death must never trigger a
   loss check on its own — confirms Task 1's `_living()` exclusion end-to-end).
4. **Force a CRIT_SUCCESS summon and verify the tankier variant.** Same as case 1 but with the
   reel forced to CRIT_SUCCESS; assert the new minion's `max_hp` is the tanky value.
5. **Summon a second minion while one is active and verify replacement.** Summon once, then
   summon again before the first minion completes its stages; assert the FIRST minion is no
   longer alive (expired) and `active_minion` now points at the second one.

- [ ] **Step 2: Run test to verify it fails**

`../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_minion_lifecycle.gd`
Expected: FAIL until Tasks 1-6 are complete (write this test last, after all production code is
in place, per this plan's own task ordering — treat "Run to verify it fails" as a sanity check by
temporarily breaking one assertion if all tasks are already done by the time you reach this one).

- [ ] **Step 3: Run test to verify it passes**

Same command. Expected: PASS.

- [ ] **Step 4: Run the full regression suite for this feature**

Re-run every test file this plan touched or that touches shared machinery it modified:
`test_turn_manager.gd`, `test_initiative_tiebreak.gd`, `test_action_reel.gd`,
`test_main_phase_plan.gd`, `test_minion_library.gd`, `test_summoner_class.gd`,
`test_minion_lifecycle.gd`, plus `test_spawn_enemy_mid_combat.gd` and
`test_boss_phase_transition.gd` (both exercise `TurnManager`/mid-fight combatant addition — a
regression in the `_living()`/`insert_acting_this_round()` area could show up there even though
this plan didn't touch those specific tests). Confirm all green.

- [ ] **Step 5: Commit**

```bash
git add tests/test_minion_lifecycle.gd
git commit -m "test(minion): end-to-end lifecycle coverage — summon, 3-stage escalation, expiry, replacement"
```

---

## Self-review notes (for whoever executes this plan)

- Task 5's panel placement (`_build_minion_panel()`) uses the same x/y math as
  `_place_party_column()` (`combat.gd:598-606`: x=24.0, y starts at 80.0, +312.0+14.0 per row),
  placed one slot past the last PC panel — verify this doesn't visually collide with anything if
  the party is already at its 3-PC cap (worst case y = 80 + 3*326 = 1058; confirm this is still
  on-screen at the project's target resolution during the manual check in Task 5 Step 4).
- This plan does NOT implement: a second minion type, Ultimate variants tied to the active
  minion, or any UI beyond a bare `CombatantPanel` for the minion (no minion-specific menu, no
  player-facing rename of "minion" per the spec's own still-open naming question). All three are
  explicitly deferred to future ability-design/content sessions per the spec.
- The Flee and Visible-Initiative-Reels plans are both already merged; this plan builds on top of
  both (`_flee_button`/`_flee_tier` exist alongside the new `_summon_tier`; `roll_initiative_for`
  is a genuinely new addition this plan introduces, used by minions only — the encounter-open
  roll from the Initiative plan still calls the unmodified `roll_initiative()` loop).
