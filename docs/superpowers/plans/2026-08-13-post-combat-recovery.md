# Post-Combat Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On a win, pressing "Continue" restores each PC a stat-scaled partial percentage of
HP/Stamina/Mana, resolves each PC's Bonus Meter via the existing floor/full-carry rule, and shows
the player what changed before the scene transitions away from combat.

**Architecture:** A new pure `Combatant` method computes and applies the HP/Stamina/Mana recovery
(mirroring the existing `heal()`/`ResourcePool.refund()` primitives) and returns the actual amounts
gained. `combat/combat.gd`'s existing `_resolve_handoff_continue()` (shared by the real Continue
button and its test hook) calls this per PC plus the already-existing-but-never-called
`BonusMeter.resolve_post_combat()`, and appends a summary to the result overlay's label. The real
button handler adds a readable pause before the fade/scene-change so the player can actually see it.

**Tech Stack:** Godot 4.6 GDScript, headless `SceneTree`-based tests.

**Spec:** `docs/superpowers/specs/2026-08-13-accuracy-stat-and-post-combat-flow-design.md` (§3 only;
§1/§2 and §4 are separate plans).

## Global Constraints

- Trigger point is pressing "Continue" on the VICTORY overlay — NOT the instant combat ends
  (spec §3).
- HP recovery: `5% + 1% per 3 Vigor` of max HP, uncapped. Stamina/Mana recovery: `5% + 1% per 2
  Focus` of max, uncapped, applied only to whichever rail(s) a combatant's class actually uses
  (spec §3).
- Recovered amounts round up (`ceili`), project-wide convention (`[[round-up-damage-healing]]`).
- Bonus Meter: wire up the existing, currently-uncalled `BonusMeter.resolve_post_combat()` — no new
  Bonus Meter mechanic (spec §3).
- Every nonzero change needs a visible on-screen marker before the scene transitions away from
  combat — exact animation is not specified, only that it must be visible, not silently applied
  off-screen (spec §3).
- This plan only touches the WIN path. The LOSS path (full restore, effect clearing, meter reset to
  floor, world-state reset) is a separate plan (`docs/superpowers/plans/2026-08-13-defeat-handling.md`)
  — do not add any loss-branch behavior here.
- Run the Godot binary from `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe` with
  `--headless --path .` from the repo root (`C:\bunnies\bunnies-main\bunnies`) for every test.

---

## File Map

- **Modify:** `combat/combatant.gd` — new constants + `apply_post_combat_recovery() -> Dictionary`.
- **Modify:** `combat/combat.gd` — `_resolve_handoff_continue()` gains a win-only recovery step
  that updates the result label; `_on_continue_after_handoff_pressed()` adds a readable pause
  before the fade.
- **Create (test):** `tests/test_post_combat_recovery.gd` (pure `Combatant`-level unit test).
- **Create (test):** `tests/test_combat_win_recovery.gd` (full `combat.tscn` handoff-harness
  integration test, mirroring `tests/test_combat_handoff_entry.gd`'s pattern).

---

### Task 1: Add `Combatant.apply_post_combat_recovery()`

**Files:**
- Modify: `combat/combatant.gd` (new consts near `FOCUS_REGEN_PER_POINT`, new method near `heal()`/
  `restore_to_full()`)
- Test: `tests/test_post_combat_recovery.gd` (new)

**Interfaces:**
- Consumes: `Combatant.effective_stats()` (existing), `Combatant.heal(amount: int) -> int`
  (existing, `combatant.gd:409`), `ResourcePool.refund(cost: Dictionary) -> void` (existing,
  `combat/resource_pool.gd:43`).
- Produces: `Combatant.apply_post_combat_recovery() -> Dictionary` returning
  `{"hp": int, "stamina": int, "mana": int}` — the ACTUAL amounts gained after clamping (not the
  intended pre-clamp amount), for Task 2's on-screen summary to read. No-op (all zeros) on a dead
  combatant.

- [ ] **Step 1: Write the failing test**

Create `tests/test_post_combat_recovery.gd`:

```gdscript
extends SceneTree

# Headless test: Combatant.apply_post_combat_recovery() — the post-combat HP/Stamina/Mana partial
# recovery (2026-08-13 post-combat-flow spec §3). Base 5% of max, plus a stat-scaled bonus: HP +1%
# per 3 Vigor, Stamina/Mana +1% per 2 Focus, both uncapped. Returns actual (post-clamp) amounts
# gained. Pure Combatant-level test — no scene/combat.tscn needed.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_post_combat_recovery.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _mk(max_hp: int, hp: int, max_stamina: int, stamina: int, max_mana: int, mana: int, vigor: int, focus: int) -> Combatant:
	var c: Combatant = Combatant.new()
	c.max_hp = max_hp
	c.hp = hp
	c.resource_pool = ResourcePool.new()
	c.resource_pool.max_stamina = max_stamina
	c.resource_pool.stamina = stamina
	c.resource_pool.max_mana = max_mana
	c.resource_pool.mana = mana
	var s: Stats = Stats.new()
	s.vigor = vigor
	s.focus = focus
	c.base_stats = s
	return c

func _initialize() -> void:
	# Baseline (Vigor 0, Focus 0): HP recovers exactly 5% of max, rounded up. Stamina rail only
	# (max_mana 0), also 5%.
	var c1: Combatant = _mk(100, 50, 20, 5, 0, 0, 0, 0)
	var g1: Dictionary = c1.apply_post_combat_recovery()
	_check(g1.hp == 5, "Vigor 0 -> HP recovers ceil(100*0.05)=5 (got %d)" % g1.hp)
	_check(c1.hp == 55, "HP actually applied: 50 -> 55 (got %d)" % c1.hp)
	_check(g1.stamina == 1, "Focus 0 -> Stamina recovers ceil(20*0.05)=1 (got %d)" % g1.stamina)
	_check(c1.resource_pool.stamina == 6, "Stamina actually applied: 5 -> 6 (got %d)" % c1.resource_pool.stamina)
	_check(g1.mana == 0, "max_mana 0 -> mana recovery is 0 (unused rail, no phantom recovery)")

	# Vigor 6 -> +1%/3 * 6 = +2%, total 7% of max HP.
	var c2: Combatant = _mk(100, 50, 20, 5, 0, 0, 6, 0)
	var g2: Dictionary = c2.apply_post_combat_recovery()
	_check(g2.hp == 7, "Vigor 6 -> HP recovers ceil(100*0.07)=7 (got %d)" % g2.hp)

	# Focus 4 -> +1%/2 * 4 = +2%, total 7% of max Stamina.
	var c3: Combatant = _mk(100, 50, 20, 5, 0, 0, 0, 4)
	var g3: Dictionary = c3.apply_post_combat_recovery()
	_check(g3.stamina == 2, "Focus 4 -> Stamina recovers ceil(20*0.07)=2 (got %d)" % g3.stamina)

	# Mana-only class (max_stamina 0): mana recovers, stamina reports 0 (unused rail).
	var c4: Combatant = _mk(100, 50, 0, 0, 15, 5, 0, 0)
	var g4: Dictionary = c4.apply_post_combat_recovery()
	_check(g4.mana == 1, "Focus 0, mana-only -> Mana recovers ceil(15*0.05)=1 (got %d)" % g4.mana)
	_check(g4.stamina == 0, "max_stamina 0 -> stamina recovery is 0 (unused rail)")

	# Clamped at max: already-full HP/Stamina/Mana gain 0 (not negative, not over max).
	var c5: Combatant = _mk(100, 100, 20, 20, 0, 0, 0, 0)
	var g5: Dictionary = c5.apply_post_combat_recovery()
	_check(g5.hp == 0, "already-full HP gains 0, not negative")
	_check(c5.hp == 100, "already-full HP stays clamped at max")
	_check(g5.stamina == 0, "already-full Stamina gains 0")

	# Uncapped: very high Vigor/Focus still scales linearly, no ceiling (player's explicit call).
	var c6: Combatant = _mk(1000, 0, 100, 0, 0, 0, 300, 0)
	var g6: Dictionary = c6.apply_post_combat_recovery()
	# Vigor 300 -> +1%/3*300 = +100%, total 105% of max -> clamped to max (1000), gain = 1000.
	_check(g6.hp == 1000, "Vigor 300 -> recovery pct exceeds 100%%, clamps at max_hp (got %d)" % g6.hp)

	# Dead combatant: no-op, all zeros.
	var c7: Combatant = _mk(100, 0, 20, 5, 0, 0, 4, 4)
	var g7: Dictionary = c7.apply_post_combat_recovery()
	_check(g7.hp == 0 and g7.stamina == 0 and g7.mana == 0, "dead combatant (hp 0) -> no recovery at all")

	print(("POST COMBAT RECOVERY TEST PASSED" if _failures == 0 else "POST COMBAT RECOVERY TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_post_combat_recovery.gd`
Expected: FAIL — `Invalid call. Nonexistent function 'apply_post_combat_recovery'`.

- [ ] **Step 3: Add the constants and method in `combat/combatant.gd`**

Add these constants immediately after the existing `FOCUS_REGEN_PER_POINT` const (around line 26):

```gdscript
## Post-combat recovery (2026-08-13 post-combat-flow spec §3): base 5% of max, uncapped stat-scaled
## bonus. HP scales with Vigor, Stamina/Mana scale with Focus — the same two stats that already
## govern those pools' max/regen (Vigor -> HP, Focus -> resource pool).
const RECOVERY_BASE_PCT: float = 0.05
const RECOVERY_PCT_PER_HP_STEP: float = 0.01
const VIGOR_PER_RECOVERY_STEP: int = 3
const RECOVERY_PCT_PER_RESOURCE_STEP: float = 0.01
const FOCUS_PER_RECOVERY_STEP: int = 2
```

Add this method immediately after `restore_to_full()`:

```gdscript
## Applies the post-combat partial recovery (2026-08-13 post-combat-flow spec §3, triggered by
## combat.gd on pressing "Continue" after a WIN — never on a loss, see the defeat-handling plan for
## that path). HP recovers RECOVERY_BASE_PCT + RECOVERY_PCT_PER_HP_STEP per VIGOR_PER_RECOVERY_STEP
## points of Vigor, of max HP. Stamina/Mana recover RECOVERY_BASE_PCT +
## RECOVERY_PCT_PER_RESOURCE_STEP per FOCUS_PER_RECOVERY_STEP points of Focus, of max, applied only
## to whichever rail(s) this combatant's class actually uses (same base>0 gating apply_stats()
## already uses for Focus's regen bonus). Both percentages are deliberately uncapped — [ASSUMPTION]
## gear-stat budgets are unlikely to reach a level where this matters, and a build that does invest
## heavily in Vigor/Focus should be rewarded, not throttled (player's explicit call). Returns the
## ACTUAL (post-clamp) amounts gained, for on-screen feedback. No-op (all zeros) if dead.
func apply_post_combat_recovery() -> Dictionary:
	var result: Dictionary = {"hp": 0, "stamina": 0, "mana": 0}
	if not is_alive():
		return result

	var s: Stats = effective_stats()

	var hp_pct: float = RECOVERY_BASE_PCT + (s.vigor / VIGOR_PER_RECOVERY_STEP) * RECOVERY_PCT_PER_HP_STEP
	var hp_before: int = hp
	heal(ceili(max_hp * hp_pct))
	result.hp = hp - hp_before

	if resource_pool != null:
		var resource_pct: float = RECOVERY_BASE_PCT + (s.focus / FOCUS_PER_RECOVERY_STEP) * RECOVERY_PCT_PER_RESOURCE_STEP
		if resource_pool.max_stamina > 0:
			var stamina_before: int = resource_pool.stamina
			resource_pool.refund({&"stamina": ceili(resource_pool.max_stamina * resource_pct)})
			result.stamina = resource_pool.stamina - stamina_before
		if resource_pool.max_mana > 0:
			var mana_before: int = resource_pool.mana
			resource_pool.refund({&"mana": ceili(resource_pool.max_mana * resource_pct)})
			result.mana = resource_pool.mana - mana_before

	return result
```

- [ ] **Step 4: Run the test again to confirm it passes**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_post_combat_recovery.gd`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add combat/combatant.gd tests/test_post_combat_recovery.gd
git commit -m "feat(combat): add Combatant.apply_post_combat_recovery"
```

---

### Task 2: Wire recovery + Bonus Meter resolution into `_resolve_handoff_continue()` (win only)

**Files:**
- Modify: `combat/combat.gd` (`_resolve_handoff_continue()`, around line 2655)
- Test: `tests/test_combat_win_recovery.gd` (new)

**Interfaces:**
- Consumes: `Combatant.apply_post_combat_recovery()` (Task 1),
  `BonusMeter.resolve_post_combat()` (existing, `combat/bonus_meter.gd:86`, previously uncalled),
  `Combat._pcs: Array[Combatant]` (existing field), `Combat._overlay.get_node("ResultLabel")`
  (existing node path, same one `_on_combat_ended()` already writes XP/Amber/loot lines to).
- Produces: no new public interface — `_resolve_handoff_continue()`'s behavior changes (win path
  only) to apply recovery and append a summary to the already-visible result label before it
  returns the destination path.

- [ ] **Step 1: Write the failing test**

Create `tests/test_combat_win_recovery.gd`, following `tests/test_combat_handoff_entry.gd`'s exact
harness pattern (handoff → instantiate `combat.tscn` → `press_continue_for_test()`):

```gdscript
extends SceneTree

# Headless test: pressing Continue on a WIN applies post-combat recovery to every PC and appends a
# summary to the result label (2026-08-13 post-combat-flow spec §3). Mirrors
# tests/test_combat_handoff_entry.gd's exact handoff-harness pattern.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combat_win_recovery.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()

	# --- WIN case: PC damaged + meter partially charged before Continue is pressed ---
	var pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	pc.hp = pc.max_hp - 50  # damaged, so recovery is actually observable
	pc.bonus_meter.value = pc.bonus_meter.floor + 2  # above floor, below cap -> resolve_post_combat drops it to floor
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	var enemy_ids: Array[StringName] = [&"rat"]
	var return_path: String = "res://world/overworld_demo.tscn"
	CombatHandoff.begin_encounter(pc, [], inv, vault, enemy_ids, &"OverworldRat", return_path, Vector2(1.0, 2.0))

	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame

	var hp_before: int = pc.hp
	var meter_floor: int = pc.bonus_meter.floor
	inst._last_result_won = true
	inst.press_continue_for_test()

	_check(pc.hp > hp_before, "WIN + Continue recovered some HP (before %d, after %d)" % [hp_before, pc.hp])
	_check(pc.bonus_meter.value == meter_floor, "WIN + Continue resolved the Bonus Meter to its floor (got %d, floor %d)" % [pc.bonus_meter.value, meter_floor])

	var label: Label = inst._overlay.get_node("ResultLabel")
	_check(label.text.contains("HP"), "result label mentions the HP recovery (got: %s)" % label.text)

	inst.queue_free()
	await process_frame
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

	# --- LOSS case (regression): recovery must NOT apply on a loss — that's the defeat-handling plan's job ---
	var loss_pc: Combatant = ClassLibrary.make(&"ranger").build_combatant(true)
	loss_pc.hp = loss_pc.max_hp - 50
	CombatHandoff.begin_encounter(loss_pc, [], inv, vault, enemy_ids, &"OverworldFerret", return_path, Vector2(1.0, 2.0))

	var loss_scene: PackedScene = load("res://combat/combat.tscn")
	var loss_inst: Combat = loss_scene.instantiate()
	get_root().add_child(loss_inst)
	await process_frame
	await process_frame

	var loss_hp_before: int = loss_pc.hp
	loss_inst._last_result_won = false
	loss_inst.press_continue_for_test()
	_check(loss_pc.hp == loss_hp_before, "LOSS + Continue does NOT apply win-side recovery (hp unchanged, got %d, was %d)" % [loss_pc.hp, loss_hp_before])

	loss_inst.queue_free()
	await process_frame
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

	print(("COMBAT WIN RECOVERY TEST PASSED" if _failures == 0 else "COMBAT WIN RECOVERY TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_combat_win_recovery.gd`
Expected: FAIL — HP/meter unchanged after `press_continue_for_test()` (recovery not wired yet).

- [ ] **Step 3: Add the recovery step in `combat/combat.gd`**

Find `_resolve_handoff_continue()` (doc comment starts `## Shared by
_on_continue_after_handoff_pressed() and press_continue_for_test()`). Change:

```gdscript
func _resolve_handoff_continue() -> String:
	var handoff: Node = _handoff()
	if _last_result_won:
		handoff.mark_defeated(handoff.pending_encounter_id)
```

to:

```gdscript
func _resolve_handoff_continue() -> String:
	var handoff: Node = _handoff()
	if _last_result_won:
		handoff.mark_defeated(handoff.pending_encounter_id)
		_apply_post_combat_recovery()
```

Then add this new method right above `_resolve_handoff_continue()`:

```gdscript
## Applies post-combat recovery to every PC on a WIN (2026-08-13 post-combat-flow spec §3): each
## PC's HP/Stamina/Mana partially recover (Combatant.apply_post_combat_recovery()) and their Bonus
## Meter resolves via the existing floor/full-carry rule (BonusMeter.resolve_post_combat(),
## DESIGN.md §4.9 — previously coded but never actually called anywhere in the real combat flow).
## Appends a per-PC "+N HP, +N Stamina, +N Mana" summary line to the already-visible result label so
## the player sees what changed before the scene transitions away (never on a loss — see the
## defeat-handling plan for that path).
func _apply_post_combat_recovery() -> void:
	var label: Label = _overlay.get_node("ResultLabel")
	for c: Combatant in _pcs:
		if not c.is_alive():
			continue
		var gains: Dictionary = c.apply_post_combat_recovery()
		if c.bonus_meter != null:
			c.bonus_meter.resolve_post_combat()
		var parts: Array[String] = []
		if gains.hp > 0:
			parts.append("+%d HP" % gains.hp)
		if gains.stamina > 0:
			parts.append("+%d Stamina" % gains.stamina)
		if gains.mana > 0:
			parts.append("+%d Mana" % gains.mana)
		if not parts.is_empty():
			label.text += "\n%s: %s" % [c.display_name, ", ".join(parts)]
```

- [ ] **Step 4: Run the test again to confirm it passes**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_combat_win_recovery.gd`
Expected: PASS

- [ ] **Step 5: Run `tests/test_combat_handoff_entry.gd` as a regression check**

This is the test that already exercises `press_continue_for_test()` for both win and loss paths —
confirm this plan's change didn't break its existing assertions (it doesn't check HP/meter values,
only handoff-state fields, so it should be unaffected, but it's the closest existing coverage of
this exact code path).

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_combat_handoff_entry.gd`
Expected: PASS unmodified

- [ ] **Step 6: Commit**

```bash
git add combat/combat.gd tests/test_combat_win_recovery.gd
git commit -m "feat(combat): wire post-combat recovery + Bonus Meter resolution into WIN Continue"
```

---

### Task 3: Add a readable pause before the fade on a win

**Files:**
- Modify: `combat/combat.gd` (`_on_continue_after_handoff_pressed()`, around line 2675)

**Interfaces:**
- Consumes: `_resolve_handoff_continue()` (Task 2, now applies recovery and updates the label as a
  side effect before returning the path), `FadeOverlay.fade_out()` (existing,
  `world/ui/fade_overlay.gd:30`).
- Produces: no new interface — reorders `_on_continue_after_handoff_pressed()` so the label update
  happens and is visible BEFORE the fade starts, instead of the fade starting immediately.

- [ ] **Step 1: Reorder `_on_continue_after_handoff_pressed()` in `combat/combat.gd`**

This is a real behavior change worth being deliberate about: today, `fade_out()` runs FIRST (the
screen goes black over the still-unmodified result label), and `_resolve_handoff_continue()` runs
SECOND, immediately before the scene swap — so its effects were never visible anyway. Now that
`_resolve_handoff_continue()` updates the label with recovery text, that ordering must flip: resolve
first (so the label is updated while still visible), pause so the player can read it, THEN fade out.

Add a named constant near the top of `combat/combat.gd` (alongside its other tuning constants — find
an existing `const` near the top of the file, e.g. near `ENEMY_XP_REWARD`, and add):

```gdscript
## How long the recovery summary stays on screen (readable) before the Continue-on-win transition
## fades out (2026-08-13 post-combat-flow spec §3). [ASSUMPTION] tune by playtest.
const RECOVERY_DISPLAY_PAUSE: float = 1.5
```

Change `_on_continue_after_handoff_pressed()` from:

```gdscript
func _on_continue_after_handoff_pressed() -> void:
	await _handoff_fade_overlay.fade_out()
	get_tree().change_scene_to_file(_resolve_handoff_continue())
```

to:

```gdscript
func _on_continue_after_handoff_pressed() -> void:
	var was_win: bool = _last_result_won
	var return_path: String = _resolve_handoff_continue()
	if was_win:
		await get_tree().create_timer(RECOVERY_DISPLAY_PAUSE).timeout
	await _handoff_fade_overlay.fade_out()
	get_tree().change_scene_to_file(return_path)
```

(`was_win` is captured before `_resolve_handoff_continue()` runs, in case anything inside it ever
changes `_last_result_won` in the future — defensive, matches this file's existing style of
capturing values into locals before a call that could plausibly mutate state, e.g.
`_resolve_handoff_continue()`'s own `return_path` local capture before `clear_combat_data()`.)

- [ ] **Step 2: Manual verification (this step cannot be headlessly tested — timer/fade ordering is
  a real-time visual behavior)**

Per CLAUDE.md's "you cannot press play and judge whether the spin is fun" boundary — this
specific change (does the label visibly update and stay readable before the screen fades) needs a
human to actually run the game and win a fight to confirm. Flag this explicitly at hand-off: ask
the player to play through one win and confirm the recovery summary is legible before the fade
starts, and that `RECOVERY_DISPLAY_PAUSE` (1.5s) feels like enough (or too much) time to read a
short line.

- [ ] **Step 3: Run `tests/test_combat_win_recovery.gd` and `tests/test_combat_handoff_entry.gd`
  once more as a final regression check**

Neither test calls `_on_continue_after_handoff_pressed()` directly (both use
`press_continue_for_test()`, which is unaffected by this task — it still calls
`_resolve_handoff_continue()` directly with no timer/fade involved), so both should already pass
unmodified. Re-run them anyway as a final gate for this plan.

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_combat_win_recovery.gd`
Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_combat_handoff_entry.gd`
Expected: both PASS

- [ ] **Step 4: Commit**

```bash
git add combat/combat.gd
git commit -m "feat(combat): pause on the recovery summary before fading out on a win"
```

---

## Plan Self-Review

**Spec coverage:** §3's every requirement is covered — Continue-press trigger point (Task 2),
Bonus Meter wiring (Task 2), HP/Stamina/Mana formula (Task 1), on-screen feedback (Task 2's label
append + Task 3's readable pause). §1/§2 (accuracy stat) and §4 (defeat handling) are separate
plans, correctly out of scope here.

**Placeholder scan:** no TBD/TODO; every step has real code or a real shell command. Task 3 Step 2
is an explicit human-verification step, not a placeholder — it's flagged because this specific
behavior (real-time visual pacing) is outside what a headless test can meaningfully assert, per
this project's own established "cannot press play and judge" boundary (CLAUDE.md §5).

**Type consistency:** `Combatant.apply_post_combat_recovery() -> Dictionary` (Task 1) returns keys
`hp`/`stamina`/`mana`, read by the exact same key names in Task 2's `_apply_post_combat_recovery()`
in `combat.gd`. `RECOVERY_DISPLAY_PAUSE` (Task 3) is defined once and used once.
