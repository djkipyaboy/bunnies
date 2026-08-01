# Team-Up/Riposte Playtest Fixes + Boss Debug Harness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the riposte-charge persistence bug, rebalance Riposte Storm, let the player undo a Team-Up lock before the next spin and bank a Team-Up round early, and add a permanent debug button that jumps straight into a real Hollow Warden fight for fast boss-fight playtesting.

**Architecture:** Five independent, small changes across `combat/combatant.gd`, `combat/ability_talent_library.gd`, `combat/ui/ability_catalog.gd`, `combat/team_up_minigame.gd`, `combat/ui/team_up_panel.gd`, `world/ui/adventuring_board_panel.gd`, and `world/town_demo.gd`. No new production files except tests. Tasks 3 and 4 both touch `combat/team_up_minigame.gd` and `combat/ui/team_up_panel.gd` — run them in order (3 then 4) to avoid merge conflicts; every other task touches disjoint files and can run in any order.

**Tech Stack:** Godot 4.6.3-stable, GDScript, headless test runner (`Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/<file>.gd`, executable lives ONE DIRECTORY ABOVE the repo at `C:\bunnies\bunnies-main\`).

## Global Constraints

- Godot 4.6.3-stable, GDScript only — no C#.
- Static typing throughout (typed vars, typed function signatures).
- Naming: PascalCase classes, snake_case script files, snake_case past-tense signals, `_on_<emitter>_<signal>` handlers.
- Balance/magnitude numbers are `[ASSUMPTION]`s tuned by playtest — the two numeric changes in this plan (Riposte Storm's 20%/30%) are exactly that kind of player-directed tweak, not to be second-guessed.
- Keep every design N-vs-M / party-ready — no 1v1-only assumptions in new code.
- Run each new/modified test via the headless runner and confirm PASS before committing.
- Indentation in all GDScript files in this repo is tabs, not spaces — match the surrounding file.

---

### Task 1: Fix riposte_charges leaking between fights

**Files:**
- Modify: `combat/combatant.gd:1177-1182` (`clear_combat_effects`)
- Modify: `tests/test_clear_combat_effects_on_combat_end.gd`

**Interfaces:**
- Consumes: `Combatant.riposte_charges: int` (`combatant.gd:295`), pre-existing.
- Produces: no new public API — `clear_combat_effects()` keeps its existing signature, just resets one more field.

**Context:** `Combatant.riposte_charges` is never reset by `clear_combat_effects()` (the "reset transient combat state at fight end" method shipped 2026-07-31). The player saw 6 charges carried over from a prior fight into a new one during the 2026-07-31/08-01 playtest, then a correct +3 gain (a 3-reel Hollow Warden attack landing while Evasion was up) brought it to 9 — reading as a math bug when the real bug is the missing reset. This is the same class of fix as the existing `shield_hp`/`shield_turns` reset already in this method.

- [ ] **Step 1: Add a failing assertion to the existing test**

In `tests/test_clear_combat_effects_on_combat_end.gd`, change the "Combatant.clear_combat_effects() itself" block:

```gdscript
		# --- Combatant.clear_combat_effects() itself ---
		var solo: Combatant = Combatant.new()
		solo.base_stats = Stats.new(); solo.base_max_hp = 100; solo.apply_stats(); solo.start_combat()
		solo.attach_effect(EffectLibrary.make(&"guarded"))
		solo.attach_effect(EffectLibrary.make(&"taunt"))
		solo.apply_shield(20, 2)
		solo.clear_combat_effects()
		_check(solo.active_effects.is_empty(), "clear_combat_effects wipes every effect, including beneficial ones cleanse() would keep")
		_check(solo.shield_hp == 0 and solo.shield_turns == 0, "clear_combat_effects also zeroes any residual shield (got %d/%d)" % [solo.shield_hp, solo.shield_turns])
```

to:

```gdscript
		# --- Combatant.clear_combat_effects() itself ---
		var solo: Combatant = Combatant.new()
		solo.base_stats = Stats.new(); solo.base_max_hp = 100; solo.apply_stats(); solo.start_combat()
		solo.attach_effect(EffectLibrary.make(&"guarded"))
		solo.attach_effect(EffectLibrary.make(&"taunt"))
		solo.apply_shield(20, 2)
		solo.gain_riposte_charges(6)
		solo.clear_combat_effects()
		_check(solo.active_effects.is_empty(), "clear_combat_effects wipes every effect, including beneficial ones cleanse() would keep")
		_check(solo.shield_hp == 0 and solo.shield_turns == 0, "clear_combat_effects also zeroes any residual shield (got %d/%d)" % [solo.shield_hp, solo.shield_turns])
		_check(solo.riposte_charges == 0, "clear_combat_effects also resets riposte_charges (playtest 2026-08-01: charges leaked across fights, got %d)" % solo.riposte_charges)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_clear_combat_effects_on_combat_end.gd`
Expected: FAIL on the new `riposte_charges == 0` check (currently stays at 6).

- [ ] **Step 3: Fix `clear_combat_effects()`**

In `combat/combatant.gd`, change:

```gdscript
func clear_combat_effects() -> void:
	active_effects.clear()
	shield_hp = 0
	shield_turns = 0
	shield_changed.emit(shield_hp, shield_turns)
	recompute_initiative()
```

to:

```gdscript
func clear_combat_effects() -> void:
	active_effects.clear()
	shield_hp = 0
	shield_turns = 0
	shield_changed.emit(shield_hp, shield_turns)
	riposte_charges = 0
	recompute_initiative()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_clear_combat_effects_on_combat_end.gd`
Expected: PASS, all checks `ok`.

- [ ] **Step 5: Run the wider Riposte/Skirmisher suites to confirm no regression**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_riposte_storm.gd`, `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_riposte_charge_counter.gd`
Expected: both PASS unchanged (neither exercises `clear_combat_effects()`).

- [ ] **Step 6: Commit**

```bash
git add combat/combatant.gd tests/test_clear_combat_effects_on_combat_end.gd
git commit -m "fix(combat): reset riposte_charges when combat effects clear at fight end"
```

---

### Task 2: Riposte Storm rebalance — 15%→20% baseline, storm_deeper 20%→30%

**Files:**
- Modify: `combat/combatant.gd:1504-1517` (`fire_riposte_storm` + its doc comment)
- Modify: `combat/ability_talent_library.gd:236` (`storm_deeper` description)
- Modify: `combat/ui/ability_catalog.gd:88` (Riposte Storm catalog description)
- Modify: `tests/test_riposte_storm.gd`
- Modify: `tests/test_ability_talents_skirmisher.gd:148-173` (`_test_riposte_storm_row`)

**Interfaces:**
- Consumes: `Combatant.has_ability_talent(id: StringName) -> bool` (pre-existing).
- Produces: no signature change — `fire_riposte_storm(cost: int) -> bool` keeps its exact shape, only its internal `per_charge` constants change.

**Context:** Player-directed rebalance from the 2026-08-01 playtest conversation: Riposte Storm's baseline per-charge scaling goes from 15% to 20%, and since the `storm_deeper` talent currently boosts exactly that value from 15%→20% (which would make it a dead pick once the baseline itself becomes 20%), the talent's bonus becomes 20%→30%.

- [ ] **Step 1: Write the failing test — update the existing baseline/talent assertions**

In `tests/test_riposte_storm.gd`, change:

```gdscript
	_check(is_equal_approx(_empowered_magnitude(c), 1.45), "commit's Empowered magnitude is 1.45 (1.0 + 0.15*3)")
```

to:

```gdscript
	_check(is_equal_approx(_empowered_magnitude(c), 1.60), "commit's Empowered magnitude is 1.60 (1.0 + 0.20*3)")
```

and change:

```gdscript
	_check(is_equal_approx(_empowered_magnitude(direct_c), 1.75), "fire_riposte_storm caps magnitude at 1.75 (1.0 + 0.15*5), not higher")
```

to:

```gdscript
	_check(is_equal_approx(_empowered_magnitude(direct_c), 2.00), "fire_riposte_storm caps magnitude at 2.00 (1.0 + 0.20*5), not higher")
```

In `tests/test_ability_talents_skirmisher.gd`, change:

```gdscript
	var c2: Combatant = _mk_skirmisher()
	c2.riposte_charges = 4
	_check(c2.fire_riposte_storm(4), "fires Riposte Storm (baseline, 4 charges)")
	var emp: Effect = c2._find_effect(&"empowered")
	_check(is_equal_approx(emp.magnitude, 1.60), "baseline Riposte Storm: 1.0 + 0.15*4 = 1.60 (got %.3f)" % emp.magnitude)
	_check(emp.duration == 1, "baseline Riposte Storm: Empowered lasts 1 turn (got %d)" % emp.duration)
	_check(c2.riposte_charges == 0, "sanity: charges reset to 0 after firing")

	var c3: Combatant = _mk_skirmisher()
	c3.riposte_charges = 4
	_check(c3.pick_ability_talent(&"ability_l4", &"storm_deeper"), "picks storm_deeper")
	_check(c3.fire_riposte_storm(4), "fires Riposte Storm (deeper, 4 charges)")
	var emp3: Effect = c3._find_effect(&"empowered")
	_check(is_equal_approx(emp3.magnitude, 1.80), "storm_deeper: 1.0 + 0.20*4 = 1.80 (got %.3f)" % emp3.magnitude)
```

to:

```gdscript
	var c2: Combatant = _mk_skirmisher()
	c2.riposte_charges = 4
	_check(c2.fire_riposte_storm(4), "fires Riposte Storm (baseline, 4 charges)")
	var emp: Effect = c2._find_effect(&"empowered")
	_check(is_equal_approx(emp.magnitude, 1.80), "baseline Riposte Storm: 1.0 + 0.20*4 = 1.80 (got %.3f)" % emp.magnitude)
	_check(emp.duration == 1, "baseline Riposte Storm: Empowered lasts 1 turn (got %d)" % emp.duration)
	_check(c2.riposte_charges == 0, "sanity: charges reset to 0 after firing")

	var c3: Combatant = _mk_skirmisher()
	c3.riposte_charges = 4
	_check(c3.pick_ability_talent(&"ability_l4", &"storm_deeper"), "picks storm_deeper")
	_check(c3.fire_riposte_storm(4), "fires Riposte Storm (deeper, 4 charges)")
	var emp3: Effect = c3._find_effect(&"empowered")
	_check(is_equal_approx(emp3.magnitude, 2.20), "storm_deeper: 1.0 + 0.30*4 = 2.20 (got %.3f)" % emp3.magnitude)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_riposte_storm.gd`
Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_ability_talents_skirmisher.gd`
Expected: both FAIL on the updated magnitude checks (current code still produces the old 0.15/0.20 values).

- [ ] **Step 3: Implement the rebalance**

In `combat/combatant.gd`, change:

```gdscript
## Skirmisher "Riposte Storm" (L9, ultimate-tier, 3-turn CD): detonates accumulated riposte_charges
## (built by Evasion, Task 9) as a temporary Empowered on this turn's normal reels — +15% per
## charge, capped at 5 charges (+75% max). Fires at baseline (no bonus) with 0 charges. Resets
## charges on use.
func fire_riposte_storm(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	var per_charge: float = 0.20 if has_ability_talent(&"storm_deeper") else 0.15
```

to:

```gdscript
## Skirmisher "Riposte Storm" (L9, ultimate-tier, 3-turn CD): detonates accumulated riposte_charges
## (built by Evasion, Task 9) as a temporary Empowered on this turn's normal reels — +20% per
## charge, capped at 5 charges (+100% max). Fires at baseline (no bonus) with 0 charges. Resets
## charges on use. Baseline bumped 15%->20%, storm_deeper 20%->30%, player-directed rebalance
## 2026-08-01.
func fire_riposte_storm(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	var per_charge: float = 0.30 if has_ability_talent(&"storm_deeper") else 0.20
```

In `combat/ability_talent_library.gd`, change:

```gdscript
					t1.description = "Riposte Storm's per-charge scaling increases to +20% (was +15%)."
```

to:

```gdscript
					t1.description = "Riposte Storm's per-charge scaling increases to +30% (was +20%)."
```

In `combat/ui/ability_catalog.gd`, change:

```gdscript
		&"riposte_storm": return "Consumes your riposte charges: a nova reel deals +15% weapon damage per charge (cap 5), then charges reset to 0. Fires at baseline with 0 charges."
```

to:

```gdscript
		&"riposte_storm": return "Consumes your riposte charges: a nova reel deals +20% weapon damage per charge (cap 5), then charges reset to 0. Fires at baseline with 0 charges."
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_riposte_storm.gd`
Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_ability_talents_skirmisher.gd`
Expected: both PASS, all checks `ok`.

- [ ] **Step 5: Run the wider Skirmisher/ability suites to confirm no regression**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_riposte_charge_counter.gd`, `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_ability_catalog.gd`
Expected: both PASS unchanged (neither asserts the specific magnitude numbers this task changed; `test_ability_catalog.gd` — if present — only checks descriptions are non-empty/exist, not their exact text; if it does assert exact text for `riposte_storm`, update it to match the new "+20%" wording as part of this step).

- [ ] **Step 6: Commit**

```bash
git add combat/combatant.gd combat/ability_talent_library.gd combat/ui/ability_catalog.gd tests/test_riposte_storm.gd tests/test_ability_talents_skirmisher.gd
git commit -m "feat(combat): rebalance Riposte Storm to 20% baseline / 30% with storm_deeper"
```

---

### Task 3: Team-Up minigame — undo a lock before the next spin

**Files:**
- Modify: `combat/team_up_minigame.gd`
- Modify: `combat/ui/team_up_panel.gd`
- Test: Create `tests/test_team_up_minigame_unlock.gd`

**Interfaces:**
- Consumes: `TeamUpMinigame.locked: Array` (`grid[col][row]` shape, pre-existing), `TeamUpMinigame.lock_tokens_remaining: int` (pre-existing).
- Produces: new public methods `TeamUpMinigame.unlock(col: int, row: int) -> bool` and `TeamUpMinigame.can_unlock(col: int, row: int) -> bool`. `TeamUpPanel._on_cell_pressed` and `_refresh_grid` are internal — no other task depends on their exact bodies, only on `TeamUpPanel.open_for(config, allies, enemies)` staying unchanged (it does).

**Context:** `TeamUpMinigame.lock()` (`combat/team_up_minigame.gd:42-51`) only ever locks — there is no unlock, and `TeamUpPanel._refresh_grid()` (`combat/ui/team_up_panel.gd:188`) disables any already-locked cell, so a lock is effectively permanent forever. Player request from the 2026-07-31/08-01 playtest: allow undoing a lock made THIS spin (before the next Spin press) — Hold & Win locks from *earlier* spins stay permanently committed, that's the whole point of the minigame, but a same-spin misclick should be correctable.

- [ ] **Step 1: Write the failing test**

Create `tests/test_team_up_minigame_unlock.gd`:

```gdscript
extends SceneTree

## Headless test: TeamUpMinigame.unlock() lets the player undo a lock made THIS spin (before the
## next spin() call), refunding its token — but a lock committed by an EARLIER spin stays
## permanently held (that's the Hold & Win point). Player request, 2026-08-01 playtest follow-up.
## Run: Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_team_up_minigame_unlock.gd

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond: print("  ok: ", label)
	else: _failures += 1; push_error("FAIL: " + label); print("  FAIL: ", label)

func _initialize() -> void:
	var reel: TeamUpReel = TeamUpReel.new()
	var face: ReelFace = ReelFace.new()
	face.team_up_symbol = &"strike"
	reel.faces = [face]
	var reels: Array[TeamUpReel] = [reel, reel, reel]
	var game: TeamUpMinigame = TeamUpMinigame.new(reels, 3, 5)

	game.spin()
	_check(game.lock(0, 0), "locks (0,0) on the first spin's grid")
	_check(game.lock_tokens_remaining == 2, "locking spent a token (got %d)" % game.lock_tokens_remaining)
	_check(game.can_unlock(0, 0), "a lock made THIS spin can be undone")

	_check(game.unlock(0, 0), "unlock succeeds on a same-spin lock")
	_check(not game.locked[0][0], "(0,0) is no longer locked")
	_check(game.lock_tokens_remaining == 3, "unlocking refunded the token (got %d)" % game.lock_tokens_remaining)
	_check(not game.unlock(0, 0), "unlocking an already-unlocked cell is a no-op (returns false)")

	# Re-lock, then advance a spin — the lock is now from an EARLIER spin and must stay committed.
	_check(game.lock(0, 0), "re-locks (0,0)")
	game.spin()
	_check(game.locked[0][0], "(0,0) is still locked after the next spin")
	_check(not game.can_unlock(0, 0), "a lock from an EARLIER spin can no longer be undone")
	_check(not game.unlock(0, 0), "unlock() refuses a committed (earlier-spin) lock")
	_check(game.locked[0][0], "(0,0) is STILL locked — the refused unlock changed nothing")
	_check(game.lock_tokens_remaining == 2, "no token was refunded by the refused unlock (got %d)" % game.lock_tokens_remaining)

	_check(not game.can_unlock(9, 9), "can_unlock is bounds-safe for an out-of-range cell")
	_check(not game.unlock(9, 9), "unlock is bounds-safe for an out-of-range cell")

	print(("TEAM UP MINIGAME UNLOCK TEST PASSED" if _failures == 0 else "TEAM UP MINIGAME UNLOCK TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_team_up_minigame_unlock.gd`
Expected: FAIL — `can_unlock`/`unlock` don't exist yet (method-not-found).

- [ ] **Step 3: Add lock-tracking and `unlock()`/`can_unlock()` to `TeamUpMinigame`**

In `combat/team_up_minigame.gd`, change:

```gdscript
var reels: Array[TeamUpReel] = []
var grid: Array = []          # grid[col][row] = ReelFace
var locked: Array = []        # locked[col][row] = bool
var lock_tokens_remaining: int
var spins_remaining: int
var _cols: int
```

to:

```gdscript
var reels: Array[TeamUpReel] = []
var grid: Array = []          # grid[col][row] = ReelFace
var locked: Array = []        # locked[col][row] = bool
var lock_tokens_remaining: int
var spins_remaining: int
var _cols: int
## Cells locked since the last spin() call — only these can be unlock()'d (player request,
## 2026-08-01): a lock committed by an EARLIER spin is permanently held (the Hold & Win point).
var _locked_this_round: Array[Vector2i] = []
```

Change `spin()`:

```gdscript
func spin() -> bool:
	if spins_remaining <= 0:
		return false
	for c: int in range(_cols):
		for r: int in range(ROWS):
			if not locked[c][r]:
				grid[c][r] = reels[c].spin()
	spins_remaining -= 1
	return true
```

to:

```gdscript
func spin() -> bool:
	if spins_remaining <= 0:
		return false
	for c: int in range(_cols):
		for r: int in range(ROWS):
			if not locked[c][r]:
				grid[c][r] = reels[c].spin()
	spins_remaining -= 1
	_locked_this_round.clear()
	return true
```

Change `lock()`:

```gdscript
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
```

to:

```gdscript
func lock(col: int, row: int) -> bool:
	if lock_tokens_remaining <= 0:
		return false
	if col < 0 or col >= _cols or row < 0 or row >= ROWS:
		return false
	if locked[col][row] or grid[col][row] == null:
		return false
	locked[col][row] = true
	lock_tokens_remaining -= 1
	_locked_this_round.append(Vector2i(col, row))
	return true

## True if (col, row) is locked AND was locked THIS round (since the last spin()) — the only
## locks unlock() will undo. Bounds-safe.
func can_unlock(col: int, row: int) -> bool:
	if col < 0 or col >= _cols or row < 0 or row >= ROWS:
		return false
	return locked[col][row] and _locked_this_round.has(Vector2i(col, row))

## Undoes a same-round lock, refunding its token. Returns false (no-op) if the cell isn't locked,
## is out of bounds, or was locked by an EARLIER spin (see can_unlock()).
func unlock(col: int, row: int) -> bool:
	if not can_unlock(col, row):
		return false
	locked[col][row] = false
	lock_tokens_remaining += 1
	_locked_this_round.erase(Vector2i(col, row))
	return true
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_team_up_minigame_unlock.gd`
Expected: PASS, all checks `ok`.

- [ ] **Step 5: Wire the panel — toggle lock/unlock on click, with a distinct highlight for still-undoable locks**

In `combat/ui/team_up_panel.gd`, change:

```gdscript
func _on_cell_pressed(col: int, row: int) -> void:
	_minigame.lock(col, row)
	_refresh_grid()
```

to:

```gdscript
func _on_cell_pressed(col: int, row: int) -> void:
	if _minigame.locked[col][row]:
		_minigame.unlock(col, row)
	else:
		_minigame.lock(col, row)
	_refresh_grid()
```

Change the disabled/modulate block inside `_refresh_grid()`:

```gdscript
			var face: ReelFace = _minigame.grid[c][r]
			btn.text = String(face.team_up_symbol).capitalize() if face != null else ""
			btn.disabled = _minigame.locked[c][r] or _minigame.is_complete()
			if _minigame.locked[c][r]:
				btn.modulate = Color(0.6, 1.0, 0.6)
			elif _payline_preview_cells.has(Vector2i(c, r)):
				btn.modulate = Color(1.6, 1.5, 0.5)
			else:
				btn.modulate = Color(1, 1, 1)
```

to:

```gdscript
			var face: ReelFace = _minigame.grid[c][r]
			btn.text = String(face.team_up_symbol).capitalize() if face != null else ""
			var is_locked: bool = _minigame.locked[c][r]
			var can_undo: bool = _minigame.can_unlock(c, r)
			btn.disabled = _minigame.is_complete() or (is_locked and not can_undo)
			if is_locked and can_undo:
				btn.modulate = Color(0.6, 1.0, 1.0)   # still-undoable this round (cyan-green)
			elif is_locked:
				btn.modulate = Color(0.6, 1.0, 0.6)   # committed from an earlier spin (green)
			elif _payline_preview_cells.has(Vector2i(c, r)):
				btn.modulate = Color(1.6, 1.5, 0.5)
			else:
				btn.modulate = Color(1, 1, 1)
```

- [ ] **Step 6: Run the wider Team-Up suites to confirm no regression**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_team_up_panel_e2e.gd`, `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_team_up_panel_center_band.gd`
Expected: both PASS unchanged — locking still works the same for a payline/tally purpose, only the disabled/modulate rule for a same-round lock changed, which neither of these files asserts on.

- [ ] **Step 7: Commit**

```bash
git add combat/team_up_minigame.gd combat/ui/team_up_panel.gd tests/test_team_up_minigame_unlock.gd
git commit -m "feat(combat): let the player undo a Team-Up lock before the next spin"
```

---

### Task 4: Team-Up minigame — end spins early ("Bank Result")

**Files:**
- Modify: `combat/team_up_minigame.gd`
- Modify: `combat/ui/team_up_panel.gd`
- Test: Create `tests/test_team_up_minigame_end_early.gd`

**Interfaces:**
- Consumes: `TeamUpMinigame.spins_remaining: int`, `TeamUpMinigame.is_complete() -> bool` (both pre-existing).
- Produces: new public methods `TeamUpMinigame.can_end_early() -> bool` and `TeamUpMinigame.end_early() -> void`. Depends on Task 3's edits to `spin()` (this task adds one more line to the same function) — run after Task 3.

**Context:** Player request from the same playtest: let the player stop spinning and bank whatever the grid currently tallies to, instead of being forced to burn every remaining spin. `TeamUpMinigame.is_complete()` already gates the panel's resolve flow purely off `spins_remaining <= 0` — ending early just needs a way to zero that out on demand.

- [ ] **Step 1: Write the failing test**

Create `tests/test_team_up_minigame_end_early.gd`:

```gdscript
extends SceneTree

## Headless test: TeamUpMinigame.end_early() lets the player bank the current grid instead of
## burning every remaining spin. Disabled (can_end_early() == false) before the first spin and
## once the round is already complete. Player request, 2026-08-01 playtest follow-up.
## Run: Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_team_up_minigame_end_early.gd

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond: print("  ok: ", label)
	else: _failures += 1; push_error("FAIL: " + label); print("  FAIL: ", label)

func _initialize() -> void:
	var reel: TeamUpReel = TeamUpReel.new()
	var face: ReelFace = ReelFace.new()
	face.team_up_symbol = &"strike"
	reel.faces = [face]
	var reels: Array[TeamUpReel] = [reel, reel, reel]
	var game: TeamUpMinigame = TeamUpMinigame.new(reels, 3, 5)

	_check(not game.can_end_early(), "can't end early before any spin has happened")
	game.end_early()
	_check(not game.is_complete(), "end_early() before any spin is a safe no-op (spins_remaining was already 0-relative, nothing to bank)")

	var game2: TeamUpMinigame = TeamUpMinigame.new(reels, 3, 5)
	game2.spin()
	_check(game2.can_end_early(), "can end early once at least one spin has happened")
	_check(not game2.is_complete(), "round isn't complete yet (1 of 5 spins used, still mid-round)")

	game2.end_early()
	_check(game2.is_complete(), "end_early() completes the round")
	_check(game2.spins_remaining == 0, "end_early() zeroes spins_remaining (got %d)" % game2.spins_remaining)
	var tally: Dictionary = game2.tally()
	_check(tally.get("strike", 0) > 0, "tally() reflects whatever was on the grid when banked (got %d strike)" % tally.get("strike", 0))

	_check(not game2.can_end_early(), "can't end early again once the round is already complete")

	print(("TEAM UP MINIGAME END EARLY TEST PASSED" if _failures == 0 else "TEAM UP MINIGAME END EARLY TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_team_up_minigame_end_early.gd`
Expected: FAIL — `can_end_early`/`end_early` don't exist yet (method-not-found).

- [ ] **Step 3: Add `_has_spun` tracking and `end_early()`/`can_end_early()` to `TeamUpMinigame`**

In `combat/team_up_minigame.gd`, change the field block (as left by Task 3):

```gdscript
var reels: Array[TeamUpReel] = []
var grid: Array = []          # grid[col][row] = ReelFace
var locked: Array = []        # locked[col][row] = bool
var lock_tokens_remaining: int
var spins_remaining: int
var _cols: int
## Cells locked since the last spin() call — only these can be unlock()'d (player request,
## 2026-08-01): a lock committed by an EARLIER spin is permanently held (the Hold & Win point).
var _locked_this_round: Array[Vector2i] = []
```

to:

```gdscript
var reels: Array[TeamUpReel] = []
var grid: Array = []          # grid[col][row] = ReelFace
var locked: Array = []        # locked[col][row] = bool
var lock_tokens_remaining: int
var spins_remaining: int
var _cols: int
## Cells locked since the last spin() call — only these can be unlock()'d (player request,
## 2026-08-01): a lock committed by an EARLIER spin is permanently held (the Hold & Win point).
var _locked_this_round: Array[Vector2i] = []
## True once at least one spin() has actually drawn a grid — end_early() is meaningless (nothing to
## bank) before that.
var _has_spun: bool = false
```

Change `spin()` (as left by Task 3):

```gdscript
func spin() -> bool:
	if spins_remaining <= 0:
		return false
	for c: int in range(_cols):
		for r: int in range(ROWS):
			if not locked[c][r]:
				grid[c][r] = reels[c].spin()
	spins_remaining -= 1
	_locked_this_round.clear()
	return true
```

to:

```gdscript
func spin() -> bool:
	if spins_remaining <= 0:
		return false
	for c: int in range(_cols):
		for r: int in range(ROWS):
			if not locked[c][r]:
				grid[c][r] = reels[c].spin()
	spins_remaining -= 1
	_locked_this_round.clear()
	_has_spun = true
	return true
```

Add near `is_complete()`:

```gdscript
## True once the player CAN bank the current grid early — at least one spin has happened, and the
## round isn't already complete on its own (player request, 2026-08-01).
func can_end_early() -> bool:
	return _has_spun and not is_complete()

## Ends the round immediately, whatever the current grid tallies to. Safe to call when
## can_end_early() is false (a no-op if there's nothing to bank yet, or the round is already over).
func end_early() -> void:
	spins_remaining = 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_team_up_minigame_end_early.gd`
Expected: PASS, all checks `ok`.

- [ ] **Step 5: Add the "Bank Result" button to `TeamUpPanel`**

In `combat/ui/team_up_panel.gd`, add a field near `_spin_button`:

```gdscript
var _spin_button: Button
```

to:

```gdscript
var _spin_button: Button
var _end_early_button: Button
```

In `_ready()`, right after the `_spin_button` block:

```gdscript
	_spin_button = Button.new()
	_spin_button.text = "Spin"
	_spin_button.position = Vector2(380, 350)
	_spin_button.custom_minimum_size = Vector2(160, 44)
	_spin_button.pressed.connect(_on_spin_pressed)
	add_child(_spin_button)
```

add:

```gdscript
	_end_early_button = Button.new()
	_end_early_button.text = "Bank Result"
	_end_early_button.position = Vector2(380, 402)
	_end_early_button.custom_minimum_size = Vector2(160, 44)
	_end_early_button.tooltip_text = "Stop spinning now and take whatever the grid currently tallies to."
	_end_early_button.disabled = true
	_end_early_button.pressed.connect(_on_end_early_pressed)
	add_child(_end_early_button)
```

Add the handler near `_on_spin_pressed()`:

```gdscript
func _on_end_early_pressed() -> void:
	if _minigame == null or not _minigame.can_end_early():
		return
	_minigame.end_early()
	_clear_payline_preview()
	_refresh_grid()
	_resolve()
```

In `open_for()`, change:

```gdscript
	_continue_button.visible = false
	_tally_label.visible = false
	_spin_button.disabled = false
	_resolve_lines = []
```

to:

```gdscript
	_continue_button.visible = false
	_tally_label.visible = false
	_spin_button.disabled = false
	_end_early_button.disabled = true
	_resolve_lines = []
```

In `_refresh_grid()`, change:

```gdscript
	_spin_button.disabled = _minigame.is_complete()
	_status_label.text = "Spins left: %d   Lock tokens left: %d" % [_minigame.spins_remaining, _minigame.lock_tokens_remaining]
```

to:

```gdscript
	_spin_button.disabled = _minigame.is_complete()
	_end_early_button.disabled = not _minigame.can_end_early()
	_status_label.text = "Spins left: %d   Lock tokens left: %d" % [_minigame.spins_remaining, _minigame.lock_tokens_remaining]
```

- [ ] **Step 6: Run the wider Team-Up suites to confirm no regression**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_team_up_panel_e2e.gd`, `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_team_up_minigame_unlock.gd`
Expected: both PASS unchanged (a normal full-spins round never calls `end_early()`, and Task 3's unlock behavior is untouched by this task).

- [ ] **Step 7: Commit**

```bash
git add combat/team_up_minigame.gd combat/ui/team_up_panel.gd tests/test_team_up_minigame_end_early.gd
git commit -m "feat(combat): let the player bank a Team-Up round early instead of spinning it out"
```

---

### Task 5: Debug harness — "Test: Hollow Warden Fight" button on the Town Adventuring Board

**Files:**
- Modify: `world/ui/adventuring_board_panel.gd`
- Modify: `world/town_demo.gd`
- Test: Create `tests/test_town_demo_test_boss_fight.gd`

**Interfaces:**
- Consumes: `AdventuringBoardPanel` (existing pattern from `_endgame_level_up_button`/`endgame_level_up_pressed`), `CombatHandoff.begin_encounter(p, comps, inv, v, ids, encounter_id, scene_path, position, b, shop, floor)` (`world/combat_handoff.gd:111-125`, pre-existing signature, unchanged), `PartyInventory.JACKPOT_CAP: int` (`economy/resources/party_inventory.gd:14`, pre-existing), `town_demo.gd`'s existing `_pc_combatant`/`_companions`/`_bench`/`_party_inventory`/`_vault`/`_shop_stock`/`_pc`/`_fade_overlay`/`_handoff()` (all pre-existing fields/methods).
- Produces: new signal `AdventuringBoardPanel.test_boss_fight_pressed`, new method `AdventuringBoardPanel.press_test_boss_fight_for_test()`, new method `TownDemo._on_test_boss_fight_pressed()` — none consumed by any other task in this plan.

**Context:** Player request: a permanent debug button (same precedent as the already-shipped "Level Up to Endgame" button) that jumps straight into a real fight against the Hollow Warden trio, using whatever party is currently assembled, with the jackpot meter pre-maxed — cutting out the ~30 minutes of walking through dungeon floors 1-3 every time the player wants to test boss-fight content. It reuses the exact `&"DungeonFloor4Enemy"` encounter id the real dungeon floor uses, so a win here legitimately marks the boss defeated (Treasure Trove/Lost Cat become reachable on a real dungeon visit afterward too).

- [ ] **Step 1: Write the failing test**

Create `tests/test_town_demo_test_boss_fight.gd`, following `tests/test_town_demo_endgame_level_up.gd`'s
exact established pattern for driving a real board button inside the real `town_demo.tscn` (same
`_initialize()` + `await process_frame` shape, same `_on_board_opened([])` open call, same
`get_root().get_node("CombatHandoff")` fetch `tests/test_bench_survives_combat.gd` already uses):

```gdscript
extends SceneTree

## Headless test: the Town Adventuring Board's "Test: Hollow Warden Fight" debug button maxes the
## party's jackpot meter and populates CombatHandoff with a real Hollow Warden encounter, tagged
## with the same &"DungeonFloor4Enemy" id the real dungeon floor uses. Player request, 2026-08-01:
## skip the ~30-minute walk through dungeon floors 1-3 for boss-fight testing.

var _town: TownDemo
var _combat_handoff: Node
var _failures: int = 0

func _check(cond: bool, label: String) -> void:
	if cond: print("  ok: ", label)
	else: _failures += 1; push_error("FAIL: " + label); print("  FAIL: ", label)

func _initialize() -> void:
	var scene: PackedScene = load("res://world/town_demo.tscn")
	_town = scene.instantiate() as TownDemo
	root.add_child(_town)
	await process_frame
	await process_frame

	_combat_handoff = get_root().get_node("CombatHandoff")
	_combat_handoff.clear_pending()
	_town._party_inventory.jackpot_meter = 10  # below cap, so the fix is provably doing the work

	_town._on_board_opened([])   # real production entry point, same as the endgame-level-up test
	_check(_town._board_panel.visible, "the real Adventuring Board opens")
	_town._board_panel.press_test_boss_fight_for_test()

	_check(_combat_handoff.pc == _town._pc_combatant, "CombatHandoff.pc is the real, currently-assembled PC")
	_check(_combat_handoff.companions == _town._companions, "CombatHandoff.companions is the real, currently-assembled companion list")
	_check(_combat_handoff.enemy_ids == [&"hollow_warden", &"warden_acolyte_lesser_healer", &"warden_acolyte_lesser_curser"], "enemy_ids is the real Hollow Warden trio (got %s)" % [_combat_handoff.enemy_ids])
	_check(_combat_handoff.pending_encounter_id == &"DungeonFloor4Enemy", "tagged with the SAME encounter id the real dungeon floor uses, so a win marks the real boss defeated")
	_check(_combat_handoff.return_scene_path == "res://world/town_demo.tscn", "returns to town, not the dungeon")
	_check(_combat_handoff.has_return_position, "a return position is set")
	_check(_town._party_inventory.jackpot_meter == PartyInventory.JACKPOT_CAP, "jackpot meter is maxed (got %d)" % _town._party_inventory.jackpot_meter)
	_check(not _town._board_panel.visible, "the board closes after pressing the button")

	# Repeatable: pressing it again produces the identical handoff state, no crash.
	_town._on_board_opened([])
	_town._board_panel.press_test_boss_fight_for_test()
	_check(_combat_handoff.pending_encounter_id == &"DungeonFloor4Enemy", "second press: still tagged correctly")

	_town.free()
	print(("TOWN DEMO TEST BOSS FIGHT BUTTON TEST PASSED" if _failures == 0 else "TOWN DEMO TEST BOSS FIGHT BUTTON TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_town_demo_test_boss_fight.gd`
Expected: FAIL — `_on_test_boss_fight_pressed()`/`press_test_boss_fight_for_test()` don't exist yet (method-not-found).

- [ ] **Step 3: Add the button + signal to `AdventuringBoardPanel`**

In `world/ui/adventuring_board_panel.gd`, change:

```gdscript
signal endgame_level_up_pressed
```

to:

```gdscript
signal endgame_level_up_pressed
signal test_boss_fight_pressed
```

Change the field declaration:

```gdscript
var _endgame_level_up_button: Button
```

to:

```gdscript
var _endgame_level_up_button: Button
var _test_boss_fight_button: Button
```

In `open_for()` (rebuilds every open — every row button lives here, not in `_ready()`), right
after the existing block that builds `_endgame_level_up_button`:

```gdscript
	_endgame_level_up_button = Button.new()
	_endgame_level_up_button.text = "Level Up to Endgame"
	_endgame_level_up_button.position = Vector2(PAD, y)
	_endgame_level_up_button.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, ROW_H - 4.0)
	_endgame_level_up_button.pressed.connect(func() -> void: endgame_level_up_pressed.emit())
	add_child(_endgame_level_up_button)
	y += ROW_H + 6.0
```

add (matching the exact `y += ROW_H + 6.0` spacing convention every other row in this function
already uses):

```gdscript
	_test_boss_fight_button = Button.new()
	_test_boss_fight_button.text = "Test: Hollow Warden Fight"
	_test_boss_fight_button.position = Vector2(PAD, y)
	_test_boss_fight_button.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, ROW_H - 4.0)
	_test_boss_fight_button.tooltip_text = "Debug: launch a real fight vs. the Hollow Warden trio with the current party and a maxed jackpot meter, skipping the dungeon."
	_test_boss_fight_button.pressed.connect(func() -> void: test_boss_fight_pressed.emit())
	add_child(_test_boss_fight_button)
	y += ROW_H + 6.0
```

Add near `press_endgame_level_up_for_test()` (in the "Headless test hook" section at the bottom of
the file):

```gdscript
func press_test_boss_fight_for_test() -> void:
	_test_boss_fight_button.pressed.emit()
```

- [ ] **Step 4: Wire the handler in `world/town_demo.gd`**

In `_build_ui()` (or wherever `_board_panel` is constructed), find:

```gdscript
	_board_panel = AdventuringBoardPanel.new()
	_board_panel.position = Vector2(500, 150)
	_board_panel.party_selection_pressed.connect(_on_party_selection_pressed)
	_board_panel.endgame_level_up_pressed.connect(_on_endgame_level_up_pressed)
	_board_panel.entry_selected.connect(_on_board_entry_selected)
```

and change it to:

```gdscript
	_board_panel = AdventuringBoardPanel.new()
	_board_panel.position = Vector2(500, 150)
	_board_panel.party_selection_pressed.connect(_on_party_selection_pressed)
	_board_panel.endgame_level_up_pressed.connect(_on_endgame_level_up_pressed)
	_board_panel.test_boss_fight_pressed.connect(_on_test_boss_fight_pressed)
	_board_panel.entry_selected.connect(_on_board_entry_selected)
```

Add the handler near `_on_endgame_level_up_pressed()`:

```gdscript
## "Test: Hollow Warden Fight" (2026-08-01 debug harness) — a permanent testing aid, same
## precedent as "Level Up to Endgame". Takes the party EXACTLY as currently assembled (no forced
## roster changes, no auto-leveling), maxes the jackpot meter, and launches a real fight against
## the Hollow Warden trio tagged with the SAME &"DungeonFloor4Enemy" id the real dungeon floor
## uses — a win here legitimately marks the boss defeated (Treasure Trove/Lost Cat become
## reachable afterward too). Repeatable any number of times.
func _on_test_boss_fight_pressed() -> void:
	_board_panel.close()
	_pc.set_movement_paused(false)
	_party_inventory.jackpot_meter = PartyInventory.JACKPOT_CAP
	var floor4_ids: Array[StringName] = [&"hollow_warden", &"warden_acolyte_lesser_healer", &"warden_acolyte_lesser_curser"]
	_handoff().log_event("Debug: launching Hollow Warden test fight", &"combat")
	_handoff().begin_encounter(_pc_combatant, _companions, _party_inventory, _vault, floor4_ids,
		&"DungeonFloor4Enemy", "res://world/town_demo.tscn", _pc.global_position, _bench,
		_shop_stock, 0)
	await _fade_overlay.fade_out()
	get_tree().change_scene_to_file("res://combat/combat.tscn")
```

- [ ] **Step 5: Run test to verify it passes**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_town_demo_test_boss_fight.gd`
Expected: PASS, all checks `ok`.

- [ ] **Step 6: Run the wider Town/AdventuringBoard suites to confirm no regression**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_town_demo_endgame_level_up.gd`
Expected: PASS unchanged (a new button/signal doesn't affect the existing endgame button's behavior).

Note: `tests/test_adventuring_board_panel.gd` has one pre-existing, unrelated, already-documented
failure (present since 2026-07-14, confirmed identical across many prior sessions — see CLAUDE.md's
2026-07-14 status entry) not touched by this task; don't treat it as a regression from this change,
but do confirm no NEW failures appear in that file beyond the one already-known one.

- [ ] **Step 7: Commit**

```bash
git add world/ui/adventuring_board_panel.gd world/town_demo.gd tests/test_town_demo_test_boss_fight.gd
git commit -m "feat(world): add a debug button to jump straight into the Hollow Warden fight"
```

---

### Task 6: Final whole-branch review

Run the full headless test suite (every file in `tests/`) from `C:\bunnies\bunnies-main`:

```bash
for f in bunnies/tests/test_*.gd; do
  name=$(basename "$f")
  ./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script "res://tests/$name" > /tmp/out_$name.log 2>&1
  echo "$? $name"
done | grep -v '^0 '
```

Expected: no output (every file exits 0), aside from the already-documented intermittent
teardown-only SIGSEGV flake class (confirm clean on an immediate individual retry if one appears)
and the one pre-existing, unrelated `test_adventuring_board_panel.gd` failure noted in Task 5.

Then dispatch a final whole-branch code review (per `superpowers:subagent-driven-development`'s
own final-review step) covering all 5 tasks' diffs together, specifically checking for:
- Any place outside this plan's own tasks that hardcodes the old 0.15/0.20 Riposte Storm values
  (grep for `0.15` and `"+15%"`/`"+20%"` across `combat/` and `docs/` beyond the files this plan
  already touched).
- Whether `TeamUpPanel`'s new "Bank Result" button visually overlaps the existing "Show Paylines"
  button or the legend text at the `920x780` panel size (both buttons sit in the same row/column
  area — eyeball the constants).
- Whether `_on_test_boss_fight_pressed()`'s repeatability (pressing it again mid-session, or after
  already defeating the boss once) has any sharp edge CombatHandoff/dungeon_demo.gd assumes won't
  happen.

Fix anything the review finds, following this project's "no second fix wave beyond one round"
convention (per `superpowers:subagent-driven-development`), then report the final state to the
player: full suite status, and that a human playtest of these 5 changes (especially exercising the
new debug button, and re-testing Team-Up unlock/bank-early live) is the natural next step.
