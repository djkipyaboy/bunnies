# Fishing Mini-Game (Claw-Machine Targeting + Manual-Stop Catch) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the placeholder `GatheringNode`-based "FishingSpot" (which currently runs the Foraging Shake-the-Bush flow as a known intermediate state) with a real Fishing catch: an arcade claw-machine targeting phase followed by a manual-stop multi-reel resolution.

**Architecture:** Three pure/headless-testable layers feed one view. `FishingReel`/`ReelFace.fishing_tier` are the data layer (a fourth `Reel` sibling). `FishingShadowGenerator` is pure shadow-layout math (mirrors `Wander`'s "caller supplies randomness" pattern for its deterministic core, plus a convenience wrapper that supplies real randomness). `FishingMinigame` is the pure resolution model — unlike every other `Reel` consumer in this codebase (which calls `spin()` for an instant result), it drives CONTINUOUS rotation via `advance(delta)` and captures whatever face is showing at the moment of `stop(col)`. `FishingSpot` (a new `Interactable`, mirrors `RandomEncounterNode`'s hand-off shape) triggers `FishingPanel` (the view, mirrors `RandomEncounterPanel`'s "clear and rebuild children per phase" convention), which owns hook movement (reusing `PCController.movement_velocity()`, the same pure calc the PC itself uses), shadow-hit detection, and the actual `PartyInventory`/`CraftingMaterial` grant.

**Tech Stack:** Godot 4.6, GDScript, headless `--script` tests run via `Godot_v4.6.3-stable_win64_console.exe` (lives one directory above the repo, at `C:\bunnies\bunnies-main\`).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-01-gathering-profession-minigames-design.md` §1, §3.
- All balance numbers ([ASSUMPTION] shadow count range, reel composition, hook speed, tick duration) are placeholders per CLAUDE.md §4 — implement exactly as specified below, do not "improve" them; they get tuned by playtest.
- **The 1-reel bonus rule (locked by the player during brainstorming, do not deviate):** a 1-reel fish has NO separate quantity-only bonus tier. A plain Success win on a 1-reel fish is a baseline catch only (`quantity_multiplier = 1`, `quality_tier = 0`). Only a Critical result on that single reel grants the full bonus (`quantity_multiplier = 2`, `quality_tier = 1`). The quantity-only bonus tier ("all positive, not all critical") only exists for 3- and 5-reel fish, where "some vs. all positive" is a meaningful distinction. See Task 3's `resolve()` implementation — it guards this with `total > 1`, and that guard must not be removed or "simplified" away.
- Follow this project's existing GDScript naming/typing conventions (PascalCase classes, snake_case files, static typing on vars/signatures) — CLAUDE.md §2.
- Every new test file is a `SceneTree`-script test using a `_check(cond, label)` helper printing `ok`/`FAIL` lines, run via `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_<name>.gd` from `C:\bunnies\bunnies-main\`.
- Test files that reference randomized production behavior (shadow placement, reel shuffling) must either supply their own deterministic inputs (rig reels with a hand-authored `.faces` array, not `.shuffle()`'d output; use the `forced_shadows`/`forced_reels`-style test seams this plan defines) or use the project's established "many trials, assert statistical coverage" technique — never assert on a single non-deterministic draw.

---

### Task 1: `ReelFace.fishing_tier` + `FishingReel`

**Files:**
- Modify: `combat/resources/reel_face.gd`
- Create: `combat/resources/fishing_reel.gd`
- Test: `tests/test_fishing_reel.gd`

**Interfaces:**
- Produces: `ReelFace.fishing_tier: StringName = &""` (new nullable field). `class_name FishingReel extends Reel` with `static func make_default(composition: Array) -> FishingReel`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_fishing_reel.gd`:

```gdscript
extends SceneTree

## FishingReel + ReelFace.fishing_tier: data layer for the Fishing mini-game (2026-08-01
## gathering-profession-minigames spec section 3).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var bare: ReelFace = ReelFace.new()
	_check(bare.fishing_tier == &"", "ReelFace.fishing_tier defaults to empty StringName")

	var composition: Array = [[&"fail", 4], [&"success", 4], [&"critical", 2]]
	var reel: FishingReel = FishingReel.make_default(composition)
	_check(reel.faces.size() == 10, "make_default builds a 10-face strip from the composition's counts")

	var counts: Dictionary = {&"fail": 0, &"success": 0, &"critical": 0}
	for face: ReelFace in reel.faces:
		counts[face.fishing_tier] = counts[face.fishing_tier] + 1
	_check(counts[&"fail"] == 4, "4 fail faces built")
	_check(counts[&"success"] == 4, "4 success faces built")
	_check(counts[&"critical"] == 2, "2 critical faces built")

	# A second call builds an INDEPENDENT reel (no shared state between rounds).
	var reel2: FishingReel = FishingReel.make_default(composition)
	reel.faces[0].fishing_tier = &"mutated_for_test"
	_check(reel2.faces[0].fishing_tier != &"mutated_for_test", "make_default's two calls build independent face objects, not shared references")

	print("ok FishingReel smoke test complete")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_fishing_reel.gd`
Expected: FAIL / parse error — `FishingReel` does not exist yet.

- [ ] **Step 3: Write the implementation**

In `combat/resources/reel_face.gd`, add after the existing `team_up_symbol` field (and its section comment):

```gdscript
# ---------------------------------------------------------------------------
# Fishing-reel field
# ---------------------------------------------------------------------------

## Which of the 3 Fishing tiers (Fail/Success/Critical) this face carries -- a FishingReel-only
## field, following this file's own "nullable fields serve multiple reel kinds" precedent
## (2026-08-01 gathering-profession-minigames spec section 3). Empty on every other reel's faces.
@export var fishing_tier: StringName = &""
```

Create `combat/resources/fishing_reel.gd`:

```gdscript
class_name FishingReel
extends Reel

## The Fishing mini-game's reel (2026-08-01 gathering-profession-minigames spec section 3) -- a
## fourth Reel sibling (InitiativeReel/ActionReel/TeamUpReel). Faces carry fishing_tier, not
## result_tier/team_up_symbol/digit.
##
## Deliberately adds NO spin()/_select_index() override, and nothing ever CALLS spin() on a
## FishingReel: FishingMinigame reads faces[] directly by index to drive its own
## continuous-rotation advance()/stop() mechanic -- a consumption pattern distinct from every other
## reel in this codebase, which all resolve instantly via spin().

## Builds a reel from [param composition], an Array of [tier: StringName, count: int] pairs.
static func make_default(composition: Array) -> FishingReel:
	var reel: FishingReel = FishingReel.new()
	for entry: Array in composition:
		var tier: StringName = entry[0]
		var count: int = entry[1]
		for i in range(count):
			var face: ReelFace = ReelFace.new()
			face.fishing_tier = tier
			reel.faces.append(face)
	reel.faces.shuffle()
	return reel
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2. Expected: every line prints `ok`.

- [ ] **Step 5: Commit**

```bash
git add combat/resources/reel_face.gd combat/resources/fishing_reel.gd tests/test_fishing_reel.gd
git commit -m "feat(combat): add ReelFace.fishing_tier and the FishingReel data layer"
```

---

### Task 2: `FishingShadowGenerator`

**Files:**
- Create: `world/fishing_shadow_generator.gd`
- Test: `tests/test_fishing_shadow_generator.gd`

**Interfaces:**
- Produces: `class_name FishingShadowGenerator extends RefCounted`, `const SIZE_BUCKETS: Array[StringName] = [&"small", &"medium", &"large"]`, `static func reel_count_for_bucket(bucket: StringName) -> int`, `static func make_shadow(bounds: Rect2, x_fraction: float, y_fraction: float, bucket_index: int) -> Dictionary` (returns `{"position": Vector2, "size_bucket": StringName, "radius": float}`), `static func generate(bounds: Rect2, min_count: int, max_count: int) -> Array[Dictionary]`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_fishing_shadow_generator.gd`:

```gdscript
extends SceneTree

## FishingShadowGenerator: pure shadow-layout math for the Fishing mini-game's targeting phase
## (2026-08-01 gathering-profession-minigames spec section 3). Mirrors Wander's "caller supplies
## randomness" pattern for the deterministic core (make_shadow); generate() is the thin wrapper
## that supplies real randf()/randi() calls.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	_check(FishingShadowGenerator.reel_count_for_bucket(&"small") == 1, "small bucket maps to 1 reel")
	_check(FishingShadowGenerator.reel_count_for_bucket(&"medium") == 3, "medium bucket maps to 3 reels")
	_check(FishingShadowGenerator.reel_count_for_bucket(&"large") == 5, "large bucket maps to 5 reels")

	var bounds := Rect2(0.0, 0.0, 200.0, 100.0)

	var small_shadow: Dictionary = FishingShadowGenerator.make_shadow(bounds, 0.0, 0.0, 0)
	_check(small_shadow["size_bucket"] == &"small", "bucket_index 0 maps to the small bucket")
	_check(bounds.has_point(small_shadow["position"]), "a shadow placed at fraction (0,0) still lands inside bounds (radius-inset)")

	var large_shadow: Dictionary = FishingShadowGenerator.make_shadow(bounds, 1.0, 1.0, 2)
	_check(large_shadow["size_bucket"] == &"large", "bucket_index 2 maps to the large bucket")
	_check(bounds.has_point(large_shadow["position"]), "a shadow placed at fraction (1,1) still lands inside bounds (radius-inset)")
	_check(large_shadow["radius"] > small_shadow["radius"], "a large-bucket shadow has a bigger radius than a small-bucket one")

	# generate() supplies real randomness -- prove over many calls that (a) every position stays
	# in bounds and (b) bucket variety actually appears (not always the same bucket).
	var seen_buckets: Dictionary = {}
	var any_out_of_bounds: bool = false
	for i in range(50):
		var shadows: Array[Dictionary] = FishingShadowGenerator.generate(bounds, 3, 6)
		if shadows.size() < 3 or shadows.size() > 6:
			any_out_of_bounds = true
		for shadow: Dictionary in shadows:
			seen_buckets[shadow["size_bucket"]] = true
			if not bounds.has_point(shadow["position"]):
				any_out_of_bounds = true
	_check(not any_out_of_bounds, "over 50 generate() calls, every shadow's count is within [3,6] and every position is in bounds")
	_check(seen_buckets.size() > 1, "over 50 generate() calls, more than one size bucket appears")

	print("ok FishingShadowGenerator smoke test complete")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_fishing_shadow_generator.gd`
Expected: FAIL / parse error — `FishingShadowGenerator` does not exist yet.

- [ ] **Step 3: Write the implementation**

Create `world/fishing_shadow_generator.gd`:

```gdscript
class_name FishingShadowGenerator
extends RefCounted

## Pure/static shadow-layout math for the Fishing mini-game's targeting phase (2026-08-01
## gathering-profession-minigames spec section 3). Mirrors Wander's "caller supplies randomness"
## pattern: make_shadow() is a pure function of explicit inputs; generate() is the thin wrapper
## that supplies real randomness for FishingPanel's real call sites.

const SIZE_BUCKETS: Array[StringName] = [&"small", &"medium", &"large"]

## [ASSUMPTION] reel-count-per-bucket mapping (spec section 3), tuned by playtest.
const REEL_COUNT_FOR_BUCKET: Dictionary = {&"small": 1, &"medium": 3, &"large": 5}

## [ASSUMPTION] radius-per-bucket (visual + hit-detection size), tuned by playtest.
const RADIUS_FOR_BUCKET: Dictionary = {&"small": 16.0, &"medium": 24.0, &"large": 32.0}

static func reel_count_for_bucket(bucket: StringName) -> int:
	return REEL_COUNT_FOR_BUCKET.get(bucket, 1)

## Returns one shadow's {"position": Vector2, "size_bucket": StringName, "radius": float}, placed
## within [param bounds] using the explicit [param x_fraction]/[param y_fraction] (each clamped to
## 0.0-1.0, caller-supplied randomness) and [param bucket_index] (caller-supplied index into
## SIZE_BUCKETS, clamped). The radius inset keeps the shadow's full circle inside bounds.
static func make_shadow(bounds: Rect2, x_fraction: float, y_fraction: float, bucket_index: int) -> Dictionary:
	var bucket: StringName = SIZE_BUCKETS[clampi(bucket_index, 0, SIZE_BUCKETS.size() - 1)]
	var radius: float = RADIUS_FOR_BUCKET[bucket]
	var usable_w: float = maxf(bounds.size.x - radius * 2.0, 0.0)
	var usable_h: float = maxf(bounds.size.y - radius * 2.0, 0.0)
	var position: Vector2 = bounds.position + Vector2(
		radius + clampf(x_fraction, 0.0, 1.0) * usable_w,
		radius + clampf(y_fraction, 0.0, 1.0) * usable_h)
	return {"position": position, "size_bucket": bucket, "radius": radius}

## Generates a fresh, freshly-randomized layout every call -- [ASSUMPTION] shadow count between
## [param min_count] and [param max_count] inclusive, tuned by playtest.
static func generate(bounds: Rect2, min_count: int, max_count: int) -> Array[Dictionary]:
	var count: int = randi_range(min_count, max_count)
	var shadows: Array[Dictionary] = []
	for i in range(count):
		shadows.append(make_shadow(bounds, randf(), randf(), randi() % SIZE_BUCKETS.size()))
	return shadows
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2. Expected: every line prints `ok`.

- [ ] **Step 5: Commit**

```bash
git add world/fishing_shadow_generator.gd tests/test_fishing_shadow_generator.gd
git commit -m "feat(world): add FishingShadowGenerator pure shadow-layout math"
```

---

### Task 3: `FishingMinigame` pure model

**Files:**
- Create: `world/fishing_minigame.gd`
- Test: `tests/test_fishing_minigame.gd`

**Interfaces:**
- Consumes: `FishingReel` (Task 1) — `.faces: Array[ReelFace]`. `ReelFace.fishing_tier` (Task 1).
- Produces: `class_name FishingMinigame extends RefCounted`, `_init(p_reels: Array[FishingReel])`, `const SECONDS_PER_TICK: float`, `func advance(delta: float) -> void`, `func current_face(col: int) -> ReelFace`, `func stop(col: int) -> ReelFace`, `func is_stopped(col: int) -> bool`, `func all_stopped() -> bool`, `func resolve() -> Dictionary` (returns `{"caught": bool, "quantity_multiplier": int, "quality_tier": int}`).

- [ ] **Step 1: Write the failing test**

Create `tests/test_fishing_minigame.gd`:

```gdscript
extends SceneTree

## FishingMinigame: pure model for the Fishing reel-stop mechanic (2026-08-01
## gathering-profession-minigames spec section 3). Unlike every other Reel consumer, nothing here
## calls spin() -- advance()/stop() drive continuous rotation and capture-on-stop instead. Tests
## build FishingReels with hand-authored, UNshuffled .faces arrays for full determinism.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

## Builds a FishingReel whose faces are exactly [param tiers], in order, un-shuffled.
func _reel(tiers: Array) -> FishingReel:
	var reel: FishingReel = FishingReel.new()
	for tier: StringName in tiers:
		var face: ReelFace = ReelFace.new()
		face.fishing_tier = tier
		reel.faces.append(face)
	return reel

func _init() -> void:
	# --- Mechanics: advance()/stop()/all_stopped() ---
	var reel: FishingReel = _reel([&"fail", &"success", &"critical"])
	var one: Array[FishingReel] = [reel]
	var m: FishingMinigame = FishingMinigame.new(one)
	_check(m.current_face(0).fishing_tier == &"fail", "starts on index 0's face")
	_check(not m.is_stopped(0), "starts unstopped")

	m.advance(FishingMinigame.SECONDS_PER_TICK * 1.0)
	_check(m.current_face(0).fishing_tier == &"success", "advancing one full tick moves to the next face")
	m.advance(FishingMinigame.SECONDS_PER_TICK * 2.0)
	_check(m.current_face(0).fishing_tier == &"fail", "advancing wraps around the strip (index 1 + 2 ticks = index 0 on a 3-face strip)")

	var frozen: ReelFace = m.stop(0)
	_check(frozen.fishing_tier == &"fail", "stop() returns whatever face is showing at that instant")
	_check(m.is_stopped(0), "stop() marks the reel stopped")
	m.advance(FishingMinigame.SECONDS_PER_TICK * 5.0)
	_check(m.current_face(0) == frozen, "advance() no longer changes a stopped reel's face")
	_check(m.stop(0) == frozen, "calling stop() again on an already-stopped reel returns the same frozen face")
	_check(m.all_stopped(), "all_stopped() is true once every reel is stopped")

	var two: Array[FishingReel] = [_reel([&"fail"]), _reel([&"success"])]
	var m2: FishingMinigame = FishingMinigame.new(two)
	_check(not m2.all_stopped(), "all_stopped() is false while any reel is still spinning")
	m2.stop(0)
	_check(not m2.all_stopped(), "all_stopped() is false while even one reel is still spinning")
	m2.stop(1)
	_check(m2.all_stopped(), "all_stopped() becomes true once the last reel stops")

	# --- Resolution ladder: 1-reel (locked rule: no quantity-only tier at 1 reel) ---
	var one_fail: FishingMinigame = FishingMinigame.new([_reel([&"fail"])] as Array[FishingReel])
	one_fail.stop(0)
	var r1: Dictionary = one_fail.resolve()
	_check(r1["caught"] == false, "1-reel Fail: not caught")

	var one_success: FishingMinigame = FishingMinigame.new([_reel([&"success"])] as Array[FishingReel])
	one_success.stop(0)
	var r2: Dictionary = one_success.resolve()
	_check(r2["caught"] == true and r2["quantity_multiplier"] == 1 and r2["quality_tier"] == 0,
		"1-reel Success: caught, NO bonus (locked rule -- plain win is baseline only, got %s" % str(r2))

	var one_crit: FishingMinigame = FishingMinigame.new([_reel([&"critical"])] as Array[FishingReel])
	one_crit.stop(0)
	var r3: Dictionary = one_crit.resolve()
	_check(r3["caught"] == true and r3["quantity_multiplier"] == 2 and r3["quality_tier"] == 1,
		"1-reel Critical: caught, quantity+quality bonus, got %s" % str(r3))

	# --- Resolution ladder: 3-reel (threshold 2 of 3) ---
	var three_below: Array[FishingReel] = [_reel([&"success"]), _reel([&"fail"]), _reel([&"fail"])]
	var m3a: FishingMinigame = FishingMinigame.new(three_below)
	m3a.stop(0); m3a.stop(1); m3a.stop(2)
	_check(m3a.resolve()["caught"] == false, "3-reel with 1 of 3 positive: below threshold, not caught")

	var three_baseline: Array[FishingReel] = [_reel([&"success"]), _reel([&"success"]), _reel([&"fail"])]
	var m3b: FishingMinigame = FishingMinigame.new(three_baseline)
	m3b.stop(0); m3b.stop(1); m3b.stop(2)
	var r3b: Dictionary = m3b.resolve()
	_check(r3b["caught"] == true and r3b["quantity_multiplier"] == 1 and r3b["quality_tier"] == 0,
		"3-reel with exactly 2 of 3 positive: caught, baseline only (not all-positive), got %s" % str(r3b))

	var three_all_mixed: Array[FishingReel] = [_reel([&"success"]), _reel([&"success"]), _reel([&"critical"])]
	var m3c: FishingMinigame = FishingMinigame.new(three_all_mixed)
	m3c.stop(0); m3c.stop(1); m3c.stop(2)
	var r3c: Dictionary = m3c.resolve()
	_check(r3c["caught"] == true and r3c["quantity_multiplier"] == 2 and r3c["quality_tier"] == 0,
		"3-reel with 3 of 3 positive, mixed (not all critical): quantity bonus only, got %s" % str(r3c))

	var three_all_crit: Array[FishingReel] = [_reel([&"critical"]), _reel([&"critical"]), _reel([&"critical"])]
	var m3d: FishingMinigame = FishingMinigame.new(three_all_crit)
	m3d.stop(0); m3d.stop(1); m3d.stop(2)
	var r3d: Dictionary = m3d.resolve()
	_check(r3d["caught"] == true and r3d["quantity_multiplier"] == 2 and r3d["quality_tier"] == 1,
		"3-reel all Critical: quantity+quality bonus, got %s" % str(r3d))

	# --- Resolution ladder: 5-reel (threshold 3 of 5) ---
	var five_below: Array[FishingReel] = [_reel([&"success"]), _reel([&"success"]), _reel([&"fail"]), _reel([&"fail"]), _reel([&"fail"])]
	var m5a: FishingMinigame = FishingMinigame.new(five_below)
	for i in range(5): m5a.stop(i)
	_check(m5a.resolve()["caught"] == false, "5-reel with 2 of 5 positive: below threshold, not caught")

	var five_baseline: Array[FishingReel] = [_reel([&"success"]), _reel([&"success"]), _reel([&"success"]), _reel([&"fail"]), _reel([&"fail"])]
	var m5b: FishingMinigame = FishingMinigame.new(five_baseline)
	for i in range(5): m5b.stop(i)
	var r5b: Dictionary = m5b.resolve()
	_check(r5b["caught"] == true and r5b["quantity_multiplier"] == 1 and r5b["quality_tier"] == 0,
		"5-reel with exactly 3 of 5 positive: caught, baseline only, got %s" % str(r5b))

	var five_all_mixed: Array[FishingReel] = [_reel([&"success"]), _reel([&"success"]), _reel([&"success"]), _reel([&"success"]), _reel([&"critical"])]
	var m5c: FishingMinigame = FishingMinigame.new(five_all_mixed)
	for i in range(5): m5c.stop(i)
	var r5c: Dictionary = m5c.resolve()
	_check(r5c["caught"] == true and r5c["quantity_multiplier"] == 2 and r5c["quality_tier"] == 0,
		"5-reel with 5 of 5 positive, mixed: quantity bonus only, got %s" % str(r5c))

	var five_all_crit: Array[FishingReel] = [_reel([&"critical"]), _reel([&"critical"]), _reel([&"critical"]), _reel([&"critical"]), _reel([&"critical"])]
	var m5d: FishingMinigame = FishingMinigame.new(five_all_crit)
	for i in range(5): m5d.stop(i)
	var r5d: Dictionary = m5d.resolve()
	_check(r5d["caught"] == true and r5d["quantity_multiplier"] == 2 and r5d["quality_tier"] == 1,
		"5-reel all Critical: quantity+quality bonus, got %s" % str(r5d))

	print("ok FishingMinigame smoke test complete")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_fishing_minigame.gd`
Expected: FAIL / parse error — `FishingMinigame` does not exist yet.

- [ ] **Step 3: Write the implementation**

Create `world/fishing_minigame.gd`:

```gdscript
class_name FishingMinigame
extends RefCounted

## Pure model for the Fishing reel-stop mini-game (2026-08-01 gathering-profession-minigames spec
## section 3) -- N FishingReels (N=1/3/5) rotate continuously; the player stops each individually,
## in any order. Unlike every other Reel consumer in this codebase (which calls spin() for an
## instant result), this drives CONTINUOUS rotation via advance(delta) and captures whatever face
## is showing at the moment of stop(col). Mirrors TeamUpMinigame/ForagingMinigame's shape: no
## Node/UI state, fully headless-testable; FishingPanel is the view.

## [ASSUMPTION] seconds per face-advance tick, tuned at playtest (spec section 3 -- rotation speed
## explicitly deferred to playtest, not designed now).
const SECONDS_PER_TICK: float = 0.15

var reels: Array[FishingReel] = []
var _current_indices: Array[int] = []
var _stopped: Array[bool] = []
var _elapsed: Array[float] = []

func _init(p_reels: Array[FishingReel]) -> void:
	reels = p_reels
	for i in range(reels.size()):
		_current_indices.append(0)
		_stopped.append(false)
		_elapsed.append(0.0)

## Advances every UN-STOPPED reel's displayed index by however many whole ticks [param delta]
## covers (leftover fractional time carries over per-reel, so a slow/irregular caller doesn't lose
## ticks). No-op on any reel already stopped.
func advance(delta: float) -> void:
	for i in range(reels.size()):
		if _stopped[i]:
			continue
		_elapsed[i] += delta
		while _elapsed[i] >= SECONDS_PER_TICK:
			_elapsed[i] -= SECONDS_PER_TICK
			_current_indices[i] = (_current_indices[i] + 1) % reels[i].faces.size()

## The face currently displayed on reel [param col] (whether still rotating or already stopped).
func current_face(col: int) -> ReelFace:
	return reels[col].faces[_current_indices[col]]

func is_stopped(col: int) -> bool:
	return _stopped[col]

## Freezes reel [param col] at whatever face is CURRENTLY showing and returns it. Calling this
## again on an already-stopped reel is a no-op that returns the same frozen face.
func stop(col: int) -> ReelFace:
	_stopped[col] = true
	return current_face(col)

## True once every reel has been stopped.
func all_stopped() -> bool:
	return not _stopped.has(false)

## Resolution ladder (spec section 3): catch/no-catch + quantity/quality bonus, once all_stopped().
## Meaningless before that -- callers must check all_stopped() first.
##
## LOCKED RULE (do not remove the `total > 1` guard): a 1-reel fish has no separate
## quantity-only bonus tier -- "all positive, not all critical" is indistinguishable from a plain
## win when there's only one reel, so that tier must never fire at total == 1. Only an all-Critical
## result grants a bonus on a 1-reel fish.
func resolve() -> Dictionary:
	var total: int = reels.size()
	var positive_count: int = 0
	var critical_count: int = 0
	for i in range(total):
		var tier: StringName = current_face(i).fishing_tier
		if tier == &"success" or tier == &"critical":
			positive_count += 1
		if tier == &"critical":
			critical_count += 1

	var threshold: int = _catch_threshold(total)
	var caught: bool = positive_count >= threshold
	var quantity_multiplier: int = 1
	var quality_tier: int = 0
	if caught:
		if critical_count == total:
			quantity_multiplier = 2
			quality_tier = 1
		elif total > 1 and positive_count == total:
			quantity_multiplier = 2
	return {"caught": caught, "quantity_multiplier": quantity_multiplier, "quality_tier": quality_tier}

## [ASSUMPTION] catch thresholds (spec section 3): 1-reel needs its own win, 3-reel needs 2 of 3,
## 5-reel needs 3 of 5. Every real fish is one of these three sizes.
static func _catch_threshold(total: int) -> int:
	match total:
		1: return 1
		3: return 2
		5: return 3
		_: return total
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2. Expected: every line prints `ok`.

- [ ] **Step 5: Commit**

```bash
git add world/fishing_minigame.gd tests/test_fishing_minigame.gd
git commit -m "feat(world): add FishingMinigame pure model with the locked resolution ladder"
```

---

### Task 4: `FishingSpot` node

**Files:**
- Create: `world/fishing_spot.gd`
- Test: `tests/test_fishing_spot.gd`

**Interfaces:**
- Produces: `class_name FishingSpot extends Interactable` with per-bucket `@export` fields (`small_material_type`/`small_material_display_name`/`small_quantity`, and the `medium_`/`large_` equivalents), `signal fishing_requested(bucket_configs: Dictionary)`, `func interact() -> void`. `bucket_configs` shape: `{&"small": {"material_type": StringName, "material_display_name": String, "quantity": int}, &"medium": {...}, &"large": {...}}`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_fishing_spot.gd`:

```gdscript
extends SceneTree

## FishingSpot: a stationary, contact-triggered overworld fishing node (2026-08-01
## gathering-profession-minigames spec section 3). HANDS OFF to the driving scene's FishingPanel on
## interact() (mirrors GatheringNode/RandomEncounterNode's shape) -- marks itself defeated in
## CombatHandoff and frees itself, carrying one material config PER shadow-size bucket since real
## fish content doesn't exist yet.

var _combat_handoff: Node
var _node: FishingSpot
var _requested: Array = []   # [Dictionary] -- the bucket_configs payload from each emit
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	_node = FishingSpot.new()
	_node.name = "TestFishingSpot"
	_node.small_material_type = &"fish_small"
	_node.small_material_display_name = "Minnow"
	_node.small_quantity = 1
	_node.medium_material_type = &"fish_medium"
	_node.medium_material_display_name = "Freshwater Fish"
	_node.medium_quantity = 1
	_node.large_material_type = &"fish_large"
	_node.large_material_display_name = "Prize Bass"
	_node.large_quantity = 1
	root.add_child(_node)

	_node.fishing_requested.connect(func(bucket_configs: Dictionary) -> void:
		_requested.append(bucket_configs))

	_check(_node.auto_trigger == true, "FishingSpot sets auto_trigger true on construction")

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_combat_handoff = get_root().get_node("CombatHandoff")
		_combat_handoff.defeated_encounter_ids = [] as Array[StringName]

		_node.interact()

		_check(_requested.size() == 1, "interact() emits fishing_requested exactly once")
		var configs: Dictionary = _requested[0]
		_check(configs[&"small"] == {"material_type": &"fish_small", "material_display_name": "Minnow", "quantity": 1},
			"the small bucket's config matches the node's authored fields, got %s" % str(configs[&"small"]))
		_check(configs[&"medium"] == {"material_type": &"fish_medium", "material_display_name": "Freshwater Fish", "quantity": 1},
			"the medium bucket's config matches the node's authored fields, got %s" % str(configs[&"medium"]))
		_check(configs[&"large"] == {"material_type": &"fish_large", "material_display_name": "Prize Bass", "quantity": 1},
			"the large bucket's config matches the node's authored fields, got %s" % str(configs[&"large"]))
		_check(_node.is_queued_for_deletion(), "interact() queues the node for deletion")
		_check(_combat_handoff.is_defeated(&"TestFishingSpot"), "interact() marks its own node name defeated in CombatHandoff")

		_combat_handoff.defeated_encounter_ids = [] as Array[StringName]

	if _frames >= 3:
		print("ok FishingSpot smoke test complete")
		return true
	return false
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_fishing_spot.gd`
Expected: FAIL / parse error — `FishingSpot` does not exist yet.

- [ ] **Step 3: Write the implementation**

Create `world/fishing_spot.gd`:

```gdscript
class_name FishingSpot
extends Interactable

## A stationary, contact-triggered overworld fishing node (2026-08-01
## gathering-profession-minigames spec section 3) -- a claw-machine-style catch, distinct from
## GatheringNode's touch-and-grant flow. HANDS OFF to the driving scene's FishingPanel on
## interact() (mirrors GatheringNode/RandomEncounterNode's shape) -- marks itself defeated and
## frees itself, since the catch attempt has started regardless of what the player does in the
## panel afterward. Carries one material/quantity config PER shadow-size bucket (small/medium/
## large) since real fish content doesn't exist yet -- placeholder authoring fields, not a catalog.

@export var small_material_type: StringName = &""
@export var small_material_display_name: String = ""
@export var small_quantity: int = 1

@export var medium_material_type: StringName = &""
@export var medium_material_display_name: String = ""
@export var medium_quantity: int = 1

@export var large_material_type: StringName = &""
@export var large_material_display_name: String = ""
@export var large_quantity: int = 1

## Emitted right before this node frees itself; the driving scene opens its FishingPanel with this
## payload. Keyed by size bucket, each value {"material_type", "material_display_name", "quantity"}.
signal fishing_requested(bucket_configs: Dictionary)

func _init() -> void:
	auto_trigger = true
	prompt_text = "Fish"

	var visual := ColorRect.new()
	visual.color = Color(0.2, 0.4, 0.8)
	visual.position = Vector2(-8, -8)
	visual.size = Vector2(16, 16)
	add_child(visual)

func interact() -> void:
	_handoff().mark_defeated(StringName(name))
	fishing_requested.emit(_build_bucket_configs())
	queue_free()

func _build_bucket_configs() -> Dictionary:
	return {
		&"small": {"material_type": small_material_type, "material_display_name": small_material_display_name, "quantity": small_quantity},
		&"medium": {"material_type": medium_material_type, "material_display_name": medium_material_display_name, "quantity": medium_quantity},
		&"large": {"material_type": large_material_type, "material_display_name": large_material_display_name, "quantity": large_quantity},
	}

## Fetches the CombatHandoff autoload by path -- same rationale as every other _handoff() in this
## project (bare identifier fails under headless --script test runs).
func _handoff() -> Node:
	return get_node("/root/CombatHandoff")
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2. Expected: every line prints `ok`.

- [ ] **Step 5: Commit**

```bash
git add world/fishing_spot.gd tests/test_fishing_spot.gd
git commit -m "feat(world): add FishingSpot hand-off Interactable"
```

---

### Task 5: `FishingPanel`

**Files:**
- Create: `world/ui/fishing_panel.gd`
- Test: `tests/test_fishing_panel.gd`

**Interfaces:**
- Consumes: `FishingShadowGenerator` (Task 2) — `.generate(bounds, min, max)`, `.reel_count_for_bucket(bucket)`. `FishingReel` (Task 1) — `.make_default(composition)`. `FishingMinigame` (Task 3) — `.new(reels)`, `.advance(delta)`, `.current_face(col)`, `.stop(col)`, `.all_stopped()`, `.resolve()`. `PCController.movement_velocity(input_vector, speed, paused) -> Vector2` (existing, `world/pc_controller.gd`). `PartyInventory.give_material(m: CraftingMaterial)` (existing). `CraftingMaterial.quality_tier` (existing, added by the Foraging plan).
- Produces: `class_name FishingPanel extends Panel` with `signal fishing_completed(item_name: String, quantity: int)`, `func open_for(bucket_configs: Dictionary, party_inventory: PartyInventory, forced_shadows: Array[Dictionary] = []) -> void` (empty `forced_shadows` = real random generation; tests pass a deterministic layout), `func is_open() -> bool`, `func current_phase_for_test() -> StringName`, `func shadows_for_test() -> Array[Dictionary]`, `func move_hook_to_for_test(pos: Vector2) -> void`, `func press_hook_button_for_test() -> void`, `func begin_reel_stop_for_test(bucket: StringName, forced_reels: Array[FishingReel]) -> void` (test-only bypass straight into the reel-stop phase, skipping targeting, for deterministic resolve/grant testing), `func advance_for_test(delta: float) -> void`, `func press_stop_for_test(col: int) -> void`, `func press_continue_for_test() -> void`, `func reel_label_font_size_for_test(col: int) -> int` (proves Critical renders smaller, per spec section 3).

- [ ] **Step 1: Write the failing test**

Create `tests/test_fishing_panel.gd`:

```gdscript
extends SceneTree

## FishingPanel: view over FishingShadowGenerator/FishingMinigame (2026-08-01
## gathering-profession-minigames spec section 3). Mirrors RandomEncounterPanel's
## SceneTree/_initialize()/press_*_for_test structure and "clear and rebuild children per phase"
## convention.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _bucket_configs() -> Dictionary:
	return {
		&"small": {"material_type": &"fish_small", "material_display_name": "Minnow", "quantity": 1},
		&"medium": {"material_type": &"fish_medium", "material_display_name": "Freshwater Fish", "quantity": 2},
		&"large": {"material_type": &"fish_large", "material_display_name": "Prize Bass", "quantity": 1},
	}

## Builds a FishingReel whose faces are exactly [param tiers], in order, un-shuffled.
func _reel(tiers: Array) -> FishingReel:
	var reel: FishingReel = FishingReel.new()
	for tier: StringName in tiers:
		var face: ReelFace = ReelFace.new()
		face.fishing_tier = tier
		reel.faces.append(face)
	return reel

func _initialize() -> void:
	var inv: PartyInventory = PartyInventory.new()
	var panel: FishingPanel = FishingPanel.new()
	get_root().add_child(panel)
	await process_frame

	# --- Targeting phase, with a forced deterministic shadow layout ---
	var forced_shadows: Array[Dictionary] = [
		{"position": Vector2(100.0, 100.0), "size_bucket": &"small", "radius": 16.0},
		{"position": Vector2(300.0, 150.0), "size_bucket": &"large", "radius": 32.0},
	]
	panel.open_for(_bucket_configs(), inv, forced_shadows)
	_check(panel.visible, "open_for shows the panel")
	_check(panel.is_open(), "is_open() reflects visible")
	_check(panel.current_phase_for_test() == &"targeting", "opens into the targeting phase")
	_check(panel.shadows_for_test().size() == 2, "the forced shadow layout is used as-is (not randomly regenerated)")

	# A miss: hook far from both shadows, pressing the button does nothing.
	panel.move_hook_to_for_test(Vector2(0.0, 0.0))
	panel.press_hook_button_for_test()
	_check(panel.current_phase_for_test() == &"targeting", "pressing Drop Hook while not overlapping any shadow stays in targeting phase")

	# A hit: move onto the small shadow exactly, drop the hook.
	panel.move_hook_to_for_test(Vector2(100.0, 100.0))
	panel.press_hook_button_for_test()
	_check(panel.current_phase_for_test() == &"reel_stop", "pressing Drop Hook while overlapping a shadow transitions to the reel_stop phase")

	# --- Reel-stop phase + resolution + grant, via the deterministic test-only bypass ---
	# (re-open fresh so this part of the test is independent of the targeting-phase hit above)
	panel.open_for(_bucket_configs(), inv, forced_shadows)
	panel.begin_reel_stop_for_test(&"medium", [_reel([&"critical"]), _reel([&"critical"]), _reel([&"critical"])] as Array[FishingReel])
	_check(panel.current_phase_for_test() == &"reel_stop", "begin_reel_stop_for_test enters the reel_stop phase directly")
	_check(panel.reel_label_font_size_for_test(0) == FishingPanel.CRITICAL_FONT_SIZE,
		"a reel currently showing Critical renders at the smaller CRITICAL_FONT_SIZE (spec: a genuine precision reward)")

	var completed_events: Array = []   # [{"name": String, "quantity": int}]
	panel.fishing_completed.connect(func(item_name: String, quantity: int) -> void:
		completed_events.append({"name": item_name, "quantity": quantity}))

	panel.advance_for_test(1.0)   # prove ticking doesn't crash; the rigged reels are all-critical regardless of index
	panel.press_stop_for_test(0)
	panel.press_stop_for_test(1)
	panel.press_stop_for_test(2)
	panel.press_continue_for_test()

	_check(inv.materials.size() == 1, "an all-Critical 3-reel catch grants exactly one CraftingMaterial")
	var m: CraftingMaterial = inv.materials[0]
	_check(m.material_type == &"fish_medium", "the granted material matches the medium bucket's config")
	_check(m.quantity == 4, "medium bucket base quantity 2, all-Critical quantity_multiplier 2 -> 4")
	_check(m.quality_tier == 1, "an all-Critical catch stamps quality_tier == 1")
	_check(completed_events.size() == 1 and completed_events[0]["name"] == "Freshwater Fish", "fishing_completed fires with the caught item's display name")
	_check(not panel.is_open(), "pressing Continue after a catch closes the panel")

	# --- A no-catch case grants nothing and does not emit fishing_completed ---
	var inv2: PartyInventory = PartyInventory.new()
	panel.open_for(_bucket_configs(), inv2, forced_shadows)
	panel.begin_reel_stop_for_test(&"small", [_reel([&"fail"])] as Array[FishingReel])
	_check(panel.reel_label_font_size_for_test(0) == FishingPanel.NORMAL_FONT_SIZE,
		"a reel currently showing Fail renders at the normal (larger) font size, distinct from Critical's")
	panel.press_stop_for_test(0)
	panel.press_continue_for_test()
	_check(inv2.materials.is_empty(), "a Fail on a 1-reel fish grants nothing")
	_check(completed_events.size() == 1, "fishing_completed does not fire again on a no-catch round")

	panel.free()
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_fishing_panel.gd`
Expected: FAIL / parse error — `FishingPanel` does not exist yet.

- [ ] **Step 3: Write the implementation**

Create `world/ui/fishing_panel.gd`:

```gdscript
class_name FishingPanel
extends Panel

## Fishing mini-game overlay -- claw-machine targeting + manual-stop multi-reel catch (2026-08-01
## gathering-profession-minigames spec section 3). Mirrors RandomEncounterPanel's "clear and
## rebuild children per phase" convention (_build_targeting/_build_reel_stop/_build_result) rather
## than toggling visibility on a fixed set of pre-built children, since the phases have genuinely
## different content (a movable hook + shadows vs. a row of reel displays vs. a result message).

signal fishing_completed(item_name: String, quantity: int)

const PANEL_W: float = 520.0
const PANEL_H: float = 440.0
const WATER_RECT: Rect2 = Rect2(20.0, 20.0, 480.0, 240.0)
## [ASSUMPTION] hook hit-radius/speed, tuned at playtest.
const HOOK_RADIUS: float = 10.0
const HOOK_SPEED: float = 140.0
## [ASSUMPTION] shadow count range per targeting-phase layout, tuned at playtest.
const MIN_SHADOWS: int = 3
const MAX_SHADOWS: int = 6
## [ASSUMPTION] reel composition (spec section 3's own example numbers): 4 Fail, 4 Success,
## 2 Critical out of 10 faces, tuned at playtest.
const REEL_COMPOSITION: Array = [[&"fail", 4], [&"success", 4], [&"critical", 2]]
## Critical's face renders visibly SMALLER than Fail/Success (spec section 3: "a genuine precision
## reward, not just a rarer color") -- a font-size difference on the same Label, [ASSUMPTION]
## exact point sizes, tuned at playtest.
const NORMAL_FONT_SIZE: int = 20
const CRITICAL_FONT_SIZE: int = 11

var _party_inventory: PartyInventory
var _bucket_configs: Dictionary = {}
var _shadows: Array[Dictionary] = []
var _hook_position: Vector2 = Vector2.ZERO
var _phase: StringName = &"targeting"   # "targeting" | "reel_stop" | "result"
var _minigame: FishingMinigame
var _active_bucket: StringName = &""

var _hook_control: ColorRect
var _hook_button: Button
var _reel_labels: Array[Label] = []
var _stop_buttons: Array[Button] = []
var _result_label: Label
var _continue_button: Button
var _pending_item_name: String = ""
var _pending_quantity: int = 0

func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	size = custom_minimum_size
	visible = false

## Opens a fresh round. [param forced_shadows] empty (every real call site's default) means
## "generate a real random layout"; tests pass a deterministic layout instead.
func open_for(bucket_configs: Dictionary, party_inventory: PartyInventory, forced_shadows: Array[Dictionary] = []) -> void:
	_party_inventory = party_inventory
	_bucket_configs = bucket_configs
	_shadows = forced_shadows if not forced_shadows.is_empty() else FishingShadowGenerator.generate(WATER_RECT, MIN_SHADOWS, MAX_SHADOWS)
	_hook_position = Vector2(WATER_RECT.position.x + WATER_RECT.size.x / 2.0, WATER_RECT.position.y + WATER_RECT.size.y / 2.0)
	_phase = &"targeting"
	_build_targeting()
	visible = true

func is_open() -> bool:
	return visible

func current_phase_for_test() -> StringName:
	return _phase

func shadows_for_test() -> Array[Dictionary]:
	return _shadows

func _process(delta: float) -> void:
	if not visible:
		return
	if _phase == &"targeting":
		_update_hook_position(delta)
	elif _phase == &"reel_stop":
		_minigame.advance(delta)
		_refresh_reel_labels()

func _update_hook_position(delta: float) -> void:
	var input_vector := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up"))
	var velocity: Vector2 = PCController.movement_velocity(input_vector, HOOK_SPEED, false)
	_hook_position += velocity * delta
	_hook_position.x = clampf(_hook_position.x, WATER_RECT.position.x, WATER_RECT.position.x + WATER_RECT.size.x)
	_hook_position.y = clampf(_hook_position.y, WATER_RECT.position.y, WATER_RECT.position.y + WATER_RECT.size.y)
	if _hook_control != null:
		_hook_control.position = _hook_position - Vector2(HOOK_RADIUS, HOOK_RADIUS)

func _build_targeting() -> void:
	for child in get_children():
		child.queue_free()

	var water_bg := ColorRect.new()
	water_bg.color = Color(0.15, 0.35, 0.55)
	water_bg.position = WATER_RECT.position
	water_bg.size = WATER_RECT.size
	add_child(water_bg)

	for shadow: Dictionary in _shadows:
		var radius: float = shadow["radius"]
		var r := ColorRect.new()
		r.color = Color(0.05, 0.1, 0.2, 0.8)
		r.position = shadow["position"] - Vector2(radius, radius)
		r.size = Vector2(radius * 2.0, radius * 2.0)
		add_child(r)

	_hook_control = ColorRect.new()
	_hook_control.color = Color(0.9, 0.9, 0.2)
	_hook_control.size = Vector2(HOOK_RADIUS * 2.0, HOOK_RADIUS * 2.0)
	_hook_control.position = _hook_position - Vector2(HOOK_RADIUS, HOOK_RADIUS)
	add_child(_hook_control)

	_hook_button = Button.new()
	_hook_button.text = "Drop Hook"
	_hook_button.position = Vector2(WATER_RECT.position.x, WATER_RECT.position.y + WATER_RECT.size.y + 16.0)
	_hook_button.custom_minimum_size = Vector2(150.0, 40.0)
	_hook_button.pressed.connect(_on_hook_pressed)
	add_child(_hook_button)

func move_hook_to_for_test(pos: Vector2) -> void:
	_hook_position = pos
	if _hook_control != null:
		_hook_control.position = _hook_position - Vector2(HOOK_RADIUS, HOOK_RADIUS)

func press_hook_button_for_test() -> void:
	_hook_button.pressed.emit()

func _on_hook_pressed() -> void:
	var hooked_index: int = -1
	for i in range(_shadows.size()):
		var shadow: Dictionary = _shadows[i]
		if _hook_position.distance_to(shadow["position"]) <= float(shadow["radius"]) + HOOK_RADIUS:
			hooked_index = i
			break
	if hooked_index == -1:
		return
	var bucket: StringName = _shadows[hooked_index]["size_bucket"]
	_shadows.remove_at(hooked_index)
	var reel_count: int = FishingShadowGenerator.reel_count_for_bucket(bucket)
	var reels: Array[FishingReel] = []
	for i in range(reel_count):
		reels.append(FishingReel.make_default(REEL_COMPOSITION))
	_begin_reel_stop(bucket, reels)

## Test-only bypass straight into the reel-stop phase with caller-supplied deterministic reels,
## skipping the random targeting phase entirely -- lets tests prove the resolve/grant path exactly,
## since the real _on_hook_pressed() path always builds shuffled reels internally.
func begin_reel_stop_for_test(bucket: StringName, forced_reels: Array[FishingReel]) -> void:
	_begin_reel_stop(bucket, forced_reels)

func _begin_reel_stop(bucket: StringName, reels: Array[FishingReel]) -> void:
	_active_bucket = bucket
	_minigame = FishingMinigame.new(reels)
	_phase = &"reel_stop"
	_build_reel_stop(reels.size())

func _build_reel_stop(reel_count: int) -> void:
	for child in get_children():
		child.queue_free()
	_reel_labels.clear()
	_stop_buttons.clear()

	for i in range(reel_count):
		var label := Label.new()
		label.position = Vector2(20.0 + i * 90.0, 20.0)
		label.custom_minimum_size = Vector2(80.0, 30.0)
		add_child(label)
		_reel_labels.append(label)

		var btn := Button.new()
		btn.text = "Stop"
		btn.position = Vector2(20.0 + i * 90.0, 60.0)
		btn.custom_minimum_size = Vector2(80.0, 36.0)
		var col: int = i
		btn.pressed.connect(func() -> void: _on_stop_pressed(col))
		add_child(btn)
		_stop_buttons.append(btn)

	_refresh_reel_labels()

func _refresh_reel_labels() -> void:
	for i in range(_reel_labels.size()):
		var tier: StringName = _minigame.current_face(i).fishing_tier
		_reel_labels[i].text = String(tier).capitalize()
		var font_size: int = CRITICAL_FONT_SIZE if tier == &"critical" else NORMAL_FONT_SIZE
		_reel_labels[i].add_theme_font_size_override("font_size", font_size)

func advance_for_test(delta: float) -> void:
	if _phase == &"reel_stop":
		_minigame.advance(delta)
		_refresh_reel_labels()

func press_stop_for_test(col: int) -> void:
	_stop_buttons[col].pressed.emit()

## Reads back the reel label's currently-applied font size (spec section 3's "Critical renders
## visibly smaller" requirement) so tests can prove the size actually differs by tier.
func reel_label_font_size_for_test(col: int) -> int:
	return _reel_labels[col].get_theme_font_size("font_size")

func _on_stop_pressed(col: int) -> void:
	_minigame.stop(col)
	_stop_buttons[col].disabled = true
	_refresh_reel_labels()
	if _minigame.all_stopped():
		_resolve()

func _resolve() -> void:
	var outcome: Dictionary = _minigame.resolve()
	_phase = &"result"
	if outcome["caught"]:
		var config: Dictionary = _bucket_configs.get(_active_bucket, {})
		var m := CraftingMaterial.new()
		m.material_type = config.get("material_type", &"")
		m.display_name = config.get("material_display_name", "")
		m.quantity = int(config.get("quantity", 1)) * int(outcome["quantity_multiplier"])
		m.quality_tier = int(outcome["quality_tier"])
		_party_inventory.give_material(m)
		_pending_item_name = m.display_name
		_pending_quantity = m.quantity
		_build_result("You caught a %s! (x%d)" % [m.display_name, m.quantity])
	else:
		_pending_item_name = ""
		_pending_quantity = 0
		_build_result("The fish got away.")

func _build_result(text: String) -> void:
	for child in get_children():
		child.queue_free()

	_result_label = Label.new()
	_result_label.text = text
	_result_label.position = Vector2(20.0, 20.0)
	_result_label.custom_minimum_size = Vector2(PANEL_W - 40.0, 60.0)
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_result_label)

	_continue_button = Button.new()
	_continue_button.text = "Continue"
	_continue_button.position = Vector2(20.0, 90.0)
	_continue_button.custom_minimum_size = Vector2(150.0, 40.0)
	_continue_button.pressed.connect(_on_continue_pressed)
	add_child(_continue_button)

func press_continue_for_test() -> void:
	_continue_button.pressed.emit()

func _on_continue_pressed() -> void:
	visible = false
	if _pending_item_name != "":
		fishing_completed.emit(_pending_item_name, _pending_quantity)
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2. Expected: every line prints `ok`.

- [ ] **Step 5: Commit**

```bash
git add world/ui/fishing_panel.gd tests/test_fishing_panel.gd
git commit -m "feat(world): add FishingPanel (targeting + reel-stop + resolution)"
```

---

### Task 6: Wire `FishingSpot`/`FishingPanel` into `overworld_demo.gd`

**Files:**
- Modify: `world/overworld_demo.gd`
- Test: `tests/test_overworld_demo_fishing.gd`

**Interfaces:**
- Consumes: `FishingPanel` (Task 5) — `.open_for(bucket_configs, party_inventory, forced_shadows)`, `.is_open()`, `.shadows_for_test()`, `.move_hook_to_for_test(pos)`, `.press_hook_button_for_test()`, `.begin_reel_stop_for_test(bucket, forced_reels)`, `.press_stop_for_test(col)`, `.press_continue_for_test()`, `.fishing_completed` signal. `FishingSpot` (Task 4) — `.fishing_requested` signal.

- [ ] **Step 1: Write the failing test**

Create `tests/test_overworld_demo_fishing.gd`:

```gdscript
extends SceneTree

## End-to-end: OverworldDemo's real FishingSpot hands off to the scene's real FishingPanel; a real
## generated shadow gets hooked, a rigged all-Critical 3-reel round grants the correct material into
## the real PartyInventory. Mirrors tests/test_overworld_demo_foraging.gd's real-scene-instance
## technique.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _reel(tiers: Array) -> FishingReel:
	var reel: FishingReel = FishingReel.new()
	for tier: StringName in tiers:
		var face: ReelFace = ReelFace.new()
		face.fishing_tier = tier
		reel.faces.append(face)
	return reel

func _initialize() -> void:
	var combat_handoff: Node = get_root().get_node("CombatHandoff")
	combat_handoff.defeated_encounter_ids = [] as Array[StringName]
	combat_handoff.event_log_entries = [] as Array[Dictionary]

	var scene: PackedScene = load("res://world/overworld_demo.tscn")
	var demo: OverworldDemo = scene.instantiate()
	get_root().add_child(demo)
	await process_frame
	await process_frame

	var spot: FishingSpot = demo.get_node("World/FishingSpot")
	_check(spot != null, "the real overworld scene places a FishingSpot named FishingSpot")

	spot.interact()
	await process_frame

	_check(demo._fishing_panel.is_open(), "interacting with the FishingSpot opens the scene's real FishingPanel")
	_check(demo._pc.movement_paused_for_test(), "opening the fishing panel pauses PC movement")
	_check(combat_handoff.is_defeated(&"FishingSpot"), "the node marked itself defeated on interact")

	# The real targeting phase generated a real random layout -- read it back rather than
	# predicting it, move the hook onto whatever the first shadow actually is, and drop the hook.
	var shadows: Array[Dictionary] = demo._fishing_panel.shadows_for_test()
	_check(shadows.size() > 0, "the real scene's FishingPanel generated at least one shadow")
	var first_shadow: Dictionary = shadows[0]
	demo._fishing_panel.move_hook_to_for_test(first_shadow["position"])
	demo._fishing_panel.press_hook_button_for_test()
	_check(demo._fishing_panel.current_phase_for_test() == &"reel_stop", "dropping the hook on a real generated shadow transitions to the reel_stop phase")

	# Bypass into a deterministic all-Critical 3-reel round to prove the grant lands in the REAL
	# scene's real PartyInventory (the exact resolve/grant math is already Task 3/5's own coverage;
	# this test's job is proving the WIRING, mirroring the Foraging plan's own scene-wiring test).
	demo._fishing_panel.begin_reel_stop_for_test(&"medium", [_reel([&"critical"]), _reel([&"critical"]), _reel([&"critical"])] as Array[FishingReel])
	demo._fishing_panel.press_stop_for_test(0)
	demo._fishing_panel.press_stop_for_test(1)
	demo._fishing_panel.press_stop_for_test(2)
	demo._fishing_panel.press_continue_for_test()
	await process_frame

	_check(not demo._fishing_panel.is_open(), "pressing Continue after a catch closes the panel")
	_check(not demo._pc.movement_paused_for_test(), "closing the panel resumes PC movement")
	_check(demo._party_inventory.materials.size() == 1, "the catch grants the material into the scene's real PartyInventory")
	var m: CraftingMaterial = demo._party_inventory.materials[0]
	_check(m.quality_tier == 1, "the all-Critical catch stamps quality_tier == 1 on the real granted material")

	demo.queue_free()
	await process_frame
	combat_handoff.defeated_encounter_ids = [] as Array[StringName]
	combat_handoff.event_log_entries = [] as Array[Dictionary]
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_overworld_demo_fishing.gd`
Expected: FAIL — `OverworldDemo` has no `_fishing_panel` member yet, and the scene still places the old placeholder `GatheringNode` named `"FishingSpot"`, not a real `FishingSpot`.

- [ ] **Step 3: Write the implementation**

In `world/overworld_demo.gd`, add a new member alongside the existing `_foraging_panel` declaration (currently line 46):

```gdscript
var _foraging_panel: ForagingPanel
var _fishing_panel: FishingPanel
```

Alongside the existing `_foraging_panel` construction block (currently lines 301-304):

```gdscript
	_foraging_panel = ForagingPanel.new()
	_foraging_panel.position = Vector2(140, 60)
	_foraging_panel.foraging_completed.connect(_on_foraging_completed)
	ui.add_child(_foraging_panel)

	_fishing_panel = FishingPanel.new()
	_fishing_panel.position = Vector2(140, 60)
	_fishing_panel.fishing_completed.connect(_on_fishing_completed)
	ui.add_child(_fishing_panel)
```

Replace the placeholder `GatheringNode`-based "FishingSpot" placement block (currently lines 447-455 — locate by content, the block starting `if not _handoff().is_defeated(&"FishingSpot"):`, not by line number, since earlier edits may have shifted it) with a real `FishingSpot`:

```gdscript
	if not _handoff().is_defeated(&"FishingSpot"):
		var fish := FishingSpot.new()
		fish.name = "FishingSpot"
		fish.small_material_type = &"fish_small"
		fish.small_material_display_name = "Minnow"
		fish.small_quantity = 1
		fish.medium_material_type = &"fish_medium"
		fish.medium_material_display_name = "Freshwater Fish"
		fish.medium_quantity = 1
		fish.large_material_type = &"fish_large"
		fish.large_material_display_name = "Prize Bass"
		fish.large_quantity = 1
		fish.global_position = Vector2(560, 340)
		fish.fishing_requested.connect(_on_fishing_requested)
		_world.add_child(fish)
```

Add new handlers alongside the existing `_on_foraging_requested`/`_on_foraging_completed` (currently lines 561-572):

```gdscript
## Opens the Fishing mini-game panel (2026-08-01 gathering-profession-minigames spec section 3) and
## pauses PC movement -- mirrors _on_foraging_requested's existing pattern.
func _on_fishing_requested(bucket_configs: Dictionary) -> void:
	_fishing_panel.open_for(bucket_configs, _party_inventory)
	_pc.set_movement_paused(true)

## A completed catch shows the same top-left pickup label the other gathering flows use, and
## resumes PC movement -- mirrors _on_foraging_completed's existing pattern.
func _on_fishing_completed(item_name: String, quantity: int) -> void:
	_pickup_debug_label.text = "Caught: %s x%d" % [item_name, quantity]
	_handoff().log_event("Caught: %s x%d" % [item_name, quantity], &"loot")
	_pc.set_movement_paused(false)
```

Add `_fishing_panel.is_open()` alongside every existing `_foraging_panel.is_open()` guard check. Locate each site by its current content (the exact set of checks in that `if` line), not by line number — the current five sites (as of this plan's writing) are in `_toggle_inventory()`, `_toggle_stats()`, `_toggle_talents()`, `_process()`, and `_unhandled_input()`, each currently reading:

```gdscript
	if _random_encounter_panel.is_open() or _foraging_panel.is_open() or _talent_panel.visible:
```
or (in `_toggle_talents()`):
```gdscript
	if _random_encounter_panel.is_open() or _foraging_panel.is_open() or _inventory_panel.visible:
```
or (in `_process()`):
```gdscript
	if _inventory_panel.visible or _dialogue_box.is_open() or _random_encounter_panel.is_open() or _foraging_panel.is_open() or _talent_panel.visible:
```
or (in `_unhandled_input()`):
```gdscript
	if _inventory_panel.visible or _random_encounter_panel.is_open() or _foraging_panel.is_open() or _talent_panel.visible:
```

Add `_fishing_panel.is_open()` to each, immediately after `_foraging_panel.is_open()`. For example, `_toggle_inventory()`'s becomes:

```gdscript
	if _random_encounter_panel.is_open() or _foraging_panel.is_open() or _fishing_panel.is_open() or _talent_panel.visible:
		return
```

Apply the equivalent addition to all five sites (read the actual current file to confirm you've found all five and none were missed — do not rely on this plan's own count without verifying against the live file, since a prior task's review in the Foraging plan found exactly this kind of miscount is easy to make).

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2. Expected: every line prints `ok`.

- [ ] **Step 5: Run the full existing suite to confirm no regressions**

From `C:\bunnies\bunnies-main`, run this as a FOREGROUND Bash call (do not background it and walk away — a prior task in the Foraging plan lost a backgrounded sweep entirely; if it doesn't finish within your tool's timeout, run it again, it does not need to restart from scratch since each file is independent):

```bash
for f in bunnies/tests/test_*.gd; do
  name=$(basename "$f")
  ./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script "res://tests/$name" > /tmp/out_$name.log 2>&1
  echo "$? $name"
done | grep -v '^0 '
```

Additionally grep every log for silent mid-frame errors that don't affect exit code (a real bug class this project has hit before): `grep -lE 'SCRIPT ERROR' /tmp/out_test_*.log`. Investigate anything this finds, EXCEPT the already-documented pre-existing `test_dungeon_demo.gd` `SCRIPT ERROR` (null `_location_label`) — that one is confirmed unrelated to this plan, do not attempt to fix it.

Expected: no output from the exit-code grep (aside from the already-documented intermittent teardown-only SIGSEGV flake class, confirm clean on an immediate individual retry if one appears), and no NEW `SCRIPT ERROR` hits beyond the one already-known, unrelated `test_dungeon_demo.gd` case.

- [ ] **Step 6: Commit**

```bash
git add world/overworld_demo.gd tests/test_overworld_demo_fishing.gd
git commit -m "feat(world): wire FishingSpot/FishingPanel into overworld_demo.gd"
```
