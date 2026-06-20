# STUNNED Mechanic Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** A combatant that starts its turn with `current_initiative < −20` becomes STUNNED and must pass a d100 gate (01–50 lose the turn / 51–100 recover to a full turn); it can't be STUNNED two turns in a row.

**Architecture:** STUNNED is a per-turn `Combatant` condition (`stunned_this_turn` + `stunned_last_turn` anti-lock), recomputed at turn start from initiative — not a duration Effect. The orchestrator runs the gate at Main 1 (PC presses SPIN; NPC auto-rolls) using `TurnManager.roll_d100()`; fail ends the turn, recover hands off to the normal turn. v1 shows a plain dice readout (scrolling-reel visual is future, `ARCHITECTURE.md §9`).

**Tech Stack:** Godot 4.6.3-stable, GDScript (static-typed). Headless `SceneTree` tests under `tests/`.

## Global Constraints

- **Engine Godot 4.6.3-stable. GDScript only — never C#.** Static typing; signals past-tense; handlers `_on_<emitter>_<signal>`. (CLAUDE.md §2)
- **Per-combatant / N-vs-M only — NO 1v1 hardcoding.** STUNNED state, the anti-lock, and the gate are per-combatant; the design must hold when party sizes grow on both sides (party max 3 PCs, multiple enemies). (CLAUDE.md §7)
- **`[ASSUMPTION]` values:** `STUN_THRESHOLD = -20` (start-of-turn init below this → STUNNED); d100 split **01–50 lose / 51–100 recover**; anti-lock = immune if STUNNED last turn.
- STUNNED is a **per-turn condition**, not a duration `Effect`. The d100 reuses the shared `InitiativeReel` percentile.
- **v1 UI = simple dice readout** (log + a small label/banner). Scrolling reel-strips for the stun roll and per-character initiative, plus party-frame buff icons, are future (`ARCHITECTURE.md §9`) — do NOT build them.
- **Godot binary (NOT on PATH):** `/c/Godot_v4.6.3-stable_win64_console.exe`, from project root. New `class_name`? none here. Compile check / cache: `… --editor --quit`. Benign at exit: `ObjectDB leaked`/`resources still in use` — judge by `… TEST PASSED` + exit 0.
- Implements `docs/superpowers/specs/2026-06-20-stunned-mechanic-design.md`. Source of truth = `DESIGN.md`.

---

## File Structure
**Modified:** `combat/combatant.gd` (stun state + `evaluate_stun` + `on_end` flag-carry + `stun_check_passed`), `combat/turn_manager.gd` (`roll_d100`), `combat/combat.gd` (stun-gate turn-flow + dice readout), `combat/ui/combatant_panel.gd` (STUNNED in status line).
**New test:** `tests/test_stun.gd`.

---

## Task 1: `Combatant` STUNNED state + d100 helper + `TurnManager.roll_d100`

**Files:** Modify `combat/combatant.gd`, `combat/turn_manager.gd`; Test `tests/test_stun.gd`.

**Interfaces:**
- `Combatant`: `stunned_this_turn: bool`, `stunned_last_turn: bool`; `evaluate_stun(threshold: int) -> bool` (sets/returns `stunned_this_turn`); `static stun_check_passed(roll: int) -> bool`; `on_end()` carries the flag.
- `TurnManager.roll_d100() -> int`.

- [ ] **Step 1: Write the failing test** — create `tests/test_stun.gd`:

```gdscript
extends SceneTree

# Headless test for the STUNNED condition + anti-lock + d100 gate split (DESIGN spec 2026-06-20).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_stun.gd

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
	# Below threshold + not stunned last turn -> STUNNED.
	var a: Combatant = _mk(-25)
	_check(a.evaluate_stun(-20), "init -25 (< -20), not immune -> STUNNED")
	_check(a.stunned_this_turn, "stunned_this_turn set")

	# At/above threshold -> not stunned.
	var b: Combatant = _mk(-10)
	_check(not b.evaluate_stun(-20), "init -10 (>= -20) -> not stunned")
	var b2: Combatant = _mk(-20)
	_check(not b2.evaluate_stun(-20), "init -20 (not strictly below) -> not stunned")

	# Anti-lock: immune if stunned last turn, even at deep negative.
	var c: Combatant = _mk(-50)
	c.stunned_last_turn = true
	_check(not c.evaluate_stun(-20), "immune when stunned_last_turn (init -50)")

	# Lifecycle over 3 turns of deep-negative init: stun -> immune -> stun.
	var d: Combatant = _mk(-40)
	_check(d.evaluate_stun(-20), "turn 1: STUNNED")
	d.on_end()
	_check(d.stunned_last_turn and not d.stunned_this_turn, "turn 1 end: last=true, this reset")
	_check(not d.evaluate_stun(-20), "turn 2: immune (was stunned)")
	d.on_end()
	_check(not d.stunned_last_turn, "turn 2 end: last=false (this turn wasn't stunned)")
	_check(d.evaluate_stun(-20), "turn 3: STUNNED again (anti-lock cap = every other turn)")

	# d100 gate split: 01-50 lose (false), 51-100 recover (true).
	_check(not Combatant.stun_check_passed(1), "roll 1 -> lose")
	_check(not Combatant.stun_check_passed(50), "roll 50 -> lose (boundary)")
	_check(Combatant.stun_check_passed(51), "roll 51 -> recover (boundary)")
	_check(Combatant.stun_check_passed(100), "roll 100 -> recover")

	# TurnManager.roll_d100 in range 1..100.
	var tm: TurnManager = TurnManager.new()
	var out_of_range: int = 0
	for i: int in range(200):
		var r: int = tm.roll_d100()
		if r < 1 or r > 100: out_of_range += 1
	_check(out_of_range == 0, "roll_d100 in 1..100 (out: %d)" % out_of_range)

	print(("STUN TEST PASSED" if _failures == 0 else "STUN TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run to verify it fails** — `… --script res://tests/test_stun.gd` → FAIL (`evaluate_stun`/`stun_check_passed`/`roll_d100` undefined).

- [ ] **Step 3: Add STUNNED state to `combat/combatant.gd`** — after the sticky-wild fields, add:

```gdscript
## STUNNED is a per-turn condition (NOT a duration Effect): set at turn start when current_initiative
## is below the threshold and the combatant wasn't STUNNED last turn (anti-lock). DESIGN spec 2026-06-20.
var stunned_this_turn: bool = false
var stunned_last_turn: bool = false
```
Add methods (near the effects/turn hooks):
```gdscript
## Recomputes STUNNED for this turn: stunned when current_initiative < [param threshold] AND not
## immune (immune = STUNNED last turn — the anti-lock that prevents a permanent lockout). Returns
## the new stunned_this_turn. Call at turn start, after on_upkeep has recomputed initiative.
func evaluate_stun(threshold: int) -> bool:
	stunned_this_turn = current_initiative < threshold and not stunned_last_turn
	return stunned_this_turn

## The d100 "shake off" gate: a roll of 51+ recovers (takes the turn); 01–50 loses the turn.
static func stun_check_passed(roll: int) -> bool:
	return roll >= 51
```
In `on_end()`, append the anti-lock flag-carry (after the existing effect tick):
```gdscript
	stunned_last_turn = stunned_this_turn
	stunned_this_turn = false
```

- [ ] **Step 4: Add `roll_d100` to `combat/turn_manager.gd`** — after `roll_initiative`:
```gdscript
## Rolls a fresh d100 (percentile, 00=100, range 1–100) from the shared Initiative reels — used by
## the STUNNED "shake off" gate. (DESIGN spec 2026-06-20.)
func roll_d100() -> int:
	return InitiativeReel.roll_percentile(_initiative_tens, _initiative_ones)
```

- [ ] **Step 5: Run to verify it passes** — `STUN TEST PASSED`, exit 0.

- [ ] **Step 6: Regression** — run `test_combatant`, `test_turn_manager`, `test_crushing_slow`, `test_combat_loop` → green (new fields default false; `on_end`'s extra lines don't affect non-stunned combatants).

- [ ] **Step 7: Commit**
```bash
git add combat/combatant.gd combat/turn_manager.gd tests/test_stun.gd
git commit -m "feat(combat): STUNNED per-turn condition + anti-lock + d100 gate helper"
```

---

## Task 2: Orchestrator stun-gate turn flow + dice readout + panel display

**Files:** Modify `combat/combat.gd`, `combat/ui/combatant_panel.gd`; Test `tests/test_combat_loop.gd` (drive `evaluate_stun` in the loop).

**Interfaces:** Consumes Task 1. View/flow; verified by compile + full suite + play-test.

- [ ] **Step 1: Drive the lifecycle in the integration loop** — in `tests/test_combat_loop.gd._on_turn_started`, after `c.on_upkeep()` add `c.evaluate_stun(-20)` so the loop maintains the stun flags (combatants there have positive init → never stunned, so the fight is unchanged). Keep the rest. Run `test_combat_loop` → still green.

- [ ] **Step 2: Add a `STUN_THRESHOLD` const + `_awaiting_stun_check` state to `combat/combat.gd`** — near the other state vars:
```gdscript
const STUN_THRESHOLD: int = -20   # [ASSUMPTION] start-of-turn initiative below this → STUNNED
var _awaiting_stun_check: bool = false
```

- [ ] **Step 3: Branch the turn start on STUNNED** — in `_on_turn_started`, after `_phase_manager.start_turn()` (so `on_upkeep` has recomputed initiative) and after `_attacker` is set, evaluate stun and route:

Replace the tail of `_on_turn_started` (from `_end_turn_button.disabled = true` onward) with:
```gdscript
	_end_turn_button.disabled = true
	(_panels[c] as CombatantPanel).refresh_status()  # show/clear STUNNED tag
	if c.evaluate_stun(STUN_THRESHOLD):
		# STUNNED — gate the turn behind a d100 "shake off" check.
		_awaiting_stun_check = true
		_awaiting_player_spin = false
		_splice_button.disabled = true
		_ultimate_button.disabled = true
		_prepare_strips(c.turn_reels)  # show the reels (idle) behind the gate
		_log("  %s is STUNNED — %s a shake-off roll." % [c.display_name, "press SPIN for" if c.is_player else "rolling"])
		if c.is_player:
			_spin_button.disabled = false  # SPIN rolls the stun check (not an attack)
		else:
			_spin_button.disabled = true
			get_tree().create_timer(ENEMY_THINK_DELAY).timeout.connect(_resolve_stun_check, CONNECT_ONE_SHOT)
		return
	# Not stunned — normal turn.
	if c.is_player:
		_awaiting_player_spin = true
		_spin_button.disabled = false
	else:
		_awaiting_player_spin = false
		_spin_button.disabled = true
		get_tree().create_timer(ENEMY_THINK_DELAY).timeout.connect(_do_spin, CONNECT_ONE_SHOT)
	_refresh_main1_preview()
```

- [ ] **Step 4: SPIN routes to the stun check when gated** — at the top of `_on_spin_pressed`, before the existing body:
```gdscript
	if _awaiting_stun_check:
		_resolve_stun_check()
		return
```

- [ ] **Step 5: Add `_resolve_stun_check`** — the gate resolution (PC + NPC share it):
```gdscript
## Resolves the STUNNED shake-off gate: roll d100; 01–50 loses the turn, 51–100 recovers to a full
## normal turn. v1 shows a plain dice readout (scrolling-reel version is future — ARCHITECTURE §9).
func _resolve_stun_check() -> void:
	_awaiting_stun_check = false
	_spin_button.disabled = true
	var roll: int = _turn_manager.roll_d100()
	if Combatant.stun_check_passed(roll):
		_log("  %s shook off the stun (rolled %d) — free to act!" % [_attacker.display_name, roll])
		_payline_banner.text = "STUN CHECK %d → SHAKE OFF" % roll
		# Recover into a normal turn (stunned_this_turn stays true only as the anti-lock record).
		if _attacker.is_player:
			_awaiting_player_spin = true
			_spin_button.disabled = false
		else:
			get_tree().create_timer(ENEMY_THINK_DELAY).timeout.connect(_do_spin, CONNECT_ONE_SHOT)
		_refresh_main1_preview()
	else:
		_log("  %s is STUNNED (rolled %d) — loses the turn!" % [_attacker.display_name, roll])
		_payline_banner.text = "STUN CHECK %d → TURN LOST" % roll
		# Lose the turn: skip Combat, run Main 2 → End → advance. (No proceed_to_combat.)
		_phase_manager.resume_after_combat()
```

- [ ] **Step 6: Show STUNNED in the panel status** — in `combat/ui/combatant_panel.gd._refresh_status` (or `refresh_status`), prepend a STUNNED tag when the combatant is stunned. After building the effect parts, before setting the text:
```gdscript
	if _combatant.stunned_this_turn:
		parts.insert(0, "[color=#e0e040]STUNNED[/color]")
```
(Uses the bbcode RichTextLabel already in place; STUNNED shows yellow/orange like a debuff.)

- [ ] **Step 7: Compile check + full suite**
Run `… --editor --quit` (exit 0). Then run every suite (stats, initiative_tiebreak, might_damage, stun, payline_library, payline_resolver, payline_grid, payline_rewards, effect, main_phase_plan, resource_pool, crushing_slow, reel_splice, ultimate_sticky_wild, turn_manager, combatant, phase_manager, bonus_meter, action_reel, combat_loop) — all print `… TEST PASSED`.

- [ ] **Step 8: Commit**
```bash
git add combat/combat.gd combat/ui/combatant_panel.gd tests/test_combat_loop.gd
git commit -m "feat(combat): STUNNED turn-gate (PC SPIN / NPC auto), dice readout + panel tag"
```

---

## Final verification
- [ ] **Whole suite green** (20 suites). **Compile clean.**
- [ ] **Human play-test (CLAUDE.md §5):** stack SLOW on Martin until his initiative drops below −20; on his next turn he's STUNNED, presses SPIN to roll the d100 — 01–50 loses the turn, 51–100 lets him play fully. Confirm he can't be STUNNED two turns in a row. (To reach −20 you need ~2 enemy Crushing crits stacking Slow; the rat may need more HP/turns to set that up — flag if hard to reproduce.)

## Self-review notes (author)
- **Spec coverage:** §2 trigger/flow/anti-lock → Task 1 (`evaluate_stun`, flag-carry) + Task 2 (gate flow). §3 modeling → Task 1 state. §4 turn-flow integration → Task 2 Steps 3–5. §5 UI → Task 2 (dice readout + panel tag; scrolling-reel deferred). §6 tests → Task 1 `test_stun` + regression.
- **N-vs-M:** all stun state is per-`Combatant`; `_resolve_stun_check`/`evaluate_stun` operate on `_attacker`/any combatant — no 1v1 assumption. `_allies`/multiple enemies unaffected.
- **Type consistency:** `evaluate_stun(threshold)`, `stun_check_passed(roll)`, `stunned_this_turn`/`stunned_last_turn`, `roll_d100()`, `_awaiting_stun_check`, `STUN_THRESHOLD` — consistent across tasks/tests.
- **Flow safety:** lose-turn calls `resume_after_combat()` without `proceed_to_combat()` (Combat phase skipped — correct for a lost turn); `on_end` runs at END and carries the anti-lock flag + ticks effects.
- **Out of scope (spec §8):** scrolling-reel visuals, party-frame icons/tooltips, cleanses — none built.
