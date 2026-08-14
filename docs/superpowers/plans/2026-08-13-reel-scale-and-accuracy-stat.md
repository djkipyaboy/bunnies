# Reel Scale-Up, Finesse Accuracy & Ability Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scale every `ActionReel` composition 5×, rework Luck's crit-face hook and add a new
Finesse accuracy hook (both as replace-in-place mechanics instead of additive), and give every
resource-costed ability reel a new, more reliable no-neutral composition.

**Architecture:** All changes are data/logic changes inside `combat/resources/action_reel.gd`
(face-composition constants + factory methods) and `combat/combatant.gd` (the two stat-conversion
hooks + every ability method that builds a reel), with mirrored preview-only changes in
`combat/main_phase_plan.gd`. No new classes, no scene/UI changes — this plan is pure combat-logic.

**Tech Stack:** Godot 4.6 GDScript, headless `SceneTree`-based tests run via the Godot console binary.

**Spec:** `docs/superpowers/specs/2026-08-13-accuracy-stat-and-post-combat-flow-design.md` (§1–§2 only;
§3/§4 are separate plans).

## Global Constraints

- Every `ActionReel` variant's face count scales 5× (`DEFAULT_COMPOSITION`, the new ability
  composition, `GAMBLE_COMPOSITION`, `make_rallying_cry()`, `make_item_use()`) — spec §2.
- Luck's crit-fail→crit-success conversion and Finesse's new fail→success conversion are both
  **replace** mechanics (swap an existing face's tier in place, total face count on the reel never
  changes) — NOT additive/appending. Both use the same pace: 1 face converted per 3 points, capped
  at however many convertible faces exist on that specific reel. Points beyond the cap are
  explicitly wasted — do not build overflow-routing (spec §2).
- The new ability composition (no NEUTRAL tier, 70% base hit rate) applies to Flurry, Rend, Select
  Fate, Sundering Strike, Quake Slam, Jinx the Odds, Snare Trap, Crippling Shot, Hex, Entangle, Mana
  Surge, Rampage, Collateral Damage, Big Bang, and Earthquake. It explicitly does NOT apply to
  Heft (a different, already-shipped, stronger mechanic), Rallying Cry, or item-use reels (spec §2).
- Round-up-damage/healing convention (`[[round-up-damage-healing]]`) is not implicated by this plan
  — no new floating-point-to-int rounding is introduced here.
- Run the Godot binary from `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe` (one
  directory above the repo, per CLAUDE.md) with `--headless --path .` from the repo root
  (`C:\bunnies\bunnies-main\bunnies`) for every test in this plan.

---

## File Map

- **Modify:** `combat/resources/action_reel.gd` — scale `DEFAULT_COMPOSITION`/`GAMBLE_COMPOSITION`,
  replace `RIDER_COMPOSITION`/`make_rider_attack()` with a new `ABILITY_COMPOSITION`/
  `make_ability_attack()`, scale `make_rallying_cry()`/`make_item_use()`, rework `make_rend()`.
- **Modify:** `combat/combatant.gd` — rework `apply_luck()`, add `apply_finesse_accuracy()`, swap
  every ability method's reel-building call from `make_default()`/`make_rider_attack()` to
  `make_ability_attack()`.
- **Modify:** `combat/combat.gd`, `combat/enemy_library.gd`, `combat/resources/character_class.gd`
  — call `apply_finesse_accuracy()` alongside each existing `apply_luck()` call.
- **Modify:** `combat/main_phase_plan.gd` — mirror the same call swaps in `preview_reels()` only
  (preview must match commit behavior).
- **Modify (tests):** `tests/test_action_reel.gd`, `tests/test_rend_reel.gd`,
  `tests/test_gamble_reel.gd`, `tests/test_rallying_cry_reel.gd`, `tests/test_item_use_reel.gd`,
  `tests/test_luck_threshold.gd`.
- **Delete + replace (test):** `tests/test_rider_attack_reel.gd` → `tests/test_ability_attack_reel.gd`.
- **Create (test):** `tests/test_finesse_accuracy_threshold.gd`.

---

### Task 1: Scale `DEFAULT_COMPOSITION` to 50 faces

**Files:**
- Modify: `combat/resources/action_reel.gd:46-52` (`DEFAULT_COMPOSITION` const)
- Test: `tests/test_action_reel.gd`

**Interfaces:**
- Consumes: nothing new.
- Produces: `ActionReel.DEFAULT_COMPOSITION` now totals 50 faces (5 crit-fail / 10 fail / 10
  neutral / 20 success / 5 crit-success) — every later task that reads a default weapon reel's
  face counts (Tasks 3, 7, 8) depends on these exact numbers.

- [ ] **Step 1: Update the failing test first**

Replace `tests/test_action_reel.gd` in full:

```gdscript
extends SceneTree

# Headless test for ActionReel.make_default() face composition (DESIGN.md §4.4 success ladder).
# Scaled 5x (2026-08-13 accuracy-stat spec §2) so Luck/Finesse's per-point face conversions have
# real percentage granularity to work with. The reel is a physical 50-face strip — odds come from
# how many of each symbol sit on it, NOT hidden weights (protects "the reel IS the dice").
# Run: Godot_v4.6.3-stable_win64 --headless --path <proj> --script res://tests/test_action_reel.gd

var _failures: int = 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _count(reel: ActionReel, tier: ReelFace.ResultTier) -> int:
	var n: int = 0
	for f: ReelFace in reel.faces:
		if f.result_tier == tier:
			n += 1
	return n

func _initialize() -> void:
	var T := ReelFace.ResultTier
	var reel: ActionReel = ActionReel.make_default()

	_check(reel.faces.size() == 50, "default reel has 50 faces (got %d)" % reel.faces.size())

	_check(_count(reel, T.CRIT_FAILURE) == 5, "5 crit-failure symbols = 10%% (got %d)" % _count(reel, T.CRIT_FAILURE))
	_check(_count(reel, T.CRIT_SUCCESS) == 5, "5 crit-success symbols = 10%% (got %d)" % _count(reel, T.CRIT_SUCCESS))
	_check(_count(reel, T.SUCCESS) == 20, "20 success symbols = 40%% (got %d)" % _count(reel, T.SUCCESS))
	_check(_count(reel, T.FAILURE) == 10, "10 failure symbols = 20%% (got %d)" % _count(reel, T.FAILURE))
	_check(_count(reel, T.NEUTRAL) == 10, "10 neutral/utility symbols = 20%% (got %d)" % _count(reel, T.NEUTRAL))

	# Faces must be distinct objects so the resolver's chosen face maps to a unique strip index.
	var seen: Dictionary = {}
	for f: ReelFace in reel.faces:
		seen[f] = true
	_check(seen.size() == 50, "all 50 faces are distinct objects (got %d)" % seen.size())

	# Damaging tiers keep their multipliers; non-damaging tiers deal none.
	for f: ReelFace in reel.faces:
		match f.result_tier:
			T.SUCCESS:
				_check(is_equal_approx(f.multiplier, 1.0), "success multiplier 1.0")
			T.CRIT_SUCCESS:
				_check(is_equal_approx(f.multiplier, 2.0), "crit-success multiplier 2.0")

	print(("ACTION REEL TEST PASSED" if _failures == 0 else "ACTION REEL TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run it to confirm it fails against the current 10-face composition**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_action_reel.gd`
Expected: FAIL — `default reel has 50 faces (got 10)` and every count assertion mismatched.

- [ ] **Step 3: Scale `DEFAULT_COMPOSITION` in `combat/resources/action_reel.gd`**

Replace the existing `DEFAULT_COMPOSITION` const (lines 46-52) with:

```gdscript
## Builds a first-pass Action reel as a physical 50-face strip (scaled 5x from the original 10,
## 2026-08-13 accuracy-stat spec §2 — gives Luck/Finesse's per-point face conversions real
## percentage granularity without eliminating a tier entirely). Odds = how many of each symbol sit
## on the reel (the reel IS the dice — no hidden weights). Crits are rare (5 each → 10%):
##   5 crit-failure · 10 failure · 10 neutral/utility · 20 success · 5 crit-success.
## [b]Balance numbers are [ASSUMPTION] placeholders[/b] — tune by playtest, do not hard-balance.
## (Later, gear/talents edit this symbol mix; see DESIGN.md §4.4.)
const DEFAULT_COMPOSITION := [
	[ReelFace.ResultTier.CRIT_FAILURE, 0.0, 5],
	[ReelFace.ResultTier.FAILURE, 0.0, 10],
	[ReelFace.ResultTier.NEUTRAL, 0.0, 10],
	[ReelFace.ResultTier.SUCCESS, 1.0, 20],
	[ReelFace.ResultTier.CRIT_SUCCESS, 2.0, 5],
]
```

- [ ] **Step 4: Run the test again to confirm it passes**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_action_reel.gd`
Expected: PASS — `ACTION REEL TEST PASSED`

- [ ] **Step 5: Commit**

```bash
git add combat/resources/action_reel.gd tests/test_action_reel.gd
git commit -m "feat(combat): scale default weapon reel to 50 faces (5x)"
```

---

### Task 2: Replace `RIDER_COMPOSITION`/`make_rider_attack()` with `ABILITY_COMPOSITION`/`make_ability_attack()`

**Files:**
- Modify: `combat/resources/action_reel.gd:80-111` (delete `RIDER_COMPOSITION` + `make_rider_attack`,
  add `ABILITY_COMPOSITION` + `make_ability_attack`)
- Delete: `tests/test_rider_attack_reel.gd`
- Create: `tests/test_ability_attack_reel.gd`

**Interfaces:**
- Consumes: `ReelFace`, `DamageType` (unchanged).
- Produces: `ActionReel.make_ability_attack(type: DamageType, rider_id: StringName = &"",
  bonus_vs_cc: bool = false) -> ActionReel` — the factory every ability-added reel (Tasks 3, 9, 10)
  will call. 50 faces: 5 crit-fail / 10 fail / 0 neutral / 30 success / 5 crit-success (70% hit
  rate). `rider_id` (when non-empty) is attached to every SUCCESS/CRIT_SUCCESS face, same
  attachment rule `make_rider_attack()` used. This function fully replaces `make_rider_attack()`,
  which is deleted — no call sites should reference it after this task (Tasks 9/10 do the actual
  call-site swaps; this task only builds the new factory and proves it in isolation).

- [ ] **Step 1: Write the new test file (it will fail — the factory doesn't exist yet)**

Delete `tests/test_rider_attack_reel.gd` and create `tests/test_ability_attack_reel.gd`:

```gdscript
extends SceneTree

# Headless test: ActionReel.make_ability_attack() — the shared composition for every reel that
# exists because of a resource-costed ability (2026-08-13 accuracy-stat spec §2). Replaces the old
# RIDER_COMPOSITION/make_rider_attack(): removes the NEUTRAL tier entirely and lands hit rate at
# 70% (before any Finesse/Luck conversion), out of a 50-face strip: 5 crit-fail / 10 fail / 0
# neutral / 30 success / 5 crit-success.
# Run: "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_ability_attack_reel.gd

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
	var T := ReelFace.ResultTier
	var reel: ActionReel = ActionReel.make_ability_attack(null, &"sundered")

	_check(reel.is_weapon_attack, "make_ability_attack reel joins paylines (unlike Rend)")
	_check(reel.faces.size() == 50, "50-face strip (got %d)" % reel.faces.size())
	_check(_count(reel, T.CRIT_FAILURE) == 5, "5 crit-failure faces (got %d)" % _count(reel, T.CRIT_FAILURE))
	_check(_count(reel, T.FAILURE) == 10, "10 failure faces (got %d)" % _count(reel, T.FAILURE))
	_check(_count(reel, T.NEUTRAL) == 0, "zero neutral faces — the whole point of this composition")
	_check(_count(reel, T.SUCCESS) == 30, "30 success faces (got %d)" % _count(reel, T.SUCCESS))
	_check(_count(reel, T.CRIT_SUCCESS) == 5, "5 crit-success faces (got %d)" % _count(reel, T.CRIT_SUCCESS))

	var hit_count: int = 0
	for f: ReelFace in reel.faces:
		if f.result_tier == T.SUCCESS or f.result_tier == T.CRIT_SUCCESS:
			hit_count += 1
			_check(f.multiplier > 0.0, "hit face keeps real damage multiplier")
			_check(f.rider_effect_id == &"sundered", "hit face carries the requested rider")
	_check(hit_count == 35, "35 hit faces (30 success + 5 crit-success) = 70%% hit rate (got %d)" % hit_count)

	# No-rider variant: used by every plain reel-count-adding ability (Flurry, Rampage, etc.)
	var no_rider: ActionReel = ActionReel.make_ability_attack(null)
	var no_rider_hit: bool = no_rider.faces.all(func(f: ReelFace) -> bool:
		return f.rider_effect_id == &"" or (f.result_tier != T.SUCCESS and f.result_tier != T.CRIT_SUCCESS))
	_check(no_rider_hit, "no rider_id passed -> no face carries a rider")

	var cc_reel: ActionReel = ActionReel.make_ability_attack(null, &"weakened", true)
	_check(cc_reel.bonus_vs_cc, "bonus_vs_cc flag set when requested")
	var plain_reel: ActionReel = ActionReel.make_ability_attack(null, &"rooted")
	_check(not plain_reel.bonus_vs_cc, "bonus_vs_cc defaults false")

	print(("ABILITY ATTACK REEL TEST PASSED" if _failures == 0 else "ABILITY ATTACK REEL TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_ability_attack_reel.gd`
Expected: FAIL — `Invalid call. Nonexistent function 'make_ability_attack'` (or parse error).

- [ ] **Step 3: Replace `RIDER_COMPOSITION`/`make_rider_attack()` in `combat/resources/action_reel.gd`**

Delete lines 80-111 (the `RIDER_COMPOSITION` const doc comment + const + `make_rider_attack()`
doc comment + function) entirely, and replace with:

```gdscript
## The shared composition for every reel that exists because of a resource-costed ability — NOT
## the plain weapon-swing baseline (2026-08-13 accuracy-stat spec §2, replacing the old
## RIDER_COMPOSITION/make_rider_attack "called shot" concept). Removes the NEUTRAL tier entirely
## (player's own least-favorite thing about combat: spending a resource and landing on a
## no-damage utility result) and redistributes what used to be neutral into fail/success so the
## base hit rate lands at 70% (before Finesse/Luck conversion): 5 crit-failure · 10 failure ·
## 30 success · 5 crit-success, out of 50 faces. [ASSUMPTION] tune by playtest, same as
## DEFAULT_COMPOSITION.
const ABILITY_COMPOSITION := [
	[ReelFace.ResultTier.CRIT_FAILURE, 0.0, 5],
	[ReelFace.ResultTier.FAILURE, 0.0, 10],
	[ReelFace.ResultTier.SUCCESS, 1.0, 30],
	[ReelFace.ResultTier.CRIT_SUCCESS, 2.0, 5],
]

## Builds a real weapon-attack reel using ABILITY_COMPOSITION's more-reliable odds (see its comment)
## rather than DEFAULT_COMPOSITION — every reel that exists because of a resource-costed ability
## uses this, whether or not it carries a rider. When [param rider_id] is non-empty, it's attached
## to every SUCCESS/CRIT_SUCCESS face (the attack both hits AND applies its rider on a hit). Used by
## Flurry, Rend (via make_rend), Select Fate, Sundering Strike, Quake Slam, Jinx the Odds, Snare
## Trap, Hex, Entangle, Crippling Shot, Mana Surge, Rampage, Collateral Damage, Big Bang, and
## Earthquake (spec 2026-08-13 §2).
static func make_ability_attack(type: DamageType, rider_id: StringName = &"", bonus_vs_cc: bool = false) -> ActionReel:
	var reel: ActionReel = ActionReel.new()
	reel.damage_type = type
	reel.bonus_vs_cc = bonus_vs_cc
	for entry: Array in ABILITY_COMPOSITION:
		var tier: ReelFace.ResultTier = entry[0]
		var multiplier: float = entry[1]
		var count: int = entry[2]
		for i: int in range(count):
			var face: ReelFace = _make_face(tier, multiplier)
			if rider_id != &"" and (tier == ReelFace.ResultTier.SUCCESS or tier == ReelFace.ResultTier.CRIT_SUCCESS):
				face.rider_effect_id = rider_id
			reel.faces.append(face)
	reel.faces.shuffle()
	return reel
```

- [ ] **Step 4: Run the test again to confirm it passes**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_ability_attack_reel.gd`
Expected: PASS — `ABILITY ATTACK REEL TEST PASSED`

Note: `combat/combatant.gd` and `combat/main_phase_plan.gd` still call the now-deleted
`ActionReel.make_rider_attack()` at this point in the plan — that's expected and fixed in Tasks 9
and 10. The project will not compile cleanly again until those tasks land; this is acceptable
mid-plan since each task's own test targets only the file(s) it touches directly, and Godot's
per-script headless test runner doesn't require the whole project to parse cleanly to run one
script. Do not attempt to run the full test suite (or any test that transitively loads
`combatant.gd`) until Task 10 is complete.

- [ ] **Step 5: Commit**

```bash
git add combat/resources/action_reel.gd tests/test_ability_attack_reel.gd
git rm tests/test_rider_attack_reel.gd
git commit -m "feat(combat): replace RIDER_COMPOSITION with the 70%-hit ABILITY_COMPOSITION"
```

---

### Task 3: Rework `make_rend()` to derive from `ABILITY_COMPOSITION`

**Files:**
- Modify: `combat/resources/action_reel.gd:68-78` (`make_rend()`)
- Test: `tests/test_rend_reel.gd`, `tests/test_weapon_attack_reels.gd`

**Interfaces:**
- Consumes: `ActionReel.make_ability_attack(type)` (Task 2).
- Produces: `ActionReel.make_rend()` still returns a 50-face reel where every SUCCESS/CRIT_SUCCESS
  face has multiplier 0.0 and carries the `&"bleed"` rider, but now built on the 70%-hit-rate
  ability composition (35 hit faces) instead of the 50%-hit default composition (25 hit faces).

- [ ] **Step 1: Update `tests/test_rend_reel.gd`'s hit-face-count assertion**

In `tests/test_rend_reel.gd`, change:

```gdscript
	_check(hit_faces == 5, "rend has 5 hit faces (4 success + 1 crit, default spread; got %d)" % hit_faces)
```

to:

```gdscript
	_check(hit_faces == 35, "rend has 35 hit faces (30 success + 5 crit, ability-composition spread; got %d)" % hit_faces)
```

Also update the non-hit-face loop's implicit assumption: `make_rend()` no longer has a NEUTRAL
tier at all (it derives from `ABILITY_COMPOSITION`, which has no neutral), so the existing `else`
branch (checking every non-hit face has no rider) still passes unchanged — no other edit needed in
this file.

- [ ] **Step 2: Run it to confirm it fails against the still-unmodified `make_rend()`**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_rend_reel.gd`
Expected: FAIL — `rend has 35 hit faces ... got 25` (since `make_rend()` still derives from
`make_default()`'s 50-face/25-hit composition at this point).

- [ ] **Step 3: Rework `make_rend()` in `combat/resources/action_reel.gd`**

Replace the existing `make_rend()` (previously lines 68-78, now shifted by Task 2's edits — find
by its doc comment `## Builds the Warrior's "Rend" reel`):

```gdscript
## Builds the Warrior's "Rend" reel (spec §4A/§4B): derives from ABILITY_COMPOSITION (2026-08-13
## accuracy-stat spec §2 — Rend is a resource-costed ability that adds a reel, same as every other
## reel in that spec's scope), but its HIT faces (success / crit-success) deal NO direct weapon
## damage (multiplier 0) and instead carry a &"bleed" rider. So landing a hit on this reel applies
## a BLEED stack rather than swinging for damage.
static func make_rend(type: DamageType = null) -> ActionReel:
	var reel: ActionReel = make_ability_attack(type)
	reel.is_weapon_attack = false  # Rend hits apply BLEED (a debuff), not a weapon swing — out of paylines
	for face: ReelFace in reel.faces:
		if face.result_tier == ReelFace.ResultTier.SUCCESS or face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
			face.multiplier = 0.0
			face.rider_effect_id = &"bleed"
	return reel
```

- [ ] **Step 4: Run `test_rend_reel.gd` and `test_weapon_attack_reels.gd` to confirm both pass**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_rend_reel.gd`
Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_weapon_attack_reels.gd`
Expected: both PASS (`test_weapon_attack_reels.gd` only checks booleans, unaffected by the
composition swap, but re-run it as a cheap regression check since it directly calls `make_rend()`).

- [ ] **Step 5: Commit**

```bash
git add combat/resources/action_reel.gd tests/test_rend_reel.gd
git commit -m "feat(combat): rework make_rend to derive from ABILITY_COMPOSITION"
```

---

### Task 4: Scale `GAMBLE_COMPOSITION` to 100 faces

**Files:**
- Modify: `combat/resources/action_reel.gd` (`GAMBLE_COMPOSITION` const)
- Test: `tests/test_gamble_reel.gd`

**Interfaces:**
- Consumes: nothing new.
- Produces: `ActionReel.make_gamble()` now returns a 100-face reel (25 crit-fail / 10 success / 65
  crit-success) instead of 20 faces — same percentages, 5× the granularity.

- [ ] **Step 1: Update `tests/test_gamble_reel.gd`**

Replace the file in full:

```gdscript
extends SceneTree

## Chancer "Double or Nothing" (L9) wild gambler's reel (playtest 2026-07-04, player-specified exact
## distribution): ActionReel.make_gamble() and Combatant.gambled_reels(). Scaled 5x (2026-08-13
## accuracy-stat spec §2) — the reel is a physical 100-face strip — 25% crit-failure, 10% success,
## 65% crit-success, ZERO failure/neutral faces.
## Run: Godot_v4.6.3-stable_win64 --headless --path <proj> --script res://tests/test_gamble_reel.gd

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _count(reel: ActionReel, tier: ReelFace.ResultTier) -> int:
	var n: int = 0
	for f: ReelFace in reel.faces:
		if f.result_tier == tier:
			n += 1
	return n

func _init() -> void:
	var T := ReelFace.ResultTier
	var reel: ActionReel = ActionReel.make_gamble()

	_check(reel.faces.size() == 100, "gamble reel has 100 faces (got %d)" % reel.faces.size())
	_check(_count(reel, T.CRIT_FAILURE) == 25, "25 crit-failure faces = 25%% (got %d)" % _count(reel, T.CRIT_FAILURE))
	_check(_count(reel, T.SUCCESS) == 10, "10 success faces = 10%% (got %d)" % _count(reel, T.SUCCESS))
	_check(_count(reel, T.CRIT_SUCCESS) == 65, "65 crit-success faces = 65%% (got %d)" % _count(reel, T.CRIT_SUCCESS))
	_check(_count(reel, T.FAILURE) == 0, "zero plain-failure faces (all-or-nothing reel)")
	_check(_count(reel, T.NEUTRAL) == 0, "zero neutral faces (all-or-nothing reel)")

	for f: ReelFace in reel.faces:
		if f.result_tier == T.SUCCESS:
			_check(is_equal_approx(f.multiplier, 1.0), "success face keeps a real 1.0x multiplier")
		elif f.result_tier == T.CRIT_SUCCESS:
			_check(is_equal_approx(f.multiplier, 2.0), "crit-success face keeps a real 2.0x multiplier")

	var typed_reel: ActionReel = ActionReel.make_gamble(load("res://combat/resources/types/storm.tres"))
	_check(typed_reel.damage_type != null, "damage_type carries through")
	_check(typed_reel.is_weapon_attack, "gamble reel joins paylines (a real weapon-attack reel)")

	# gambled_reels(): converts weapon-attack reels to the gamble spread, passes utility reels through.
	var weapon_reel: ActionReel = ActionReel.make_default()
	var utility_reel: ActionReel = ActionReel.make_rallying_cry()
	var converted: Array[ActionReel] = Combatant.gambled_reels([weapon_reel, utility_reel])
	_check(converted.size() == 2, "gambled_reels preserves reel count")
	_check(converted[0].faces.size() == 100, "weapon-attack reel replaced with the 100-face gamble composition")
	_check(converted[1] == utility_reel, "non-weapon-attack (utility) reel passes through untouched, same instance")
	_check(weapon_reel.faces.size() == 50, "original weapon_reel is untouched (gambled_reels doesn't mutate the input)")

	quit()
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_gamble_reel.gd`
Expected: FAIL — `gamble reel has 100 faces (got 20)`.

- [ ] **Step 3: Scale `GAMBLE_COMPOSITION` in `combat/resources/action_reel.gd`**

Find the `GAMBLE_COMPOSITION` const (doc comment starts `## Chancer "Double or Nothing"`) and
replace it:

```gdscript
## Chancer "Double or Nothing" (L9) wild gambler's reel (playtest 2026-07-04, player-specified exact
## distribution): a genuine ALL-OR-NOTHING reel — no FAILURE or NEUTRAL faces at all. Scaled 5x
## (2026-08-13 accuracy-stat spec §2) to a 100-face strip (not 20) for consistency with every other
## reel variant's new face-count granularity, same percentages: 25 crit-failure (25%), 10 success
## (10%), 65 crit-success (65%). Used for BOTH the caster's existing weapon-attack reels (via
## Combatant.gambled_reels()) and the ability's own 2 bonus reels — a whole-spin effect, not a
## partial one, matching the ability's original "wild crit-biased" framing.
const GAMBLE_COMPOSITION := [
	[ReelFace.ResultTier.CRIT_FAILURE, 0.0, 25],
	[ReelFace.ResultTier.SUCCESS, 1.0, 10],
	[ReelFace.ResultTier.CRIT_SUCCESS, 2.0, 65],
]
```

(`make_gamble()` itself is unchanged — it already just loops over `GAMBLE_COMPOSITION`'s entries.)

- [ ] **Step 4: Run the test again to confirm it passes**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_gamble_reel.gd`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add combat/resources/action_reel.gd tests/test_gamble_reel.gd
git commit -m "feat(combat): scale gamble reel to 100 faces (5x)"
```

---

### Task 5: Scale `make_rallying_cry()` to 50 faces

**Files:**
- Modify: `combat/resources/action_reel.gd` (`make_rallying_cry()`)
- Test: `tests/test_rallying_cry_reel.gd`

**Interfaces:**
- Consumes: nothing new.
- Produces: `ActionReel.make_rallying_cry()` now returns a 50-face reel (10 crit-success + 40
  success, both 0-multiplier) instead of 10 faces.

- [ ] **Step 1: Update `tests/test_rallying_cry_reel.gd`**

Change lines 21-23 from:

```gdscript
	_check(reel.faces.size() == 10, "10 faces (got %d)" % reel.faces.size())
	_check(_count(reel, ReelFace.ResultTier.CRIT_SUCCESS) == 2, "2 crit-success faces (got %d)" % _count(reel, ReelFace.ResultTier.CRIT_SUCCESS))
	_check(_count(reel, ReelFace.ResultTier.SUCCESS) == 8, "8 success faces (got %d)" % _count(reel, ReelFace.ResultTier.SUCCESS))
```

to:

```gdscript
	_check(reel.faces.size() == 50, "50 faces (got %d)" % reel.faces.size())
	_check(_count(reel, ReelFace.ResultTier.CRIT_SUCCESS) == 10, "10 crit-success faces (got %d)" % _count(reel, ReelFace.ResultTier.CRIT_SUCCESS))
	_check(_count(reel, ReelFace.ResultTier.SUCCESS) == 40, "40 success faces (got %d)" % _count(reel, ReelFace.ResultTier.SUCCESS))
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_rallying_cry_reel.gd`
Expected: FAIL — `50 faces (got 10)`.

- [ ] **Step 3: Scale `make_rallying_cry()` in `combat/resources/action_reel.gd`**

Find `make_rallying_cry()` (doc comment starts `## Builds the Warden's "Rallying Cry" reel`) and
replace its body:

```gdscript
## Builds the Warden's "Rallying Cry" reel (spec 2026-06-29 §3): a no-damage UTILITY reel, scaled 5x
## (2026-08-13 accuracy-stat spec §2) to 10 crit-success + 40 success faces (no fail/neutral/crit-
## fail). Every face deals zero direct damage (multiplier 0) and carries NO rider — the orchestrator
## reads the landed tier post-spin and shields the party (SUCCESS → half-weapon, CRIT_SUCCESS →
## full-weapon). is_weapon_attack = false → it stays OUT of paylines, is never WILD-biased, and sits
## at the loadout tail.
static func make_rallying_cry(type: DamageType = null) -> ActionReel:
	var reel: ActionReel = ActionReel.new()
	reel.damage_type = type
	reel.is_weapon_attack = false
	reel.charges_meter = false  # the shield IS the payoff — don't also feed the Bonus Meter (playtest 2026-06-29)
	for i: int in range(10):
		reel.faces.append(_make_face(ReelFace.ResultTier.CRIT_SUCCESS, 0.0))
	for i: int in range(40):
		reel.faces.append(_make_face(ReelFace.ResultTier.SUCCESS, 0.0))
	reel.faces.shuffle()  # balance-neutral: only adjacency varies, tier counts fixed
	return reel
```

- [ ] **Step 4: Run the test again to confirm it passes**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_rallying_cry_reel.gd`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add combat/resources/action_reel.gd tests/test_rallying_cry_reel.gd
git commit -m "feat(combat): scale rallying cry reel to 50 faces (5x)"
```

---

### Task 6: Scale `make_item_use()` to 50 faces

**Files:**
- Modify: `combat/resources/action_reel.gd` (`make_item_use()`)
- Test: `tests/test_item_use_reel.gd`

**Interfaces:**
- Consumes: nothing new.
- Produces: `ActionReel.make_item_use()` now returns a 50-face reel (5 crit-success + 45 success)
  instead of 10 faces.

- [ ] **Step 1: Update `tests/test_item_use_reel.gd`**

Change lines 22-24 from:

```gdscript
	_check(reel.faces.size() == 10, "10 faces (got %d)" % reel.faces.size())
	_check(_count(reel, ReelFace.ResultTier.SUCCESS) == 9, "9 success faces (got %d)" % _count(reel, ReelFace.ResultTier.SUCCESS))
	_check(_count(reel, ReelFace.ResultTier.CRIT_SUCCESS) == 1, "1 crit-success face (got %d)" % _count(reel, ReelFace.ResultTier.CRIT_SUCCESS))
```

to:

```gdscript
	_check(reel.faces.size() == 50, "50 faces (got %d)" % reel.faces.size())
	_check(_count(reel, ReelFace.ResultTier.SUCCESS) == 45, "45 success faces (got %d)" % _count(reel, ReelFace.ResultTier.SUCCESS))
	_check(_count(reel, ReelFace.ResultTier.CRIT_SUCCESS) == 5, "5 crit-success faces (got %d)" % _count(reel, ReelFace.ResultTier.CRIT_SUCCESS))
```

And change line 45's `untyped.faces.size() == 10` to `untyped.faces.size() == 50`:

```gdscript
	_check(untyped.faces.size() == 50, "untyped reel still has 50 faces")
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_item_use_reel.gd`
Expected: FAIL — `50 faces (got 10)`.

- [ ] **Step 3: Scale `make_item_use()` in `combat/resources/action_reel.gd`**

Find `make_item_use()` (doc comment starts `## Builds the item-use reel`) and replace its body:

```gdscript
## Builds the item-use reel (2026-07-16 combat item-use targeting design §2): a no-damage utility
## reel with NO failure tiers at all — a potion should never simply fail. Scaled 5x (2026-08-13
## accuracy-stat spec §2) to 45 SUCCESS + 5 CRIT_SUCCESS (90%/10%). Every face has multiplier 0; the
## orchestrator reads the landed tier post-spin and applies the item's real effect (e.g. a heal,
## ×1.5 on crit) itself, same convention as make_rallying_cry(). is_weapon_attack = false (out of
## paylines); charges_meter = false (the item's effect IS the payoff — same reasoning already used
## for Rallying Cry).
static func make_item_use(type: DamageType = null) -> ActionReel:
	var reel: ActionReel = ActionReel.new()
	reel.damage_type = type
	reel.is_weapon_attack = false
	reel.charges_meter = false
	for i: int in range(5):
		reel.faces.append(_make_face(ReelFace.ResultTier.CRIT_SUCCESS, 0.0))
	for i: int in range(45):
		reel.faces.append(_make_face(ReelFace.ResultTier.SUCCESS, 0.0))
	reel.faces.shuffle()
	return reel
```

- [ ] **Step 4: Run the test again to confirm it passes**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_item_use_reel.gd`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add combat/resources/action_reel.gd tests/test_item_use_reel.gd
git commit -m "feat(combat): scale item-use reel to 50 faces (5x)"
```

---

### Task 7: Rework `apply_luck()` from additive to replace (crit-fail → crit-success)

**Files:**
- Modify: `combat/combatant.gd` (`apply_luck()`, around line 902)
- Test: `tests/test_luck_threshold.gd`

**Interfaces:**
- Consumes: `Combatant.effective_stats().luck`, `Combatant.LUCK_PER_CRIT_FACE` (unchanged, still 3),
  `ActionReel.make_default()` (Task 1, 50 faces with 5 crit-fail at baseline).
- Produces: `Combatant.apply_luck()` still mutates `weapon.reels` in place, still non-idempotent,
  but now CONVERTS existing crit-fail faces to crit-success (in place, `result_tier` +
  `multiplier` changed on the SAME face object) instead of appending new ones. Capped at however
  many crit-fail faces exist on that reel (5 at baseline → caps at Luck 15).

- [ ] **Step 1: Update `tests/test_luck_threshold.gd`**

Replace the file in full:

```gdscript
extends SceneTree

# Headless test: Luck's crit-face hook is a REPLACE mechanic (2026-08-13 accuracy-stat spec §2) —
# converts existing CRIT_FAILURE faces to CRIT_SUCCESS in place, not additive. Threshold pace
# unchanged (1 face per 3 Luck points), capped at however many crit-fail faces exist on the reel
# (5 at the default 50-face reel's baseline -> caps at Luck 15). Separately, Luck also grants extra
# scored payline lines via the extra_lines hook (spec §5.4, unaffected by this rework).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_luck_threshold.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _count(w: Weapon, tier: ReelFace.ResultTier) -> int:
	var n: int = 0
	for f: ReelFace in w.reels[0].faces:
		if f.result_tier == tier: n += 1
	return n

func _initialize() -> void:
	var T := ReelFace.ResultTier
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")

	# Below threshold (Luck 2, needs 3): no conversion.
	var w1: Weapon = Weapon.new(); w1.reels.append(ActionReel.make_default(slashing))
	var base_cf: int = _count(w1, T.CRIT_FAILURE)
	var base_cs: int = _count(w1, T.CRIT_SUCCESS)
	var c1: Combatant = Combatant.new(); c1.weapon = w1
	var s1: Stats = Stats.new(); s1.luck = 2
	c1.base_stats = s1
	c1.apply_luck()
	_check(_count(w1, T.CRIT_FAILURE) == base_cf, "Luck 2 (below threshold 3) converts 0 crit-fail faces")
	_check(_count(w1, T.CRIT_SUCCESS) == base_cs, "Luck 2 -> crit-success count unchanged")
	_check(w1.reels[0].faces.size() == 50, "Luck 2 -> total face count unchanged (replace, not additive)")

	# At Luck 7 -> floor(7/3) = 2 faces converted.
	var w2: Weapon = Weapon.new(); w2.reels.append(ActionReel.make_default(slashing))
	var base_cf2: int = _count(w2, T.CRIT_FAILURE)
	var base_cs2: int = _count(w2, T.CRIT_SUCCESS)
	var c2: Combatant = Combatant.new(); c2.weapon = w2
	var s2: Stats = Stats.new(); s2.luck = 7
	c2.base_stats = s2
	c2.apply_luck()
	_check(_count(w2, T.CRIT_FAILURE) == base_cf2 - 2, "Luck 7 -> 2 fewer crit-fail faces (got %d, base %d)" % [_count(w2, T.CRIT_FAILURE), base_cf2])
	_check(_count(w2, T.CRIT_SUCCESS) == base_cs2 + 2, "Luck 7 -> 2 more crit-success faces (got %d, base %d)" % [_count(w2, T.CRIT_SUCCESS), base_cs2])
	_check(w2.reels[0].faces.size() == 50, "Luck 7 -> total face count unchanged (replace, not additive)")

	# Cap: Luck 15 exactly converts all 5 baseline crit-fail faces (5/3 -> floor is 5, matching the
	# reel's actual crit-fail count of 5 at 3-per-face pace: floor(15/3) = 5).
	var w3: Weapon = Weapon.new(); w3.reels.append(ActionReel.make_default(slashing))
	var c3: Combatant = Combatant.new(); c3.weapon = w3
	var s3: Stats = Stats.new(); s3.luck = 15
	c3.base_stats = s3
	c3.apply_luck()
	_check(_count(w3, T.CRIT_FAILURE) == 0, "Luck 15 -> all 5 crit-fail faces converted (capped, got %d)" % _count(w3, T.CRIT_FAILURE))
	_check(_count(w3, T.CRIT_SUCCESS) == 10, "Luck 15 -> crit-success doubles from 5 to 10 (got %d)" % _count(w3, T.CRIT_SUCCESS))

	# Points beyond the cap are wasted, never negative/over-converted (player's explicit call, spec §2).
	var w4: Weapon = Weapon.new(); w4.reels.append(ActionReel.make_default(slashing))
	var c4: Combatant = Combatant.new(); c4.weapon = w4
	var s4: Stats = Stats.new(); s4.luck = 999
	c4.base_stats = s4
	c4.apply_luck()
	_check(_count(w4, T.CRIT_FAILURE) == 0, "Luck 999 -> still only 0 crit-fail faces (no over-conversion)")
	_check(_count(w4, T.CRIT_SUCCESS) == 10, "Luck 999 -> still only 10 crit-success faces (capped, not unbounded)")

	# Converted faces carry a real 2.0x multiplier, same as any other crit-success face.
	for f: ReelFace in w3.reels[0].faces:
		if f.result_tier == T.CRIT_SUCCESS:
			_check(is_equal_approx(f.multiplier, 2.0), "converted crit-success face has 2.0x multiplier")

	# Extra payline lines: Luck 4 -> floor(4/4) = 1 extra line; Luck 3 -> 0. Unaffected by this rework.
	var c5: Combatant = Combatant.new()
	var s5: Stats = Stats.new(); s5.luck = 4
	c5.base_stats = s5
	_check(c5.luck_extra_lines(3).size() == 1, "Luck 4 -> 1 extra payline line (got %d)" % c5.luck_extra_lines(3).size())

	var c6: Combatant = Combatant.new()
	var s6: Stats = Stats.new(); s6.luck = 3
	c6.base_stats = s6
	_check(c6.luck_extra_lines(3).size() == 0, "Luck 3 (below threshold 4) -> 0 extra lines")

	print(("LUCK THRESHOLD TEST PASSED" if _failures == 0 else "LUCK THRESHOLD TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run it to confirm it fails against the current additive `apply_luck()`**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_luck_threshold.gd`
Expected: FAIL — `Luck 7 -> 2 fewer crit-fail faces (got 5, base 5)` (additive doesn't touch
crit-fail count at all) and the total-face-count assertions (`w1.reels[0].faces.size() == 50` will
actually still PASS at Luck 2 since 0 get added either way, but `w2`'s will read 52 instead of 50
under the old additive code).

- [ ] **Step 3: Rework `apply_luck()` in `combat/combatant.gd`**

Replace the existing `apply_luck()` (find by its doc comment `## Edits this combatant's weapon
reels to add crit-success faces from its Luck`):

```gdscript
## Edits this combatant's weapon reels by converting existing CRIT_FAILURE faces to CRIT_SUCCESS
## from its Luck (the reel IS the dice — Luck raises crit odds by converting existing risk into
## reward, not by diluting the reel with new faces). REPLACE mechanic (2026-08-13 accuracy-stat
## spec §2, reworked from the original additive append): total face count on the reel never
## changes. Mutates this combatant's OWN weapon reels only (N-vs-M safe — each combatant has its
## own Weapon). Call ONCE at setup (after gear/apply_stats); NOT idempotent — each call converts up
## to [member LUCK_PER_CRIT_FACE]-per-point MORE faces on whatever's left, so do not re-apply.
## [ASSUMPTION] converts 1 crit-failure face to crit-success per LUCK_PER_CRIT_FACE points of Luck
## (threshold, not 1:1), capped at however many crit-failure faces exist on that specific reel —
## points beyond the cap are explicitly wasted (player's call, spec §2).
func apply_luck() -> void:
	if weapon == null:
		return
	var n: int = effective_stats().luck / LUCK_PER_CRIT_FACE
	if n <= 0:
		return
	for reel: ActionReel in weapon.reels:
		var converted: int = 0
		for face: ReelFace in reel.faces:
			if converted >= n:
				break
			if face.result_tier == ReelFace.ResultTier.CRIT_FAILURE:
				face.result_tier = ReelFace.ResultTier.CRIT_SUCCESS
				face.multiplier = 2.0
				converted += 1
		reel.faces.shuffle()
```

- [ ] **Step 4: Run the test again to confirm it passes**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_luck_threshold.gd`
Expected: PASS

- [ ] **Step 5: Run `test_stats.gd` as a regression check (it also exercises `apply_luck()`)**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_stats.gd`
Expected: PASS unmodified — its assertion is `new_crit == base_crit + 2` (Luck 7 → +2
crit-success faces), which holds under BOTH the old additive mechanism and the new replace
mechanism, since both increase the crit-success COUNT by the same `floor(luck/3)` amount. If it
fails for any other reason, stop and investigate before continuing — do not edit this test file as
part of this task; it should not need any changes.

- [ ] **Step 6: Commit**

```bash
git add combat/combatant.gd tests/test_luck_threshold.gd
git commit -m "feat(combat): rework apply_luck to a replace mechanic (crit-fail -> crit-success)"
```

---

### Task 8: Add `apply_finesse_accuracy()` (new Finesse hook, fail → success)

**Files:**
- Modify: `combat/combatant.gd` (new const + new method, near `apply_luck()`)
- Modify: `combat/combat.gd:332`, `combat/enemy_library.gd:82`,
  `combat/resources/character_class.gd:127` (call the new method alongside each existing
  `apply_luck()` call)
- Create: `tests/test_finesse_accuracy_threshold.gd`

**Interfaces:**
- Consumes: `Combatant.effective_stats().finesse`, `ActionReel.make_default()` (Task 1, 50 faces
  with 10 fail at baseline).
- Produces: `Combatant.apply_finesse_accuracy() -> void` — same shape as `apply_luck()`: converts
  existing FAILURE faces to SUCCESS in place, 1 per `FINESSE_PER_ACCURACY_FACE` (3) points, capped
  at however many fail faces exist on the reel (10 at baseline → caps at Finesse 30). Called at
  the same three setup call sites `apply_luck()` already is.

- [ ] **Step 1: Write the new test file (it will fail — the method doesn't exist yet)**

Create `tests/test_finesse_accuracy_threshold.gd`:

```gdscript
extends SceneTree

# Headless test: Finesse's new accuracy hook (2026-08-13 accuracy-stat spec §2) — converts existing
# FAILURE faces to SUCCESS in place, same replace-mechanic shape and 3-points-per-face pace as
# Luck's crit-fail->crit-success hook, but on the disjoint fail/success face pool. Capped at
# however many fail faces exist on the reel (10 at the default 50-face reel's baseline -> caps at
# Finesse 30). Finesse's existing initiative role (turn_manager.gd) is untouched by this.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_finesse_accuracy_threshold.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _count(w: Weapon, tier: ReelFace.ResultTier) -> int:
	var n: int = 0
	for f: ReelFace in w.reels[0].faces:
		if f.result_tier == tier: n += 1
	return n

func _initialize() -> void:
	var T := ReelFace.ResultTier
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")

	# Below threshold (Finesse 2, needs 3): no conversion.
	var w1: Weapon = Weapon.new(); w1.reels.append(ActionReel.make_default(slashing))
	var base_f: int = _count(w1, T.FAILURE)
	var base_s: int = _count(w1, T.SUCCESS)
	var c1: Combatant = Combatant.new(); c1.weapon = w1
	var s1: Stats = Stats.new(); s1.finesse = 2
	c1.base_stats = s1
	c1.apply_finesse_accuracy()
	_check(_count(w1, T.FAILURE) == base_f, "Finesse 2 (below threshold 3) converts 0 fail faces")
	_check(_count(w1, T.SUCCESS) == base_s, "Finesse 2 -> success count unchanged")
	_check(w1.reels[0].faces.size() == 50, "Finesse 2 -> total face count unchanged (replace, not additive)")

	# At Finesse 7 -> floor(7/3) = 2 faces converted.
	var w2: Weapon = Weapon.new(); w2.reels.append(ActionReel.make_default(slashing))
	var base_f2: int = _count(w2, T.FAILURE)
	var base_s2: int = _count(w2, T.SUCCESS)
	var c2: Combatant = Combatant.new(); c2.weapon = w2
	var s2: Stats = Stats.new(); s2.finesse = 7
	c2.base_stats = s2
	c2.apply_finesse_accuracy()
	_check(_count(w2, T.FAILURE) == base_f2 - 2, "Finesse 7 -> 2 fewer fail faces (got %d, base %d)" % [_count(w2, T.FAILURE), base_f2])
	_check(_count(w2, T.SUCCESS) == base_s2 + 2, "Finesse 7 -> 2 more success faces (got %d, base %d)" % [_count(w2, T.SUCCESS), base_s2])

	# Cap: Finesse 30 converts all 10 baseline fail faces (floor(30/3) = 10).
	var w3: Weapon = Weapon.new(); w3.reels.append(ActionReel.make_default(slashing))
	var c3: Combatant = Combatant.new(); c3.weapon = w3
	var s3: Stats = Stats.new(); s3.finesse = 30
	c3.base_stats = s3
	c3.apply_finesse_accuracy()
	_check(_count(w3, T.FAILURE) == 0, "Finesse 30 -> all 10 fail faces converted (capped, got %d)" % _count(w3, T.FAILURE))
	_check(_count(w3, T.SUCCESS) == 30, "Finesse 30 -> success rises from 20 to 30 (got %d)" % _count(w3, T.SUCCESS))

	# Points beyond the cap are wasted (player's explicit call, spec §2).
	var w4: Weapon = Weapon.new(); w4.reels.append(ActionReel.make_default(slashing))
	var c4: Combatant = Combatant.new(); c4.weapon = w4
	var s4: Stats = Stats.new(); s4.finesse = 999
	c4.base_stats = s4
	c4.apply_finesse_accuracy()
	_check(_count(w4, T.FAILURE) == 0, "Finesse 999 -> still only 0 fail faces (no over-conversion)")
	_check(_count(w4, T.SUCCESS) == 30, "Finesse 999 -> still only 30 success faces (capped, not unbounded)")

	# Crit-fail and crit-success are NEVER touched by this hook (disjoint face pool from Luck's hook).
	_check(_count(w4, T.CRIT_FAILURE) == 5, "Finesse never touches crit-fail count (still 5)")
	_check(_count(w4, T.CRIT_SUCCESS) == 5, "Finesse never touches crit-success count (still 5)")

	# Converted faces carry a real 1.0x multiplier, same as any other success face.
	for f: ReelFace in w3.reels[0].faces:
		if f.result_tier == T.SUCCESS:
			_check(is_equal_approx(f.multiplier, 1.0), "converted success face has 1.0x multiplier")

	print(("FINESSE ACCURACY THRESHOLD TEST PASSED" if _failures == 0 else "FINESSE ACCURACY THRESHOLD TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_finesse_accuracy_threshold.gd`
Expected: FAIL — `Invalid call. Nonexistent function 'apply_finesse_accuracy'`.

- [ ] **Step 3: Add the constant and method in `combat/combatant.gd`**

Add this constant immediately after the existing `LUCK_PER_CRIT_FACE` const (around line 30):

```gdscript
## Finesse -> accuracy: every FINESSE_PER_ACCURACY_FACE points converts 1 FAILURE face to SUCCESS on
## a weapon reel (threshold, not 1:1 — same replace-mechanic pace as LUCK_PER_CRIT_FACE, 2026-08-13
## accuracy-stat spec §2).
const FINESSE_PER_ACCURACY_FACE: int = 3
```

Add this method immediately after `apply_luck()`:

```gdscript
## Edits this combatant's weapon reels by converting existing FAILURE faces to SUCCESS from its
## Finesse (2026-08-13 accuracy-stat spec §2 — Finesse's second job alongside initiative). REPLACE
## mechanic, mirroring apply_luck()'s shape exactly but on the disjoint fail/success face pool
## (never touches crit-fail/crit-success). Mutates this combatant's OWN weapon reels only. Call
## ONCE at setup (same point as apply_luck()); NOT idempotent for the same reason.
## [ASSUMPTION] converts 1 failure face to success per FINESSE_PER_ACCURACY_FACE points of Finesse,
## capped at however many failure faces exist on that specific reel — points beyond the cap are
## explicitly wasted (player's call, spec §2).
func apply_finesse_accuracy() -> void:
	if weapon == null:
		return
	var n: int = effective_stats().finesse / FINESSE_PER_ACCURACY_FACE
	if n <= 0:
		return
	for reel: ActionReel in weapon.reels:
		var converted: int = 0
		for face: ReelFace in reel.faces:
			if converted >= n:
				break
			if face.result_tier == ReelFace.ResultTier.FAILURE:
				face.result_tier = ReelFace.ResultTier.SUCCESS
				face.multiplier = 1.0
				converted += 1
		reel.faces.shuffle()
```

- [ ] **Step 4: Run the new test to confirm it passes**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_finesse_accuracy_threshold.gd`
Expected: PASS

- [ ] **Step 5: Wire the call into every existing `apply_luck()` call site**

In `combat/combat.gd`, line 332, change:

```gdscript
	c.apply_luck()        # edit weapon reels: +1 crit-success face per Luck. ONCE here — not idempotent.
```

to:

```gdscript
	c.apply_luck()        # edit weapon reels: convert crit-fail -> crit-success per Luck. ONCE here — not idempotent.
	c.apply_finesse_accuracy()  # edit weapon reels: convert fail -> success per Finesse. ONCE here — not idempotent.
```

In `combat/enemy_library.gd`, line 82, change:

```gdscript
	c.apply_luck()    # luck 0 → no-op, kept for parity with ClassLibrary
```

to:

```gdscript
	c.apply_luck()    # luck 0 → no-op, kept for parity with ClassLibrary
	c.apply_finesse_accuracy()    # finesse 0 → no-op, kept for parity with ClassLibrary
```

In `combat/resources/character_class.gd`, line 127, change:

```gdscript
	c.apply_luck()    # edit weapon reels: +1 crit face per Luck. ONCE — not idempotent.
```

to:

```gdscript
	c.apply_luck()    # edit weapon reels: convert crit-fail -> crit-success per Luck. ONCE — not idempotent.
	c.apply_finesse_accuracy()    # edit weapon reels: convert fail -> success per Finesse. ONCE — not idempotent.
```

- [ ] **Step 6: Run `test_character_creation_screen.gd` as a regression check**

This test's own comments explicitly call out `apply_luck()`'s non-idempotency and the exact
`build_combatant()` sequence — it's the most likely place a double-apply bug would surface.

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_character_creation_screen.gd`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add combat/combatant.gd combat/combat.gd combat/enemy_library.gd combat/resources/character_class.gd tests/test_finesse_accuracy_threshold.gd
git commit -m "feat(combat): add Finesse accuracy hook (fail -> success conversion)"
```

---

### Task 9: Swap rider-effect ability call sites to `make_ability_attack()`

**Files:**
- Modify: `combat/combatant.gd` — `try_sundering_strike`, `try_quake_slam`, `try_jinx_the_odds`,
  `try_snare_trap`, `try_crippling_shot`, `try_hex`, `try_entangle`
- Modify: `combat/main_phase_plan.gd:291-303` (the matching preview lines)
- Test: `tests/test_sundering_strike.gd`, `tests/test_quake_slam.gd`, `tests/test_jinx_the_odds.gd`,
  `tests/test_snare_trap.gd`, `tests/test_crippling_shot.gd`, `tests/test_hex.gd`,
  `tests/test_entangle.gd`

**Interfaces:**
- Consumes: `ActionReel.make_ability_attack(type, rider_id, bonus_vs_cc)` (Task 2).
- Produces: no new interface — every rider-effect ability now builds its reel via
  `make_ability_attack()` instead of the deleted `make_rider_attack()`. This is the task that makes
  the project compile cleanly again (Task 2 deleted `make_rider_attack()`; these are its last
  remaining callers along with Task 10's).

- [ ] **Step 1: Swap the 7 call sites in `combat/combatant.gd`**

In `try_sundering_strike`, change:
```gdscript
	turn_reels.append(ActionReel.make_rider_attack(type, &"sundered"))
```
to:
```gdscript
	turn_reels.append(ActionReel.make_ability_attack(type, &"sundered"))
```

In `try_quake_slam`, change:
```gdscript
	var reel: ActionReel = ActionReel.make_rider_attack(type, &"slow")
```
to:
```gdscript
	var reel: ActionReel = ActionReel.make_ability_attack(type, &"slow")
```

In `try_jinx_the_odds`, change:
```gdscript
	turn_reels.append(ActionReel.make_rider_attack(type, &"jinxed"))
```
to:
```gdscript
	turn_reels.append(ActionReel.make_ability_attack(type, &"jinxed"))
```

In `try_snare_trap`, change:
```gdscript
	turn_reels.append(ActionReel.make_rider_attack(type, &"rooted"))
```
to:
```gdscript
	turn_reels.append(ActionReel.make_ability_attack(type, &"rooted"))
```

In `try_crippling_shot`, change:
```gdscript
	turn_reels.append(ActionReel.make_rider_attack(type, &"weakened", true))
```
to:
```gdscript
	turn_reels.append(ActionReel.make_ability_attack(type, &"weakened", true))
```

In `try_hex`, change:
```gdscript
	turn_reels.append(ActionReel.make_rider_attack(type, &"cursed"))
```
to:
```gdscript
	turn_reels.append(ActionReel.make_ability_attack(type, &"cursed"))
```

In `try_entangle`, change:
```gdscript
	turn_reels.append(ActionReel.make_rider_attack(type, &"rooted"))
```
to:
```gdscript
	turn_reels.append(ActionReel.make_ability_attack(type, &"rooted"))
```

(`try_entangle` and `try_snare_trap` have identical bodies except the surrounding doc comments —
double-check you're editing each function's own line, not the same line twice.)

- [ ] **Step 2: Swap the matching preview lines in `combat/main_phase_plan.gd:291-303`**

Change:
```gdscript
			&"sundering_strike":
				reels.append(ActionReel.make_rider_attack(combatant.weapon_type(), &"sundered"))
			&"quake_slam":
				reels.append(ActionReel.make_rider_attack(combatant.weapon_type(), &"slow"))
			&"jinx_the_odds":
				reels.append(ActionReel.make_rider_attack(combatant.weapon_type(), &"jinxed"))
			&"snare_trap":
				reels.append(ActionReel.make_rider_attack(combatant.weapon_type(), &"rooted"))
			&"crippling_shot":
				reels.append(ActionReel.make_rider_attack(combatant.weapon_type(), &"weakened", true))
			&"hex":
				reels.append(ActionReel.make_rider_attack(combatant.weapon_type(), &"cursed"))
			&"entangle":
				reels.append(ActionReel.make_rider_attack(combatant.weapon_type(), &"rooted"))
```
to:
```gdscript
			&"sundering_strike":
				reels.append(ActionReel.make_ability_attack(combatant.weapon_type(), &"sundered"))
			&"quake_slam":
				reels.append(ActionReel.make_ability_attack(combatant.weapon_type(), &"slow"))
			&"jinx_the_odds":
				reels.append(ActionReel.make_ability_attack(combatant.weapon_type(), &"jinxed"))
			&"snare_trap":
				reels.append(ActionReel.make_ability_attack(combatant.weapon_type(), &"rooted"))
			&"crippling_shot":
				reels.append(ActionReel.make_ability_attack(combatant.weapon_type(), &"weakened", true))
			&"hex":
				reels.append(ActionReel.make_ability_attack(combatant.weapon_type(), &"cursed"))
			&"entangle":
				reels.append(ActionReel.make_ability_attack(combatant.weapon_type(), &"rooted"))
```

- [ ] **Step 3: Run all 7 affected ability tests**

Run each of:
```
"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_sundering_strike.gd
"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_quake_slam.gd
"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_jinx_the_odds.gd
"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_snare_trap.gd
"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_crippling_shot.gd
"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_hex.gd
"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_entangle.gd
```
Expected: all PASS unmodified — none of these tests assert exact face-tier counts (verified by
grep before writing this plan), only rider attachment, damage>0, cooldowns, and reel counts, all
of which are unaffected by the composition swap. If any fails, read its specific assertion before
changing anything — do not assume the failure is spurious.

- [ ] **Step 4: Commit**

```bash
git add combat/combatant.gd combat/main_phase_plan.gd
git commit -m "feat(combat): swap rider-effect abilities to make_ability_attack"
```

---

### Task 10: Swap reel-count-adding ability call sites to `make_ability_attack()`

**Files:**
- Modify: `combat/combatant.gd` — `try_splice_reel` (Flurry), `apply_select_fate`,
  `apply_mana_surge`, `fire_rampage`, `fire_collateral`, `fire_big_bang`, `fire_earthquake`
- Modify: `combat/main_phase_plan.gd:281`, `:285`, `:309`, `:322`, `:326`
- Test: `tests/test_reel_splice.gd`, `tests/test_select_fate.gd`, `tests/test_mana_surge.gd`,
  `tests/test_rampage.gd`, `tests/test_collateral.gd`, `tests/test_big_bang.gd`,
  `tests/test_earthquake.gd`

**Interfaces:**
- Consumes: `ActionReel.make_ability_attack(type)` (Task 2, no-rider form — `rider_id` defaults to
  `&""`).
- Produces: no new interface — this is the last remaining set of `make_default()` calls at
  ability-specific (not plain-weapon-swing) call sites. After this task, `make_default()` is only
  ever called for an actual weapon-swing baseline reel (the initial loadout) or by
  `Combatant.gambled_reels()`/similar generic helpers — never by an ability.

- [ ] **Step 1: Swap the 7 call sites in `combat/combatant.gd`**

In `try_splice_reel` (Flurry), change:
```gdscript
	var reel: ActionReel = ActionReel.make_default(type)
```
to:
```gdscript
	var reel: ActionReel = ActionReel.make_ability_attack(type)
```

In `apply_select_fate`, change:
```gdscript
	var extra: ActionReel = ActionReel.make_default(chosen_type)
```
to:
```gdscript
	var extra: ActionReel = ActionReel.make_ability_attack(chosen_type)
```

In `apply_mana_surge`, change:
```gdscript
	for i: int in range(2):
		if turn_reels.size() < reel_cap:
			turn_reels.append(ActionReel.make_default(type))
```
to:
```gdscript
	for i: int in range(2):
		if turn_reels.size() < reel_cap:
			turn_reels.append(ActionReel.make_ability_attack(type))
```

In `fire_rampage`, change:
```gdscript
	var extra_reel: ActionReel = ActionReel.make_default(extra_reel_type)
```
to:
```gdscript
	var extra_reel: ActionReel = ActionReel.make_ability_attack(extra_reel_type)
```

In `fire_collateral`, change:
```gdscript
	turn_reels.append(ActionReel.make_default(extra_reel_type))  # +1 weapon-attack reel for the Collateral turn
```
to:
```gdscript
	turn_reels.append(ActionReel.make_ability_attack(extra_reel_type))  # +1 weapon-attack reel for the Collateral turn
```

In `fire_big_bang`, change:
```gdscript
	while turn_reels.size() < target_reels:
		turn_reels.append(ActionReel.make_default(extra_reel_type))  # top up to the Big Bang reel count
```
to:
```gdscript
	while turn_reels.size() < target_reels:
		turn_reels.append(ActionReel.make_ability_attack(extra_reel_type))  # top up to the Big Bang reel count
```

In `fire_earthquake`, change:
```gdscript
	_insert_weapon_attack_reel(ActionReel.make_default(extra_reel_type))  # 3 → 4 weapon-attack reels
```
to:
```gdscript
	_insert_weapon_attack_reel(ActionReel.make_ability_attack(extra_reel_type))  # 3 → 4 weapon-attack reels
```

- [ ] **Step 2: Swap the matching preview lines in `combat/main_phase_plan.gd`**

Line 281 (Flurry preview), change:
```gdscript
			&"flurry":
				reels.append(ActionReel.make_default(combatant.weapon_type()))
```
to:
```gdscript
			&"flurry":
				reels.append(ActionReel.make_ability_attack(combatant.weapon_type()))
```

Line 285 (Select Fate preview), change:
```gdscript
			&"select_fate":
				reels.append(ActionReel.make_default(selected_fate_type))  # joins paylines (a weapon-attack reel)
```
to:
```gdscript
			&"select_fate":
				reels.append(ActionReel.make_ability_attack(selected_fate_type))  # joins paylines (a weapon-attack reel)
```

Line 309 (the `double_or_nothing`/`mana_surge` bonus-reel preview `maker` Callable), change:
```gdscript
		var maker: Callable = ActionReel.make_gamble if staged_extra_ability_id == &"double_or_nothing" else ActionReel.make_default
```
to:
```gdscript
		var maker: Callable = ActionReel.make_gamble if staged_extra_ability_id == &"double_or_nothing" else ActionReel.make_ability_attack
```

Line 322 (the Rampage/Collateral/Earthquake Ultimate preview), change:
```gdscript
			reels.insert(pos, ActionReel.make_default(combatant.weapon_type()))
```
to:
```gdscript
			reels.insert(pos, ActionReel.make_ability_attack(combatant.weapon_type()))
```

Line 326 (the Big Bang preview top-up), change:
```gdscript
			reels.append(ActionReel.make_default(combatant.weapon_type()))
```
to:
```gdscript
			reels.append(ActionReel.make_ability_attack(combatant.weapon_type()))
```

(Line 322 and 326 both call `ActionReel.make_default(combatant.weapon_type())` with identical
syntax but in different `if` blocks a few lines apart — verify by the surrounding comment before
each (`# The reel-adding Ultimates preview...` for 322, `# The Big Bang tops the loadout up...`
for 326) that you're editing both occurrences, not the same one twice.)

- [ ] **Step 3: Run all 7 affected ability tests**

Run each of:
```
"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_reel_splice.gd
"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_select_fate.gd
"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_mana_surge.gd
"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_rampage.gd
"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_collateral.gd
"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_big_bang.gd
"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_earthquake.gd
```
Expected: all PASS unmodified — same reasoning as Task 9 Step 3 (verified by grep, none assert
exact face-tier counts).

- [ ] **Step 4: Run the FULL test suite as a final regression gate for this plan**

This is the first point where every script in the project should parse and run cleanly again
(Task 2 deleted `make_rider_attack()`; Tasks 9 and 10 together are its only callers). Run every
`.gd` file directly under `tests/` and confirm none regress. If the project has an existing
"run everything" script or convention, use it; otherwise iterate `tests/test_*.gd` individually.
Pay particular attention to any test not already re-run in Tasks 1-10 that touches combat (e.g.
`test_combat_loop.gd`, `test_ultimate_variants.gd`, `test_ability_cost.gd`,
`test_evasion_and_bonus_line.gd`, `test_jinxed_reels.gd`, `test_darkness_rampage.gd`,
`test_heft.gd`, `test_ultimate_sticky_wild.gd`, `test_payline_and_splash_damage_multiplier.gd`,
`test_payline_profile.gd`, `test_class_abilities_plan.gd`, `test_enemy_ai.gd`,
`test_enemy_ai_taunt.gd`, `test_chancer_class.gd`, `test_wildcard_gamble.gd`,
`test_double_or_nothing.gd`, `test_loaded_dice.gd`, `test_hunters_mark.gd`,
`test_riposte_charge_counter.gd`, `test_reresolve_reel.gd`) — none were identified during planning
as asserting exact reel-composition counts, but this step exists specifically to catch anything
missed.

- [ ] **Step 5: Commit**

```bash
git add combat/combatant.gd combat/main_phase_plan.gd
git commit -m "feat(combat): swap reel-count-adding abilities to make_ability_attack"
```

---

## Plan Self-Review

**Spec coverage:** §2's every requirement is covered — 5× scale (Tasks 1, 4, 5, 6), Luck replace
mechanic (Task 7), Finesse accuracy hook (Task 8), the new ability composition applied to every
named ability including the explicit `Heft`/Rallying-Cry/item-use exclusions (Tasks 2, 3, 9, 10).
§3 and §4 (post-combat recovery, defeat handling) are separate plans, correctly out of scope here.

**Placeholder scan:** no TBD/TODO; every step has real code or a real shell command.

**Type consistency:** `ActionReel.make_ability_attack(type: DamageType, rider_id: StringName = &"",
bonus_vs_cc: bool = false) -> ActionReel` (introduced Task 2) is called identically everywhere in
Tasks 3, 9, 10 — no drift in argument order or defaults. `Combatant.apply_finesse_accuracy() ->
void` (Task 8) mirrors `apply_luck()`'s existing signature (no args, mutates `weapon.reels`).
`FINESSE_PER_ACCURACY_FACE` is defined once (Task 8) and not redefined elsewhere.
