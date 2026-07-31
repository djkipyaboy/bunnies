# Team-Up! Minigame Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the real 5×3 Hold & Win Team-Up bonus round (independent per-row draws, token-budgeted locking, symbol tallying, Strike/Mend/Ward/Break/Surge effect resolution, one authored region config) and wire it into the `TeamUpPanel` placeholder shipped by `docs/superpowers/plans/2026-07-29-jackpot-meter-and-trigger.md` (Plan 1) — replacing that plan's "acknowledge and continue" screen with the real minigame, while keeping its `completed` signal contract (meter reset, Main-1 buttons restored) unchanged.

**Prerequisite:** Plan 1 (`docs/superpowers/plans/2026-07-29-jackpot-meter-and-trigger.md`) must already be merged — this plan builds directly on its `PartyInventory.jackpot_meter`, `combat.gd`'s `_team_up_button`/`_team_up_panel`/`_on_team_up_pressed()`/`_on_team_up_completed()`, and `TeamUpPanel`'s `open()`/`completed` shape.

**Architecture:** A pure-logic core (`TeamUpReel` — third `Reel` sibling; `TeamUpMinigame` — the grid/lock/spin/tally model; `TeamUpPaylineResolver` — symbol-matching sibling of `PaylineResolver`; `TeamUpEffects` — static AoE resolution) is built and unit-tested with zero scene/UI dependency, mirroring this codebase's existing "resolver reports, orchestrator applies" convention. `FreeSpinLibrary` (a static registry mirroring `LootTableLibrary`/`EnemyLibrary`) supplies the one authored region config. `TeamUpPanel`'s body is then rewritten from Plan 1's placeholder into a real 5-column grid of clickable cells + Spin/Continue buttons, calling the pure core underneath.

**Tech Stack:** Godot 4.6 GDScript, headless SceneTree tests.

## Global Constraints

- Godot 4.6.3-stable, GDScript only (CLAUDE.md §2). Static typing throughout.
- All new numeric values are `[ASSUMPTION]` placeholders (CLAUDE.md §4) — never "balance" them. Use exactly these first-pass values (spec §8, plus this plan's own necessary additions for the effect-magnitude/amplification numbers the spec left as "exact curve is `[ASSUMPTION]`"):
  - Grid: 5 reels × 3 rows (from `FreeSpinLibrary`'s authored `dungeon` entry — `TeamUpMinigame` itself is grid-size-agnostic, sized from whatever reel array it's constructed with)
  - Lock tokens: 9, Max spins: 5
  - Per-reel composition (10 faces): 3 Strike, 2 Mend, 2 Ward, 2 Break, 1 Surge
  - Effect magnitudes (this plan's own additions, not yet in the spec): `STRIKE_PER_SYMBOL = 8`, `MEND_PER_SYMBOL = 8`, `WARD_PER_SYMBOL = 8`, `WARD_SHIELD_TURNS = 2`, `BREAK_BASE_DURATION = 2` (+1 turn per Break symbol beyond the first), `SURGE_AMPLIFY_PER_LINE = 0.5` (each completed Surge payline adds +50%, stacking additively)
  - Damage type: Light (`res://combat/resources/types/light.tres`)
- No fail/negative tiers anywhere on `TeamUpReel` — every symbol is positive-for-the-party (spec §5).
- `TeamUpReel extends Reel` directly (a third sibling of `InitiativeReel`/`ActionReel`), NOT an `ActionReel` subclass — its rows are drawn independently (3 separate `spin()` calls per reel per grid-fill), never via `CombatResolver._build_grid()`'s single-index-plus-adjacency approach.
- The Godot executable lives ONE DIRECTORY ABOVE this repo: `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe`.
- `take_damage(amount: int)` never applies type-chart math itself — every caller (including `TeamUpEffects`) must compute `damage_type.multiplier_against(target.defense_type)` per target before calling it.

---

## Task 1: `ReelFace.team_up_symbol` + `TeamUpReel`

**Files:**
- Modify: `combat/resources/reel_face.gd`
- Create: `combat/resources/team_up_reel.gd`
- Test: `tests/test_team_up_reel.gd` (new)

**Interfaces:**
- Produces: `ReelFace.team_up_symbol: StringName` (field, default `&""`), `TeamUpReel extends Reel`, `TeamUpReel.make_default(composition: Array) -> TeamUpReel` where `composition` is `Array[Array]` of `[symbol: StringName, count: int]` pairs.

- [ ] **Step 1: Write the failing test**

Create `tests/test_team_up_reel.gd`:

```gdscript
extends SceneTree

# Headless test: ReelFace.team_up_symbol (the third "nullable field" kind, alongside the existing
# Action-reel and Initiative-reel fields — see reel_face.gd's own doc-comment) and TeamUpReel's
# make_default() factory (2026-07-29 UTIL-reel jackpot spec §4). Pure data, no scene needed.
# Run: "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_team_up_reel.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var f: ReelFace = ReelFace.new()
	_check(f.team_up_symbol == &"", "team_up_symbol defaults to empty (unused by Action/Initiative faces)")
	f.team_up_symbol = &"strike"
	_check(f.team_up_symbol == &"strike", "team_up_symbol is a settable StringName")
	_check(f.result_tier == ReelFace.ResultTier.SUCCESS, "setting team_up_symbol leaves the Action-reel default fields untouched")

	var reel: TeamUpReel = TeamUpReel.make_default([[&"strike", 3], [&"mend", 2], [&"ward", 2], [&"break", 2], [&"surge", 1]])
	_check(reel is Reel, "TeamUpReel is a real Reel subclass")
	_check(reel.faces.size() == 10, "make_default builds exactly one face per composition count (got %d)" % reel.faces.size())

	var counts: Dictionary = {}
	for face: ReelFace in reel.faces:
		counts[face.team_up_symbol] = counts.get(face.team_up_symbol, 0) + 1
	_check(counts.get(&"strike", 0) == 3, "3 strike faces (got %d)" % counts.get(&"strike", 0))
	_check(counts.get(&"mend", 0) == 2, "2 mend faces (got %d)" % counts.get(&"mend", 0))
	_check(counts.get(&"ward", 0) == 2, "2 ward faces (got %d)" % counts.get(&"ward", 0))
	_check(counts.get(&"break", 0) == 2, "2 break faces (got %d)" % counts.get(&"break", 0))
	_check(counts.get(&"surge", 0) == 1, "1 surge face (got %d)" % counts.get(&"surge", 0))

	var landed: ReelFace = reel.spin()
	_check(landed != null and landed.team_up_symbol != &"", "spin() (inherited from Reel, no override needed) returns a real tagged face")

	print(("TEAM UP REEL TEST PASSED" if _failures == 0 else "TEAM UP REEL TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_team_up_reel.gd`
Expected: FAIL — `team_up_symbol`/`TeamUpReel` don't exist yet.

- [ ] **Step 3: Add `team_up_symbol` to `ReelFace`**

In `combat/resources/reel_face.gd`, add a new section (after the existing "# Initiative-reel field" block, before "# Helpers"):

```gdscript
# ---------------------------------------------------------------------------
# Team-Up-reel field
# ---------------------------------------------------------------------------

## Which of the 5 Team-Up symbols (Strike/Mend/Ward/Break/Surge) this face carries — a
## TeamUpReel-only field, following this file's own "nullable fields serve multiple reel kinds"
## precedent (2026-07-29 UTIL-reel jackpot spec §4). Empty on every Action/Initiative face.
@export var team_up_symbol: StringName = &""
```

- [ ] **Step 4: Create `TeamUpReel`**

Create `combat/resources/team_up_reel.gd`:

```gdscript
class_name TeamUpReel
extends Reel

## The Team-Up! bonus-round reel — a third sibling of InitiativeReel/ActionReel (2026-07-29 spec
## §4). CLAUDE.md §2's "two subclasses" rule describes why a shared enum-based class is wrong (the
## two existing kinds carry genuinely different face data), not a hard cap of two — this kind's
## faces carry team_up_symbol, not result_tier/multiplier.
##
## Deliberately adds NO spin()/_select_index() override: Reel.spin() already returns one
## independently-drawn face per call. TeamUpMinigame fills a column's 3 rows with THREE separate
## spin() calls on this same reel object, rather than deriving 3 rows from one landed index via
## strip adjacency the way CombatResolver._build_grid() does for ActionReel — that adjacency
## approach can't support "lock one row, re-spin the others on the same reel," which this design
## requires (spec §4).

## Builds a reel from [param composition], an Array of [symbol: StringName, count: int] pairs.
static func make_default(composition: Array) -> TeamUpReel:
	var reel: TeamUpReel = TeamUpReel.new()
	for entry: Array in composition:
		var symbol: StringName = entry[0]
		var count: int = entry[1]
		for i: int in range(count):
			var face: ReelFace = ReelFace.new()
			face.team_up_symbol = symbol
			reel.faces.append(face)
	reel.faces.shuffle()
	return reel
```

- [ ] **Step 5: Run test to verify it passes**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_team_up_reel.gd`
Expected: PASS, exit code 0.

- [ ] **Step 6: Commit**

```bash
git add combat/resources/reel_face.gd combat/resources/team_up_reel.gd tests/test_team_up_reel.gd
git commit -m "feat(combat): add ReelFace.team_up_symbol + the TeamUpReel Reel subclass"
```

---

## Task 2: `TeamUpMinigame` controller

**Files:**
- Create: `combat/team_up_minigame.gd`
- Test: `tests/test_team_up_minigame.gd` (new)

**Interfaces:**
- Consumes: `TeamUpReel` (Task 1); `PaylineLibrary.lines_for(width: int) -> Array` (existing); `TeamUpPaylineResolver.evaluate_by_symbol(...)` (Task 3 — see note below on task ordering).
- Produces: `TeamUpMinigame.new(reels: Array[TeamUpReel], lock_tokens: int, max_spins: int)`, `.grid: Array`, `.locked: Array`, `.lock_tokens_remaining: int`, `.spins_remaining: int`, `.spin() -> bool`, `.lock(col: int, row: int) -> bool`, `.is_complete() -> bool`, `.tally() -> Dictionary` (keys: `"strike"`, `"mend"`, `"ward"`, `"break"`, `"surge_lines"`, all `int`).

**Note on ordering:** `tally()` depends on `TeamUpPaylineResolver` (Task 3). Build this task's `spin()`/`lock()`/`is_complete()`/grid-state first (fully testable without `tally()`), then implement `tally()` as this task's final step once Task 3 exists — **do Task 3 before Task 2's `tally()` step**, i.e. implement Task 3 first, then return here. (If executed strictly in written order, complete Task 2 Steps 1-4 below, pause, do Task 3 in full, then resume Task 2 at Step 5.)

- [ ] **Step 1: Write the failing test (spin/lock/is_complete, no tally yet)**

Create `tests/test_team_up_minigame.gd`:

```gdscript
extends SceneTree

# Headless test: TeamUpMinigame's pure grid/lock/spin/tally logic (2026-07-29 spec §4, §9). No
# scene/UI involved. tally() needs TeamUpPaylineResolver (Task 3) — the surge-payline assertions
# near the bottom of _initialize() will fail until Task 3 lands; everything above them is
# independently correct once Task 2 alone is done.
# Run: "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_team_up_minigame.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _uniform_reel(symbol: StringName) -> TeamUpReel:
	return TeamUpReel.make_default([[symbol, 1]])

func _initialize() -> void:
	# --- Construction ---
	var reels: Array[TeamUpReel] = [_uniform_reel(&"strike"), _uniform_reel(&"mend")]
	var mg: TeamUpMinigame = TeamUpMinigame.new(reels, 9, 5)
	_check(mg.lock_tokens_remaining == 9, "lock_tokens_remaining starts at the constructor value")
	_check(mg.spins_remaining == 5, "spins_remaining starts at the constructor value")
	_check(mg.grid.size() == 2, "grid has one column per reel (got %d)" % mg.grid.size())
	_check(mg.grid[0].size() == 3, "each column has 3 rows (got %d)" % mg.grid[0].size())
	_check(mg.grid[0][0] == null, "the grid starts empty before any spin")
	_check(not mg.is_complete(), "not complete before any spin")

	# --- spin() fills every position and consumes a spin ---
	_check(mg.spin(), "spin() succeeds while spins remain")
	_check(mg.spins_remaining == 4, "spin() decrements spins_remaining (got %d)" % mg.spins_remaining)
	_check(mg.grid[0][0] != null and mg.grid[0][1] != null and mg.grid[0][2] != null, "every row of column 0 is filled after a spin")
	_check(mg.grid[0][0].team_up_symbol == &"strike", "column 0 draws from its own reel's symbol (uniform reel -> always strike)")
	_check(mg.grid[1][0].team_up_symbol == &"mend", "column 1 draws from its own reel's symbol")

	# --- lock() freezes a position deterministically (identity check, not a probabilistic "changed") ---
	var locked_face: ReelFace = mg.grid[0][0]
	_check(mg.lock(0, 0), "lock() succeeds on a visible, unlocked position")
	_check(mg.locked[0][0], "locked[col][row] flips true")
	_check(mg.lock_tokens_remaining == 8, "lock() consumes one token (got %d)" % mg.lock_tokens_remaining)
	mg.spin()
	_check(mg.grid[0][0] == locked_face, "a locked position's face is the SAME object across a subsequent spin (never redrawn)")
	mg.spin()
	_check(mg.grid[0][0] == locked_face, "...and stays the same object across a second subsequent spin")
	_check(not mg.lock(0, 0), "re-locking an already-locked position is a no-op (returns false, no extra token spent)")
	_check(mg.lock_tokens_remaining == 8, "the no-op re-lock didn't consume another token")

	# --- Unlocked rows within the SAME column genuinely redraw independently (spec §9: "confirm
	# the 3 row positions per reel are drawn independently, not sharing one landed index the way
	# ActionReel's grid does"). Proven operationally rather than by reading _select_index() calls: a
	# 5-distinct-symbol reel, one row locked, the other two rows re-spun ~19 more times — if rows
	# were coupled via one shared landed index (like CombatResolver._build_grid()'s posmod
	# adjacency), the locked row freezing would say nothing about the others; independence means the
	# OTHER rows can and do keep changing while the locked one provably doesn't. Chance of a truly
	# independent 5-symbol row showing only 1 distinct value across 19 draws is (1/5)^18 — not a
	# real flake risk.
	var varied_reel: TeamUpReel = TeamUpReel.make_default([[&"strike", 1], [&"mend", 1], [&"ward", 1], [&"break", 1], [&"surge", 1]])
	var mg_indep: TeamUpMinigame = TeamUpMinigame.new([varied_reel], 9, 20)
	mg_indep.spin()
	var row0_locked_face: ReelFace = mg_indep.grid[0][0]
	_check(mg_indep.lock(0, 0), "lock row 0 of the only column")
	var row1_symbols_seen: Dictionary = {}
	var row2_symbols_seen: Dictionary = {}
	for i: int in range(19):
		mg_indep.spin()
		_check(mg_indep.grid[0][0] == row0_locked_face, "locked row 0 stays fixed across spin %d" % (i + 1))
		row1_symbols_seen[mg_indep.grid[0][1].team_up_symbol] = true
		row2_symbols_seen[mg_indep.grid[0][2].team_up_symbol] = true
	_check(row1_symbols_seen.size() > 1, "unlocked row 1 (same column as the locked row 0) shows more than one distinct symbol across 19 re-spins — it is NOT frozen alongside row 0")
	_check(row2_symbols_seen.size() > 1, "unlocked row 2 independently varies too — rows 1 and 2 are not coupled to each other or to row 0")

	# --- lock() runs out of tokens ---
	var mg2: TeamUpMinigame = TeamUpMinigame.new([_uniform_reel(&"strike"), _uniform_reel(&"mend")], 1, 5)
	mg2.spin()
	_check(mg2.lock(0, 0), "the first lock succeeds (1 token available)")
	_check(not mg2.lock(0, 1), "a second lock fails once tokens are exhausted (returns false)")
	_check(not mg2.locked[0][1], "the failed lock attempt left that position unlocked")

	# --- lock() rejects out-of-bounds / empty positions ---
	var mg3: TeamUpMinigame = TeamUpMinigame.new([_uniform_reel(&"strike")], 9, 5)
	_check(not mg3.lock(0, 0), "lock() fails on an empty (never-spun) position")
	_check(not mg3.lock(5, 0), "lock() fails on an out-of-bounds column")
	_check(not mg3.lock(0, 9), "lock() fails on an out-of-bounds row")

	# --- is_complete() / spin() exhaustion ---
	var mg4: TeamUpMinigame = TeamUpMinigame.new([_uniform_reel(&"strike")], 9, 2)
	mg4.spin()
	_check(not mg4.is_complete(), "not complete after 1 of 2 spins")
	mg4.spin()
	_check(mg4.is_complete(), "complete after using all spins")
	var grid_snapshot: ReelFace = mg4.grid[0][0]
	_check(not mg4.spin(), "spin() returns false once complete")
	_check(mg4.grid[0][0] == grid_snapshot, "an over-called spin() leaves the grid untouched")

	print(("TEAM UP MINIGAME TEST PASSED (pre-tally) — run again after Task 3 for the surge-payline assertions" if _failures == 0 else "TEAM UP MINIGAME TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_team_up_minigame.gd`
Expected: FAIL — `TeamUpMinigame` doesn't exist yet.

- [ ] **Step 3: Create `TeamUpMinigame` (grid/lock/spin/is_complete only — no `tally()` body yet)**

Create `combat/team_up_minigame.gd`:

```gdscript
class_name TeamUpMinigame
extends RefCounted

## Pure model for the Team-Up! bonus round (2026-07-29 spec §4): a reels.size()-column x 3-row
## grid, independently-drawn per position, with Hold & Win token-budgeted locking across a fixed
## number of spins. TeamUpPanel is the view; this class holds no Node/UI state and is fully
## headless-testable, mirroring this project's resolver/orchestrator split.

const ROWS: int = 3

var reels: Array[TeamUpReel] = []
var grid: Array = []          # grid[col][row] = ReelFace
var locked: Array = []        # locked[col][row] = bool
var lock_tokens_remaining: int
var spins_remaining: int
var _cols: int

func _init(p_reels: Array[TeamUpReel], p_lock_tokens: int, p_max_spins: int) -> void:
	reels = p_reels
	_cols = reels.size()
	lock_tokens_remaining = p_lock_tokens
	spins_remaining = p_max_spins
	for c: int in range(_cols):
		grid.append([null, null, null])
		locked.append([false, false, false])

## Draws a fresh face for every UNLOCKED position (locked positions keep their current face
## object). Consumes one spin. No-op (returns false, grid untouched) once spins_remaining is 0.
func spin() -> bool:
	if spins_remaining <= 0:
		return false
	for c: int in range(_cols):
		for r: int in range(ROWS):
			if not locked[c][r]:
				grid[c][r] = reels[c].spin()
	spins_remaining -= 1
	return true

## Locks a currently-visible position, freezing it for all remaining spins. Spending a token is
## always optional (spec §4) — this only ever gets CALLED when the player chooses to. Returns
## false (no-op, no token spent) if out of bounds, already locked, empty, or no tokens remain.
func lock(col: int, row: int) -> bool:
	if lock_tokens_remaining <= 0:
		return false
	if col < 0 or col >= _cols or row < 0 or row >= ROWS:
		return false
	if locked[col][row] or grid[col][row] == null:
		return false
	locked[col][row] = true
	lock_tokens_remaining -= 1
	return true

## True once every spin has been used. Every symbol is positive-for-the-party (spec §5) — there is
## no win/lose condition here, only "has the round finished."
func is_complete() -> bool:
	return spins_remaining <= 0

## PLACEHOLDER for this step only — replaced in Step 5 below once TeamUpPaylineResolver (Task 3)
## exists. Do not leave this as the final implementation; Step 5 is required.
func tally() -> Dictionary:
	return {}
```

- [ ] **Step 4: Run the spin/lock/is_complete assertions to verify they pass (tally-dependent ones still fail — expected at this point)**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_team_up_minigame.gd`
Expected: PASS (this test file has no `tally()` assertions yet — those are added in Step 6 below, after Task 3 exists). Commit this intermediate state:

```bash
git add combat/team_up_minigame.gd tests/test_team_up_minigame.gd
git commit -m "feat(combat): add TeamUpMinigame's grid/lock/spin/is_complete model"
```

- [ ] **Step 5: STOP — complete Task 3 in full now, then return here.**

- [ ] **Step 6: Implement `tally()` and extend the test**

Replace the placeholder `tally()` body in `combat/team_up_minigame.gd`:

```gdscript
## Symbol counts + completed Surge-payline count over the current grid (2026-07-29 spec §4/§5).
## Meaningful once is_complete() is true, but callable earlier if TeamUpPanel wants a live preview.
func tally() -> Dictionary:
	var counts: Dictionary = {}
	for c: int in range(_cols):
		for r: int in range(ROWS):
			var face: ReelFace = grid[c][r]
			if face == null or face.team_up_symbol == &"":
				continue
			counts[face.team_up_symbol] = counts.get(face.team_up_symbol, 0) + 1
	var lines: Array = PaylineLibrary.lines_for(_cols)
	var surge_hits: Array = TeamUpPaylineResolver.evaluate_by_symbol(grid, lines, &"surge")
	return {
		"strike": counts.get(&"strike", 0),
		"mend": counts.get(&"mend", 0),
		"ward": counts.get(&"ward", 0),
		"break": counts.get(&"break", 0),
		"surge_lines": surge_hits.size(),
	}
```

Append to `tests/test_team_up_minigame.gd`'s `_initialize()`, right before the `print(...)` line:

```gdscript
	# --- tally(): symbol counts + surge-line detection (needs TeamUpPaylineResolver, Task 3) ---
	var mg5: TeamUpMinigame = TeamUpMinigame.new([_uniform_reel(&"strike"), _uniform_reel(&"strike")], 9, 1)
	mg5.spin()
	var t5: Dictionary = mg5.tally()
	_check(t5["strike"] == 6, "a fully-strike 2x3 grid tallies 6 strike (got %d)" % t5["strike"])
	_check(t5["mend"] == 0 and t5["ward"] == 0 and t5["break"] == 0, "other symbol counts are 0")
	_check(t5["surge_lines"] == 0, "no surge symbols anywhere -> 0 completed surge lines")

	var mg6: TeamUpMinigame = TeamUpMinigame.new([_uniform_reel(&"surge"), _uniform_reel(&"surge")], 9, 1)
	mg6.spin()
	var t6: Dictionary = mg6.tally()
	# PaylineLibrary.lines_for(2): 2 columns (length 3) + 3 rows (length 2) + 0 diagonals (width<3) = 5 lines.
	# Every cell is "surge", so all 5 lines complete.
	_check(t6["surge_lines"] == 5, "a fully-surge 2x3 grid completes all 5 of PaylineLibrary.lines_for(2)'s lines (got %d)" % t6["surge_lines"])
```

Update the file's final print message back to a plain pass/fail line (remove the "run again after Task 3" caveat text):

```gdscript
	print(("TEAM UP MINIGAME TEST PASSED" if _failures == 0 else "TEAM UP MINIGAME TEST FAILED: %d" % _failures))
```

- [ ] **Step 7: Run test to verify it passes**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_team_up_minigame.gd`
Expected: PASS, exit code 0.

- [ ] **Step 8: Commit**

```bash
git add combat/team_up_minigame.gd tests/test_team_up_minigame.gd
git commit -m "feat(combat): implement TeamUpMinigame.tally() via TeamUpPaylineResolver"
```

---

## Task 3: `TeamUpPaylineResolver`

**Files:**
- Create: `combat/team_up_payline_resolver.gd`
- Test: `tests/test_team_up_payline_resolver.gd` (new)

**Interfaces:**
- Consumes: `PaylineLibrary.lines_for(width: int) -> Array` (existing, symbol-agnostic Vector2i coordinate lists).
- Produces: `TeamUpPaylineResolver.evaluate_by_symbol(grid: Array, lines: Array, symbol: StringName) -> Array` (of `TeamUpPaylineResolver.SymbolHit`, each with `.cells: Array`, `.symbol: StringName`, `.length: int`) — consumed by `TeamUpMinigame.tally()` (Task 2, Step 6).

**Note:** do this task in full before returning to Task 2 Step 6.

- [ ] **Step 1: Write the failing test**

Create `tests/test_team_up_payline_resolver.gd`:

```gdscript
extends SceneTree

# Headless test: TeamUpPaylineResolver, the symbol-matching sibling of PaylineResolver (which
# matches on ReelFace.result_tier — this matches on ReelFace.team_up_symbol instead). Pure grid
# logic, no scene needed. 2026-07-29 spec §4.
# Run: "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_team_up_payline_resolver.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _face(symbol: StringName) -> ReelFace:
	var f: ReelFace = ReelFace.new()
	f.team_up_symbol = symbol
	return f

func _initialize() -> void:
	# A 2-column x 3-row grid: column 0 is all "surge" (a full column match); column 1 is mixed.
	var grid: Array = [
		[_face(&"surge"), _face(&"surge"), _face(&"surge")],
		[_face(&"surge"), _face(&"strike"), _face(&"strike")],
	]
	var lines: Array = PaylineLibrary.lines_for(2)
	_check(lines.size() == 5, "PaylineLibrary.lines_for(2) returns 5 lines (2 columns + 3 rows, no diagonals at width<3) (got %d)" % lines.size())

	var surge_hits: Array = TeamUpPaylineResolver.evaluate_by_symbol(grid, lines, &"surge")
	# Column 0 (all surge) scores. Row 0 ([0,0]=surge,[1,0]=surge) scores. Rows 1/2 mix surge/strike -> no.
	_check(surge_hits.size() == 2, "exactly 2 lines are all-surge (column 0 + row 0) (got %d)" % surge_hits.size())
	for hit: TeamUpPaylineResolver.SymbolHit in surge_hits:
		_check(hit.symbol == &"surge", "each hit records the queried symbol")
		_check(hit.length == hit.cells.size(), "length matches the cells array size")

	var strike_hits: Array = TeamUpPaylineResolver.evaluate_by_symbol(grid, lines, &"strike")
	_check(strike_hits.is_empty(), "no line is entirely 'strike' in this grid (got %d)" % strike_hits.size())

	var mend_hits: Array = TeamUpPaylineResolver.evaluate_by_symbol(grid, lines, &"mend")
	_check(mend_hits.is_empty(), "a symbol present nowhere in the grid scores no lines")

	print(("TEAM UP PAYLINE RESOLVER TEST PASSED" if _failures == 0 else "TEAM UP PAYLINE RESOLVER TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_team_up_payline_resolver.gd`
Expected: FAIL — `TeamUpPaylineResolver` doesn't exist yet.

- [ ] **Step 3: Create `TeamUpPaylineResolver`**

Create `combat/team_up_payline_resolver.gd`:

```gdscript
class_name TeamUpPaylineResolver
extends RefCounted

## Symbol-matching sibling of PaylineResolver (which matches on ReelFace.result_tier) — this
## matches on ReelFace.team_up_symbol instead (2026-07-29 spec §4). Same PaylineHit-shaped return
## and _cell() grid-lookup convention as the original, so a reader already familiar with
## PaylineResolver.evaluate() recognizes this immediately.

## One scoring line for a specific symbol.
class SymbolHit:
	var cells: Array         ## Array[Vector2i] (col,row) on the line.
	var symbol: StringName = &""
	var length: int = 0

## [param grid]: Array[col] of Array[row]=ReelFace. [param lines]: from PaylineLibrary.lines_for().
## Returns every line whose cells are ALL [param symbol] — unlike PaylineResolver.evaluate() (which
## discovers whichever tier the line's first cell has), this checks one caller-specified symbol at
## a time, since TeamUpMinigame.tally() only ever needs Surge-line detection.
static func evaluate_by_symbol(grid: Array, lines: Array, symbol: StringName) -> Array:
	var hits: Array = []
	for line: Array in lines:
		var all_match: bool = true
		for cell: Vector2i in line:
			var face: ReelFace = _cell(grid, cell)
			if face == null or face.team_up_symbol != symbol:
				all_match = false
				break
		if all_match:
			var hit: SymbolHit = SymbolHit.new()
			hit.cells = line
			hit.symbol = symbol
			hit.length = line.size()
			hits.append(hit)
	return hits

static func _cell(grid: Array, cell: Vector2i) -> ReelFace:
	if cell.x < 0 or cell.x >= grid.size():
		return null
	var col: Array = grid[cell.x]
	if cell.y < 0 or cell.y >= col.size():
		return null
	return col[cell.y]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_team_up_payline_resolver.gd`
Expected: PASS, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add combat/team_up_payline_resolver.gd tests/test_team_up_payline_resolver.gd
git commit -m "feat(combat): add TeamUpPaylineResolver, the symbol-matching payline evaluator"
```

- [ ] **Step 6: Now return to Task 2 and complete its Steps 5-8** (implement `TeamUpMinigame.tally()` using this resolver, extend and re-run its test).

---

## Task 4: `TeamUpEffects` — Strike/Mend/Ward/Break/Surge resolution

**Files:**
- Create: `combat/team_up_effects.gd`
- Test: `tests/test_team_up_effects.gd` (new)

**Interfaces:**
- Consumes: `TeamUpMinigame.tally() -> Dictionary` (Task 2); `Combatant.take_damage(amount: int) -> void`, `Combatant.heal(amount: int) -> int`, `Combatant.apply_shield(amount: int, turns: int) -> void`, `Combatant.attach_effect(effect: Effect) -> void`, `Combatant.has_effect(id: StringName) -> bool`, `Combatant.is_alive() -> bool`, `Combatant.defense_type: DamageType` (all existing); `DamageType.multiplier_against(defender: DamageType) -> float` (existing); `EffectLibrary.make(&"weakened") -> Effect` (existing).
- Produces: `TeamUpEffects.apply(tally: Dictionary, allies: Array, enemies: Array, damage_type: DamageType) -> void` — consumed by `TeamUpPanel` (Task 6).

- [ ] **Step 1: Write the failing test**

Create `tests/test_team_up_effects.gd`:

```gdscript
extends SceneTree

# Headless test: TeamUpEffects.apply() — the Strike/Mend/Ward/Break/Surge resolution step
# (2026-07-29 spec §5). Pure Combatant-array logic, no full combat scene needed (mirrors how
# ClassLibrary/EnemyLibrary already build standalone Combatants for unit tests elsewhere).
# Run: "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_team_up_effects.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var light: DamageType = load("res://combat/resources/types/light.tres")

	var ally1: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	var ally2: Combatant = ClassLibrary.make(&"seer").build_combatant(true)
	ally1.take_damage(ally1.max_hp - 10)
	ally2.take_damage(ally2.max_hp - 10)
	var enemy1: Combatant = EnemyLibrary.make(&"rat")
	var enemy2: Combatant = EnemyLibrary.make(&"ferret")
	var enemy1_hp_before: int = enemy1.hp
	var enemy2_hp_before: int = enemy2.hp

	var tally: Dictionary = {"strike": 2, "mend": 1, "ward": 1, "break": 3, "surge_lines": 0}
	TeamUpEffects.apply(tally, [ally1, ally2], [enemy1, enemy2], light)

	_check(enemy1.hp < enemy1_hp_before, "Strike damages enemy1 (%d -> %d)" % [enemy1_hp_before, enemy1.hp])
	_check(enemy2.hp < enemy2_hp_before, "Strike damages enemy2 (%d -> %d)" % [enemy2_hp_before, enemy2.hp])
	_check(ally1.hp == 10 + TeamUpEffects.MEND_PER_SYMBOL, "Mend heals ally1 by count(1)*MEND_PER_SYMBOL, no amplification (expected hp %d, got %d)" % [10 + TeamUpEffects.MEND_PER_SYMBOL, ally1.hp])
	_check(ally2.hp == 10 + TeamUpEffects.MEND_PER_SYMBOL, "Mend heals ally2 identically")
	_check(ally1.shield_hp == TeamUpEffects.WARD_PER_SYMBOL, "Ward shields ally1 by count(1)*WARD_PER_SYMBOL (got %d)" % ally1.shield_hp)
	_check(ally2.shield_hp == TeamUpEffects.WARD_PER_SYMBOL, "Ward shields ally2 identically")
	_check(enemy1.has_effect(&"weakened"), "Break applies the weakened debuff to enemy1")
	_check(enemy2.has_effect(&"weakened"), "Break applies the weakened debuff to enemy2")

	# --- Surge amplification stacks additively across completed lines ---
	var ally3: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	ally3.take_damage(ally3.max_hp - 10)
	var tally_surged: Dictionary = {"strike": 0, "mend": 1, "ward": 0, "break": 0, "surge_lines": 2}
	TeamUpEffects.apply(tally_surged, [ally3], [], light)
	var expected_amp: float = 1.0 + 2.0 * TeamUpEffects.SURGE_AMPLIFY_PER_LINE
	var expected_heal: int = ceili(1 * TeamUpEffects.MEND_PER_SYMBOL * expected_amp)
	_check(ally3.hp == 10 + expected_heal, "2 completed Surge lines amplify Mend (expected heal %d -> hp %d, got hp %d)" % [expected_heal, 10 + expected_heal, ally3.hp])

	# --- A Surge-only tally (no completed line) amplifies nothing on its own (spec §5: "a lone
	# locked Surge face... does nothing") ---
	var ally4: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	ally4.take_damage(ally4.max_hp - 10)
	TeamUpEffects.apply({"strike": 0, "mend": 1, "ward": 0, "break": 0, "surge_lines": 0}, [ally4], [], light)
	_check(ally4.hp == 10 + TeamUpEffects.MEND_PER_SYMBOL, "0 completed surge lines = no amplification (plain heal, got hp %d)" % ally4.hp)

	# --- An all-zero tally is a safe no-op ---
	var ally5: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	var hp_before: int = ally5.hp
	TeamUpEffects.apply({"strike": 0, "mend": 0, "ward": 0, "break": 0, "surge_lines": 0}, [ally5], [], light)
	_check(ally5.hp == hp_before, "an all-zero tally is a safe no-op")
	_check(ally5.shield_hp == 0, "...and grants no shield")

	# --- A dead enemy is skipped (no crash, no effect on the already-dead) ---
	var enemy3: Combatant = EnemyLibrary.make(&"rat")
	enemy3.take_damage(9999)
	_check(not enemy3.is_alive(), "enemy3 is actually dead before this check")
	TeamUpEffects.apply({"strike": 5, "mend": 0, "ward": 0, "break": 5, "surge_lines": 0}, [], [enemy3], light)
	_check(not enemy3.has_effect(&"weakened"), "a dead enemy is skipped, not granted a debuff")

	print(("TEAM UP EFFECTS TEST PASSED" if _failures == 0 else "TEAM UP EFFECTS TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_team_up_effects.gd`
Expected: FAIL — `TeamUpEffects` doesn't exist yet.

- [ ] **Step 3: Create `TeamUpEffects`**

Create `combat/team_up_effects.gd`:

```gdscript
class_name TeamUpEffects
extends RefCounted

## Applies a resolved Team-Up! tally (2026-07-29 spec §5) — the orchestrator half of the
## resolver/orchestrator split TeamUpMinigame.tally() reports. Same-symbol counts collapse into ONE
## combined application per symbol (never per-face); Surge is payline-gated only (a raw surge count
## in the tally is otherwise inert — only tally["surge_lines"] matters here). All [ASSUMPTION]
## magnitudes, tune by playtest (CLAUDE.md §4).

const STRIKE_PER_SYMBOL: int = 8
const MEND_PER_SYMBOL: int = 8
const WARD_PER_SYMBOL: int = 8
const WARD_SHIELD_TURNS: int = 2
const BREAK_BASE_DURATION: int = 2
const SURGE_AMPLIFY_PER_LINE: float = 0.5   ## each completed Surge payline adds +50%, additive stacking

## [param tally]: from TeamUpMinigame.tally(). [param allies]/[param enemies]: plain Combatant
## arrays (combat.gd passes _allies_of(attacker)/_enemies_of(attacker)). [param damage_type]: the
## Team-Up round's damage type (Light for the one authored region so far).
static func apply(tally: Dictionary, allies: Array, enemies: Array, damage_type: DamageType) -> void:
	var amp: float = 1.0 + float(tally.get("surge_lines", 0)) * SURGE_AMPLIFY_PER_LINE

	var strike_count: int = tally.get("strike", 0)
	if strike_count > 0:
		var raw: int = ceili(strike_count * STRIKE_PER_SYMBOL * amp)
		for enemy: Combatant in enemies:
			if enemy.is_alive():
				var mult: float = damage_type.multiplier_against(enemy.defense_type) if damage_type != null else 1.0
				enemy.take_damage(ceili(raw * mult))

	var mend_count: int = tally.get("mend", 0)
	if mend_count > 0:
		var heal_amt: int = ceili(mend_count * MEND_PER_SYMBOL * amp)
		for ally: Combatant in allies:
			if ally.is_alive():
				ally.heal(heal_amt)

	var ward_count: int = tally.get("ward", 0)
	if ward_count > 0:
		var shield_amt: int = ceili(ward_count * WARD_PER_SYMBOL * amp)
		for ally: Combatant in allies:
			if ally.is_alive():
				ally.apply_shield(shield_amt, WARD_SHIELD_TURNS)

	var break_count: int = tally.get("break", 0)
	if break_count > 0:
		var duration: int = BREAK_BASE_DURATION + (break_count - 1)
		for enemy: Combatant in enemies:
			if enemy.is_alive():
				var eff: Effect = EffectLibrary.make(&"weakened")
				eff.duration = duration
				enemy.attach_effect(eff)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_team_up_effects.gd`
Expected: PASS, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add combat/team_up_effects.gd tests/test_team_up_effects.gd
git commit -m "feat(combat): add TeamUpEffects — Strike/Mend/Ward/Break/Surge resolution"
```

---

## Task 5: `FreeSpinLibrary` registry

**Files:**
- Create: `economy/free_spin_library.gd`
- Test: `tests/test_free_spin_library.gd` (new)

**Interfaces:**
- Consumes: `TeamUpReel.make_default(composition: Array) -> TeamUpReel` (Task 1).
- Produces: `FreeSpinLibrary.IDS: Array[StringName]`, `FreeSpinLibrary.make(id: StringName) -> Dictionary` (keys: `"reels": Array[TeamUpReel]`, `"lock_tokens": int`, `"max_spins": int`, `"damage_type": DamageType`; empty `{}` for an unknown id) — consumed by `TeamUpPanel` (Task 6).

- [ ] **Step 1: Write the failing test**

Create `tests/test_free_spin_library.gd`:

```gdscript
extends SceneTree

# Headless test: FreeSpinLibrary, the region/dungeon-keyed Team-Up config registry (2026-07-29
# spec §6) — mirrors LootTableLibrary/EnemyLibrary's static-registry convention. Exactly one
# authored entry (the current dungeon) per spec's deliberately-scoped-down §6/§7.
# Run: "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_free_spin_library.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	_check(FreeSpinLibrary.IDS.has(&"dungeon"), "the dungeon config id is registered")

	var config: Dictionary = FreeSpinLibrary.make(&"dungeon")
	var reels: Array = config.get("reels", [])
	_check(reels.size() == FreeSpinLibrary.COLS, "the dungeon config builds COLS reels (got %d)" % reels.size())
	for reel: TeamUpReel in reels:
		_check(reel is TeamUpReel, "each reel is a real TeamUpReel")
		_check(reel.faces.size() == 10, "each reel's authored composition totals 10 faces (3+2+2+2+1) (got %d)" % reel.faces.size())
	_check(config["lock_tokens"] == FreeSpinLibrary.LOCK_TOKENS, "lock_tokens matches the const (got %d)" % config["lock_tokens"])
	_check(config["max_spins"] == FreeSpinLibrary.MAX_SPINS, "max_spins matches the const (got %d)" % config["max_spins"])
	_check(config["damage_type"] is DamageType and (config["damage_type"] as DamageType).type == DamageType.Type.LIGHT, "the dungeon's Team-Up damage type is Light")

	var unknown: Dictionary = FreeSpinLibrary.make(&"nonexistent_region")
	_check(unknown.is_empty(), "an unknown region id returns an empty config, not a crash")

	var config2: Dictionary = FreeSpinLibrary.make(&"dungeon")
	_check(config["reels"][0] != config2["reels"][0], "make() returns FRESH reel instances every call — no shared state between rounds")

	print(("FREE SPIN LIBRARY TEST PASSED" if _failures == 0 else "FREE SPIN LIBRARY TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_free_spin_library.gd`
Expected: FAIL — `FreeSpinLibrary` doesn't exist yet.

- [ ] **Step 3: Create `FreeSpinLibrary`**

Create `economy/free_spin_library.gd`:

```gdscript
class_name FreeSpinLibrary
extends RefCounted

## Code registry of authored Team-Up! round configs, keyed by region/dungeon id (2026-07-29 spec
## §6) — mirrors LootTableLibrary/EnemyLibrary/EncounterLibrary's static-registry convention.
## Returns a FRESH config (fresh TeamUpReel instances) every call, so no state leaks between
## rounds/fights. Exactly ONE authored entry per spec §6/§7 — the current dungeon; no other
## region's variant is designed or stubbed. [ASSUMPTION] composition/token/spin counts (spec §8).

const IDS: Array[StringName] = [&"dungeon"]

const COLS: int = 5
const LOCK_TOKENS: int = 9
const MAX_SPINS: int = 5

## [ASSUMPTION] per-reel symbol composition (spec §8): 3 Strike, 2 Mend, 2 Ward, 2 Break, 1 Surge.
static func make(id: StringName) -> Dictionary:
	match id:
		&"dungeon":
			var composition: Array = [[&"strike", 3], [&"mend", 2], [&"ward", 2], [&"break", 2], [&"surge", 1]]
			var reels: Array[TeamUpReel] = []
			for i: int in range(COLS):
				reels.append(TeamUpReel.make_default(composition))
			var light: DamageType = load("res://combat/resources/types/light.tres")
			return {
				"reels": reels,
				"lock_tokens": LOCK_TOKENS,
				"max_spins": MAX_SPINS,
				"damage_type": light,
			}
		_:
			return {}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_free_spin_library.gd`
Expected: PASS, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add economy/free_spin_library.gd tests/test_free_spin_library.gd
git commit -m "feat(economy): add FreeSpinLibrary — the region-keyed Team-Up config registry"
```

---

## Task 6: Real `TeamUpPanel` UI + `combat.gd` wiring

**Files:**
- Modify: `combat/ui/team_up_panel.gd` (replaces Plan 1's placeholder body)
- Modify: `combat/combat.gd` (`_on_team_up_pressed()`'s call site)
- Test: `tests/test_team_up_panel_e2e.gd` (new)

**Interfaces:**
- Consumes: `TeamUpMinigame` (Task 2), `FreeSpinLibrary.make(id) -> Dictionary` (Task 5), `TeamUpEffects.apply(...)` (Task 4); `Combat._allies_of(c)`/`_enemies_of(c)` (existing, from `combat.gd`).
- Produces: `TeamUpPanel.open_for(config: Dictionary, allies: Array, enemies: Array) -> void` — **replaces Plan 1's zero-arg `open()`** (this is the one deliberate, documented deviation from Plan 1's "contract does not change" note — the `completed` signal itself, and everything `combat.gd`'s `_on_team_up_completed()` does with it, is unchanged).

- [ ] **Step 1: Write the failing test**

Create `tests/test_team_up_panel_e2e.gd`:

```gdscript
extends SceneTree

# Headless end-to-end test: the real Team-Up! minigame UI, driven through a real combat.tscn via
# the CombatHandoff entry point (mirrors tests/test_item_use_targeting_e2e.gd). Rigs every reel's
# faces to a single deterministic symbol so the round's outcome is predictable, then drives the
# panel through a full round via its own button-press handlers (the same technique other e2e tests
# use for Tween-free, input-free driving). 2026-07-29 spec §3/§4.
# Run: "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_team_up_panel_e2e.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _face(symbol: StringName) -> ReelFace:
	var f: ReelFace = ReelFace.new()
	f.team_up_symbol = symbol
	return f

func _initialize() -> void:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()

	var pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	var inv: PartyInventory = PartyInventory.new()
	inv.jackpot_meter = PartyInventory.JACKPOT_CAP
	var vault: Vault = Vault.new()
	CombatHandoff.begin_encounter(pc, [], inv, vault, [&"rat"],
		&"TeamUpMinigameE2ETestEncounter", "res://world/overworld_demo.tscn", Vector2.ZERO)

	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame

	var guard: int = 0
	while is_instance_valid(inst) and not (inst._awaiting_player_spin and inst._attacker == pc) and guard < 1000:
		guard += 1
		await process_frame
	_check(inst._awaiting_player_spin and inst._attacker == pc, "reached the PC's own pre-spin window")

	var enemy: Combatant = inst._enemies[0]
	var enemy_hp_before: int = enemy.hp

	inst._on_team_up_pressed()
	_check(inst._team_up_panel.visible, "Team-Up! opens the real minigame panel")
	_check(inst._team_up_panel._minigame is TeamUpMinigame, "open_for() built a real TeamUpMinigame from FreeSpinLibrary.make(&\"dungeon\")")

	# Rig every reel to a single deterministic "strike" face for a fully predictable tally.
	for reel: TeamUpReel in inst._team_up_panel._minigame.reels:
		reel.faces = [_face(&"strike")]

	for i: int in range(FreeSpinLibrary.MAX_SPINS):
		inst._team_up_panel._on_spin_pressed()

	_check(inst._team_up_panel._minigame.is_complete(), "the round completes after MAX_SPINS spins")
	_check(enemy.hp < enemy_hp_before, "an all-Strike round damages the enemy once resolved (%d -> %d)" % [enemy_hp_before, enemy.hp])
	_check(inst._team_up_panel._continue_button.visible, "Continue appears once the round resolves")

	inst._team_up_panel._continue_button.pressed.emit()
	_check(not inst._team_up_panel.visible, "Continue closes the panel")
	_check(inv.jackpot_meter == 0, "completing the real minigame still resets the Jackpot Meter (Plan 1's contract, unchanged)")
	_check(not inst._spin_button.disabled, "the triggering PC's own turn is still unaffected")

	# --- Click-to-lock wiring (fresh round on the same panel instance) ---
	inst._team_up_panel.open_for(FreeSpinLibrary.make(&"dungeon"), [pc], [enemy])
	for reel: TeamUpReel in inst._team_up_panel._minigame.reels:
		reel.faces = [_face(&"mend")]
	inst._team_up_panel._on_spin_pressed()
	inst._team_up_panel._on_cell_pressed(0, 0)
	_check(inst._team_up_panel._minigame.locked[0][0], "clicking a cell button calls lock() on that grid position")
	_check(inst._team_up_panel._cell_buttons[0][0].disabled, "a locked cell's button visually disables")

	inst.queue_free()
	await process_frame

	print(("TEAM UP PANEL E2E TEST PASSED" if _failures == 0 else "TEAM UP PANEL E2E TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_team_up_panel_e2e.gd`
Expected: FAIL — `TeamUpPanel` still has Plan 1's placeholder body (`open_for`/`_minigame`/`_cell_buttons`/`_on_spin_pressed`/`_on_cell_pressed` don't exist yet).

- [ ] **Step 3: Rewrite `TeamUpPanel`**

Replace the full contents of `combat/ui/team_up_panel.gd`:

```gdscript
class_name TeamUpPanel
extends Panel

## Full-screen Team-Up! overlay (2026-07-29 spec §3/§4) — a 5x3 Hold & Win grid of clickable cells,
## a Spin button, and a resolve-then-Continue flow. Replaces the jackpot-meter-and-trigger plan's
## placeholder "acknowledge and continue" body; combat.gd's pause-before/restore-after handling
## (_on_team_up_pressed/_on_team_up_completed) is unchanged — only open()'s call site becomes
## open_for(config, allies, enemies), since the real round needs a config + target lists.
##
## Mirrors combat.gd's own full-screen precedent (_build_start_overlay's Control.PRESET_FULL_RECT),
## not the small content-sized floating panels AbilityMenuPanel/ItemMenuPanel use.

signal completed

const GRID_COLS: int = 5
const GRID_ROWS: int = 3
const CELL_SIZE: float = 90.0
const CELL_GAP: float = 10.0
const GRID_ORIGIN: Vector2 = Vector2(300, 150)

var _minigame: TeamUpMinigame
var _damage_type: DamageType
var _allies: Array = []
var _enemies: Array = []
var _cell_buttons: Array = []   # [col][row] = Button
var _spin_button: Button
var _status_label: Label
var _tally_label: Label
var _continue_button: Button

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build_grid()

	_spin_button = Button.new()
	_spin_button.text = "Spin"
	_spin_button.position = Vector2(700, 560)
	_spin_button.custom_minimum_size = Vector2(160, 44)
	_spin_button.pressed.connect(_on_spin_pressed)
	add_child(_spin_button)

	_status_label = Label.new()
	_status_label.position = Vector2(300, 500)
	_status_label.custom_minimum_size = Vector2(1000, 30)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_status_label)

	_tally_label = Label.new()
	_tally_label.position = Vector2(300, 620)
	_tally_label.custom_minimum_size = Vector2(1000, 60)
	_tally_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tally_label.visible = false
	add_child(_tally_label)

	_continue_button = Button.new()
	_continue_button.text = "Continue"
	_continue_button.position = Vector2(700, 700)
	_continue_button.custom_minimum_size = Vector2(200, 50)
	_continue_button.visible = false
	_continue_button.pressed.connect(func() -> void:
		visible = false
		completed.emit())
	add_child(_continue_button)

func _build_grid() -> void:
	_cell_buttons.clear()
	for c: int in range(GRID_COLS):
		var col_buttons: Array = []
		for r: int in range(GRID_ROWS):
			var b: Button = Button.new()
			b.position = GRID_ORIGIN + Vector2(c * (CELL_SIZE + CELL_GAP), r * (CELL_SIZE + CELL_GAP))
			b.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
			var cc: int = c
			var rr: int = r
			b.pressed.connect(func() -> void: _on_cell_pressed(cc, rr))
			add_child(b)
			col_buttons.append(b)
		_cell_buttons.append(col_buttons)

## Starts a fresh round using [param config] (from FreeSpinLibrary.make(id)) against
## [param allies]/[param enemies] (combat.gd passes _allies_of(attacker)/_enemies_of(attacker)).
## Mirrors ItemMenuPanel/AbilityMenuPanel's open_for() convention.
func open_for(config: Dictionary, allies: Array, enemies: Array) -> void:
	var reels: Array[TeamUpReel] = config.get("reels", [])
	_minigame = TeamUpMinigame.new(reels, config.get("lock_tokens", 0), config.get("max_spins", 0))
	_damage_type = config.get("damage_type", null)
	_allies = allies
	_enemies = enemies
	_continue_button.visible = false
	_tally_label.visible = false
	_spin_button.disabled = false
	_refresh_grid()
	visible = true

func _on_spin_pressed() -> void:
	if _minigame.spin():
		_refresh_grid()
		if _minigame.is_complete():
			_resolve()

func _on_cell_pressed(col: int, row: int) -> void:
	_minigame.lock(col, row)
	_refresh_grid()

func _refresh_grid() -> void:
	for c: int in range(GRID_COLS):
		for r: int in range(GRID_ROWS):
			var face: ReelFace = _minigame.grid[c][r]
			var btn: Button = _cell_buttons[c][r]
			btn.text = String(face.team_up_symbol).capitalize() if face != null else ""
			btn.disabled = _minigame.locked[c][r] or _minigame.is_complete()
			btn.modulate = Color(0.6, 1.0, 0.6) if _minigame.locked[c][r] else Color(1, 1, 1)
	_spin_button.disabled = _minigame.is_complete()
	_status_label.text = "Spins left: %d   Lock tokens left: %d" % [_minigame.spins_remaining, _minigame.lock_tokens_remaining]

func _resolve() -> void:
	var tally: Dictionary = _minigame.tally()
	TeamUpEffects.apply(tally, _allies, _enemies, _damage_type)
	_tally_label.text = "Strike x%d   Mend x%d   Ward x%d   Break x%d   Surge lines x%d" % [
		tally.get("strike", 0), tally.get("mend", 0), tally.get("ward", 0), tally.get("break", 0), tally.get("surge_lines", 0)]
	_tally_label.visible = true
	_continue_button.visible = true
```

- [ ] **Step 4: Update `combat.gd`'s call site**

In `combat/combat.gd`'s `_on_team_up_pressed()`, replace the `_team_up_panel.open()` line:

```gdscript
	move_child(_team_up_panel, get_child_count() - 1)
	_team_up_panel.open_for(FreeSpinLibrary.make(&"dungeon"), _allies_of(_attacker), _enemies_of(_attacker))
```

(Only one authored region config exists — spec §6/§7 — so `&"dungeon"` is hardcoded here; a future region-variation pass would replace this literal with whatever region/dungeon id the active encounter actually belongs to, not something this pass stubs.)

- [ ] **Step 5: Run test to verify it passes**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_team_up_panel_e2e.gd`
Expected: PASS, exit code 0. Also re-run Plan 1's `tests/test_team_up_trigger.gd` to confirm the pause/restore contract survives this rewrite:

`"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_team_up_trigger.gd`

Expected: this will now FAIL on its one line that calls the OLD `_team_up_panel._continue_button.pressed.emit()` expecting the placeholder's immediate Continue visibility — since the real panel only shows Continue after `_minigame.is_complete()`. Update that one test's flow to match: replace its `inst._on_team_up_pressed()` / immediate-Continue section with the same rig-and-spin-to-completion sequence used above before pressing Continue (or, simpler, since Task 6 fully re-covers that pause/restore/meter-reset contract in `test_team_up_panel_e2e.gd` already, delete the now-redundant later half of `test_team_up_trigger.gd` — from `inst._on_team_up_pressed()` onward — keeping only its earlier button-enablement assertions, which remain valid and aren't duplicated elsewhere).

- [ ] **Step 6: Run the full new-test set to confirm everything is green**

```bash
for f in test_team_up_reel test_team_up_minigame test_team_up_payline_resolver test_team_up_effects test_free_spin_library test_team_up_panel_e2e test_team_up_trigger test_party_inventory_jackpot test_jackpot_fill_hooks test_jackpot_payline_fill_hook test_jackpot_checkpoint_wiring test_jackpot_hud; do
  "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script "res://tests/$f.gd"
  echo "exit: $? ($f)"
done
```

Expected: every listed file exits 0.

- [ ] **Step 7: Commit**

```bash
git add combat/ui/team_up_panel.gd combat/combat.gd tests/test_team_up_panel_e2e.gd tests/test_team_up_trigger.gd
git commit -m "feat(combat): build the real 5x3 Team-Up! minigame UI, replacing the Plan 1 placeholder"
```

---

## Final check

Run the full headless suite to confirm no regressions across the whole codebase:

```bash
for f in tests/test_*.gd; do
  "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script "res://$f" > /tmp/out.txt 2>&1
  code=$?
  if [ $code -ne 0 ]; then echo "FAIL ($code): $f"; fi
done
echo "sweep done"
```

Any failure other than the already-documented, unrelated `test_adventuring_board_panel.gd` (pre-existing since 2026-07-14) or an isolated intermittent teardown-only SIGSEGV (confirmed clean on individual retry, per this project's established flake class) should be investigated before declaring this feature complete.

This plan closes out all 4 sub-projects from `docs/superpowers/specs/2026-07-29-util-reel-jackpot-freespin-design.md`. What remains explicitly out of scope (spec §7, unchanged): any region's Team-Up config besides the dungeon's; Surge acting as a full wild for other symbols' paylines; the profession-minigame tie-in idea; and all tuning of the `[ASSUMPTION]` numbers, which happens after a human playtests the real spin (CLAUDE.md §5's hard ceiling — "you cannot press play and judge whether the spin is fun").
