# Chancer Casino Paylines + Clarity + Reroll Log — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Give the Chancer a casino-style payline experience — ~20 left-to-right lines scored by left-aligned runs (≥3 from reel 1) — plus a universal "Paylines" toggle that cycles the line patterns, and a reroll log that shows the result that *prompted* each re-roll. Every non-Chancer class is unchanged.

**Architecture:** A per-class **payline profile** (`Combatant.payline_profile_id`: `&"default"` | `&"casino"`). `PaylineLibrary` supplies each profile's line set; `PaylineResolver` gains a left-aligned matching mode; `CombatResolver` dispatches by mode; the orchestrator picks the profile from the attacker. The default profile's code path and outputs are untouched, so the six other classes don't regress. UI (toggle) + log are thin glue verified by scene-load + the human playtest; all scoring logic is unit-tested.

**Tech Stack:** Godot 4.6.3-stable, GDScript (static typing), headless `SceneTree` tests.

## Global Constraints

- **GDScript only, never C#.** Static typing throughout.
- **Naming (LOCKED):** Classes/Resources `PascalCase`; files `snake_case`; signals `snake_case` past-tense.
- **`default` profile MUST stay byte-behavior-identical** — the six non-Chancer classes don't change; existing payline suites stay green.
- **Payline reward values unchanged** (decided): keep crit→bonus-damage, success→+1 meter, neutral→refund. `[ASSUMPTION]`, tuned post-playtest.
- **Casino profile:** ~20 left-to-right paths (one cell per reel, col 0→3), left-aligned run scoring, `MIN_RUN = 3` (`[ASSUMPTION]`). Grid stays **3 rows** (no reel-window change).
- **Legibility pillar:** the Paylines toggle shows **one line at a time** (never all-at-once); the reroll log shows the pre-reroll result.
- **Run a test:** from `C:\bunnies\bunnies-main\bunnies`,
  `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_<name>.gd`
- **Commit** after each task (trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`).

---

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `combat/payline_library.gd` | + `casino_lines(width)` (≥20 LTR paths); + `lines_for_profile(profile_id, width)` | Modify |
| `combat/payline_resolver.gd` | + `evaluate_left_align(grid, lines, min_run)` | Modify |
| `combat/combat_resolver.gd` | + `evaluate_paylines_profile(reels, attacks, weapon_reel_count, lines, left_align, min_run)` | Modify |
| `combat/resources/character_class.gd` | + `payline_profile_id` field; copy in `build_combatant`; Chancer = `&"casino"` | Modify |
| `combat/combatant.gd` | + `payline_profile_id: StringName = &"default"` | Modify |
| `combat/combat.gd` | profile-aware payline scoring; reroll-log pre-result; Paylines toggle button | Modify |
| `combat/ui/reel_strip.gd` | + `highlight_path_cell(row)` / clear for the toggle overlay | Modify |
| `tests/test_casino_lines.gd` | ≥20 distinct width-4 one-cell-per-column paths | Create |
| `tests/test_payline_casino.gd` | left-align run scoring | Create |
| `tests/test_payline_profile.gd` | Chancer→casino+left-align, others→default unchanged | Create |

---

### Task 1: `PaylineLibrary` casino line set + profile dispatch

**Files:** Modify `combat/payline_library.gd`; Test `tests/test_casino_lines.gd`

**Interfaces:**
- Produces: `casino_lines(width: int) -> Array` — for `width == 4`, a curated list of **20 distinct** left-to-right paths (each an `Array[Vector2i]` of 4 cells, one per column, col 0→3, rows 0/1/2); for other widths, falls back to `lines_for(width)` (Chancer is always 4 reels — the fallback just avoids a crash). `lines_for_profile(profile_id: StringName, width: int) -> Array` → `&"casino"`→`casino_lines`, else `lines_for`.

- [ ] **Step 1: Write the failing test** — create `tests/test_casino_lines.gd`:

```gdscript
extends SceneTree

# Headless: the Chancer casino line set is >=20 distinct width-4 left-to-right paths (one cell per
# column, valid rows). Run:
# "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_casino_lines.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var lines: Array = PaylineLibrary.casino_lines(4)
	_check(lines.size() >= 20, ">=20 casino lines (got %d)" % lines.size())

	var seen: Dictionary = {}
	var all_ok: bool = true
	for line in lines:
		_check(line.size() == 4, "line has one cell per column (got %d)" % line.size())
		var key: String = ""
		for c: int in range(line.size()):
			var cell: Vector2i = line[c]
			if cell.x != c: all_ok = false          # ordered left-to-right, col == index
			if cell.y < 0 or cell.y > 2: all_ok = false  # valid row
			key += "%d," % cell.y
		seen[key] = true
	_check(all_ok, "every cell is in column order with a valid row 0..2")
	_check(seen.size() == lines.size(), "all lines are distinct paths (got %d unique of %d)" % [seen.size(), lines.size()])

	# Dispatch: casino profile -> casino_lines; default -> lines_for.
	_check(PaylineLibrary.lines_for_profile(&"casino", 4).size() == lines.size(), "profile casino -> casino_lines")
	_check(PaylineLibrary.lines_for_profile(&"default", 4).size() == PaylineLibrary.lines_for(4).size(), "profile default -> lines_for")

	print(("CASINO LINES TEST PASSED" if _failures == 0 else "CASINO LINES TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run to verify it fails**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_casino_lines.gd`
Expected: FAIL — `casino_lines`/`lines_for_profile` not defined.

- [ ] **Step 3: Implement.** In `combat/payline_library.gd`, after `lines_for` add:

```gdscript
## The Chancer's casino payline set: curated left-to-right paths (one cell per reel, col 0 → width-1),
## scored left-aligned (see PaylineResolver.evaluate_left_align). For width 4 (the Chancer) a hand-picked
## set of 20 distinct zigzag/straight rows. Other widths fall back to lines_for (Chancer is always 4).
static func casino_lines(width: int) -> Array:
	if width != 4:
		return lines_for(width)
	# Row sequence per line (row 0=top, 1=center, 2=bottom), one row per reel. Adjacency kept within
	# one row for clean readable zigzags. 20 distinct paths.
	var patterns: Array = [
		[0, 0, 0, 0], [1, 1, 1, 1], [2, 2, 2, 2],
		[0, 1, 2, 2], [2, 1, 0, 0], [0, 0, 1, 2], [2, 2, 1, 0],
		[1, 0, 0, 1], [1, 2, 2, 1], [0, 1, 1, 0], [2, 1, 1, 2],
		[1, 0, 1, 0], [1, 2, 1, 2], [0, 1, 0, 1], [2, 1, 2, 1],
		[1, 1, 0, 0], [1, 1, 2, 2], [0, 0, 1, 1], [2, 2, 1, 1], [1, 0, 1, 2],
	]
	var lines: Array = []
	for pat: Array in patterns:
		var line: Array = []
		for c: int in range(pat.size()):
			line.append(Vector2i(c, pat[c]))
		lines.append(line)
	return lines

## Returns the line set for a payline profile id (Combatant.payline_profile_id).
static func lines_for_profile(profile_id: StringName, width: int) -> Array:
	if profile_id == &"casino":
		return casino_lines(width)
	return lines_for(width)
```

- [ ] **Step 4: Run to verify it passes**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_casino_lines.gd`
Expected: `CASINO LINES TEST PASSED`

- [ ] **Step 5: Commit**

```bash
git add combat/payline_library.gd tests/test_casino_lines.gd
git commit -m "feat(paylines): Chancer casino line set + profile dispatch

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: `PaylineResolver` left-aligned matching

**Files:** Modify `combat/payline_resolver.gd`; Test `tests/test_payline_casino.gd`

**Interfaces:**
- Produces: `evaluate_left_align(grid: Array, lines: Array, min_run: int) -> Array` — for each line (ordered col 0→N-1), finds the **longest run of one scoring tier starting at line[0]**; if `run >= min_run`, emits a `PaylineHit` whose `cells` are the matched prefix (`line.slice(0, run)`), `tier` is that tier, `length` is `run`. Lines whose first cell is null/non-scoring contribute nothing.

- [ ] **Step 1: Write the failing test** — create `tests/test_payline_casino.gd`:

```gdscript
extends SceneTree

# Headless: left-aligned payline scoring — longest run of one scoring tier from reel 1; pays if >=min_run;
# trailing mismatch caps the run; failure-tier start never scores. Run:
# "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_payline_casino.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _face(tier: ReelFace.ResultTier) -> ReelFace:
	var f: ReelFace = ReelFace.new(); f.result_tier = tier; return f

# Build a 4-col grid; each column is [top, center, bottom]. We only populate the center row (row 1).
func _grid_center(tiers: Array) -> Array:
	var g: Array = []
	for t in tiers:
		g.append([_face(ReelFace.ResultTier.FAILURE), _face(t), _face(ReelFace.ResultTier.FAILURE)])
	return g

func _mid_line() -> Array:
	return [Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)]

func _initialize() -> void:
	var CS := ReelFace.ResultTier.CRIT_SUCCESS
	var S := ReelFace.ResultTier.SUCCESS
	var CF := ReelFace.ResultTier.CRIT_FAILURE

	# Run of 3 crit+ then a hit -> scores length 3, tier crit-success, cells = first 3.
	var hits: Array = PaylineResolver.evaluate_left_align(_grid_center([CS, CS, CS, S]), [_mid_line()], 3)
	_check(hits.size() == 1, "3-run scores one hit (got %d)" % hits.size())
	_check(hits[0].length == 3, "run length 3 (got %d)" % hits[0].length)
	_check(hits[0].tier == CS, "tier carried = crit-success")
	_check(hits[0].cells.size() == 3, "hit cells = matched prefix of 3 (got %d)" % hits[0].cells.size())

	# Run of only 2 from the left (crit, crit, hit, crit) -> below min_run -> no score.
	var hits2: Array = PaylineResolver.evaluate_left_align(_grid_center([CS, CS, S, CS]), [_mid_line()], 3)
	_check(hits2.is_empty(), "2-run does not score (got %d)" % hits2.size())

	# Full 4-run.
	var hits3: Array = PaylineResolver.evaluate_left_align(_grid_center([S, S, S, S]), [_mid_line()], 3)
	_check(hits3.size() == 1 and hits3[0].length == 4, "4-run scores length 4")

	# Failure tier at reel 1 -> never scores.
	var hits4: Array = PaylineResolver.evaluate_left_align(_grid_center([CF, CF, CF, CF]), [_mid_line()], 3)
	_check(hits4.is_empty(), "failure-tier start never scores")

	print(("PAYLINE CASINO TEST PASSED" if _failures == 0 else "PAYLINE CASINO TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run to verify it fails**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_payline_casino.gd`
Expected: FAIL — `evaluate_left_align` not defined.

- [ ] **Step 3: Implement.** In `combat/payline_resolver.gd`, after `evaluate` add:

```gdscript
## Left-aligned scoring (the Chancer casino profile): each [param line] is ordered col 0 → N-1; a line
## scores on the longest run of ONE scoring tier starting at line[0], if that run reaches [param min_run].
## The hit's cells are the matched prefix only. Failure tiers (or a null/non-scoring first cell) never score.
static func evaluate_left_align(grid: Array, lines: Array, min_run: int) -> Array:
	var hits: Array = []
	for line: Array in lines:
		if line.is_empty():
			continue
		var first: ReelFace = _cell(grid, line[0])
		if first == null or not (first.result_tier in SCORING_TIERS):
			continue
		var tier: ReelFace.ResultTier = first.result_tier
		var run: int = 1
		for k: int in range(1, line.size()):
			var face: ReelFace = _cell(grid, line[k])
			if face != null and face.result_tier == tier:
				run += 1
			else:
				break
		if run >= min_run:
			var hit: PaylineHit = PaylineHit.new()
			hit.cells = line.slice(0, run)
			hit.tier = tier
			hit.length = run
			hits.append(hit)
	return hits
```

- [ ] **Step 4: Run to verify it passes**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_payline_casino.gd`
Expected: `PAYLINE CASINO TEST PASSED`

- [ ] **Step 5: Commit**

```bash
git add combat/payline_resolver.gd tests/test_payline_casino.gd
git commit -m "feat(paylines): left-aligned run scoring (casino profile)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: `CombatResolver.evaluate_paylines_profile`

**Files:** Modify `combat/combat_resolver.gd`; Test `tests/test_payline_profile.gd` (created here, extended in Task 4)

**Interfaces:**
- Consumes: Task 2 `PaylineResolver.evaluate_left_align`; existing `PaylineResolver.evaluate`, `_build_grid`.
- Produces: `evaluate_paylines_profile(reels: Array[ActionReel], attacks: Array[AttackResult], weapon_reel_count: int, lines: Array, left_align: bool, min_run: int) -> Array` — rebuilds `last_grid` from the attacks' indices, then scores `lines` with `evaluate_left_align` (if `left_align`) or `evaluate` (whole-line). Returns hits; does not emit.

- [ ] **Step 1: Write the failing test** — create `tests/test_payline_profile.gd`:

```gdscript
extends SceneTree

# Headless: CombatResolver.evaluate_paylines_profile dispatches whole-line vs left-aligned scoring and
# rebuilds last_grid. Run:
# "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_payline_profile.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var storm: DamageType = load("res://combat/resources/types/storm.tres")
	var r: CombatResolver = CombatResolver.new()
	var reels: Array[ActionReel] = []
	for i in range(4): reels.append(ActionReel.make_default(storm))
	var attacks: Array[CombatResolver.AttackResult] = []
	for rr: ActionReel in reels:
		attacks.append(r.reresolve_reel(rr, 6.0, null, 0))

	# left_align path runs against the casino lines and rebuilds the grid.
	var casino: Array = PaylineLibrary.casino_lines(4)
	var hits: Array = r.evaluate_paylines_profile(reels, attacks, 4, casino, true, 3)
	_check(hits != null, "left-align profile returns an Array")
	_check(r.last_grid.size() == 4, "last_grid rebuilt to 4 cols (got %d)" % r.last_grid.size())
	for h in hits:
		_check(h.length >= 3, "every left-align hit has length>=3 (got %d)" % h.length)

	# whole-line path runs against the default lines without error.
	var deflines: Array = PaylineLibrary.lines_for(4)
	var hits2: Array = r.evaluate_paylines_profile(reels, attacks, 4, deflines, false, 3)
	_check(hits2 != null, "whole-line profile returns an Array")

	print(("PAYLINE PROFILE TEST PASSED" if _failures == 0 else "PAYLINE PROFILE TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run to verify it fails**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_payline_profile.gd`
Expected: FAIL — `evaluate_paylines_profile` not defined.

- [ ] **Step 3: Implement.** In `combat/combat_resolver.gd`, after `evaluate_paylines` add:

```gdscript
## Scores a given line set against the spin, dispatching by matching mode. Rebuilds last_grid (like
## evaluate_paylines) then uses left-aligned run scoring ([param left_align]) or whole-line matching.
## The orchestrator supplies [param lines] from the attacker's payline profile. Does not emit.
func evaluate_paylines_profile(reels: Array[ActionReel], attacks: Array[AttackResult], weapon_reel_count: int, lines: Array, left_align: bool, min_run: int) -> Array:
	var wcount: int = mini(weapon_reel_count, reels.size())
	last_grid = _build_grid(reels, attacks, wcount)
	if left_align:
		return PaylineResolver.evaluate_left_align(last_grid, lines, min_run)
	return PaylineResolver.evaluate(last_grid, lines)
```

- [ ] **Step 4: Run to verify it passes**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_payline_profile.gd`
Expected: `PAYLINE PROFILE TEST PASSED`

- [ ] **Step 5: Commit**

```bash
git add combat/combat_resolver.gd tests/test_payline_profile.gd
git commit -m "feat(resolver): evaluate_paylines_profile dispatches whole-line vs left-aligned

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: `payline_profile_id` on `CharacterClass`/`Combatant` (Chancer = casino)

**Files:** Modify `combat/resources/character_class.gd`, `combat/combatant.gd`, `combat/class_library.gd`; extend `tests/test_payline_profile.gd`

**Interfaces:**
- Produces: `CharacterClass.payline_profile_id: StringName = &"default"` (exported), copied to `Combatant.payline_profile_id: StringName = &"default"` in `build_combatant`. Chancer's class sets `&"casino"`.

- [ ] **Step 1: Extend the test.** Append to `tests/test_payline_profile.gd` `_initialize()` before the final `print(...)`:

```gdscript
	# Class wiring: Chancer is casino; the other classes are default.
	_check(ClassLibrary.make(&"chancer").payline_profile_id == &"casino", "Chancer profile = casino")
	for id: StringName in [&"warrior", &"vanguard", &"skirmisher"]:
		_check(ClassLibrary.make(id).payline_profile_id == &"default", "%s profile = default" % id)
	var built: Combatant = ClassLibrary.make(&"chancer").build_combatant(true)
	_check(built.payline_profile_id == &"casino", "built Chancer combatant carries casino profile")
```

- [ ] **Step 2: Run to verify it fails**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_payline_profile.gd`
Expected: FAIL — `payline_profile_id` not a valid property.

- [ ] **Step 3: Implement.**
(a) `combat/resources/character_class.gd` — after the `ultimate_id` export add:

```gdscript
## Which payline profile this class scores spins with (Combatant.payline_profile_id): &"default" (the
## 11-line whole-line set) or &"casino" (the Chancer's ~20 left-aligned lines).
@export var payline_profile_id: StringName = &"default"
```

In `build_combatant`, after `c.ultimate_id = ultimate_id` add:

```gdscript
	c.payline_profile_id = payline_profile_id
```

(b) `combat/combatant.gd` — after `var ultimate_id: StringName = &"sticky_wild"` add:

```gdscript
## Payline profile (spec 2026-06-23): &"default" or &"casino" (Chancer). Drives orchestrator scoring.
var payline_profile_id: StringName = &"default"
```

(c) `combat/class_library.gd` — in the `&"chancer"` case, after `c.ultimate_id = &"wildcard_gamble"` add:

```gdscript
			c.payline_profile_id = &"casino"
```

- [ ] **Step 4: Run to verify it passes**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_payline_profile.gd`
Expected: `PAYLINE PROFILE TEST PASSED`

- [ ] **Step 5: Commit**

```bash
git add combat/resources/character_class.gd combat/combatant.gd combat/class_library.gd tests/test_payline_profile.gd
git commit -m "feat(class): payline_profile_id (Chancer = casino)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Orchestrator — profile-aware scoring + reroll-log pre-result

**Files:** Modify `combat/combat.gd`
**Verify:** scene loads headless without error; full suite green.

**Interfaces:** Consumes Tasks 1-4. Two edits, both in `combat/combat.gd`.

- [ ] **Step 1: Profile-aware payline scoring.** Add a const near the top of the script (with the other consts):

```gdscript
const CASINO_MIN_RUN: int = 3  # [ASSUMPTION] Chancer casino lines pay on a left-aligned run of >=3
```

Replace the single payline-emit line (currently `combat/combat.gd:569`):

```gdscript
	_resolver.paylines_resolved.emit(_resolver.evaluate_paylines(reels, attacks, weapon_count, []))
```

with:

```gdscript
	# Score paylines with the attacker's profile: Chancer uses the ~20 casino lines + left-aligned runs;
	# every other class keeps the default whole-line set. (Resolver deferred the emit above.)
	var payline_hits: Array
	if _attacker.payline_profile_id == &"casino":
		payline_hits = _resolver.evaluate_paylines_profile(reels, attacks, weapon_count, PaylineLibrary.casino_lines(weapon_count), true, CASINO_MIN_RUN)
	else:
		payline_hits = _resolver.evaluate_paylines(reels, attacks, weapon_count, [])
	_resolver.paylines_resolved.emit(payline_hits)
```

- [ ] **Step 2: Reroll log shows the pre-reroll result.** In `_apply_post_spin_rerolls` (currently `combat/combat.gd:585`), capture the prior tier before overwriting.

Replace the Re-roll success branch (currently lines ~591-594):

```gdscript
		if idx >= 0 and idx < reels.size():
			attacks[idx] = _resolver.reresolve_reel(reels[idx], base, _defender.defense_type, might)
			changed.append(idx)
			_log("  ♻ %s RE-ROLLS reel %d → %s." % [_attacker.display_name, idx + 1, ReelFace.ResultTier.keys()[attacks[idx].face.result_tier]])
```

with:

```gdscript
		if idx >= 0 and idx < reels.size():
			var prev: String = ReelFace.ResultTier.keys()[attacks[idx].face.result_tier]
			attacks[idx] = _resolver.reresolve_reel(reels[idx], base, _defender.defense_type, might)
			changed.append(idx)
			_log("  ♻ %s RE-ROLLS reel %d: was %s → %s." % [_attacker.display_name, idx + 1, prev, ReelFace.ResultTier.keys()[attacks[idx].face.result_tier]])
```

Replace the Wildcard Gamble loop body (currently lines ~600-608) to log each gambled reel's transition:

```gdscript
		for i: int in range(mini(weapon_count, reels.size())):
			if attacks[i].face != null and attacks[i].face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
				continue  # crit reels are not gambled
			var prev_tier: String = ReelFace.ResultTier.keys()[attacks[i].face.result_tier]
			var orig: int = attacks[i].final_damage
			var rolled: CombatResolver.AttackResult = _resolver.reresolve_reel(reels[i], base, _defender.defense_type, might)
			rolled.final_damage = Combatant.gamble_final_damage(rolled.face.result_tier, orig)
			var rolled_tier: String = ReelFace.ResultTier.keys()[rolled.face.result_tier]
			var outcome: String = ("×2" if rolled.face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS else ("lost" if rolled.final_damage == 0 and orig > 0 else "kept"))
			_log("    R%d was %s → gamble → %s (%s)." % [i + 1, prev_tier, rolled_tier, outcome])
			attacks[i] = rolled
			if i not in changed:
				changed.append(i)
		_log("  🎲 %s WILDCARD GAMBLE — every non-crit reel re-rolled (double-or-nothing)!" % _attacker.display_name)
```

> The `🎲` summary line stays; the per-reel `was X → gamble → Y (outcome)` lines are added before it inside the loop. The `(kept)` label covers neutral/success re-rolls (original stands); `(lost)` covers fail/crit-fail that zeroed a previously-damaging reel; `×2` covers a crit re-roll.

- [ ] **Step 3: Verify scene loads + full suite green.**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --quit-after 3 res://combat/combat.tscn 2>&1 | tail -30`
Expected: no `SCRIPT ERROR` / `Nonexistent function` / parse errors.
Then run every `tests/test_*.gd` and confirm all green (the default payline path must be unchanged — existing payline suites green; new casino suites green).

- [ ] **Step 4: Commit**

```bash
git add combat/combat.gd
git commit -m "feat(combat): profile-aware payline scoring + reroll log shows pre-reroll result

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Paylines toggle UI (all classes)

**Files:** Modify `combat/combat.gd`, `combat/ui/reel_strip.gd`
**Verify:** scene loads headless; **human playtest**.

**Interfaces:** Consumes Task 1 (`lines_for_profile`). A new "Paylines" button cycles the attacker's line set one pattern at a time over the reels.

- [ ] **Step 1: Add a path-highlight to `reel_strip.gd`.** After `flash_cell` add a persistent (non-tweened) highlight that the toggle controls:

```gdscript
## Persistent payline-preview highlight on one window cell (row 0=top,1=center,2=bottom). Unlike
## flash_cell (which fades), this stays until cleared — used by the Paylines toggle to draw one line.
func highlight_path_cell(row: int) -> void:
	clear_path_highlight()
	var marker := ColorRect.new()
	marker.name = "PathHL"
	marker.color = Color(0.3, 0.7, 1.0, 0.40)
	marker.size = Vector2(110, CELL_HEIGHT)
	marker.position = Vector2(0, CELL_HEIGHT * float(row))
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(marker)

func clear_path_highlight() -> void:
	var hl: Node = get_node_or_null("PathHL")
	if hl != null:
		hl.queue_free()
```

- [ ] **Step 2: Add the Paylines button.** In the UI-build block (near the other buttons, `combat/combat.gd:184-210`), add a member `var _paylines_button: Button` (with the other button members) and create it:

```gdscript
	_paylines_button = Button.new()
	_paylines_button.text = "Paylines"
	_paylines_button.position = Vector2(900, 584)
	_paylines_button.custom_minimum_size = Vector2(210, 52)
	add_child(_paylines_button)
```

Add members for cycle state (near other members): `var _payline_cycle_index: int = -1`.

In the signal-connect block (near `_spin_button.pressed.connect(...)`, ~line 304), connect:

```gdscript
	_paylines_button.pressed.connect(_on_paylines_pressed)
```

- [ ] **Step 3: Implement the cycle handler.** Add:

```gdscript
## Cycles the current PC's payline patterns one at a time over the reels (legibility: one line, not all).
## Each press advances to the next line; after the last it clears. Uses the player's profile line set.
func _on_paylines_pressed() -> void:
	var pc: Combatant = _pc
	if pc == null or pc.weapon == null:
		return
	var width: int = pc.weapon.reels.size()
	var lines: Array = PaylineLibrary.lines_for_profile(pc.payline_profile_id, width)
	_clear_payline_preview()
	if lines.is_empty():
		return
	_payline_cycle_index += 1
	if _payline_cycle_index >= lines.size():
		_payline_cycle_index = -1
		_payline_banner.text = ""
		return
	var line: Array = lines[_payline_cycle_index]
	for cell: Vector2i in line:
		if cell.x >= 0 and cell.x < _strips.size():
			_strips[cell.x].highlight_path_cell(cell.y)
	_payline_banner.text = "Paylines: %d / %d" % [_payline_cycle_index + 1, lines.size()]

## Clears any payline-preview highlight on all strips.
func _clear_payline_preview() -> void:
	for s in _strips:
		(s as ReelStrip).clear_path_highlight()
```

- [ ] **Step 4: Clear the preview when a spin starts.** In `_on_spin_pressed` (after `_awaiting_player_spin = false`, ~line 433) add:

```gdscript
	_payline_cycle_index = -1
	_clear_payline_preview()
```

(So a staged preview doesn't linger over a live spin. The strips are rebuilt by `_prepare_strips` anyway, but resetting the cycle index keeps the next turn's cycle starting fresh.)

- [ ] **Step 5: Verify scene loads + full suite green.**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --quit-after 3 res://combat/combat.tscn 2>&1 | tail -30`
Expected: no errors. Then run the full `tests/test_*.gd` suite — all green (UI-only change; no logic suite affected).

- [ ] **Step 6: Commit**

```bash
git add combat/combat.gd combat/ui/reel_strip.gd
git commit -m "feat(combat): Paylines toggle cycles line patterns one at a time (all classes)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

- [ ] **Step 7: PLAYTEST GATE (human).** Play `combat.tscn`, pick Chancer. Verify: the Paylines button cycles ~20 lines one at a time (readable); spins light up far more wins (left-aligned 3+ runs, including partial rows like your middle-three-crits); the reroll/gamble log now shows `was X → … → Y`. Judge the casino feel — if it still falls short, the parked **5-visible-rows** option is the next lever.

---

## Completion checklist

- [ ] New suites green: `test_casino_lines`, `test_payline_casino`, `test_payline_profile`.
- [ ] Full `tests/` suite green — **default-profile payline suites unchanged** (no regression to the six other classes).
- [ ] `combat.tscn` loads headless without errors.
- [ ] **Human playtest** of the Chancer (the casino-feel call).

## Self-review notes (author)

- **Spec coverage:** §1 profiles → T1/T3/T4; §1.2 left-align → T2; §3 toggle → T6; §5 reroll log → T5; §4 balance (rewards unchanged) → T5 reuses existing handlers untouched. Default profile preserved (T5 branches; non-casino path is the existing call verbatim).
- **Type consistency:** `casino_lines(width)->Array`, `lines_for_profile(id,width)->Array`, `evaluate_left_align(grid,lines,min_run)->Array`, `evaluate_paylines_profile(...)->Array`, `payline_profile_id:StringName`, `highlight_path_cell(row)`/`clear_path_highlight()` — consistent across tasks.
- **Risk:** T5/T6 are orchestrator/UI glue verified by scene-load + playtest; all scoring logic is unit-tested in T1-T4. The implementer must read the real `combat.gd` line numbers (they drift) and match the intent if quotes differ.
- **No placeholders:** every code/test step shows complete code + a real command.
